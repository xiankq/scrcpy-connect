//! 仅接收媒体包的 FFmpeg 解码器。Flutter 适配器拥有纹理和音频设备；
//! 本 crate 拥有包准入、解码、回退及媒体源生命周期。

pub mod api;
mod backend;
mod controls;
mod frb_generated;
mod image;
mod pcm;

/// 本机解码与像素转换的资源上限，不限制媒体来源协议所能表达的尺寸。
const MAX_VIDEO_DIMENSION: u32 = 16 * 1024;

use image::{Conversion, Frame};

use backend::{codec_id, Backend};
mod packet;

#[cfg(test)]
use packet::{GopHistory, HISTORY_MAX_BYTES, HISTORY_MAX_PACKETS, MAX_PACKETS};
use packet::{Packet, PacketBytes, PacketQueue, Storage, MAX_BYTES};

mod ff {
    #![allow(
        non_camel_case_types,
        non_upper_case_globals,
        non_snake_case,
        dead_code,
        clippy::type_complexity
    )]
    include!(concat!(env!("OUT_DIR"), "/ffmpeg.rs"));
}

use std::{
    ffi::{c_char, c_int, c_void, CStr, CString},
    ptr, slice,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    thread::{self, JoinHandle},
};

struct SourceWaker {
    context: *mut c_void,
    wake: ff::mc_wake_fn,
    release: ff::mc_release_fn,
}
unsafe impl Send for SourceWaker {}
impl Drop for SourceWaker {
    fn drop(&mut self) {
        if let Some(release) = self.release {
            unsafe {
                release(self.context);
            }
        }
    }
}
impl SourceWaker {
    fn notify(&self) {
        if let Some(wake) = self.wake {
            unsafe {
                wake(self.context);
            }
        }
    }
}
struct Attachment {
    source: CString,
    detach: ff::mc_detach_fn,
}
struct Shared {
    status: ff::mc_status,
    packets: PacketQueue,
    stopping: bool,
    latest: *mut ff::AVFrame,
    window_request: u64,
    window_applied: u64,
    next_window: usize,
    present_requested: bool,
    audio_control_request: u64,
    audio_control_applied: u64,
    ending: bool,
    source_waker: Option<SourceWaker>,
    audio_clock_generation: Option<u64>,
    audio_clock_base: u64,
    audio_pts_origin: Option<i64>,
}
impl Drop for Shared {
    fn drop(&mut self) {
        unsafe {
            ff::av_frame_free(&mut self.latest);
        }
    }
}
struct Decoder {
    control_id: u64,
    config: ff::mc_config,
    #[cfg_attr(target_os = "android", allow(dead_code))]
    requested_device: String,
    shared: Mutex<Shared>,
    wake: Condvar,
    attachment: Mutex<Option<Attachment>>,
    native_window: AtomicUsize,
    paused: AtomicBool,
    volume: AtomicU64,
    worker: Mutex<Option<JoinHandle<()>>>,
    conversion: Mutex<Conversion>,
}
// 配置和回调指针不可变；FFmpeg 上下文仅由工作线程访问，
// 共享帧及转换上下文分别受其互斥锁保护。
unsafe impl Send for Decoder {}
unsafe impl Sync for Decoder {}

fn text(target: &mut [c_char], value: &str) {
    target.fill(0);
    let length = target.len().saturating_sub(1).min(value.len());
    for (out, input) in target.iter_mut().zip(value.as_bytes()).take(length) {
        *out = *input as c_char;
    }
}
unsafe fn string(value: *const c_char) -> String {
    if value.is_null() {
        String::new()
    } else {
        CStr::from_ptr(value).to_string_lossy().into_owned()
    }
}
fn error(decoder: &Decoder, code: c_int, stage: &str) {
    let mut message = [0 as c_char; 128];
    unsafe {
        ff::av_strerror(code, message.as_mut_ptr(), message.len());
    }
    let mut shared = decoder.shared.lock().unwrap();
    shared.status.error_code = code;
    text(
        &mut shared.status.error,
        &format!("{stage}: {}", unsafe { string(message.as_ptr()) }),
    );
}
fn clear_error(status: &mut ff::mc_status) {
    status.error_code = 0;
    status.error.fill(0);
}

unsafe fn update_audio_clock(decoder: &Decoder) {
    if let Some(callback) = decoder.config.audio_state {
        let mut state: ff::mc_audio_state = std::mem::zeroed();
        if callback(decoder.config.user, &mut state) == 0 {
            let mut shared = decoder.shared.lock().unwrap();
            if shared.audio_clock_generation != Some(state.generation) {
                shared.audio_clock_base = shared.status.audio_played_frames;
                shared.audio_clock_generation = Some(state.generation);
            }
            shared.status.audio_played_frames =
                shared.audio_clock_base.saturating_add(state.played_frames);
            shared.status.audio_queued_frames = state.queued_frames;
            shared.status.position_us = shared.audio_pts_origin.unwrap_or(0).saturating_add(
                (shared.status.audio_played_frames.saturating_mul(1_000_000) / 48_000)
                    .min(i64::MAX as u64) as i64,
            );
        }
    }
}

unsafe extern "C" fn set_source_waker(
    context: *mut c_void,
    user: *mut c_void,
    wake: ff::mc_wake_fn,
    release: ff::mc_release_fn,
) {
    let decoder = &*(context as *const Decoder);
    decoder.shared.lock().unwrap().source_waker = Some(SourceWaker {
        context: user,
        wake,
        release,
    });
}

