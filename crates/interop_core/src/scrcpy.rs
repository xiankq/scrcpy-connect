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
    collections::{HashMap, HashSet, VecDeque},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    sync::{Mutex, RwLock, mpsc, oneshot},
    time::Instant,
};

pub(crate) const SERVER: &[u8] = include_bytes!("../../../servers/vendor/scrcpy-server-v5.0.1");
pub(crate) const SERVER_SHA: &str =
    "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536";
const CAPTURE_SERVER: &[u8] = include_bytes!("../../../servers/scrcpy/interop-scrcpy-server.jar");
const CAPTURE_SERVER_SHA: &str =
    include_str!("../../../servers/scrcpy/interop-scrcpy-server.sha256");
const MAX_PACKET: usize = 16 * 1024 * 1024;
const CLIPBOARD_MAX: usize = (1 << 18) - 14;

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

#[derive(Clone)]
struct VideoEncoder {
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
#[derive(Clone)]
struct OwnedProcess {
    pid: u32,
    started: u64,
    jar: String,
    scid: String,
}

fn process_stat(bytes: &[u8]) -> CoreResult<(char, u64)> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| CoreError::new("process_identity", "服务进程标识无效。"))?;
    // comm is parenthesized and may itself contain spaces or parentheses.
    let (_, fields) = text
        .rsplit_once(") ")
        .ok_or_else(|| CoreError::new("process_identity", "服务进程状态无效。"))?;
    let fields = fields.split_ascii_whitespace().collect::<Vec<_>>();
    let state = fields
        .first()
        .and_then(|v| v.chars().next())
        .ok_or_else(|| CoreError::new("process_identity", "服务进程状态缺失。"))?;
    let started = fields
        .get(19)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| CoreError::new("process_identity", "服务进程启动标识缺失。"))?;
    Ok((state, started))
}

impl OwnedProcess {
    async fn capture(
        client: &interop_adb::Client,
        pid: u32,
        jar: &str,
        scid: String,
    ) -> CoreResult<Self> {
        let stat = client
            .shell(
                &format!("cat /proc/{pid}/stat"),
                4096,
                OperationOptions::default(),
            )
            .await?;
        let (_, started) = process_stat(&stat.stdout)?;
        let process = Self {
            pid,
            started,
            jar: jar.to_owned(),
            scid,
        };
        process.signal(client, false).await?;
        Ok(process)
    }

