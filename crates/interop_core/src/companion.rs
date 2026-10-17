//! Temporary shell JAR: live Binder notifications/clipboard and read-only Telecom state.
//! Notification contents and drafts stay in memory; original action references
//! are scoped to one companion process and notification revision.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, quote, required},
};
use interop_adb::{
    AdbStream, CancellationToken, Client, OperationOptions, ShellEvent, ShellMode, ShellSession,
    sync::RemotePath,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex as StdMutex, OnceLock, Weak},
    time::Duration,
};
use tokio::sync::{RwLock, mpsc, oneshot, watch};

const SERVER: &[u8] = include_bytes!("../../../servers/companion/companion.jar");
const SERVER_SHA: &str = "719e57e3317d91d0858aa722f86770275d3af6130ad2ff0cd4334a5f7722b828";
const MAX_MESSAGE: usize = 1024 * 1024;
const RPC_TIMEOUT: Duration = Duration::from_secs(20);

struct Request {
    payload: Value,
    action: bool,
    result: oneshot::Sender<CoreResult<Value>>,
}
struct Pending {
    command: String,
    action: bool,
    result: oneshot::Sender<CoreResult<Value>>,
}
pub(crate) struct Companion {
    cancellation: CancellationToken,
    requests: mpsc::Sender<Request>,
    state: Arc<RwLock<Value>>,
    stopped: watch::Receiver<bool>,
}
impl Companion {
    pub(crate) fn is_active(&self) -> bool {
        !self.cancellation.is_cancelled()
    }

    pub(crate) async fn capability_state(&self) -> Value {
        self.state.read().await.clone()
    }
}

impl Drop for Companion {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}
struct CancelGuard(Option<CancellationToken>);
impl Drop for CancelGuard {
    fn drop(&mut self) {
        if let Some(token) = &self.0 {
            token.cancel();
        }
    }
}

fn operations(token: &CancellationToken) -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(365 * 86400),
        cancellation: token.clone(),
    }
}
fn event(events: &crate::events::EventBus, kind: &str, device: &str, data: Value) {
    let _ = events.send(json!({"type":kind,"deviceId":device,"data":data,"timestamp":now()}));
}
async fn read_message(stream: &mut AdbStream, line: &mut Vec<u8>) -> CoreResult<Value> {
    loop {
        if let Some(end) = line.iter().position(|byte| *byte == b'\n') {
            if end > MAX_MESSAGE {
                return Err(CoreError::new("protocol_error", "互联服务消息超过限制。"));
            }
            let message: Vec<_> = line.drain(..=end).collect();
            let mut value: Value = serde_json::from_slice(&message)?;
            if value["result"].get("sourceStamp").is_some() {
                value["result"]["rpcBytesReceived"] = json!(message.len());
            }
            return Ok(value);
        }
        if line.len() > MAX_MESSAGE {
            return Err(CoreError::new("protocol_error", "互联服务消息超过限制。"));
        }
        let mut buffer = [0u8; 8192];
        let count = stream.read(&mut buffer).await?;
        if count == 0 {
            return Err(CoreError::new("disconnected", "互联服务已结束。"));
        }
        line.extend_from_slice(&buffer[..count]);
    }
}
async fn ready(shell: &mut ShellSession) -> CoreResult<()> {
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    while let Some(message) = shell.next_event().await? {
        match message {
            ShellEvent::Stdout(bytes) => {
                if stdout.len() + bytes.len() > 8192 {
                    return Err(CoreError::new(
                        "companion_startup",
                        "互联服务启动输出超过限制。",
                    ));
                }
                stdout.extend(bytes);
                if stdout.split(|byte| *byte == b'\n').any(|line| {
                    line.starts_with(b"INTEROP_COMPANION_READY ")
                        && line[24..].iter().all(u8::is_ascii_digit)
                }) {
                    return Ok(());
                }
            }
            ShellEvent::Stderr(bytes) => stderr.extend(
                bytes
                    .into_iter()
                    .take(4096usize.saturating_sub(stderr.len())),
            ),
            ShellEvent::Exit(_) => break,
        }
    }
    Err(CoreError::new(
        "companion_startup",
        format!("互联服务未能启动：{}", String::from_utf8_lossy(&stderr)),
    ))
}
fn rpc_error(action: bool, message: &str) -> CoreError {
    if action {
        CoreError::new(
            "result_unknown",
            format!("动作结果尚不确定，不会自动重试。{message}"),
        )
    } else {
        CoreError::new("disconnected", message)
    }
}
fn startup_lock(key: &str) -> CoreResult<Arc<tokio::sync::Mutex<()>>> {
    type Locks = HashMap<String, Weak<tokio::sync::Mutex<()>>>;
    static LOCKS: OnceLock<StdMutex<Locks>> = OnceLock::new();
    let mut locks = LOCKS
        .get_or_init(Default::default)
        .lock()
        .map_err(|_| CoreError::new("companion_error", "互联服务锁不可用。"))?;
    locks.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = locks.get(key).and_then(Weak::upgrade) {
        return Ok(lock);
    }
    let lock = Arc::new(tokio::sync::Mutex::new(()));
    locks.insert(key.into(), Arc::downgrade(&lock));
    Ok(lock)
}