unsafe extern "C" fn event_owned(
    context: *mut c_void,
    kind: u32,
    generation: u64,
    codec: u32,
    width: u32,
    height: u32,
    data: *mut u8,
    size: usize,
    allocation_size: usize,
    owner: *mut c_void,
    release: ff::mc_release_fn,
    pts: i64,
    flags: u32,
) -> c_int {
    if context.is_null()
        || data.is_null()
        || release.is_none()
        || kind != 2
        || size == 0
        || size > MAX_BYTES
        || allocation_size < size + 64
        || width > MAX_VIDEO_DIMENSION
        || height > MAX_VIDEO_DIMENSION
    {
        return -1;
    }
    let decoder = &*(context as *const Decoder);
    if generation != decoder.config.generation || (codec == 100 && !size.is_multiple_of(4)) {
        return -1;
    }
    let mut shared = decoder.shared.lock().unwrap();
    if shared.stopping || shared.ending || shared.status.ended != 0 {
        return -1;
    }
    if decoder.config.codec == 100 && decoder.paused.load(Ordering::Acquire) {
        release.unwrap()(owner);
        return 0;
    }
    if !shared.packets.enqueue(size, || Packet {
        event: kind,
        codec,
        width,
        height,
        flags,
        pts,
        data: Arc::new(PacketBytes {
            storage: Storage::Foreign {
                data,
                size: allocation_size,
                owner,
                release,
            },
            length: size,
        }),
    }) {
        return 1;
    }
    decoder.wake.notify_one();
    0
}

unsafe fn run(pointer: usize) {
    let decoder = &*(pointer as *const Decoder);
    struct AudioClose<'a>(&'a Decoder);
    impl Drop for AudioClose<'_> {
        fn drop(&mut self) {
            if self.0.config.codec == 100 {
                if let Some(close) = self.0.config.audio_close {
                    unsafe {
                        close(self.0.config.user);
                    }
                }
            }
        }
    }
    let _audio_close = AudioClose(decoder);
    let Some(mut backend) = Backend::new(decoder) else {
        error(decoder, ff::MC_ENOMEM, "allocate decode buffers");
        let mut shared = decoder.shared.lock().unwrap();
        shared.stopping = true;
        if let Some(waker) = &shared.source_waker {
            waker.notify();
        }
        // 纹理和 PCM 控制调用可能已经在等待工作线程，退出前必须唤醒。
        decoder.wake.notify_all();
        return;
    };
    let mut regulator = pcm::Regulator::default();
    loop {
        let mut packet = {
            let mut shared = decoder.shared.lock().unwrap();
            while !shared.stopping
                && shared.packets.is_empty()
                && shared.window_request == shared.window_applied
                && !shared.present_requested
                && !shared.ending
                && shared.audio_control_request == shared.audio_control_applied
            {
                shared = decoder.wake.wait(shared).unwrap();
            }
            if shared.stopping {
                break;
            }
            if shared.audio_control_request != shared.audio_control_applied {
                let sequence = shared.audio_control_request;
                let paused = decoder.paused.load(Ordering::Acquire);
                drop(shared);
                regulator.reset();
                update_audio_clock(decoder);
                if let Some(callback) = decoder.config.audio_pause {
                    callback(decoder.config.user, paused as c_int);
                }
                update_audio_clock(decoder);
                let mut shared = decoder.shared.lock().unwrap();
                shared.audio_control_applied = sequence;
                decoder.wake.notify_all();
                continue;
            }
            if shared.window_request != shared.window_applied {
                let sequence = shared.window_request;
                let window = shared.next_window;
                let previous = decoder.native_window.load(Ordering::Acquire);
                if previous == window {
                    shared.window_applied = sequence;
                    decoder.wake.notify_all();
                    continue;
                }
                ff::av_frame_unref(shared.latest);
                drop(shared);
                backend.set_window(window);
                let mut shared = decoder.shared.lock().unwrap();
                shared.window_applied = sequence;
                decoder.wake.notify_all();
                continue;
            }
            if shared.present_requested {
                shared.present_requested = false;
                drop(shared);
                if !decoder.paused.load(Ordering::Acquire) {
                    if let Some(callback) = decoder.config.frame_ready {
                        callback(decoder.config.user);
                    }
                }
                continue;
            }
            if shared.packets.is_empty() && shared.ending {
                shared.ending = false;
                shared.status.ended = 1;
                continue;
            }
            if decoder.config.codec == 100 && decoder.config.audio_state.is_some() {
                shared.status.audio_dropped_frames += shared.packets.trim_pcm();
            }
            let packet = shared.packets.pop().unwrap();
            if let Some(waker) = &shared.source_waker {
                waker.notify();
            }
            packet
        };
        if packet.event == 3 {
            decoder.shared.lock().unwrap().status.ended = 1;
            continue;
        }
        if decoder.config.codec != 100 {
            backend.process(packet);
            continue;
        }
        if packet.event != 2 || decoder.paused.load(Ordering::Acquire) {
            continue;
        }
        {
            let mut shared = decoder.shared.lock().unwrap();
            shared.audio_pts_origin.get_or_insert(packet.pts);
        }
        let volume = f64::from_bits(decoder.volume.load(Ordering::Relaxed));
        // 音频包不进入 GOP 历史，取得唯一 Arc 后可以就地调整音量。
        if volume != 1.0 {
            let bytes = Arc::get_mut(&mut packet.data).unwrap();
            for sample in bytes.storage[..bytes.length].as_chunks_mut::<2>().0 {
                let value = (i16::from_le_bytes([sample[0], sample[1]]) as f64 * volume)
                    .clamp(-32768.0, 32767.0) as i16;
                sample.copy_from_slice(&value.to_le_bytes());
            }
        }
        let mut clock: ff::mc_audio_state = std::mem::zeroed();
        let device_clock = decoder
            .config
            .audio_state
            .is_some_and(|callback| callback(decoder.config.user, &mut clock) == 0);
        let data = if device_clock {
            regulator.process(
                &packet.data.storage[..packet.data.length],
                clock.queued_frames,
                clock.generation,
            )
        } else {
            &packet.data.storage[..packet.data.length]
        };
        let mut offset = 0;
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        while offset < data.len() {
            if decoder.paused.load(Ordering::Acquire) {
                break;
            }
            if decoder.shared.lock().unwrap().stopping {
                break;
            }
            let written = decoder
                .config
                .pcm
                .map(|callback| {
                    callback(
                        decoder.config.user,
                        data.as_ptr().add(offset),
                        data.len() - offset,
                    )
                })
                .unwrap_or(-1);
            if written < 0 || written as usize > data.len() - offset || written % 4 != 0 {
                error(decoder, ff::MC_EXTERNAL, "audio output");
                break;
            }
            if written == 0 {
                if std::time::Instant::now() > deadline {
                    error(
                        decoder,
                        ff::MC_EXTERNAL,
                        "audio output stalled with pending samples",
                    );
                    break;
                }
                let shared = decoder.shared.lock().unwrap();
                let _ = decoder
                    .wake
                    .wait_timeout(shared, std::time::Duration::from_millis(2))
                    .unwrap();
                continue;
            }
            offset += written as usize;
            {
                let mut shared = decoder.shared.lock().unwrap();
                shared.status.bytes_written += written as u64;
                shared.status.native_ready = 1;
                clear_error(&mut shared.status);
                // 提交位置仅供旧回调使用；存在设备时钟时立即用实际播放水位替代。
                shared.status.position_us = packet
                    .pts
                    .saturating_add(offset as i64 * 1_000_000 / 192_000);
            }
            update_audio_clock(decoder);
        }
    }
}

