//! 固定上游版本的类型化启动配置；服务器字节与部署身份由调用方提供。
use crate::{Error, Result, shell_quote};

pub const SERVER_VERSION: &str = "5.0.1";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoCodec {
    H264,
    H265,
    Av1,
    Vp8,
    Vp9,
}
impl VideoCodec {
    pub fn name(self) -> &'static str {
        match self {
            Self::H264 => "h264",
            Self::H265 => "h265",
            Self::Av1 => "av1",
            Self::Vp8 => "vp8",
            Self::Vp9 => "vp9",
        }
    }
    pub fn wire(self) -> [u8; 4] {
        match self {
            Self::H264 => *b"h264",
            Self::H265 => *b"h265",
            Self::Av1 => [0, b'a', b'v', b'1'],
            Self::Vp8 => *b"\0vp8",
            Self::Vp9 => *b"\0vp9",
        }
    }
}

/// 固定服务端支持的日志等级；不随显示或捕获类型隐式切换。
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum LogLevel {
    Verbose,
    #[default]
    Debug,
    Info,
    Warn,
    Error,
}
impl LogLevel {
    pub fn name(self) -> &'static str {
        match self {
            Self::Verbose => "verbose",
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct DisplayOptions {
    pub size: Option<(u16, u16)>,
    pub density: Option<u16>,
}

#[derive(Clone, Debug)]
pub struct Options {
    pub log_level: LogLevel,
    pub video: bool,
    /// 当前原生音频来源支持 raw/output PCM；不承诺其他编码或麦克风来源。
    pub audio: bool,
    pub display_id: u32,
    pub keep_active: bool,
    pub power_off_on_close: bool,
    pub stay_awake: bool,
    pub cleanup: bool,
    pub codec: VideoCodec,
    pub bit_rate: u32,
    pub max_size: u16,
    /// 当前类型化入口支持上游帧率的非负整数子集；0 为不限。
    pub max_fps: u16,
    pub encoder: Option<String>,
    pub display: Option<DisplayOptions>,
    pub control: bool,
    pub power_on: bool,
    pub clipboard_autosync: bool,
    pub vd_destroy_content: bool,
    pub flex_display: bool,
    pub vd_system_decorations: bool,
    pub repeat_previous_frame_after_us: Option<u64>,
    pub process_name_prefix: String,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            log_level: LogLevel::default(),
            video: true,
            audio: false,
            display_id: 0,
            keep_active: false,
            power_off_on_close: false,
            stay_awake: false,
            cleanup: true,
            codec: VideoCodec::H264,
            bit_rate: 8_000_000,
            max_size: 0,
            max_fps: 0,
            encoder: None,
            display: None,
            control: true,
            power_on: true,
            clipboard_autosync: true,
            vd_destroy_content: true,
            flex_display: false,
            vd_system_decorations: true,
            repeat_previous_frame_after_us: None,
            process_name_prefix: "scrcpy".into(),
        }
    }
}

impl Options {
    pub fn validate(&self) -> Result<()> {
        if (!self.video && !self.audio && !self.control)
            || (self.video && self.bit_rate == 0)
            || self.process_name_prefix.is_empty()
            || self.process_name_prefix.chars().any(char::is_control)
        {
            return Err(Error::new("invalid_argument", "视频码率或帧率无效。"));
        }
        if let Some(encoder) = &self.encoder
            && (encoder.is_empty() || encoder.len() > 256 || encoder.chars().any(char::is_control))
        {
            return Err(Error::new("invalid_argument", "视频编码器名称无效。"));
        }
        if let Some(display) = &self.display
            && (display.size.is_some_and(|(w, h)| w == 0 || h == 0) || display.density == Some(0))
        {
            return Err(Error::new("invalid_argument", "虚拟显示尺寸或密度无效。"));
        }
        Ok(())
    }

    pub fn command(&self, jar: &str, scid: u32) -> Result<String> {
        self.validate()?;
        if scid > 0x7fff_ffff {
            return Err(Error::new(
                "invalid_argument",
                "SCID 必须为非负有符号整数。",
            ));
        }
        let log = self.log_level.name();
        let mut command = format!(
            "CLASSPATH={} exec app_process / --nice-name={} com.genymobile.scrcpy.Server {SERVER_VERSION} scid={scid:08x} log_level={log} video={} audio={} audio_codec=raw audio_source=output control={} video_codec={} max_size={} max_fps={} video_bit_rate={} tunnel_forward=true cleanup={} display_id={} keep_active={} power_off_on_close={} stay_awake={} vd_destroy_content={} clipboard_autosync={} power_on={} send_dummy_byte=true send_device_meta=true send_stream_meta=true send_frame_meta=true",
            shell_quote(jar)?,
            shell_quote(&format!("{}:{scid:08x}:{jar}", self.process_name_prefix))?,
            self.video,
            self.audio,
            self.control,
            self.codec.name(),
            self.max_size,
            self.max_fps,
            self.bit_rate,
            self.cleanup,
            self.display_id,
            self.keep_active,
            self.power_off_on_close,
            self.stay_awake,
            self.vd_destroy_content,
            self.clipboard_autosync,
            self.power_on
        );
        if let Some(delay) = self.repeat_previous_frame_after_us {
            command.push_str(&format!(
                " video_codec_options=repeat-previous-frame-after:long={delay}"
            ));
        }
        if let Some(encoder) = &self.encoder {
            command.push(' ');
            command.push_str(&shell_quote(&format!("video_encoder={encoder}"))?);
        }
        if let Some(display) = &self.display {
            command.push_str(" new_display=");
            if let Some((width, height)) = display.size {
                command.push_str(&format!("{width}x{height}"));
            }
            if let Some(density) = display.density {
                command.push_str(&format!("/{density}"));
            }
            command.push_str(&format!(
                " flex_display={} vd_system_decorations={}",
                self.flex_display, self.vd_system_decorations
            ));
        }
        Ok(command)
    }
}