impl Companion {
    async fn start(
        client: Client,
        device: String,
        events: crate::events::EventBus,
        cancellation: CancellationToken,
    ) -> CoreResult<Arc<Self>> {
        if format!("{:x}", Sha256::digest(SERVER)) != SERVER_SHA {
            return Err(CoreError::new("server_integrity", "内置互联服务校验失败。"));
        }
        let mut guard = CancelGuard(Some(cancellation.clone()));
        let socket_name = format!("interop-companion-{}", uuid::Uuid::new_v4().simple());
        let secret = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        let remote_jar = format!("/data/local/tmp/{socket_name}.jar");
        let startup = Box::pin(async {
            let mut sync = client.sync(operations(&cancellation)).await?;
            let count = sync
                .push(
                    &RemotePath::new(&remote_jar)?,
                    &mut &SERVER[..],
                    0o600,
                    now().min(u32::MAX as u64) as u32,
                    SERVER.len() as u64,
                )
                .await?;
            if count != SERVER.len() as u64 {
                return Err(CoreError::new("server_integrity", "互联服务未完整上传。"));
            }
            let command = format!(
                "CLASSPATH={} app_process / com.interop.companion.Main {} {}",
                quote(&remote_jar)?,
                socket_name,
                secret
            );
            let mut shell = client
                .shell_session(&command, ShellMode::Raw, 65536, operations(&cancellation))
                .await?;
            ready(&mut shell).await?;
            let mut stream = client
                .open(
                    &format!("localabstract:{socket_name}"),
                    operations(&cancellation),
                )
                .await?;
            let mut auth = serde_json::to_vec(&json!({"token":secret}))?;
            auth.push(b'\n');
            stream.write_all(&auth).await?;

            let mut line = Vec::new();
            let ready = loop {
                let message = read_message(&mut stream, &mut line).await?;
                if message["event"] == "ready" {
                    break message;
                }
            };
            if ready["protocol"] != 1 || ready["uid"] != 2000 {
                return Err(CoreError::new(
                    "protocol_error",
                    "互联服务协议或 shell 身份不匹配。",
                ));
            }
            Ok((shell, stream, line, ready))
        });
        let result = tokio::time::timeout(Duration::from_secs(25), startup).await;
        let (shell, stream, line, initial) = match result {
            Ok(Ok(result)) => result,
            failed => {
                cancellation.cancel();
                let _ = client
                    .shell(
                        &format!("rm -f -- {}", quote(&remote_jar)?),
                        4096,
                        OperationOptions {
                            timeout: Duration::from_secs(2),
                            ..Default::default()
                        },
                    )
                    .await;
                return Err(match failed {
                    Ok(Err(error)) => error,
                    _ => CoreError::new("timeout", "互联服务启动超时。"),
                });
            }
        };
        let state = Arc::new(RwLock::new(
            json!({"notifications":initial["notifications"],"calls":initial["calls"],"clipboard":{"status":"not_started","live":false},"apiLevel":initial["apiLevel"]}),
        ));
        let (sender, receiver) = mpsc::channel(32);
        let (stopped_tx, stopped) = watch::channel(false);
        let process_cancel = cancellation.clone();
        let process_client = client.clone();
        tokio::spawn(async move {
            drain_process(shell, &process_cancel).await;
            process_cancel.cancel();
            let _ = process_client
                .shell(
                    &format!("rm -f -- '{}'", remote_jar),
                    4096,
                    OperationOptions::default(),
                )
                .await;
            let _ = stopped_tx.send(true);
        });
        let actor_state = state.clone();
        let actor_cancel = cancellation.clone();
        tokio::spawn(async move {
            run(
                stream,
                line,
                receiver,
                actor_state,
                actor_cancel,
                events,
                device,
            )
            .await;
        });
        guard.0 = None;
        Ok(Arc::new(Self {
            cancellation,
            requests: sender,
            state,
            stopped,
        }))
    }
    async fn request(&self, command: &str, params: &Value) -> CoreResult<Value> {
        let mut payload = params.clone();
        payload["command"] = json!(command);
        payload["requestId"] = json!(uuid::Uuid::new_v4().to_string());
        let action = !command.ends_with(".list")
            && command != "clipboard.get"
            && !command.starts_with("media.");
        let (result, receiver) = oneshot::channel();
        let request = Request {
            payload,
            action,
            result,
        };
        tokio::time::timeout(RPC_TIMEOUT, async {
            self.requests
                .send(request)
                .await
                .map_err(|_| rpc_error(action, "互联服务已断开。"))?;
            receiver
                .await
                .map_err(|_| rpc_error(action, "互联服务未返回结果。"))?
        })
        .await
        .map_err(|_| {
            if action {
                rpc_error(true, "等待系统回执超时，请核对手机。")
            } else {
                CoreError::new("timeout", "读取互联状态超时。")
            }
        })?
    }
    async fn stop(&self) {
        // Keep the authenticated socket alive until the media owner confirms
        // that its exact Process objects exited. Closing shell transport alone
        // does not acknowledge Java finally/child cleanup.
        if !self.cancellation.is_cancelled() {
            let _ = tokio::time::timeout(
                Duration::from_secs(6),
                self.request(
                    "media.shutdown",
                    &json!({"operationId":uuid::Uuid::new_v4().to_string()}),
                ),
            )
            .await;
        }
        self.cancellation.cancel();
        let mut stopped = self.stopped.clone();
        let _ = tokio::time::timeout(Duration::from_secs(5), async {
            while !*stopped.borrow_and_update() {
                if stopped.changed().await.is_err() {
                    break;
                }
            }
        })
        .await;
    }
}