unsafe extern "C" fn event(
    context: *mut c_void,
    kind: u32,
    generation: u64,
    codec: u32,
    width: u32,
    height: u32,
    data: *const u8,
    size: usize,
    pts: i64,
    flags: u32,
) -> c_int {
    if context.is_null() {
        return -1;
    }
    let decoder = &*(context as *const Decoder);
    if generation != decoder.config.generation
        || !(1..=3).contains(&kind)
        || size > MAX_BYTES
        || (kind == 2 && size == 0)
        || (size != 0 && data.is_null())
        || width > MAX_VIDEO_DIMENSION
        || height > MAX_VIDEO_DIMENSION
    {
        return -1;
    }
    if codec == 100 && kind == 2 && !size.is_multiple_of(4) {
        return -1;
    }
    let mut shared = decoder.shared.lock().unwrap();
    if shared.stopping {
        return -1;
    }
    if decoder.config.codec == 100 && kind == 2 && decoder.paused.load(Ordering::Acquire) {
        return 0;
    }
    if kind == 3 {
        shared.ending = true;
        decoder.wake.notify_one();
        return 0;
    }
    if shared.ending || shared.status.ended != 0 {
        return -1;
    }
    if !shared.packets.enqueue(size, || {
        let mut storage = Vec::with_capacity(size + ff::AV_INPUT_BUFFER_PADDING_SIZE as usize);
        if size != 0 {
            storage.extend_from_slice(slice::from_raw_parts(data, size));
        }
        storage.resize(size + ff::AV_INPUT_BUFFER_PADDING_SIZE as usize, 0);
        Packet {
            event: kind,
            codec,
            width,
            height,
            flags,
            pts,
            data: Arc::new(PacketBytes {
                storage: Storage::Local(storage),
                length: size,
            }),
        }
    }) {
        return 1;
    }
    decoder.wake.notify_one();
    0
}

unsafe fn decoder<'a>(value: *mut ff::mc_decoder) -> &'a Decoder {
    &*(value as *const Decoder)
}

/// # Safety
/// config 必须指向完整、已初始化的 mc_config。回调及 user 在销毁前持续有效；回调不得销毁解码器。
#[no_mangle]
pub unsafe extern "C" fn mc_create(config: *const ff::mc_config) -> *mut ff::mc_decoder {
    if config.is_null()
        || (*config).struct_size < std::mem::size_of::<ff::mc_config>() as u32
        || ((*config).codec != 100 && codec_id((*config).codec) == ff::AV_CODEC_ID_NONE)
        || (*config).width > MAX_VIDEO_DIMENSION
        || (*config).height > MAX_VIDEO_DIMENSION
    {
        return ptr::null_mut();
    }
    let mut status: ff::mc_status = std::mem::zeroed();
    status.hardware_verification = -1;
    status.width = (*config).width;
    status.height = (*config).height;
    if (*config).codec == 100 {
        text(&mut status.decoder_name, "pcm_s16le");
    }
    let latest = ff::av_frame_alloc();
    if latest.is_null() {
        return ptr::null_mut();
    }
    let Some(control_id) = controls::next_id() else {
        let mut latest = latest;
        ff::av_frame_free(&mut latest);
        return ptr::null_mut();
    };
    let value = Box::new(Decoder {
        control_id,
        config: *config,
        requested_device: string((*config).hardware_device),
        shared: Mutex::new(Shared {
            status,
            packets: PacketQueue::default(),
            stopping: false,
            latest,
            window_request: 0,
            window_applied: 0,
            next_window: (*config).native_window as usize,
            present_requested: false,
            audio_control_request: 0,
            audio_control_applied: 0,
            ending: false,
            source_waker: None,
            audio_clock_generation: None,
            audio_clock_base: 0,
            audio_pts_origin: None,
        }),
        wake: Condvar::new(),
        attachment: Mutex::new(None),
        native_window: AtomicUsize::new((*config).native_window as usize),
        paused: AtomicBool::new(false),
        volume: AtomicU64::new(1.0_f64.to_bits()),
        worker: Mutex::new(None),
        conversion: Mutex::new(Conversion::default()),
    });
    let pointer = Box::into_raw(value);
    let address = pointer as usize;
    match thread::Builder::new()
        .name("media-codec".into())
        .spawn(move || run(address))
    {
        Ok(worker) => {
            *(*pointer).worker.lock().unwrap() = Some(worker);
            controls::register(control_id, pointer);
            pointer as *mut ff::mc_decoder
        }
        Err(_) => {
            drop(Box::from_raw(pointer));
            ptr::null_mut()
        }
    }
}
/// # Safety
/// value 必须为空或指向本库存活的解码器，调用期间不得销毁。
#[no_mangle]
pub unsafe extern "C" fn mc_control_id(value: *mut ff::mc_decoder) -> u64 {
    if value.is_null() {
        0
    } else {
        decoder(value).control_id
    }
}

