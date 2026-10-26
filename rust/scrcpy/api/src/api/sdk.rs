//! 独立 SDK 捕获的所有者；连接、服务器输入和事件均由当前宿主显式提供。
use super::{
    ScrcpyEvent, ScrcpyEventKind, ScrcpyNativeSource, ScrcpyProcessInfo, ScrcpySessionInfo,
    ScrcpySourceKind, ScrcpySourceState, ScrcpySourceStatus, ScrcpyVideoCodec,
};
use interop_adb::{CancellationToken, Client, OperationOptions};
use interop_scrcpy::{
    config::Options,
    control::{Channel, Completion, DeviceMessage, Message},
    process_identity::ProcessLaunchState,
    session::Session,
};
use interop_scrcpy::{
    control::ControlCompletion,
    media::native::{MediaSource, MediaStreams},
};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

mod media;
#[cfg(test)]
mod startup_tests;

fn server_bytes() -> &'static OnceLock<Arc<[u8]>> {
    static SERVER: OnceLock<Arc<[u8]>> = OnceLock::new();
    &SERVER
}
/// 服务器由宿主提供；捕获保留自己的不可变快照，不从应用路径隐式加载。
#[flutter_rust_bridge::frb(ignore)]
pub fn initialize_sdk(bytes: Vec<u8>) -> Result<(), String> {
    if bytes.is_empty() || bytes.len() > 64 * 1024 * 1024 {
        return Err("invalid_argument: 服务器字节为空或超过限额。".into());
    }
    let bytes: Arc<[u8]> = bytes.into();
    let actual = server_bytes().get_or_init(|| bytes.clone());
    if actual.as_ref() != bytes.as_ref() {
        return Err("sdk_configuration_mismatch: 本宿主已初始化不同的服务器字节。".into());
    }
    Ok(())
}