async fn drain_process(mut shell: ShellSession, cancellation: &CancellationToken) {
    loop {
        tokio::select! {
            _=cancellation.cancelled()=>{
                let _=tokio::time::timeout(Duration::from_secs(3),async {while shell.next_event().await.is_ok_and(|event|event.is_some()) {}}).await;
                break;
            },
            result=shell.next_event()=>if matches!(result,Ok(None)|Err(_)) {break;},
        }
    }
}

// The socket actor commits both observations and RPC cache refreshes here.
// Callers receive their receipt only after its cache update is fenced, so a
// delayed caller cannot overwrite a later message from the same socket.
async fn commit_message(
    response: Value,
    pending: &mut HashMap<String, Pending>,
    state: &RwLock<Value>,
    events: &crate::events::EventBus,
    device: &str,
) -> CoreResult<()> {
    if let Some(kind) = response["event"].as_str() {
        let section = match kind {
            "notifications.changed" => Some("notifications"),
            "calls.changed" | "calls.incoming" => Some("calls"),
            _ => None,
        };
        if let Some(section) = section {
            let data = response["data"].clone();
            let mut state = state.write().await;
            state[section] = data.clone();
            event(events, kind, device, data);
        } else if matches!(kind, "clipboard.changed" | "clipboard.unavailable") {
            let available = kind == "clipboard.changed";
            let mut state = state.write().await;
            state["clipboard"] = json!({"status":if available {"available"}else{"limited"},"live":available,"reason":response["data"]["reason"]});
            event(events, kind, device, response["data"].clone());
        } else if kind == "companion.error" {
            return Err(CoreError::new(
                "companion_error",
                response["reason"].as_str().unwrap_or("互联服务出错。"),
            ));
        }
    } else {
        let id = response["requestId"]
            .as_str()
            .ok_or_else(|| CoreError::new("protocol_error", "互联服务缺少请求标识。"))?;
        let request = pending
            .remove(id)
            .ok_or_else(|| CoreError::new("protocol_error", "互联服务返回未知请求。"))?;
        let result = if let Some(error) = response.get("error") {
            Err(CoreError::new(
                error["code"].as_str().unwrap_or("companion_error"),
                error["message"].as_str().unwrap_or("互联动作失败。"),
            ))
        } else {
            Ok(response["result"].clone())
        };
        let section = match request.command.as_str() {
            "notifications.list" => Some("notifications"),
            "calls.list" => Some("calls"),
            _ => None,
        };
        if let (Some(section), Ok(data)) = (section, &result) {
            let mut state = state.write().await;
            state[section] = data.clone();
            events.note_state_change();
        } else if matches!(request.command.as_str(), "clipboard.get" | "clipboard.set") {
            let capability = match &result {
                Ok(_) => json!({"status":"available","live":true}),
                Err(error) => {
                    json!({"status":"limited","live":false,"reason":error.message,"code":error.code})
                }
            };
            let mut state = state.write().await;
            state["clipboard"] = capability;
            events.note_state_change();
        }
        let _ = request.result.send(result);
    }
    Ok(())
}