/// 返回同一媒体库中的 FRB 锚点，同时保留静态链接所需的桥接符号。
#[no_mangle]
pub extern "C" fn mc_frb_anchor() -> *const c_void {
    frb_generated::frb_get_rust_content_hash as *const () as *const c_void
}
/// # Safety
/// value 必须是存活的解码器，source 为有效 C 字符串，attach/detach 为匹配 ABI 的函数地址；detach 返回前必须结束全部媒体源回调。
#[no_mangle]
pub unsafe extern "C" fn mc_attach(
    value: *mut ff::mc_decoder,
    source: *const c_char,
    attach: usize,
    detach: usize,
) -> c_int {
    if value.is_null() || source.is_null() || attach == 0 || detach == 0 {
        return -1;
    }
    let decoder = decoder(value);
    let mut attachment = decoder.attachment.lock().unwrap();
    if attachment.is_some() {
        return -1;
    }
    let source = CStr::from_ptr(source).to_owned();
    if source.as_bytes().len() > 256 {
        return -1;
    }
    let sink = ff::mc_sink_v2 {
        base: ff::mc_sink_v1 {
            abi_version: 2,
            struct_size: std::mem::size_of::<ff::mc_sink_v2>() as u32,
            context: value as *mut c_void,
            event: Some(event),
        },
        event_owned: Some(event_owned),
        set_waker: Some(set_source_waker),
    };
    let attach: unsafe extern "C" fn(*const u8, usize, u64, *const ff::mc_sink_v1) -> c_int =
        std::mem::transmute(attach);
    let mut result = attach(
        source.as_ptr() as *const u8,
        source.as_bytes().len(),
        decoder.config.generation,
        &sink.base,
    );
    if result != 0 {
        let legacy = ff::mc_sink_v1 {
            abi_version: 1,
            struct_size: std::mem::size_of::<ff::mc_sink_v1>() as u32,
            ..sink.base
        };
        result = attach(
            source.as_ptr() as *const u8,
            source.as_bytes().len(),
            decoder.config.generation,
            &legacy,
        );
    }
    if result == 0 {
        *attachment = Some(Attachment {
            source,
            detach: Some(std::mem::transmute::<
                usize,
                unsafe extern "C" fn(*const u8, usize, u64) -> c_int,
            >(detach)),
        });
    }
    result
}
/// # Safety
/// 非空 value 必须指向存活的解码器，非空 out 必须指向可写的完整 mc_status；调用期间不得销毁解码器。
#[no_mangle]
pub unsafe extern "C" fn mc_get_status(value: *mut ff::mc_decoder, out: *mut ff::mc_status) {
    if !value.is_null() && !out.is_null() {
        *out = decoder(value).shared.lock().unwrap().status;
    }
}
/// # Safety
/// 非空 value 必须指向存活的解码器；不得从其输出回调调用此同步屏障，也不得与销毁并发。
#[no_mangle]
pub unsafe extern "C" fn mc_set_paused(value: *mut ff::mc_decoder, paused: c_int) {
    if value.is_null() {
        return;
    }
    let decoder = decoder(value);
    let was = decoder.paused.swap(paused != 0, Ordering::AcqRel);
    {
        let mut shared = decoder.shared.lock().unwrap();
        shared.status.paused = (paused != 0) as c_int;
        if paused != 0 && decoder.config.codec == 100 {
            shared.packets.discard_data();
            if let Some(waker) = &shared.source_waker {
                waker.notify();
            }
        }
    }
    if decoder.config.codec == 100 && was != (paused != 0) {
        let mut shared = decoder.shared.lock().unwrap();
        shared.audio_control_request += 1;
        let sequence = shared.audio_control_request;
        decoder.wake.notify_all();
        while !shared.stopping && shared.audio_control_applied < sequence {
            shared = decoder.wake.wait(shared).unwrap();
        }
    }
    if was && paused == 0 && decoder.config.codec != 100 {
        decoder.shared.lock().unwrap().present_requested = true;
        decoder.wake.notify_one();
    }
}
/// # Safety
/// 非空 value 必须指向存活的解码器，window 按目标平台保持有效，直到替换屏障或销毁完成；不得从输出回调调用。
#[no_mangle]
pub unsafe extern "C" fn mc_set_native_window(value: *mut ff::mc_decoder, window: *mut c_void) {
    if value.is_null() {
        return;
    }
    let decoder = decoder(value);
    let mut shared = decoder.shared.lock().unwrap();
    shared.window_request += 1;
    let sequence = shared.window_request;
    shared.next_window = window as usize;
    decoder.wake.notify_all();
    while !shared.stopping && shared.window_applied < sequence {
        shared = decoder.wake.wait(shared).unwrap();
    }
}
/// # Safety
/// 非空 value 必须指向存活的解码器，且调用期间不得销毁。
#[no_mangle]
pub unsafe extern "C" fn mc_set_volume(value: *mut ff::mc_decoder, volume: f64) {
    if !value.is_null() {
        decoder(value).volume.store(
            if volume.is_finite() {
                volume.clamp(0.0, 1.0)
            } else {
                0.0
            }
            .to_bits(),
            Ordering::Relaxed,
        );
    }
}
/// # Safety
/// 非空 value 必须指向存活的解码器；返回的非空帧引用归调用方，最终须由 mc_release_frame 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_acquire_frame(value: *mut ff::mc_decoder) -> *mut ff::AVFrame {
    mc_acquire_frame_snapshot(value, ptr::null_mut())
}
/// # Safety
/// 非空 value 必须指向存活的解码器；非空 sequence 必须可写。返回的非空帧引用须由 mc_release_frame 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_acquire_frame_snapshot(
    value: *mut ff::mc_decoder,
    sequence: *mut u64,
) -> *mut ff::AVFrame {
    if value.is_null() {
        return ptr::null_mut();
    }
    let shared = decoder(value).shared.lock().unwrap();
    if !sequence.is_null() {
        *sequence = shared.status.frame_count;
    }
    if shared.latest.is_null() || (*shared.latest).format < 0 {
        ptr::null_mut()
    } else {
        ff::av_frame_clone(shared.latest)
    }
}
/// # Safety
/// 非空 value 必须指向存活的解码器；path/failure 为有效 C 字符串或空指针，调用期间不得销毁解码器。
#[no_mangle]
pub unsafe extern "C" fn mc_report_present(
    value: *mut ff::mc_decoder,
    sequence: u64,
    path: *const c_char,
    failure: *const c_char,
) {
    if value.is_null() {
        return;
    }
    let mut shared = decoder(value).shared.lock().unwrap();
    text(&mut shared.status.presentation_path, &string(path));
    text(&mut shared.status.presentation_error, &string(failure));
    if failure.is_null() {
        let sequence = if sequence == 0 {
            shared.status.frame_count
        } else {
            sequence
        };
        if sequence > shared.status.presented_sequence {
            shared.status.presented_frame_count += 1;
            shared.status.presented_sequence = sequence;
        }
    }
}
/// # Safety
/// frame 必须为空或本库返回且尚未释放的帧引用；同一引用只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn mc_release_frame(mut frame: *mut ff::AVFrame) {
    ff::av_frame_free(&mut frame);
}
/// # Safety
/// 非空 value 必须指向存活的解码器，out 指向可写的 mc_image；out 中已有图像须先释放，成功结果须用 mc_image_free 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_copy_rgba(value: *mut ff::mc_decoder, out: *mut ff::mc_image) -> c_int {
    mc_copy_rgba_scaled(value, 0, 0, out)
}
/// # Safety
/// 非空 value 必须指向存活的解码器，out 指向可写的 mc_image；out 中已有图像须先释放，成功结果须用 mc_image_free 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_copy_rgba_scaled(
    value: *mut ff::mc_decoder,
    max_width: u32,
    max_height: u32,
    out: *mut ff::mc_image,
) -> c_int {
    if value.is_null() || out.is_null() {
        return -1;
    }
    let mut conversion = decoder(value).conversion.lock().unwrap();
    let frame = Frame(mc_acquire_frame(value));
    conversion.copy(frame.0, max_width, max_height, ff::AV_PIX_FMT_RGBA, out)
}
/// # Safety
/// frame 必须为空或有效且在调用期间不被修改的 FFmpeg 帧，out 指向可写的 mc_image；成功结果须用 mc_image_free 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_copy_frame_rgba(
    frame: *mut ff::AVFrame,
    out: *mut ff::mc_image,
) -> c_int {
    Conversion::default().copy(frame, 0, 0, ff::AV_PIX_FMT_RGBA, out)
}
/// # Safety
/// frame 必须为空或有效且在调用期间不被修改的 FFmpeg 帧，out 指向可写的 mc_image；成功结果须用 mc_image_free 释放。
#[no_mangle]
pub unsafe extern "C" fn mc_copy_frame_bgra(
    frame: *mut ff::AVFrame,
    out: *mut ff::mc_image,
) -> c_int {
    Conversion::default().copy(frame, 0, 0, ff::AV_PIX_FMT_BGRA, out)
}
/// # Safety
/// image 必须为空或指向本库返回且尚未释放的 mc_image；调用期间不得与图像读取并发。
#[no_mangle]
pub unsafe extern "C" fn mc_image_free(image: *mut ff::mc_image) {
    image::free(image);
}
/// # Safety
/// 非空 value 必须是本库创建且尚未销毁的解码器；只能销毁一次，不得从输出回调调用。
/// FRB 控制借用会在释放前排空；其余 C ABI 操作不得与销毁并发。
#[no_mangle]
pub unsafe extern "C" fn mc_destroy(value: *mut ff::mc_decoder) {
    if value.is_null() {
        return;
    }
    let decoder = decoder(value);
    controls::revoke(decoder.control_id);
    if let Some(attachment) = decoder.attachment.lock().unwrap().take() {
        if let Some(detach) = attachment.detach {
            detach(
                attachment.source.as_ptr() as *const u8,
                attachment.source.as_bytes().len(),
                decoder.config.generation,
            );
        }
    }
    {
        let mut shared = decoder.shared.lock().unwrap();
        shared.stopping = true;
        decoder.wake.notify_all();
    }
    if let Some(worker) = decoder.worker.lock().unwrap().take() {
        let _ = worker.join();
    }
    drop(Box::from_raw(value as *mut Decoder));
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn allocation_failure_rejects_creation_and_releases_control_barriers() {
        // FFmpeg 分配上限属于进程全局状态，使用子进程隔离故障注入，
        // 避免影响并发运行的其他解码器测试。
        const CHILD: &str = "MEDIA_CODEC_TEST_ALLOCATION_CHILD";
        if std::env::var_os(CHILD).is_none() {
            let mut child = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "tests::allocation_failure_rejects_creation_and_releases_control_barriers",
                    "--nocapture",
                ])
                .env(CHILD, "1")
                .spawn()
                .unwrap();
            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
            loop {
                if let Some(status) = child.try_wait().unwrap() {
                    assert!(status.success(), "allocation failure child: {status}");
                    return;
                }
                if std::time::Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    panic!("control barrier waited for an exited worker");
                }
                thread::sleep(std::time::Duration::from_millis(5));
            }
        }
        unsafe {
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 100;
            ff::av_max_alloc(1);
            assert!(
                mc_create(&config).is_null(),
                "latest frame must be allocated"
            );
            ff::av_max_alloc(usize::MAX);
            let value = mc_create(&config);
            assert!(!value.is_null());
            // 执行真实初始化失败路径；正常工作线程没有输入，
            // 两个执行者仅通过加锁后的状态交互。
            ff::av_max_alloc(1);
            run(value as usize);
            mc_set_native_window(value, ptr::null_mut());
            mc_set_paused(value, 1);
            let mut status: ff::mc_status = std::mem::zeroed();
            mc_get_status(value, &mut status);
            assert_eq!(status.error_code, ff::MC_ENOMEM);
            ff::av_max_alloc(usize::MAX);
            mc_destroy(value);
        }
    }

    use std::time::{Duration, Instant};

    #[test]
    fn owned_packets_keep_the_buffer_and_end_survives_a_full_queue() {
        struct Output {
            state: Mutex<(bool, bool, usize)>,
            changed: Condvar,
        }
        struct Owner(Vec<u8>, Arc<AtomicUsize>);
        unsafe extern "C" fn release(owner: *mut c_void) {
            let owner = Box::from_raw(owner as *mut Owner);
            owner.1.fetch_add(1, Ordering::SeqCst);
        }
        unsafe extern "C" fn write(user: *mut c_void, bytes: *const u8, size: usize) -> i64 {
            let output = &*(user as *const Output);
            let mut state = output.state.lock().unwrap();
            if !state.0 {
                state.0 = true;
                state.2 = bytes as usize;
                output.changed.notify_all();
                while !state.1 {
                    state = output.changed.wait(state).unwrap();
                }
            }
            size as i64
        }
        unsafe {
            let output = Output {
                state: Mutex::new((false, false, 0)),
                changed: Condvar::new(),
            };
            let releases = Arc::new(AtomicUsize::new(0));
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 100;
            config.generation = 1;
            config.user = &output as *const _ as *mut c_void;
            config.pcm = Some(write);
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
            let mut owner = Box::new(Owner(vec![0; 68], releases.clone()));
            let address = owner.0.as_mut_ptr();
            assert_eq!(
                event_owned(
                    decoder.cast(),
                    2,
                    1,
                    100,
                    0,
                    0,
                    address,
                    4,
                    68,
                    Box::into_raw(owner).cast(),
                    Some(release),
                    0,
                    0
                ),
                0
            );
            {
                let state = output.state.lock().unwrap();
                let (state, timeout) = output
                    .changed
                    .wait_timeout_while(state, Duration::from_secs(2), |state| !state.0)
                    .unwrap();
                assert!(!timeout.timed_out());
                assert_eq!(
                    state.2, address as usize,
                    "owned delivery must preserve the allocation"
                );
            }
            for _ in 0..MAX_PACKETS {
                assert_eq!(
                    event(decoder.cast(), 2, 1, 100, 0, 0, [0u8; 4].as_ptr(), 4, 0, 0),
                    0
                );
            }
            let mut rejected = Box::new(Owner(vec![0; 68], releases.clone()));
            let pointer = rejected.0.as_mut_ptr();
            let rejected = Box::into_raw(rejected);
            assert_eq!(
                event_owned(
                    decoder.cast(),
                    2,
                    1,
                    100,
                    0,
                    0,
                    pointer,
                    4,
                    68,
                    rejected.cast(),
                    Some(release),
                    0,
                    0
                ),
                1
            );
            assert_eq!(
                releases.load(Ordering::SeqCst),
                0,
                "retry retains producer ownership"
            );
            release(rejected.cast());
            assert_eq!(
                event(decoder.cast(), 3, 1, 100, 0, 0, ptr::null(), 0, 0, 0),
                0
            );
            output.state.lock().unwrap().1 = true;
            output.changed.notify_all();
            let deadline = Instant::now() + Duration::from_secs(2);
            let mut status: ff::mc_status = std::mem::zeroed();
            loop {
                mc_get_status(decoder, &mut status);
                if status.ended != 0 || Instant::now() > deadline {
                    break;
                }
                thread::sleep(Duration::from_millis(1));
            }
            mc_destroy(decoder);
            assert_eq!(
                status.ended, 1,
                "END cannot be rejected by packet backpressure"
            );
            assert_eq!(status.bytes_written, ((MAX_PACKETS + 1) * 4) as u64);
            assert_eq!(
                releases.load(Ordering::SeqCst),
                2,
                "each allocation is released exactly once"
            );
        }
    }

    #[test]
    fn pcm_partial_write_preserves_the_tail() {
        unsafe extern "C" fn write(user: *mut c_void, bytes: *const u8, size: usize) -> i64 {
            let output = &*(user as *const Mutex<Vec<u8>>);
            let count = size.min(4);
            output
                .lock()
                .unwrap()
                .extend_from_slice(slice::from_raw_parts(bytes, count));
            count as i64
        }
        unsafe {
            let output = Mutex::new(Vec::<u8>::new());
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 100;
            config.generation = 1;
            config.user = &output as *const _ as *mut c_void;
            config.pcm = Some(write);
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
            let bytes: Vec<u8> = (0..32).collect();
            assert_eq!(
                event(
                    decoder.cast(),
                    2,
                    1,
                    100,
                    0,
                    0,
                    bytes.as_ptr(),
                    bytes.len(),
                    1_000,
                    0
                ),
                0
            );
            assert_eq!(
                event(decoder.cast(), 3, 1, 100, 0, 0, ptr::null(), 0, 0, 0),
                0
            );
            let deadline = Instant::now() + Duration::from_secs(2);
            let mut status: ff::mc_status = std::mem::zeroed();
            loop {
                mc_get_status(decoder, &mut status);
                if status.ended != 0 || Instant::now() > deadline {
                    break;
                }
                thread::sleep(Duration::from_millis(1));
            }
            mc_destroy(decoder);
            assert_eq!(
                *output.lock().unwrap(),
                bytes,
                "the real PCM worker must retry an accepted prefix's remaining samples"
            );
            assert_eq!(status.bytes_written, 32);
        }
    }

    #[test]
    fn overflow_never_replays_a_partial_gop_and_recovers_at_next_keyframe() {
        let packet = |length, flags, pts| Packet {
            event: 2,
            codec: 1,
            width: 16,
            height: 16,
            flags,
            pts,
            data: Arc::new(PacketBytes {
                storage: Storage::Local(Vec::new()),
                length,
            }),
        };
        let mut history = GopHistory::default();
        history.record(&packet(1, 0, 0));
        assert!(
            history.replay().is_none(),
            "a fresh decoder needs a keyframe"
        );
        history.record(&packet(HISTORY_MAX_BYTES, 1, 1));
        assert_eq!(history.replay().unwrap().len(), 1);
        history.record(&packet(1, 0, 2));
        assert!(history.replay().is_none(), "overflow loses the keyframe");
        for pts in 3..10 {
            history.record(&packet(1, 0, pts));
            assert!(history.replay().is_none(), "P suffix cannot revive old GOP");
        }
        history.record(&packet(2, 1, 10));
        history.record(&packet(3, 0, 11));
        let replay = history.replay().unwrap();
        assert_eq!(replay.iter().map(|p| p.pts).collect::<Vec<_>>(), [10, 11]);
        history.clear();
        history.record(&packet(1, 0, 12));
        assert!(
            history.replay().is_none(),
            "configuration resets GOP continuity"
        );
    }

    #[test]
    fn tiny_packets_cannot_grow_gop_history_without_bound() {
        let packet = |flags| Packet {
            event: 2,
            codec: 1,
            width: 16,
            height: 16,
            flags,
            pts: 0,
            data: Arc::new(PacketBytes {
                storage: Storage::Local(vec![0]),
                length: 1,
            }),
        };
        let mut history = GopHistory::default();
        history.record(&packet(1));
        for _ in 1..HISTORY_MAX_PACKETS {
            history.record(&packet(0));
        }
        assert_eq!(history.replay().unwrap().len(), HISTORY_MAX_PACKETS);
        history.record(&packet(0));
        assert!(history.replay().is_none(), "包数溢出须丢弃整个 GOP");
        history.record(&packet(0));
        assert!(history.replay().is_none(), "P 帧后缀不能恢复历史");
        history.record(&packet(1));
        assert_eq!(history.replay().unwrap().len(), 1);
    }

    #[test]
    fn decoder_rejects_oversized_dimensions_at_creation_and_both_source_abis() {
        unsafe extern "C" fn release(context: *mut c_void) {
            let released = &*(context as *const AtomicUsize);
            released.fetch_add(1, Ordering::SeqCst);
        }
        unsafe {
            for (width, height) in [(16385, 1), (1, 16385)] {
                let mut config: ff::mc_config = std::mem::zeroed();
                config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
                config.codec = 4;
                config.generation = 1;
                config.hardware_device = c"none".as_ptr();
                config.width = width;
                config.height = height;
                assert!(mc_create(&config).is_null());

                config.width = 0;
                config.height = 0;
                let decoder = mc_create(&config);
                assert!(!decoder.is_null());
                let mut bytes = [0u8; 65];
                let released = AtomicUsize::new(0);
                let borrowed = event(decoder.cast(), 1, 1, 4, width, height, ptr::null(), 0, 0, 0);
                let owned = event_owned(
                    decoder.cast(),
                    2,
                    1,
                    4,
                    width,
                    height,
                    bytes.as_mut_ptr(),
                    1,
                    bytes.len(),
                    (&released as *const AtomicUsize).cast_mut().cast(),
                    Some(release),
                    0,
                    0,
                );
                mc_destroy(decoder);
                assert_eq!(borrowed, -1, "旧 ABI 配置不能越过解码器上限");
                assert_eq!(owned, -1, "所有权 ABI 数据不能越过解码器上限");
                assert_eq!(released.load(Ordering::SeqCst), 0, "拒绝时仍由来源持有负载");
            }
        }
    }

    #[test]
    fn legacy_source_rejects_empty_data_but_accepts_end() {
        unsafe {
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 100;
            config.generation = 1;
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
            let data = event(decoder.cast(), 2, 1, 100, 0, 0, ptr::null(), 0, 0, 0);
            let end = event(decoder.cast(), 3, 1, 100, 0, 0, ptr::null(), 0, 0, 0);
            mc_destroy(decoder);
            assert_eq!(data, -1, "数据事件必须包含负载");
            assert_eq!(end, 0, "结束事件保持零长度 ABI 语义");
        }
    }

    #[test]
    fn controls_borrow_platform_output_until_revoked() {
        unsafe {
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 4;
            config.generation = 1;
            config.hardware_device = c"none".as_ptr();
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
            let control_id = mc_control_id(decoder);
            assert!(control_id > 0);
            assert!(api::media_status(control_id).is_ok());
            api::media_set_paused(control_id, true).unwrap();
            assert!(api::media_status(control_id).unwrap().paused);
            api::media_set_paused(control_id, false).unwrap();
            api::media_set_volume(control_id, 0.25).unwrap();
            assert!(api::media_set_volume(control_id, f64::NAN).is_err());
            assert_eq!(
                event(decoder.cast(), 1, 1, 4, 16, 16, ptr::null(), 0, 0, 0),
                0
            );
            assert_eq!(
                event(decoder.cast(), 3, 1, 4, 16, 16, ptr::null(), 0, 0, 0),
                0
            );
            let deadline = Instant::now() + Duration::from_secs(5);
            let mut status: ff::mc_status = std::mem::zeroed();
            loop {
                mc_get_status(decoder, &mut status);
                if status.ended != 0 {
                    break;
                }
                assert!(Instant::now() < deadline, "configuration did not drain");
                thread::sleep(Duration::from_millis(1));
            }
            assert_eq!(status.error_code, 0);
            assert_eq!(status.frame_count, 0);
            assert_eq!(status.native_ready, 0);
            assert_eq!(status.hardware_accelerated, 0);
            assert_eq!(string(status.decoder_name.as_ptr()), "");
            let (borrowed_tx, borrowed_rx) = std::sync::mpsc::channel();
            let (release_tx, release_rx) = std::sync::mpsc::channel();
            let borrowing = thread::spawn(move || {
                controls::with_decoder(control_id, |_| {
                    borrowed_tx.send(()).unwrap();
                    release_rx.recv().unwrap();
                })
                .unwrap();
            });
            borrowed_rx.recv_timeout(Duration::from_secs(2)).unwrap();
            let address = decoder as usize;
            let (destroyed_tx, destroyed_rx) = std::sync::mpsc::channel();
            let destroying = thread::spawn(move || {
                mc_destroy(address as *mut ff::mc_decoder);
                destroyed_tx.send(()).unwrap();
            });
            let deadline = Instant::now() + Duration::from_secs(2);
            while controls::registry()
                .lock()
                .unwrap()
                .contains_key(&control_id)
            {
                assert!(Instant::now() < deadline, "destroy must revoke admission");
                thread::yield_now();
            }
            assert!(api::media_status(control_id).is_err());
            assert!(
                destroyed_rx.try_recv().is_err(),
                "destroy must wait for borrowed controls"
            );
            release_tx.send(()).unwrap();
            borrowing.join().unwrap();
            destroyed_rx.recv_timeout(Duration::from_secs(2)).unwrap();
            destroying.join().unwrap();
            assert!(api::media_set_paused(control_id, true).is_err());
            assert!(api::media_set_volume(control_id, 0.5).is_err());
            let next = mc_create(&config);
            assert!(!next.is_null());
            assert!(
                mc_control_id(next) > control_id,
                "control IDs must not be reused"
            );
            assert!(api::media_status(control_id).is_err());
            mc_destroy(next);
        }
    }

    #[test]
    #[ignore = "requires MEDIA_CODEC_TEST_H264_PATH pointing to a real Android H.264 fixture"]
    fn decode_android_packet_and_read_scaled_pixels() {
        let bytes = std::fs::read(std::env::var("MEDIA_CODEC_TEST_H264_PATH").unwrap()).unwrap();
        let mut starts = Vec::new();
        let mut cursor = 0;
        while cursor + 3 < bytes.len() {
            let length = if bytes[cursor..].starts_with(&[0, 0, 0, 1]) {
                4
            } else if bytes[cursor..].starts_with(&[0, 0, 1]) {
                3
            } else {
                cursor += 1;
                continue;
            };
            starts.push((cursor, length));
            cursor += length;
        }
        let mut configuration = Vec::new();
        let mut frames = Vec::new();
        for (index, &(start, prefix)) in starts.iter().enumerate() {
            let end = starts
                .get(index + 1)
                .map(|value| value.0)
                .unwrap_or(bytes.len());
            let kind = bytes[start + prefix] & 31;
            if kind == 7 || kind == 8 {
                configuration.extend_from_slice(&bytes[start..end]);
            } else if kind == 5 {
                frames.push(bytes[start..end].to_vec());
            }
        }
        assert!(
            !configuration.is_empty() && !frames.is_empty(),
            "fixture requires SPS/PPS and IDR"
        );
        unsafe {
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 1;
            config.generation = 7;
            // 验证 VA-API 不可用时自动选择软件解码的路径。
            config.hardware_device = c"vaapi".as_ptr();
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
            assert_eq!(
                event(
                    decoder as *mut c_void,
                    1,
                    7,
                    1,
                    320,
                    720,
                    configuration.as_ptr(),
                    configuration.len(),
                    0,
                    0
                ),
                0
            );
            assert_eq!(
                event(
                    decoder as *mut c_void,
                    2,
                    7,
                    1,
                    320,
                    720,
                    frames[0].as_ptr(),
                    frames[0].len(),
                    123_000,
                    1
                ),
                0
            );
            let deadline = Instant::now() + Duration::from_secs(5);
            let mut status: ff::mc_status = std::mem::zeroed();
            loop {
                mc_get_status(decoder, &mut status);
                if status.frame_count > 0 {
                    break;
                }
                assert!(
                    Instant::now() < deadline,
                    "decode timed out: {}",
                    string(status.error.as_ptr())
                );
                thread::sleep(Duration::from_millis(2));
            }
            assert_eq!((status.width, status.height), (320, 720));
            assert_eq!(status.position_us, 123_000);
            assert_eq!(status.native_ready, 1);
            let mut image: ff::mc_image = std::mem::zeroed();
            assert_eq!(mc_copy_rgba_scaled(decoder, 32, 32, &mut image), 0);
            assert_eq!((image.width, image.height), (14, 32));
            assert_eq!(image.size, 14 * 32 * 4);
            let pixels = slice::from_raw_parts(image.rgba, image.size);
            let pixels = pixels.as_chunks::<4>().0;
            assert!(pixels.iter().all(|pixel| pixel[3] == 255));
            assert!(pixels.iter().any(|pixel| pixel[..3] != [0, 0, 0]));
            println!(
                "decoded Android H264: {}x{}, decoder={}, hardware={}, scaled={}x{}",
                status.width,
                status.height,
                string(status.decoder_name.as_ptr()),
                status.hardware_accelerated,
                image.width,
                image.height
            );
            mc_image_free(&mut image);
            mc_destroy(decoder);
        }
    }
}
