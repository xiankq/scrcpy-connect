//! Packet-only FFmpeg decoder. Flutter adapters own textures and audio devices;
//! this crate owns packet admission, decoding, fallback and the source lifetime.
#![allow(clippy::missing_safety_doc)]

mod pcm;

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
    collections::VecDeque,
    ffi::{c_char, c_int, c_void, CStr, CString},
    ptr, slice,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    thread::{self, JoinHandle},
};

const MAX_BYTES: usize = 16 * 1024 * 1024;
const HISTORY_MAX_BYTES: usize = 8 * 1024 * 1024;
const MAX_PACKETS: usize = 8;

enum Storage {
    Local(Vec<u8>),
    Foreign {
        data: *mut u8,
        size: usize,
        owner: *mut c_void,
        release: ff::mc_release_fn,
    },
}
unsafe impl Send for Storage {}
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
struct PacketBytes {
    storage: Storage,
    length: usize,
}
#[derive(Clone)]
struct Packet {
    event: u32,
    codec: u32,
    width: u32,
    height: u32,
    flags: u32,
    pts: i64,
    data: Arc<PacketBytes>,
}
// Replay is usable only while it contains the complete current GOP. After
// overflow, a P-frame suffix must never become a replacement history.
#[derive(Default)]
struct GopHistory {
    packets: VecDeque<Packet>,
    bytes: usize,
    complete: bool,
}
impl GopHistory {
    fn record(&mut self, packet: &Packet) {
        if packet.flags & 1 != 0 {
            self.clear();
            self.complete = true;
        }
        if !self.complete {
            return;
        }
        if packet.data.length > HISTORY_MAX_BYTES - self.bytes {
            self.clear();
            return;
        }
        self.bytes += packet.data.length;
        self.packets.push_back(packet.clone());
    }
    fn clear(&mut self) {
        self.packets.clear();
        self.bytes = 0;
        self.complete = false;
    }
    fn replay(&self) -> Option<VecDeque<Packet>> {
        self.complete.then(|| self.packets.clone())
    }
}
struct Attachment {
    source: CString,
    detach: ff::mc_detach_fn,
}
struct Shared {
    status: ff::mc_status,
    packets: VecDeque<Packet>,
    queued_bytes: usize,
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
struct Conversion {
    scaler: *mut ff::SwsContext,
}
impl Drop for Conversion {
    fn drop(&mut self) {
        unsafe {
            ff::sws_freeContext(self.scaler);
        }
    }
}
struct Decoder {
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
// Configuration and callback pointers are immutable. FFmpeg contexts belong to
// the worker; shared frames and conversion contexts are protected by their locks.
unsafe impl Send for Decoder {}
unsafe impl Sync for Decoder {}

fn codec_id(codec: u32) -> ff::AVCodecID {
    match codec {
        1 => ff::AV_CODEC_ID_H264,
        2 => ff::AV_CODEC_ID_HEVC,
        3 => ff::AV_CODEC_ID_AV1,
        4 => ff::AV_CODEC_ID_VP8,
        5 => ff::AV_CODEC_ID_VP9,
        _ => ff::AV_CODEC_ID_NONE,
    }
}
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

struct Frame(*mut ff::AVFrame);
impl Drop for Frame {
    fn drop(&mut self) {
        unsafe {
            ff::av_frame_free(&mut self.0);
        }
    }
}

struct Backend {
    decoder: *const Decoder,
    codec: *mut ff::AVCodecContext,
    hardware: *mut ff::AVBufferRef,
    hardware_format: ff::AVPixelFormat,
    kind: u32,
    width: u32,
    height: u32,
    extra: Vec<u8>,
    history: GopHistory,
    waiting_for_key: bool,
    hardware_failed: bool,
    output_reported: bool,
    hardware_kind: c_int,
    #[cfg(target_os = "android")]
    low_latency: bool,
    frame: Frame,
    packet: *mut ff::AVPacket,
}
impl Drop for Backend {
    fn drop(&mut self) {
        unsafe {
            self.close();
            ff::av_packet_free(&mut self.packet);
        }
    }
}
#[cfg(not(target_os = "android"))]
unsafe extern "C" fn choose_format(
    context: *mut ff::AVCodecContext,
    formats: *const ff::AVPixelFormat,
) -> ff::AVPixelFormat {
    let backend = &*((*context).opaque as *const Backend);
    let mut cursor = formats;
    while !cursor.is_null() && *cursor != ff::AV_PIX_FMT_NONE {
        if *cursor == backend.hardware_format {
            return *cursor;
        }
        cursor = cursor.add(1);
    }
    cursor = formats;
    while !cursor.is_null() && *cursor != ff::AV_PIX_FMT_NONE {
        let description = ff::av_pix_fmt_desc_get(*cursor);
        if !description.is_null()
            && ((*description).flags & ff::AV_PIX_FMT_FLAG_HWACCEL as u64) == 0
        {
            return *cursor;
        }
        cursor = cursor.add(1);
    }
    ff::AV_PIX_FMT_NONE
}
impl Backend {
    unsafe fn close(&mut self) {
        if !self.frame.0.is_null() {
            ff::av_frame_unref(self.frame.0);
        }
        if !self.packet.is_null() {
            ff::av_packet_unref(self.packet);
        }
        ff::avcodec_free_context(&mut self.codec);
        ff::av_buffer_unref(&mut self.hardware);
        self.hardware_format = ff::AV_PIX_FMT_NONE;
    }
    unsafe fn open(&mut self, software: bool) -> bool {
        self.close();
        self.output_reported = false;
        self.hardware_kind = -1;
        let decoder = &*self.decoder;
        let software = software || decoder.requested_device == "none";
        // libdav1d may precede native av1 in FFmpeg's codec registry. Select
        // the hardware-capable implementation explicitly before falling back.
        #[allow(unused_mut)]
        let mut implementation = if self.kind == 3 {
            ff::avcodec_find_decoder_by_name(if software { c"libdav1d" } else { c"av1" }.as_ptr())
        } else {
            ff::avcodec_find_decoder(codec_id(self.kind))
        };
        #[cfg(target_os = "android")]
        if !software && decoder.native_window.load(Ordering::Acquire) != 0 {
            let name = match self.kind {
                1 => c"h264_mediacodec",
                2 => c"hevc_mediacodec",
                3 => c"av1_mediacodec",
                4 => c"vp8_mediacodec",
                _ => c"vp9_mediacodec",
            };
            let candidate = ff::avcodec_find_decoder_by_name(name.as_ptr());
            if !candidate.is_null() {
                implementation = candidate;
            }
        }
        if implementation.is_null() {
            if !software {
                return self.open(true);
            }
            error(
                decoder,
                ff::MC_NO_DECODER,
                if self.kind == 3 {
                    "AV1 software decoder libdav1d unavailable in this build"
                } else {
                    "decoder"
                },
            );
            return false;
        }
        self.codec = ff::avcodec_alloc_context3(implementation);
        if self.codec.is_null() {
            error(decoder, ff::MC_ENOMEM, "allocate decoder");
            return false;
        }
        (*self.codec).width = self.width as c_int;
        (*self.codec).height = self.height as c_int;
        (*self.codec).pkt_timebase = ff::AVRational {
            num: 1,
            den: 1_000_000,
        };
        (*self.codec).flags |= ff::AV_CODEC_FLAG_LOW_DELAY as c_int;
        if self.kind == 1 {
            (*self.codec).hwaccel_flags |= ff::AV_HWACCEL_FLAG_ALLOW_PROFILE_MISMATCH as c_int;
        }
        // dav1d keeps one-frame delay under LOW_DELAY while using tile/row
        // parallelism. Other decoders retain slice-only single-frame decoding.
        // Slice/tile workers do not add frame-thread buffering. Let FFmpeg
        // choose its bounded CPU count for streams with independently coded slices.
        (*self.codec).thread_count = 0;
        (*self.codec).thread_type = ff::FF_THREAD_SLICE as c_int;
        (*self.codec).opaque = self as *mut Self as *mut c_void;
        if !self.extra.is_empty() {
            (*self.codec).extradata =
                ff::av_mallocz(self.extra.len() + ff::AV_INPUT_BUFFER_PADDING_SIZE as usize)
                    as *mut u8;
            if (*self.codec).extradata.is_null() {
                error(decoder, ff::MC_ENOMEM, "codec configuration");
                return false;
            }
            ptr::copy_nonoverlapping(
                self.extra.as_ptr(),
                (*self.codec).extradata,
                self.extra.len(),
            );
            (*self.codec).extradata_size = self.extra.len() as c_int;
        }
        let mut uses_hardware = false;
        #[cfg(target_os = "android")]
        if !software
            && decoder.native_window.load(Ordering::Acquire) != 0
            && string((*implementation).name).contains("mediacodec")
        {
            self.hardware = ff::av_hwdevice_ctx_alloc(ff::AV_HWDEVICE_TYPE_MEDIACODEC);
            if self.hardware.is_null() {
                return self.open(true);
            }
            let device = (*self.hardware).data as *mut ff::AVHWDeviceContext;
            let context = (*device).hwctx as *mut ff::AVMediaCodecDeviceContext;
            (*context).native_window = decoder.native_window.load(Ordering::Acquire) as *mut c_void;
            if ff::av_hwdevice_ctx_init(self.hardware) < 0 {
                return self.open(true);
            }
            (*self.codec).hw_device_ctx = ff::av_buffer_ref(self.hardware);
            ff::av_opt_set_int((*self.codec).priv_data, c"ndk_codec".as_ptr(), 1, 0);
            ff::av_opt_set_int(
                (*self.codec).priv_data,
                c"low_latency".as_ptr(),
                self.low_latency as i64,
                0,
            );
            uses_hardware = true;
        }
        #[cfg(not(target_os = "android"))]
        if !software && decoder.requested_device != "none" {
            let candidates = if !decoder.requested_device.is_empty() {
                let name =
                    CString::new(decoder.requested_device.split(':').next().unwrap()).unwrap();
                vec![ff::av_hwdevice_find_type_by_name(name.as_ptr())]
            } else if cfg!(target_os = "windows") {
                vec![ff::AV_HWDEVICE_TYPE_D3D11VA, ff::AV_HWDEVICE_TYPE_DXVA2]
            } else if cfg!(target_vendor = "apple") {
                vec![ff::AV_HWDEVICE_TYPE_VIDEOTOOLBOX]
            } else {
                vec![
                    ff::AV_HWDEVICE_TYPE_VAAPI,
                    ff::AV_HWDEVICE_TYPE_CUDA,
                    ff::AV_HWDEVICE_TYPE_VULKAN,
                ]
            };
            for kind in candidates {
                let mut index = 0;
                loop {
                    let config = ff::avcodec_get_hw_config(implementation, index);
                    if config.is_null() {
                        break;
                    }
                    index += 1;
                    if (*config).device_type != kind
                        || ((*config).methods
                            & ff::AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX as c_int)
                            == 0
                    {
                        continue;
                    }
                    let device = decoder
                        .requested_device
                        .split_once(':')
                        .and_then(|(_, device)| CString::new(device).ok());
                    if ff::av_hwdevice_ctx_create(
                        &mut self.hardware,
                        kind,
                        device
                            .as_ref()
                            .map_or(ptr::null(), |device| device.as_ptr()),
                        ptr::null_mut(),
                        0,
                    ) < 0
                    {
                        break;
                    }
                    self.hardware_format = (*config).pix_fmt;
                    (*self.codec).hw_device_ctx = ff::av_buffer_ref(self.hardware);
                    (*self.codec).get_format = Some(choose_format);
                    uses_hardware = true;
                    break;
                }
                if uses_hardware {
                    break;
                }
            }
        }
        if self.kind == 3 && !software && !uses_hardware {
            // Native av1 has no software reconstruction implementation.
            return self.open(true);
        }
        let result = ff::avcodec_open2(self.codec, implementation, ptr::null_mut());
        if result < 0 {
            // Some OEM components reject the optional low-latency MediaFormat
            // key. Retry the same platform decoder before software fallback.
            #[cfg(target_os = "android")]
            if !software && uses_hardware && self.low_latency {
                self.low_latency = false;
                return self.open(false);
            }
            if !software {
                return self.open(true);
            }
            error(decoder, result, "open decoder");
            return false;
        }
        let mut shared = decoder.shared.lock().unwrap();
        clear_error(&mut shared.status);
        true
    }
    unsafe fn publish(&mut self, frame: *mut ff::AVFrame) {
        let decoder = &*self.decoder;
        #[cfg(target_os = "android")]
        if (*frame).format == ff::AV_PIX_FMT_MEDIACODEC && !(*frame).data[3].is_null() {
            let result = ff::av_mediacodec_release_buffer(
                (*frame).data[3] as *mut ff::AVMediaCodecBuffer,
                (!decoder.paused.load(Ordering::Acquire)
                    && decoder.native_window.load(Ordering::Acquire) != 0) as c_int,
            );
            if result < 0 {
                error(decoder, result, "release MediaCodec output buffer");
                mc_report_present(
                    self.decoder as *mut ff::mc_decoder,
                    0,
                    c"android-mediacodec-surface".as_ptr(),
                    c"MediaCodec output buffer release failed".as_ptr(),
                );
                return;
            }
        }
        #[cfg(target_os = "android")]
        if !self.output_reported && (*frame).format == ff::AV_PIX_FMT_MEDIACODEC {
            let component = ff::av_mediacodec_get_codec_name(self.codec);
            self.hardware_kind = decoder
                .config
                .hardware_kind
                .map(|callback| callback(decoder.config.user, component))
                .unwrap_or(-1);
        }
        {
            let mut shared = decoder.shared.lock().unwrap();
            ff::av_frame_unref(shared.latest);
            if ff::av_frame_ref(shared.latest, frame) < 0 {
                drop(shared);
                error(decoder, ff::MC_ENOMEM, "retain decoded frame");
                return;
            }
            shared.status.width = (*frame).width as u32;
            shared.status.height = (*frame).height as u32;
            if (*frame).pts != ff::MC_NO_PTS {
                shared.status.position_us = (*frame).pts;
            }
            shared.status.frame_count += 1;
            shared.status.native_ready = 1;
            clear_error(&mut shared.status);
            let description = ff::av_pix_fmt_desc_get((*frame).format);
            let actual_hardware = (!description.is_null()
                && ((*description).flags & ff::AV_PIX_FMT_FLAG_HWACCEL as u64) != 0)
                as c_int;
            if !self.output_reported || shared.status.backend_hardware_frames != actual_hardware {
                self.output_reported = true;
                // FFmpeg may internally reject a hardware format and decode in
                // software without reopening the context (notably iOS Simulator).
                let suffix = if actual_hardware != 0 && !self.hardware.is_null() {
                    let device = (*self.hardware).data as *const ff::AVHWDeviceContext;
                    format!(
                        "/{}",
                        string(ff::av_hwdevice_get_type_name((*device).type_))
                    )
                } else {
                    String::new()
                };
                #[allow(unused_mut)]
                let mut selected = format!("{}{suffix}", string((*(*self.codec).codec).name));
                #[cfg(target_os = "android")]
                if (*frame).format == ff::AV_PIX_FMT_MEDIACODEC {
                    let component = string(ff::av_mediacodec_get_codec_name(self.codec));
                    if !component.is_empty() {
                        selected.push('/');
                        selected.push_str(&component);
                    }
                }
                text(&mut shared.status.decoder_name, &selected);
            }
            #[cfg(not(target_os = "android"))]
            {
                self.hardware_kind = actual_hardware;
            }
            if actual_hardware == 0 {
                self.hardware_kind = 0;
            }
            shared.status.backend_hardware_frames = actual_hardware;
            shared.status.hardware_verification = self.hardware_kind;
            shared.status.hardware_accelerated = (self.hardware_kind == 1) as c_int;
        }
        if !decoder.paused.load(Ordering::Acquire) {
            if let Some(callback) = decoder.config.frame_ready {
                callback(decoder.config.user);
            }
        }
    }
    unsafe fn decode(&mut self, packet: &Packet) -> c_int {
        let input = self.packet;
        if input.is_null() {
            return ff::MC_ENOMEM;
        }
        ff::av_packet_unref(input);
        // The ingress copy already includes FFmpeg's zero padding. Retain that
        // allocation instead of copying the compressed packet into another buffer.
        let owner = Arc::into_raw(packet.data.clone());
        let storage = &(*owner).storage;
        let data = storage.as_ptr() as *mut u8;
        let buffer = ff::av_buffer_create(
            data,
            storage.len(),
            Some(release_packet),
            owner as *mut c_void,
            ff::AV_BUFFER_FLAG_READONLY as c_int,
        );
        if buffer.is_null() {
            drop(Arc::from_raw(owner));
            return ff::MC_ENOMEM;
        }
        (*input).buf = buffer;
        (*input).data = data;
        (*input).size = packet.data.length as c_int;
        (*input).pts = packet.pts;
        (*input).dts = ff::MC_NO_PTS;
        if packet.flags & 1 != 0 {
            (*input).flags |= ff::AV_PKT_FLAG_KEY as c_int;
        }
        let mut result = ff::avcodec_send_packet(self.codec, input);
        if result == ff::MC_EAGAIN {
            let drained = self.receive();
            if drained < 0 {
                ff::av_packet_unref(input);
                return drained;
            }
            result = ff::avcodec_send_packet(self.codec, input);
        }
        ff::av_packet_unref(input);
        if result < 0 {
            return result;
        }
        self.receive()
    }
    unsafe fn receive(&mut self) -> c_int {
        loop {
            let result = ff::avcodec_receive_frame(self.codec, self.frame.0);
            if result == ff::MC_EAGAIN || result == ff::MC_EOF {
                return 0;
            }
            if result < 0 {
                return result;
            }
            self.publish(self.frame.0);
            ff::av_frame_unref(self.frame.0);
        }
    }
    unsafe fn process(&mut self, packet: Packet) {
        if packet.event == 1 {
            let data = &packet.data.storage[..packet.data.length];
            if self.kind != 3
                && !self.codec.is_null()
                && self.kind == packet.codec
                && self.width == packet.width
                && self.height == packet.height
                && self.extra == data
            {
                return;
            }
            self.kind = packet.codec;
            self.width = packet.width;
            self.height = packet.height;
            self.extra = data.to_vec();
            self.history.clear();
            self.waiting_for_key = true;
            self.hardware_failed = false;
            #[cfg(target_os = "android")]
            if (&*self.decoder).native_window.load(Ordering::Acquire) == 0 {
                return;
            }
            self.open(false);
            return;
        }
        #[cfg(target_os = "android")]
        if (&*self.decoder).native_window.load(Ordering::Acquire) == 0 {
            self.history.record(&packet);
            return;
        }
        if self.codec.is_null() && !self.open(self.hardware_failed) {
            return;
        }
        if self.waiting_for_key {
            if packet.flags & 1 == 0 {
                return;
            }
            self.waiting_for_key = false;
        }
        if !self.hardware.is_null() {
            self.history.record(&packet);
        }
        let mut result = self.decode(&packet);
        if result < 0
            && result != ff::MC_EAGAIN
            && result != ff::MC_ENOMEM
            && !self.hardware_failed
            && !self.hardware.is_null()
        {
            self.hardware_failed = true;
            if self.open(true) {
                if let Some(replay) = self.history.replay() {
                    for previous in replay {
                        result = self.decode(&previous);
                        if result < 0 {
                            break;
                        }
                    }
                } else if packet.flags & 1 != 0 {
                    // An oversized keyframe may still be decoded directly,
                    // although it cannot be retained within the replay bound.
                    result = self.decode(&packet);
                } else {
                    self.waiting_for_key = true;
                    return;
                }
            } else {
                // Preserve the precise fallback-open failure (for example an
                // omitted libdav1d), rather than replacing it with the initial
                // hardware decoder's generic packet error.
                return;
            }
        }
        if result < 0 {
            self.history.clear();
            self.waiting_for_key = true;
            error(&*self.decoder, result, "decode packet");
        }
    }
}
unsafe extern "C" fn release_packet(context: *mut c_void, _: *mut u8) {
    drop(Arc::from_raw(context as *const PacketBytes));
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
        || width > 16384
        || height > 16384
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
    if shared.packets.len() >= MAX_PACKETS || shared.queued_bytes + size > MAX_BYTES {
        return 1;
    }
    shared.queued_bytes += size;
    shared.packets.push_back(Packet {
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
    });
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
    // The box keeps the get_format callback's Backend pointer stable.
    let mut backend = Box::new(Backend {
        decoder,
        codec: ptr::null_mut(),
        hardware: ptr::null_mut(),
        hardware_format: ff::AV_PIX_FMT_NONE,
        kind: decoder.config.codec,
        width: decoder.config.width,
        height: decoder.config.height,
        extra: Vec::new(),
        history: GopHistory::default(),
        waiting_for_key: true,
        hardware_failed: false,
        output_reported: false,
        hardware_kind: -1,
        #[cfg(target_os = "android")]
        low_latency: true,
        frame: Frame(ff::av_frame_alloc()),
        packet: ff::av_packet_alloc(),
    });
    if backend.frame.0.is_null() || backend.packet.is_null() {
        error(decoder, ff::MC_ENOMEM, "allocate decode buffers");
        let mut shared = decoder.shared.lock().unwrap();
        shared.stopping = true;
        if let Some(waker) = &shared.source_waker {
            waker.notify();
        }
        // Surface and PCM controls may already be waiting for this worker.
        decoder.wake.notify_all();
        return;
    }
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
                #[allow(unused_mut)]
                let mut swapped = false;
                #[cfg(target_os = "android")]
                if window != 0
                    && !backend.codec.is_null()
                    && string((*(*backend.codec).codec).name).contains("mediacodec")
                {
                    swapped =
                        ff::av_mediacodec_set_output_window(backend.codec, window as *mut c_void)
                            == 0;
                }
                decoder.native_window.store(window, Ordering::Release);
                if !swapped {
                    backend.close();
                    // A missing presentation target suspends decode rather
                    // than silently switching all background packets to CPU.
                    if window != 0 && decoder.config.codec != 100 && backend.open(false) {
                        backend.waiting_for_key = true;
                        if let Some(replay) = backend.history.replay() {
                            backend.waiting_for_key = false;
                            for packet in replay {
                                if backend.decode(&packet) < 0 {
                                    backend.waiting_for_key = true;
                                    backend.history.clear();
                                    break;
                                }
                            }
                        }
                    }
                }
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
                while shared.queued_bytes > 15_360 && shared.packets.len() > 1 {
                    let oldest = shared.packets.pop_front().unwrap();
                    shared.queued_bytes -= oldest.data.length;
                    shared.status.audio_dropped_frames += (oldest.data.length / 4) as u64;
                }
            }
            let packet = shared.packets.pop_front().unwrap();
            shared.queued_bytes -= packet.data.length;
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
        // Audio packets are not shared with GOP history, so mutation stays local.
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
                // Submission position is retained only for legacy callbacks;
                // actual device clock replaces it whenever one is available.
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
        || (size != 0 && data.is_null())
        || width > 16384
        || height > 16384
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
    if shared.packets.len() >= MAX_PACKETS || shared.queued_bytes + size > MAX_BYTES {
        return 1;
    }
    let mut storage = Vec::with_capacity(size + ff::AV_INPUT_BUFFER_PADDING_SIZE as usize);
    if size != 0 {
        storage.extend_from_slice(slice::from_raw_parts(data, size));
    }
    storage.resize(size + ff::AV_INPUT_BUFFER_PADDING_SIZE as usize, 0);
    shared.queued_bytes += size;
    shared.packets.push_back(Packet {
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
    });
    decoder.wake.notify_one();
    0
}

unsafe fn decoder<'a>(value: *mut ff::mc_decoder) -> &'a Decoder {
    &*(value as *const Decoder)
}

#[no_mangle]
pub unsafe extern "C" fn mc_create(config: *const ff::mc_config) -> *mut ff::mc_decoder {
    if config.is_null()
        || (*config).struct_size < std::mem::size_of::<ff::mc_config>() as u32
        || ((*config).codec != 100 && codec_id((*config).codec) == ff::AV_CODEC_ID_NONE)
        || (*config).width > 16384
        || (*config).height > 16384
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
    let value = Box::new(Decoder {
        config: *config,
        requested_device: string((*config).hardware_device),
        shared: Mutex::new(Shared {
            status,
            packets: VecDeque::new(),
            queued_bytes: 0,
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
        conversion: Mutex::new(Conversion {
            scaler: ptr::null_mut(),
        }),
    });
    let pointer = Box::into_raw(value);
    let address = pointer as usize;
    match thread::Builder::new()
        .name("media-codec".into())
        .spawn(move || run(address))
    {
        Ok(worker) => {
            *(*pointer).worker.lock().unwrap() = Some(worker);
            pointer as *mut ff::mc_decoder
        }
        Err(_) => {
            drop(Box::from_raw(pointer));
            ptr::null_mut()
        }
    }
}
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
#[no_mangle]
pub unsafe extern "C" fn mc_get_status(value: *mut ff::mc_decoder, out: *mut ff::mc_status) {
    if !value.is_null() && !out.is_null() {
        *out = decoder(value).shared.lock().unwrap().status;
    }
}
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
            shared.packets.retain(|packet| packet.event != 2);
            shared.queued_bytes = shared.packets.iter().map(|packet| packet.data.length).sum();
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
#[no_mangle]
pub unsafe extern "C" fn mc_acquire_frame(value: *mut ff::mc_decoder) -> *mut ff::AVFrame {
    mc_acquire_frame_snapshot(value, ptr::null_mut())
}
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
#[no_mangle]
pub unsafe extern "C" fn mc_release_frame(mut frame: *mut ff::AVFrame) {
    ff::av_frame_free(&mut frame);
}
#[no_mangle]
pub unsafe extern "C" fn mc_copy_rgba(value: *mut ff::mc_decoder, out: *mut ff::mc_image) -> c_int {
    mc_copy_rgba_scaled(value, 0, 0, out)
}
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
    convert_frame(
        frame.0,
        &mut conversion,
        max_width,
        max_height,
        ff::AV_PIX_FMT_RGBA,
        out,
    )
}
#[no_mangle]
pub unsafe extern "C" fn mc_copy_frame_rgba(
    frame: *mut ff::AVFrame,
    out: *mut ff::mc_image,
) -> c_int {
    convert_frame(
        frame,
        &mut Conversion {
            scaler: ptr::null_mut(),
        },
        0,
        0,
        ff::AV_PIX_FMT_RGBA,
        out,
    )
}
#[no_mangle]
pub unsafe extern "C" fn mc_copy_frame_bgra(
    frame: *mut ff::AVFrame,
    out: *mut ff::mc_image,
) -> c_int {
    convert_frame(
        frame,
        &mut Conversion {
            scaler: ptr::null_mut(),
        },
        0,
        0,
        ff::AV_PIX_FMT_BGRA,
        out,
    )
}
unsafe fn convert_frame(
    input: *mut ff::AVFrame,
    conversion: &mut Conversion,
    max_width: u32,
    max_height: u32,
    format: ff::AVPixelFormat,
    out: *mut ff::mc_image,
) -> c_int {
    if out.is_null() {
        return -1;
    }
    *out = std::mem::zeroed();
    // Borrow the caller's reference; only the optional downloaded frame is owned here.
    let frame = std::mem::ManuallyDrop::new(Frame(input));
    if frame.0.is_null() {
        return 1;
    }
    let mut software = Frame(ptr::null_mut());
    let description = ff::av_pix_fmt_desc_get((*frame.0).format);
    if !description.is_null() && ((*description).flags & ff::AV_PIX_FMT_FLAG_HWACCEL as u64) != 0 {
        software.0 = ff::av_frame_alloc();
        if software.0.is_null() {
            return ff::MC_ENOMEM;
        }
        let result = ff::av_hwframe_transfer_data(software.0, frame.0, 0);
        if result < 0 {
            return result;
        }
        let result = ff::av_frame_copy_props(software.0, frame.0);
        if result < 0 {
            return result;
        }
    }
    let source = if software.0.is_null() {
        &*frame.0
    } else {
        &*software.0
    };
    if source.width <= 0 || source.height <= 0 || source.width > 16384 || source.height > 16384 {
        return -1;
    }
    let mut scale = 1.0_f64;
    if max_width != 0 && source.width as u32 > max_width {
        scale = scale.min(max_width as f64 / source.width as f64);
    }
    if max_height != 0 && source.height as u32 > max_height {
        scale = scale.min(max_height as f64 / source.height as f64);
    }
    (*out).width = ((source.width as f64 * scale) as u32).max(1);
    (*out).height = ((source.height as f64 * scale) as u32).max(1);
    (*out).stride = (*out).width as usize * 4;
    (*out).size = (*out).stride * (*out).height as usize;
    (*out).rgba = ff::av_malloc((*out).size) as *mut u8;
    if (*out).rgba.is_null() {
        *out = std::mem::zeroed();
        return ff::MC_ENOMEM;
    }
    conversion.scaler = ff::sws_getCachedContext(
        conversion.scaler,
        source.width,
        source.height,
        source.format,
        (*out).width as c_int,
        (*out).height as c_int,
        format,
        ff::SWS_FAST_BILINEAR as c_int,
        ptr::null_mut(),
        ptr::null_mut(),
        ptr::null(),
    );
    let result = if conversion.scaler.is_null() {
        -1
    } else {
        let matrix = match source.colorspace {
            ff::AVCOL_SPC_BT709 => ff::SWS_CS_ITU709,
            ff::AVCOL_SPC_BT2020_NCL | ff::AVCOL_SPC_BT2020_CL => ff::SWS_CS_BT2020,
            ff::AVCOL_SPC_UNSPECIFIED => ff::SWS_CS_ITU709,
            _ => ff::SWS_CS_ITU601,
        };
        let coefficients = ff::sws_getCoefficients(matrix as c_int);
        ff::sws_setColorspaceDetails(
            conversion.scaler,
            coefficients,
            (source.color_range == ff::AVCOL_RANGE_JPEG) as c_int,
            coefficients,
            1,
            0,
            1 << 16,
            1 << 16,
        );
        let planes = [
            (*out).rgba,
            ptr::null_mut(),
            ptr::null_mut(),
            ptr::null_mut(),
        ];
        let strides = [(*out).stride as c_int, 0, 0, 0];
        ff::sws_scale(
            conversion.scaler,
            source.data.as_ptr() as *const *const u8,
            source.linesize.as_ptr(),
            0,
            source.height,
            planes.as_ptr(),
            strides.as_ptr(),
        )
    };
    if result < 0 {
        mc_image_free(out);
        result
    } else {
        0
    }
}
#[no_mangle]
pub unsafe extern "C" fn mc_image_free(image: *mut ff::mc_image) {
    if !image.is_null() {
        ff::av_free((*image).rgba as *mut c_void);
        *image = std::mem::zeroed();
    }
}
#[no_mangle]
pub unsafe extern "C" fn mc_destroy(value: *mut ff::mc_decoder) {
    if value.is_null() {
        return;
    }
    let decoder = decoder(value);
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
        // FFmpeg's allocation ceiling is process-global. Isolate fault
        // injection so concurrently running decoder tests cannot observe it.
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
            // Invoke the actual initialization failure path. The ordinary
            // worker has no input; both instances only touch locked status.
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
    fn configuration_does_not_claim_decoded_output() {
        unsafe {
            let mut config: ff::mc_config = std::mem::zeroed();
            config.struct_size = std::mem::size_of::<ff::mc_config>() as u32;
            config.codec = 4;
            config.generation = 1;
            config.hardware_device = c"none".as_ptr();
            let decoder = mc_create(&config);
            assert!(!decoder.is_null());
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
            mc_destroy(decoder);
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
            // Exercise automatic software selection if VA-API is unavailable.
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
