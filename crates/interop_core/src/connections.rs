//! Owns admitted transports, per-device transitions and in-flight retirement.
//! Slow teardown is scheduled independently; the transition still fences any
//! replacement of that same device until its old activities finish cleanup.
use interop_adb::Client;
use std::{
    collections::{HashMap, HashSet},
    future::Future,
    sync::{Arc, Mutex as StdMutex},
};
use tokio::sync::{Mutex, MutexGuard, OwnedMutexGuard};

#[derive(Default)]
pub(crate) struct ConnectionOwner {
    clients: Mutex<HashMap<String, Client>>,
    transitions: Mutex<HashMap<String, Arc<Mutex<bool>>>>,
    retiring: Arc<StdMutex<HashSet<String>>>,
}

impl ConnectionOwner {
    // Callers that atomically update persisted device state acquire the store
    // before this guard. The owner alone manages transition/task bookkeeping.
    pub(crate) async fn lock(&self) -> MutexGuard<'_, HashMap<String, Client>> {
        self.clients.lock().await
    }

    pub(crate) async fn client(&self, id: &str) -> Option<Client> {
        self.clients
            .lock()
            .await
            .get(id)
            .filter(|client| !client.is_closed())
            .cloned()
    }

    pub(crate) async fn transition(&self, id: &str) -> OwnedMutexGuard<bool> {
        let gate = {
            let mut gates = self.transitions.lock().await;
            gates.retain(|_, gate| {
                Arc::strong_count(gate) > 1 || gate.try_lock().map_or(true, |pending| *pending)
            });
            gates.entry(id.into()).or_default().clone()
        };
        gate.lock_owned().await
    }

    pub(crate) async fn pending_retirements(&self) -> Vec<String> {
        let mut ids = self
            .clients
            .lock()
            .await
            .iter()
            .filter(|(_, client)| client.is_closed())
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        // Dropped callers leave a pending flag, so a later monitor tick can
        // resume cleanup even when no transport/reconnect remains.
        ids.extend(
            self.transitions
                .lock()
                .await
                .iter()
                .filter(|(_, gate)| {
                    Arc::strong_count(gate) == 1 && gate.try_lock().is_ok_and(|pending| *pending)
                })
                .map(|(id, _)| id.clone()),
        );
        ids.sort();
        ids.dedup();
        ids
    }

    pub(crate) fn schedule_retirement(
        &self,
        id: String,
        cleanup: impl Future<Output = ()> + Send + 'static,
    ) -> bool {
        if !self
            .retiring
            .lock()
            .expect("retirement registry poisoned")
            .insert(id.clone())
        {
            return false;
        }
        let permit = RetirementPermit {
            id,
            registry: self.retiring.clone(),
        };
        tokio::spawn(async move {
            let _permit = permit;
            cleanup.await;
        });
        true
    }
}

struct RetirementPermit {
    id: String,
    registry: Arc<StdMutex<HashSet<String>>>,
}

impl Drop for RetirementPermit {
    fn drop(&mut self) {
        self.registry
            .lock()
            .expect("retirement registry poisoned")
            .remove(&self.id);
    }
}

/// An application coordinator owns only its pending automatic attempts.
/// Admitted transports retain their independent ConnectionOwner lifetime.
pub(crate) struct ReconnectLease {
    pub(crate) id: String,
    pub(crate) cancellation: tokio_util::sync::CancellationToken,
}

