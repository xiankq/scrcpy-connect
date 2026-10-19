//! One independent scrcpy output-audio capture per device. Raw PCM is presented
//! by a platform output adapter; this module never claims voice-call capture.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, quote, required},
    remote_process::managed_shell_command,
    scrcpy::accept_media,
};
use interop_adb::{AdbStream, CancellationToken, OperationOptions, RemoteSocket, sync::RemotePath};
use serde_json::{Value, json};
use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    sync::{Mutex, RwLock},
    time::Instant,
};

pub(crate) struct AudioSource {
    cancellation: CancellationToken,
    state: Arc<RwLock<Value>>,
}
impl AudioSource {
    pub(crate) fn new(cancellation: CancellationToken, state: Arc<RwLock<Value>>) -> Self {
        Self {
            cancellation,
            state,
        }
    }
    pub(crate) async fn stop(&self) -> Value {
        let mut state = self.state.write().await;
        state["status"] = json!("stopped");
        state["nativeAttached"] = json!(false);
        self.cancellation.cancel();
        state.clone()
    }
    pub(crate) async fn snapshot(&self, active_only: bool) -> Option<Value> {
        let state = self.state.read().await;
        (!active_only
            || (!self.cancellation.is_cancelled()
                && matches!(
                    state["status"].as_str(),
                    Some("starting" | "playing" | "paused")
                )))
        .then(|| state.clone())
    }
}
impl Drop for AudioSource {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}
struct StartupGuard(Option<CancellationToken>);
impl Drop for StartupGuard {
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
fn emit(events: &crate::events::EventBus, kind: &str, device: &str, data: Value) {
    let _ = events.send(json!({"type":kind,"deviceId":device,"data":data,"timestamp":now()}));
}

fn apply_presentation(data: &mut Value, params: &Value) -> CoreResult<()> {
    let revision = params["revision"]
        .as_u64()
        .ok_or_else(|| CoreError::new("audio_not_applied", "播放器缺少声音状态版本。"))?;
    let play_state = params["playState"]
        .as_str()
        .filter(|state| matches!(*state, "playing" | "paused"));
    if params["applied"] != true || play_state.is_none() {
        return Err(CoreError::new(
            "audio_not_applied",
            "播放器尚未确认实际声音状态。",
        ));
    }
    if data["nativeRevision"]
        .as_u64()
        .is_some_and(|previous| revision < previous)
    {
        return Ok(());
    }
    data["nativeRevision"] = json!(revision);
    data["status"] = json!(play_state.unwrap());
    for key in ["manualPaused", "focusPaused", "backgroundPaused"] {
        if let Some(value) = params[key].as_bool() {
            data[key] = json!(value);
        }
    }
    data["presentationOnly"] = json!(false);
    data["playbackVerified"] = json!(true);
    if let Some(reason) = params["reason"].as_str() {
        data["reason"] = json!(reason.chars().take(1024).collect::<String>());
    } else {
        data.as_object_mut().unwrap().remove("reason");
    }
    Ok(())
}

fn apply_ready(data: &mut Value, params: &Value) -> CoreResult<()> {
    let shared = params["backend"] == "fvp";
    if shared {
        let valid_clock = params["clockStartMs"]
            .as_i64()
            .zip(params["clockEndMs"].as_i64())
            .is_some_and(|(start, end)| start >= 0 && end > start);
        if params["applied"] != true
            || params["revision"].as_u64().is_none()
            || !matches!(params["playState"].as_str(), Some("playing" | "paused"))
            || [
                "mediaInfoReady",
                "playingConfirmed",
                "sourcePcmReceived",
                "playbackClockAdvanced",
            ]
            .iter()
            .any(|key| params[*key] != true)
            || !params["sourcePcmPackets"]
                .as_u64()
                .is_some_and(|count| count > 0)
            || !valid_clock
            || params["sampleRate"] != 48000
            || params["channels"] != 2
        {
            return Err(CoreError::new(
                "audio_not_ready",
                "共享播放器尚未返回完整的真实声音播放证据。",
            ));
        }
    }
    if data["nativeAttached"] == true {
        if (data["backend"] == "fvp") != shared {
            return Err(CoreError::new(
                "audio_not_ready",
                "声音输出后端与已连接的音源不一致。",
            ));
        }
        return apply_presentation(data, params);
    }
    // Preserve the existing native AudioTrack acknowledgement requirements.
    let paused_after_first_write = params["playState"] == "paused"
        && params["nativeReady"] == true
        && params["applied"] == true
        && params["bytesWritten"]
            .as_u64()
            .is_some_and(|count| count > 0)
        && params["revision"].as_u64().is_some();
    if params["playState"] != "playing" && !paused_after_first_write && !shared {
        return Err(CoreError::new(
            "audio_not_ready",
            "音频播放器尚未开始工作。",
        ));
    }
    data["status"] = params["playState"].clone();
    data["nativeAttached"] = json!(true);
    for key in ["manualPaused", "backgroundPaused", "focusPaused"] {
        if let Some(value) = params[key].as_bool() {
            data[key] = json!(value);
        }
    }
    if let Some(revision) = params["revision"].as_u64() {
        data["nativeRevision"] = json!(revision);
    }
    if shared {
        data["backend"] = json!("fvp");
        data["playbackVerified"] = json!(true);
        data["speakerSamplesVerified"] = json!(false);
        for key in [
            "mediaInfoReady",
            "playingConfirmed",
            "sourcePcmReceived",
            "playbackClockAdvanced",
            "sourcePcmPackets",
            "clockStartMs",
            "clockEndMs",
        ] {
            data[key] = params[key].clone();
        }
    }
    // Playback (including silence) cannot identify the target app producing it
    // or prove that physical speaker samples have been observed.
    data["audibleContentVerified"] = json!(false);
    Ok(())
}

fn should_forward_pcm(data: &Value) -> bool {
    // The shared player owns presentation pause. It still needs fresh, bounded
    // input to confirm a resume; stopping upstream here can deadlock that ack.
    data["status"] != "paused" || data["backend"] == "fvp"
}

impl Runtime {
    pub(crate) async fn stop_device_audio(&self, device: &str) {
        let _ = self
            .audio_command("audio.stop", &json!({"deviceId":device}))
            .await;
    }

