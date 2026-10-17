//! Ordered event receipts shared by every runtime producer and state snapshots.
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;

#[derive(Clone)]
pub(crate) struct EventBus(Arc<Inner>);

struct Inner {
    sender: broadcast::Sender<Value>,
    cursor: Mutex<Cursor>,
}

#[derive(Clone, Copy, Default)]
pub(crate) struct Cursor {
    pub(crate) sequence: u64,
    pub(crate) state_revision: u64,
}

impl EventBus {
    pub(crate) fn new(capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self(Arc::new(Inner {
            sender,
            cursor: Mutex::new(Cursor::default()),
        }))
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<Value> {
        self.0.sender.subscribe()
    }

    pub(crate) fn cursor(&self) -> Cursor {
        *self.0.cursor.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// A query may refresh a cache without producing a new user-facing event.
    /// Record that write while its state guard is held so snapshots retry it.
    pub(crate) fn note_state_change(&self) {
        let mut cursor = self.0.cursor.lock().unwrap_or_else(|e| e.into_inner());
        cursor.state_revision = cursor
            .state_revision
            .checked_add(1)
            .expect("state revision exhausted");
    }

    pub(crate) fn send(
        &self,
        mut event: Value,
    ) -> Result<usize, broadcast::error::SendError<Value>> {
        // Sequence assignment and publication use one short synchronous lock;
        // concurrent producers cannot publish sequence N+1 ahead of N.
        let mut cursor = self.0.cursor.lock().unwrap_or_else(|e| e.into_inner());
        cursor.sequence = cursor
            .sequence
            .checked_add(1)
            .expect("event sequence exhausted");
        if event["type"] != "session.frame" {
            cursor.state_revision = cursor
                .state_revision
                .checked_add(1)
                .expect("state revision exhausted");
        }
        event["sequence"] = json!(cursor.sequence);
        self.0.sender.send(event)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn concurrent_producers_publish_in_sequence_order() {
        let bus = EventBus::new(1024);
        let mut receiver = bus.subscribe();
        std::thread::scope(|scope| {
            for _ in 0..4 {
                let bus = bus.clone();
                scope.spawn(move || {
                    for _ in 0..100 {
                        bus.send(json!({"type":"device.changed"})).unwrap();
                    }
                });
            }
        });
        for sequence in 1..=400 {
            assert_eq!(receiver.try_recv().unwrap()["sequence"], sequence);
        }
        assert_eq!(bus.cursor().state_revision, 400);
    }

    #[test]
    fn frame_telemetry_does_not_starve_a_state_snapshot() {
        let bus = EventBus::new(2);
        // Even without a subscriber, a committed state's sequence advances.
        assert!(bus.send(json!({"type":"session.updated"})).is_err());
        assert!(bus.send(json!({"type":"session.frame"})).is_err());
        assert_eq!(bus.cursor().sequence, 2);
        assert_eq!(bus.cursor().state_revision, 1);
    }
}
