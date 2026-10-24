//! 调用方提供单调时钟域的可选接收诊断。
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

/// 提供最近流读取数据的 WRTE payload 计时。所有微秒值使用 [`crate::AdbStream::set_read_trace_clock`] 提供的时钟；计时从 ADB 头部之后开始，不含之前的传输缓冲或空闲时间。同一 WRTE 的重复读取沿用同一回执和序号。
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
