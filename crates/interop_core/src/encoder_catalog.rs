use crate::{CoreError, CoreResult, scrcpy::VideoEncoder};
use interop_adb::Client;
use std::{collections::VecDeque, future::Future, sync::Arc};
use tokio::sync::{Mutex, OnceCell};

/// Encoder enumeration belongs to the actual ADB connection, not its address
/// or remembered device record. Never reuse it after transport replacement.
#[derive(Default)]
pub(crate) struct EncoderCatalog {
    entries: Mutex<VecDeque<Entry>>,
}

struct Entry {
    client: Client,
    encoders: Arc<OnceCell<Vec<VideoEncoder>>>,
}

impl EncoderCatalog {
    /// Read successful enumeration for this connection without starting or
    /// waiting for a probe. Unknown, failed, and in-progress probes are `None`.
    pub(crate) async fn peek(&self, client: &Client) -> CoreResult<Option<Vec<VideoEncoder>>> {
        if client.is_closed() {
            return Err(CoreError::new("disconnected", "设备连接已结束。"));
        }
        let encoders = {
            let entries = self.entries.lock().await;
            entries
                .iter()
                .find(|entry| entry.client.same_connection(client))
                .map(|entry| entry.encoders.clone())
        };
        let result = encoders.and_then(|encoders| encoders.get().cloned());
        if client.is_closed() {
            return Err(CoreError::new("disconnected", "设备连接已结束。"));
        }
        Ok(result)
    }

    pub(crate) async fn get<F, R>(&self, client: &Client, load: F) -> CoreResult<Vec<VideoEncoder>>
    where
        F: FnOnce() -> R,
        R: Future<Output = CoreResult<Vec<VideoEncoder>>>,
    {
        if client.is_closed() {
            return Err(CoreError::new("disconnected", "设备连接已结束。"));
        }
        let encoders = {
            let mut entries = self.entries.lock().await;
            entries.retain(|entry| !entry.client.is_closed());
            let entry = entries
                .iter()
                .position(|entry| entry.client.same_connection(client))
                .and_then(|index| entries.remove(index))
                .unwrap_or_else(|| Entry {
                    client: client.clone(),
                    encoders: Arc::new(OnceCell::new()),
                });
            let encoders = entry.encoders.clone();
            entries.push_back(entry);
            // A metadata optimization must not retain an unbounded number of
            // transport handles. Eviction never closes a live connection.
            while entries.len() > 32 {
                entries.pop_front();
            }
            encoders
        };
        // Do not hold the catalog lock over ADB I/O. Concurrent requests on this
        // connection share one probe; a failed/cancelled initializer can retry.
        let result = encoders.get_or_try_init(load).await?;
        if client.is_closed() {
            return Err(CoreError::new("disconnected", "设备连接已结束。"));
        }
        Ok(result.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{DeviceInfo, protocol};
    use std::{
        collections::HashSet,
        sync::atomic::{AtomicUsize, Ordering},
        time::Duration,
    };

    fn connection() -> (Client, tokio::io::DuplexStream) {
        let (transport, peer) = tokio::io::duplex(1024);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::same-remembered-phone".into(),
                features: HashSet::new(),
            },
        )
        .unwrap();
        (client, peer)
    }

