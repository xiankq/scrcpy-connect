//! AOSP delayed_ack 信用与保守的接收内存预留。协议来源：platform/packages/modules/adb @ 9084198a2d4b0f6a0f174260fb42da33485b684d 的 adb.cpp、sockets.cpp。
use crate::{Error, Result, read_trace::ReceivedPayload};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::Notify;

// 发送方余额为正时可发送一个完整 max_payload 包，即使该包使余额转负。
pub(crate) const RECEIVE_WINDOW: usize = 64 * 1024;
pub(crate) const RECEIVE_PACKETS: usize = RECEIVE_WINDOW + 1;
const CONNECTION_RECEIVE_BUDGET: usize = 128 * 1024 * 1024;

#[derive(Default)]
pub(crate) struct Budget(Arc<AtomicUsize>);
impl Budget {
    pub fn reserve(&self, max_payload: usize) -> Result<Arc<Reservation>> {
        // 非空包至少消耗一个信用字节；预留包含通道块、追踪元数据，以及单字节 WRTE、max_payload 超额包和保留读缓冲的最坏分配开销。空 burst WRTE 直接丢弃，不分配队列项。
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
    // 直到路由和消费者（含 CLSE 尾部数据）全部释放后，才归还预留。
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
