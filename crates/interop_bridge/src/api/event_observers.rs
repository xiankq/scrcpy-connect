//! One bounded, independently cancellable owner for each Dart event observer.
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, MutexGuard},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::sync::broadcast;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

#[derive(Clone)]
pub(super) struct EventObservers(Arc<Registry>);

struct Registry {
    entries: Mutex<HashMap<Uuid, Observer>>,
    capacity: usize,
    reservation_ttl: Duration,
}

struct Observer {
    token: CancellationToken,
    created: Instant,
    listening: bool,
}

/// Keeps an active slot occupied until its event loop has actually stopped,
/// including when the containing future is dropped or aborted.
pub(super) struct ObserverLease {
    registry: Arc<Registry>,
    id: Uuid,
    pub(super) token: CancellationToken,
}

impl Registry {
    fn entries(&self) -> MutexGuard<'_, HashMap<Uuid, Observer>> {
        self.entries.lock().unwrap_or_else(|e| e.into_inner())
    }
}

impl EventObservers {
    pub(super) fn bounded() -> Self {
        Self::new(64, Duration::from_secs(60))
    }
    fn new(capacity: usize, reservation_ttl: Duration) -> Self {
        Self(Arc::new(Registry {
            entries: Mutex::new(HashMap::new()),
            capacity,
            reservation_ttl,
        }))
    }

    pub(super) fn open(&self) -> Result<Uuid, String> {
        let mut entries = self.0.entries();
        // A dead engine may disappear between open_events and events. Such
        // reservations have no task to wake, so reclaim them lazily and boundedly.
        entries
            .retain(|_, entry| entry.listening || entry.created.elapsed() < self.0.reservation_ttl);
        if entries.len() >= self.0.capacity {
            return Err("事件订阅数量已达上限，请先关闭已有订阅。".into());
        }
        // Never replace an existing owner, even in the unlikely UUID collision.
        let id = loop {
            let id = Uuid::new_v4();
            if !entries.contains_key(&id) {
                break id;
            }
        };
        entries.insert(
            id,
            Observer {
                token: CancellationToken::new(),
                created: Instant::now(),
                listening: false,
            },
        );
        Ok(id)
    }

    pub(super) fn listen(&self, id: Uuid) -> Result<Option<ObserverLease>, String> {
        let mut entries = self.0.entries();
        let Some(entry) = entries.get_mut(&id) else {
            // Cancellation before the async* consumer starts is a normal close.
            // Unknown/expired IDs must never allocate an implicit observer.
            return Ok(None);
        };
        if entry.listening {
            return Err("此事件订阅已经开始监听。".into());
        }
        if entry.created.elapsed() >= self.0.reservation_ttl {
            entries.remove(&id);
            return Ok(None);
        }
        entry.listening = true;
        Ok(Some(ObserverLease {
            registry: self.0.clone(),
            id,
            token: entry.token.clone(),
        }))
    }

    pub(super) fn cancel(&self, id: Uuid) {
        let mut entries = self.0.entries();
        if let Some(entry) = entries.get(&id) {
            entry.token.cancel();
            if !entry.listening {
                entries.remove(&id);
            }
        }
    }
}

impl Drop for ObserverLease {
    fn drop(&mut self) {
        // IDs are never reused by this registry while an entry exists. A live
        // lease is its sole listener, and cancellation cannot remove its slot.
        self.registry.entries().remove(&self.id);
    }
}