    #[tokio::test]
    async fn encoder_catalog_reuses_sequential_and_cloned_connection_calls() {
        let catalog = EncoderCatalog::default();
        let (client, _peer) = connection();
        assert!(catalog.peek(&client).await.unwrap().is_none());
        assert!(catalog.entries.lock().await.is_empty());
        let calls = AtomicUsize::new(0);
        for connection in [client.clone(), client.clone(), client.clone()] {
            catalog
                .get(&connection, || async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Ok(Vec::new())
                })
                .await
                .unwrap();
            assert!(catalog.peek(&connection).await.unwrap().unwrap().is_empty());
        }
        client.close();
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "one actual catalog enumeration per connection"
        );
    }

    #[tokio::test]
    async fn encoder_catalog_coalesces_concurrent_callers() {
        let catalog = EncoderCatalog::default();
        let (client, _peer) = connection();
        let calls = AtomicUsize::new(0);
        let query = || {
            catalog.get(&client, || async {
                calls.fetch_add(1, Ordering::SeqCst);
                tokio::time::sleep(Duration::from_millis(10)).await;
                Ok(Vec::new())
            })
        };
        let (a, b, c, d) = tokio::join!(query(), query(), query(), query());
        for result in [a, b, c, d] {
            result.unwrap();
        }
        client.close();
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "concurrent sessions share enumeration"
        );
    }

    #[tokio::test]
    async fn encoder_catalog_does_not_cross_transport_replacement_or_closed_connections() {
        let catalog = EncoderCatalog::default();
        let (old, _old_peer) = connection();
        let (next, _next_peer) = connection();
        let calls = AtomicUsize::new(0);
        for client in [&old, &next] {
            assert!(catalog.peek(client).await.unwrap().is_none());
            catalog
                .get(client, || async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Ok(Vec::new())
                })
                .await
                .unwrap();
            assert!(catalog.peek(client).await.unwrap().unwrap().is_empty());
        }
        old.close();
        assert_eq!(catalog.peek(&old).await.err().unwrap().code, "disconnected");
        let result = catalog
            .get(&old, || async {
                panic!("closed transport must not enumerate")
            })
            .await;
        next.close();
        assert_eq!(result.err().unwrap().code, "disconnected");
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn encoder_catalog_failed_or_cancelled_loading_can_retry() {
        let catalog = EncoderCatalog::default();
        let (client, _peer) = connection();
        let calls = AtomicUsize::new(0);
        let failed = catalog
            .get(&client, || async {
                calls.fetch_add(1, Ordering::SeqCst);
                Err(CoreError::new("encoder_probe", "fixture failure"))
            })
            .await;
        assert_eq!(failed.err().unwrap().code, "encoder_probe");
        assert!(catalog.peek(&client).await.unwrap().is_none());
        {
            let (started, ready) = tokio::sync::oneshot::channel();
            let loading = catalog.get(&client, || async {
                calls.fetch_add(1, Ordering::SeqCst);
                started.send(()).unwrap();
                std::future::pending().await
            });
            tokio::pin!(loading);
            tokio::select! {
                _ = ready => {},
                _ = &mut loading => panic!("fixture probe must stay pending"),
            }
            assert!(
                tokio::time::timeout(Duration::from_millis(100), catalog.peek(&client))
                    .await
                    .expect("peek must not wait for an in-progress probe")
                    .unwrap()
                    .is_none()
            );
        }
        assert!(catalog.peek(&client).await.unwrap().is_none());
        catalog
            .get(&client, || async {
                calls.fetch_add(1, Ordering::SeqCst);
                Ok(Vec::new())
            })
            .await
            .unwrap();
        client.close();
        assert_eq!(calls.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn encoder_catalog_peek_rechecks_connection_after_waiting_for_catalog() {
        let catalog = EncoderCatalog::default();
        let (client, _peer) = connection();
        let entries = catalog.entries.lock().await;
        let peek = catalog.peek(&client);
        tokio::pin!(peek);
        std::future::poll_fn(|cx| {
            assert!(peek.as_mut().poll(cx).is_pending());
            std::task::Poll::Ready(())
        })
        .await;
        client.close();
        drop(entries);
        assert_eq!(peek.await.err().unwrap().code, "disconnected");
    }

    #[tokio::test]
    async fn encoder_catalog_discards_result_if_transport_closes_during_probe() {
        let catalog = EncoderCatalog::default();
        let (client, _peer) = connection();
        let result = catalog
            .get(&client, || async {
                client.close();
                Ok(Vec::new())
            })
            .await;
        assert_eq!(result.err().unwrap().code, "disconnected");
    }

    #[tokio::test]
    async fn encoder_catalog_eviction_does_not_close_connections() {
        let catalog = EncoderCatalog::default();
        let connections: Vec<_> = (0..33).map(|_| connection()).collect();
        let calls = AtomicUsize::new(0);
        for (client, _) in &connections {
            catalog
                .get(client, || async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Ok(Vec::new())
                })
                .await
                .unwrap();
        }
        catalog
            .get(&connections[0].0, || async {
                calls.fetch_add(1, Ordering::SeqCst);
                Ok(Vec::new())
            })
            .await
            .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 34);
        for (client, _) in &connections {
            assert!(
                !client.is_closed(),
                "catalog eviction is not device disconnect"
            );
            client.close();
        }
    }
}
