//! Fixed scrcpy 5.0.1 protocol: compressed media stays off the Dart event channel.
//! Source: Genymobile/scrcpy v5.0.1 Streamer, DesktopConnection and ControlMessageReader.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, quote, required},
    resource::ResourceStatus,
};
use interop_adb::{AdbStream, CancellationToken, OperationOptions, RemoteSocket, sync::RemotePath};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    sync::{Mutex, RwLock, Semaphore, mpsc, oneshot},
    time::Instant,
};

pub(crate) const SERVER: &[u8] = include_bytes!("../../../servers/vendor/scrcpy-server-v5.0.1");
pub(crate) const SERVER_SHA: &str =
    "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536";
const MAX_PACKET: usize = 16 * 1024 * 1024;
const CLIPBOARD_MAX: usize = (1 << 18) - 14;
// Acquire before spawning: repeatedly cancelled catalog initializers cannot
// leave an unbounded number of detached probe uploads/processes behind.
static ENCODER_PROBE_JOBS: Semaphore = Semaphore::const_new(4);

fn encoder_probe_command(path: &str) -> CoreResult<String> {
    let path = quote(path)?;
    Ok(format!(
        "CLASSPATH={path} app_process / com.genymobile.scrcpy.Server 5.0.1 list_encoders=true cleanup=true log_level=info; interop_probe_status=$?; rm -f -- {path}; exit \"$interop_probe_status\""
    ))
}

#[derive(Clone, Copy)]
struct VideoCodec {
    name: &'static str,
    label: &'static str,
    mime: &'static str,
    wire: [u8; 4],
}
// Fixed v5.0.1 VideoCodec.java IDs, including leading zeroes for 3-byte names.
const VIDEO_CODECS: [VideoCodec; 5] = [
    VideoCodec {
        name: "h264",
        label: "H.264",
        mime: "video/avc",
        wire: *b"h264",
    },
    VideoCodec {
        name: "h265",
        label: "H.265",
        mime: "video/hevc",
        wire: *b"h265",
    },
    VideoCodec {
        name: "av1",
        label: "AV1",
        mime: "video/av01",
        wire: *b"\0av1",
    },
    VideoCodec {
        name: "vp8",
        label: "VP8",
        mime: "video/x-vnd.on2.vp8",
        wire: *b"\0vp8",
    },
    VideoCodec {
        name: "vp9",
        label: "VP9",
        mime: "video/x-vnd.on2.vp9",
        wire: *b"\0vp9",
    },
];

fn video_codec(name: &str) -> CoreResult<VideoCodec> {
    VIDEO_CODECS
        .iter()
        .find(|codec| codec.name == name)
        .copied()
        .ok_or_else(|| invalid("视频编码格式无效。"))
}

// A live decoder may wait for subsequent frames even when the remote screen is
// static. Bound the repeat timeout by a 30fps frame period and respect a
// user's lower FPS choice. This option is a timeout, not a steady frame rate.
fn repeat_frame_delay_us(max_fps: u64) -> u64 {
    1_000_000u64.div_ceil(max_fps.clamp(1, 30))
}

#[derive(Clone)]
pub(crate) struct VideoEncoder {
    codec: String,
    name: String,
    hardware: Option<bool>,
}

fn parse_encoders(text: &str) -> CoreResult<Vec<VideoEncoder>> {
    if !text.contains("List of video encoders:") {
        return Err(CoreError::new(
            "encoder_probe",
            "设备未返回可识别的编码器列表。",
        ));
    }
    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for line in text.lines().filter(|line| line.contains("--video-codec=")) {
        let fields: Vec<_> = line.split_ascii_whitespace().collect();
        let codec = fields
            .iter()
            .find_map(|field| field.strip_prefix("--video-codec="))
            .ok_or_else(|| CoreError::new("encoder_probe", "编码器列表格式无效。"))?;
        let name = fields
            .iter()
            .find_map(|field| field.strip_prefix("--video-encoder="))
            .filter(|name| crate::preferences::valid_encoder(name))
            .ok_or_else(|| CoreError::new("encoder_probe", "设备返回的编码器名称无效。"))?;
        video_codec(codec)?;
        if seen.insert((codec.to_owned(), name.to_owned())) {
            result.push(VideoEncoder {
                codec: codec.into(),
                name: name.into(),
                hardware: if fields.contains(&"(hw)") {
                    Some(true)
                } else if fields.contains(&"(sw)") {
                    Some(false)
                } else {
                    None
                },
            });
        }
        if result.len() > 1024 {
            return Err(CoreError::new("encoder_probe", "编码器列表超出限制。"));
        }
    }
    Ok(result)
}

fn selected_video(settings: &Value) -> CoreResult<(VideoCodec, Option<&str>)> {
    let codec = video_codec(settings["videoCodec"].as_str().unwrap_or("h264"))?;
    let encoder = match &settings["videoEncoder"] {
        Value::Null => None,
        Value::String(value) if crate::preferences::valid_encoder(value) => Some(value.as_str()),
        _ => return Err(invalid("视频编码器名称无效。")),
    };
    Ok((codec, encoder))
}

fn validate_encoder_selection(settings: &Value, encoders: &[VideoEncoder]) -> CoreResult<()> {
    let (codec, encoder) = selected_video(settings)?;
    if !encoders
        .iter()
        .any(|entry| entry.codec == codec.name && encoder.is_none_or(|name| entry.name == name))
    {
        return Err(CoreError::new(
            "encoder_unavailable",
            "这台设备未枚举到所选格式与编码器组合；现有会话保持运行。",
        ));
    }
    Ok(())
}

fn current_quality(settings: &Value) -> Value {
    json!({"preset":settings["qualityPreset"],"maxSize":settings["maxSize"],"maxFps":settings["maxFps"],
        "bitRate":settings["videoBitRate"],"videoBitRate":settings["videoBitRate"],"codec":settings["videoCodec"],
        "videoCodec":settings["videoCodec"],"videoEncoder":settings["videoEncoder"],"audio":false})
}

fn record_decoded_size(state: &mut Value, receipt: &Value) {
    let dimensions = receipt["decodedWidth"]
        .as_u64()
        .zip(receipt["decodedHeight"].as_u64());
    if let Some((width, height)) = dimensions
        && (1..=16384).contains(&width)
        && (1..=16384).contains(&height)
        && width * height <= 67_108_864
    {
        state["decodedWidth"] = json!(width);
        state["decodedHeight"] = json!(height);
    }
}

fn quality_patch(current: &Value, params: &Value) -> CoreResult<Value> {
    let mut next = current.clone();
    if let Some(value) = params.get("preset") {
        let (size, fps, rate) = match value.as_str() {
            Some("smooth") => (720, 30, 2_000_000),
            Some("balanced") => (1280, 60, 8_000_000),
            Some("clear") => (1920, 60, 12_000_000),
            _ => return Err(invalid("画质预设无效。")),
        };
        next["qualityPreset"] = value.clone();
        next["maxSize"] = json!(size);
        next["maxFps"] = json!(fps);
        next["videoBitRate"] = json!(rate);
    }
    for (key, alias) in [
        ("maxSize", "maxSize"),
        ("maxFps", "maxFps"),
        ("videoBitRate", "bitRate"),
        ("videoCodec", "codec"),
        ("videoEncoder", "encoder"),
    ] {
        if let Some(value) = params.get(key).or_else(|| params.get(alias)) {
            next[key] = value.clone();
        }
    }
    if ["audioMode", "audioEnabled", "audioCodec"]
        .iter()
        .any(|key| params.get(key).is_some())
    {
        return Err(invalid("设备声音设置请使用独立音源设置。"));
    }
    let quality: serde_json::Map<String, Value> = crate::preferences::QUALITY_KEYS
        .iter()
        .map(|key| ((*key).to_owned(), next[*key].clone()))
        .collect();
    crate::preferences::validate_quality(&Value::Object(quality))?;
    selected_video(&next)?;
    Ok(next)
}

pub(crate) struct Session {
    device_id: String,
    package: Option<String>,
    cancellation: CancellationToken,
    control: mpsc::Sender<ControlRequest>,
    state: Arc<RwLock<Value>>,
    process_closed: Arc<AtomicBool>,
    process: Option<OwnedProcess>,
}

impl Session {
    pub(crate) async fn activity_snapshot(&self) -> Option<Value> {
        let state = self.state.read().await;
        (!self.cancellation.is_cancelled() || state["launchOutcome"] == "unknown")
            .then(|| state.clone())
    }
}
#[derive(Clone)]
struct OwnedProcess {
    pid: u32,
    started: u64,
    jar: String,
    scid: String,
}

fn launch_identity(bytes: &[u8]) -> CoreResult<(u32, u64)> {
    let parsed = std::str::from_utf8(bytes)
        .ok()
        .and_then(|line| line.strip_prefix("__INTEROP_PID__"))
        .and_then(|fields| fields.split_once(':'))
        .filter(|(pid, started)| {
            !pid.is_empty()
                && !started.is_empty()
                && pid.bytes().all(|byte| byte.is_ascii_digit())
                && started.bytes().all(|byte| byte.is_ascii_digit())
        })
        .and_then(|(pid, started)| Some((pid.parse::<u32>().ok()?, started.parse::<u64>().ok()?)))
        .filter(|(pid, started)| *pid > 1 && *started > 0);
    parsed.ok_or_else(|| CoreError::new("process_identity", "服务进程启动标识缺失或无效。"))
}

impl OwnedProcess {
    async fn capture(
        client: &interop_adb::Client,
        pid: u32,
        started: u64,
        jar: &str,
        scid: String,
    ) -> CoreResult<Self> {
        // The launcher's shell reads the child start time before handing it
        // over. exec preserves it. Verify the same kernel identity and the
        // complete JAR/SCID nice-name below, without a second stat request.
        let process = Self {
            pid,
            started,
            jar: jar.to_owned(),
            scid,
        };
        process.verify(client).await?;
        Ok(process)
    }

    async fn verify(&self, client: &interop_adb::Client) -> CoreResult<()> {
        // Revalidate in the shell, including the kernel start time,
        // rather than retaining a numeric PID across independent shell calls.
        // app_process rewrites argv[0]; explicitly give it a unique nice-name
        // containing both our private JAR path and SCID, then match that whole arg.
        let identity = quote(&format!("\ninterop.scrcpy:{}:{}\n", self.scid, self.jar))?;
        let command = format!(
            r#"p={pid}
expected={started}
identity() {{
  IFS= read -r stat < /proc/$p/stat || return 1
  rest=${{stat##*) }}
  set -- $rest
  state=$1
  shift 19 || return 1
  [ "$1" = "$expected" ] || return 1
  cmd=$(tr '\000' '\n' < /proc/$p/cmdline) || return 1
  cmd="
$cmd
"
  case "$cmd" in *{identity}*) ;; *) return 1 ;; esac
}}
identity || {{ printf 'identity-mismatch\n'; exit 41; }}
case "$state" in R|S|D|I) printf 'verified:%s\n' "$state"; exit 0 ;; esac
exit 43"#,
            pid = self.pid,
            started = self.started,
        );
        let output = client
            .shell(
                &command,
                4096,
                OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                },
            )
            .await?;
        if output.exit_code.is_some_and(|code| code != 0)
            || !output.stdout.starts_with(b"verified:")
        {
            return Err(CoreError::new(
                "process_identity",
                "无法确认本会话服务进程的身份。",
            ));
        }
        Ok(())
    }
}
impl Drop for Session {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}
enum ControlRequest {
    Launch(Vec<u8>, crate::app_open::LaunchPermit, ControlReply),
    Send(Vec<u8>, ControlReply),
    ClipboardSet(String, bool, ControlReply),
}
impl ControlRequest {
    fn reply(&self) -> &ControlReply {
        match self {
            Self::Launch(_, _, reply) | Self::Send(_, reply) | Self::ClipboardSet(_, _, reply) => {
                reply
            }
        }
    }
}
// The same deadline travels through queue admission, the ADB write receipt,
// and any protocol acknowledgement. An expired input is never submitted later.
struct ControlReply {
    deadline: Instant,
    sender: oneshot::Sender<CoreResult<Value>>,
}
impl ControlReply {
    fn is_closed(&self) -> bool {
        self.sender.is_closed() || Instant::now() >= self.deadline
    }

    fn send(self, result: CoreResult<Value>) -> Result<(), CoreResult<Value>> {
        self.sender.send(result)
    }
}
struct CancelOnDrop(Option<CancellationToken>);
struct SessionContext {
    cancellation: CancellationToken,
    state: Arc<RwLock<Value>>,
    events: crate::events::EventBus,
    device: String,
}
impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        if let Some(token) = &self.0 {
            token.cancel();
        }
    }
}

fn options(token: &CancellationToken) -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(365 * 86400),
        cancellation: token.clone(),
    }
}
fn event(events: &crate::events::EventBus, kind: &str, device: &str, data: Value) {
    let _ = events.send(json!({"type":kind,"deviceId":device,"data":data,"timestamp":now()}));
}
fn invalid(message: &str) -> CoreError {
    CoreError::new("invalid_argument", message)
}
pub(crate) fn package_name(value: &str) -> CoreResult<&str> {
    if value.is_empty()
        || value.len() > 230
        || !value.split('.').all(|part| {
            let mut bytes = part.bytes();
            bytes
                .next()
                .is_some_and(|b| b.is_ascii_alphabetic() || b == b'_')
                && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
        })
    {
        return Err(invalid("应用包名无效。"));
    }
    Ok(value)
}

fn unknown_app_launch(state: &Value) -> CoreError {
    let mut error = CoreError::new(
        "app_launch_unknown",
        "应用打开请求已提交，但结果无法确认。应用可能已打开或迁移；请核对手机并明确关闭本次记录后再选择重新打开。",
    );
    error.details = state.clone();
    error
}

impl Runtime {
    async fn session_resource_busy(&self, busy: crate::resource::ResourceBusy) -> CoreError {
        let mut error: CoreError = busy.into();
        let mut important = Vec::new();
        // Read existing observations only: rejection must not start a companion,
        // reconnect a device, pause audio, or send a call action.
        if let Ok(sources) = self.audio_command("audio.sources", &json!({})).await
            && let Some(sources) = sources["sources"].as_array()
        {
            for source in sources {
                important.push(
                    json!({"id":format!("audio:{}",source["sourceId"].as_str().unwrap_or_default()),
                    "deviceId":source["deviceId"],"kind":"audio","status":source["status"],
                    "canPause":source["status"]=="playing","preserved":true}),
                );
            }
        }
        let companions = self
            .companions
            .lock()
            .await
            .iter()
            .map(|(device, companion)| (device.clone(), companion.clone()))
            .collect::<Vec<_>>();
        for (device, companion) in companions {
            let observed = companion.capability_state().await;
            if let Some(calls) = observed["calls"]["calls"].as_array()
                && !calls.is_empty()
            {
                important.push(
                    json!({"id":format!("call-observation:{device}"),"deviceId":device,
                    "kind":"call_observation","aggregate":true,"status":observed["calls"]["status"],
                    "canPause":false,"preserved":true}),
                );
            }
        }
        error.details["importantActivities"] = json!(important);
        error.details["automaticStop"] = json!(false);
        error
    }

    pub(crate) async fn start_session(&self, params: &Value) -> CoreResult<Value> {
        let result = async {
            let device = required(params, "deviceId")?;
            let settings = crate::preferences::quality_settings(
                &self.store.read().await.settings,
                Some(device),
            );
            let settings = quality_patch(&settings, params)?;
            // This startup state includes the complete media/process handshake.
            // Keep it out of the session entry's nested async frames: debug
            // builds otherwise exhaust a standard 2 MiB caller thread stack.
            Box::pin(self.start_session_with_settings(params, &settings)).await
        }
        .await;
        result.map_err(|mut error| {
            if error.code != "app_launch_unknown" {
                if !error.details.is_object() {
                    error.details = json!({});
                }
                error.details["launchOutcome"] = json!("not_submitted");
            }
            error
        })
    }