#[derive(Default)]
struct EventState {
    clipboard: Option<String>,
    stopped: bool,
    delivered_terminal: bool,
    cancelled: bool,
}
#[derive(Default)]
struct EventQueue {
    state: Mutex<EventState>,
    changed: tokio::sync::Notify,
}
impl EventQueue {
    fn clipboard(&self, text: String) {
        let mut state = self.state.lock().expect("SDK 事件状态");
        if !state.stopped && !state.cancelled {
            state.clipboard = Some(text);
            self.changed.notify_waiters();
        }
    }
    fn finish(&self) {
        self.state.lock().expect("SDK 事件状态").stopped = true;
        self.changed.notify_waiters();
    }
    fn cancel(&self) {
        let mut state = self.state.lock().expect("SDK 事件状态");
        state.cancelled = true;
        state.clipboard = None;
        self.changed.notify_waiters();
    }
    async fn next(&self, id: &str) -> Option<ScrcpyEvent> {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let mut state = self.state.lock().expect("SDK 事件状态");
                if state.cancelled {
                    return None;
                }
                if let Some(text) = state.clipboard.take() {
                    return Some(ScrcpyEvent {
                        kind: ScrcpyEventKind::ClipboardChanged,
                        capture_ref: id.into(),
                        text: Some(text),
                        reason: None,
                    });
                }
                if state.stopped {
                    if state.delivered_terminal {
                        return None;
                    }
                    state.delivered_terminal = true;
                    return Some(ScrcpyEvent {
                        kind: ScrcpyEventKind::Stopped,
                        capture_ref: id.into(),
                        text: None,
                        reason: None,
                    });
                }
            }
            changed.await;
        }
    }
}
#[derive(Default)]
struct HubState {
    clipboard: Option<String>,
    stopped: bool,
    observers: HashMap<String, std::sync::Weak<EventQueue>>,
}
#[derive(Default)]
struct EventHub {
    state: Mutex<HubState>,
}
impl EventHub {
    fn clipboard(&self, text: String) {
        let mut state = self.state.lock().expect("SDK 事件来源");
        if state.stopped {
            return;
        }
        state.clipboard = Some(text.clone());
        state.observers.retain(|_, queue| {
            if let Some(queue) = queue.upgrade() {
                queue.clipboard(text.clone());
                true
            } else {
                false
            }
        });
    }
    fn finish(&self) {
        let mut state = self.state.lock().expect("SDK 事件来源");
        state.stopped = true;
        state.observers.retain(|_, queue| {
            if let Some(queue) = queue.upgrade() {
                queue.finish();
                true
            } else {
                false
            }
        });
    }
}
struct Observer {
    capture_ref: String,
    queue: Arc<EventQueue>,
}
fn observers() -> &'static Mutex<HashMap<String, Observer>> {
    static OBSERVERS: OnceLock<Mutex<HashMap<String, Observer>>> = OnceLock::new();
    OBSERVERS.get_or_init(Mutex::default)
}
struct EventEntry {
    created: std::time::Instant,
    hub: Arc<EventHub>,
}
fn event_registry() -> &'static Mutex<HashMap<String, EventEntry>> {
    static EVENTS: OnceLock<Mutex<HashMap<String, EventEntry>>> = OnceLock::new();
    EVENTS.get_or_init(Mutex::default)
}
fn register_events(id: &str, hub: Arc<EventHub>) {
    let mut entries = event_registry().lock().expect("SDK 事件登记表");
    // 活跃捕获最多 32 个，其余 32 个位置留给已结束但尚未读取的终态。
    while entries.len() >= 64 {
        let oldest = entries
            .iter()
            .filter(|(_, entry)| entry.hub.state.lock().expect("SDK 事件来源").stopped)
            .min_by_key(|(_, entry)| entry.created)
            .map(|(id, _)| id.clone());
        if let Some(oldest) = oldest {
            entries.remove(&oldest);
        } else {
            break;
        }
    }
    entries.insert(
        id.into(),
        EventEntry {
            created: std::time::Instant::now(),
            hub,
        },
    );
}
#[flutter_rust_bridge::frb(ignore)]
pub fn open_events(capture_ref: &str) -> Result<String, String> {
    let hub = event_registry()
        .lock()
        .expect("SDK 事件登记表")
        .get(capture_ref)
        .map(|entry| entry.hub.clone())
        .ok_or_else(|| "stale_capture: 捕获事件已回收。".to_owned())?;
    let mut state = hub.state.lock().expect("SDK 事件来源");
    let queue = Arc::new(EventQueue::default());
    if let Some(text) = &state.clipboard {
        queue.clipboard(text.clone());
    }
    if state.stopped {
        queue.finish();
    }
    let id = uuid::Uuid::new_v4().to_string();
    let mut observers = observers().lock().expect("SDK 观察者登记表");
    if observers.len() >= 128 {
        return Err("resource_busy: SDK 观察者数量已达上限。".into());
    }
    state.observers.retain(|_, queue| queue.strong_count() != 0);
    state.observers.insert(id.clone(), Arc::downgrade(&queue));
    observers.insert(
        id.clone(),
        Observer {
            capture_ref: capture_ref.into(),
            queue,
        },
    );
    Ok(id)
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn next_event(id: &str) -> Result<Option<ScrcpyEvent>, String> {
    let observer = observers()
        .lock()
        .expect("SDK 观察者登记表")
        .get(id)
        .map(|entry| (entry.capture_ref.clone(), entry.queue.clone()));
    let Some((capture_ref, queue)) = observer else {
        return Ok(None);
    };
    let event = queue.next(&capture_ref).await;
    if event.is_none() {
        cancel_events(id);
    }
    Ok(event)
}
#[flutter_rust_bridge::frb(ignore)]
pub fn cancel_events(id: &str) {
    if let Some(observer) = observers().lock().expect("SDK 观察者登记表").remove(id) {
        observer.queue.cancel();
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Created,
    Starting,
    ControlReady,
    Running,
    Stopped,
}
struct Capture {
    id: String,
    server: Arc<[u8]>,
    events: Arc<EventHub>,
    created: std::time::Instant,
    connection_owner: String,
    client: Client,
    options: Options,
    cancellation: CancellationToken,
    phase: Mutex<Phase>,
    startup_finished: CancellationToken,
    process_finished: CancellationToken,
    has_process: AtomicBool,
    has_video: AtomicBool,
    has_audio: AtomicBool,
    audio_finished: CancellationToken,
    media_requested: CancellationToken,
    media_ready: CancellationToken,
    media_error: Mutex<Option<String>>,
    process_info: Mutex<Option<ScrcpyProcessInfo>>,
    process_launch: Mutex<Option<ProcessLaunchState>>,
    audio_source: Mutex<Option<Arc<MediaSource>>>,
    video_finished: CancellationToken,
    finished: CancellationToken,
    control: Mutex<Option<Channel>>,
    clipboard_read: tokio::sync::Mutex<()>,
    source: Mutex<Option<Arc<MediaSource>>>,
    info: Mutex<Option<ScrcpySessionInfo>>,
    cleanup_error: Mutex<Option<String>>,
    cleanup_retry: tokio::sync::Mutex<()>,
}
fn registry() -> &'static Mutex<HashMap<String, Arc<Capture>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<String, Arc<Capture>>>> = OnceLock::new();
    REGISTRY.get_or_init(Mutex::default)
}
fn lookup(id: &str) -> Result<Arc<Capture>, String> {
    registry()
        .lock()
        .expect("SDK 捕获登记表")
        .get(id)
        .cloned()
        .ok_or_else(|| "stale_capture: 捕获已结束。".into())
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn create(connection: &str, options: Options) -> Result<String, String> {
    options.validate().map_err(|error| error.to_string())?;
    let server = server_bytes()
        .get()
        .cloned()
        .ok_or_else(|| "sdk_uninitialized: 尚未提供 scrcpy 服务器字节。".to_owned())?;
    let id = format!("sdk:{}", uuid::Uuid::new_v4());
    let events = Arc::new(EventHub::default());
    // ADB 准入与捕获登记共用一次短临界区；旧句柄不能跨认领完成后才登记捕获。
    let capture =
        interop_adb_api::api::admit_capture(connection, |client, cancellation, owner| {
            let capture = Arc::new(Capture {
                id: id.clone(),
                server,
                events: events.clone(),
                created: std::time::Instant::now(),
                connection_owner: owner,
                client,
                options,
                cancellation,
                phase: Mutex::new(Phase::Created),
                startup_finished: CancellationToken::new(),
                process_finished: CancellationToken::new(),
                has_process: AtomicBool::new(false),
                has_video: AtomicBool::new(false),
                has_audio: AtomicBool::new(false),
                audio_finished: CancellationToken::new(),
                media_requested: CancellationToken::new(),
                media_ready: CancellationToken::new(),
                media_error: Mutex::default(),
                process_info: Mutex::default(),
                process_launch: Mutex::default(),
                audio_source: Mutex::default(),
                video_finished: CancellationToken::new(),
                finished: CancellationToken::new(),
                control: Mutex::default(),
                clipboard_read: tokio::sync::Mutex::new(()),
                source: Mutex::default(),
                info: Mutex::default(),
                cleanup_error: Mutex::default(),
                cleanup_retry: tokio::sync::Mutex::new(()),
            });
            {
                let mut registry = registry().lock().expect("SDK 捕获登记表");
                if registry
                    .values()
                    .filter(|capture| !capture.finished.is_cancelled())
                    .count()
                    >= 32
                {
                    return Err("resource_busy: SDK 捕获数量已达上限。".into());
                }
                // 未确认清理仍拥有资源，不能当作诊断淘汰；容量耗尽时拒绝新捕获。
                while registry.len() >= 64 {
                    let oldest = registry
                        .iter()
                        .filter(|(_, capture)| {
                            capture.finished.is_cancelled()
                                && capture
                                    .cleanup_error
                                    .lock()
                                    .expect("SDK 清理结果")
                                    .is_none()
                        })
                        .min_by_key(|(_, capture)| capture.created)
                        .map(|(id, _)| id.clone());
                    if let Some(oldest) = oldest {
                        registry.remove(&oldest);
                    } else {
                        return Err("resource_busy: SDK 清理仍在进行。".into());
                    }
                }
                registry.insert(id.clone(), capture.clone());
            }
            Ok(capture)
        })?;
    register_events(&id, events);
    tokio::spawn(cleanup(capture));
    Ok(id)
}

fn jar(capture: &Capture) -> String {
    format!(
        "/data/local/tmp/scrcpy-sdk-{}.jar",
        capture.id.trim_start_matches("sdk:")
    )
}

async fn cleanup(capture: Arc<Capture>) {
    let _finished = capture.finished.clone().drop_guard();
    capture.cancellation.cancelled().await;
    let remote_started = {
        let mut phase = capture.phase.lock().expect("SDK 捕获状态");
        let remote_started = *phase != Phase::Created;
        if !remote_started {
            capture.startup_finished.cancel();
        }
        *phase = Phase::Stopped;
        remote_started
    };
    capture.startup_finished.cancelled().await;
    if capture.has_process.load(Ordering::Acquire) {
        capture.process_finished.cancelled().await;
    }
    let control = capture.control.lock().expect("SDK 控制器").take();
    if let Some(control) = control {
        control.close().await;
    }
    if capture.has_video.load(Ordering::Acquire) {
        capture.video_finished.cancelled().await;
    }
    if capture.has_audio.load(Ordering::Acquire) {
        capture.audio_finished.cancelled().await;
    }
    if let Some(source) = capture.audio_source.lock().expect("SDK 音频来源").take() {
        source.finish();
    }
    capture.media_ready.cancel();
    if let Some(source) = capture.source.lock().expect("SDK 来源").take() {
        source.finish();
    }
    let result = if remote_started {
        cleanup_remote(&capture).await
    } else {
        Ok(())
    };
    let succeeded = result.is_ok();
    if let Err(error) = result {
        *capture.cleanup_error.lock().expect("SDK 清理结果") = Some(error);
    }
    capture.events.finish();
    if succeeded {
        registry()
            .lock()
            .expect("SDK 捕获登记表")
            .remove(&capture.id);
    }
}

async fn cleanup_remote(capture: &Capture) -> Result<(), String> {
    let options = OperationOptions {
        timeout: Duration::from_secs(3),
        ..Default::default()
    };
    let result = async {
        let launch = capture
            .process_launch
            .lock()
            .expect("SDK 进程启动责任")
            .clone();
        if let Some(launch) = launch {
            // 本机日志任务结束只确认流已释放；远端须有本次监督终态或精确内核退出证明。
            // START 后身份与终态都未知时保留原捕获，不能通过删除 JAR 冒充回收。
            launch
                .wait_exited(&capture.client)
                .await
                .map_err(|error| error.to_string())?;
        }
        capture
            .client
            .flush_closed_streams(options.clone())
            .await
            .map_err(|error| error.to_string())?;
        let receipt = format!("__INTEROP_REMOVED__{}", uuid::Uuid::new_v4().simple());
        let command = format!(
            "rm -f -- {} && print -r -- {receipt}",
            interop_scrcpy::shell_quote(&jar(capture)).map_err(|error| error.to_string())?
        );
        let result = capture
            .client
            .shell(&command, 4096, options)
            .await
            .map_err(|error| error.to_string())?;
        // 旧 shell 没有退出码；EOF 只代表服务结束，须有当次完整成功回执。
        let legacy_confirmed = result.stdout == format!("{receipt}\n").as_bytes()
            || result.stdout == format!("{receipt}\r\n").as_bytes();
        if result.exit_code.is_some_and(|code| code != 0)
            || (result.exit_code.is_none() && !legacy_confirmed)
        {
            return Err("远端未确认文件移除。".into());
        }
        Ok::<_, String>(())
    }
    .await;
    result.map_err(|error| format!("capture_cleanup_unverified: {error}"))
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn start(id: &str) -> Result<ScrcpySessionInfo, String> {
    let capture = lookup(id)?;
    start_control(id).await?;
    let cancel_on_failure = capture.cancellation.clone().drop_guard();
    let info = await_media(id, 1).await?;
    cancel_on_failure.disarm();
    Ok(info)
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn start_control(id: &str) -> Result<ScrcpySessionInfo, String> {
    let capture = lookup(id)?;
    {
        let mut phase = capture.phase.lock().expect("SDK 捕获状态");
        if *phase != Phase::Created || capture.cancellation.is_cancelled() {
            return Err("invalid_state: 捕获已启动或停止。".into());
        }
        *phase = Phase::Starting;
    }
    // 等待者退出只撤销本次意图；实际启动责任独立存活，身份回执前也不能丢弃监督流。
    let cancel_on_failure = capture.cancellation.clone().drop_guard();
    let worker = tokio::spawn({
        let capture = capture.clone();
        async move {
            let _startup_finished = capture.startup_finished.clone().drop_guard();
            let cancel_on_failure = capture.cancellation.clone().drop_guard();
            let result = start_inner(capture).await;
            if result.is_ok() {
                cancel_on_failure.disarm();
            }
            result
        }
    });
    let result = worker
        .await
        .map_err(|error| format!("capture_start_failed: {error}"))?;
    if result.is_ok() {
        cancel_on_failure.disarm();
    }
    result
}

async fn start_inner(capture: Arc<Capture>) -> Result<ScrcpySessionInfo, String> {
    let scid = u32::from_be_bytes(
        uuid::Uuid::new_v4().as_bytes()[..4]
            .try_into()
            .expect("UUID"),
    ) & 0x7fff_ffff;
    let session = Session::new(
        capture.client.clone(),
        scid,
        capture.options.clone(),
        capture.cancellation.clone(),
    )
    .map_err(|error| error.to_string())?;
    *capture.process_launch.lock().expect("SDK 进程启动责任") = Some(session.launch_state());
    let launched = session
        .launch(&jar(&capture), &capture.server)
        .await
        .map_err(|error| error.to_string())?;
    let interop_scrcpy::session::Launched {
        session,
        mut process,
        pid,
        started,
    } = launched;
    *capture.process_info.lock().expect("SDK 进程事实") = Some(ScrcpyProcessInfo {
        pid,
        started,
        log_tail: Vec::new(),
        truncated: false,
    });
    capture.has_process.store(true, Ordering::Release);
    tokio::spawn({
        let capture = capture.clone();
        async move {
            let _finished = capture.process_finished.clone().drop_guard();
            let mut bytes = [0; 4096];
            loop {
                // ManagedProcess 在取消时发送 STOP 并继续收取精确监督终态，不直接丢弃读取。
                let result = process.read(&mut bytes).await;
                let Ok(count) = result else { break };
                if count == 0 {
                    break;
                }
                let mut info = capture.process_info.lock().expect("SDK 进程事实");
                if let Some(info) = info.as_mut() {
                    // 原生日志为固定空间的事实尾部，不将解析规则或产品状态放入 SDK。
                    const MAX_LOG_BYTES: usize = 64 * 1024;
                    info.log_tail.extend_from_slice(&bytes[..count]);
                    if info.log_tail.len() > MAX_LOG_BYTES {
                        let remove = info.log_tail.len() - MAX_LOG_BYTES;
                        info.log_tail.drain(..remove);
                        info.truncated = true;
                    }
                }
            }
            drop(process);
            capture.cancellation.cancel();
        }
    });
    let interop_scrcpy::session::ConnectedChannels {
        video,
        audio,
        control,
        device_name,
        video_initial,
    } = session
        .connect_channels()
        .await
        .map_err(|error| error.to_string())?;
    if let Some(control) = control {
        let channel = Channel::start(control, capture.cancellation.clone())
            .map_err(|error| error.to_string())?;
        let mut events = channel.subscribe();
        *capture.control.lock().expect("SDK 控制器") = Some(channel);
        tokio::spawn({
            let capture = capture.clone();
            async move {
                loop {
                    let event = tokio::select! {_=capture.cancellation.cancelled()=>break,event=events.recv()=>event};
                    match event {
                        Ok(DeviceMessage::Clipboard(text)) => {
                            capture.events.clipboard(text);
                        }
                        Ok(_) => {}
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(_) => break,
                    }
                }
            }
        });
    }
    let (width, height) = match video_initial {
        Some(initial) => interop_scrcpy::capture::session_dimensions(&initial)
            .map_err(|error| error.to_string())?
            .expect("通道已验证尺寸"),
        None => (0, 0),
    };
    if let Some(audio) = audio {
        let source = register_source(
            &capture,
            interop_scrcpy::media::native::CODEC_PCM_S16LE,
            0,
            0,
        )?;
        *capture.audio_source.lock().expect("SDK 音频来源") = Some(source.clone());
        capture.has_audio.store(true, Ordering::Release);
        tokio::spawn(media::forward_audio(capture.clone(), source, audio));
    }
    let info = ScrcpySessionInfo {
        id: capture.id.clone(),
        device_name,
        video_codec: match capture.options.codec {
            interop_scrcpy::config::VideoCodec::H264 => ScrcpyVideoCodec::H264,
            interop_scrcpy::config::VideoCodec::H265 => ScrcpyVideoCodec::H265,
            interop_scrcpy::config::VideoCodec::Av1 => ScrcpyVideoCodec::Av1,
            interop_scrcpy::config::VideoCodec::Vp8 => ScrcpyVideoCodec::Vp8,
            interop_scrcpy::config::VideoCodec::Vp9 => ScrcpyVideoCodec::Vp9,
        },
        width,
        height,
        source: None,
        audio_source: None,
        video_enabled: capture.options.video,
        audio_enabled: capture.options.audio,
        control_ready: capture.control.lock().expect("SDK 控制器").is_some(),
        media_ready: video.is_none(),
        process_id: Some(pid),
        process_started: Some(started),
    };
    {
        let mut phase = capture.phase.lock().expect("SDK 捕获状态");
        if *phase != Phase::Starting || capture.cancellation.is_cancelled() {
            return Err("cancelled: 捕获已停止。".into());
        }
        *phase = if video.is_some() {
            Phase::ControlReady
        } else {
            Phase::Running
        };
        *capture.info.lock().expect("SDK 元数据") = Some(info);
    }
    if let Some(video) = video {
        capture.has_video.store(true, Ordering::Release);
        tokio::spawn(media::prepare_video(
            capture.clone(),
            video,
            video_initial.expect("视频初始尺寸"),
        ));
    } else {
        capture.media_ready.cancel();
    }
    inspect(&capture.id, 1).await
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn inspect(id: &str, generation: u64) -> Result<ScrcpySessionInfo, String> {
    let capture = lookup(id)?;
    if capture.cancellation.is_cancelled() {
        return Err("stale_capture: 捕获已结束。".into());
    }
    let mut info = capture
        .info
        .lock()
        .expect("SDK 元数据")
        .clone()
        .ok_or_else(|| "invalid_state: 捕获尚未就绪。".to_owned())?;
    if let Some(source) = capture.source.lock().expect("SDK 来源").as_ref() {
        let endpoint = source_endpoint(source, generation)?;
        info.width = endpoint.width;
        info.height = endpoint.height;
        info.source = Some(endpoint);
    }
    if let Some(source) = capture.audio_source.lock().expect("SDK 音频来源").as_ref() {
        info.audio_source = Some(source_endpoint(source, generation)?);
    }
    Ok(info)
}

/// 当前操作句柄与来源归属在同一连接准入锁内核验，不能跨认领复用旧权限。
#[flutter_rust_bridge::frb(ignore)]
pub fn source_status(
    connection: &str,
    id: &str,
    source_id: &str,
) -> Result<ScrcpySourceStatus, String> {
    interop_adb_api::api::admit_capture(connection, |client, _, owner| {
        let capture = lookup(id)?;
        if capture.connection_owner != owner
            || capture.client.connection_id() != client.connection_id()
        {
            return Err("foreign_capture: 捕获不属于当前连接登记。".into());
        }
        if capture.cancellation.is_cancelled() {
            return Err("stale_capture: 捕获已结束。".into());
        }
        // 保留精确来源 Arc，避免核验后来源被释放；不允许按全局来源 ID 绕过捕获归属。
        let source = capture
            .source
            .lock()
            .expect("SDK 来源")
            .as_ref()
            .filter(|source| source.id() == source_id)
            .cloned()
            .or_else(|| {
                capture
                    .audio_source
                    .lock()
                    .expect("SDK 音频来源")
                    .as_ref()
                    .filter(|source| source.id() == source_id)
                    .cloned()
            })
            .ok_or_else(|| "stale_source: 来源不属于该捕获或已释放。".to_owned())?;
        let status = MediaStreams
            .status(source.id())
            .map_err(|error| error.to_string())?;
        Ok(ScrcpySourceStatus {
            capture_ref: id.into(),
            source_id: status.source_id,
            generation: status.generation,
            kind: match status.kind.as_str() {
                "video" => ScrcpySourceKind::Video,
                "audio" => ScrcpySourceKind::Audio,
                _ => return Err("media_kind: 未知原生来源类型。".into()),
            },
            codec: status.codec,
            status: match status.status.as_str() {
                "waiting" => ScrcpySourceState::Waiting,
                "streaming" => ScrcpySourceState::Streaming,
                "closed" => ScrcpySourceState::Closed,
                _ => return Err("media_state: 未知原生来源状态。".into()),
            },
            packets: status.packets,
            bytes: status.bytes,
        })
    })
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn await_media(id: &str, generation: u64) -> Result<ScrcpySessionInfo, String> {
    let capture = lookup(id)?;
    if *capture.phase.lock().expect("SDK 捕获状态") == Phase::Created {
        return Err("invalid_state: 尚未启动捕获。".into());
    }
    // 首帧期限从调用方完成控制准备并开始等待媒体时计算，不能吞掉 START_APP 之前的准备时间。
    capture.media_requested.cancel();
    tokio::select! {
        biased;
        _ = capture.media_ready.cancelled() => {},
        _ = capture.cancellation.cancelled() => return Err("cancelled: 媒体等待已取消。".into()),
    }
    if let Some(error) = capture
        .media_error
        .lock()
        .expect("SDK 媒体启动结果")
        .clone()
    {
        return Err(error);
    }
    inspect(id, generation).await
}
#[flutter_rust_bridge::frb(ignore)]
pub fn process_info(id: &str) -> Result<ScrcpyProcessInfo, String> {
    lookup(id)?
        .process_info
        .lock()
        .expect("SDK 进程事实")
        .clone()
        .ok_or_else(|| "invalid_state: 进程尚未启动。".into())
}
fn register_source(
    capture: &Capture,
    codec: u32,
    width: u32,
    height: u32,
) -> Result<Arc<MediaSource>, String> {
    MediaSource::register(
        format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        ),
        codec,
        width,
        height,
        capture.cancellation.clone(),
    )
    .map_err(|error| error.to_string())
}
fn source_endpoint(source: &MediaSource, generation: u64) -> Result<ScrcpyNativeSource, String> {
    let endpoint = MediaStreams
        .inspect(source.id(), generation)
        .map_err(|error| error.to_string())?;
    Ok(ScrcpyNativeSource {
        source_id: endpoint.source_id,
        generation: endpoint.generation,
        codec: endpoint.codec,
        width: endpoint.width,
        height: endpoint.height,
        attach_address: endpoint.attach_address,
        detach_address: endpoint.detach_address,
    })
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn send(id: &str, message: Message) -> Result<ControlCompletion, String> {
    let capture = lookup(id)?;
    if matches!(message, Message::ResizeDisplay { .. })
        && (!capture.options.video
            || capture.options.display.is_none()
            || !capture.options.flex_display)
    {
        // 固定服务端将此消息交给 NewDisplayCapture；拒绝不支持的捕获，避免破坏控制通道。
        return Err("resize_unavailable: 当前捕获不是可调整尺寸的新显示。".into());
    }
    let channel = capture
        .control
        .lock()
        .expect("SDK 控制器")
        .clone()
        .ok_or_else(|| "control_unavailable".to_owned())?;
    let result = channel
        .send(message, Duration::from_secs(6))
        .await
        .map_err(|error| error.to_string())?;
    Ok(match result {
        Completion::Written => ControlCompletion::Written,
        Completion::ClipboardAcknowledged => ControlCompletion::ClipboardAcknowledged,
    })
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn clipboard(id: &str) -> Result<String, String> {
    let capture = lookup(id)?;
    let _read = capture.clipboard_read.lock().await;
    if capture.cancellation.is_cancelled() {
        return Err("cancelled".into());
    }
    if capture.options.clipboard_autosync {
        return Err(
            "clipboard_snapshot_unavailable: Snapshot requires clipboard_autosync=false".into(),
        );
    }
    let channel = capture
        .control
        .lock()
        .expect("SDK 控制器")
        .clone()
        .ok_or_else(|| "control_unavailable".to_owned())?;
    let mut events = channel.subscribe();
    channel
        .send(Message::GetClipboard, Duration::from_secs(6))
        .await
        .map_err(|error| error.to_string())?;
    // Upstream has no negative response for empty, non-text or denied clipboard access.
    let result = tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            tokio::select! {
                biased;
                _ = capture.cancellation.cancelled() => return Err("cancelled".into()),
                event = events.recv() => match event {
                    Ok(DeviceMessage::Clipboard(text)) => return Ok(text),
                    Ok(_) => {},
                    Err(_) => return Err("clipboard_result_unknown: Clipboard response was lost".into()),
                },
            }
        }
    }).await.unwrap_or_else(|_| Err("clipboard_result_unknown: No readable text response; empty, non-text or restricted clipboard".into()));
    if capture.cancellation.is_cancelled() {
        return Err("cancelled".into());
    }
    // GET has no correlation ID; retire uncertain streams before a late response
    // could be mistaken for the next snapshot.
    if result.is_err() {
        capture.cancellation.cancel();
    }
    result
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn stop(id: &str) -> Result<(), String> {
    let capture = lookup(id)?;
    let retry = capture.finished.is_cancelled();
    capture.cancellation.cancel();
    finish_stop(capture, retry).await
}

async fn finish_stop(capture: Arc<Capture>, retry: bool) -> Result<(), String> {
    tokio::time::timeout(Duration::from_secs(10), capture.finished.cancelled())
        .await
        .map_err(|_| "capture_cleanup_timeout".to_owned())?;
    // 精确停止和连接排空可能同时重试同一捕获，远端清理只允许一个调用执行。
    let _retry = capture.cleanup_retry.lock().await;
    let error = capture.cleanup_error.lock().expect("SDK 清理结果").clone();
    if let Some(error) = error {
        if !retry {
            return Err(error);
        }
        cleanup_remote(&capture).await?;
        *capture.cleanup_error.lock().expect("SDK 清理结果") = None;
        registry()
            .lock()
            .expect("SDK 捕获登记表")
            .remove(&capture.id);
    }
    Ok(())
}

/// 排空当前连接权限范围内已登记的捕获；不关闭连接，也不扩大到等待期间新建的捕获。
#[flutter_rust_bridge::frb(ignore)]
pub async fn drain_connection(connection: &str) -> Result<(), String> {
    let captures = interop_adb_api::api::with_connection_owner(connection, |owner| {
        let captures = registry().lock().expect("SDK 捕获登记表");
        captures
            .values()
            .filter(|capture| capture.connection_owner == owner)
            .map(|capture| {
                let retry = capture.finished.is_cancelled();
                capture.cancellation.cancel();
                (capture.clone(), retry)
            })
            .collect::<Vec<_>>()
    })
    .ok_or_else(|| "stale_connection: 连接句柄已撤销，不能排空其捕获。".to_owned())?;
    // 先在 ADB → SDK 的同一次临界区固定身份和取消范围，再锁外等待全部所有者退出。
    tokio::time::timeout(Duration::from_secs(10), async {
        let mut first_error = None;
        for (capture, retry) in captures {
            if let Err(error) = finish_stop(capture, retry).await {
                first_error.get_or_insert(error);
            }
        }
        first_error.map_or(Ok(()), Err)
    })
    .await
    .map_err(|_| "capture_cleanup_timeout: 连接捕获仍待清理，可重试排空。".to_owned())?
}

#[flutter_rust_bridge::frb(ignore)]
pub fn stop_connection(connection: &str) {
    // 与捕获准入保持 ADB → SDK 的锁序，不能把旧句柄的身份检查与取消分开。
    interop_adb_api::api::with_connection_owner(connection, |owner| {
        let captures = registry().lock().expect("SDK 捕获登记表");
        for capture in captures
            .values()
            .filter(|capture| capture.connection_owner == owner)
        {
            capture.cancellation.cancel();
        }
    });
}
#[flutter_rust_bridge::frb(ignore)]
pub async fn shutdown() {
    let captures = registry()
        .lock()
        .expect("SDK 捕获登记表")
        .values()
        .cloned()
        .collect::<Vec<_>>();
    for capture in &captures {
        capture.cancellation.cancel();
    }
    let _ = tokio::time::timeout(Duration::from_secs(10), async {
        for capture in captures {
            capture.finished.cancelled().await;
        }
    })
    .await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    async fn read(peer: &mut tokio::io::DuplexStream) -> Frame {
        tokio::time::timeout(Duration::from_secs(1), Frame::read(peer, 65536, true))
            .await
            .unwrap()
            .unwrap()
    }
    async fn shell_exit(peer: &mut tokio::io::DuplexStream, open: Frame, status: u8) {
        Frame::new(protocol::OKAY, 88, open.arg0, [])
            .write(peer)
            .await
            .unwrap();
        Frame::new(protocol::WRTE, 88, open.arg0, [3, 1, 0, 0, 0, status])
            .write(peer)
            .await
            .unwrap();
    }
    async fn next_open(peer: &mut tokio::io::DuplexStream) -> Frame {
        loop {
            let frame = read(peer).await;
            if frame.command == protocol::OPEN {
                return frame;
            }
        }
    }

    #[tokio::test]
    async fn events_keep_latest_clipboard_then_terminal_and_close_pending_reader() {
        let queue = Arc::new(EventQueue::default());
        for text in ["first", "second", "latest"] {
            queue.clipboard(text.into());
        }
        queue.finish();
        queue.clipboard("late".into());
        let clipboard = queue.next("sdk:fixture").await.unwrap();
        assert_eq!(clipboard.kind, ScrcpyEventKind::ClipboardChanged);
        assert_eq!(clipboard.text.as_deref(), Some("latest"));
        assert_eq!(
            queue.next("sdk:fixture").await.unwrap().kind,
            ScrcpyEventKind::Stopped
        );
        assert!(queue.next("sdk:fixture").await.is_none());

        let waiting = Arc::new(EventQueue::default());
        let reading = tokio::spawn({
            let waiting = waiting.clone();
            async move { waiting.next("sdk:waiting").await }
        });
        tokio::task::yield_now().await;
        waiting.finish();
        assert_eq!(
            reading.await.unwrap().unwrap().kind,
            ScrcpyEventKind::Stopped
        );
    }

    #[tokio::test]
    async fn dropping_event_read_does_not_end_capture_or_consume_future_event() {
        let queue = Arc::new(EventQueue::default());
        let reading = tokio::spawn({
            let queue = queue.clone();
            async move { queue.next("sdk:fixture").await }
        });
        tokio::task::yield_now().await;
        reading.abort();
        assert!(reading.await.unwrap_err().is_cancelled());
        assert!(!queue.state.lock().unwrap().stopped);
        queue.clipboard("after-cancel".into());
        assert_eq!(
            queue.next("sdk:fixture").await.unwrap().text.as_deref(),
            Some("after-cancel")
        );
    }

    #[tokio::test]
    async fn independent_observers_do_not_compete_and_cancel_wakes_only_one_reader() {
        let capture_ref = format!("sdk:event-test-{}", uuid::Uuid::new_v4());
        let hub = Arc::new(EventHub::default());
        register_events(&capture_ref, hub.clone());
        let first = open_events(&capture_ref).unwrap();
        let second = open_events(&capture_ref).unwrap();
        hub.clipboard("shared".into());
        assert_eq!(
            next_event(&first).await.unwrap().unwrap().text.as_deref(),
            Some("shared")
        );
        assert_eq!(
            next_event(&second).await.unwrap().unwrap().text.as_deref(),
            Some("shared")
        );
        let pending = tokio::spawn({
            let first = first.clone();
            async move { next_event(&first).await }
        });
        tokio::task::yield_now().await;
        cancel_events(&first);
        assert!(pending.await.unwrap().unwrap().is_none());
        assert!(!hub.state.lock().unwrap().stopped);
        hub.clipboard("still-live".into());
        assert_eq!(
            next_event(&second).await.unwrap().unwrap().text.as_deref(),
            Some("still-live")
        );
        hub.finish();
        assert_eq!(
            next_event(&second).await.unwrap().unwrap().kind,
            ScrcpyEventKind::Stopped
        );
        assert!(next_event(&second).await.unwrap().is_none());
        event_registry().lock().unwrap().remove(&capture_ref);
    }

    #[tokio::test]
    async fn source_status_reports_sink_acceptance_and_fences_claims_and_foreign_sources() {
        use interop_scrcpy::media::native::{
            CODEC_PCM_S16LE, EVENT_PACKET, MediaSinkV1, interop_media_attach,
        };
        use std::{ffi::c_void, sync::atomic::AtomicUsize};

        unsafe extern "C" fn receive(
            context: *mut c_void,
            event: u32,
            _: u64,
            _: u32,
            _: u32,
            _: u32,
            _: *const u8,
            _: usize,
            _: i64,
            _: u32,
        ) -> i32 {
            if event == EVENT_PACKET
                && unsafe { &*context.cast::<AtomicUsize>() }.fetch_add(1, Ordering::SeqCst) == 0
            {
                return 1;
            }
            0
        }

        initialize_sdk(vec![1, 2, 3]).unwrap();
        let (transport, peer) = tokio::io::duplex(256 * 1024);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 65536,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        let owner =
            interop_adb_api::api::insert_connection(client.clone(), "status".into(), true).unwrap();
        let independent =
            interop_adb_api::api::insert_connection(client.clone(), "status".into(), false)
                .unwrap();
        let id = create(&owner.id, Options::default()).await.unwrap();
        let other_id = create(&owner.id, Options::default()).await.unwrap();
        let capture = lookup(&id).unwrap();
        let other = lookup(&other_id).unwrap();
        let video = register_source(&capture, 1, 640, 480).unwrap();
        let audio = register_source(&capture, CODEC_PCM_S16LE, 48_000, 2).unwrap();
        let other_video = register_source(&other, 1, 320, 240).unwrap();
        *capture.source.lock().unwrap() = Some(video.clone());
        *capture.audio_source.lock().unwrap() = Some(audio.clone());
        *other.source.lock().unwrap() = Some(other_video.clone());

        let waiting = source_status(&owner.id, &id, video.id()).unwrap();
        assert_eq!(waiting.status, ScrcpySourceState::Waiting);
        assert_eq!(waiting.generation, 0);
        assert_eq!((waiting.packets, waiting.bytes), (0, 0));
        assert_eq!(waiting.kind, ScrcpySourceKind::Video);
        assert_eq!(waiting.codec, "h264");
        assert_eq!(waiting.capture_ref, id);
        assert_eq!(waiting.source_id, video.id());
        let pcm = source_status(&owner.id, &id, audio.id()).unwrap();
        assert_eq!(pcm.kind, ScrcpySourceKind::Audio);
        assert_eq!(pcm.codec, "pcm_s16le");
        assert!(
            source_status(&owner.id, &id, other_video.id())
                .unwrap_err()
                .contains("stale_source")
        );
        assert!(
            source_status(&owner.id, &other_id, video.id())
                .unwrap_err()
                .contains("stale_source")
        );
        assert!(
            source_status(&owner.id, &id, "missing")
                .unwrap_err()
                .contains("stale_source")
        );
        assert!(
            source_status(&independent.id, &id, video.id())
                .unwrap_err()
                .contains("foreign_capture")
        );

        let attempts = AtomicUsize::new(0);
        let sink = MediaSinkV1 {
            abi_version: 1,
            struct_size: std::mem::size_of::<MediaSinkV1>() as u32,
            context: (&attempts as *const AtomicUsize).cast_mut().cast(),
            event: Some(receive),
        };
        // 使用真实 ABI sink；首次背压后的重试只能累计一次接纳。
        assert_eq!(
            unsafe { interop_media_attach(video.id().as_ptr(), video.id().len(), 17, &sink) },
            0
        );
        video.packet(b"accepted-packet", 1234, true).await.unwrap();
        let streaming = source_status(&owner.id, &id, video.id()).unwrap();
        assert_eq!(streaming.status, ScrcpySourceState::Streaming);
        assert_eq!(streaming.generation, 17);
        assert_eq!((streaming.packets, streaming.bytes), (1, 15));
        assert_eq!(attempts.load(Ordering::SeqCst), 2);

        let claimed = interop_adb_api::api::adb_claim_connection(owner.id.clone())
            .await
            .unwrap();
        assert!(source_status(&owner.id, &id, video.id()).is_err());
        assert_eq!(
            source_status(&claimed.id, &id, video.id()).unwrap().packets,
            1
        );
        video.finish();
        let closed = source_status(&claimed.id, &id, video.id()).unwrap();
        assert_eq!(closed.status, ScrcpySourceState::Closed);
        assert_eq!((closed.packets, closed.bytes), (1, 15));
        capture.source.lock().unwrap().take();
        assert!(
            source_status(&claimed.id, &id, video.id())
                .unwrap_err()
                .contains("stale_source")
        );
        capture.cancellation.cancel();
        assert!(
            source_status(&claimed.id, &id, audio.id())
                .unwrap_err()
                .contains("stale_capture")
        );
        stop(&id).await.unwrap();
        stop(&other_id).await.unwrap();
        interop_adb_api::api::adb_disconnect(independent.id)
            .await
            .unwrap();
        interop_adb_api::api::adb_disconnect(claimed.id.clone())
            .await
            .unwrap();
        assert!(source_status(&claimed.id, &id, video.id()).is_err());
        drop(peer);
    }

    #[tokio::test]
    async fn claiming_preserves_existing_captures_and_fences_old_handles_per_entry() {
        initialize_sdk(vec![1, 2, 3]).unwrap();
        let (transport, peer) = tokio::io::duplex(256 * 1024);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 65536,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        let owner =
            interop_adb_api::api::insert_connection(client.clone(), "same".into(), true).unwrap();
        let other =
            interop_adb_api::api::insert_connection(client.clone(), "same".into(), false).unwrap();
        let before = create(&owner.id, Options::default()).await.unwrap();
        let independent = create(&other.id, Options::default()).await.unwrap();
        let before_capture = lookup(&before).unwrap();
        let independent_capture = lookup(&independent).unwrap();
        let physical = client.connection_id();
        let next = interop_adb_api::api::adb_claim_connection(owner.id.clone())
            .await
            .unwrap();
        assert_eq!(
            interop_adb_api::api::device(&next.id)
                .unwrap()
                .connection_id(),
            physical
        );
        assert!(
            !before_capture.cancellation.is_cancelled(),
            "认领仅撤销服务，不终止已持有 Client 的捕获"
        );
        assert!(create(&owner.id, Options::default()).await.is_err());
        let after = create(&next.id, Options::default()).await.unwrap();
        let after_capture = lookup(&after).unwrap();
        assert_eq!(
            before_capture.connection_owner,
            after_capture.connection_owner
        );
        assert_ne!(
            before_capture.connection_owner,
            independent_capture.connection_owner
        );
        stop_connection(&owner.id);
        assert!(!before_capture.cancellation.is_cancelled());
        assert!(!after_capture.cancellation.is_cancelled());
        stop_connection(&next.id);
        assert!(before_capture.cancellation.is_cancelled());
        assert!(after_capture.cancellation.is_cancelled());
        assert!(
            !independent_capture.cancellation.is_cancelled(),
            "同物理 Client 的另一登记不属于本次认领"
        );
        before_capture.finished.cancelled().await;
        after_capture.finished.cancelled().await;
        interop_adb_api::api::adb_disconnect(owner.id)
            .await
            .unwrap();
        assert!(!client.is_closed());
        interop_adb_api::api::adb_disconnect(other.id)
            .await
            .unwrap();
        independent_capture.finished.cancelled().await;
        assert!(!client.is_closed());
        interop_adb_api::api::adb_disconnect(next.id).await.unwrap();
        assert!(client.is_closed());
        drop(peer);
    }

    #[tokio::test]
    async fn draining_claimed_connection_waits_for_exact_snapshot_and_retains_failed_cleanup() {
        initialize_sdk(vec![1, 2, 3]).unwrap();
        let (transport, mut peer) = tokio::io::duplex(256 * 1024);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 65536,
                banner: "device::".into(),
                features: ["shell_v2".into()].into(),
            },
        )
        .unwrap();
        let old =
            interop_adb_api::api::insert_connection(client.clone(), "drain".into(), true).unwrap();
        let other =
            interop_adb_api::api::insert_connection(client.clone(), "drain".into(), false).unwrap();
        let first = create(&old.id, Options::default()).await.unwrap();
        let first_owner = lookup(&first).unwrap();
        *first_owner.phase.lock().unwrap() = Phase::Running;
        first_owner.startup_finished.cancel();
        let independent = create(&other.id, Options::default()).await.unwrap();
        let independent_owner = lookup(&independent).unwrap();
        let draining = tokio::spawn({
            let id = old.id.clone();
            async move { drain_connection(&id).await }
        });
        // 删除命令已开始，证明排空快照已固定，但远端确认尚未返回。
        let rm = next_open(&mut peer).await;
        assert!(String::from_utf8_lossy(&rm.payload).contains(&jar(&first_owner)));
        assert!(!draining.is_finished());
        let current = interop_adb_api::api::adb_claim_connection(old.id.clone())
            .await
            .unwrap();
        let replacement = create(&current.id, Options::default()).await.unwrap();
        let replacement_owner = lookup(&replacement).unwrap();
        shell_exit(&mut peer, rm, 1).await;
        assert!(
            draining
                .await
                .unwrap()
                .unwrap_err()
                .contains("cleanup_unverified")
        );
        assert!(lookup(&first).is_ok(), "未确认清理必须保留重试权");
        assert!(
            !replacement_owner.cancellation.is_cancelled(),
            "旧排空不能扩大快照"
        );
        assert!(!independent_owner.cancellation.is_cancelled());
        assert!(
            drain_connection(&old.id)
                .await
                .unwrap_err()
                .contains("stale_connection")
        );
        assert!(
            !replacement_owner.cancellation.is_cancelled(),
            "旧句柄不得撤销新捕获"
        );

        let retry = tokio::spawn({
            let id = current.id.clone();
            async move { drain_connection(&id).await }
        });
        let rm = next_open(&mut peer).await;
        assert!(String::from_utf8_lossy(&rm.payload).contains(&jar(&first_owner)));
        shell_exit(&mut peer, rm, 0).await;
        retry.await.unwrap().unwrap();
        assert!(lookup(&first).is_err());
        assert!(lookup(&replacement).is_err());
        assert!(!independent_owner.cancellation.is_cancelled());
        assert!(!client.is_closed(), "排空捕获不得关闭共享传输");
        drain_connection(&current.id).await.unwrap();
        drain_connection(&other.id).await.unwrap();
        interop_adb_api::api::adb_disconnect(other.id)
            .await
            .unwrap();
        interop_adb_api::api::adb_disconnect(current.id)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn sdk_owners_cancel_upload_before_cleanup_and_retain_failed_cleanup_for_retry() {
        initialize_sdk(vec![1, 2, 3]).unwrap();
        let (transport, mut peer) = tokio::io::duplex(256 * 1024);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 65536,
                banner: "device::".into(),
                features: ["shell_v2".into()].into(),
            },
        )
        .unwrap();
        let connection =
            interop_adb_api::api::insert_connection(client.clone(), "fixture".into(), false)
                .unwrap();
        let pending = create(&connection.id, Options::default()).await.unwrap();
        let observer = open_events(&pending).unwrap();
        stop(&pending).await.unwrap();
        let terminal = next_event(&observer).await.unwrap().unwrap();
        assert_eq!(terminal.kind, ScrcpyEventKind::Stopped);
        assert_eq!(terminal.capture_ref, pending);
        assert!(next_event(&observer).await.unwrap().is_none());
        assert!(
            tokio::time::timeout(
                Duration::from_millis(10),
                Frame::read(&mut peer, 65536, true)
            )
            .await
            .is_err(),
            "仅本机登记后停止不得执行任何远端命令"
        );

        let failed = create(&connection.id, Options::default()).await.unwrap();
        let failed_owner = lookup(&failed).unwrap();
        *failed_owner.phase.lock().unwrap() = Phase::Running;
        failed_owner.startup_finished.cancel();
        let stopping = tokio::spawn({
            let id = failed.clone();
            async move { stop(&id).await }
        });
        let rm = next_open(&mut peer).await;
        assert!(String::from_utf8_lossy(&rm.payload).contains("rm -f --"));
        shell_exit(&mut peer, rm, 1).await;
        assert!(
            stopping
                .await
                .unwrap()
                .unwrap_err()
                .contains("cleanup_unverified")
        );
        assert!(lookup(&failed).is_ok(), "失败清理必须保留可重试的终态");
        let retry = tokio::spawn({
            let id = failed.clone();
            async move { stop(&id).await }
        });
        let rm = next_open(&mut peer).await;
        shell_exit(&mut peer, rm, 0).await;
        retry.await.unwrap().unwrap();
        assert!(lookup(&failed).is_err());

        let uploading = create(&connection.id, Options::default()).await.unwrap();
        let starting = tokio::spawn({
            let id = uploading.clone();
            async move { start(&id).await }
        });
        let sync = next_open(&mut peer).await;
        assert_eq!(sync.payload, b"sync:\0");
        Frame::new(protocol::OKAY, 77, sync.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let send = read(&mut peer).await;
        assert_eq!(&send.payload[..4], b"SEND");
        let stopping = tokio::spawn({
            let id = uploading.clone();
            async move { stop(&id).await }
        });
        let result = tokio::time::timeout(Duration::from_millis(200), starting)
            .await
            .unwrap()
            .unwrap();
        assert!(result.is_err());
        let mut sync_closed = false;
        loop {
            let frame = read(&mut peer).await;
            if frame.command == protocol::CLSE && frame.arg0 == sync.arg0 {
                sync_closed = true;
            }
            if frame.command == protocol::OPEN {
                assert!(sync_closed, "删除 JAR 不得越过仍在上传的本机流");
                shell_exit(&mut peer, frame, 0).await;
                break;
            }
        }
        stopping.await.unwrap().unwrap();
        let borrowed = create(&connection.id, Options::default()).await.unwrap();
        let owner = lookup(&borrowed).unwrap();
        interop_adb_api::api::adb_disconnect(connection.id)
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_millis(200), owner.finished.cancelled())
            .await
            .unwrap();
        assert!(
            !client.is_closed(),
            "借用句柄释放不得关闭产品持有的同一传输"
        );
        client.close();
    }
}
