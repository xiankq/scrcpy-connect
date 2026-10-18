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

    pub(crate) fn is_retiring(&self, id: &str) -> bool {
        self.retiring
            .lock()
            .expect("retirement registry poisoned")
            .contains(id)
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

#[cfg(test)]
mod tests {
    use super::*;

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