impl Drop for ReconnectLease {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

impl crate::Runtime {
    pub(crate) async fn reconnect_owner_command(
        &self,
        params: &serde_json::Value,
    ) -> crate::CoreResult<serde_json::Value> {
        let id = crate::model::required(params, "ownerId")?;
        if id.is_empty() || id.len() > 200 || id.contains('\0') {
            return Err(crate::CoreError::new(
                "invalid_argument",
                "重连协调器标识无效。",
            ));
        }
        let active = params["active"]
            .as_bool()
            .ok_or_else(|| crate::CoreError::new("invalid_argument", "缺少协调器租约状态。"))?;
        let mut owner = self.reconnect_owner.lock().await;
        if active {
            if owner.as_ref().is_none_or(|lease| lease.id != id) {
                *owner = Some(ReconnectLease {
                    id: id.into(),
                    cancellation: tokio_util::sync::CancellationToken::new(),
                });
            }
        } else if owner.as_ref().is_some_and(|lease| lease.id == id) {
            *owner = None;
        }
        Ok(
            serde_json::json!({"ownerId":id,"active":owner.as_ref().is_some_and(|lease| lease.id == id)}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn automatic_attempts_require_a_live_owner_and_cannot_replay_a_persisted_stop() {
        use crate::{ConnectionPolicy, Runtime};
        use interop_adb::protocol::{self, Frame};
        use serde_json::json;
        use std::time::Duration;
        let directory = tempfile::tempdir().unwrap();
        let mut policy = ConnectionPolicy::standalone();
        policy.monitor_interval_ms = 25;
        let runtime = Runtime::initialize_with_connection_policy(directory.path(), policy)
            .await
            .unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let receipt = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":port}))
            .await
            .unwrap();
        let id = receipt["deviceId"].as_str().unwrap().to_owned();
        runtime.store.write().await.devices[0].auto_reconnect = true;
        runtime.persist().await.unwrap();
        assert!(
            tokio::time::timeout(Duration::from_millis(100), listener.accept())
                .await
                .is_err(),
            "native liveness monitoring must not schedule an automatic connection"
        );
        runtime
            .invoke(
                "devices.reconnect.owner",
                json!({"ownerId":"first","active":true}),
            )
            .await
            .unwrap();
        let first = runtime
            .reconnect_owner
            .lock()
            .await
            .as_ref()
            .unwrap()
            .cancellation
            .clone();
        let executor = runtime.clone();
        let device = id.clone();
        let pending = tokio::spawn(async move {
            executor.invoke("devices.connect", json!({"deviceId":device,"automatic":true,"ownerId":"first","attemptId":"first-attempt"})).await
        });
        let (mut peer, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            Frame::read(&mut peer, 4096, true).await.unwrap().command,
            protocol::CNXN
        );
        runtime
            .invoke(
                "devices.reconnect.owner",
                json!({"ownerId":"first","active":false}),
            )
            .await
            .unwrap();
        assert!(first.is_cancelled());
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(2), pending)
                .await
                .unwrap()
                .unwrap()
                .unwrap_err()
                .code,
            "cancelled"
        );
        assert!(
            runtime.device(&id).await.unwrap().auto_reconnect,
            "detaching a Dart retry owner cancels an attempt, not persistent user intent"
        );
        assert!(
            !runtime
                .device_operations
                .lock()
                .await
                .contains_key("first-attempt")
        );
        assert_eq!(
            runtime
                .invoke(
                    "devices.connect",
                    json!({"deviceId":id,"automatic":true,"ownerId":"first"})
                )
                .await
                .unwrap_err()
                .code,
            "cancelled"
        );
        runtime
            .invoke(
                "devices.reconnect.owner",
                json!({"ownerId":"second","active":true}),
            )
            .await
            .unwrap();
        runtime
            .invoke(
                "devices.reconnect.owner",
                json!({"ownerId":"first","active":false}),
            )
            .await
            .unwrap();
        assert_eq!(
            runtime.reconnect_owner.lock().await.as_ref().unwrap().id,
            "second"
        );
        runtime
            .invoke("devices.disconnect", json!({"deviceId":id}))
            .await
            .unwrap();
        assert_eq!(
            runtime
                .invoke(
                    "devices.connect",
                    json!({"deviceId":id,"automatic":true,"ownerId":"second"})
                )
                .await
                .unwrap_err()
                .code,
            "cancelled"
        );
        let saved: serde_json::Value = serde_json::from_slice(
            &tokio::fs::read(directory.path().join("devices.json"))
                .await
                .unwrap(),
        )
        .unwrap();
        assert_eq!(saved["devices"][0]["autoReconnect"], false);
        assert!(
            tokio::time::timeout(Duration::from_millis(50), listener.accept())
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn retirement_deduplicates_only_the_device_still_in_flight() {
        let owner = ConnectionOwner::default();
        let release = Arc::new(tokio::sync::Notify::new());
        let waiting = release.clone();
        assert!(owner.schedule_retirement("slow".into(), async move {
            waiting.notified().await;
        }));
        assert!(!owner.schedule_retirement("slow".into(), async {
            panic!("duplicate cleanup ran");
        }));
        let (finished, completion) = tokio::sync::oneshot::channel();
        assert!(owner.schedule_retirement("fast".into(), async move {
            let _ = finished.send(());
        }));
        tokio::time::timeout(std::time::Duration::from_secs(1), completion)
            .await
            .unwrap()
            .unwrap();
        assert!(!owner.schedule_retirement("slow".into(), async {
            panic!("slow cleanup still owns its device");
        }));
        release.notify_one();
    }
}
