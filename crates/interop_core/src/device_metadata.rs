//! Optional device information never holds transport admission open. Jobs are
//! bounded and may publish only to the exact connection that requested them.
use crate::Runtime;
use interop_adb::{Client, OperationOptions};
#[cfg(test)]
use serde_json::json;
use std::{
    sync::{Arc, Weak},
    time::Duration,
};
use tokio::{sync::mpsc, task::JoinSet};
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub(crate) struct Request {
    pub(crate) id: String,
    pub(crate) client: Client,
}

pub(crate) fn spawn(
    runtime: &Arc<Runtime>,
    mut requests: mpsc::Receiver<Request>,
    lifetime: CancellationToken,
) {
    let runtime = Arc::downgrade(runtime);
    tokio::spawn(async move {
        let mut jobs = JoinSet::new();
        let mut refresh_tick = tokio::time::interval(Duration::from_secs(30));
        refresh_tick.tick().await;
        let mut pending = std::collections::VecDeque::<Request>::new();
        loop {
            tokio::select! {
                biased;
                _ = lifetime.cancelled() => break,
                _ = refresh_tick.tick(), if pending.is_empty() => {
                    let Some(owner) = runtime.upgrade() else { break; };
                    let clients = owner.connections.lock().await;
                    pending.extend(clients.iter().filter(|(_, client)| !client.is_closed())
                        .map(|(id,client)| Request { id:id.clone(), client:client.clone() }));
                }
                _ = std::future::ready(()), if !pending.is_empty() && jobs.len() < 4 => {
                    if let Some(request) = pending.pop_front() {
                        jobs.spawn(refresh(runtime.clone(), request));
                    }
                }
                request = requests.recv(), if jobs.len() < 4 => {
                    let Some(request) = request else { break; };
                    let runtime = runtime.clone();
                    jobs.spawn(refresh(runtime, request));
                }
                _ = jobs.join_next(), if !jobs.is_empty() => {}
            }
        }
        // Runtime owns the only sender. Its release aborts any queued or
        // in-flight optional requests instead of keeping device owners alive.
    });
}