async fn run(
    mut stream: AdbStream,
    mut line: Vec<u8>,
    mut requests: mpsc::Receiver<Request>,
    state: Arc<RwLock<Value>>,
    cancellation: CancellationToken,
    events: crate::events::EventBus,
    device: String,
) {
    let mut pending = HashMap::<String, Pending>::new();
    let result:CoreResult<()>=async {loop {tokio::select! {
        _=cancellation.cancelled()=>return Ok(()),
        request=requests.recv()=>{
            let Some(request)=request else {return Ok(());};
            if request.result.is_closed() {continue;}
            if pending.len()>=32 {let _=request.result.send(Err(CoreError::new("busy","正在等待系统动作，请稍后再试。")));continue;}
            let id=request.payload["requestId"].as_str().unwrap_or_default().to_owned();
            let mut bytes=serde_json::to_vec(&request.payload)?;
            if bytes.len()>MAX_MESSAGE-1024 {let _=request.result.send(Err(CoreError::new("invalid_argument","互联服务请求超过消息限制。")));continue;}
            bytes.push(b'\n');
            let command=request.payload["command"].as_str().unwrap_or_default().to_owned();
            pending.insert(id,Pending {command,action:request.action,result:request.result});
            tokio::time::timeout(RPC_TIMEOUT,stream.write_all(&bytes)).await.map_err(|_|CoreError::new("timeout","互联服务写入超时。"))??;
        },
        response=read_message(&mut stream,&mut line)=>{
            commit_message(response?,&mut pending,&state,&events,&device).await?;
        }
    }}}.await;
    cancellation.cancel();
    drop(stream);
    let reason = result
        .err()
        .map(|e| e.message)
        .unwrap_or_else(|| "互联服务已停止。".into());
    for (_, request) in pending {
        let _ = request.result.send(Err(rpc_error(request.action, &reason)));
    }
    while let Ok(request) = requests.try_recv() {
        let _ = request
            .result
            .send(Err(CoreError::new("disconnected", reason.clone())));
    }
    let mut state = state.write().await;
    *state = json!({"notifications":{"notifications":[],"status":"unknown","live":false,"reason":reason},"calls":{"calls":[],"status":"unknown","audioStatus":"unknown","live":false,"reason":reason},"clipboard":{"status":"unknown","live":false,"reason":reason}});
    event(
        &events,
        "companion.stopped",
        &device,
        json!({"reason":reason}),
    );
}