    async fn start_session_with_settings(
        &self,
        params: &Value,
        settings: &Value,
    ) -> CoreResult<Value> {
        // Cumulative milestones use one local monotonic clock. They measure
        // startup work, never latency by subtracting the device's media PTS.
        let startup_clock = Instant::now();
        let mut startup_timing = serde_json::Map::new();
        let device_id = required(params, "deviceId")?.to_owned();
        let (selected_codec, selected_encoder) = selected_video(settings)?;
        let package = params
            .get("packageName")
            .and_then(Value::as_str)
            .map(package_name)
            .transpose()?
            .map(str::to_owned);
        if let Some(package) = &package {
            self.app_opens.ensure_available(&device_id, package).await?;
        }
        let client = self.client(&device_id).await?;
        if package.is_some() {
            for session in self.activities.sessions.lock().await.values() {
                if session.device_id == device_id && session.package == package {
                    let observed = session.state.read().await;
                    if observed["launchOutcome"] == "unknown" {
                        return Err(unknown_app_launch(&observed));
                    }
                }
            }
        }
        let device = self.device(&device_id).await?;
        if package.is_some() && device.api_level.is_some_and(|level| level < 29) {
            return Err(CoreError::new(
                "unsupported",
                "独立应用窗口需要 Android 10 或更新版本。",
            ));
        }
        if format!("{:x}", Sha256::digest(SERVER)) != SERVER_SHA {
            return Err(CoreError::new("server_integrity", "内置控制服务校验失败。"));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let activity_id = crate::activities::ActivityRef::Session(&id).to_string();
        let cancellation = CancellationToken::new();
        let mut guard = CancelOnDrop(Some(cancellation.clone()));
        let reservation = match self.activities.admission.reserve_session(
            activity_id.clone(),
            device_id.clone(),
            package.clone().unwrap_or_else(|| "手机屏幕".into()),
            cancellation.clone(),
        ) {
            Ok(reservation) => reservation,
            Err(busy) => return Err(self.session_resource_busy(busy).await),
        };
        // Like scrcpy's normal startup, default H264 screen capture can try the
        // platform-selected encoder directly. Unknown is not an availability
        // claim: actual metadata, keyframe and local decoding still gate ready.
        // Keep strict preflight for explicit choices and real application tasks
        // (START_APP may migrate a task before the first encoded frame).
        let requires_enumeration =
            package.is_some() || selected_codec.name != "h264" || selected_encoder.is_some();
        // Join any real probe through cleanup before rejecting sleep. A cached
        // catalog remains authoritative when the default path does not probe.
        let (sleeping, encoders) = tokio::join!(
            async {
                if package.is_none() {
                    self.device_sleeping(&device_id).await
                } else {
                    Ok(None)
                }
            },
            async {
                if requires_enumeration {
                    self.probe_video_encoders(&device_id).await.map(Some)
                } else {
                    self.encoder_catalog.peek(&client).await
                }
            },
        );
        if sleeping? == Some(true) {
            return Err(CoreError::new(
                "device_asleep",
                "手机当前处于系统休眠，尚未提供画面。可在手机上唤醒，或明确选择唤醒手机；这可能点亮实体屏幕，仍需使用手机自身的锁屏解锁。",
            ));
        }
        if let Some(encoders) = encoders? {
            validate_encoder_selection(settings, &encoders)?;
        }
        startup_timing.insert(
            "validatedMs".into(),
            json!(startup_clock.elapsed().as_millis() as u64),
        );
        if cancellation.is_cancelled() {
            return Err(CoreError::new(
                "cancelled",
                "新的控制会话启动已取消；已有活动保持不变。",
            ));
        }
        let video_token = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        let return_token = video_token.clone();
        let scid = u32::from_be_bytes(
            uuid::Uuid::new_v4().as_bytes()[..4]
                .try_into()
                .expect("UUID"),
        ) & 0x7fff_ffff;
        let remote_jar = format!("/data/local/tmp/interop-scrcpy-{id}.jar");
        let state = Arc::new(RwLock::new(
            json!({"sessionId":id,"id":id,"deviceId":device_id,"name":package.as_deref().unwrap_or("手机屏幕"),"packageName":package,"status":"starting","createdAt":now(),"codec":selected_codec.name,"mime":selected_codec.mime,"videoEncoder":selected_encoder,"encoderSelection":if selected_encoder.is_some(){"explicit"}else{"platformDefault"},"quality":current_quality(settings),"audio":false,"apiLevel":device.api_level}),
        ));
        if params["traceFrames"].as_bool() == Some(true) {
            state.write().await["transportTrace"] = json!([]);
        }
        let cleanup_cancel = cancellation.clone();
        let cleanup_client = client.clone();
        let cleanup_path = remote_jar.clone();
        let cleanup_state = state.clone();
        let cleanup_events = self.events.clone();
        let cleanup_device = device_id.clone();
        tokio::spawn(async move {
            cleanup_cancel.cancelled().await;
            reservation.stopping();
            {
                let mut data = cleanup_state.write().await;
                if data["status"] != "failed" {
                    data["status"] = json!("stopped");
                }
                data.as_object_mut()
                    .expect("session state")
                    .remove("textureId");
                data.as_object_mut()
                    .expect("session state")
                    .remove("videoPort");
                event(
                    &cleanup_events,
                    "session.disconnected",
                    &cleanup_device,
                    data.clone(),
                );
            }
            let cleanup = format!("rm -f -- {}", quote(&cleanup_path).expect("generated path"));
            let _ = cleanup_client
                .shell(
                    &cleanup,
                    4096,
                    OperationOptions {
                        timeout: Duration::from_secs(3),
                        ..Default::default()
                    },
                )
                .await;
            // Hold the application slot through teardown, including EOF and
            // startup failures. A cancelled task cannot orphan its reservation.
            drop(reservation);
        });
        let max_size = settings["maxSize"]
            .as_u64()
            .unwrap_or(1280)
            .clamp(320, 4096);
        let max_fps = settings["maxFps"].as_u64().unwrap_or(60).clamp(1, 120);
        let repeat_delay = repeat_frame_delay_us(max_fps);
        let bit_rate = settings["videoBitRate"]
            .as_u64()
            .unwrap_or(8_000_000)
            .clamp(500_000, 50_000_000);
        let mut app_launch_submitted = false;
        let startup = async {
            let mut sync = client.sync(OperationOptions::default()).await?;
            sync.push(
                &RemotePath::new(&remote_jar)?,
                &mut &SERVER[..],
                0o600,
                now().min(u32::MAX as u64) as u32,
                SERVER.len() as u64,
            )
            .await?;
            drop(sync);
            startup_timing.insert(
                "uploadedMs".into(),
                json!(startup_clock.elapsed().as_millis() as u64),
            );
            let mut command = format!(
                "CLASSPATH={} app_process / --nice-name={} com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn video=true audio=false control=true video_codec={} max_size={max_size} max_fps={max_fps} video_bit_rate={bit_rate} tunnel_forward=true cleanup=true vd_destroy_content=false clipboard_autosync=false power_on=false send_dummy_byte=true send_device_meta=true send_stream_meta=true send_frame_meta=true",
                quote(&remote_jar)?,
                quote(&format!("interop.scrcpy:{scid:08x}:{remote_jar}"))?,
                selected_codec.name,
            );
            command.push_str(&format!(
                " video_codec_options=repeat-previous-frame-after:long={repeat_delay}"
            ));
            if let Some(encoder) = selected_encoder {
                command.push(' ');
                command.push_str(&quote(&format!("video_encoder={encoder}"))?);
            }
            if package.is_some() {
                command.push_str(" new_display=1080x1920 vd_system_decorations=false");
            }
            // Keep the launcher's stdin open while reporting the child identity.
            command = format!(
                r#"{command} </dev/null &
child=$!
IFS= read -r stat < /proc/$child/stat || exit 40
rest=${{stat##*) }}
set -- $rest
shift 19 || exit 40
started=$1
case "$started" in ''|*[!0-9]*) exit 40 ;; esac
printf '__INTEROP_PID__%s:%s\n' "$child" "$started"
while IFS= read -r keepalive; do :; done
wait "$child""#
            );
            let mut process = client.exec(&command, options(&cancellation)).await?;
            let mut pid_line = Vec::new();
            loop {
                let mut byte = [0];
                process.read_exact(&mut byte).await?;
                if byte[0] == b'\n' {
                    break;
                }
                pid_line.push(byte[0]);
                if pid_line.len() > 64 {
                    return Err(CoreError::new("process_identity", "服务进程启动标识无效。"));
                }
            }
            let (pid, started) = launch_identity(&pid_line)?;
            let process_closed = Arc::new(AtomicBool::new(false));
            let logs = Arc::new(Mutex::new(Vec::new()));
            let process_cancel = cancellation.clone();
            let process_closed_task = process_closed.clone();
            let process_logs = logs.clone();
            let process_state = state.clone();
            tokio::spawn(async move {
                let mut buffer = [0; 4096];
                loop {
                    let result = tokio::select! { _ = process_cancel.cancelled() => break, result = process.read(&mut buffer) => result };
                    match result {
                        Ok(0) | Err(_) => break,
                        Ok(count) => {
                            let mut logs = process_logs.lock().await;
                            let room = 16_384usize.saturating_sub(logs.len());
                            logs.extend_from_slice(&buffer[..count.min(room)]);
                        }
                    }
                }
                if !process_cancel.is_cancelled() {
                    let detail = String::from_utf8_lossy(&process_logs.lock().await)
                        .trim()
                        .to_owned();
                    let mut state = process_state.write().await;
                    state["status"] = json!("failed");
                    state["reason"] = json!(if detail.is_empty() {
                        "被控端的窗口服务已结束，请检查连接后重新打开。".to_owned()
                    } else {
                        detail
                    });
                }
                process_closed_task.store(true, Ordering::Release);
                process_cancel.cancel();
            });
            let socket = RemoteSocket::LocalAbstract(format!("scrcpy_{scid:08x}"));
            let deadline = Instant::now() + Duration::from_secs(12);
            let mut video = loop {
                if process_closed.load(Ordering::Acquire) {
                    return Err(CoreError::new(
                        "server_start_failed",
                        String::from_utf8_lossy(&logs.lock().await).to_string(),
                    ));
                }
                match tokio::time::timeout(
                    Duration::from_millis(600),
                    client.connect_socket(&socket, options(&cancellation)),
                )
                .await
                {
                    Ok(Ok(video)) => break video,
                    Ok(Err(error)) if Instant::now() >= deadline => return Err(error.into()),
                    Err(_) if Instant::now() >= deadline => {
                        return Err(CoreError::new("timeout", "控制服务套接字未就绪。"));
                    }
                    _ => tokio::time::sleep(Duration::from_millis(40)).await,
                }
            };
            // This socket must be connected before reading device metadata: adbd's
            // server sends metadata only after all enabled channels are accepted.
            let control = client
                .connect_socket(&socket, options(&cancellation))
                .await?;
            let mut dummy = [0];
            video.read_exact(&mut dummy).await?;
            if dummy != [0] {
                return Err(CoreError::new("video_protocol", "控制服务连接标识无效。"));
            }
            let mut name = [0; 64];
            video.read_exact(&mut name).await?;
            let mut codec = [0; 4];
            video.read_exact(&mut codec).await?;
            if codec != selected_codec.wire {
                return Err(CoreError::new(
                    "video_codec",
                    "设备实际视频编码与请求格式不一致。",
                ));
            }
            let mut initial = [0; 12];
            video.read_exact(&mut initial).await?;
            startup_timing.insert(
                "metadataMs".into(),
                json!(startup_clock.elapsed().as_millis() as u64),
            );
            // Streamer writes the codec ID before MediaCodec.configure(). Wait
            // for encoded output, not just metadata, before reporting encoder readiness.
            // A decoration-free virtual display may stay blank until START_APP.
            // Like upstream's independent controller/demuxer threads, do not
            // wait for an encoded frame before launching its real application.
            let (control_tx, control_rx) = mpsc::channel(64);
            let actor_cancel = cancellation.clone();
            let actor_events = self.events.clone();
            let actor_device = device_id.clone();
            let actor_state = state.clone();
            tokio::spawn(async move {
                run_control(
                    control,
                    control_rx,
                    actor_cancel,
                    actor_events,
                    actor_device,
                    actor_state,
                )
                .await;
            });
            if let Some(package_name) = &package {
                // Persist the operation identity before a possibly partial write.
                // START_APP has no application-completion acknowledgement. A
                // timeout, cancellation or lost write receipt cannot justify replay.
                let permit = self
                    .app_opens
                    .begin(&id, &id, &device_id, package_name)
                    .await?;
                app_launch_submitted = true;
                state.write().await["launchOperationId"] = json!(id);
                let mut sessions = self.activities.sessions.lock().await;
                for session in sessions.values() {
                    if session.device_id == device_id && session.package == package {
                        let observed = session.state.read().await;
                        if observed["launchOutcome"] == "unknown" {
                            return Err(unknown_app_launch(&observed));
                        }
                    }
                }
                state.write().await["launchOutcome"] = json!("unknown");
                sessions.insert(
                    id.clone(),
                    Session {
                        device_id: device_id.clone(),
                        package: package.clone(),
                        cancellation: cancellation.clone(),
                        control: control_tx.clone(),
                        state: state.clone(),
                        process_closed: process_closed.clone(),
                        process: None,
                    },
                );
                drop(sessions);
                let mut bytes = vec![16, package_name.len() as u8];
                bytes.extend_from_slice(package_name.as_bytes());
                request_launch(&control_tx, bytes, permit).await?;
            }
            // Metadata proves app_process has reached its configured socket.
            // Verify its launcher-recorded identity while the encoder produces
            // the first key frame. Both must succeed before publishing an input.
            // try_join keeps cancellation local: neither operation is detached.
            let encoded = async {
                let frame = read_video_preface(&mut video, initial).await?;
                Ok::<_, CoreError>((frame, startup_clock.elapsed().as_millis() as u64))
            };
            let verified = async {
                let process = OwnedProcess::capture(
                    &client,
                    pid,
                    started,
                    &remote_jar,
                    format!("{scid:08x}"),
                )
                .await?;
                Ok::<_, CoreError>((process, startup_clock.elapsed().as_millis() as u64))
            };
            let (((preface, width, height), encoded_ms), (process, verified_ms)) =
                tokio::try_join!(encoded, verified)?;
            startup_timing.insert("encodedKeyFrameMs".into(), json!(encoded_ms));
            startup_timing.insert("processVerifiedMs".into(), json!(verified_ms));
            let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
            let port = listener.local_addr()?.port();
            {
                let mut data = state.write().await;
                data["videoPort"] = json!(port);
                data["width"] = json!(width);
                data["height"] = json!(height);
                data["encodedKeyFrameReady"] = json!(true);
                data["deviceName"] = json!(String::from_utf8_lossy(
                    &name[..name.iter().position(|b| *b == 0).unwrap_or(64)]
                ));
            }
            let video_cancel = cancellation.clone();
            let video_state = state.clone();
            let video_events = self.events.clone();
            let video_device = device_id.clone();
            tokio::spawn(async move {
                run_video(
                    listener,
                    video_token,
                    video,
                    preface,
                    SessionContext {
                        cancellation: video_cancel,
                        state: video_state,
                        events: video_events,
                        device: video_device,
                    },
                )
                .await;
            });
            Ok::<_, CoreError>((control_tx, process_closed, process))
        };
        let started = tokio::select! {
            _ = cancellation.cancelled() => Err(CoreError::new("cancelled", "新的控制会话启动已取消；已有活动保持不变。")),
            result = tokio::time::timeout(Duration::from_secs(20), startup) => result
                .map_err(|_| CoreError::new("timeout", "控制服务启动超时。"))
                .and_then(|result| result),
        };
        let started = started.and_then(|result| {
            if cancellation.is_cancelled() {
                Err(CoreError::new(
                    "cancelled",
                    "新的控制会话启动已取消；已有活动保持不变。",
                ))
            } else {
                Ok(result)
            }
        });
        let (control, process_closed, process) = match started {
            Ok(started) => started,
            Err(error) if app_launch_submitted => {
                cancellation.cancel();
                // Admission was durable before START_APP. A failed terminal
                // write leaves pending evidence, which also blocks replay.
                let _ = self.app_opens.finish(&id, Some(&error.code)).await;
                let mut observed = state.write().await;
                observed["status"] = json!("failed");
                observed["launchOutcome"] = json!("unknown");
                observed["failureCode"] = json!(error.code);
                let unknown = unknown_app_launch(&observed);
                observed["reason"] = json!(unknown.message);
                return Err(unknown_app_launch(&observed));
            }
            Err(error) => return Err(error),
        };
        if app_launch_submitted && let Err(error) = self.app_opens.finish(&id, None).await {
            cancellation.cancel();
            let mut observed = state.write().await;
            observed["status"] = json!("failed");
            observed["launchOutcome"] = json!("unknown");
            observed["failureCode"] = json!(error.code);
            observed["reason"] = json!(unknown_app_launch(&observed).message);
            return Err(unknown_app_launch(&observed));
        }
        let mut result = {
            let mut observed = state.write().await;
            startup_timing.insert(
                "totalMs".into(),
                json!(startup_clock.elapsed().as_millis() as u64),
            );
            observed["captureStartupTimingMs"] = Value::Object(startup_timing);
            if app_launch_submitted {
                observed["launchOutcome"] = json!("observed");
            }
            observed.clone()
        };
        result["videoToken"] = json!(return_token);
        let mut sessions = self.activities.sessions.lock().await;
        if app_launch_submitted {
            // Updating avoids dropping the provisional owner and cancelling
            // the live control service shared with the completed session.
            let Some(session) = sessions.get_mut(&id) else {
                return Err(CoreError::new("cancelled", "本次打开已明确关闭。"));
            };
            session.process = Some(process);
        } else {
            sessions.insert(
                id,
                Session {
                    device_id,
                    package,
                    cancellation,
                    control,
                    state,
                    process_closed,
                    process: Some(process),
                },
            );
        }
        guard.0 = None;
        Ok(result)
    }

    pub(crate) async fn stop_device_sessions(&self, device: &str) {
        self.activities.admission.cancel_device(device);
        let ids = self
            .activities
            .sessions
            .lock()
            .await
            .iter()
            .filter(|(_, s)| s.device_id == device)
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        for id in ids {
            let keep_unknown = {
                let sessions = self.activities.sessions.lock().await;
                if let Some(session) = sessions.get(&id) {
                    let unknown = session.state.read().await["launchOutcome"] == "unknown";
                    if unknown {
                        session.cancellation.cancel();
                    }
                    unknown
                } else {
                    false
                }
            };
            if keep_unknown {
                continue;
            }
            self.stop_session(&id).await;
        }
    }

    async fn stop_session(&self, id: &str) {
        let process_closed = self
            .activities
            .sessions
            .lock()
            .await
            .remove(id)
            .map(|session| session.process_closed.clone());
        if let Some(closed) = process_closed {
            let _ = tokio::time::timeout(Duration::from_secs(3), async {
                while !closed.load(Ordering::Acquire) {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await;
        }
    }

    pub(crate) async fn session_command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        if command == "session.stop"
            && params["keepLaunchRecord"] != true
            && let Some(id) = params["sessionId"].as_str()
            && self
                .app_opens
                .close(id, params["deviceId"].as_str())
                .await?
            && !self.activities.sessions.lock().await.contains_key(id)
        {
            self.emit(
                "session.updated",
                params["deviceId"].as_str(),
                json!({"sessionId":id,"status":"stopped"}),
            );
            return Ok(json!({"sessionId":id,"status":"stopped","applicationStopped":false}));
        }
        if command == "session.stop"
            && let Some(id) = params["sessionId"].as_str()
            && !self.activities.sessions.lock().await.contains_key(id)
            && self
                .activities
                .admission
                .cancel(&crate::activities::ActivityRef::Session(id).to_string())
        {
            return Ok(
                json!({"sessionId":id,"status":"stopping","starting":true,"applicationStopped":false}),
            );
        }
        if command == "session.list" {
            let mut result = Vec::new();
            for session in self.activities.sessions.lock().await.values() {
                if params["deviceId"]
                    .as_str()
                    .is_none_or(|device| device == session.device_id)
                {
                    result.push(session.state.read().await.clone());
                }
            }
            for record in self.app_opens.unresolved(params["deviceId"].as_str()).await {
                if !result
                    .iter()
                    .any(|session| session["sessionId"] == record["sessionId"])
                {
                    result.push(record);
                }
            }
            return Ok(json!({"sessions":result}));
        }
        if command == "session.quality.options" {
            return self.quality_options(params).await;
        }
        if command == "session.quality" {
            return self.change_quality(params).await;
        }
        if command == "session.screenshot" {
            return self.screenshot(params).await;
        }
        let (id, control, state, package, process, cancellation, session_device) = {
            let sessions = self.activities.sessions.lock().await;
            let session_id = params["sessionId"].as_str();
            let device_id = params["deviceId"].as_str();
            let mut matching = sessions.iter().filter(|(id, session)| {
                session_id.map_or_else(
                    || device_id.is_some_and(|device| device == session.device_id),
                    |wanted| *id == wanted,
                )
            });
            let (id, session) = matching.next().ok_or_else(|| {
                CoreError::new("session_required", "请先打开这台设备的实时画面。")
            })?;
            if session_id.is_none() && matching.next().is_some() {
                return Err(CoreError::new(
                    "ambiguous_session",
                    "这台设备有多个窗口，请选择需要操作的窗口。",
                ));
            }
            if device_id.is_some_and(|device| device != session.device_id) {
                return Err(invalid("会话不属于所选设备。"));
            }
            if session.cancellation.is_cancelled() && command != "session.stop" {
                return Err(CoreError::new(
                    "disconnected",
                    "控制会话已结束，请重新打开。",
                ));
            }
            (
                id.clone(),
                session.control.clone(),
                session.state.clone(),
                session.package.clone(),
                session.process.clone(),
                session.cancellation.clone(),
                session.device_id.clone(),
            )
        };
        if command == "session.stop" {
            if params["keepLaunchRecord"] == true && package.is_some() {
                // Renderer setup can fail after an app was opened. Tear down
                // capture resources while retaining its fixed operation record.
                let persisted = self
                    .app_opens
                    .finish(&id, Some("renderer_start_failed"))
                    .await;
                cancellation.cancel();
                let mut observed = state.write().await;
                observed["status"] = json!("failed");
                observed["launchOutcome"] = json!("unknown");
                observed["reason"] = json!(unknown_app_launch(&observed).message);
                if persisted.is_err() {
                    return Err(unknown_app_launch(&observed));
                }
                return Ok(observed.clone());
            }
            self.app_opens.close(&id, Some(&session_device)).await?;
            self.stop_session(&id).await;
            return Ok(json!({"sessionId":id,"status":"stopped","applicationStopped":false}));
        }
        let _process = process.ok_or_else(|| {
            CoreError::new(
                "app_launch_unknown",
                "应用打开结果未知，请先核对并关闭本次记录。",
            )
        })?;
        if command == "session.clock.probe" {
            if !state.read().await["transportTrace"].is_array() {
                return Err(invalid("时钟采样仅用于已开启逐帧观测的诊断会话。"));
            }
            let client = self.client(&session_device).await?;
            return crate::clock_probe::sample(&client, cancellation).await;
        }
        if command == "session.ready" {
            let texture = params["textureId"]
                .as_i64()
                .filter(|id| *id >= 0)
                .ok_or_else(|| invalid("渲染纹理无效。"))?;
            let mut data = state.write().await;
            data["textureId"] = json!(texture);
            // A replacement renderer must preserve a local presentation pause.
            let paused = data["status"] == "paused";
            data["status"] = json!(if paused { "paused" } else { "streaming" });
            self.activities.admission.set_status(
                &crate::activities::ActivityRef::Session(&id).to_string(),
                if paused {
                    ResourceStatus::Paused
                } else {
                    ResourceStatus::Streaming
                },
            );
            if let Some(name) = params["decoderName"].as_str() {
                data["decoderName"] = json!(name);
            }
            if let Some(hardware) = params["hardwareAccelerated"].as_bool() {
                data["hardwareAccelerated"] = json!(hardware);
            }
            // Decoder output dimensions are diagnostic receipts. Touch routing
            // must keep using the scrcpy session dimensions, not a padded or
            // cropped decoder buffer size.
            record_decoded_size(&mut data, params);
            self.emit("session.updated", data["deviceId"].as_str(), data.clone());
            return Ok(data.clone());
        }
        if command == "session.frame" {
            let mut data = state.write().await;
            if data["textureId"].is_null() {
                return Err(CoreError::new("renderer_not_ready", "实时渲染尚未就绪。"));
            }
            data["lastFrameAt"] = json!(now());
            record_decoded_size(&mut data, params);
            for key in ["frameCount", "framesDecoded", "presentationTimeUs"] {
                if let Some(value) = params[key].as_u64() {
                    data[key] = json!(value);
                }
            }
            self.emit("session.frame", data["deviceId"].as_str(), data.clone());
            return Ok(json!({"received":true}));
        }
        if command == "session.refresh" {
            // Official scrcpy RESET_VIDEO restarts only the existing encoder.
            // It neither injects a gesture nor launches/migrates an app task.
            request_control(&control, ControlRequest::Send, vec![17]).await?;
            return Ok(json!({"sessionId":id,"refreshRequested":true}));
        }
        if matches!(command, "session.pause" | "session.resume") {
            {
                let data = state.read().await;
                if data["textureId"].is_null() {
                    return Err(CoreError::new("renderer_not_ready", "实时渲染尚未就绪。"));
                }
            }
            let pausing = command.ends_with("pause");
            if cancellation.is_cancelled() {
                return Err(CoreError::new("disconnected", "控制会话已结束。"));
            }
            let mut data = state.write().await;
            data["status"] = json!(if pausing { "paused" } else { "streaming" });
            self.activities.admission.set_status(
                &crate::activities::ActivityRef::Session(&id).to_string(),
                if pausing {
                    ResourceStatus::Paused
                } else {
                    ResourceStatus::Streaming
                },
            );
            // Official scrcpy keeps capturing; only local presentation pauses.
            data["presentationOnly"] = json!(true);
            data["capturePaused"] = json!(false);
            data["awaitingSession"] = json!(!pausing);
            self.emit("session.updated", data["deviceId"].as_str(), data.clone());
            let result = data.clone();
            drop(data);
            if !pausing {
                request_control(&control, ControlRequest::Send, vec![17]).await?;
            }
            return Ok(result);
        }
        let mut bytes = Vec::new();
        match command {
            "session.touch" => bytes = touch_message(params, &*state.read().await)?,
            "session.key" => {
                let key = params["keyCode"]
                    .as_u64()
                    .filter(|key| *key <= 1024)
                    .ok_or_else(|| invalid("按键编码无效。"))? as u32;
                let actions: &[u8] = match params["action"].as_str().unwrap_or("press") {
                    "down" => &[0],
                    "up" => &[1],
                    "press" => &[0, 1],
                    _ => return Err(invalid("按键动作无效。")),
                };
                for action in actions {
                    bytes.extend_from_slice(&[0, *action]);
                    bytes.extend_from_slice(&key.to_be_bytes());
                    bytes.extend_from_slice(&0u32.to_be_bytes());
                    bytes.extend_from_slice(
                        &(params["metaState"]
                            .as_u64()
                            .unwrap_or(0)
                            .min(u32::MAX as u64) as u32)
                            .to_be_bytes(),
                    );
                }
            }
            "session.text" => {
                let text = required(params, "text")?;
                if text.len() > CLIPBOARD_MAX {
                    return Err(invalid("输入文字过长。"));
                }
                if !text.is_ascii() {
                    if state.read().await["apiLevel"]
                        .as_u64()
                        .is_some_and(|level| level < 24)
                    {
                        return Err(CoreError::new(
                            "unsupported",
                            "Android 7 以下的系统输入通道不支持粘贴此类文字。",
                        ));
                    }
                    return clipboard_set(&control, text.to_owned(), true).await;
                }
                for chunk in text.as_bytes().chunks(300) {
                    bytes.push(1);
                    bytes.extend_from_slice(&(chunk.len() as u32).to_be_bytes());
                    bytes.extend_from_slice(chunk);
                }
            }
            "session.rotate" => bytes.push(11),
            "session.screen" => {
                bytes.extend_from_slice(&[
                    10,
                    match params["mode"].as_str() {
                        Some("on") => 1,
                        Some("off") => 0,
                        _ => return Err(invalid("屏幕模式无效。")),
                    },
                ]);
            }
            "session.launch" => {
                let requested = params
                    .get("packageName")
                    .map(|value| {
                        value
                            .as_str()
                            .ok_or_else(|| invalid("应用包名无效。"))
                            .and_then(package_name)
                    })
                    .transpose()?;
                if let (Some(current), Some(requested)) = (package.as_deref(), requested)
                    && current != requested
                {
                    return Err(invalid(
                        "独立窗口只能重新打开它所属的应用；其他应用请在手机屏幕或另一个窗口中打开。",
                    ));
                }
                let package = requested
                    .or(package.as_deref())
                    .ok_or_else(|| invalid("请指定要在手机屏幕打开的应用。"))?;
                self.app_opens
                    .ensure_available(&session_device, package)
                    .await?;
                let sessions = self.activities.sessions.lock().await;
                for session in sessions.values() {
                    if session.device_id == session_device
                        && session.package.as_deref() == Some(package)
                    {
                        let observed = session.state.read().await;
                        if observed["launchOutcome"] == "unknown" {
                            return Err(unknown_app_launch(&observed));
                        }
                    }
                }
                drop(sessions);
                bytes.extend_from_slice(&[16, package.len() as u8]);
                bytes.extend_from_slice(package.as_bytes());
                let operation = uuid::Uuid::new_v4().to_string();
                let permit = self
                    .app_opens
                    .begin(&operation, &id, &session_device, package)
                    .await?;
                self.events.note_state_change();
                let sent = request_launch(&control, bytes, permit).await;
                let failure = match sent {
                    Ok(mut receipt) => match self.app_opens.finish(&operation, None).await {
                        Ok(()) => {
                            self.events.note_state_change();
                            receipt["launchOperationId"] = json!(operation);
                            receipt["launchOutcome"] = json!("sent");
                            return Ok(receipt);
                        }
                        Err(error) => error,
                    },
                    Err(error) => error,
                };
                // The write may have reached the real application. Keep the
                // record even when capture or this page subsequently ends.
                let _ = self.app_opens.finish(&operation, Some(&failure.code)).await;
                self.events.note_state_change();
                let record = self
                    .app_opens
                    .unresolved(Some(&session_device))
                    .await
                    .into_iter()
                    .find(|record| record["launchOperationId"] == operation)
                    .ok_or_else(|| CoreError::new("cancelled", "本次打开记录已明确关闭。"))?;
                return Err(crate::app_open::unknown(record));
            }
            _ => return Err(CoreError::new("unknown_command", "控制操作无效。")),
        }
        request_control(&control, ControlRequest::Send, bytes).await
    }

    pub(crate) async fn clipboard_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        let device = required(params, "deviceId")?;
        if !matches!(command, "clipboard.get" | "clipboard.set") {
            return Err(invalid("剪贴板操作无效。"));
        }
        // scrcpy GET_CLIPBOARD may legally send no response for an empty or
        // unreadable clipboard. The companion correlates each read and reports
        // that state explicitly, while preserving its allowStart policy.
        if command == "clipboard.get" {
            return self.companion_command(command, params).await;
        }
        let text = params["text"]
            .as_str()
            .ok_or_else(|| invalid("剪贴板内容无效。"))?;
        if text.len() > CLIPBOARD_MAX {
            return Err(invalid("剪贴板文字过长。"));
        }
        let control = self
            .activities
            .sessions
            .lock()
            .await
            .values()
            .find(|session| {
                session.device_id == device
                    && !session.cancellation.is_cancelled()
                    && !session.control.is_closed()
            })
            .map(|session| session.control.clone());
        let Some(control) = control else {
            return self.companion_command(command, params).await;
        };
        clipboard_set(&control, text.to_owned(), false).await
    }

    pub(crate) async fn list_apps(&self, params: &Value) -> CoreResult<Value> {
        let client = self.client(required(params, "deviceId")?).await?;
        let path = format!("/data/local/tmp/interop-apps-{}.jar", uuid::Uuid::new_v4());
        let mut sync = client.sync(OperationOptions::default()).await?;
        sync.push(
            &RemotePath::new(&path)?,
            &mut &SERVER[..],
            0o600,
            now() as u32,
            SERVER.len() as u64,
        )
        .await?;
        drop(sync);
        let command = format!(
            "CLASSPATH={} app_process / com.genymobile.scrcpy.Server 5.0.1 list_apps=true cleanup=true",
            quote(&path)?
        );
        let result = client
            .shell(&command, 4 * 1024 * 1024, OperationOptions::default())
            .await;
        let _ = client
            .shell(
                &format!("rm -f -- {}", quote(&path)?),
                4096,
                OperationOptions::default(),
            )
            .await;
        let result = result?;
        if result.exit_code.is_some_and(|code| code != 0) {
            return Err(CoreError::new(
                "apps_unavailable",
                String::from_utf8_lossy(&result.stderr).to_string(),
            ));
        }
        let mut text = String::from_utf8_lossy(&result.stdout).to_string();
        text.push_str(&String::from_utf8_lossy(&result.stderr));
        Ok(json!({"apps":parse_apps(&text)?}))
    }

    pub(crate) async fn launch_app(&self, params: &Value) -> CoreResult<Value> {
        self.start_session(params).await
    }

    async fn probe_video_encoders(&self, device: &str) -> CoreResult<Vec<VideoEncoder>> {
        let client = self.client(device).await?;
        self.encoder_catalog
            .get(&client, || Self::read_video_encoders(&client))
            .await
    }

    async fn read_video_encoders(client: &interop_adb::Client) -> CoreResult<Vec<VideoEncoder>> {
        let permit = tokio::time::timeout(Duration::from_secs(15), ENCODER_PROBE_JOBS.acquire())
            .await
            .map_err(|_| CoreError::new("timeout", "等待设备编码器探测空位超时。"))?
            .expect("encoder probe semaphore stays open");
        let client = client.clone();
        tokio::spawn(async move {
            let _permit = permit;
            // Own the operation through its cleanup even if the requesting
            // startup/catalog future is dropped. Every ADB operation below has
            // a deadline; this does not claim that a failed sync upload has a
            // remote completion acknowledgement.
            Self::read_video_encoders_owned(&client).await
        })
        .await
        .map_err(|error| CoreError::new("encoder_probe", error.to_string()))?
    }

    async fn read_video_encoders_owned(
        client: &interop_adb::Client,
    ) -> CoreResult<Vec<VideoEncoder>> {
        if format!("{:x}", Sha256::digest(SERVER)) != SERVER_SHA {
            return Err(CoreError::new("server_integrity", "内置控制服务校验失败。"));
        }
        let path = format!(
            "/data/local/tmp/interop-encoders-{}.jar",
            uuid::Uuid::new_v4()
        );
        let mut shell_completed = false;
        let result = async {
            let operation = OperationOptions {
                timeout: Duration::from_secs(15),
                ..Default::default()
            };
            let mut sync = client.sync(operation.clone()).await?;
            sync.push(
                &RemotePath::new(&path)?,
                &mut &SERVER[..],
                0o600,
                now().min(u32::MAX as u64) as u32,
                SERVER.len() as u64,
            )
            .await?;
            drop(sync);
            let command = encoder_probe_command(&path)?;
            let output = client.shell(&command, 256 * 1024, operation).await?;
            // EXIT (shell_v2) or EOF (legacy) arrives after the same shell has
            // attempted rm. As before, rm is best effort, not proof of absence.
            shell_completed = true;
            if output.exit_code.is_some_and(|code| code != 0) {
                return Err(CoreError::new(
                    "encoder_probe",
                    "设备编码器枚举失败；尚未确认所选格式可用。",
                ));
            }
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            parse_encoders(&text)
        }
        .await;
        if !shell_completed {
            // Failed uploads and incomplete shells still need an independent
            // cleanup attempt, owned by the probe job through its deadline.
            let _ = client
                .shell(
                    &format!("rm -f -- {}", quote(&path)?),
                    4096,
                    OperationOptions {
                        timeout: Duration::from_secs(3),
                        ..Default::default()
                    },
                )
                .await;
        }
        result
    }

    async fn quality_options(&self, params: &Value) -> CoreResult<Value> {
        let device = match params.get("deviceId") {
            None | Some(Value::Null) => None,
            Some(Value::String(id)) if !id.is_empty() => Some(id.as_str()),
            _ => return Err(invalid("设备标识无效。")),
        };
        if let Some(id) = device {
            self.device(id).await?;
        }
        let settings =
            crate::preferences::quality_settings(&self.store.read().await.settings, device);
        let (encoders, reason) = if let Some(device) = device {
            match self.probe_video_encoders(device).await {
                Ok(encoders) => (
                    Some(encoders),
                    "已从被控设备枚举；实际配置、资源与主控解码仍需验证。".to_owned(),
                ),
                Err(error) => (None, error.message),
            }
        } else {
            (None, "尚未选择并探测被控设备。".to_owned())
        };
        let entries: Vec<Value> = encoders.as_deref().unwrap_or_default().iter().map(|encoder|
            json!({"name":encoder.name,"codec":encoder.codec,"available":encoders.is_some(),"status":"available","hardwareAccelerated":encoder.hardware,
                "reason":"设备已枚举此编码器；不保证当前资源足够或所选参数配置成功。"})).collect();
        let codecs: Vec<Value> = VIDEO_CODECS.iter().map(|codec| {
            let listed: Vec<_> = entries.iter().filter(|encoder| encoder["codec"] == codec.name).cloned().collect();
            let available = !listed.is_empty();
            json!({"id":codec.name,"value":codec.name,"name":codec.label,"label":codec.label,"mime":codec.mime,
                "status":if encoders.is_none(){"unknown"}else if available{"available"}else{"unavailable"},"available":available,
                "reason":if encoders.is_none(){reason.as_str()}else if available{"目标已枚举编码器；尚需主控解码交集与实际配置验证。"}else{"目标本次未枚举此格式的编码器。"},
                "encoders":listed,"decoderStatus":"unknown","requiresDecoder":true})
        }).collect();
        let mut active_streams = Vec::new();
        if let Some(device) = device {
            for session in self.activities.sessions.lock().await.values() {
                if session.device_id == device && !session.cancellation.is_cancelled() {
                    let state = session.state.read().await;
                    active_streams.push(
                        json!({"sessionId":state["sessionId"],"name":state["name"],
                        "codec":state["codec"],"width":state["width"],"height":state["height"],
                        "decodedWidth":state["decodedWidth"],"decodedHeight":state["decodedHeight"],
                        "requestedMaxSize":state["quality"]["maxSize"],"status":state["status"],
                        "dimensionsSource":"scrcpy-session-metadata"}),
                    );
                }
            }
        }
        Ok(
            json!({"current":current_quality(&settings),"deviceId":device,"scope":if device.is_some(){"device"}else{"global"},
            "activeStreams":active_streams,
            "probe":{"status":if encoders.is_some(){"enumerated"}else{"unknown"},"source":"scrcpy-5.0.1-list-encoders","reason":reason},
            "presets":[{"id":"smooth","name":"流畅","available":encoders.is_some()},{"id":"balanced","name":"均衡","available":encoders.is_some()},{"id":"clear","name":"清晰","available":encoders.is_some()}],
            "maxSize":[{"value":720,"label":"720","available":encoders.is_some()},{"value":1080,"label":"1080","available":encoders.is_some()},{"value":1280,"label":"1280","available":encoders.is_some()},{"value":1920,"label":"1920","available":encoders.is_some()}],
            "maxFps":[{"value":30,"label":"30 fps","available":encoders.is_some()},{"value":60,"label":"60 fps","available":encoders.is_some()}],
            "bitRate":[{"value":2000000,"label":"2 Mbps","available":encoders.is_some()},{"value":8000000,"label":"8 Mbps","available":encoders.is_some()},{"value":12000000,"label":"12 Mbps","available":encoders.is_some()}],
            "codec":codecs,"codecs":codecs,"encoders":entries,"maxSizes":[720,1080,1280,1920],"frameRates":[30,60],"audioAvailable":false}),
        )
    }

    async fn save_device_quality(&self, device: &str, settings: &Value) -> CoreResult<()> {
        let quality: serde_json::Map<String, Value> = crate::preferences::QUALITY_KEYS
            .iter()
            .map(|key| ((*key).to_owned(), settings[*key].clone()))
            .collect();
        crate::preferences::validate_quality(&Value::Object(quality.clone()))?;
        let previous = {
            let mut store = self.store.write().await;
            if !store.settings["deviceQuality"].is_object() {
                store.settings["deviceQuality"] = json!({});
            }
            let map = store.settings["deviceQuality"]
                .as_object_mut()
                .expect("quality map");
            if !map.contains_key(device) && map.len() >= 256 {
                return Err(CoreError::new(
                    "quality_limit",
                    "设备画质覆盖数量已达到上限。",
                ));
            }
            map.insert(device.to_owned(), Value::Object(quality.clone()))
        };
        if let Err(error) = self.persist().await {
            let mut store = self.store.write().await;
            let map = store.settings["deviceQuality"]
                .as_object_mut()
                .expect("quality map");
            // Do not overwrite a newer successful concurrent settings operation.
            if map.get(device) == Some(&Value::Object(quality)) {
                if let Some(previous) = previous {
                    map.insert(device.to_owned(), previous);
                } else {
                    map.remove(device);
                }
            }
            return Err(error);
        }
        Ok(())
    }

    async fn change_quality(&self, params: &Value) -> CoreResult<Value> {
        let device = required(params, "deviceId")?.to_owned();
        self.client(&device).await?;
        let next = quality_patch(
            &crate::preferences::quality_settings(&self.store.read().await.settings, Some(&device)),
            params,
        )?;
        let previous = {
            let sessions = self.activities.sessions.lock().await;
            if let Some(id) = params.get("sessionId") {
                let id = id.as_str().ok_or_else(|| invalid("会话标识无效。"))?;
                let session = sessions
                    .get(id)
                    .ok_or_else(|| CoreError::new("not_found", "控制会话已结束。"))?;
                if session.device_id != device {
                    return Err(invalid("会话不属于所选设备。"));
                }
                Some((id.to_owned(), session.package.clone()))
            } else {
                let mut matching = sessions.iter().filter(|(_, session)| {
                    session.device_id == device && !session.cancellation.is_cancelled()
                });
                let first = matching
                    .next()
                    .map(|(id, session)| (id.clone(), session.package.clone()));
                if matching.next().is_none() {
                    first
                } else {
                    None
                }
            }
        };
        // A target keyframe does not prove a local decoder can render it.
        // Keep every current session/task alive; the user explicitly closes and reopens
        // after saving. This also avoids implicit migration of app tasks.
        validate_encoder_selection(&next, &self.probe_video_encoders(&device).await?)?;
        self.save_device_quality(&device, &next).await?;
        let active = self
            .activities
            .sessions
            .lock()
            .await
            .values()
            .any(|session| session.device_id == device && !session.cancellation.is_cancelled());
        Ok(
            json!({"deviceId":device,"appliesNextSession":true,"needsRestart":active,"existingSessionId":previous.as_ref().map(|(id, _)| id),
            "current":current_quality(&next),"seamless":false,"reason":"设置已保存到这台设备，新建屏幕或应用窗口时生效；已保留的窗口继续使用原设置，关闭后重新打开即可应用。"}),
        )
    }

    async fn screenshot(&self, params: &Value) -> CoreResult<Value> {
        let device = required(params, "deviceId")?;
        if self
            .activities
            .sessions
            .lock()
            .await
            .values()
            .any(|s| s.device_id == device && s.package.is_some() && !s.cancellation.is_cancelled())
        {
            return Err(CoreError::new(
                "native_capture_required",
                "独立应用窗口截图需要从当前渲染画面保存。",
            ));
        }
        let client = self.client(device).await?;
        let mut stream = client
            .exec("screencap -p", OperationOptions::default())
            .await?;
        let mut bytes = Vec::new();
        let mut buffer = [0; 64 * 1024];
        loop {
            let count = stream.read(&mut buffer).await?;
            if count == 0 {
                break;
            }
            if bytes.len() + count > 32 * 1024 * 1024 {
                return Err(CoreError::new("screenshot_limit", "截图超出大小限制。"));
            }
            bytes.extend_from_slice(&buffer[..count]);
        }
        if !bytes.starts_with(b"\x89PNG\r\n\x1a\n") || !bytes.ends_with(b"\0\0\0\0IEND\xaeB`\x82") {
            return Err(CoreError::new(
                "screenshot_failed",
                "设备没有返回有效截图。",
            ));
        }
        let directory = self.root.join("screenshots");
        tokio::fs::create_dir_all(&directory).await?;
        let path = directory.join(format!("{}.png", uuid::Uuid::new_v4()));
        Self::private_write(&path, &bytes).await?;
        Ok(json!({"localPath":path,"mime":"image/png","size":bytes.len()}))
    }
}

struct CancelLaunchOnDrop(crate::app_open::LaunchPermit);
impl Drop for CancelLaunchOnDrop {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
async fn request_launch(
    sender: &mpsc::Sender<ControlRequest>,
    bytes: Vec<u8>,
    permit: crate::app_open::LaunchPermit,
) -> CoreResult<Value> {
    let _guard = CancelLaunchOnDrop(permit.clone());
    request_control(
        sender,
        |bytes, reply| ControlRequest::Launch(bytes, permit, reply),
        bytes,
    )
    .await
}

async fn request_control<F>(
    sender: &mpsc::Sender<ControlRequest>,
    constructor: F,
    bytes: Vec<u8>,
) -> CoreResult<Value>
where
    F: FnOnce(Vec<u8>, ControlReply) -> ControlRequest,
{
    send_control_request(sender, |reply| constructor(bytes, reply)).await
}

async fn send_control_request<F>(
    sender: &mpsc::Sender<ControlRequest>,
    constructor: F,
) -> CoreResult<Value>
where
    F: FnOnce(ControlReply) -> ControlRequest,
{
    let deadline = Instant::now() + Duration::from_secs(6);
    let (reply, receiver) = oneshot::channel();
    tokio::time::timeout_at(deadline, async {
        sender
            .send(constructor(ControlReply {
                deadline,
                sender: reply,
            }))
            .await
            .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?;
        receiver
            .await
            .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?
    })
    .await
    .map_err(|_| control_timeout())?
}

fn control_timeout() -> CoreError {
    CoreError::new("timeout", "设备未及时响应控制请求。")
}
async fn clipboard_set(
    sender: &mpsc::Sender<ControlRequest>,
    text: String,
    paste: bool,
) -> CoreResult<Value> {
    send_control_request(sender, |reply| {
        ControlRequest::ClipboardSet(text, paste, reply)
    })
    .await
}

fn session_dimensions(header: &[u8; 12]) -> CoreResult<Option<(u32, u32)>> {
    let flags = u32::from_be_bytes(header[..4].try_into().expect("header"));
    if flags & 0x8000_0000 == 0 {
        return Ok(None);
    }
    let width = u32::from_be_bytes(header[4..8].try_into().expect("header"));
    let height = u32::from_be_bytes(header[8..].try_into().expect("header"));
    if flags & 0x7fff_fffe != 0 || width == 0 || height == 0 || width > 16384 || height > 16384 {
        return Err(CoreError::new("video_protocol", "视频会话尺寸无效。"));
    }
    Ok(Some((width, height)))
}

async fn read_video_preface(
    video: &mut AdbStream,
    initial: [u8; 12],
) -> CoreResult<(Vec<u8>, u32, u32)> {
    tokio::time::timeout(Duration::from_secs(8), async {
        let mut bytes = initial.to_vec();
        let (mut width, mut height) = session_dimensions(&initial)?
            .ok_or_else(|| CoreError::new("video_protocol", "视频流缺少会话尺寸。"))?;
        for _ in 0..64 {
            let mut header = [0; 12];
            video.read_exact(&mut header).await?;
            if let Some((updated_width, updated_height)) = session_dimensions(&header)? {
                width = updated_width;
                height = updated_height;
                bytes.extend_from_slice(&header);
                continue;
            }
            let length = u32::from_be_bytes(header[8..].try_into().expect("header")) as usize;
            if length == 0 || length > MAX_PACKET || bytes.len() + length + 12 > 2 * MAX_PACKET {
                return Err(CoreError::new("video_protocol", "首帧数据超出大小限制。"));
            }
            bytes.extend_from_slice(&header);
            let start = bytes.len();
            bytes.resize(start + length, 0);
            video.read_exact(&mut bytes[start..]).await?;
            let flags = u64::from_be_bytes(header[..8].try_into().expect("header"));
            if flags & (1 << 61) != 0 && flags & (1 << 62) == 0 {
                return Ok((bytes, width, height));
            }
        }
        Err(CoreError::new(
            "video_protocol",
            "设备未提供有界的编码首帧。",
        ))
    })
    .await
    .map_err(|_| {
        CoreError::new(
            "encoder_start_failed",
            "所选编码器未及时提供首帧；现有会话保持运行。",
        )
    })?
}

fn adb_read_timing(trace: Option<interop_adb::ReadTrace>) -> Value {
    trace.map_or(Value::Null, |trace| {
        json!({
            "sequence": trace.sequence,
            "bytes": trace.payload_bytes,
            "payloadStartedUs": trace.payload_started_us,
            "payloadReadUs": trace.payload_read_us,
            "routedUs": trace.routed_us,
            "firstConsumedUs": trace.first_consumed_us,
        })
    })
}

async fn run_video(
    listener: TcpListener,
    token: String,
    mut video: AdbStream,
    initial: Vec<u8>,
    context: SessionContext,
) {
    let SessionContext {
        cancellation,
        state,
        events,
        device,
    } = context;
    let tracing = state.read().await["transportTrace"].is_array();
    // The startup preface is already buffered. Number only subsequent capture
    // segments here; this counter is not the renderer generation identifier.
    let mut capture_segment = 1u64;
    let operation = async {
        if tracing {
            video.set_read_trace_clock(Some(crate::media::monotonic_micros))?;
        }
        let output = accept_media(&listener, &token).await?;
        output.set_nodelay(true)?;
        let (mut native_reader, mut output) = output.into_split();
        let native_cancel = cancellation.clone();
        tokio::spawn(async move {
            let mut unexpected = [0];
            tokio::select! { _ = native_cancel.cancelled() => {}, _ = native_reader.read(&mut unexpected) => { native_cancel.cancel(); } }
        });
        let ready_state = state.clone();
        let ready_cancel = cancellation.clone();
        tokio::spawn(async move {
            tokio::select! { _ = ready_cancel.cancelled() => {}, _ = tokio::time::sleep(Duration::from_secs(20)) => {
                let mut data = ready_state.write().await;
                if data["textureId"].is_null() { data["status"] = json!("failed"); data["reason"] = json!("视频渲染器未返回可用画面。"); ready_cancel.cancel(); }
            } }
        });
        output.write_all(&initial).await?;
        loop {
            let mut header = [0; 12];
            // A static screen may remain silent between complete units. Once
            // a unit starts, bound its entire header/session/payload delivery:
            // the downstream relay cannot see a fragment buffered here.
            video.read_exact(&mut header[..1]).await?;
            // AdbStream delivers complete WRTE payloads. This clock excludes
            // the first WRTE's earlier transport receive and queue wait.
            let first_byte_us = tracing.then(crate::media::monotonic_micros);
            let first_adb_read = tracing.then(|| video.read_trace()).flatten();
            let complete = async {
                video.read_exact(&mut header[1..]).await?;
                if let Some(dimensions) = session_dimensions(&header)? {
                    return Ok((Some(dimensions), Vec::new()));
                }
                let length =
                    u32::from_be_bytes(header[8..].try_into().expect("video header")) as usize;
                if length == 0 || length > MAX_PACKET {
                    return Err(CoreError::new("video_protocol", "视频数据包大小无效。"));
                }
                let mut bytes = vec![0; length];
                video.read_exact(&mut bytes).await?;
                Ok((None, bytes))
            };
            let (dimensions, bytes) = tokio::time::timeout(Duration::from_secs(10), complete)
                .await
                .map_err(|_| CoreError::new("video_timeout", "视频数据包未及时发送完整。"))??;
            if let Some((width, height)) = dimensions {
                capture_segment = capture_segment.saturating_add(1);
                let forward = {
                    let mut data = state.write().await;
                    data["width"] = json!(width);
                    data["height"] = json!(height);
                    data["awaitingSession"] = json!(false);
                    event(&events, "session.updated", &device, data.clone());
                    data["status"] != "paused"
                };
                // A slow presentation consumer must not hold the session state
                // lock needed by control acknowledgements and cancellation.
                if forward {
                    output.write_all(&header).await?;
                }
                continue;
            }
            let read_completed_us = tracing.then(crate::media::monotonic_micros);
            let last_adb_read = tracing.then(|| video.read_trace()).flatten();
            {
                let data = state.read().await;
                if data["status"] == "paused" || data["awaitingSession"] == true {
                    continue;
                }
            }
            let write_started_us = tracing.then(crate::media::monotonic_micros);
            output.write_all(&header).await?;
            output.write_all(&bytes).await?;
            let written_us = tracing.then(crate::media::monotonic_micros);
            let flags = u64::from_be_bytes(header[..8].try_into().expect("video header"));
            if let Some(first_byte_us) = first_byte_us.filter(|_| flags & (1 << 62) == 0) {
                let mut data = state.write().await;
                if let Some(frames) = data.get_mut("transportTrace").and_then(Value::as_array_mut) {
                    if frames.len() == 256 {
                        frames.remove(0);
                    }
                    frames.push(json!({
                        "captureSegment": capture_segment,
                        "sourcePtsUs": flags & ((1 << 61) - 1),
                        "bytes": bytes.len(),
                        "firstByteUs": first_byte_us,
                        "readCompletedUs": read_completed_us,
                        "writeStartedUs": write_started_us,
                        "writtenUs": written_us,
                        "firstAdbRead": adb_read_timing(first_adb_read),
                        "lastAdbRead": adb_read_timing(last_adb_read),
                    }));
                }
            }
        }
        #[allow(unreachable_code)]
        Ok::<(), CoreError>(())
    };
    let result =
        tokio::select! { _ = cancellation.cancelled() => Ok(()), result = operation => result };
    if let Err(error) = result {
        let mut data = state.write().await;
        data["status"] = json!("failed");
        data["reason"] = json!(error.message);
    }
    cancellation.cancel();
}

/// Fixed-length authenticated loopback media connection. No media bytes are
/// sent to unauthenticated clients; repeated failures share the startup deadline.
pub(crate) async fn accept_media(
    listener: &TcpListener,
    token: &str,
) -> CoreResult<tokio::net::TcpStream> {
    use subtle::ConstantTimeEq;
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let (mut candidate, _) = tokio::time::timeout_at(deadline, listener.accept())
            .await
            .map_err(|_| CoreError::new("renderer_timeout", "未能连接媒体呈现器。"))??;
        let mut authentication = [0; 65];
        if tokio::time::timeout_at(
            deadline.min(Instant::now() + Duration::from_secs(3)),
            candidate.read_exact(&mut authentication),
        )
        .await
        .is_ok_and(|result| result.is_ok())
            && authentication[64] == b'\n'
            && bool::from(authentication[..64].ct_eq(token.as_bytes()))
        {
            return Ok(candidate);
        }
    }
}

async fn run_control(
    mut stream: AdbStream,
    mut requests: mpsc::Receiver<ControlRequest>,
    cancellation: CancellationToken,
    events: crate::events::EventBus,
    device: String,
    state: Arc<RwLock<Value>>,
) {
    let mut incoming = Vec::new();
    let mut buffer = [0; 4096];
    let mut sets: HashMap<u64, ControlReply> = HashMap::new();
    let mut sequence = 1u64;
    loop {
        tokio::select! {
            _ = cancellation.cancelled() => break,
            request = requests.recv() => {
                let Some(request) = request else { break; };
                if request.reply().is_closed() { continue; }
                let deadline = request.reply().deadline;
                let (bytes, immediate) = match request {
                    ControlRequest::Launch(bytes, permit, reply) => {
                        if !permit.claim() {
                            let _ = reply.send(Err(CoreError::new("cancelled", "本次应用打开已关闭。")));
                            continue;
                        }
                        let result = tokio::select! {
                            biased;
                            _ = permit.cancelled() => Err(CoreError::new("cancelled", "本次应用打开已关闭。")),
                            _ = cancellation.cancelled() => Err(CoreError::new("disconnected", "控制连接已结束。")),
                            _ = tokio::time::sleep_until(deadline) => Err(control_timeout()),
                            result = stream.write_all(&bytes) => result.map_err(CoreError::from),
                        };
                        let abort = result.is_err() || permit.is_cancelled();
                        permit.complete();
                        let _ = reply.send(result.map(|()| json!({"sent":true})));
                        if abort { break; }
                        continue;
                    }
                    ControlRequest::Send(bytes, reply) => (bytes, Some(reply)),
                    ControlRequest::ClipboardSet(text, paste, reply) => {
                        sets.retain(|_, reply| !reply.is_closed());
                        if sets.len() >= 16 { let _ = reply.send(Err(CoreError::new("busy","剪贴板请求较多，请稍后重试。"))); continue; }
                        sequence = sequence.wrapping_add(1).max(1); let mut bytes = vec![9]; bytes.extend_from_slice(&sequence.to_be_bytes()); bytes.push(u8::from(paste)); bytes.extend_from_slice(&(text.len() as u32).to_be_bytes()); bytes.extend_from_slice(text.as_bytes()); sets.insert(sequence,reply); (bytes,None)
                    }
                };
                let result = tokio::select! {
                    biased;
                    _ = cancellation.cancelled() => Err(CoreError::new("disconnected", "控制连接已结束。")),
                    _ = tokio::time::sleep_until(deadline) => Err(control_timeout()),
                    result = stream.write_all(&bytes) => result.map_err(CoreError::from),
                };
                let abort = result.is_err();
                if let Some(reply) = immediate { let _ = reply.send(result.map(|()| json!({"sent":true}))); }
                // A partial or unacknowledged write cannot safely be retried.
                // Dropping this stream closes its route, while the Client keeps
                // serving unrelated streams on the same device connection.
                if abort { break; }
            },
            result = stream.read(&mut buffer) => {
                let Ok(count) = result else { break; }; if count == 0 { break; }
                incoming.extend_from_slice(&buffer[..count]);
                loop {
                    if incoming.is_empty() { break; }
                    let needed = match incoming[0] {
                        0 => { if incoming.len() < 5 { break; } let length = u32::from_be_bytes(incoming[1..5].try_into().expect("clipboard length")) as usize; if length > (1 << 18)-5 { cancellation.cancel(); break; } 5 + length },
                        1 => 9,
                        2 => { if incoming.len() < 5 { break; } 5 + u16::from_be_bytes(incoming[3..5].try_into().expect("UHID length")) as usize },
                        _ => { cancellation.cancel(); break; }
                    };
                    if incoming.len() < needed { break; }
                    if incoming[0] == 0 {
                        let Ok(text) = std::str::from_utf8(&incoming[5..needed]) else { cancellation.cancel(); break; };
                        event(&events,"clipboard.changed",&device,json!({"text":text,"sessionId":state.read().await["sessionId"]}));
                    } else if incoming[0] == 1 {
                        let sequence = u64::from_be_bytes(incoming[1..9].try_into().expect("control sequence"));
                        if let Some(reply) = sets.remove(&sequence) { let _ = reply.send(Ok(json!({"applied":true}))); }
                    }
                    incoming.drain(..needed);
                }
            }
        }
    }
    for reply in sets.into_values() {
        let error = if Instant::now() >= reply.deadline {
            control_timeout()
        } else {
            CoreError::new("disconnected", "控制连接已结束。")
        };
        let _ = reply.send(Err(error));
    }
    cancellation.cancel();
}

fn touch_message(params: &Value, state: &Value) -> CoreResult<Vec<u8>> {
    let action = match params["action"].as_str() {
        Some("down") => 0,
        Some("up") => 1,
        Some("move") => 2,
        Some("cancel") => 3,
        _ => return Err(invalid("触控动作无效。")),
    };
    let width = params["screenWidth"]
        .as_u64()
        .filter(|v| *v > 0 && *v <= u16::MAX as u64)
        .ok_or_else(|| invalid("触控画面尺寸无效。"))?;
    let height = params["screenHeight"]
        .as_u64()
        .filter(|v| *v > 0 && *v <= u16::MAX as u64)
        .ok_or_else(|| invalid("触控画面尺寸无效。"))?;
    if state["width"].as_u64() != Some(width) || state["height"].as_u64() != Some(height) {
        return Err(CoreError::new(
            "stale_frame",
            "画面尺寸已变化，请等待新画面后重试。",
        ));
    }
    let x = params["x"]
        .as_i64()
        .filter(|x| *x >= 0 && *x < width as i64)
        .ok_or_else(|| invalid("触控位置超出画面。"))? as u32;
    let y = params["y"]
        .as_i64()
        .filter(|y| *y >= 0 && *y < height as i64)
        .ok_or_else(|| invalid("触控位置超出画面。"))? as u32;
    let pointer = params["pointerId"]
        .as_u64()
        .ok_or_else(|| invalid("触点标识无效。"))?;
    let pressure = params["pressure"]
        .as_f64()
        .unwrap_or(if action == 1 || action == 3 { 0.0 } else { 1.0 });
    if !pressure.is_finite() || !(0.0..=1.0).contains(&pressure) {
        return Err(invalid("触控压力无效。"));
    }
    let pressure = ((pressure * 65536.0) as u32).min(65535) as u16;
    let mut bytes = vec![2, action];
    bytes.extend_from_slice(&pointer.to_be_bytes());
    bytes.extend_from_slice(&x.to_be_bytes());
    bytes.extend_from_slice(&y.to_be_bytes());
    bytes.extend_from_slice(&(width as u16).to_be_bytes());
    bytes.extend_from_slice(&(height as u16).to_be_bytes());
    bytes.extend_from_slice(&pressure.to_be_bytes());
    bytes.extend_from_slice(&0u32.to_be_bytes());
    bytes.extend_from_slice(&0u32.to_be_bytes());
    Ok(bytes)
}

fn parse_apps(text: &str) -> CoreResult<Vec<Value>> {
    let mut apps = Vec::new();
    let mut pending: Option<(bool, String)> = None;
    if !text.contains("List of apps:") {
        return Err(CoreError::new(
            "apps_unavailable",
            "设备没有返回可解析的应用列表。",
        ));
    }
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed
            .strip_prefix("* ")
            .or_else(|| trimmed.strip_prefix("- "))
        {
            let system = trimmed.starts_with('*');
            if let Some((name, package)) = rest.rsplit_once(char::is_whitespace)
                && package_name(package).is_ok()
                && package.contains('.')
            {
                apps.push(json!({"name":name.trim(),"packageName":package,"system":system}));
                pending = None;
                continue;
            }
            pending = Some((system, rest.to_owned()));
        } else if let Some((system, name)) = pending.take()
            && package_name(trimmed).is_ok()
        {
            apps.push(json!({"name":name,"packageName":trimmed,"system":system}));
        }
    }
    Ok(apps)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn monitor_retires_another_device_while_a_session_waits_for_process_shutdown() {
        use interop_adb::{Client, DeviceInfo, protocol};
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let mut peers = Vec::new();
        for id in ["a-slow", "z-fast"] {
            runtime.store.write().await.devices.push(
                serde_json::from_value(json!({
                    "id":id,"name":id,"address":"fixture","port":5555,"transport":"tcp",
                    "status":"connected","autoReconnect":false,"observationWanted":false,
                }))
                .unwrap(),
            );
            let (transport, peer) = tokio::io::duplex(4096);
            let client = Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 4096,
                    banner: "device::\0".into(),
                    features: Default::default(),
                },
            )
            .unwrap();
            client.close();
            runtime.connections.lock().await.insert(id.into(), client);
            peers.push(peer);
        }
        let slow_cancel = CancellationToken::new();
        let process_closed = Arc::new(AtomicBool::new(false));
        let (control, _requests) = mpsc::channel(1);
        runtime.activities.sessions.lock().await.insert(
            "slow-session".into(),
            Session {
                device_id: "a-slow".into(),
                package: None,
                cancellation: slow_cancel.clone(),
                control,
                state: Arc::new(RwLock::new(
                    json!({"sessionId":"slow-session","status":"streaming"}),
                )),
                process_closed: process_closed.clone(),
                process: None,
            },
        );
        let fast_cancel = CancellationToken::new();
        let _reservation = runtime
            .activities
            .admission
            .reserve_session(
                "session:fast".into(),
                "z-fast".into(),
                "fast".into(),
                fast_cancel.clone(),
            )
            .unwrap();
        // Exercise the actual monitor tick and its actual stop_session wait.
        tokio::time::timeout(Duration::from_secs(5), slow_cancel.cancelled())
            .await
            .unwrap();
        let fast_retired = tokio::time::timeout(Duration::from_millis(500), async {
            fast_cancel.cancelled().await;
            let _transition = runtime.connections.transition("z-fast").await;
        })
        .await
        .is_ok();
        assert!(!process_closed.load(Ordering::Acquire));
        process_closed.store(true, Ordering::Release);
        assert!(
            fast_retired,
            "one device's 3-second process cleanup must not delay another device's retirement"
        );
        assert_eq!(runtime.device("z-fast").await.unwrap().status, "offline");
        let _transition = runtime.connections.transition("a-slow").await;
        drop(peers);
    }