    pub(crate) async fn audio_activity_sources(&self) -> Vec<Value> {
        self.activities.audio_snapshots(true).await
    }

    pub(crate) async fn audio_command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        if command == "audio.sources" {
            return Ok(json!({"sources":self.activities.audio_snapshots(false).await}));
        }
        let device_id = required(params, "deviceId")?.to_owned();
        if command == "audio.start" {
            return self.start_audio(&device_id).await;
        }
        if command == "audio.stop" {
            let mut sources = self.activities.audio_sources.lock().await;
            let stopped = if let Some(source) = sources.get(&device_id) {
                let mut data = source.state.write().await;
                if params["sourceId"]
                    .as_str()
                    .is_some_and(|id| data["sourceId"] != id)
                {
                    return Err(CoreError::new("source_changed", "设备音源已重新连接。"));
                }
                data["status"] = json!("stopped");
                data["nativeAttached"] = json!(false);
                Some(data.clone())
            } else {
                None
            };
            sources.remove(&device_id);
            // Publish removal while the registry guard is still held, so an
            // event-fenced activity snapshot cannot miss this state change.
            let source_id = stopped.as_ref().map_or_else(
                || params["sourceId"].clone(),
                |data| data["sourceId"].clone(),
            );
            if let Some(data) = stopped {
                emit(&self.events, "audio.updated", &device_id, data);
            }
            return Ok(json!({"deviceId":device_id,"sourceId":source_id,"status":"stopped"}));
        }
        let (state, cancellation) = {
            let sources = self.activities.audio_sources.lock().await;
            let source = sources
                .get(&device_id)
                .filter(|source| !source.cancellation.is_cancelled())
                .ok_or_else(|| {
                    CoreError::new("audio_source_required", "请先连接这台设备的音源。")
                })?;
            (source.state.clone(), source.cancellation.clone())
        };
        let mut data = state.write().await;
        if params["sourceId"]
            .as_str()
            .is_some_and(|id| data["sourceId"] != id)
        {
            return Err(CoreError::new("source_changed", "设备音源已重新连接。"));
        }
        match command {
            "audio.ready" => {
                apply_ready(&mut data, params)?;
            }
            "audio.pause" | "audio.resume" => {
                if data["nativeAttached"] != true {
                    return Err(CoreError::new("audio_not_ready", "音频播放器尚未就绪。"));
                }
                if params["applied"] != true {
                    return Ok(
                        json!({"sourceId":data["sourceId"],"deviceId":device_id,"nativeApplyRequired":true,"paused":command=="audio.pause"}),
                    );
                }
                apply_presentation(&mut data, params)?;
            }
            "audio.presentation" => {
                if data["nativeAttached"] != true {
                    return Err(CoreError::new("audio_not_ready", "音频播放器尚未就绪。"));
                }
                apply_presentation(&mut data, params)?;
            }
            "audio.volume" => {
                let volume = params
                    .get("volume")
                    .map(|value| {
                        value
                            .as_f64()
                            .filter(|volume| volume.is_finite() && (0.0..=1.0).contains(volume))
                            .ok_or_else(|| {
                                CoreError::new("invalid_argument", "音量必须在 0 到 1 之间。")
                            })
                    })
                    .transpose()?
                    .unwrap_or(data["volume"].as_f64().unwrap_or(1.0));
                let muted = params
                    .get("muted")
                    .map(|value| {
                        value
                            .as_bool()
                            .ok_or_else(|| CoreError::new("invalid_argument", "静音状态无效。"))
                    })
                    .transpose()?
                    .unwrap_or(data["muted"].as_bool().unwrap_or(false));
                if params["applied"] != true {
                    return Ok(
                        json!({"sourceId":data["sourceId"],"deviceId":device_id,"volume":volume,"muted":muted,"nativeApplyRequired":true}),
                    );
                }
                data["volume"] = json!(volume);
                data["muted"] = json!(muted);
            }
            _ => return Err(CoreError::new("unknown_command", "音源操作无效。")),
        }
        if cancellation.is_cancelled() {
            return Err(CoreError::new("disconnected", "设备音源已经结束。"));
        }
        emit(&self.events, "audio.updated", &device_id, data.clone());
        Ok(data.clone())
    }

