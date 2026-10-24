//! 包存储、双重容量约束与完整 GOP 重放；不依赖解码器或平台输出。

use super::ff;
use std::{collections::VecDeque, ffi::c_void, slice, sync::Arc};

pub(super) const MAX_BYTES: usize = 16 * 1024 * 1024;
pub(super) const HISTORY_MAX_BYTES: usize = 8 * 1024 * 1024;
// 同时限制元数据和 Arc 数量，不能只依靠媒体负载字节约束历史内存。
pub(super) const HISTORY_MAX_PACKETS: usize = 4096;
pub(super) const MAX_PACKETS: usize = 8;

pub(super) enum Storage {
    Local(Vec<u8>),
    Foreign {
        data: *mut u8,
        size: usize,
        owner: *mut c_void,
        release: ff::mc_release_fn,
    },
}
// 独占包存储在准入成功后转交解码线程；生产者不得继续读写。
unsafe impl Send for Storage {}
// 共享引用只读取压缩数据；PCM 仅在 Arc 唯一时修改。
unsafe impl Sync for Storage {}
impl std::ops::Deref for Storage {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        match self {
            Self::Local(bytes) => bytes,
            Self::Foreign { data, size, .. } => unsafe { slice::from_raw_parts(*data, *size) },
        }
    }
}
impl std::ops::DerefMut for Storage {
    fn deref_mut(&mut self) -> &mut [u8] {
        match self {
            Self::Local(bytes) => bytes,
            Self::Foreign { data, size, .. } => unsafe { slice::from_raw_parts_mut(*data, *size) },
        }
    }
}
impl Drop for Storage {
    fn drop(&mut self) {
        if let Self::Foreign {
            owner,
            release: Some(release),
            ..
        } = self
        {
            unsafe {
                release(*owner);
            }
        }
    }
}
pub(super) struct PacketBytes {
    pub(super) storage: Storage,
    pub(super) length: usize,
}
#[derive(Clone)]
pub(super) struct Packet {
    pub(super) event: u32,
    pub(super) codec: u32,
    pub(super) width: u32,
    pub(super) height: u32,
    pub(super) flags: u32,
    pub(super) pts: i64,
    pub(super) data: Arc<PacketBytes>,
}
// 只有完整的当前 GOP 才能重放；容量溢出后，P 帧后缀不能恢复历史。
#[derive(Default)]
pub(super) struct GopHistory {
    packets: VecDeque<Packet>,
    bytes: usize,
    complete: bool,
}
impl GopHistory {
    pub(super) fn record(&mut self, packet: &Packet) {
        if packet.flags & 1 != 0 {
            self.clear();
            self.complete = true;
        }
        if !self.complete {
            return;
        }
        if self.packets.len() >= HISTORY_MAX_PACKETS
            || packet.data.length > HISTORY_MAX_BYTES - self.bytes
        {
            self.clear();
            return;
        }
        self.bytes += packet.data.length;
        self.packets.push_back(packet.clone());
    }
    pub(super) fn clear(&mut self) {
        self.packets.clear();
        self.bytes = 0;
        self.complete = false;
    }
    pub(super) fn replay(&self) -> Option<VecDeque<Packet>> {
        self.complete.then(|| self.packets.clone())
    }
}

/// 同时约束包数和字节数，集中维护准入、消费与暂停后的容量回收。
#[derive(Default)]
pub(super) struct PacketQueue {
    packets: VecDeque<Packet>,
    bytes: usize,
}

impl PacketQueue {
    pub(super) fn is_empty(&self) -> bool {
        self.packets.is_empty()
    }

    /// 只有获得容量后才构造包，拒绝时外部存储仍由生产者释放。
    pub(super) fn enqueue(&mut self, size: usize, make: impl FnOnce() -> Packet) -> bool {
        if self.packets.len() >= MAX_PACKETS || size > MAX_BYTES - self.bytes {
            return false;
        }
        let packet = make();
        debug_assert_eq!(packet.data.length, size);
        self.bytes += size;
        self.packets.push_back(packet);
        true
    }

    pub(super) fn pop(&mut self) -> Option<Packet> {
        let packet = self.packets.pop_front()?;
        self.bytes -= packet.data.length;
        Some(packet)
    }

    pub(super) fn discard_data(&mut self) {
        self.packets.retain(|packet| packet.event != 2);
        self.bytes = self.packets.iter().map(|packet| packet.data.length).sum();
    }

    /// PCM 允许舍弃积压的完整旧包，至少保留最新包；视频不走此路径。
    pub(super) fn trim_pcm(&mut self) -> u64 {
        let mut dropped = 0;
        while self.bytes > 15_360 && self.packets.len() > 1 {
            dropped += (self.pop().unwrap().data.length / 4) as u64;
        }
        dropped
    }
}
