//! 解码上下文、硬件选择、软件回退和换纹理后的连续性均由本模块拥有。

#[cfg(target_os = "android")]
use super::mc_report_present;
use super::packet::{GopHistory, Packet, PacketBytes};
use super::{clear_error, error, ff, string, text, Decoder, Frame};
use std::{
    ffi::{c_int, c_void, CString},
    ptr,
    sync::{atomic::Ordering, Arc},
};

pub(super) fn codec_id(codec: u32) -> ff::AVCodecID {
    match codec {
        1 => ff::AV_CODEC_ID_H264,
        2 => ff::AV_CODEC_ID_HEVC,
        3 => ff::AV_CODEC_ID_AV1,
        4 => ff::AV_CODEC_ID_VP8,
        5 => ff::AV_CODEC_ID_VP9,
        _ => ff::AV_CODEC_ID_NONE,
    }
}
pub(super) struct Backend {
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
        // FFmpeg 注册表中 libdav1d 可能排在原生 av1 前；
        // 先明确选择可使用硬件的实现，失败后再回退。
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
        // dav1d 在 LOW_DELAY 下保持一帧延迟并使用 tile/row 并行；
        // 其他解码器只启用单帧 slice 并行，不引入帧线程缓冲。
        // 含独立编码 slice 的码流由 FFmpeg 选择有界线程数。
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
            // 原生 av1 不提供软件重建，未取得硬件上下文时转入 libdav1d。
            return self.open(true);
        }
        let result = ff::avcodec_open2(self.codec, implementation, ptr::null_mut());
        if result < 0 {
            // 部分 OEM 组件拒绝可选的低延迟 MediaFormat 参数；
            // 先去掉该参数重试同一平台解码器，再尝试软件回退。
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
                // FFmpeg 可能拒绝硬件格式后直接在原上下文中软件解码，
                // iOS Simulator 尤其如此；硬解证据必须来自实际输出帧。
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
        // 入站存储已包含 FFmpeg 要求的零填充；保留这份分配，
        // 避免将压缩包再次复制到另一缓冲区。
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
    pub(super) unsafe fn process(&mut self, packet: Packet) {
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
                    // 超限关键帧不能留作历史，但仍可直接解码。
                    result = self.decode(&packet);
                } else {
                    self.waiting_for_key = true;
                    return;
                }
            } else {
                // 保留打开回退解码器的精确错误（如缺少 libdav1d），
                // 不用最初的硬件包解码错误覆盖它。
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

impl Backend {
    /// Box 保持 get_format 回调中的 opaque 指针稳定；上下文仅由解码线程访问。
    pub(super) unsafe fn new(decoder: &Decoder) -> Option<Box<Self>> {
        let backend = Box::new(Backend {
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
            return None;
        }
        Some(backend)
    }

    /// 纹理切换、解码器重开和 GOP 重放共同维护同一捕获的连续性。
    pub(super) unsafe fn set_window(&mut self, window: usize) {
        let decoder = &*self.decoder;
        #[allow(unused_mut)]
        let mut swapped = false;
        #[cfg(target_os = "android")]
        if window != 0
            && !self.codec.is_null()
            && string((*(*self.codec).codec).name).contains("mediacodec")
        {
            swapped = ff::av_mediacodec_set_output_window(self.codec, window as *mut c_void) == 0;
        }
        decoder.native_window.store(window, Ordering::Release);
        if swapped {
            return;
        }
        self.close();
        // 没有呈现目标时停止解码，避免后台包静默触发 CPU 回退。
        if window != 0 && decoder.config.codec != 100 && self.open(false) {
            self.waiting_for_key = true;
            if let Some(replay) = self.history.replay() {
                self.waiting_for_key = false;
                for packet in replay {
                    if self.decode(&packet) < 0 {
                        self.waiting_for_key = true;
                        self.history.clear();
                        break;
                    }
                }
            }
        }
    }
}
