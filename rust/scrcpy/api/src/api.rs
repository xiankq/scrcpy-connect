//! 独立 scrcpy SDK 的类型化接口；只解析本宿主登记的捕获。
use interop_scrcpy::control::{Message, Position};
pub mod sdk;

#[derive(Clone, Copy, Debug)]
pub enum ScrcpyVideoCodec {
    H264,
    H265,
    Av1,
    Vp8,
    Vp9,
}

#[derive(Clone)]
pub struct ScrcpyNativeSource {
    pub source_id: String,
    pub generation: u64,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub attach_address: u64,
    pub detach_address: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrcpySourceState {
    Waiting,
    Streaming,
    Closed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrcpySourceKind {
    Video,
    Audio,
}

/// 原生 sink 的接纳事实；数据包和字节计数不证明解码或播放。
#[derive(Clone, Debug)]
pub struct ScrcpySourceStatus {
    pub capture_ref: String,
    pub source_id: String,
    pub generation: u64,
    pub kind: ScrcpySourceKind,
    pub codec: String,
    pub status: ScrcpySourceState,
    pub packets: u64,
    pub bytes: u64,
}

pub fn scrcpy_source_status(
    connection_id: String,
    capture_ref: String,
    source_id: String,
) -> Result<ScrcpySourceStatus, String> {
    sdk::source_status(&connection_id, &capture_ref, &source_id)
}

#[derive(Clone)]
pub struct ScrcpySessionInfo {
    pub id: String,
    pub device_name: String,
    pub video_codec: ScrcpyVideoCodec,
    pub width: u32,
    pub height: u32,
    pub source: Option<ScrcpyNativeSource>,
    pub audio_source: Option<ScrcpyNativeSource>,
    pub video_enabled: bool,
    pub audio_enabled: bool,
    pub control_ready: bool,
    pub media_ready: bool,
    pub process_id: Option<u32>,
    pub process_started: Option<u64>,
}

/// 原始进程输出尾部，仅提供执行事实；日志含义由调用方解释。
#[derive(Clone)]
pub struct ScrcpyProcessInfo {
    pub pid: u32,
    pub started: u64,
    pub log_tail: Vec<u8>,
    pub truncated: bool,
}
pub fn scrcpy_process_info(capture_ref: String) -> Result<ScrcpyProcessInfo, String> {
    sdk::process_info(&capture_ref)
}

#[derive(Clone, Copy, Debug)]
pub enum ScrcpyKeyAction {
    Down,
    Up,
}
#[derive(Clone, Copy, Debug)]
pub enum ScrcpyTouchAction {
    Down,
    Up,
    Move,
    Cancel,
    HoverMove,
}

#[derive(Clone, Copy, Debug)]
pub enum ScrcpyControlCompletion {
    Admitted,
    Written,
    ClipboardAcknowledged,
}
pub struct ScrcpyControlReceipt {
    pub completion: ScrcpyControlCompletion,
}

pub async fn scrcpy_inspect(
    capture_ref: String,
    generation: u64,
) -> Result<ScrcpySessionInfo, String> {
    sdk::inspect(&capture_ref, generation).await
}

pub async fn scrcpy_stop_session(capture_ref: String) -> Result<(), String> {
    sdk::stop(&capture_ref).await
}

async fn send(capture_ref: String, message: Message) -> Result<ScrcpyControlReceipt, String> {
    let completion = sdk::send(&capture_ref, message).await?;
    Ok(ScrcpyControlReceipt {
        completion: match completion {
            interop_scrcpy::control::ControlCompletion::Admitted => {
                ScrcpyControlCompletion::Admitted
            }
            interop_scrcpy::control::ControlCompletion::Written => ScrcpyControlCompletion::Written,
            interop_scrcpy::control::ControlCompletion::ClipboardAcknowledged => {
                ScrcpyControlCompletion::ClipboardAcknowledged
            }
        },
    })
}

pub async fn scrcpy_key(
    capture_ref: String,
    action: ScrcpyKeyAction,
    keycode: u32,
    repeat: u32,
    meta_state: u32,
) -> Result<ScrcpyControlReceipt, String> {
    send(
        capture_ref,
        Message::Key {
            action: match action {
                ScrcpyKeyAction::Down => 0,
                ScrcpyKeyAction::Up => 1,
            },
            keycode,
            repeat,
            meta_state,
        },
    )
    .await
}
pub async fn scrcpy_text(
    capture_ref: String,
    text: String,
) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::Text(text)).await
}
#[allow(clippy::too_many_arguments)]
pub async fn scrcpy_touch(
    capture_ref: String,
    action: ScrcpyTouchAction,
    pointer_id: i64,
    x: u32,
    y: u32,
    width: u16,
    height: u16,
    pressure: f64,
    action_button: u32,
    buttons: u32,
) -> Result<ScrcpyControlReceipt, String> {
    if pointer_id < -1 {
        return Err("invalid_argument: 触点标识无效。".into());
    }
    send(
        capture_ref,
        Message::Touch {
            action: match action {
                ScrcpyTouchAction::Down => 0,
                ScrcpyTouchAction::Up => 1,
                ScrcpyTouchAction::Move => 2,
                ScrcpyTouchAction::Cancel => 3,
                ScrcpyTouchAction::HoverMove => 7,
            },
            pointer: pointer_id as u64,
            position: Position {
                x,
                y,
                width,
                height,
            },
            pressure,
            action_button,
            buttons,
        },
    )
    .await
}
#[allow(clippy::too_many_arguments)]
pub async fn scrcpy_scroll(
    capture_ref: String,
    x: u32,
    y: u32,
    width: u16,
    height: u16,
    horizontal: f64,
    vertical: f64,
    buttons: u32,
) -> Result<ScrcpyControlReceipt, String> {
    send(
        capture_ref,
        Message::Scroll {
            position: Position {
                x,
                y,
                width,
                height,
            },
            horizontal,
            vertical,
            buttons,
        },
    )
    .await
}
pub async fn scrcpy_clipboard(
    capture_ref: String,
    text: String,
    paste: bool,
) -> Result<ScrcpyControlReceipt, String> {
    send(
        capture_ref,
        Message::Clipboard {
            text,
            paste,
            sequence: 0,
        },
    )
    .await
}
pub async fn scrcpy_rotate(capture_ref: String) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::Rotate).await
}
pub async fn scrcpy_reset_video(capture_ref: String) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::ResetVideo).await
}
/// 发送上游显示电源请求；写入完成不证明设备已经改变屏幕状态。
pub async fn scrcpy_set_display_power(
    capture_ref: String,
    on: bool,
) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::SetDisplayPower(on)).await
}
/// 仅适用于启用了 flex_display 的新显示，不执行物理屏幕或密度配置。
pub async fn scrcpy_resize_display(
    capture_ref: String,
    width: u16,
    height: u16,
) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::ResizeDisplay { width, height }).await
}
pub async fn scrcpy_start_app(
    capture_ref: String,
    package_name: String,
) -> Result<ScrcpyControlReceipt, String> {
    send(capture_ref, Message::StartApp(package_name)).await
}

