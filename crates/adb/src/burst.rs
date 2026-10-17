//! AOSP delayed_ack credit and conservative receive-memory reservations.
//!
//! Protocol reference: platform/packages/modules/adb @
//! 9084198a2d4b0f6a0f174260fb42da33485b684d, adb.cpp and sockets.cpp.
use crate::{Error, Result, read_trace::ReceivedPayload};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::Notify;

// A sender may transmit one whole max_payload packet while its balance is
// positive, even when that packet makes the balance negative.
pub(crate) const RECEIVE_WINDOW: usize = 64 * 1024;
pub(crate) const RECEIVE_PACKETS: usize = RECEIVE_WINDOW + 1;
const CONNECTION_RECEIVE_BUDGET: usize = 128 * 1024 * 1024;

#[derive(Default)]
pub(crate) struct Budget(Arc<AtomicUsize>);
impl Budget {
    pub fn reserve(&self, max_payload: usize) -> Result<Arc<Reservation>> {
        // Nonempty packets cost at least one credit byte. Include channel block
        // storage, trace metadata and a conservative allocation allowance for
        // the worst case of one-byte WRTEs, the max-payload overshoot, and the
        // retained read buffer.
        // Zero-byte burst WRTEs are discarded without allocating queue entries.
        let bytes = RECEIVE_WINDOW
            + 2 * max_payload
            + RECEIVE_PACKETS * (std::mem::size_of::<ReceivedPayload>() + 64);
        let mut used = self.0.load(Ordering::Relaxed);
        loop {
            let next = used
                .checked_add(bytes)
                .filter(|total| *total <= CONNECTION_RECEIVE_BUDGET)
                .ok_or(Error::InvalidArgument(
                    "ADB burst receive memory budget exhausted",
                ))?;
            match self
                .0
                .compare_exchange_weak(used, next, Ordering::Relaxed, Ordering::Relaxed)
            {
                Ok(_) => break,
                Err(current) => used = current,
            }
        }
        Ok(Arc::new(Reservation {
            used: self.0.clone(),
            bytes,
        }))
    }
}
pub(crate) struct Reservation {
    used: Arc<AtomicUsize>,
    bytes: usize,
}
impl Drop for Reservation {
    fn drop(&mut self) {
        self.used.fetch_sub(self.bytes, Ordering::Relaxed);
    }
}

pub(crate) struct Flow {
    pub send_credit: i64,
    pub receive_credit: i64,
    pub changed: Arc<Notify>,
    // Retain the reservation until both the route and the consumer (including
    // any CLSE tail data) have gone away.
    pub _reservation: Arc<Reservation>,
}
impl Flow {
    pub fn new(reservation: Arc<Reservation>, send_credit: i64, receiving: bool) -> Self {
        Self {
            send_credit,
            receive_credit: if receiving { RECEIVE_WINDOW as i64 } else { 0 },
            changed: Arc::new(Notify::new()),
            _reservation: reservation,
        }
    }
    pub fn acknowledge(&mut self, payload: &[u8]) -> Result<()> {
        let delta =
            i32::from_le_bytes(payload.try_into().map_err(|_| {
                Error::Protocol("burst OKAY needs a signed four-byte delta".into())
            })?);
        self.send_credit = self
            .send_credit
            .checked_add(i64::from(delta))
            .ok_or_else(|| Error::Protocol("burst send credit overflow".into()))?;
        self.changed.notify_waiters();
        Ok(())
    }
    pub fn receive(&mut self, bytes: usize) -> bool {
        if bytes == 0 {
            return true;
        }
        if self.receive_credit <= 0 {
            return false;
        }
        self.receive_credit -= bytes as i64;
        true
    }
}
impl Drop for Flow {
    fn drop(&mut self) {
        self.changed.notify_waiters();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signed_64_bit_credit_overflow_is_rejected_without_wrapping() {
        let reservation = Budget::default().reserve(4096).unwrap();
        let mut flow = Flow::new(reservation, i64::MAX, true);
        assert!(flow.acknowledge(&1i32.to_le_bytes()).is_err());
        assert_eq!(flow.send_credit, i64::MAX);
        flow.send_credit = i64::MIN;
        assert!(flow.acknowledge(&(-1i32).to_le_bytes()).is_err());
        assert_eq!(flow.send_credit, i64::MIN);
    }
}