async fn refresh(runtime: Weak<Runtime>, request: Request) {
    if runtime.strong_count() == 0 {
        return;
    }
    let facts = request
        .client
        .shell(
            "dumpsys battery",
            64 * 1024,
            OperationOptions {
                timeout: Duration::from_secs(3),
                ..Default::default()
            },
        )
        .await
        .ok()
        .filter(|output| !output.exit_code.is_some_and(|code| code != 0))
        .and_then(|output| {
            let text = std::str::from_utf8(&output.stdout).ok()?;
            let facts = crate::device_details::battery_data(text);
            facts["level"].as_u64()?;
            Some(facts)
        });
    let Some(runtime) = runtime.upgrade() else {
        return;
    };
    {
        // Match connection publication's lock order. A delayed reply from a
        // disconnected or replaced transport cannot update its replacement.
        let mut store = runtime.store.write().await;
        let connections = runtime.connections.lock().await;
        if !connections
            .get(&request.id)
            .is_some_and(|client| !client.is_closed() && client.same_connection(&request.client))
        {
            return;
        }
        let Some(device) = store
            .devices
            .iter_mut()
            .find(|device| device.id == request.id && device.status == "connected")
        else {
            return;
        };
        if facts.is_none()
            && device.battery.is_none()
            && device.charging.is_none()
            && device.battery_updated_at.is_none()
        {
            return;
        }
        // A failed refresh revokes the last live sample immediately, while the
        // connection fence above prevents an old failure clearing a new sample.
        device.battery = facts
            .as_ref()
            .and_then(|facts| facts["level"].as_u64())
            .map(|level| level as u32);
        device.charging = facts.as_ref().and_then(|facts| facts["charging"].as_bool());
        device.battery_updated_at = facts.as_ref().map(|_| crate::model::now());
        runtime.emit(
            "device.changed",
            Some(&request.id),
            crate::device::project_device(device, &connections),
        );
    }
    let _ = runtime.persist().await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    use tokio::{io::DuplexStream, sync::oneshot};

    fn connection() -> (Client, DuplexStream) {
        let (transport, peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::features=shell_v2;\0".into(),
                features: ["shell_v2".into()].into(),
            },
        )
        .unwrap();
        (client, peer)
    }

    #[tokio::test]
    async fn late_battery_cannot_update_a_replaced_or_offline_device() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let added = runtime
            .add_device(&json!({"address":"127.0.0.1", "port":5555, "transport":"tcp"}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        for replace in [true, false] {
            let (client, mut peer) = connection();
            runtime
                .connections
                .lock()
                .await
                .insert(id.clone(), client.clone());
            {
                let mut store = runtime.store.write().await;
                let device = store
                    .devices
                    .iter_mut()
                    .find(|device| device.id == id)
                    .unwrap();
                device.status = "connected".into();
                device.battery = Some(42);
                device.observation_wanted = false;
            }
            let (started, observed) = oneshot::channel();
            let (release, ready) = oneshot::channel();
            let server = tokio::spawn(async move {
                let frame = Frame::read(&mut peer, 4096, true).await.unwrap();
                assert_eq!(frame.command, protocol::OPEN);
                assert!(String::from_utf8_lossy(&frame.payload).contains("dumpsys battery"));
                Frame::new(protocol::OKAY, 100, frame.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
                started.send(()).unwrap();
                ready.await.unwrap();
                let text = b"level: 99\nscale: 100\n";
                let mut reply = vec![1];
                reply.extend_from_slice(&(text.len() as u32).to_le_bytes());
                reply.extend_from_slice(text);
                reply.extend_from_slice(&[3, 1, 0, 0, 0, 0]);
                Frame::new(protocol::WRTE, 100, frame.arg0, reply)
                    .write(&mut peer)
                    .await
                    .unwrap();
                // Keep this transport alive until refresh has checked ownership.
                while Frame::read(&mut peer, 4096, true).await.is_ok() {}
            });
            let refresh = tokio::spawn(super::refresh(
                Arc::downgrade(&runtime),
                Request {
                    id: id.clone(),
                    client,
                },
            ));
            observed.await.unwrap();
            let (_replacement, _replacement_peer) = if replace {
                let (replacement, peer) = connection();
                runtime
                    .connections
                    .lock()
                    .await
                    .insert(id.clone(), replacement.clone());
                (Some(replacement), Some(peer))
            } else {
                runtime
                    .store
                    .write()
                    .await
                    .devices
                    .iter_mut()
                    .find(|device| device.id == id)
                    .unwrap()
                    .status = "offline".into();
                (None, None)
            };
            release.send(()).unwrap();
            tokio::time::timeout(Duration::from_secs(1), refresh)
                .await
                .unwrap()
                .unwrap();
            assert_eq!(runtime.device(&id).await.unwrap().battery, Some(42));
            runtime.connections.lock().await.remove(&id);
            server.abort();
        }
        runtime.stop_all().await;
    }

    #[tokio::test]
    async fn failed_refresh_revokes_previously_live_battery() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let added = runtime
            .add_device(&json!({"address":"127.0.0.1", "port":5555, "transport":"tcp"}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        for exit in [0, 1] {
            let (client, mut peer) = connection();
            runtime
                .connections
                .lock()
                .await
                .insert(id.clone(), client.clone());
            {
                let mut store = runtime.store.write().await;
                let device = store.devices.iter_mut().find(|d| d.id == id).unwrap();
                device.status = "connected".into();
                device.battery = Some(42);
                device.charging = Some(true);
                device.battery_updated_at = Some(crate::model::now());
                device.observation_wanted = false;
            }
            let server = tokio::spawn(async move {
                let frame = Frame::read(&mut peer, 4096, true).await.unwrap();
                Frame::new(protocol::OKAY, 100, frame.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
                Frame::new(protocol::WRTE, 100, frame.arg0, [3, 1, 0, 0, 0, exit])
                    .write(&mut peer)
                    .await
                    .unwrap();
                while Frame::read(&mut peer, 4096, true).await.is_ok() {}
            });
            super::refresh(
                Arc::downgrade(&runtime),
                Request {
                    id: id.clone(),
                    client,
                },
            )
            .await;
            let device = runtime.device(&id).await.unwrap();
            assert_eq!(
                device.battery, None,
                "failed/missing query cannot remain live"
            );
            assert_eq!(device.charging, None);
            assert_eq!(device.battery_updated_at, None);
            runtime.connections.lock().await.remove(&id);
            server.abort();
        }
        runtime.stop_all().await;
    }

    #[tokio::test]
    async fn runtime_release_aborts_running_and_queued_queries() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let mut peers = Vec::new();
        for _ in 0..5 {
            let (client, peer) = connection();
            assert!(
                runtime
                    .metadata_updates
                    .try_send(Request {
                        id: "device".into(),
                        client
                    })
                    .is_ok()
            );
            peers.push(peer);
        }
        // Saturate all four workers with peers that never finish the shell.
        for peer in &mut peers[..4] {
            let frame = tokio::time::timeout(Duration::from_secs(1), Frame::read(peer, 4096, true))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(frame.command, protocol::OPEN);
        }
        let weak = Arc::downgrade(&runtime);
        drop(runtime);
        tokio::time::timeout(Duration::from_secs(1), async {
            while weak.strong_count() != 0 {
                tokio::task::yield_now().await;
            }
            for peer in &mut peers {
                while let Ok(frame) = Frame::read(peer, 4096, true).await {
                    assert_eq!(
                        frame.command,
                        protocol::CLSE,
                        "no queued query may start after Runtime release"
                    );
                }
            }
        })
        .await
        .expect("Runtime release must abort optional work, including its queued clients");
    }
}