/// 只登记可取消句柄，不上传服务器或打开 socket。
pub async fn scrcpy_create_session(
    connection_id: String,
    options: ScrcpyOptions,
) -> Result<String, String> {
    sdk::create(&connection_id, options.native()?).await
}
pub async fn scrcpy_start_session(session_id: String) -> Result<ScrcpySessionInfo, String> {
    sdk::start(&session_id).await
}
/// 接纳通道并启动控制，不等待编码首关键帧；调用方此后可提交 START_APP。
pub async fn scrcpy_start_control(session_id: String) -> Result<ScrcpySessionInfo, String> {
    sdk::start_control(&session_id).await
}
/// 观察同一捕获的媒体就绪，读取未完成不阻止其他调用者发送控制。
pub async fn scrcpy_await_media(
    capture_ref: String,
    generation: u64,
) -> Result<ScrcpySessionInfo, String> {
    sdk::await_media(&capture_ref, generation).await
}

/// 按当前连接句柄排空已登记捕获；失败保留精确清理所有权，调用者可重试。
pub async fn scrcpy_drain_connection(connection_id: String) -> Result<(), String> {
    sdk::drain_connection(&connection_id).await
}
#[derive(Clone, Copy, Debug)]
pub enum ScrcpyLogLevel {
    Verbose,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Clone)]