pub(super) async fn pump_events(
    mut receiver: broadcast::Receiver<Value>,
    token: &CancellationToken,
    idle_timeout: Duration,
    mut send: impl FnMut(String) -> bool,
) {
    loop {
        let message = tokio::select! {
            biased;
            _ = token.cancelled() => break,
            message = tokio::time::timeout(idle_timeout, receiver.recv()) => message,
        };
        let event = match message {
            Ok(Ok(event)) => event,
            Ok(Err(broadcast::error::RecvError::Lagged(_))) => {
                // Drop retained events before the caller loads a snapshot.
                // Events arriving while it handles the marker remain queued.
                receiver = receiver.resubscribe();
                json!({"type":"state.resync","data":{}})
            }
            Ok(Err(broadcast::error::RecvError::Closed)) => break,
            Err(_) => {
                // Only transport liveness, never a business/media receipt. The
                // send failure detects a Dart engine that vanished while idle.
                let timestamp = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis();
                json!({"type":"runtime.heartbeat","deviceId":null,"data":{},"timestamp":timestamp})
            }
        };
        // Cancellation also wins if it arrives after recv became ready.
        if token.is_cancelled() || !send(event.to_string()) {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn registry(capacity: usize) -> EventObservers {
        EventObservers::new(capacity, Duration::from_secs(60))
    }

    #[test]
    fn cancellation_before_listen_closes_and_reclaims_without_reopening() {
        let observers = registry(1);
        let id = observers.open().unwrap();
        observers.cancel(id);
        observers.cancel(id);
        assert!(observers.listen(id).unwrap().is_none());
        let next = observers.open().unwrap();
        assert_ne!(next, id);
        observers.cancel(id);
        assert!(
            !observers
                .listen(next)
                .unwrap()
                .unwrap()
                .token
                .is_cancelled()
        );
    }

    #[tokio::test]
    async fn cancel_wakes_idle_loop_without_closing_another_observer() {
        let observers = registry(2);
        let first = observers.open().unwrap();
        let second = observers.open().unwrap();
        let lease = observers.listen(first).unwrap().unwrap();
        let other = observers.listen(second).unwrap().unwrap();
        let (_sender, receiver) = broadcast::channel(2);
        let task = tokio::spawn(async move {
            pump_events(receiver, &lease.token, Duration::from_secs(60), |_| {
                panic!("cancellation must not need an event or heartbeat")
            })
            .await;
        });
        observers.cancel(first);
        tokio::time::timeout(Duration::from_millis(200), task)
            .await
            .unwrap()
            .unwrap();
        assert!(!other.token.is_cancelled());
        assert_eq!(observers.0.entries().len(), 1);
    }

    #[tokio::test]
    async fn active_cancelled_slots_remain_bounded_until_loop_drop() {
        let observers = registry(1);
        let id = observers.open().unwrap();
        assert!(observers.open().is_err());
        let lease = observers.listen(id).unwrap().unwrap();
        assert!(observers.listen(id).is_err());
        observers.cancel(id);
        assert!(lease.token.is_cancelled());
        assert!(observers.open().is_err());
        let task = tokio::spawn(async move {
            let _lease = lease;
            std::future::pending::<()>().await;
        });
        task.abort();
        assert!(task.await.unwrap_err().is_cancelled());
        assert!(observers.open().is_ok());
    }

    #[test]
    fn abandoned_reservations_expire_without_expiring_live_owners() {
        let observers = EventObservers::new(2, Duration::from_millis(1));
        let idle = observers.open().unwrap();
        let live = observers.open().unwrap();
        let lease = observers.listen(live).unwrap().unwrap();
        // Manipulate the monotonic creation stamp rather than sleeping.
        for entry in observers.0.entries().values_mut() {
            entry.created = Instant::now() - Duration::from_secs(1);
        }
        assert!(observers.open().is_ok());
        assert!(observers.listen(idle).unwrap().is_none());
        assert!(!lease.token.is_cancelled());
        assert_eq!(observers.0.entries().len(), 2);
    }

    #[tokio::test]
    async fn heartbeat_detects_dead_sink_and_reclaims_only_its_lease() {
        let observers = registry(1);
        let id = observers.open().unwrap();
        let lease = observers.listen(id).unwrap().unwrap();
        let (_sender, receiver) = broadcast::channel(2);
        let mut sent = Vec::new();
        tokio::time::timeout(Duration::from_millis(200), async {
            pump_events(receiver, &lease.token, Duration::from_millis(1), |event| {
                sent.push(serde_json::from_str::<Value>(&event).unwrap());
                false
            })
            .await;
        })
        .await
        .unwrap();
        drop(lease);
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0]["type"], "runtime.heartbeat");
        assert_eq!(sent[0]["data"], json!({}));
        assert!(observers.0.entries().is_empty());
    }

    #[tokio::test]
    async fn lagged_observer_discards_old_events_and_keeps_new_events_isolated() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let observers = registry(2);
            let paused_id = observers.open().unwrap();
            let active_id = observers.open().unwrap();
            let paused = observers.listen(paused_id).unwrap().unwrap();
            let active = observers.listen(active_id).unwrap().unwrap();
            let active_token = active.token.clone();
            let (sender, paused_receiver) = broadcast::channel(256);
            let active_receiver = sender.subscribe();
            let (active_output, mut active_events) = tokio::sync::mpsc::unbounded_channel();
            let active_task = tokio::spawn(async move {
                pump_events(
                    active_receiver,
                    &active.token,
                    Duration::from_secs(60),
                    |event| {
                        active_output
                            .send(serde_json::from_str::<Value>(&event).unwrap())
                            .is_ok()
                    },
                )
                .await;
            });

            // Keep one observer consuming while the other accumulates more
            // than the real Core broadcast capacity without being polled.
            for sequence in 1..=300 {
                sender
                    .send(json!({"type":"device.changed","sequence":sequence,"data":{}}))
                    .unwrap();
                let event = active_events.recv().await.unwrap();
                assert_eq!(event["sequence"], sequence);
            }

            let mut resumed_events = Vec::new();
            pump_events(
                paused_receiver,
                &paused.token,
                Duration::from_secs(60),
                |event| {
                    let event: Value = serde_json::from_str(&event).unwrap();
                    let resync = event["type"] == "state.resync";
                    resumed_events.push(event);
                    if resync && resumed_events.len() == 1 {
                        // Events published while the caller handles the marker
                        // must still reach this observer after resynchronizing.
                        sender
                            .send(json!({"type":"device.changed","sequence":301,"data":{}}))
                            .unwrap();
                    }
                    resync
                },
            )
            .await;
            drop(paused);

            assert_eq!(resumed_events.len(), 2);
            assert_eq!(resumed_events[0]["type"], "state.resync");
            assert_eq!(resumed_events[1]["sequence"], 301);
            assert!(!active_token.is_cancelled());
            assert_eq!(active_events.recv().await.unwrap()["sequence"], 301);
            observers.cancel(active_id);
            active_task.await.unwrap();
        })
        .await
        .expect("event observers should finish without waiting for a heartbeat");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_cancel_and_claim_never_reuse_or_cross_cancel_owners() {
        let observers = registry(64);
        let mut tasks = Vec::new();
        for _ in 0..64 {
            let id = observers.open().unwrap();
            let claimant = observers.clone();
            let canceller = observers.clone();
            tasks.push(tokio::spawn(async move {
                let (lease, ()) = tokio::join!(async { claimant.listen(id).unwrap() }, async {
                    tokio::task::yield_now().await;
                    canceller.cancel(id);
                });
                if let Some(lease) = lease {
                    assert!(lease.token.is_cancelled());
                }
                claimant.cancel(id);
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        assert!(observers.0.entries().is_empty());
        let fresh = observers.open().unwrap();
        assert!(
            !observers
                .listen(fresh)
                .unwrap()
                .unwrap()
                .token
                .is_cancelled()
        );
    }
}
