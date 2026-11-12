//! 进程内数据包交付；外部回调同步借用字节，注销 sink 等待已准入回调完成。

use super::{MediaError, MediaResult};
use std::{
    collections::HashMap,
    ffi::c_void,
    sync::{Arc, Mutex, OnceLock, Weak},
    time::Duration,
};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

pub const EVENT_CONFIGURE: u32 = 1;
pub const EVENT_PACKET: u32 = 2;
pub const EVENT_END: u32 = 3;
pub const FLAG_KEYFRAME: u32 = 1;
pub const CODEC_PCM_S16LE: u32 = 100;

pub type MediaEvent =
    unsafe extern "C" fn(*mut c_void, u32, u64, u32, u32, u32, *const u8, usize, i64, u32) -> i32;

/// ABI v1。detach 返回前 context、callback 保持存活；回调须及时返回，禁止展开或重入 attach/detach。仅在调用期间借用数据，禁止保留字节。返回 0 表示已消费，1 表示未消费需重试，负值表示来源失败。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct MediaSinkV1 {
    pub abi_version: u32,
    pub struct_size: u32,
    pub context: *mut c_void,
    pub event: Option<MediaEvent>,
}
// SourceState 串行化调用与 context 生命周期；外部调用方保证 context 可在任意 runtime worker 线程调用。
unsafe impl Send for MediaSinkV1 {}

pub type Release = unsafe extern "C" fn(*mut c_void);
pub type Wake = unsafe extern "C" fn(*mut c_void);
pub type OwnedEvent = unsafe extern "C" fn(
    *mut c_void,
    u32,
    u64,
    u32,
    u32,
    u32,
    *mut u8,
    usize,
    usize,
    *mut c_void,
    Option<Release>,
    i64,
    u32,
) -> i32;
#[repr(C)]
#[derive(Clone, Copy)]
pub struct MediaSinkV2 {
    pub base: MediaSinkV1,
    pub event_owned: Option<OwnedEvent>,
    pub set_waker:
        Option<unsafe extern "C" fn(*mut c_void, *mut c_void, Option<Wake>, Option<Release>)>,
}
#[derive(Clone, Copy)]
struct Sink {
    base: MediaSinkV1,
    owned: Option<OwnedEvent>,
}
unsafe impl Send for Sink {}
unsafe extern "C" fn wake_source(context: *mut c_void) {
    unsafe {
        (&*(context as *const Notify)).notify_one();
    }
}
unsafe extern "C" fn release_waker(context: *mut c_void) {
    drop(unsafe { Arc::from_raw(context as *const Notify) });
}
unsafe extern "C" fn release_bytes(context: *mut c_void) {
    drop(unsafe { Box::from_raw(context as *mut Vec<u8>) });
}

struct SourceState {
    sink: Option<Sink>,
    generation: u64,
    dimensions: (u32, u32),
    closed: bool,
    packets: u64,
    bytes: u64,
}

pub struct MediaSource {
    id: String,
    codec: u32,
    state: Mutex<SourceState>,
    attached: Notify,
    ready: Arc<Notify>,
    cancellation: CancellationToken,
}

fn sources() -> &'static Mutex<HashMap<String, Weak<MediaSource>>> {
    static SOURCES: OnceLock<Mutex<HashMap<String, Weak<MediaSource>>>> = OnceLock::new();
    SOURCES.get_or_init(Mutex::default)
}
fn lookup(id: &str) -> Option<Arc<MediaSource>> {
    sources()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .get(id)
        .and_then(Weak::upgrade)
}
fn codec_name(codec: u32) -> &'static str {
    match codec {
        1 => "h264",
        2 => "h265",
        3 => "av1",
        4 => "vp8",
        5 => "vp9",
        CODEC_PCM_S16LE => "pcm_s16le",
        _ => "unknown",
    }
}
pub fn video_codec_id(codec: &str) -> MediaResult<u32> {
    match codec {
        "h264" => Ok(1),
        "h265" => Ok(2),
        "av1" => Ok(3),
        "vp8" => Ok(4),
        "vp9" => Ok(5),
        _ => Err(MediaError::new("media_codec", "未知视频编码格式。")),
    }
}

