//! Process-local packet delivery. Foreign callbacks borrow bytes synchronously.
//! Unregistering a sink waits for its admitted callback to finish.

use crate::{CoreError, CoreResult};
use serde_json::{Value, json};
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

/// ABI v1. Context/callback remain live until detach returns. Callbacks must
/// return promptly, never unwind and never reenter attach/detach. Data is only
/// borrowed during the call. Return 0 consumed, 1 retry without consuming, or a
/// negative value to fail the source. No callback may retain the borrowed bytes.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct MediaSinkV1 {
    pub abi_version: u32,
    pub struct_size: u32,
    pub context: *mut c_void,
    pub event: Option<MediaEvent>,
}
// Calls/context lifetime are serialized by SourceState; the foreign caller
// promises that its context may be called on any runtime worker thread.
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
pub fn video_codec_id(codec: &str) -> CoreResult<u32> {
    match codec {
        "h264" => Ok(1),
        "h265" => Ok(2),
        "av1" => Ok(3),
        "vp8" => Ok(4),
        "vp9" => Ok(5),
        _ => Err(CoreError::new("media_codec", "未知视频编码格式。")),
    }
}

impl MediaSource {
    pub fn register(
        id: String,
        codec: u32,
        width: u32,
        height: u32,
        cancellation: CancellationToken,
    ) -> CoreResult<Arc<Self>> {
        let mut registry = sources().lock().unwrap_or_else(|e| e.into_inner());
        registry.retain(|_, source| source.strong_count() != 0);
        if registry.len() >= 32 || registry.contains_key(&id) {
            return Err(CoreError::new(
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
    pub async fn wait_attached(&self) -> CoreResult<()> {
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let notified = self.attached.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();
                {
                    let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
                    if state.closed {
                        return Err(CoreError::new("media_ended", "媒体输入已结束。"));
                    }
                    if state.sink.is_some() {
                        return Ok(());
                    }
                }
                notified.await;
            }
        })
        .await
        .map_err(|_| CoreError::new("renderer_timeout", "未能连接媒体呈现器。"))?
    }
    fn invoke(
        &self,
        kind: u32,
        dimensions: (u32, u32),
        data: &[u8],
        pts: i64,
        flags: u32,
    ) -> CoreResult<bool> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.closed || self.cancellation.is_cancelled() {
            return Err(CoreError::new("media_ended", "媒体输入已结束。"));
        }
        let sink = state
            .sink
            .ok_or_else(|| CoreError::new("media_detached", "媒体呈现器已释放。"))?;
        // Detach must acquire this lock before returning permission to free the
        // foreign context. No callback may reenter this source's registry API.
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
            return Err(CoreError::new("media_decoder", "原生解码器拒绝媒体输入。"));
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
    ) -> CoreResult<()> {
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
                    _ = self.cancellation.cancelled() => return Err(CoreError::new("media_ended", "媒体输入已结束。")),
                    _ = ready, if signalled => {},
                    _ = tokio::time::sleep(Duration::from_millis(2)), if !signalled => {},
                }
            }
        };
        tokio::time::timeout(Duration::from_secs(3), send)
            .await
            .map_err(|_| CoreError::new("media_stall", "原生解码器未及时读取媒体输入。"))?
    }
    pub async fn configure(&self, width: u32, height: u32, configuration: &[u8]) -> CoreResult<()> {
        if configuration.len() > super::MAX_CONFIGURATION_BYTES {
            return Err(CoreError::new("media_protocol", "媒体配置超过限额。"));
        }
        self.deliver(EVENT_CONFIGURE, (width, height), configuration, 0, 0)
            .await
    }
    pub async fn packet(&self, data: &[u8], pts_us: u64, keyframe: bool) -> CoreResult<()> {
        if data.is_empty() || data.len() > super::MAX_PACKET_BYTES {
            return Err(CoreError::new("media_protocol", "媒体数据包大小无效。"));
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
    /// Transfer a packet allocation to a v2 decoder; v1 consumers retain the
    /// borrowed compatibility path. Padding is initialized without clearing the
    /// payload a second time. Readers can reserve the 64-byte tail up front.
    pub async fn packet_owned(
        &self,
        mut data: Vec<u8>,
        pts_us: u64,
        keyframe: bool,
    ) -> CoreResult<()> {
        let length = data.len();
        if length == 0 || length > super::MAX_PACKET_BYTES {
            return Err(CoreError::new("media_protocol", "媒体数据包大小无效。"));
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
                        return Err(CoreError::new("media_ended", "媒体输入已结束。"));
                    }
                    let sink = state
                        .sink
                        .ok_or_else(|| CoreError::new("media_detached", "媒体呈现器已释放。"))?;
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
                    return Err(CoreError::new("media_decoder", "原生解码器拒绝媒体输入。"));
                }
                tokio::select! {
                    _ = self.cancellation.cancelled() => return Err(CoreError::new("media_ended", "媒体输入已结束。")),
                    _ = ready, if owned => {},
                    _ = tokio::time::sleep(Duration::from_millis(2)), if !owned => {},
                }
            }
        };
        tokio::time::timeout(Duration::from_secs(3), send)
            .await
            .map_err(|_| CoreError::new("media_stall", "原生解码器未及时读取媒体输入。"))?
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
    fn view(&self, generation: u64) -> Value {
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        json!({"sourceId":self.id,"relayId":self.id,"generation":generation,"container":"packet","kind":if self.codec == CODEC_PCM_S16LE {"audio"} else {"video"},"codec":codec_name(self.codec),"width":state.dimensions.0,"height":state.dimensions.1,"attachAddress":interop_media_attach as *const () as usize as u64,"detachAddress":interop_media_detach as *const () as usize as u64,"status":if state.closed {"closed"} else if state.sink.is_some() {"streaming"} else {"waiting"},"packets":state.packets,"bytes":state.bytes})
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

/// Takes ownership of the copied function table only, never the foreign context.
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
/// `id` is readable for `length` bytes and `sink` points to an aligned live v1
/// table. Context/callback remain valid until detach returns. No callbacks may
/// call these registry functions. This validates values, not arbitrary pointers.
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
/// `id` remains readable for `length` bytes until this function returns.
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

#[derive(Default)]
pub struct MediaStreams;
impl MediaStreams {
    pub async fn command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        let id = params["sourceId"]
            .as_str()
            .or_else(|| params["relayId"].as_str())
            .ok_or_else(|| CoreError::new("invalid_endpoint", "缺少媒体源标识。"))?;
        let Some(source) = lookup(id) else {
            if command == "media.close" {
                return Ok(json!({"closed":true}));
            }
            return Err(CoreError::new("media_ended", "媒体输入已结束。"));
        };
        match command {
            "media.open" => {
                let generation = params["generation"]
                    .as_u64()
                    .filter(|g| *g > 0)
                    .unwrap_or(1);
                if params["kind"]
                    != if source.codec == CODEC_PCM_S16LE {
                        "audio"
                    } else {
                        "video"
                    }
                {
                    return Err(CoreError::new("invalid_endpoint", "媒体源类型不一致。"));
                }
                Ok(source.view(generation))
            }
            "media.status" => {
                let generation = source
                    .state
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .generation;
                Ok(source.view(generation))
            }
            "media.close" => {
                source.finish();
                source.cancellation.cancel();
                Ok(json!({"closed":true}))
            }
            _ => Err(CoreError::new("unknown_command", "未知媒体传输操作。")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        Barrier,
        atomic::{AtomicUsize, Ordering},
    };

    type CapturedEvent = (u32, u64, Vec<u8>, i64, u32);
    #[derive(Default)]
    struct Capture {
        events: Mutex<Vec<CapturedEvent>>,
        busy: AtomicUsize,
        entered: Option<Arc<Barrier>>,
        release: Option<Arc<Barrier>>,
    }
    unsafe extern "C" fn capture(
        context: *mut c_void,
        event: u32,
        generation: u64,
        _codec: u32,
        _width: u32,
        _height: u32,
        data: *const u8,
        len: usize,
        pts: i64,
        flags: u32,
    ) -> i32 {
        let capture = unsafe { &*(context as *const Capture) };
        if event == EVENT_PACKET {
            if let Some(barrier) = &capture.entered {
                barrier.wait();
            }
            if let Some(barrier) = &capture.release {
                barrier.wait();
            }
        }
        if capture.busy.load(Ordering::SeqCst) > 0 {
            capture.busy.fetch_sub(1, Ordering::SeqCst);
            return 1;
        }
        let bytes = if len == 0 {
            Vec::new()
        } else {
            unsafe { std::slice::from_raw_parts(data, len) }.to_vec()
        };
        capture
            .events
            .lock()
            .unwrap()
            .push((event, generation, bytes, pts, flags));
        0
    }
    fn source() -> Arc<MediaSource> {
        MediaSource::register(
            format!(
                "{}{}",
                uuid::Uuid::new_v4().simple(),
                uuid::Uuid::new_v4().simple()
            ),
            1,
            640,
            480,
            CancellationToken::new(),
        )
        .unwrap()
    }
    fn sink(capture: &mut Capture) -> MediaSinkV1 {
        MediaSinkV1 {
            abi_version: 1,
            struct_size: std::mem::size_of::<MediaSinkV1>() as u32,
            context: (capture as *mut Capture).cast(),
            event: Some(self::capture),
        }
    }
    #[tokio::test]
    async fn packets_preserve_bytes_pts_generation_and_retry_without_duplication() {
        let source = source();
        let mut capture = Box::new(Capture::default());
        assert_eq!(attach(&source.id, 7, sink(&mut capture)), 0);
        source.wait_attached().await.unwrap();
        capture.busy.store(2, Ordering::SeqCst);
        source.configure(640, 480, b"annex-b-config").await.unwrap();
        source
            .packet(b"compressed-packet", 9_876_543, true)
            .await
            .unwrap();
        source.finish();
        source.finish();
        let events = capture.events.lock().unwrap();
        assert_eq!(events.len(), 3);
        assert_eq!(
            events[0],
            (EVENT_CONFIGURE, 7, b"annex-b-config".to_vec(), 0, 0)
        );
        assert_eq!(
            events[1],
            (
                EVENT_PACKET,
                7,
                b"compressed-packet".to_vec(),
                9_876_543,
                FLAG_KEYFRAME
            )
        );
        assert_eq!(events[2].0, EVENT_END);
        assert_eq!(source.view(7)["packets"], 1);
    }
    #[test]
    fn detach_waits_for_admitted_callback_and_revokes_late_delivery() {
        let source = source();
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let mut capture = Box::new(Capture {
            entered: Some(entered.clone()),
            release: Some(release.clone()),
            ..Default::default()
        });
        assert_eq!(attach(&source.id, 4, sink(&mut capture)), 0);
        let producer = source.clone();
        let sending =
            std::thread::spawn(move || producer.invoke(EVENT_PACKET, (640, 480), b"frame", 1, 1));
        entered.wait();
        let id = source.id.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        let detaching = std::thread::spawn(move || {
            let result = detach(&id, 4);
            tx.send(result).unwrap();
        });
        assert!(rx.recv_timeout(Duration::from_millis(30)).is_err());
        release.wait();
        assert!(sending.join().unwrap().unwrap());
        assert_eq!(rx.recv_timeout(Duration::from_secs(1)).unwrap(), 0);
        detaching.join().unwrap();
        assert_eq!(
            source
                .invoke(EVENT_PACKET, (640, 480), b"late", 2, 0)
                .unwrap_err()
                .code,
            "media_ended"
        );
        assert!(source.cancellation.is_cancelled());
    }
    #[tokio::test]
    async fn packet_endpoint_is_process_local_and_old_detach_cannot_end_new_output() {
        let source = source();
        let streams = MediaStreams;
        let endpoint = streams
            .command(
                "media.open",
                &json!({"sourceId":source.id,"kind":"video","generation":9}),
            )
            .await
            .unwrap();
        assert!(endpoint.get("url").is_none());
        assert_eq!(endpoint["container"], "packet");
        assert!(endpoint["attachAddress"].as_u64().unwrap() > 0);
        assert_eq!(endpoint["relayId"], source.id);
        assert_eq!(
            streams
                .command("media.open", &json!({"sourceId":source.id,"kind":"audio"}))
                .await
                .unwrap_err()
                .code,
            "invalid_endpoint"
        );
        let mut capture = Box::new(Capture::default());
        assert_eq!(attach(&source.id, 9, sink(&mut capture)), 0);
        assert_eq!(detach(&source.id, 8), -3);
        source.packet(b"still-live", 123, false).await.unwrap();
        assert!(!source.cancellation.is_cancelled());
        assert_eq!(detach(&source.id, 9), 0);
    }
    #[tokio::test]
    async fn stalled_native_input_fails_without_unbounded_queued_packets() {
        let source = source();
        let mut capture = Box::new(Capture::default());
        capture.busy.store(usize::MAX, Ordering::SeqCst);
        assert_eq!(attach(&source.id, 1, sink(&mut capture)), 0);
        let started = std::time::Instant::now();
        assert_eq!(
            source
                .packet(b"one-retained-packet", 0, true)
                .await
                .unwrap_err()
                .code,
            "media_stall"
        );
        assert!(started.elapsed() < Duration::from_secs(4));
        assert_eq!(source.view(1)["packets"], 0);
        detach(&source.id, 1);
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use std::{
        pin::Pin,
        task::{Context, Poll},
    };
    use tokio::io::{AsyncRead, AsyncWriteExt, ReadBuf};

    struct Observer {
        sender: Mutex<Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>>,
    }
    unsafe extern "C" fn observe(
        context: *mut c_void,
        event: u32,
        _generation: u64,
        _codec: u32,
        width: u32,
        height: u32,
        data: *const u8,
        len: usize,
        pts: i64,
        flags: u32,
    ) -> i32 {
        let observer = unsafe { &*(context as *const Observer) };
        let mut sender = observer.sender.lock().unwrap();
        if event == EVENT_END {
            sender.take();
            return 0;
        }
        let mut bytes = Vec::new();
        if event == EVENT_CONFIGURE && width != 0 {
            bytes.extend_from_slice(&0x8000_0000u32.to_be_bytes());
            bytes.extend_from_slice(&width.to_be_bytes());
            bytes.extend_from_slice(&height.to_be_bytes());
        }
        if event == EVENT_PACKET || len > 0 {
            let bits = if event == EVENT_CONFIGURE {
                1u64 << 62
            } else {
                (pts as u64)
                    | if flags & FLAG_KEYFRAME != 0 {
                        1u64 << 61
                    } else {
                        0
                    }
            };
            bytes.extend_from_slice(&bits.to_be_bytes());
            bytes.extend_from_slice(&(len as u32).to_be_bytes());
            if len > 0 {
                bytes.extend_from_slice(unsafe { std::slice::from_raw_parts(data, len) });
            }
        }
        sender
            .as_ref()
            .map_or(-1, |sender| if sender.send(bytes).is_ok() { 0 } else { -1 })
    }
    pub(crate) struct Reader {
        stream: tokio::io::DuplexStream,
        id: String,
        generation: u64,
        _observer: Box<Observer>,
    }
    impl Reader {
        pub(crate) fn attach(id: &str, generation: u64) -> Self {
            let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
            let (stream, mut output) = tokio::io::duplex(256 * 1024);
            tokio::spawn(async move {
                while let Some(bytes) = receiver.recv().await {
                    if output.write_all(&bytes).await.is_err() {
                        break;
                    }
                }
            });
            let mut observer = Box::new(Observer {
                sender: Mutex::new(Some(sender)),
            });
            let sink = MediaSinkV1 {
                abi_version: 1,
                struct_size: std::mem::size_of::<MediaSinkV1>() as u32,
                context: (&mut *observer as *mut Observer).cast(),
                event: Some(observe),
            };
            assert_eq!(attach(id, generation, sink), 0);
            Self {
                stream,
                id: id.to_owned(),
                generation,
                _observer: observer,
            }
        }
    }
    impl AsyncRead for Reader {
        fn poll_read(
            mut self: Pin<&mut Self>,
            context: &mut Context<'_>,
            buffer: &mut ReadBuf<'_>,
        ) -> Poll<std::io::Result<()>> {
            Pin::new(&mut self.stream).poll_read(context, buffer)
        }
    }
    impl Drop for Reader {
        fn drop(&mut self) {
            detach(&self.id, self.generation);
        }
    }
}