    async fn signal(&self, client: &interop_adb::Client, pause: bool) -> CoreResult<()> {
        // Revalidate in the signaling shell, including the kernel start time,
        // rather than retaining a numeric PID across independent shell calls.
        // The launcher also keeps a parent alive to CONT on stdin EOF.
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
kill -{signal} "$p" || exit 42
i=0
while [ "$i" -lt 30 ]; do
  identity || exit 41
  case "$state" in {states}) printf 'verified:%s\n' "$state"; exit 0 ;; esac
  i=$((i+1))
  sleep 0.01
done
exit 43"#,
            pid = self.pid,
            started = self.started,
            signal = if pause { "STOP" } else { "CONT" },
            states = if pause { "T|t" } else { "R|S|D|I" }
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
                "process_control",
                "无法确认本会话服务进程的暂停或恢复状态。",
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
    Launch(
        Vec<u8>,
        crate::app_open::LaunchPermit,
        oneshot::Sender<CoreResult<Value>>,
    ),
    Send(Vec<u8>, oneshot::Sender<CoreResult<Value>>),
    ClipboardGet(oneshot::Sender<CoreResult<Value>>),
    ClipboardSet(String, bool, oneshot::Sender<CoreResult<Value>>),
    Capture(bool, oneshot::Sender<CoreResult<Value>>),
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
            self.start_session_with_settings(params, &settings).await
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
            for session in self.sessions.lock().await.values() {
                if session.device_id == device_id && session.package == package {
                    let observed = session.state.read().await;
                    if observed["launchOutcome"] == "unknown" {
                        return Err(unknown_app_launch(&observed));
                    }
                }
            }
        }
        let device = self.device(&device_id).await?;
        if package.is_none() && self.device_sleeping(&device_id).await? == Some(true) {
            return Err(CoreError::new(
                "device_asleep",
                "手机当前处于系统休眠，尚未提供画面。可在手机上唤醒，或明确选择唤醒手机；这可能点亮实体屏幕，仍需使用手机自身的锁屏解锁。",
            ));
        }
        if package.is_some() && device.api_level.is_some_and(|level| level < 29) {
            return Err(CoreError::new(
                "unsupported",
                "独立应用窗口需要 Android 10 或更新版本。",
            ));
        }
        if format!("{:x}", Sha256::digest(CAPTURE_SERVER)) != CAPTURE_SERVER_SHA.trim() {
            return Err(CoreError::new("server_integrity", "内置控制服务校验失败。"));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let activity_id = format!("session:{id}");
        let cancellation = CancellationToken::new();
        let mut guard = CancelOnDrop(Some(cancellation.clone()));
        let reservation = match self.resource_admission.reserve_session(
            activity_id.clone(),
            device_id.clone(),
            package.clone().unwrap_or_else(|| "手机屏幕".into()),
            cancellation.clone(),
        ) {
            Ok(reservation) => reservation,
            Err(busy) => return Err(self.session_resource_busy(busy).await),
        };
        let encoders = self.probe_video_encoders(&device_id).await?;
        validate_encoder_selection(settings, &encoders)?;
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
        let bit_rate = settings["videoBitRate"]
            .as_u64()
            .unwrap_or(8_000_000)
            .clamp(500_000, 50_000_000);
        let mut app_launch_submitted = false;
        let startup = async {
            let mut sync = client.sync(OperationOptions::default()).await?;
            sync.push(
                &RemotePath::new(&remote_jar)?,
                &mut &CAPTURE_SERVER[..],
                0o600,
                now().min(u32::MAX as u64) as u32,
                CAPTURE_SERVER.len() as u64,
            )
            .await?;
            drop(sync);
            let mut command = format!(
                "CLASSPATH={} app_process / --nice-name={} com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn video=true audio=false control=true video_codec={} max_size={max_size} max_fps={max_fps} video_bit_rate={bit_rate} tunnel_forward=true cleanup=true vd_destroy_content=false clipboard_autosync=false power_on=false send_dummy_byte=true send_device_meta=true send_stream_meta=true send_frame_meta=true",
                quote(&remote_jar)?,
                quote(&format!("interop.scrcpy:{scid:08x}:{remote_jar}"))?,
                selected_codec.name,
            );
            if let Some(encoder) = selected_encoder {
                command.push(' ');
                command.push_str(&quote(&format!("video_encoder={encoder}"))?);
            }
            if package.is_some() {
                command.push_str(" new_display=1080x1920 vd_system_decorations=false");
            }
            // Keep a shell parent reading its own stdin. EOF resumes a stopped
            // child before waiting, so an unplugged controller cannot strand a
            // frozen service. starttime guards the cleanup signal against reuse.
            command = format!(
                r#"{command} </dev/null &
child=$!
IFS= read -r stat < /proc/$child/stat
rest=${{stat##*) }}
set -- $rest
shift 19
started=$1
resume_child() {{
  IFS= read -r stat < /proc/$child/stat || return
  rest=${{stat##*) }}
  set -- $rest
  shift 19 || return
  [ "$1" = "$started" ] && kill -CONT "$child" 2>/dev/null
}}
trap resume_child EXIT HUP INT TERM
printf '__INTEROP_PID__%s\n' "$child"
while IFS= read -r keepalive; do :; done
resume_child
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
            let pid = std::str::from_utf8(&pid_line)
                .ok()
                .and_then(|line| line.strip_prefix("__INTEROP_PID__"))
                .and_then(|pid| pid.parse::<u32>().ok())
                .filter(|pid| *pid > 1)
                .ok_or_else(|| CoreError::new("process_identity", "服务进程启动标识缺失。"))?;
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
                let mut sessions = self.sessions.lock().await;
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
            let (preface, width, height) = read_video_preface(&mut video, initial).await?;
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
            let process =
                OwnedProcess::capture(&client, pid, &remote_jar, format!("{scid:08x}")).await?;
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
            if app_launch_submitted {
                observed["launchOutcome"] = json!("observed");
            }
            observed.clone()
        };
        result["videoToken"] = json!(return_token);
        let mut sessions = self.sessions.lock().await;
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
        self.resource_admission.cancel_device(device);
        let ids = self
            .sessions
            .lock()
            .await
            .iter()
            .filter(|(_, s)| s.device_id == device)
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        for id in ids {
            let keep_unknown = {
                let sessions = self.sessions.lock().await;
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
            && !self.sessions.lock().await.contains_key(id)
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
            && !self.sessions.lock().await.contains_key(id)
            && self.resource_admission.cancel(&format!("session:{id}"))
        {
            return Ok(
                json!({"sessionId":id,"status":"stopping","starting":true,"applicationStopped":false}),
            );
        }
        if command == "session.list" {
            let mut result = Vec::new();
            for session in self.sessions.lock().await.values() {
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
            let sessions = self.sessions.lock().await;
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
        let process = process.ok_or_else(|| {
            CoreError::new(
                "app_launch_unknown",
                "应用打开结果未知，请先核对并关闭本次记录。",
            )
        })?;
        if command == "session.ready" {
            let texture = params["textureId"]
                .as_i64()
                .filter(|id| *id >= 0)
                .ok_or_else(|| invalid("渲染纹理无效。"))?;
            let mut data = state.write().await;
            data["textureId"] = json!(texture);
            // A replacement renderer may finish after capture was paused.
            // Its texture evidence does not resume the remote source.
            let capture_paused = data["capturePaused"] == true;
            data["status"] = json!(if capture_paused {
                "paused"
            } else {
                "streaming"
            });
            self.resource_admission.set_status(
                &format!("session:{id}"),
                if capture_paused {
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
            let device_id = {
                let data = state.read().await;
                if data["textureId"].is_null() {
                    return Err(CoreError::new("renderer_not_ready", "实时渲染尚未就绪。"));
                }
                data["deviceId"].as_str().expect("device id").to_owned()
            };
            let pausing = command.ends_with("pause");
            let client = self.client(&device_id).await?;
            // Verify our exact process identity without freezing its Binder,
            // display or controller threads. Cooperative capture has its own ACK.
            process.signal(&client, false).await?;
            let (reply, receiver) = oneshot::channel();
            control
                .send(ControlRequest::Capture(pausing, reply))
                .await
                .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?;
            let receipt = receive_reply(receiver).await?;
            if receipt["capturePaused"] != pausing || receipt["confirmed"] != true {
                return Err(CoreError::new(
                    "capture_unconfirmed",
                    "设备未确认捕获状态。",
                ));
            }
            if cancellation.is_cancelled() {
                return Err(CoreError::new("disconnected", "控制会话已结束。"));
            }
            let mut data = state.write().await;
            data["status"] = json!(if pausing { "paused" } else { "streaming" });
            self.resource_admission.set_status(
                &format!("session:{id}"),
                if pausing {
                    ResourceStatus::Paused
                } else {
                    ResourceStatus::Streaming
                },
            );
            data["presentationOnly"] = json!(false);
            data["capturePaused"] = json!(pausing);
            data["captureStateConfirmed"] = json!(true);
            data["capturePauseMode"] = json!("cooperative");
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
                let sessions = self.sessions.lock().await;
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
        let text = if command == "clipboard.set" {
            let text = params["text"]
                .as_str()
                .ok_or_else(|| invalid("剪贴板内容无效。"))?;
            if text.len() > CLIPBOARD_MAX {
                return Err(invalid("剪贴板文字过长。"));
            }
            Some(text)
        } else {
            None
        };
        let control = self
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
        if let Some(text) = text {
            return clipboard_set(&control, text.to_owned(), false).await;
        }
        let (reply, receiver) = oneshot::channel();
        control
            .send(ControlRequest::ClipboardGet(reply))
            .await
            .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?;
        receive_reply(receiver).await
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

    pub(crate) async fn activities(&self) -> CoreResult<Value> {
        let mut sessions = Vec::new();
        for session in self.sessions.lock().await.values() {
            let observed = session.state.read().await;
            if !session.cancellation.is_cancelled() || observed["launchOutcome"] == "unknown" {
                sessions.push(observed.clone());
            }
        }
        for record in self.app_opens.unresolved(None).await {
            if !sessions
                .iter()
                .any(|session| session["sessionId"] == record["sessionId"])
            {
                sessions.push(record);
            }
        }
        let transfers = self.list_transfers().await?;
        let devices = self.store.read().await.devices.clone();
        let device_name = |id: &str| {
            devices
                .iter()
                .find(|device| device.id == id)
                .map(|device| device.name.clone())
                .unwrap_or_else(|| "Android 设备".into())
        };
        let mut activities = Vec::new();
        for (device, client) in self.connections.lock().await.iter() {
            if !client.is_closed() {
                activities.push(json!({"id":format!("connection:{device}"),"deviceId":device,"deviceName":device_name(device),"name":"设备连接","status":"connected","canStop":true,"stopImpact":"断开这台设备，并停止它的控制会话和传输任务；其他设备不受影响。"}));
            }
        }
        for session in &sessions {
            activities.push(json!({"id":format!("session:{}",session["sessionId"].as_str().unwrap_or_default()),"deviceId":session["deviceId"],"deviceName":device_name(session["deviceId"].as_str().unwrap_or_default()),"name":session["name"],"status":session["status"],"canStop":true,"stopImpact":"仅关闭这个控制会话，手机应用任务交回设备，不会强停应用。"}));
        }
        let known = activities
            .iter()
            .filter_map(|activity| activity["id"].as_str().map(str::to_owned))
            .collect::<HashSet<_>>();
        for reserved in self
            .resource_admission
            .activities()
            .into_iter()
            .filter(|reserved| !known.contains(&reserved.id))
        {
            activities.push(json!({"id":reserved.id,"deviceId":reserved.device_id,"deviceName":device_name(&reserved.device_id),
                "name":reserved.name,"status":reserved.status,"canStop":true,"canPause":reserved.can_pause,
                "reserved":true,"stopImpact":"仅取消这个正在启动或清理的控制会话；已有其他活动保持不变。"}));
        }
        if let Some(transfers) = transfers["transfers"].as_array() {
            for transfer in transfers.iter().filter(|transfer| {
                matches!(
                    transfer["status"].as_str(),
                    Some("queued" | "running" | "finalizing" | "conflict")
                )
            }) {
                activities.push(json!({"id":format!("transfer:{}",transfer["id"].as_str().unwrap_or_default()),"deviceId":transfer["deviceId"],"deviceName":device_name(transfer["deviceId"].as_str().unwrap_or_default()),"name":transfer["name"],"status":transfer["status"],"canStop":true,"stopImpact":"仅取消这一项传输；已完成的文件不回滚，未完成内容保留为实际中断状态。"}));
            }
        }
        for observation in self.observation_list().await? {
            if observation["wanted"] == true {
                let id = observation["deviceId"].as_str().unwrap_or_default();
                activities.push(json!({"id":format!("observation:{id}"),"deviceId":id,"deviceName":device_name(id),"name":"通知与来电观察","status":observation["phase"],"canStop":true,"stopImpact":"仅停止这台设备的通知与来电观察；剪贴板和媒体处理保持运行。"}));
            }
        }
        for source in self.audio_activity_sources().await {
            let device = source["deviceId"].as_str().unwrap_or_default();
            let source_id = source["sourceId"].as_str().unwrap_or_default();
            activities.push(json!({"id":format!("audio:{source_id}"),"deviceId":device,"sourceId":source_id,
                "deviceName":device_name(device),"name":"设备声音","status":source["status"],"canStop":true,
                "stopImpact":"仅停止这台设备的这一代音源；设备连接、控制会话、通知与来电观察及其他设备音源保持运行。"}));
        }
        Ok(json!({"activities":activities,"sessions":sessions,"transfers":transfers["transfers"]}))
    }

    async fn probe_video_encoders(&self, device: &str) -> CoreResult<Vec<VideoEncoder>> {
        let client = self.client(device).await?;
        if format!("{:x}", Sha256::digest(SERVER)) != SERVER_SHA {
            return Err(CoreError::new("server_integrity", "内置控制服务校验失败。"));
        }
        let path = format!(
            "/data/local/tmp/interop-encoders-{}.jar",
            uuid::Uuid::new_v4()
        );
        let result = async {
            let operation = OperationOptions { timeout: Duration::from_secs(15), ..Default::default() };
            let mut sync = client.sync(operation.clone()).await?;
            sync.push(&RemotePath::new(&path)?, &mut &SERVER[..], 0o600,
                now().min(u32::MAX as u64) as u32, SERVER.len() as u64).await?;
            drop(sync);
            let command = format!("CLASSPATH={} app_process / com.genymobile.scrcpy.Server 5.0.1 list_encoders=true cleanup=true log_level=info", quote(&path)?);
            let output = client.shell(&command, 256 * 1024, operation).await?;
            if output.exit_code.is_some_and(|code| code != 0) {
                return Err(CoreError::new("encoder_probe", "设备编码器枚举失败；尚未确认所选格式可用。"));
            }
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            parse_encoders(&text)
        }.await;
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
            for session in self.sessions.lock().await.values() {
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
            let sessions = self.sessions.lock().await;
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
    F: FnOnce(Vec<u8>, oneshot::Sender<CoreResult<Value>>) -> ControlRequest,
{
    let (reply, receiver) = oneshot::channel();
    sender
        .send(constructor(bytes, reply))
        .await
        .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?;
    receive_reply(receiver).await
}
async fn receive_reply(receiver: oneshot::Receiver<CoreResult<Value>>) -> CoreResult<Value> {
    tokio::time::timeout(Duration::from_secs(6), receiver)
        .await
        .map_err(|_| CoreError::new("timeout", "设备未及时响应控制请求。"))?
        .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?
}
async fn clipboard_set(
    sender: &mpsc::Sender<ControlRequest>,
    text: String,
    paste: bool,
) -> CoreResult<Value> {
    let (reply, receiver) = oneshot::channel();
    sender
        .send(ControlRequest::ClipboardSet(text, paste, reply))
        .await
        .map_err(|_| CoreError::new("disconnected", "控制连接已结束。"))?;
    receive_reply(receiver).await
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
    let operation = async {
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
            video.read_exact(&mut header).await?;
            if let Some((width, height)) = session_dimensions(&header)? {
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
            let length = u32::from_be_bytes(header[8..].try_into().expect("video header")) as usize;
            if length == 0 || length > MAX_PACKET {
                return Err(CoreError::new("video_protocol", "视频数据包大小无效。"));
            }
            let mut bytes = vec![0; length];
            video.read_exact(&mut bytes).await?;
            {
                let data = state.read().await;
                if data["status"] == "paused" || data["awaitingSession"] == true {
                    continue;
                }
            }
            output.write_all(&header).await?;
            output.write_all(&bytes).await?;
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
    let mut gets: VecDeque<oneshot::Sender<CoreResult<Value>>> = VecDeque::new();
    let mut sets: HashMap<u64, oneshot::Sender<CoreResult<Value>>> = HashMap::new();
    let mut captures: HashMap<u64, (bool, oneshot::Sender<CoreResult<Value>>)> = HashMap::new();
    let mut sequence = 1u64;
    loop {
        tokio::select! {
            _ = cancellation.cancelled() => break,
            request = requests.recv() => {
                let Some(request) = request else { break; };
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
                            result = stream.write_all(&bytes) => result.map_err(CoreError::from),
                        };
                        let abort = result.is_err() || permit.is_cancelled();
                        permit.complete();
                        let _ = reply.send(result.map(|()| json!({"sent":true})));
                        if abort { break; }
                        continue;
                    }
                    ControlRequest::Send(bytes, reply) => (bytes, Some(reply)),
                    ControlRequest::ClipboardGet(reply) => { gets.retain(|reply| !reply.is_closed()); if gets.len() >= 16 { let _ = reply.send(Err(CoreError::new("busy","剪贴板请求较多，请稍后重试。"))); continue; } gets.push_back(reply); (vec![8,0], None) },
                    ControlRequest::Capture(paused, reply) => {
                        captures.retain(|_, (_, reply)| !reply.is_closed());
                        if captures.len() >= 8 {
                            let _ = reply.send(Err(CoreError::new("busy", "捕获状态请求较多，请稍后重试。")));
                            continue;
                        }
                        sequence = sequence.wrapping_add(1).max(1);
                        let mut bytes = vec![128];
                        bytes.extend_from_slice(&sequence.to_be_bytes());
                        bytes.push(u8::from(paused));
                        captures.insert(sequence, (paused, reply));
                        (bytes, None)
                    }
                    ControlRequest::ClipboardSet(text, paste, reply) => {
                        sets.retain(|_,reply| !reply.is_closed()); if sets.len() >= 16 { let _ = reply.send(Err(CoreError::new("busy","剪贴板请求较多，请稍后重试。"))); continue; }
                        sequence = sequence.wrapping_add(1).max(1); let mut bytes = vec![9]; bytes.extend_from_slice(&sequence.to_be_bytes()); bytes.push(u8::from(paste)); bytes.extend_from_slice(&(text.len() as u32).to_be_bytes()); bytes.extend_from_slice(text.as_bytes()); sets.insert(sequence,reply); (bytes,None)
                    }
                };
                let result = stream.write_all(&bytes).await.map_err(CoreError::from);
                if let Some(reply) = immediate { let _ = reply.send(result.map(|()| json!({"sent":true}))); }
                else if result.is_err() { break; }
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
                        if let Some(reply) = gets.pop_front() { let _ = reply.send(Ok(json!({"text":text}))); }
                        event(&events,"clipboard.changed",&device,json!({"text":text,"sessionId":state.read().await["sessionId"]}));
                    } else if incoming[0] == 1 {
                        let sequence = u64::from_be_bytes(incoming[1..9].try_into().expect("control sequence"));
                        if let Some(reply) = sets.remove(&sequence) { let _ = reply.send(Ok(json!({"applied":true}))); }
                        else if let Some((paused, reply)) = captures.remove(&sequence) {
                            let _ = reply.send(Ok(json!({"capturePaused":paused,"confirmed":true})));
                        }
                    }
                    incoming.drain(..needed);
                }
            }
        }
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
    async fn renderer_ready_preserves_capture_pause_after_generation_replacement() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let cancellation = CancellationToken::new();
        let _reservation = runtime
            .resource_admission
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
        let (control, _requests) = mpsc::channel(1);
        // The ready boundary only consumes renderer evidence: no device or
        // remote process is started by this fixture.
        runtime.sessions.lock().await.insert(
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
            runtime.resource_admission.activities()[0].status,
            ResourceStatus::Streaming
        );

        // The capture ACK arrives before a pending generation's ready receipt.
        {
            let mut snapshot = state.write().await;
            snapshot["status"] = json!("paused");
            snapshot["capturePaused"] = json!(true);
            snapshot["captureStateConfirmed"] = json!(true);
        }
        runtime
            .resource_admission
            .set_status("session:fixture", ResourceStatus::Paused);
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
        assert_eq!(delayed["capturePaused"], true);
        assert_eq!(delayed["captureStateConfirmed"], true);
        let activity = &runtime.resource_admission.activities()[0];
        assert_eq!(activity.status, ResourceStatus::Paused);
        assert!(activity.can_resume);
        assert!(!activity.can_pause);

        // A subsequent acknowledged resume still accepts renderer updates.
        {
            let mut snapshot = state.write().await;
            snapshot["status"] = json!("streaming");
            snapshot["capturePaused"] = json!(false);
        }
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
            runtime.resource_admission.activities()[0].status,
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
                    .resource_admission
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
            runtime.sessions.lock().await[old_id].state.read().await["sessionId"],
            old_id
        );
        assert!(
            !runtime.sessions.lock().await[old_id]
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
        let reserved = runtime.resource_admission.activities();
        assert_eq!(reserved.len(), 1);
        assert_eq!(reserved[0].id, format!("session:{old_id}"));
        assert!(
            !runtime.sessions.lock().await[old_id]
                .cancellation
                .is_cancelled()
        );
        drop(socket);
        runtime.stop_session(old_id).await;
        tokio::time::timeout(Duration::from_secs(5), async {
            while !runtime.resource_admission.activities().is_empty() {
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
    fn process_stat_uses_starttime_after_the_parenthesized_command() {
        let mut fields = vec!["0"; 20];
        fields[0] = "T";
        fields[19] = "12345";
        let stat = format!("99 (name with ) parens) {}", fields.join(" "));
        assert_eq!(process_stat(stat.as_bytes()).unwrap(), ('T', 12345));
        assert!(process_stat(b"99 invalid").is_err());
    }

    #[tokio::test]
    #[ignore = "requires real Android adbd; pauses only this test-owned capture process"]
    async fn real_capture_process_stops_resumes_and_unfreezes_on_socket_close() {
        use std::sync::atomic::AtomicU64;
        let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
        let port: u16 = std::env::var("INTEROP_ADBD_PORT")
            .expect("set INTEROP_ADBD_PORT")
            .parse()
            .unwrap();
        let root = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(root.path()).await.unwrap();
        let device = runtime
            .invoke("devices.add", json!({"address":address,"port":port}))
            .await
            .unwrap();
        let id = device["deviceId"].as_str().unwrap();
        runtime
            .invoke("devices.connect", json!({"deviceId":id}))
            .await
            .unwrap();
        let session = runtime
            .start_session(&json!({"deviceId":id}))
            .await
            .unwrap();
        let session_id = session["sessionId"].as_str().unwrap();
        let (process, state, control) = {
            let sessions = runtime.sessions.lock().await;
            let session = &sessions[session_id];
            (
                session.process.clone().expect("started capture process"),
                session.state.clone(),
                session.control.clone(),
            )
        };
        let client = runtime.client(id).await.unwrap();
        let mut socket = tokio::net::TcpStream::connect((
            "127.0.0.1",
            session["videoPort"].as_u64().unwrap() as u16,
        ))
        .await
        .unwrap();
        socket
            .write_all(session["videoToken"].as_str().unwrap().as_bytes())
            .await
            .unwrap();
        socket.write_all(b"\n").await.unwrap();
        let count = Arc::new(AtomicU64::new(0));
        let reader_count = count.clone();
        let reader = tokio::spawn(async move {
            loop {
                let mut header = [0; 12];
                if socket.read_exact(&mut header).await.is_err() {
                    break;
                }
                if header[0] & 0x80 != 0 {
                    continue;
                }
                let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
                assert!(length <= MAX_PACKET);
                let mut bytes = vec![0; length];
                if socket.read_exact(&mut bytes).await.is_err() {
                    break;
                }
                reader_count.fetch_add(1, Ordering::SeqCst);
            }
        });
        tokio::time::timeout(Duration::from_secs(5), async {
            while count.load(Ordering::SeqCst) < 2 {
                tokio::time::sleep(Duration::from_millis(10)).await
            }
        })
        .await
        .unwrap();
        // The process identity mismatch must not signal even this owned server.
        let mut mismatched = process.clone();
        mismatched.started += 1;
        assert!(mismatched.signal(&client, true).await.is_err());
        process.signal(&client, true).await.unwrap();
        let stat = client
            .shell(
                &format!("cat /proc/{}/stat", process.pid),
                4096,
                OperationOptions::default(),
            )
            .await
            .unwrap();
        assert_eq!(process_stat(&stat.stdout).unwrap().0, 'T');
        tokio::time::sleep(Duration::from_millis(250)).await;
        let frozen = count.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(500)).await;
        assert_eq!(
            count.load(Ordering::SeqCst),
            frozen,
            "frames continued after capture process stopped"
        );
        process.signal(&client, false).await.unwrap();
        state.write().await["awaitingSession"] = json!(true);
        request_control(&control, ControlRequest::Send, vec![17])
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(5), async {
            while count.load(Ordering::SeqCst) <= frozen {
                tokio::time::sleep(Duration::from_millis(10)).await
            }
        })
        .await
        .unwrap();
        process.signal(&client, true).await.unwrap();
        // Close the actual transport while the child is stopped. The remote
        // launcher must observe stdin EOF and resume it for normal socket cleanup.
        client.close();
        reader.abort();
        let inspection =
            interop_adb::Client::connect_tcp((address.as_str(), port), Default::default())
                .await
                .unwrap();
        tokio::time::timeout(Duration::from_secs(8), async {
            loop {
                let stat = inspection
                    .shell(
                        &format!("cat /proc/{}/stat", process.pid),
                        4096,
                        OperationOptions::default(),
                    )
                    .await
                    .unwrap();
                if let Ok((process_state, started)) = process_stat(&stat.stdout) {
                    if started != process.started || !matches!(process_state, 'T' | 't') {
                        break;
                    }
                } else {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(50)).await
            }
        })
        .await
        .expect("capture was stranded stopped after disconnect");
        tokio::time::timeout(Duration::from_secs(8), async {
            loop {
                let stat = inspection
                    .shell(
                        &format!("cat /proc/{}/stat", process.pid),
                        4096,
                        OperationOptions::default(),
                    )
                    .await
                    .unwrap();
                if process_stat(&stat.stdout).map_or(true, |(state, started)| {
                    started != process.started || state == 'Z'
                }) {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        })
        .await
        .expect("test-owned capture process did not finish normal socket cleanup");
        runtime.stop_session(session_id).await;
        inspection.close();
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