impl MediaSource {
    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn register(
        id: String,
        codec: u32,
        width: u32,
        height: u32,
        cancellation: CancellationToken,
    ) -> MediaResult<Arc<Self>> {
        let mut registry = sources().lock().unwrap_or_else(|e| e.into_inner());
        registry.retain(|_, source| source.strong_count() != 0);
        if registry.len() >= 32 || registry.contains_key(&id) {
            return Err(MediaError::new(
                "resource_busy",
                "媒体输入数量已达上限或标识重复。",
            ));
        }
        let source = Arc::new(Self {
            id: id.clone(),
            codec,
            state: Mutex::new(SourceState {
                sink: None,
                generation: 0,
                dimensions: (width, height),
                closed: false,
                packets: 0,
                bytes: 0,
            }),
            attached: Notify::new(),
            ready: Arc::new(Notify::new()),
            cancellation,
        });
        registry.insert(id, Arc::downgrade(&source));
        Ok(source)
    }
    pub async fn wait_attached(&self) -> MediaResult<()> {
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let notified = self.attached.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();
                {
                    let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                    if state.closed {
                        return Err(MediaError::new("media_ended", "媒体输入已结束。"));
                    }
                    if state.sink.is_some() {
                        return Ok(());
                    }
                }
                notified.await;
            }
        })
        .await
        .map_err(|_| MediaError::new("renderer_timeout", "未能连接媒体呈现器。"))?
    }
    fn invoke(
        &self,
        kind: u32,
        dimensions: (u32, u32),
        data: &[u8],
        pts: i64,
        flags: u32,
    ) -> MediaResult<bool> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.closed || self.cancellation.is_cancelled() {
            return Err(MediaError::new("media_ended", "媒体输入已结束。"));
        }
        let sink = state
            .sink
            .ok_or_else(|| MediaError::new("media_detached", "媒体呈现器已释放。"))?;
        // detach 取得此锁后才允许释放外部 context；回调禁止重入本来源登记表 API。
        let result = unsafe {
            sink.base.event.expect("validated sink")(
                sink.base.context,
                kind,
                state.generation,
                self.codec,
                dimensions.0,
                dimensions.1,
                data.as_ptr(),
                data.len(),
                pts,
                flags,
            )
        };
        if result < 0 {
            return Err(MediaError::new("media_decoder", "原生解码器拒绝媒体输入。"));
        }
        if result == 0 {
            if kind == EVENT_CONFIGURE {
                state.dimensions = dimensions;
            }
            if kind == EVENT_PACKET {
                state.packets += 1;
                state.bytes += data.len() as u64;
            }
        }
        Ok(result == 0)
    }
    async fn deliver(
        &self,
        kind: u32,
        dimensions: (u32, u32),
        data: &[u8],
        pts: i64,
        flags: u32,
    ) -> MediaResult<()> {
        let send = async {
            loop {
                let ready = self.ready.notified();
                tokio::pin!(ready);
                ready.as_mut().enable();
                if self.invoke(kind, dimensions, data, pts, flags)? {
                    return Ok(());
                }
                let signalled = self
                    .state
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .sink
                    .is_some_and(|sink| sink.owned.is_some());
                tokio::select! {
                    _ = self.cancellation.cancelled() => return Err(MediaError::new("media_ended", "媒体输入已结束。")),
                    _ = ready, if signalled => {},
                    _ = tokio::time::sleep(Duration::from_millis(2)), if !signalled => {},
                }
            }
        };
        tokio::time::timeout(Duration::from_secs(3), send)
            .await
            .map_err(|_| MediaError::new("media_stall", "原生解码器未及时读取媒体输入。"))?
    }
    pub async fn configure(
        &self,
        width: u32,
        height: u32,
        configuration: &[u8],
    ) -> MediaResult<()> {
        if configuration.len() > super::MAX_CONFIGURATION_BYTES {
            return Err(MediaError::new("media_protocol", "媒体配置超过限额。"));
        }
        self.deliver(EVENT_CONFIGURE, (width, height), configuration, 0, 0)
            .await
    }
    pub async fn packet(&self, data: &[u8], pts_us: u64, keyframe: bool) -> MediaResult<()> {
        if data.is_empty() || data.len() > super::MAX_PACKET_BYTES {
            return Err(MediaError::new("media_protocol", "媒体数据包大小无效。"));
        }
        let dimensions = self
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .dimensions;
        self.deliver(
            EVENT_PACKET,
            dimensions,
            data,
            pts_us as i64,
            if keyframe { FLAG_KEYFRAME } else { 0 },
        )
        .await
    }
    /// 向 v2 解码器转交数据包分配所有权；v1 保留借用兼容路径。初始化填充不再次清零负载；reader 可预留 64 字节尾部。
    pub async fn packet_owned(
        &self,
        mut data: Vec<u8>,
        pts_us: u64,
        keyframe: bool,
    ) -> MediaResult<()> {
        let length = data.len();
        if length == 0 || length > super::MAX_PACKET_BYTES {
            return Err(MediaError::new("media_protocol", "媒体数据包大小无效。"));
        }
        data.resize(length + 64, 0);
        let owner = Box::into_raw(Box::new(data)) as usize;
        struct Owned(usize);
        unsafe impl Send for Owned {}
        impl Drop for Owned {
            fn drop(&mut self) {
                if self.0 != 0 {
                    unsafe {
                        release_bytes(self.0 as *mut c_void);
                    }
                }
            }
        }
        let mut allocation = Owned(owner);
        let send = async {
            loop {
                let ready = self.ready.notified();
                tokio::pin!(ready);
                ready.as_mut().enable();
                let (result, owned) = {
                    let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                    if state.closed || self.cancellation.is_cancelled() {
                        return Err(MediaError::new("media_ended", "媒体输入已结束。"));
                    }
                    let sink = state
                        .sink
                        .ok_or_else(|| MediaError::new("media_detached", "媒体呈现器已释放。"))?;
                    let bytes = unsafe { &mut *(allocation.0 as *mut Vec<u8>) };
                    let (width, height) = state.dimensions;
                    let flags = if keyframe { FLAG_KEYFRAME } else { 0 };
                    let result = unsafe {
                        if let Some(callback) = sink.owned {
                            callback(
                                sink.base.context,
                                EVENT_PACKET,
                                state.generation,
                                self.codec,
                                width,
                                height,
                                bytes.as_mut_ptr(),
                                length,
                                bytes.len(),
                                allocation.0 as *mut c_void,
                                Some(release_bytes),
                                pts_us as i64,
                                flags,
                            )
                        } else {
                            sink.base.event.unwrap()(
                                sink.base.context,
                                EVENT_PACKET,
                                state.generation,
                                self.codec,
                                width,
                                height,
                                bytes.as_ptr(),
                                length,
                                pts_us as i64,
                                flags,
                            )
                        }
                    };
                    if result == 0 {
                        state.packets += 1;
                        state.bytes += length as u64;
                    }
                    (result, sink.owned.is_some())
                };
                if result == 0 {
                    if owned {
                        allocation.0 = 0;
                    }
                    return Ok(());
                }
                if result < 0 {
                    return Err(MediaError::new("media_decoder", "原生解码器拒绝媒体输入。"));
                }
                tokio::select! {
                    _ = self.cancellation.cancelled() => return Err(MediaError::new("media_ended", "媒体输入已结束。")),
                    _ = ready, if owned => {},
                    _ = tokio::time::sleep(Duration::from_millis(2)), if !owned => {},
                }
            }
        };
        tokio::time::timeout(Duration::from_secs(3), send)
            .await
            .map_err(|_| MediaError::new("media_stall", "原生解码器未及时读取媒体输入。"))?
    }
    pub fn finish(&self) {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.closed {
            return;
        }
        state.closed = true;
        if let Some(sink) = state.sink.take() {
            unsafe {
                sink.base.event.expect("validated sink")(
                    sink.base.context,
                    EVENT_END,
                    state.generation,
                    self.codec,
                    state.dimensions.0,
                    state.dimensions.1,
                    std::ptr::null(),
                    0,
                    0,
                    0,
                );
            }
        }
        self.attached.notify_waiters();
        self.ready.notify_waiters();
    }
    pub fn view(&self, generation: u64) -> SourceStatus {
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        self.view_locked(&state, generation)
    }
    fn view_locked(&self, state: &SourceState, generation: u64) -> SourceStatus {
        SourceStatus {
            source_id: self.id.clone(),
            generation,
            codec: codec_name(self.codec).into(),
            kind: if self.codec == CODEC_PCM_S16LE {
                "audio"
            } else {
                "video"
            }
            .into(),
            width: state.dimensions.0,
            height: state.dimensions.1,
            attach_address: interop_media_attach as *const () as usize as u64,
            detach_address: interop_media_detach as *const () as usize as u64,
            status: if state.closed {
                "closed"
            } else if state.sink.is_some() {
                "streaming"
            } else {
                "waiting"
            }
            .into(),
            packets: state.packets,
            bytes: state.bytes,
        }
    }
}
impl Drop for MediaSource {
    fn drop(&mut self) {
        self.finish();
        sources()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&self.id);
    }
}