impl Runtime {
    // Cancellation must never start another helper after disconnect.
    pub(crate) async fn cancel_companion_media(
        &self,
        device: &str,
        operation: &str,
    ) -> CoreResult<Value> {
        let companion = self
            .companions
            .lock()
            .await
            .get(device)
            .filter(|companion| !companion.cancellation.is_cancelled())
            .cloned();
        match companion {
            Some(companion) => {
                companion
                    .request("media.thumbnail.cancel", &json!({"operationId":operation}))
                    .await
            }
            None => Ok(json!({"cancelRequested":true,"notRunning":true})),
        }
    }

    pub(crate) async fn companion_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let companion = if params["allowStart"] == false {
            let existing = self
                .companions
                .lock()
                .await
                .get(id)
                .filter(|companion| companion.is_active())
                .cloned();
            match existing {
                Some(companion) => companion,
                None => {
                    return match command {
                        "notifications.list" => Ok(
                            json!({"deviceId":id,"notifications":[],"status":"unknown","live":false,"reason":"尚未建立实时通知观察。"}),
                        ),
                        "calls.list" => Ok(
                            json!({"deviceId":id,"calls":[],"status":"unknown","audioStatus":"unknown","live":false,"reason":"尚未建立通话观察。"}),
                        ),
                        _ => Err(CoreError::new(
                            "observation_required",
                            "请先明确启动此设备的实时观察。",
                        )),
                    };
                }
            }
        } else {
            let client = self.client(id).await?;
            // Serialize startup for this device only. Stop never waits on another
            // device's startup, and can cancel ours through device_operations.
            let lock = startup_lock(&format!("{}:{id}", self.root.display()))?;
            let startup = lock.lock().await;
            let companion = {
                let existing = self
                    .companions
                    .lock()
                    .await
                    .get(id)
                    .filter(|companion| !companion.cancellation.is_cancelled())
                    .cloned();
                if let Some(companion) = existing {
                    companion
                } else {
                    let token = CancellationToken::new();
                    let companion = {
                        {
                            let mut operations = self.device_operations.lock().await;
                            if self.device(id).await?.status != "connected" {
                                return Err(CoreError::new(
                                    "cancelled",
                                    "设备正在断开，互联服务启动已取消。",
                                ));
                            }
                            operations.insert(format!("companion:{id}"), token.clone());
                        }
                        self.emit("companion.starting", Some(id), json!({"status":"starting"}));
                        Box::pin(Companion::start(
                            client,
                            id.into(),
                            self.events.clone(),
                            token.clone(),
                        ))
                        .await?
                    };
                    let _operations = self.device_operations.lock().await;
                    if token.is_cancelled() || self.device(id).await?.status != "connected" {
                        return Err(CoreError::new(
                            "cancelled",
                            "设备正在断开，互联服务启动已取消。",
                        ));
                    }
                    self.companions
                        .lock()
                        .await
                        .insert(id.into(), companion.clone());
                    companion
                }
            };
            drop(startup);
            companion
        };
        let mut result = companion.request(command, params).await?;
        result["deviceId"] = json!(id);
        if let Some(calls) = result["calls"].as_array_mut() {
            let device = self.device(id).await?;
            for call in calls {
                call["deviceId"] = json!(id);
                call["deviceName"] = json!(device.name);
            }
        }
        Ok(result)
    }
    pub(crate) async fn stop_device_companion(&self, id: &str) {
        let token = {
            let mut operations = self.device_operations.lock().await;
            let prefix = format!("thumbnail:{id}:");
            for (key, token) in operations.iter() {
                if key.starts_with(&prefix) {
                    token.cancel();
                }
            }
            operations.remove(&format!("companion:{id}"))
        };
        let companion = self.companions.lock().await.get(id).cloned();
        if let Some(companion) = companion {
            companion.stop().await;
            let mut companions = self.companions.lock().await;
            if companions
                .get(id)
                .is_some_and(|current| Arc::ptr_eq(current, &companion))
            {
                companions.remove(id);
            }
        }
        // No established helper means this only cancels in-flight startup.
        if let Some(token) = token {
            token.cancel();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn cached_companion() -> (
        tempfile::TempDir,
        Arc<Runtime>,
        String,
        Arc<Companion>,
        mpsc::Receiver<Request>,
    ) {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let device = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":9}))
            .await
            .unwrap()["deviceId"]
            .as_str()
            .unwrap()
            .to_owned();
        let (requests, receiver) = mpsc::channel(32);
        let (_, stopped) = watch::channel(false);
        let companion = Arc::new(Companion {
            cancellation: CancellationToken::new(),
            requests,
            state: Arc::new(RwLock::new(json!({
                "notifications":{"notifications":[{"id":"actionable"}],"status":"available","live":true},
                "calls":{"calls":[{"id":"ongoing"}],"status":"available","live":true},
                "clipboard":{"status":"available","live":true}
            }))),
            stopped,
        });
        runtime
            .companions
            .lock()
            .await
            .insert(device.clone(), companion.clone());
        (directory, runtime, device, companion, receiver)
    }

    #[tokio::test]
    async fn cancelled_helper_snapshot_never_exposes_actionable_cached_data() {
        let (_directory, runtime, device, companion, _requests) = cached_companion().await;
        companion.cancellation.cancel();
        let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
        let cached = &snapshot["companions"][0];
        assert_eq!(cached["deviceId"], device);
        for (section, collection) in [("notifications", "notifications"), ("calls", "calls")] {
            assert_eq!(cached["state"][section]["status"], "unknown");
            assert_eq!(cached["state"][section]["live"], false);
            assert_eq!(cached["state"][section][collection], json!([]));
        }
        assert_eq!(cached["state"]["clipboard"]["live"], false);
        assert_eq!(
            runtime
                .invoke(
                    "clipboard.get",
                    json!({"deviceId":device,"allowStart":false})
                )
                .await
                .unwrap_err()
                .code,
            "observation_required"
        );
    }

    #[tokio::test]
    async fn a_list_receipt_cannot_overwrite_a_newer_observed_change() {
        let (_directory, runtime, device, companion, mut requests) = cached_companion().await;
        for (command, section) in [
            ("notifications.list", "notifications"),
            ("calls.list", "calls"),
        ] {
            let owner = runtime.clone();
            let id = device.clone();
            let invocation = tokio::spawn(async move {
                owner
                    .invoke(command, json!({"deviceId":id,"allowStart":false}))
                    .await
            });
            let request = requests.recv().await.unwrap();
            let old = json!({section:[],"status":"available","live":true});
            let newer = json!({section:[{"id":"newer"}],"status":"available","live":true});
            // Use the real actor commit boundary without an Android socket:
            // receive the RPC result, then a newer observation, before the
            // caller resumes its oneshot.
            let request_id = request.payload["requestId"].as_str().unwrap().to_owned();
            let mut pending = HashMap::from([(
                request_id.clone(),
                Pending {
                    command: command.into(),
                    action: request.action,
                    result: request.result,
                },
            )]);
            let before = runtime.events.cursor();
            let mut events = runtime.subscribe();
            commit_message(
                json!({"requestId":request_id,"result":old}),
                &mut pending,
                &companion.state,
                &runtime.events,
                &device,
            )
            .await
            .unwrap();
            assert_eq!(
                runtime.events.cursor().state_revision,
                before.state_revision + 1
            );
            assert_eq!(runtime.events.cursor().sequence, before.sequence);
            assert!(
                events.try_recv().is_err(),
                "query refreshes must not retrigger UI queries"
            );
            assert_eq!(companion.state.read().await[section], old);
            commit_message(
                json!({"event":format!("{section}.changed"),"data":newer}),
                &mut pending,
                &companion.state,
                &runtime.events,
                &device,
            )
            .await
            .unwrap();
            assert_eq!(events.try_recv().unwrap()["data"], newer);
            invocation.await.unwrap().unwrap();
            let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
            assert_eq!(snapshot["companions"][0]["state"][section], newer);
        }
    }
}