    async fn start_audio(&self, device_id: &str) -> CoreResult<Value> {
        if !self
            .activities
            .sessions
            .lock()
            .await
            .values()
            .any(|session| session.owns_device_audio(device_id))
        {
            return Err(CoreError::new(
                "session_required",
                "请先打开这台设备的远控画面或应用窗口。",
            ));
        }
        let client = self.client(device_id).await?;
        let device = self.device(device_id).await?;
        if device.api_level.is_some_and(|api| api < 30) {
            return Err(CoreError::new(
                "unsupported",
                "设备声音采集需要 Android 11 或更新版本。",
            ));
        }
        let server = crate::bundled_servers::get("scrcpy")?;
        let cancellation = CancellationToken::new();
        let mut guard = StartupGuard(Some(cancellation.clone()));
        let id = uuid::Uuid::new_v4().to_string();
        let state = Arc::new(RwLock::new(
            json!({"sourceId":id,"deviceId":device_id,"name":device.name,"status":"starting","codec":"pcm_s16le","sampleRate":48000,"channels":2,"bytesPerSample":2,"volume":1.0,"muted":false,"createdAt":now(),"nativeAttached":false,"audibleContentVerified":false,"captureSource":"output","callAudioSupported":false}),
        ));
        {
            // Serialize page-backed capture admission with the last session's
            // removal. A device connection alone never admits sound playback.
            let sessions = self.activities.sessions.lock().await;
            if !sessions
                .values()
                .any(|session| session.owns_device_audio(device_id))
            {
                return Err(CoreError::new(
                    "session_required",
                    "请先打开这台设备的远控画面或应用窗口。",
                ));
            }
            let mut sources = self.activities.audio_sources.lock().await;
            if let Some(existing) = sources
                .get(device_id)
                .filter(|source| !source.cancellation.is_cancelled())
            {
                let mut data = existing.state.read().await.clone();
                if data["nativeAttached"] != true {
                    return Err(CoreError::new(
                        "audio_source_starting",
                        "这台设备的音源正在连接。",
                    ));
                }
                data["existing"] = json!(true);
                return Ok(data);
            }
            sources.insert(
                device_id.to_owned(),
                AudioSource::new(cancellation.clone(), state.clone()),
            );
            emit(
                &self.events,
                "audio.updated",
                device_id,
                state.read().await.clone(),
            );
        }
        let jar = format!("/data/local/tmp/interop-audio-{id}.jar");
        let cleanup_client = client.clone();
        let cleanup_path = jar.clone();
        let cleanup_cancel = cancellation.clone();
        let cleanup_state = state.clone();
        let cleanup_events = self.events.clone();
        let cleanup_device = device_id.to_owned();
        tokio::spawn(async move {
            cleanup_cancel.cancelled().await;
            {
                let mut data = cleanup_state.write().await;
                if data["status"] != "error" {
                    data["status"] = json!("stopped");
                }
                data["nativeAttached"] = json!(false);
                emit(
                    &cleanup_events,
                    "audio.updated",
                    &cleanup_device,
                    data.clone(),
                );
            }
            let _ = cleanup_client
                .shell(
                    &format!("rm -f -- {}", quote(&cleanup_path).expect("generated path")),
                    4096,
                    OperationOptions {
                        timeout: Duration::from_secs(3),
                        ..Default::default()
                    },
                )
                .await;
        });
        let token = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        let returned_token = token.clone();
        let scid = u32::from_be_bytes(
            uuid::Uuid::new_v4().as_bytes()[..4]
                .try_into()
                .expect("UUID"),
        ) & 0x7fff_ffff;
        let startup = async {
            let mut sync = client.sync(OperationOptions::default()).await?;
            sync.push(
                &RemotePath::new(&jar)?,
                &mut &server[..],
                0o644,
                now() as u32,
                server.len() as u64,
            )
            .await?;
            drop(sync);
            let command = format!(
                "CLASSPATH={} exec app_process / com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn video=false audio=true control=false audio_codec=raw audio_source=output tunnel_forward=true cleanup=true power_on=false send_device_meta=true send_dummy_byte=true send_stream_meta=true send_frame_meta=true",
                quote(&jar)?
            );
            let command = managed_shell_command(&jar, &command, false)?;
            let mut process = client.exec(&command, options(&cancellation)).await?;
            let process_closed = Arc::new(AtomicBool::new(false));
            let logs = Arc::new(Mutex::new(Vec::new()));
            let process_done = process_closed.clone();
            let process_cancel = cancellation.clone();
            let process_logs = logs.clone();
            tokio::spawn(async move {
                let mut buffer = [0; 4096];
                loop {
                    let result = tokio::select! { _ = process_cancel.cancelled() => break, result = process.read(&mut buffer) => result };
                    match result {
                        Ok(0) | Err(_) => break,
                        Ok(count) => {
                            let mut logs = process_logs.lock().await;
                            let room = 16_384usize.saturating_sub(logs.len());
                            logs.extend_from_slice(&buffer[..room.min(count)]);
                        }
                    }
                }
                process_done.store(true, Ordering::Release);
                process_cancel.cancel();
            });
            let socket = RemoteSocket::LocalAbstract(format!("scrcpy_{scid:08x}"));
            let deadline = Instant::now() + Duration::from_secs(12);
            let mut audio = loop {
                if process_closed.load(Ordering::Acquire) {
                    return Err(CoreError::new(
                        "audio_start_failed",
                        String::from_utf8_lossy(&logs.lock().await).to_string(),
                    ));
                }
                match tokio::time::timeout(
                    Duration::from_millis(600),
                    client.connect_socket(&socket, options(&cancellation)),
                )
                .await
                {
                    Ok(Ok(audio)) => break audio,
                    Ok(Err(error)) if Instant::now() >= deadline => return Err(error.into()),
                    Err(_) if Instant::now() >= deadline => {
                        return Err(CoreError::new("timeout", "设备音频服务未就绪。"));
                    }
                    _ => tokio::time::sleep(Duration::from_millis(40)).await,
                }
            };
            let mut dummy = [0];
            audio.read_exact(&mut dummy).await?;
            if dummy != [0] {
                return Err(CoreError::new("audio_protocol", "音频连接标识无效。"));
            }
            let mut name = [0; 64];
            audio.read_exact(&mut name).await?;
            let mut codec = [0; 4];
            audio.read_exact(&mut codec).await?;
            if codec == [0; 4] {
                return Err(CoreError::new(
                    "audio_unavailable",
                    "设备明确禁用了本次音频采集；请检查系统版本、前台状态和设备限制。",
                ));
            }
            if codec != [0, b'r', b'a', b'w'] {
                return Err(CoreError::new(
                    "audio_protocol",
                    "设备未返回所需的原始 PCM 音频流。",
                ));
            }
            let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
            let port = listener.local_addr()?.port();
            let stream_cancel = cancellation.clone();
            let stream_state = state.clone();
            let stream_events = self.events.clone();
            let stream_device = device_id.to_owned();
            tokio::spawn(async move {
                forward_audio(
                    listener,
                    token,
                    audio,
                    stream_cancel,
                    stream_state,
                    stream_events,
                    stream_device,
                )
                .await;
            });
            Ok::<_, CoreError>(port)
        };
        let result = tokio::time::timeout(Duration::from_secs(20), startup)
            .await
            .unwrap_or_else(|_| Err(CoreError::new("timeout", "设备音源连接超时。")));
        match result {
            Ok(port) => {
                guard.0 = None;
                let mut data = state.read().await.clone();
                data["audioPort"] = json!(port);
                data["audioToken"] = json!(returned_token);
                Ok(data)
            }
            Err(error) => {
                let mut data = state.write().await;
                data["status"] = json!("error");
                data["reason"] = json!(error.message);
                Err(error)
            }
        }
    }
}