/// 仅拥有复制后的函数表，不拥有外部 context。
pub fn attach(id: &str, generation: u64, sink: MediaSinkV1) -> i32 {
    if sink.abi_version != 1
        || sink.struct_size as usize != std::mem::size_of::<MediaSinkV1>()
        || sink.event.is_none()
        || generation == 0
    {
        return -2;
    }
    let Some(source) = lookup(id) else {
        return -1;
    };
    let mut state = source.state.lock().unwrap_or_else(|e| e.into_inner());
    if state.closed
        || source.cancellation.is_cancelled()
        || state.sink.is_some()
        || generation <= state.generation
    {
        return -3;
    }
    state.generation = generation;
    state.sink = Some(Sink {
        base: sink,
        owned: None,
    });
    drop(state);
    source.attached.notify_one();
    0
}
pub fn detach(id: &str, generation: u64) -> i32 {
    let Some(source) = lookup(id) else {
        return -1;
    };
    let mut state = source.state.lock().unwrap_or_else(|e| e.into_inner());
    if generation != state.generation {
        return -3;
    }
    state.sink = None;
    state.closed = true;
    source.cancellation.cancel();
    drop(state);
    source.attached.notify_waiters();
    0
}

/// # Safety
///
/// `id` 须可读 length 字节，sink 须指向对齐且存活的 v1 表。detach 返回前 context 和 callback 保持有效；回调禁止调用这些登记函数。此处只验证数值，不验证任意指针。
#[unsafe(no_mangle)]
pub unsafe extern "C" fn interop_media_attach(
    id: *const u8,
    length: usize,
    generation: u64,
    sink: *const MediaSinkV1,
) -> i32 {
    if id.is_null() || length != 64 || sink.is_null() {
        return -2;
    }
    let bytes = unsafe { std::slice::from_raw_parts(id, length) };
    let Ok(id) = std::str::from_utf8(bytes) else {
        return -2;
    };
    if !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return -2;
    }
    let base = unsafe { *sink };
    if base.abi_version == 1 {
        return attach(id, generation, base);
    }
    if base.abi_version != 2 || base.struct_size as usize != std::mem::size_of::<MediaSinkV2>() {
        return -2;
    }
    let table = unsafe { *(sink as *const MediaSinkV2) };
    if table.event_owned.is_none() || table.set_waker.is_none() {
        return -2;
    }
    let Some(source) = lookup(id) else {
        return -1;
    };
    let mut state = source.state.lock().unwrap_or_else(|e| e.into_inner());
    if generation == 0
        || state.closed
        || source.cancellation.is_cancelled()
        || state.sink.is_some()
        || generation <= state.generation
        || base.event.is_none()
    {
        return -3;
    }
    let context = Arc::into_raw(source.ready.clone()) as *mut c_void;
    unsafe {
        table.set_waker.unwrap()(
            base.context,
            context,
            Some(wake_source),
            Some(release_waker),
        );
    }
    state.generation = generation;
    state.sink = Some(Sink {
        base,
        owned: table.event_owned,
    });
    drop(state);
    source.attached.notify_one();
    0
}

