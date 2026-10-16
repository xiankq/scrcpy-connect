//! One independent scrcpy output-audio capture per device. Raw PCM is presented
//! by a native AudioTrack adapter; this module never claims voice-call capture.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, quote, required},
    scrcpy::{SERVER, SERVER_SHA, accept_media},
};
use interop_adb::{AdbStream, CancellationToken, OperationOptions, RemoteSocket, sync::RemotePath};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
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
    sync::{Mutex, RwLock, broadcast},
    time::Instant,
};

pub(crate) struct AudioSource {
    cancellation: CancellationToken,
    state: Arc<RwLock<Value>>,
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
fn emit(events: &broadcast::Sender<Value>, kind: &str, device: &str, data: Value) {
    let _ = events.send(json!({"type":kind,"deviceId":device,"data":data,"timestamp":now()}));
}

impl Runtime {
    pub(crate) async fn stop_device_audio(&self, device: &str) {
        self.audio_sources.lock().await.remove(device);
    }

    pub(crate) async fn audio_command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        if command == "audio.sources" {
            let mut sources = Vec::new();
            for source in self.audio_sources.lock().await.values() {
                sources.push(source.state.read().await.clone());
            }
            return Ok(json!({"sources":sources}));
        }
        let device_id = required(params, "deviceId")?.to_owned();
        if command == "audio.start" {
            return self.start_audio(&device_id).await;
        }
        if command == "audio.stop" {
            let mut sources = self.audio_sources.lock().await;
            if let Some(source) = sources.get(&device_id)
                && let Some(id) = params["sourceId"].as_str()
                && source.state.read().await["sourceId"] != id
            {
                return Err(CoreError::new("source_changed", "设备音源已重新连接。"));
            }
            sources.remove(&device_id);
            return Ok(json!({"deviceId":device_id,"status":"stopped"}));
        }
        let (state, cancellation) = {
            let sources = self.audio_sources.lock().await;
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
                if params["playState"] != "playing" {
                    return Err(CoreError::new(
                        "audio_not_ready",
                        "音频播放器尚未开始工作。",
                    ));
                }
                data["status"] = json!("playing");
                data["nativeAttached"] = json!(true);
                // Playing silence is valid playback, but is not proof that any
                // particular target application is currently emitting sound.
                data["audibleContentVerified"] = json!(false);
            }
            "audio.pause" | "audio.resume" => {
                if data["nativeAttached"] != true {
                    return Err(CoreError::new("audio_not_ready", "音频播放器尚未就绪。"));
                }
                data["status"] = json!(if command == "audio.pause" {
                    "paused"
                } else {
                    "playing"
                });
                data["presentationOnly"] = json!(true);
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
        let client = self.client(device_id).await?;
        let device = self.device(device_id).await?;
        if device.api_level.is_some_and(|api| api < 30) {
            return Err(CoreError::new(
                "unsupported",
                "设备声音采集需要 Android 11 或更新版本。",
            ));
        }
        if format!("{:x}", Sha256::digest(SERVER)) != SERVER_SHA {
            return Err(CoreError::new("server_integrity", "内置控制服务校验失败。"));
        }
        let cancellation = CancellationToken::new();
        let mut guard = StartupGuard(Some(cancellation.clone()));
        let id = uuid::Uuid::new_v4().to_string();
        let state = Arc::new(RwLock::new(
            json!({"sourceId":id,"deviceId":device_id,"name":device.name,"status":"starting","codec":"pcm_s16le","sampleRate":48000,"channels":2,"bytesPerSample":2,"volume":1.0,"muted":false,"createdAt":now(),"nativeAttached":false,"audibleContentVerified":false,"captureSource":"output","callAudioSupported":false}),
        ));
        {
            let mut sources = self.audio_sources.lock().await;
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
                AudioSource {
                    cancellation: cancellation.clone(),
                    state: state.clone(),
                },
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
                &mut &SERVER[..],
                0o600,
                now() as u32,
                SERVER.len() as u64,
            )
            .await?;
            drop(sync);
            let command = format!(
                "CLASSPATH={} app_process / com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn video=false audio=true control=false audio_codec=raw audio_source=output tunnel_forward=true cleanup=true power_on=false send_device_meta=true send_dummy_byte=true send_stream_meta=true send_frame_meta=true",
                quote(&jar)?
            );
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
    events: broadcast::Sender<Value>,
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
            if state.read().await["status"] == "paused" {
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
