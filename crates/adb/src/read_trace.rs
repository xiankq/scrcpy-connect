//! Optional receive diagnostics in a caller-supplied monotonic clock domain.
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

/// Timing of the WRTE payload supplying the most recent stream read.
///
/// All microsecond values use the clock supplied to
/// [`crate::AdbStream::set_read_trace_clock`]. Payload reception starts after
/// the ADB header and excludes earlier transport buffering and idle time.
/// Repeated reads from the same WRTE retain the same receipt and sequence.
#[derive(Debug, Clone, Copy)]
pub struct ReadTrace {
    pub sequence: u64,
    pub payload_bytes: usize,
    pub payload_started_us: u64,
    pub payload_read_us: u64,
    pub routed_us: u64,
    pub first_consumed_us: u64,
}

pub(crate) struct Subscription {
    pub clock: TraceClock,
    pub sequence: u64,
    count: Arc<AtomicUsize>,
}

impl Subscription {
    pub fn new(clock: fn() -> u64, count: Arc<AtomicUsize>) -> Self {
        count.fetch_add(1, Ordering::Relaxed);
        Self {
            clock: TraceClock {
                read: clock,
                token: Arc::new(()),
            },
            sequence: 0,
            count,
        }
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.count.fetch_sub(1, Ordering::Relaxed);
    }
}

pub(crate) struct PayloadTiming {
    pub clock: TraceClock,
    pub started_us: u64,
    pub read_us: u64,
}

pub(crate) struct ReceivedPayload {
    pub bytes: Vec<u8>,
    pub timing: Option<(ReadTrace, TraceClock)>,
}

#[derive(Clone)]
pub(crate) struct TraceClock {
    pub read: fn() -> u64,
    pub token: Arc<()>,
}