pub struct ScrcpyDisplayOptions {
    pub width: Option<u16>,
    pub height: Option<u16>,
    pub density: Option<u16>,
}
#[derive(Clone)]
pub struct ScrcpyOptions {
    pub log_level: ScrcpyLogLevel,
    pub video: bool,
    pub audio: bool,
    pub display_id: u32,
    pub keep_active: bool,
    pub power_off_on_close: bool,
    pub stay_awake: bool,
    pub cleanup: bool,
    pub video_codec: ScrcpyVideoCodec,
    pub video_bit_rate: u32,
    pub max_size: u16,
    pub max_fps: u16,
    pub video_encoder: Option<String>,
    pub display: Option<ScrcpyDisplayOptions>,
    pub control: bool,
    pub power_on: bool,
    pub clipboard_autosync: bool,
    pub vd_destroy_content: bool,
    pub flex_display: bool,
    pub vd_system_decorations: bool,
    pub repeat_previous_frame_after_us: Option<u64>,
}
impl ScrcpyOptions {
    #[flutter_rust_bridge::frb(ignore)]
    pub fn native(self) -> Result<interop_scrcpy::config::Options, String> {
        let options = interop_scrcpy::config::Options {
            log_level: match self.log_level {
                ScrcpyLogLevel::Verbose => interop_scrcpy::config::LogLevel::Verbose,
                ScrcpyLogLevel::Debug => interop_scrcpy::config::LogLevel::Debug,
                ScrcpyLogLevel::Info => interop_scrcpy::config::LogLevel::Info,
                ScrcpyLogLevel::Warn => interop_scrcpy::config::LogLevel::Warn,
                ScrcpyLogLevel::Error => interop_scrcpy::config::LogLevel::Error,
            },
            video: self.video,
            audio: self.audio,
            display_id: self.display_id,
            keep_active: self.keep_active,
            power_off_on_close: self.power_off_on_close,
            stay_awake: self.stay_awake,
            cleanup: self.cleanup,
            codec: match self.video_codec {
                ScrcpyVideoCodec::H264 => interop_scrcpy::config::VideoCodec::H264,
                ScrcpyVideoCodec::H265 => interop_scrcpy::config::VideoCodec::H265,
                ScrcpyVideoCodec::Av1 => interop_scrcpy::config::VideoCodec::Av1,
                ScrcpyVideoCodec::Vp8 => interop_scrcpy::config::VideoCodec::Vp8,
                ScrcpyVideoCodec::Vp9 => interop_scrcpy::config::VideoCodec::Vp9,
            },
            bit_rate: self.video_bit_rate,
            max_size: self.max_size,
            max_fps: self.max_fps,
            encoder: self.video_encoder,
            display: self
                .display
                .map(|display| {
                    let size = match (display.width, display.height) {
                        (Some(w), Some(h)) => Some((w, h)),
                        (None, None) => None,
                        _ => return Err("invalid_argument: 显示宽高必须同时提供。".to_owned()),
                    };
                    Ok(interop_scrcpy::config::DisplayOptions {
                        size,
                        density: display.density,
                    })
                })
                .transpose()?,
            control: self.control,
            power_on: self.power_on,
            clipboard_autosync: self.clipboard_autosync,
            vd_destroy_content: self.vd_destroy_content,
            flex_display: self.flex_display,
            vd_system_decorations: self.vd_system_decorations,
            repeat_previous_frame_after_us: self.repeat_previous_frame_after_us,
            process_name_prefix: "scrcpy".into(),
        };
        options.validate().map_err(|error| error.to_string())?;
        Ok(options)
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn stop_connection(connection: &str) {
    sdk::stop_connection(connection);
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn shutdown() {
    sdk::shutdown().await;
}

/// 初始化本宿主使用的受控服务器字节；重复初始化只接受完全相同内容。
pub fn scrcpy_initialize_sdk(server_bytes: Vec<u8>) -> Result<(), String> {
    sdk::initialize_sdk(server_bytes)
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrcpyEventKind {
    ClipboardChanged,
    Stopped,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ScrcpyEvent {
    pub kind: ScrcpyEventKind,
    pub capture_ref: String,
    pub text: Option<String>,
    pub reason: Option<String>,
}
/// 每个观察者独立暂存最新剪贴板和停止终态，不积累历史事件。
pub fn scrcpy_open_events(capture_ref: String) -> Result<String, String> {
    sdk::open_events(&capture_ref)
}
pub async fn scrcpy_next_event(observer_id: String) -> Result<Option<ScrcpyEvent>, String> {
    sdk::next_event(&observer_id).await
}
/// 仅取消当前观察者，唤醒挂起读取；不撤销捕获或媒体来源。
pub fn scrcpy_cancel_events(observer_id: String) -> Result<(), String> {
    sdk::cancel_events(&observer_id);
    Ok(())
}