    #[tokio::test]
    async fn session_start_entry_keeps_capture_state_out_of_inline_frame() {
        let fixture = ColdStartFixture::new().await;
        let params = json!({"deviceId":"cold-device", "packageName":"com.android.settings"});
        let inline_bytes = std::mem::size_of_val(&fixture.runtime.start_session(&params));
        assert!(
            inline_bytes <= 4096,
            "session entry inlines {inline_bytes} bytes; keep the capture handshake out of nested entry frames"
        );
        fixture.client.close();
    }

    struct ColdStartFixture {
        _root: tempfile::TempDir,
        runtime: Arc<Runtime>,
        client: interop_adb::Client,
        peer: tokio::io::DuplexStream,
        shell_v2: bool,
    }

    impl ColdStartFixture {
        async fn new() -> Self {
            Self::with_shell_v2(false).await
        }

        async fn with_shell_v2(shell_v2: bool) -> Self {
            use interop_adb::{DeviceInfo, protocol};
            let root = tempfile::tempdir().unwrap();
            let runtime = Runtime::initialize(root.path()).await.unwrap();
            runtime.store.write().await.devices.push(
                serde_json::from_value(json!({"id":"cold-device", "name":"Phone",
                    "address":"fixture", "port":5555, "transport":"tcp", "status":"online",
                    "apiLevel":35, "observationWanted":false}))
                .unwrap(),
            );
            let (transport, peer) = tokio::io::duplex(256 * 1024);
            let client = interop_adb::Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 64 * 1024,
                    banner: "device::cold-start".into(),
                    features: if shell_v2 {
                        HashSet::from(["shell_v2".into()])
                    } else {
                        HashSet::new()
                    },
                },
            )
            .unwrap();
            runtime
                .connections
                .lock()
                .await
                .insert("cold-device".into(), client.clone());
            Self {
                _root: root,
                runtime,
                client,
                peer,
                shell_v2,
            }
        }

        fn start(&self) -> tokio::task::JoinHandle<CoreResult<Value>> {
            // These preflight/cleanup regressions deliberately select a named
            // encoder. Automatic default-screen capture is tested separately.
            self.start_with(json!({"videoEncoder":"c2.fixture.avc"}))
        }

        fn start_with(&self, mut params: Value) -> tokio::task::JoinHandle<CoreResult<Value>> {
            let runtime = self.runtime.clone();
            params["deviceId"] = json!("cold-device");
            tokio::spawn(async move { runtime.start_session(&params).await })
        }

        async fn frame(&mut self) -> interop_adb::protocol::Frame {
            tokio::time::timeout(
                Duration::from_secs(1),
                interop_adb::protocol::Frame::read(&mut self.peer, 64 * 1024, true),
            )
            .await
            .expect("startup must make progress while the power query is gated")
            .unwrap()
        }

        async fn send(&mut self, command: u32, local: u32, payload: Vec<u8>) {
            interop_adb::protocol::Frame::new(command, local + 100, local, payload)
                .write(&mut self.peer)
                .await
                .unwrap();
        }

        // Inspect the actual first SEND. Closing the transport rejects the
        // incomplete upload, so these policy tests never start a remote JVM.
        async fn first_upload(
            &mut self,
            startup: tokio::task::JoinHandle<CoreResult<Value>>,
        ) -> (String, CoreError) {
            use interop_adb::protocol;
            let mut bytes = Vec::new();
            let path = loop {
                let frame = self.frame().await;
                match frame.command {
                    protocol::OPEN => {
                        let service = String::from_utf8_lossy(&frame.payload);
                        assert!(service.contains("dumpsys power") || service.starts_with("sync:"));
                        self.send(protocol::OKAY, frame.arg0, Vec::new()).await;
                        if service.contains("dumpsys power") {
                            self.finish_shell(frame.arg0, b"Awake\n").await;
                        }
                    }
                    protocol::WRTE => {
                        self.send(protocol::OKAY, frame.arg0, Vec::new()).await;
                        bytes.extend_from_slice(&frame.payload);
                        if bytes.len() >= 8 {
                            assert_eq!(&bytes[..4], b"SEND");
                            let len = u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
                            if bytes.len() >= 8 + len {
                                break String::from_utf8(bytes[8..8 + len].to_vec()).unwrap();
                            }
                        }
                    }
                    protocol::OKAY | protocol::CLSE => {}
                    other => panic!("unexpected first-upload frame: {other}"),
                }
            };
            self.client.close();
            let error = tokio::time::timeout(Duration::from_secs(1), startup)
                .await
                .expect("closed transport must fail startup")
                .unwrap()
                .unwrap_err();
            (path, error)
        }

        // Complete the real sync SEND/DATA/DONE exchange, not a fake probe future.
        // Keep dumpsys open until the encoder process itself has been requested.
        async fn gate_encoder_process(&mut self) -> (u32, u32) {
            use interop_adb::protocol;
            let mut power = None;
            let mut sync_bytes = Vec::new();
            let mut uploaded = 0;
            loop {
                let frame = self.frame().await;
                match frame.command {
                    protocol::OPEN => {
                        let service = String::from_utf8_lossy(&frame.payload);
                        self.send(protocol::OKAY, frame.arg0, Vec::new()).await;
                        if service.contains("dumpsys power") {
                            power = Some(frame.arg0);
                        } else if service.starts_with("sync:") {
                            assert!(power.is_some(), "screen sleep check was opened");
                        } else if service.contains("list_encoders=true") {
                            assert_eq!(
                                uploaded,
                                SERVER.len(),
                                "the actual bundled probe JAR was uploaded"
                            );
                            return (power.expect("sleep query stays gated"), frame.arg0);
                        } else {
                            panic!("unexpected startup service: {service}");
                        }
                    }
                    protocol::WRTE => {
                        self.send(protocol::OKAY, frame.arg0, Vec::new()).await;
                        sync_bytes.extend_from_slice(&frame.payload);
                        while sync_bytes.len() >= 8 {
                            let id: [u8; 4] = sync_bytes[..4].try_into().unwrap();
                            let word =
                                u32::from_le_bytes(sync_bytes[4..8].try_into().unwrap()) as usize;
                            if id == *b"DONE" {
                                sync_bytes.drain(..8);
                                self.send(protocol::WRTE, frame.arg0, b"OKAY\0\0\0\0".to_vec())
                                    .await;
                                continue;
                            }
                            if sync_bytes.len() < 8 + word {
                                break;
                            }
                            match &id {
                                b"SEND" => assert!(
                                    String::from_utf8_lossy(&sync_bytes[8..8 + word])
                                        .starts_with("/data/local/tmp/interop-encoders-")
                                ),
                                b"DATA" => uploaded += word,
                                _ => panic!("unexpected sync request: {id:?}"),
                            }
                            sync_bytes.drain(..8 + word);
                        }
                    }
                    protocol::OKAY | protocol::CLSE => {}
                    other => panic!("unexpected ADB frame: {other}"),
                }
            }
        }

        async fn finish_shell(&mut self, local: u32, output: &[u8]) {
            self.finish_shell_status(local, output, 0).await;
        }

        async fn finish_shell_status(&mut self, local: u32, output: &[u8], status: u8) {
            use interop_adb::protocol;
            if !output.is_empty() {
                let bytes = if self.shell_v2 {
                    let mut bytes = vec![1];
                    bytes.extend_from_slice(&(output.len() as u32).to_le_bytes());
                    bytes.extend_from_slice(output);
                    bytes
                } else {
                    output.to_vec()
                };
                self.send(protocol::WRTE, local, bytes).await;
            }
            if self.shell_v2 {
                self.send(protocol::WRTE, local, vec![3, 1, 0, 0, 0, status])
                    .await;
            }
            self.send(protocol::CLSE, local, Vec::new()).await;
        }

        async fn finish_probe(&mut self, encoder: u32, output: &[u8]) {
            self.finish_shell(encoder, output).await;
            self.assert_no_open().await;
        }

        async fn assert_no_open(&mut self) {
            use interop_adb::protocol;
            // Drain ACK/close traffic, but a completed probe must not open a
            // second shell. This observes the actual ADB service boundary.
            while let Ok(frame) = tokio::time::timeout(
                Duration::from_millis(30),
                protocol::Frame::read(&mut self.peer, 64 * 1024, true),
            )
            .await
            {
                assert_ne!(
                    frame.unwrap().command,
                    protocol::OPEN,
                    "a completed encoder probe must clean up in its own shell"
                );
            }
        }

        async fn finish_fallback_cleanup(&mut self) {
            use interop_adb::protocol;
            loop {
                let frame = self.frame().await;
                if frame.command == protocol::OPEN {
                    let service = String::from_utf8_lossy(&frame.payload);
                    assert!(
                        service.contains(":rm -f -- '/data/local/tmp/interop-encoders-"),
                        "only the encoder probe is cleaned up: {service}"
                    );
                    self.send(protocol::OKAY, frame.arg0, Vec::new()).await;
                    self.finish_shell(frame.arg0, &[]).await;
                    break;
                }
            }
        }
    }

    #[tokio::test]
    async fn cold_default_screen_uploads_capture_without_encoder_enumeration() {
        let mut fixture = ColdStartFixture::new().await;
        let startup = fixture.start_with(json!({}));
        let (path, error) = fixture.first_upload(startup).await;
        assert!(
            path.starts_with("/data/local/tmp/interop-scrcpy-"),
            "unexpected SEND: {path}"
        );
        assert_eq!(error.details["launchOutcome"], "not_submitted");
    }

    #[tokio::test]
    async fn cold_explicit_format_encoder_and_app_keep_real_preflight() {
        for params in [
            json!({"videoCodec":"h265"}),
            json!({"videoEncoder":"c2.fixture.avc"}),
            json!({"packageName":"com.android.settings"}),
        ] {
            let mut fixture = ColdStartFixture::new().await;
            let startup = fixture.start_with(params);
            let (path, error) = fixture.first_upload(startup).await;
            assert!(
                path.starts_with("/data/local/tmp/interop-encoders-"),
                "unexpected SEND: {path}"
            );
            assert_eq!(error.details["launchOutcome"], "not_submitted");
        }
    }

    #[tokio::test]
    async fn cold_capture_policy_uses_effective_preferences_and_overrides() {
        for (settings, params, capture) in [
            (json!({"videoCodec":"h265"}), json!({}), false),
            (json!({"videoEncoder":"c2.fixture.avc"}), json!({}), false),
            (
                json!({"videoCodec":"h265","videoEncoder":"c2.fixture.hevc"}),
                json!({"videoCodec":"h264","videoEncoder":null}),
                true,
            ),
        ] {
            let mut fixture = ColdStartFixture::new().await;
            for (key, value) in settings.as_object().unwrap() {
                fixture.runtime.store.write().await.settings[key] = value.clone();
            }
            let startup = fixture.start_with(params);
            let (path, _) = fixture.first_upload(startup).await;
            assert_eq!(
                path.starts_with("/data/local/tmp/interop-scrcpy-"),
                capture,
                "unexpected SEND: {path}"
            );
        }
    }

    #[tokio::test]
    async fn cold_default_screen_rejects_sleep_without_upload_or_wake() {
        use interop_adb::protocol;
        let mut fixture = ColdStartFixture::new().await;
        let startup = fixture.start_with(json!({}));
        let frame = fixture.frame().await;
        assert_eq!(frame.command, protocol::OPEN);
        assert!(String::from_utf8_lossy(&frame.payload).contains("dumpsys power"));
        fixture.send(protocol::OKAY, frame.arg0, Vec::new()).await;
        fixture.finish_shell(frame.arg0, b"Asleep\n").await;
        let result = tokio::time::timeout(Duration::from_secs(1), startup).await;
        if result.is_err() {
            fixture.client.close();
        }
        let error = result
            .expect("sleep rejection must not wait for a cold probe")
            .unwrap()
            .unwrap_err();
        assert_eq!(error.code, "device_asleep");
        assert_eq!(error.details["launchOutcome"], "not_submitted");
        fixture.assert_no_open().await;
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_default_screen_respects_known_unsupported_catalog() {
        use interop_adb::protocol;
        let mut fixture = ColdStartFixture::new().await;
        fixture.runtime.encoder_catalog.get(&fixture.client, || async {
            parse_encoders("List of video encoders:\n --video-codec=h265 --video-encoder=c2.fixture.hevc (hw)\n")
        }).await.unwrap();
        let startup = fixture.start_with(json!({}));
        let frame = fixture.frame().await;
        assert_eq!(frame.command, protocol::OPEN);
        fixture.send(protocol::OKAY, frame.arg0, Vec::new()).await;
        fixture.finish_shell(frame.arg0, b"Awake\n").await;
        let error = tokio::time::timeout(Duration::from_secs(1), startup)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err();
        assert_eq!(error.code, "encoder_unavailable");
        fixture.assert_no_open().await;
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_probe_shell_v2_completes_without_another_cleanup_shell() {
        let mut fixture = ColdStartFixture::with_shell_v2(true).await;
        let startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_shell(power, b"Asleep\n").await;
        fixture.finish_probe(encoder,
            b"List of video encoders:\n --video-codec=h264 --video-encoder=c2.fixture.avc (hw)\n").await;
        assert_eq!(startup.await.unwrap().unwrap_err().code, "device_asleep");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_probe_truncated_shell_v2_still_owns_fallback_cleanup() {
        use interop_adb::protocol;
        let mut fixture = ColdStartFixture::with_shell_v2(true).await;
        let startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_shell(power, b"Asleep\n").await;
        // A shell EOF without its EXIT packet is not normal completion.
        fixture.send(protocol::CLSE, encoder, Vec::new()).await;
        fixture.finish_fallback_cleanup().await;
        assert_eq!(startup.await.unwrap().unwrap_err().code, "device_asleep");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_probe_nonzero_shell_v2_rejects_even_valid_catalog() {
        let mut fixture = ColdStartFixture::with_shell_v2(true).await;
        let startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_shell(power, b"Awake\n").await;
        fixture.finish_shell_status(encoder,
            b"List of video encoders:\n --video-codec=h264 --video-encoder=c2.fixture.avc (hw)\n", 7).await;
        fixture.assert_no_open().await;
        assert_eq!(startup.await.unwrap().unwrap_err().code, "encoder_probe");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_probe_incomplete_shell_cleans_up_after_caller_abort() {
        use interop_adb::protocol;
        let mut fixture = ColdStartFixture::with_shell_v2(true).await;
        let startup = fixture.start();
        let (_power, encoder) = fixture.gate_encoder_process().await;
        startup.abort();
        assert!(startup.await.unwrap_err().is_cancelled());
        fixture.send(protocol::CLSE, encoder, Vec::new()).await;
        fixture.finish_fallback_cleanup().await;
        fixture.client.close();
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn encoder_probe_shell_removes_its_jar_without_masking_process_exit() {
        use std::os::unix::fs::PermissionsExt;
        let root = tempfile::tempdir().unwrap();
        let executable = root.path().join("app_process");
        std::fs::write(&executable, "#!/bin/sh\nprintf 'probe output\\n'\nexit 7\n").unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let jar = root.path().join("probe's quoted jar");
        std::fs::write(&jar, b"fixture").unwrap();
        let output = std::process::Command::new("/bin/sh")
            .arg("-c")
            .arg(encoder_probe_command(jar.to_str().unwrap()).unwrap())
            .env("PATH", format!("{}:/usr/bin:/bin", root.path().display()))
            .output()
            .unwrap();
        assert_eq!(
            output.status.code(),
            Some(7),
            "cleanup must preserve probe failure"
        );
        assert_eq!(output.stdout, b"probe output\n");
        assert!(
            !jar.exists(),
            "normal shell completion must attempt JAR cleanup"
        );
    }

    #[tokio::test]
    async fn cold_screen_start_overlaps_power_query_and_real_encoder_probe() {
        let mut fixture = ColdStartFixture::new().await;
        let startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_probe(encoder,
            b"List of video encoders:\n --video-codec=h264 --video-encoder=c2.fixture.avc (hw)\n").await;
        assert!(
            !startup.is_finished(),
            "sleep rejection is still required after a successful probe"
        );
        fixture.finish_shell(power, b"Asleep\n").await;
        let error = startup.await.unwrap().unwrap_err();
        assert_eq!(error.code, "device_asleep");
        assert_eq!(error.details["launchOutcome"], "not_submitted");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_start_still_validates_actual_encoder_catalog() {
        let mut fixture = ColdStartFixture::new().await;
        let startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_shell(power, b"Awake\n").await;
        fixture.finish_probe(encoder,
            b"List of video encoders:\n --video-codec=h265 --video-encoder=c2.fixture.hevc (hw)\n").await;
        let error = startup.await.unwrap().unwrap_err();
        assert_eq!(error.code, "encoder_unavailable");
        assert_eq!(error.details["launchOutcome"], "not_submitted");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_sleep_rejection_waits_for_probe_failure_cleanup() {
        let mut fixture = ColdStartFixture::new().await;
        let mut startup = fixture.start();
        let (power, encoder) = fixture.gate_encoder_process().await;
        fixture.finish_shell(power, b"Asleep\n").await;
        assert!(
            tokio::time::timeout(Duration::from_millis(30), &mut startup)
                .await
                .is_err(),
            "sleep rejection must join the outstanding probe"
        );
        fixture.finish_probe(encoder, b"probe failed\n").await;
        let error = startup.await.unwrap().unwrap_err();
        assert_eq!(error.code, "device_asleep");
        assert_eq!(error.details["launchOutcome"], "not_submitted");
        fixture.client.close();
    }

    #[tokio::test]
    async fn cold_screen_probe_finishes_cleanup_after_startup_caller_is_dropped() {
        let mut fixture = ColdStartFixture::new().await;
        let startup = fixture.start();
        let (_power, encoder) = fixture.gate_encoder_process().await;
        startup.abort();
        assert!(startup.await.unwrap_err().is_cancelled());
        fixture.finish_probe(encoder,
            b"List of video encoders:\n --video-codec=h264 --video-encoder=c2.fixture.avc (hw)\n").await;
        fixture.client.close();
    }

    struct ControlTransportFixture {
        peer: tokio::io::DuplexStream,
        client: interop_adb::Client,
        local: u32,
        control: mpsc::Sender<ControlRequest>,
        cancellation: CancellationToken,
        running: tokio::task::JoinHandle<()>,
    }

    impl ControlTransportFixture {
        async fn start() -> Self {
            use interop_adb::{
                DeviceInfo,
                protocol::{self, Frame},
            };
            let (transport, mut peer) = tokio::io::duplex(64 * 1024);
            let client = interop_adb::Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 64 * 1024,
                    banner: "device::".into(),
                    features: HashSet::new(),
                },
            )
            .unwrap();
            let cancellation = CancellationToken::new();
            let opening_client = client.clone();
            let opening_options = options(&cancellation);
            let opening = tokio::spawn(async move {
                opening_client
                    .open("localabstract:control-fixture", opening_options)
                    .await
                    .unwrap()
            });
            let open = Frame::read(&mut peer, 64 * 1024, true).await.unwrap();
            assert_eq!(open.command, protocol::OPEN);
            Frame::new(protocol::OKAY, 77, open.arg0, Vec::new())
                .write(&mut peer)
                .await
                .unwrap();
            let stream = opening.await.unwrap();
            let (control, requests) = mpsc::channel(64);
            let running = tokio::spawn(run_control(
                stream,
                requests,
                cancellation.clone(),
                crate::events::EventBus::new(8),
                "fixture-device".into(),
                Arc::new(RwLock::new(json!({"sessionId":"fixture"}))),
            ));
            Self {
                peer,
                client,
                local: open.arg0,
                control,
                cancellation,
                running,
            }
        }

        async fn read(&mut self) -> interop_adb::protocol::Frame {
            tokio::time::timeout(
                Duration::from_secs(1),
                interop_adb::protocol::Frame::read(&mut self.peer, 64 * 1024, true),
            )
            .await
            .expect("ADB peer frame")
            .unwrap()
        }

        async fn assert_healthy_service(&mut self) {
            use interop_adb::protocol::{self, Frame};
            assert!(!self.client.is_closed(), "only the control session may end");
            let client = self.client.clone();
            let opening = tokio::spawn(async move {
                client
                    .open("localabstract:healthy-fixture", OperationOptions::default())
                    .await
                    .unwrap()
            });
            let open = self.read().await;
            assert_eq!(open.command, protocol::OPEN);
            Frame::new(protocol::OKAY, 88, open.arg0, Vec::new())
                .write(&mut self.peer)
                .await
                .unwrap();
            let mut healthy = opening.await.unwrap();
            let writing = tokio::spawn(async move {
                healthy.write_all(b"healthy").await.unwrap();
                healthy
            });
            let write = self.read().await;
            assert_eq!(
                (write.command, write.arg0, write.payload.as_slice()),
                (protocol::WRTE, open.arg0, b"healthy".as_slice())
            );
            Frame::new(protocol::OKAY, 88, open.arg0, Vec::new())
                .write(&mut self.peer)
                .await
                .unwrap();
            let mut healthy = writing.await.unwrap();
            Frame::new(protocol::WRTE, 88, open.arg0, b"reply".to_vec())
                .write(&mut self.peer)
                .await
                .unwrap();
            let mut reply = [0; 5];
            healthy.read_exact(&mut reply).await.unwrap();
            assert_eq!(&reply, b"reply");
            drop(healthy);
            let receipt = self.read().await;
            assert_eq!((receipt.command, receipt.arg0), (protocol::OKAY, open.arg0));
            let closed = self.read().await;
            assert_eq!((closed.command, closed.arg0), (protocol::CLSE, open.arg0));
        }
    }

    #[tokio::test]
    async fn control_unacknowledged_write_expires_without_replaying_queued_input() {
        use interop_adb::protocol::{self, Frame};
        let mut fixture = ControlTransportFixture::start().await;
        let sender = fixture.control.clone();
        let first =
            tokio::spawn(
                async move { request_control(&sender, ControlRequest::Send, vec![17]).await },
            );
        let write = fixture.read().await;
        assert_eq!(
            (write.command, write.arg0, write.payload),
            (protocol::WRTE, fixture.local, vec![17])
        );
        // Keep the same Client useful while the control WRTE never gets OKAY.
        fixture.assert_healthy_service().await;
        let sender = fixture.control.clone();
        let queued = tokio::spawn(async move {
            request_control(&sender, ControlRequest::Send, vec![4, 0]).await
        });
        assert_eq!(first.await.unwrap().unwrap_err().code, "timeout");
        tokio::time::timeout(Duration::from_secs(1), &mut fixture.running)
            .await
            .expect("a timed-out control write must end its actor and discard queued input")
            .unwrap();
        assert!(queued.await.unwrap().is_err());
        // The only later control-route frame is CLSE, never the queued input.
        let closed = fixture.read().await;
        assert_eq!(
            (closed.command, closed.arg0),
            (protocol::CLSE, fixture.local)
        );
        Frame::new(protocol::OKAY, 77, fixture.local, Vec::new())
            .write(&mut fixture.peer)
            .await
            .unwrap();
        let closed = fixture.read().await;
        assert_eq!(
            (closed.command, closed.arg0),
            (protocol::CLSE, fixture.local),
            "a late write ACK cannot resurrect the closed route or replay input"
        );
        fixture.assert_healthy_service().await;
        fixture.client.close();
    }

    #[tokio::test]
    async fn control_stop_cancels_wait_for_write_ack() {
        use interop_adb::protocol;
        let mut fixture = ControlTransportFixture::start().await;
        let sender = fixture.control.clone();
        let writing =
            tokio::spawn(
                async move { request_control(&sender, ControlRequest::Send, vec![17]).await },
            );
        assert_eq!(fixture.read().await.command, protocol::WRTE);
        fixture.cancellation.cancel();
        tokio::time::timeout(Duration::from_secs(1), &mut fixture.running)
            .await
            .expect("stopping a session must cancel its pending write receipt")
            .unwrap();
        assert!(writing.await.unwrap().is_err());
        assert_eq!(fixture.read().await.command, protocol::CLSE);
        fixture.assert_healthy_service().await;
        fixture.client.close();
    }

    #[tokio::test]
    async fn control_queue_admission_is_inside_request_deadline() {
        let (control, mut requests) = mpsc::channel(1);
        let (reply, _receiver) = oneshot::channel();
        control
            .send(ControlRequest::Send(
                vec![17],
                ControlReply {
                    deadline: Instant::now() + Duration::from_secs(6),
                    sender: reply,
                },
            ))
            .await
            .unwrap();
        let started = Instant::now();
        let result = tokio::time::timeout(
            Duration::from_millis(6500),
            request_control(&control, ControlRequest::Send, vec![4, 0]),
        )
        .await
        .expect("a full queue must not extend the six-second request deadline");
        assert_eq!(result.unwrap_err().code, "timeout");
        assert!(started.elapsed() < Duration::from_millis(6500));
        requests.recv().await.unwrap();
        assert!(
            requests.try_recv().is_err(),
            "timed-out admission must not enqueue input later"
        );
    }

    #[tokio::test]
    async fn control_actor_discards_expired_and_cancelled_queued_input() {
        use interop_adb::protocol::{self, Frame};
        let mut fixture = ControlTransportFixture::start().await;
        let sender = fixture.control.clone();
        let first =
            tokio::spawn(
                async move { request_control(&sender, ControlRequest::Send, vec![17]).await },
            );
        assert_eq!(fixture.read().await.command, protocol::WRTE);
        let (reply, _receiver) = oneshot::channel();
        fixture
            .control
            .send(ControlRequest::Send(
                vec![4, 0],
                ControlReply {
                    deadline: Instant::now() - Duration::from_millis(1),
                    sender: reply,
                },
            ))
            .await
            .unwrap();
        let (reply, receiver) = oneshot::channel();
        drop(receiver);
        fixture
            .control
            .send(ControlRequest::Send(
                vec![4, 1],
                ControlReply {
                    deadline: Instant::now() + Duration::from_secs(6),
                    sender: reply,
                },
            ))
            .await
            .unwrap();
        Frame::new(protocol::OKAY, 77, fixture.local, Vec::new())
            .write(&mut fixture.peer)
            .await
            .unwrap();
        first.await.unwrap().unwrap();
        assert!(
            tokio::time::timeout(
                Duration::from_millis(50),
                Frame::read(&mut fixture.peer, 64 * 1024, true)
            )
            .await
            .is_err(),
            "closed or expired callers must never inject their queued input"
        );
        fixture.cancellation.cancel();
        tokio::time::timeout(Duration::from_secs(1), &mut fixture.running)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fixture.read().await.command, protocol::CLSE);
        fixture.assert_healthy_service().await;
        fixture.client.close();
    }

    #[tokio::test]
    async fn control_missing_protocol_reply_keeps_session_and_sequence_identity() {
        use interop_adb::protocol::{self, Frame};
        let mut fixture = ControlTransportFixture::start().await;
        let sender = fixture.control.clone();
        let request = tokio::spawn(async move {
            send_control_request(&sender, |reply| {
                ControlRequest::ClipboardSet("old".into(), false, reply)
            })
            .await
        });
        let write = fixture.read().await;
        assert_eq!(write.command, protocol::WRTE);
        assert_eq!(write.payload[0], 9);
        let old_sequence = write.payload[1..9].to_vec();
        Frame::new(protocol::OKAY, 77, fixture.local, Vec::new())
            .write(&mut fixture.peer)
            .await
            .unwrap();
        assert_eq!(request.await.unwrap().unwrap_err().code, "timeout");
        assert!(
            !fixture.running.is_finished(),
            "missing protocol ACK must not end a healthy session"
        );
        assert!(!fixture.cancellation.is_cancelled());
        fixture.assert_healthy_service().await;

        let sender = fixture.control.clone();
        let mut next = tokio::spawn(async move {
            send_control_request(&sender, |reply| {
                ControlRequest::ClipboardSet("new".into(), false, reply)
            })
            .await
        });
        let write = fixture.read().await;
        assert_eq!(write.command, protocol::WRTE);
        let next_sequence = write.payload[1..9].to_vec();
        assert_ne!(old_sequence, next_sequence);
        Frame::new(protocol::OKAY, 77, fixture.local, Vec::new())
            .write(&mut fixture.peer)
            .await
            .unwrap();
        let mut old_ack = vec![1];
        old_ack.extend_from_slice(&old_sequence);
        Frame::new(protocol::WRTE, 77, fixture.local, old_ack)
            .write(&mut fixture.peer)
            .await
            .unwrap();
        assert_eq!(fixture.read().await.command, protocol::OKAY);
        assert!(
            tokio::time::timeout(Duration::from_millis(50), &mut next)
                .await
                .is_err(),
            "a late protocol ACK must not satisfy a newer request"
        );
        let mut next_ack = vec![1];
        next_ack.extend_from_slice(&next_sequence);
        Frame::new(protocol::WRTE, 77, fixture.local, next_ack)
            .write(&mut fixture.peer)
            .await
            .unwrap();
        assert_eq!(fixture.read().await.command, protocol::OKAY);
        let receipt = next.await.unwrap().unwrap();
        assert_eq!(receipt["applied"], true);
        fixture.cancellation.cancel();
        tokio::time::timeout(Duration::from_secs(1), &mut fixture.running)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fixture.read().await.command, protocol::CLSE);
        fixture.client.close();
    }

    // Exercise the actual ADB route and run_video, rather than only a packet
    // parser: the HTTP relay cannot see bytes buffered by this upstream hop.
    struct VideoTransportFixture {
        peer: tokio::io::DuplexStream,
        client: interop_adb::Client,
        local: u32,
        output: tokio::net::TcpStream,
        state: Arc<RwLock<Value>>,
        cancellation: CancellationToken,
        running: tokio::task::JoinHandle<()>,
    }

    impl VideoTransportFixture {
        async fn start() -> Self {
            Self::with_trace(false).await
        }

        async fn with_trace(tracing: bool) -> Self {
            use interop_adb::{
                DeviceInfo,
                protocol::{self, Frame},
            };
            let (transport, mut peer) = tokio::io::duplex(64 * 1024);
            let client = interop_adb::Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 64 * 1024,
                    banner: "device::".into(),
                    features: HashSet::new(),
                },
            )
            .unwrap();
            let cancellation = CancellationToken::new();
            let opening_client = client.clone();
            let opening_options = options(&cancellation);
            let opening = tokio::spawn(async move {
                opening_client
                    .open("localabstract:scrcpy-fixture", opening_options)
                    .await
                    .unwrap()
            });
            let open = Frame::read(&mut peer, 64 * 1024, true).await.unwrap();
            assert_eq!(open.command, protocol::OPEN);
            Frame::new(protocol::OKAY, 77, open.arg0, Vec::new())
                .write(&mut peer)
                .await
                .unwrap();
            let video = opening.await.unwrap();
            let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
                .await
                .unwrap();
            let address = listener.local_addr().unwrap();
            let state = Arc::new(RwLock::new(json!({
                "sessionId":"fixture", "status":"streaming", "textureId":1,
            })));
            if tracing {
                state.write().await["transportTrace"] = json!([]);
            }
            let token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
            let running = tokio::spawn(run_video(
                listener,
                token.into(),
                video,
                b"fixture-preface".to_vec(),
                SessionContext {
                    cancellation: cancellation.clone(),
                    state: state.clone(),
                    events: crate::events::EventBus::new(8),
                    device: "fixture-device".into(),
                },
            ));
            let mut output = tokio::net::TcpStream::connect(address).await.unwrap();
            output
                .write_all(format!("{token}\n").as_bytes())
                .await
                .unwrap();
            let mut preface = [0; 15];
            tokio::time::timeout(Duration::from_secs(1), output.read_exact(&mut preface))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(&preface, b"fixture-preface");
            Self {
                peer,
                client,
                local: open.arg0,
                output,
                state,
                cancellation,
                running,
            }
        }

        async fn deliver(&mut self, bytes: Vec<u8>) {
            use interop_adb::protocol::{self, Frame};
            Frame::new(protocol::WRTE, 77, self.local, bytes)
                .write(&mut self.peer)
                .await
                .unwrap();
            let receipt = tokio::time::timeout(
                Duration::from_secs(1),
                Frame::read(&mut self.peer, 64 * 1024, true),
            )
            .await
            .unwrap()
            .unwrap();
            assert_eq!(
                receipt.command,
                protocol::OKAY,
                "run_video consumed this ADB fragment"
            );
        }

        async fn stop(&mut self) {
            use interop_adb::protocol::{self, Frame};
            self.cancellation.cancel();
            tokio::time::timeout(Duration::from_secs(1), &mut self.running)
                .await
                .expect("cancel releases the actual forwarding task")
                .unwrap();
            let mut remaining = Vec::new();
            tokio::time::timeout(
                Duration::from_secs(1),
                self.output.read_to_end(&mut remaining),
            )
            .await
            .expect("cancel closes the authenticated media output")
            .unwrap();
            let closed = tokio::time::timeout(
                Duration::from_secs(1),
                Frame::read(&mut self.peer, 64 * 1024, true),
            )
            .await
            .unwrap()
            .unwrap();
            assert_eq!(
                closed.command,
                protocol::CLSE,
                "only the media ADB route is closed"
            );
            assert!(
                !self.client.is_closed(),
                "other device services remain usable"
            );
            self.client.close();
        }
    }

    #[tokio::test]
    async fn video_transport_trace_correlates_fragmented_packets_and_bounds_each_capture_segment() {
        for tracing in [false, true] {
            let mut fixture = VideoTransportFixture::with_trace(tracing).await;
            let packet = |pts: u64| {
                [
                    pts.to_be_bytes().as_slice(),
                    1u32.to_be_bytes().as_slice(),
                    &[0x65],
                ]
                .concat()
            };
            let before = crate::media::monotonic_micros();
            let first = packet(5_000_000);
            fixture.deliver(first[..1].to_vec()).await;
            tokio::time::sleep(Duration::from_millis(20)).await;
            fixture.deliver(first[1..].to_vec()).await;
            let mut bytes = [0; 13];
            fixture.output.read_exact(&mut bytes).await.unwrap();
            assert_eq!(bytes.as_slice(), first);
            // The peer's ADB ACK does not prove run_video has published its
            // completed socket write. Await that actual receipt explicitly.
            if tracing {
                let frames = tokio::time::timeout(Duration::from_secs(1), async {
                    loop {
                        let state = fixture.state.read().await;
                        if state["transportTrace"].as_array().unwrap().len() == 1 {
                            break state["transportTrace"].clone();
                        }
                        drop(state);
                        tokio::task::yield_now().await;
                    }
                })
                .await
                .unwrap();
                let frame = &frames[0];
                assert_eq!(frame["sourcePtsUs"], 5_000_000);
                assert_eq!(frame["captureSegment"], 1);
                let first = frame["firstByteUs"].as_u64().unwrap();
                let read = frame["readCompletedUs"].as_u64().unwrap();
                let write = frame["writeStartedUs"].as_u64().unwrap();
                let written = frame["writtenUs"].as_u64().unwrap();
                assert!(before <= first && first <= read && read <= write && write <= written);
                let first_adb = &frame["firstAdbRead"];
                let last_adb = &frame["lastAdbRead"];
                assert_eq!(first_adb["sequence"], 1);
                assert_eq!(first_adb["bytes"], 1);
                assert_eq!(last_adb["sequence"], 2);
                assert_eq!(last_adb["bytes"], 12);
                for receipt in [first_adb, last_adb] {
                    assert!(
                        receipt["payloadStartedUs"].as_u64().unwrap()
                            <= receipt["payloadReadUs"].as_u64().unwrap()
                    );
                    assert!(
                        receipt["payloadReadUs"].as_u64().unwrap()
                            <= receipt["routedUs"].as_u64().unwrap()
                    );
                    assert!(
                        receipt["routedUs"].as_u64().unwrap()
                            <= receipt["firstConsumedUs"].as_u64().unwrap()
                    );
                }
                assert!(
                    read - first >= 10_000,
                    "the real split ADB payload was held for 20ms"
                );
            }
            let marker = [
                0x8000_0000u32.to_be_bytes(),
                288u32.to_be_bytes(),
                640u32.to_be_bytes(),
            ]
            .concat();
            fixture.deliver(marker.clone()).await;
            let mut metadata = [0; 12];
            fixture.output.read_exact(&mut metadata).await.unwrap();
            assert_eq!(metadata.as_slice(), marker);
            for index in 1..=258 {
                fixture.deliver(packet(5_000_000 + index * 1000)).await;
                fixture.output.read_exact(&mut bytes).await.unwrap();
            }
            // Codec configuration is forwarded but must not masquerade as a
            // source-PTS frame or consume a slot in the bounded frame trace.
            fixture.deliver(packet(1 << 62)).await;
            fixture.output.read_exact(&mut bytes).await.unwrap();
            fixture.deliver(packet(5_259_000)).await;
            fixture.output.read_exact(&mut bytes).await.unwrap();
            if tracing {
                let frames = tokio::time::timeout(Duration::from_secs(1), async {
                    loop {
                        let state = fixture.state.read().await;
                        let frames = state["transportTrace"].as_array().unwrap();
                        if frames.last().is_some_and(|f| f["sourcePtsUs"] == 5_259_000) {
                            break frames.clone();
                        }
                        drop(state);
                        tokio::task::yield_now().await;
                    }
                })
                .await
                .unwrap();
                assert_eq!(frames.len(), 256);
                assert_eq!(frames[0]["sourcePtsUs"], 5_004_000);
                assert!(frames.iter().all(|f| f["captureSegment"] == 2));
            } else {
                assert!(fixture.state.read().await.get("transportTrace").is_none());
            }
            fixture.stop().await;
        }
    }

    async fn partial_video_unit_must_expire(bytes: Vec<u8>) {
        let mut fixture = VideoTransportFixture::start().await;
        fixture.deliver(bytes).await;
        let completed = tokio::time::timeout(Duration::from_secs(11), async {
            while !fixture.running.is_finished() {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .is_ok();
        let status = fixture.state.read().await.clone();
        fixture.stop().await;
        assert!(
            completed,
            "an already-started scrcpy unit must expire after 10 seconds; status={status}"
        );
        assert_eq!(status["status"], "failed");
    }

    #[tokio::test]
    async fn video_transport_deadline_truncated_units_release_the_real_adb_route() {
        let session = [
            0x8000_0000u32.to_be_bytes(),
            288u32.to_be_bytes(),
            640u32.to_be_bytes(),
        ]
        .concat();
        let mut payload = [0u64.to_be_bytes().as_slice(), 4u32.to_be_bytes().as_slice()].concat();
        payload.push(0x65);
        // All cases run concurrently so this regression has one real 11s window.
        tokio::join!(
            partial_video_unit_must_expire(vec![0]),
            partial_video_unit_must_expire(session[..11].to_vec()),
            partial_video_unit_must_expire(payload),
        );
    }

    #[tokio::test]
    async fn video_transport_deadline_complete_units_allow_static_idle_and_cancel() {
        let mut fixture = VideoTransportFixture::start().await;
        let packet = [
            0u64.to_be_bytes().as_slice(),
            1u32.to_be_bytes().as_slice(),
            &[0x65],
        ]
        .concat();
        fixture.deliver(packet.clone()).await;
        let mut received = vec![0; packet.len()];
        tokio::time::timeout(
            Duration::from_secs(1),
            fixture.output.read_exact(&mut received),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(received, packet);
        tokio::time::sleep(Duration::from_millis(10_300)).await;
        assert!(
            !fixture.running.is_finished(),
            "no first byte means normal static-screen idle"
        );
        fixture.deliver(packet.clone()).await;
        tokio::time::timeout(
            Duration::from_secs(1),
            fixture.output.read_exact(&mut received),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(
            received, packet,
            "idle must not discard the next complete compressed packet"
        );
        fixture.stop().await;
    }

    #[tokio::test]
    async fn video_transport_deadline_cancel_during_partial_unit_is_prompt() {
        let mut fixture = VideoTransportFixture::start().await;
        fixture.deliver(vec![0]).await;
        fixture.stop().await;
    }

    #[tokio::test]
    async fn renderer_ready_preserves_presentation_pause_after_generation_replacement() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let cancellation = CancellationToken::new();
        let _reservation = runtime
            .activities
            .admission
            .reserve_session(
                "session:fixture".into(),
                "device".into(),
                "window".into(),
                cancellation.clone(),
            )
            .unwrap();
        let state = Arc::new(RwLock::new(json!({
            "sessionId":"fixture", "deviceId":"device", "status":"starting",
            "width":1080, "height":1920,
        })));
        let (control, mut requests) = mpsc::channel(1);
        // The ready boundary only consumes renderer evidence: no device or
        // remote process is started by this fixture.
        runtime.activities.sessions.lock().await.insert(
            "fixture".into(),
            Session {
                device_id: "device".into(),
                package: None,
                cancellation,
                control,
                state: state.clone(),
                process_closed: Arc::new(AtomicBool::new(true)),
                process: Some(OwnedProcess {
                    pid: 0,
                    started: 0,
                    jar: String::new(),
                    scid: String::new(),
                }),
            },
        );
        let initial = runtime
            .session_command(
                "session.ready",
                &json!({"sessionId":"fixture", "textureId":1}),
            )
            .await
            .unwrap();
        assert_eq!(initial["status"], "streaming");
        assert_eq!(
            runtime.activities.admission.activities()[0].status,
            ResourceStatus::Streaming
        );

        // Local presentation pauses before a pending generation's ready receipt.
        let paused = runtime
            .session_command("session.pause", &json!({"sessionId":"fixture"}))
            .await
            .unwrap();
        assert_eq!(paused["status"], "paused");
        assert_eq!(paused["presentationOnly"], true);
        assert_eq!(paused["capturePaused"], false);
        assert!(
            requests.try_recv().is_err(),
            "pause must not send a remote control message"
        );
        let delayed = runtime
            .session_command(
                "session.ready",
                &json!({"sessionId":"fixture", "textureId":2,
                    "decodedWidth":640, "decodedHeight":360, "decoderName":"replacement",
                    "status":"streaming", "capturePaused":false}),
            )
            .await
            .unwrap();
        assert_eq!(delayed["textureId"], 2);
        assert_eq!(delayed["decodedWidth"], 640);
        assert_eq!(delayed["decodedHeight"], 360);
        assert_eq!(delayed["decoderName"], "replacement");
        assert_eq!(delayed["status"], "paused");
        assert_eq!(delayed["capturePaused"], false);
        assert_eq!(delayed["presentationOnly"], true);
        let activity = &runtime.activities.admission.activities()[0];
        assert_eq!(activity.status, ResourceStatus::Paused);
        assert!(activity.can_resume);
        assert!(!activity.can_pause);

        // A subsequent local resume still accepts renderer updates.
        let reset = async {
            let request = requests.recv().await.unwrap();
            let ControlRequest::Send(bytes, reply) = request else {
                panic!("resume must use the official RESET_VIDEO request");
            };
            assert_eq!(bytes, vec![17]);
            let _ = reply.send(Ok(json!({"sent":true})));
        };
        let resume_params = json!({"sessionId":"fixture"});
        let (resumed, ()) = tokio::join!(
            runtime.session_command("session.resume", &resume_params),
            reset
        );
        assert_eq!(resumed.unwrap()["capturePaused"], false);
        let resumed = runtime
            .session_command(
                "session.ready",
                &json!({"sessionId":"fixture", "textureId":3}),
            )
            .await
            .unwrap();
        assert_eq!(resumed["textureId"], 3);
        assert_eq!(resumed["status"], "streaming");
        assert_eq!(resumed["capturePaused"], false);
        assert_eq!(
            runtime.activities.admission.activities()[0].status,
            ResourceStatus::Streaming
        );
    }

    #[tokio::test]
    #[ignore = "requires real Android adbd; reserves App guard slots without allocating additional encoders"]
    async fn real_admission_rejection_preserves_owned_encoded_stream_and_failed_start_releases_slot()
     {
        let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
        let port: u16 = std::env::var("INTEROP_ADBD_PORT")
            .expect("set INTEROP_ADBD_PORT")
            .parse()
            .unwrap();
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let device = runtime
            .invoke("devices.add", json!({"address":address,"port":port}))
            .await
            .unwrap();
        let device = device["deviceId"].as_str().unwrap();
        runtime
            .invoke("devices.connect", json!({"deviceId":device}))
            .await
            .unwrap();
        let old = runtime.start_session(&json!({"deviceId":device,"videoCodec":"h264","maxSize":720,"maxFps":30,"videoBitRate":1_000_000})).await.unwrap();
        let old_id = old["sessionId"].as_str().unwrap();
        let mut socket = tokio::net::TcpStream::connect((
            "127.0.0.1",
            old["videoPort"].as_u64().unwrap() as u16,
        ))
        .await
        .unwrap();
        socket
            .write_all(old["videoToken"].as_str().unwrap().as_bytes())
            .await
            .unwrap();
        socket.write_all(b"\n").await.unwrap();
        let mut reservations = Vec::new();
        // These occupy application slots, not hardware resources. One real
        // encoded stream suffices; never exhaust the emulator's actual codecs.
        for index in 1..crate::resource::APP_SESSION_LIMIT {
            reservations.push(
                runtime
                    .activities
                    .admission
                    .reserve_session(
                        format!("session:fixture-{index}"),
                        device.to_owned(),
                        "pending fixture".into(),
                        CancellationToken::new(),
                    )
                    .unwrap(),
            );
        }
        let busy = runtime
            .start_session(&json!({"deviceId":device}))
            .await
            .unwrap_err();
        assert_eq!(busy.code, "resource_busy");
        assert_eq!(busy.details["reason"], "app_session_guard");
        assert_eq!(busy.details["hardwareCapacityKnown"], false);
        assert!(
            busy.details["activities"]
                .as_array()
                .unwrap()
                .iter()
                .any(|activity| activity["id"] == format!("session:{old_id}"))
        );
        assert_eq!(
            runtime.activities.sessions.lock().await[old_id]
                .state
                .read()
                .await["sessionId"],
            old_id
        );
        assert!(
            !runtime.activities.sessions.lock().await[old_id]
                .cancellation
                .is_cancelled()
        );
        // The already running stream still supplies its real config/keyframe.
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let mut header = [0; 12];
                socket.read_exact(&mut header).await.unwrap();
                if session_dimensions(&header).unwrap().is_some() {
                    continue;
                }
                let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
                let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
                assert!((1..=MAX_PACKET).contains(&length));
                socket.read_exact(&mut vec![0; length]).await.unwrap();
                if flags & (1 << 61) != 0 && flags & (1 << 62) == 0 {
                    break;
                }
            }
        })
        .await
        .unwrap();
        drop(reservations);
        let invalid = runtime
            .start_session(&json!({"deviceId":device,"videoEncoder":"c2.interop.missing.encoder"}))
            .await
            .unwrap_err();
        assert_eq!(invalid.code, "encoder_unavailable");
        let reserved = runtime.activities.admission.activities();
        assert_eq!(reserved.len(), 1);
        assert_eq!(reserved[0].id, format!("session:{old_id}"));
        assert!(
            !runtime.activities.sessions.lock().await[old_id]
                .cancellation
                .is_cancelled()
        );
        drop(socket);
        runtime.stop_session(old_id).await;
        tokio::time::timeout(Duration::from_secs(5), async {
            while !runtime.activities.admission.activities().is_empty() {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        runtime
            .invoke("devices.disconnect", json!({"deviceId":device}))
            .await
            .unwrap();
    }

    #[test]
    fn decoder_receipt_cannot_change_remote_input_coordinates() {
        let mut state = json!({"width":230,"height":512});
        record_decoded_size(
            &mut state,
            &json!({"width":230,"height":512,"decodedWidth":240,"decodedHeight":512}),
        );
        assert_eq!(state["width"], 230);
        assert_eq!(state["height"], 512);
        assert_eq!(state["decodedWidth"], 240);
        record_decoded_size(
            &mut state,
            &json!({"decodedWidth":999999,"decodedHeight":512}),
        );
        assert_eq!(state["decodedWidth"], 240);
    }

    #[test]
    fn video_encoders_require_official_header_and_preserve_codec_association() {
        let list = "[server] INFO: List of video encoders:\n    --video-codec=h264 --video-encoder=c2.android.avc.encoder (sw)\n    --video-codec=h265 --video-encoder=c2.vendor.hevc.encoder (hw) [vendor]\n    --audio-codec=opus --audio-encoder=c2.android.opus.encoder\n    --video-codec=h264 --video-encoder=c2.android.avc.encoder (alias for other)";
        let encoders = parse_encoders(list).unwrap();
        assert_eq!(encoders.len(), 2);
        assert_eq!(encoders[0].hardware, Some(false));
        assert_eq!(encoders[1].hardware, Some(true));
        assert!(parse_encoders("not a successful server list").is_err());
        assert!(parse_encoders("List of video encoders:\n--video-codec=h264").is_err());
        assert!(
            parse_encoders("List of video encoders:")
                .unwrap()
                .is_empty()
        );
        let mut settings = crate::preferences::defaults();
        settings["videoCodec"] = json!("h265");
        settings["videoEncoder"] = json!("c2.android.avc.encoder");
        assert_eq!(
            validate_encoder_selection(&settings, &encoders)
                .unwrap_err()
                .code,
            "encoder_unavailable"
        );
        settings["videoEncoder"] = json!("c2.vendor.hevc.encoder");
        validate_encoder_selection(&settings, &encoders).unwrap();
    }

    #[test]
    fn live_repeat_cadence_respects_frame_budget_and_low_fps_choices() {
        for fps in 1..=120 {
            let delay = repeat_frame_delay_us(fps);
            assert!((33_334..=1_000_000).contains(&delay));
            assert!(
                delay * fps >= 1_000_000,
                "repeats exceed requested {fps}fps"
            );
            assert!(delay * 30 >= 1_000_000, "static repeat budget exceeded");
        }
    }

    #[test]
    fn five_codec_wire_ids_include_leading_zero_and_quality_rejects_injection() {
        assert_eq!(video_codec("h264").unwrap().wire, *b"h264");
        assert_eq!(video_codec("h265").unwrap().wire, *b"h265");
        assert_eq!(video_codec("av1").unwrap().wire, [0, b'a', b'v', b'1']);
        assert_eq!(video_codec("vp8").unwrap().wire, [0, b'v', b'p', b'8']);
        assert_eq!(video_codec("vp9").unwrap().wire, [0, b'v', b'p', b'9']);
        let current = crate::preferences::defaults();
        for bad in [
            json!({"codec":null}),
            json!({"codec":"h266"}),
            json!({"videoEncoder":"c2.x; reboot"}),
            json!({"videoEncoder":"$(id)"}),
            json!({"maxSize":"1280"}),
        ] {
            assert!(quality_patch(&current, &bad).is_err(), "accepted {bad}");
        }
        let next = quality_patch(
            &current,
            &json!({"preset":"smooth","videoCodec":"av1","videoEncoder":null}),
        )
        .unwrap();
        assert_eq!(next["maxFps"], 30);
        assert_eq!(next["videoCodec"], "av1");
        assert_eq!(current["videoCodec"], "h264");
    }

    #[test]
    fn launch_receipt_requires_a_complete_decimal_kernel_identity() {
        assert_eq!(
            launch_identity(b"__INTEROP_PID__123:456").unwrap(),
            (123, 456)
        );
        assert_eq!(
            launch_identity(b"__INTEROP_PID__4294967295:18446744073709551615").unwrap(),
            (u32::MAX, u64::MAX)
        );
        for receipt in [
            "__INTEROP_PID__123",
            "__INTEROP_PID__123:",
            "__INTEROP_PID__:456",
            "__INTEROP_PID__123:456:789",
            "__INTEROP_PID__0:456",
            "__INTEROP_PID__1:456",
            "__INTEROP_PID__123:0",
            "__INTEROP_PID__+123:456",
            "__INTEROP_PID__123:+456",
            "__INTEROP_PID__-123:456",
            "__INTEROP_PID__123:-456",
            "__INTEROP_PID__123: 456",
            "__INTEROP_PID__123:456\r",
            "__INTEROP_PID__4294967296:456",
            "__INTEROP_PID__123:18446744073709551616",
            "__INTEROP_PID__123:４５６",
            "123:456",
        ] {
            assert_eq!(
                launch_identity(receipt.as_bytes()).unwrap_err().code,
                "process_identity",
                "accepted {receipt:?}"
            );
        }
        assert!(launch_identity(&[0xff]).is_err());
    }

    #[test]
    fn session_headers_have_dimensions_in_the_last_eight_bytes() {
        let mut bytes = [0; 12];
        bytes[..4].copy_from_slice(&0x8000_0001u32.to_be_bytes());
        bytes[4..8].copy_from_slice(&720u32.to_be_bytes());
        bytes[8..].copy_from_slice(&1280u32.to_be_bytes());
        assert_eq!(session_dimensions(&bytes).unwrap(), Some((720, 1280)));
        bytes[4..8].fill(0);
        assert!(session_dimensions(&bytes).is_err());
        assert_eq!(session_dimensions(&[0; 12]).unwrap(), None);
    }
    #[test]
    fn touch_is_big_endian_and_rejects_stale_sizes_and_outside_points() {
        let mut params = json!({"action":"down","pointerId":7,"x":100,"y":200,"screenWidth":720,"screenHeight":1280,"pressure":1.0});
        let state = json!({"width":720,"height":1280});
        let bytes = touch_message(&params, &state).unwrap();
        assert_eq!(bytes.len(), 32);
        assert_eq!(&bytes[2..10], &7u64.to_be_bytes());
        assert_eq!(&bytes[22..24], &u16::MAX.to_be_bytes());
        params["x"] = json!(720);
        assert!(touch_message(&params, &state).is_err());
        params["x"] = json!(1);
        params["screenWidth"] = json!(1280);
        assert!(touch_message(&params, &state).is_err());
    }
    #[test]
    fn official_app_labels_keep_spaces_and_long_name_continuations() {
        let apps = parse_apps("[server] INFO: List of apps:\n * System Settings                 com.android.settings\n - An extremely long application name\n                                  org.example.long\n").unwrap();
        assert_eq!(apps.len(), 2);
        assert_eq!(apps[0]["name"], "System Settings");
        assert_eq!(apps[1]["packageName"], "org.example.long");
    }
}