pub(crate) async fn stop_unowned_audio(
    activities: &crate::activities::ActivityOwner,
    events: &crate::events::EventBus,
    device: &str,
) {
    let sessions = activities.sessions.lock().await;
    if sessions
        .values()
        .any(|session| session.owns_device_audio(device))
    {
        return;
    }
    let mut sources = activities.audio_sources.lock().await;
    if let Some(source) = sources.remove(device) {
        emit(events, "audio.updated", device, source.stop().await);
    }
}

fn pcm_packet_size(header: &[u8; 12]) -> CoreResult<usize> {
    let flags = u64::from_be_bytes(header[..8].try_into().expect("audio header"));
    let length = u32::from_be_bytes(header[8..].try_into().expect("audio header")) as usize;
    if flags >> 61 != 0 || length > 4096 || !length.is_multiple_of(4) {
        return Err(CoreError::new(
            "audio_protocol",
            "设备音频包的格式或大小无效。",
        ));
    }
    Ok(length)
}

async fn forward_audio(
    listener: TcpListener,
    token: String,
    mut audio: AdbStream,
    cancellation: CancellationToken,
    state: Arc<RwLock<Value>>,
    events: crate::events::EventBus,
    device: String,
) {
    let operation = async {
        let output = accept_media(&listener, &token).await?;
        output.set_nodelay(true)?;
        let (mut read, mut output) = output.into_split();
        let read_cancel = cancellation.clone();
        tokio::spawn(async move {
            let mut byte = [0];
            tokio::select! { _ = read_cancel.cancelled() => {}, _ = read.read(&mut byte) => { read_cancel.cancel(); } }
        });
        let ready_state = state.clone();
        let ready_cancel = cancellation.clone();
        tokio::spawn(async move {
            tokio::select! { _ = ready_cancel.cancelled() => {}, _ = tokio::time::sleep(Duration::from_secs(20)) => { let mut data = ready_state.write().await; if data["nativeAttached"] != true { data["status"] = json!("error"); data["reason"] = json!("音频播放器未返回就绪状态。"); ready_cancel.cancel(); } } }
        });
        loop {
            let mut header = [0; 12];
            audio.read_exact(&mut header).await?;
            let length = pcm_packet_size(&header)?;
            let mut bytes = vec![0; length];
            audio.read_exact(&mut bytes).await?;
            if !should_forward_pcm(&*state.read().await) {
                continue;
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
        data["status"] = json!("error");
        data["reason"] = json!(error.message);
    }
    emit(
        &events,
        "audio.updated",
        &device,
        state.read().await.clone(),
    );
    cancellation.cancel();
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn audio_requires_a_control_session_before_starting_device_work() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let added = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":5555}))
            .await
            .unwrap();
        let error = runtime
            .invoke("audio.start", json!({"deviceId":added["deviceId"]}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "session_required");
        assert!(runtime.activities.audio_sources.lock().await.is_empty());
    }
    fn shared_receipt() -> Value {
        json!({"backend":"fvp","applied":true,"revision":7,"playState":"paused","focusPaused":true,
            "mediaInfoReady":true,"playingConfirmed":true,"sourcePcmReceived":true,"playbackClockAdvanced":true,
            "sourcePcmPackets":2,"clockStartMs":0,"clockEndMs":40,"sampleRate":48000,"channels":2})
    }
    #[test]
    fn shared_ready_requires_all_independent_evidence_and_a_valid_clock() {
        for key in [
            "mediaInfoReady",
            "playingConfirmed",
            "sourcePcmReceived",
            "playbackClockAdvanced",
            "sourcePcmPackets",
            "clockStartMs",
            "clockEndMs",
            "revision",
            "sampleRate",
            "channels",
            "applied",
        ] {
            let mut receipt = shared_receipt();
            receipt.as_object_mut().unwrap().remove(key);
            let mut state = json!({"status":"starting"});
            assert_eq!(
                apply_ready(&mut state, &receipt).unwrap_err().code,
                "audio_not_ready",
                "{key}"
            );
            assert_eq!(state, json!({"status":"starting"}));
            assert!(should_forward_pcm(&state));
        }
        for (key, value) in [
            ("sourcePcmPackets", json!(0)),
            ("clockEndMs", json!(0)),
            ("clockStartMs", json!(-1)),
            ("sampleRate", json!(44100)),
            ("playState", json!("starting")),
        ] {
            let mut receipt = shared_receipt();
            receipt[key] = value;
            assert!(apply_ready(&mut json!({"status":"starting"}), &receipt).is_err());
        }
    }
    #[test]
    fn shared_first_playback_can_be_acknowledged_after_focus_paused_it() {
        let mut state = json!({"status":"starting"});
        apply_ready(&mut state, &shared_receipt()).unwrap();
        assert_eq!(state["status"], "paused");
        assert_eq!(state["nativeAttached"], true);
        assert_eq!(state["nativeRevision"], 7);
        assert_eq!(state["speakerSamplesVerified"], false);
        assert!(state.get("bytesWritten").is_none());
        assert!(
            should_forward_pcm(&state),
            "MDK must receive fresh packets to resume."
        );
        apply_presentation(
            &mut state,
            &json!({"revision":9,"applied":true,"playState":"playing","focusPaused":false}),
        )
        .unwrap();
        apply_ready(&mut state, &shared_receipt()).unwrap();
        assert_eq!(
            state["status"], "playing",
            "A late ready cannot undo a newer presentation."
        );
        assert_eq!(state["nativeRevision"], 9);
    }
    #[test]
    fn native_ready_validation_and_pause_drop_are_preserved() {
        let mut state = json!({"status":"starting"});
        assert!(
            apply_ready(
                &mut state,
                &json!({"playState":"paused","applied":true,"revision":1,"nativeReady":true})
            )
            .is_err()
        );
        apply_ready(&mut state, &json!({"playState":"paused","applied":true,"revision":1,"nativeReady":true,"bytesWritten":4})).unwrap();
        assert!(!should_forward_pcm(&state));
        assert!(
            apply_ready(&mut state, &shared_receipt()).is_err(),
            "A ready receipt cannot switch an already attached backend."
        );
        assert_eq!(state["status"], "paused");
        let mut playing = json!({"status":"starting"});
        apply_ready(&mut playing, &json!({"playState":"playing"})).unwrap();
        assert_eq!(playing["status"], "playing");
        assert!(should_forward_pcm(&playing));
    }
    #[test]
    fn presentation_state_requires_actual_native_acknowledgement() {
        let mut state = json!({"status":"playing","manualPaused":false});
        for receipt in [
            json!({"revision":1,"playState":"paused"}),
            json!({"revision":1,"applied":true,"playState":"starting"}),
        ] {
            assert_eq!(
                apply_presentation(&mut state, &receipt).unwrap_err().code,
                "audio_not_applied"
            );
            assert_eq!(state["status"], "playing");
        }
        apply_presentation(&mut state,&json!({"revision":2,"applied":true,"playState":"paused","manualPaused":false,"focusPaused":true,"reason":"temporary focus loss"})).unwrap();
        assert_eq!(state["status"], "paused");
        assert_eq!(state["manualPaused"], false);
        assert_eq!(state["focusPaused"], true);
        assert_eq!(state["playbackVerified"], true);
        assert_eq!(state["presentationOnly"], false);
        apply_presentation(&mut state,&json!({"revision":1,"applied":true,"playState":"playing","manualPaused":false,"focusPaused":false})).unwrap();
        assert_eq!(
            state["status"], "paused",
            "A late older native acknowledgement cannot undo the current focus pause."
        );
    }
    #[test]
    fn raw_audio_is_stereo_aligned_and_has_no_video_flags() {
        let mut header = [0; 12];
        header[8..].copy_from_slice(&4096u32.to_be_bytes());
        assert_eq!(pcm_packet_size(&header).unwrap(), 4096);
        header[8..].copy_from_slice(&4097u32.to_be_bytes());
        assert!(pcm_packet_size(&header).is_err());
        header[8..].copy_from_slice(&4u32.to_be_bytes());
        header[0] = 0x40;
        assert!(pcm_packet_size(&header).is_err());
    }
}