/// # Safety
///
/// 本函数返回前，id 须始终可读 length 字节。
#[unsafe(no_mangle)]
pub unsafe extern "C" fn interop_media_detach(
    id: *const u8,
    length: usize,
    generation: u64,
) -> i32 {
    if id.is_null() || length != 64 {
        return -2;
    }
    let bytes = unsafe { std::slice::from_raw_parts(id, length) };
    let Ok(id) = std::str::from_utf8(bytes) else {
        return -2;
    };
    if !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return -2;
    }
    detach(id, generation)
}

#[derive(Debug)]
pub struct SourceStatus {
    pub source_id: String,
    pub generation: u64,
    pub kind: String,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub attach_address: u64,
    pub detach_address: u64,
    pub status: String,
    pub packets: u64,
    pub bytes: u64,
}
#[derive(Default)]
pub struct MediaStreams;
pub struct SourceEndpoint {
    pub source_id: String,
    pub generation: u64,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub attach_address: u64,
    pub detach_address: u64,
}
impl MediaStreams {
    /// 只取得现有来源的 ABI 描述，不创建第二份媒体队列或来源所有权。
    pub fn inspect(&self, id: &str, generation: u64) -> MediaResult<SourceEndpoint> {
        if generation == 0 {
            return Err(MediaError::new("invalid_endpoint", "媒体代次无效。"));
        }
        let source =
            lookup(id).ok_or_else(|| MediaError::new("media_ended", "媒体输入已结束。"))?;
        let state = source
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if state.closed || source.cancellation.is_cancelled() {
            return Err(MediaError::new("media_ended", "媒体输入已结束。"));
        }
        Ok(SourceEndpoint {
            source_id: id.to_owned(),
            generation,
            codec: codec_name(source.codec).into(),
            width: state.dimensions.0,
            height: state.dimensions.1,
            attach_address: interop_media_attach as *const () as usize as u64,
            detach_address: interop_media_detach as *const () as usize as u64,
        })
    }
    pub fn open(&self, id: &str, generation: u64, kind: &str) -> MediaResult<SourceStatus> {
        let source =
            lookup(id).ok_or_else(|| MediaError::new("media_ended", "媒体输入已结束。"))?;
        if generation == 0
            || kind
                != if source.codec == CODEC_PCM_S16LE {
                    "audio"
                } else {
                    "video"
                }
        {
            return Err(MediaError::new(
                "invalid_endpoint",
                "媒体源类型或代次不一致。",
            ));
        }
        Ok(source.view(generation))
    }
    pub fn status(&self, id: &str) -> MediaResult<SourceStatus> {
        let source =
            lookup(id).ok_or_else(|| MediaError::new("media_ended", "媒体输入已结束。"))?;
        let state = source
            .state
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        // 代次、sink 状态与接纳计数必须来自同一次锁内快照，不能跨 attach 拼接事实。
        Ok(source.view_locked(&state, state.generation))
    }
    pub fn close(&self, id: &str) {
        if let Some(source) = lookup(id) {
            source.finish();
            source.cancellation.cancel();
        }
    }
}
