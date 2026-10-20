//! Temporary shell JAR: live Binder notifications/clipboard and read-only Telecom state.
//! Notification contents and drafts stay in memory; original action references
//! are scoped to one companion process and notification revision.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, quote, required},
    remote_process::managed_shell_command,
};
use interop_adb::{AdbStream, CancellationToken, Client, OperationOptions, sync::RemotePath};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex as StdMutex, OnceLock, Weak},
    time::Duration,
};
use tokio::sync::{RwLock, mpsc, oneshot, watch};

const MAX_MESSAGE: usize = 1024 * 1024;
const RPC_TIMEOUT: Duration = Duration::from_secs(20);

#[cfg(test)]
#[path = "companion/deployment_tests.rs"]
mod deployment_tests;

#[cfg(test)]
#[path = "companion/apps_tests.rs"]
mod apps_tests;

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
    pub(crate) id: uuid::Uuid,
    cancellation: CancellationToken,
    requests: mpsc::Sender<Request>,
    pub(crate) state: Arc<RwLock<Value>>,
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
async fn ready(shell: &mut AdbStream) -> CoreResult<()> {
    let mut output = Vec::new();
    let mut line = Vec::new();
    loop {
        let mut byte = [0];
        if shell.read(&mut byte).await? == 0 {
            break;
        }
        if output.len() == 8192 {
            return Err(CoreError::new(
                "companion_startup",
                "互联服务启动输出超过限制。",
            ));
        }
        output.push(byte[0]);
        if byte[0] == b'\n' {
            if line
                .strip_prefix(b"INTEROP_COMPANION_READY ")
                .is_some_and(|pid| !pid.is_empty() && pid.iter().all(u8::is_ascii_digit))
            {
                return Ok(());
            }
            line.clear();
        } else {
            line.push(byte[0]);
        }
    }
    Err(CoreError::new(
        "companion_startup",
        format!("互联服务未能启动：{}", String::from_utf8_lossy(&output)),
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
        runtime: Weak<Runtime>,
    ) -> CoreResult<Arc<Self>> {
        let server = crate::bundled_servers::get("companion")?;
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
                    &mut &server[..],
                    0o644,
                    now().min(u32::MAX as u64) as u32,
                    server.len() as u64,
                )
                .await?;
            if count != server.len() as u64 {
                return Err(CoreError::new("server_integrity", "互联服务未完整上传。"));
            }
            let command = managed_shell_command(
                &remote_jar,
                &format!(
                    "CLASSPATH={} exec app_process / com.interop.companion.Main {} {}",
                    quote(&remote_jar)?,
                    socket_name,
                    secret
                ),
                false,
            )?;
            let mut shell = client.exec(&command, operations(&cancellation)).await?;
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
        let id = uuid::Uuid::new_v4();
        tokio::spawn(async move {
            run(
                stream,
                line,
                receiver,
                actor_state,
                actor_cancel,
                events,
                ObservationContext {
                    runtime,
                    helper: id,
                    device,
                },
            )
            .await;
        });
        guard.0 = None;
        Ok(Arc::new(Self {
            id,
            cancellation,
            requests: sender,
            state,
            stopped,
        }))
    }
    pub(crate) async fn request(&self, command: &str, params: &Value) -> CoreResult<Value> {
        let mut payload = params.clone();
        payload["command"] = json!(command);
        payload["requestId"] = json!(uuid::Uuid::new_v4().to_string());
        let action = !command.ends_with(".list")
            && command != "apps.icon"
            && command != "clipboard.get"
            && command != "observation.set"
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

async fn drain_process(mut shell: AdbStream, cancellation: &CancellationToken) {
    let mut buffer = [0; 4096];
    loop {
        tokio::select! {
            _=cancellation.cancelled()=>{
                let _=tokio::time::timeout(Duration::from_secs(3),async {while shell.read(&mut [0; 4096]).await.is_ok_and(|count| count != 0) {}}).await;
                break;
            },
            result=shell.read(&mut buffer)=>if matches!(result,Ok(0)|Err(_)) {break;},
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
    context: Option<&ObservationContext>,
) -> CoreResult<()> {
    if let Some(kind) = response["event"].as_str() {
        let section = match kind {
            "notifications.changed" => Some("notifications"),
            "calls.changed" | "calls.incoming" => Some("calls"),
            _ => None,
        };
        if let Some(section) = section {
            if let Some(context) = context {
                if let Some(runtime) = context.runtime.upgrade() {
                    runtime
                        .commit_observation(
                            device,
                            context.helper,
                            &response,
                            Some(section),
                            Some(kind),
                            state,
                        )
                        .await;
                }
                return Ok(());
            }
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
        let mut result = if let Some(error) = response.get("error") {
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
            if let Some(context) = context {
                if let Some(runtime) = context.runtime.upgrade() {
                    let accepted = runtime
                        .commit_observation(
                            device,
                            context.helper,
                            &json!({"data":data}),
                            Some(section),
                            None,
                            state,
                        )
                        .await;
                    if !accepted {
                        result = runtime
                            .observation_status(device)
                            .await
                            .map(|observation| observation[section].clone());
                    }
                }
            } else {
                let mut state = state.write().await;
                state[section] = data.clone();
                events.note_state_change();
            }
        } else if request.command == "observation.set" {
            if let (Some(context), Ok(data)) = (context, &result)
                && let Some(runtime) = context.runtime.upgrade()
                && !runtime
                    .commit_observation(device, context.helper, data, None, None, state)
                    .await
            {
                result = Err(CoreError::new(
                    "cancelled",
                    "此观察回执所属的连接或意图已改变。",
                ));
            }
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
    context: ObservationContext,
) {
    let device = &context.device;
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
            commit_message(response?,&mut pending,&state,&events,device,Some(&context)).await?;
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
        device,
        json!({"reason":reason}),
    );
    drop(state);
    if let Some(runtime) = context.runtime.upgrade() {
        runtime
            .observation_helper_stopped(device, context.helper, &reason)
            .await;
    }
}

struct ObservationContext {
    runtime: Weak<Runtime>,
    helper: uuid::Uuid,
    device: String,
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
        if command == "apps.icon" {
            let package = required(params, "packageName")?;
            if package.is_empty()
                || package.len() > 255
                || !package.split('.').all(|part| {
                    !part.is_empty()
                        && part
                            .bytes()
                            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
                })
            {
                return Err(CoreError::new(
                    "invalid_argument",
                    "请指定有效的目标应用包名。",
                ));
            }
        }
        // Application snapshots belong to the transport admitted when the read
        // began. A later connection for this device cannot validate this read.
        let app_read_client = if matches!(command, "apps.list" | "apps.icon") {
            Some(self.client(id).await?)
        } else {
            None
        };
        if command == "calls.open" {
            if params.get("callId").is_some() {
                return Err(CoreError::new(
                    "call_targeting_unavailable",
                    "此入口仅打开手机当前系统通话界面，不能定位指定通话。",
                ));
            }
            let observation = self.observation_status(id).await?;
            if observation["wanted"] != true || observation["calls"]["live"] != true {
                return Err(CoreError::new(
                    "observation_required",
                    "请先核验此设备的实时通话状态。",
                ));
            }
        }
        if command == "observation.set"
            && params["enabled"] == true
            && !self
                .observation_is_current(id, params["epoch"].as_u64().unwrap_or(0))
                .await
        {
            return Err(CoreError::new(
                "cancelled",
                "此观察意图已停止或连接已改变。",
            ));
        }
        if let Some(section) = match command {
            "notifications.list" => Some("notifications"),
            "calls.list" => Some("calls"),
            _ => None,
        } {
            let observation = self.observation_status(id).await?;
            if observation["wanted"] != true
                || !matches!(observation["phase"].as_str(), Some("observing" | "limited"))
            {
                let mut result = observation[section].clone();
                result["deviceId"] = json!(id);
                return Ok(result);
            }
        }
        if command.starts_with("notifications.") && !command.ends_with(".list") {
            let observation = self.observation_status(id).await?;
            if observation["wanted"] != true || observation["notifications"]["live"] != true {
                return Err(CoreError::new(
                    "observation_required",
                    "请先明确启动此设备的实时通知观察。",
                ));
            }
        }
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
                            Arc::downgrade(self),
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
        if command == "observation.set" && params["enabled"] == true {
            let epoch = params["epoch"].as_u64().unwrap_or(0);
            if !self.bind_observation(id, epoch, companion.id).await {
                return Err(CoreError::new(
                    "cancelled",
                    "此观察意图已停止或连接已改变。",
                ));
            }
        }
        let mut result = companion.request(command, params).await?;
        if command == "observation.set" && result["observationEnabled"] != params["enabled"] {
            return Err(CoreError::new(
                "observation_cleanup_unknown",
                "尚未确认远端观察监听完成清理。",
            ));
        }
        result["deviceId"] = json!(id);
        if let Some(calls) = result.get_mut("calls").and_then(Value::as_array_mut) {
            let device = self.device(id).await?;
            for call in calls {
                call["deviceId"] = json!(id);
                call["deviceName"] = json!(device.name);
            }
        }
        if let Some(request_client) = app_read_client {
            // Match device publication's lock order and hold all ownership
            // guards through the final check. Even a success already delivered
            // into the oneshot must be discarded after stop or replacement.
            let store = self.store.read().await;
            let connections = self.connections.lock().await;
            let companions = self.companions.lock().await;
            if !store
                .devices
                .iter()
                .any(|device| device.id == id && device.status == "connected")
                || !connections.get(id).is_some_and(|client| {
                    !client.is_closed() && client.same_connection(&request_client)
                })
                || !companions
                    .get(id)
                    .is_some_and(|current| Arc::ptr_eq(current, &companion) && current.is_active())
            {
                return Err(CoreError::new(
                    "cancelled",
                    "此应用读取所属的设备连接或互联服务已改变。",
                ));
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
            id: uuid::Uuid::new_v4(),
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
        runtime.store.write().await.devices[0].status = "connected".into();
        runtime
            .invoke("observation.start", json!({"deviceId":device}))
            .await
            .unwrap();
        // Let the real supervisor establish its epoch before exercising list
        // receipts. Manually binding an epoch races its queued observation.set.
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let request = requests.recv().await.unwrap();
                assert_eq!(request.payload["command"], "observation.set");
                let epoch = request.payload["epoch"].clone();
                wire_response(
                    &runtime,
                    &device,
                    &companion,
                    request,
                    json!({
                        "observationEpoch":epoch,"observationEnabled":true,
                        "notifications":{"notifications":[],"status":"available","live":true},
                        "calls":{"calls":[],"status":"available","live":true}
                    }),
                )
                .await;
                if runtime.observation_status(&device).await.unwrap()["phase"] == "observing" {
                    break;
                }
            }
        })
        .await
        .expect("the observation supervisor must receive its actual startup receipt");
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
            let request = loop {
                let request = requests.recv().await.unwrap();
                if request.payload["command"] == command {
                    break request;
                }
                // A superseded startup may already have been enqueued when the
                // explicit start changed epoch. Its receipt must remain stale.
                assert_eq!(request.payload["command"], "observation.set");
                let epoch = request.payload["epoch"].clone();
                wire_response(
                    &runtime,
                    &device,
                    &companion,
                    request,
                    json!({
                        "observationEpoch":epoch,"observationEnabled":true,
                        "notifications":{"notifications":[],"status":"available","live":true},
                        "calls":{"calls":[],"status":"available","live":true}
                    }),
                )
                .await;
            };
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
                None,
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
                None,
            )
            .await
            .unwrap();
            assert_eq!(events.try_recv().unwrap()["data"], newer);
            invocation.await.unwrap().unwrap();
            let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
            assert_eq!(snapshot["companions"][0]["state"][section], newer);
        }
    }

    async fn wire_response(
        runtime: &Arc<Runtime>,
        device: &str,
        helper: &Companion,
        request: Request,
        result: Value,
    ) {
        let id = request.payload["requestId"].as_str().unwrap().to_owned();
        let mut pending = HashMap::from([(
            id.clone(),
            Pending {
                command: request.payload["command"].as_str().unwrap().into(),
                action: request.action,
                result: request.result,
            },
        )]);
        commit_message(
            json!({"requestId":id,"result":result}),
            &mut pending,
            &helper.state,
            &runtime.events,
            device,
            Some(&ObservationContext {
                runtime: Arc::downgrade(runtime),
                helper: helper.id,
                device: device.into(),
            }),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn cancelled_helper_invalidates_observation_projection_before_exit_callback() {
        let (_directory, runtime, device, helper, _requests) = cached_companion().await;
        runtime.store.write().await.devices[0].status = "connected".into();
        let started = runtime
            .invoke("observation.start", json!({"deviceId":device}))
            .await
            .unwrap();
        let epoch = started["generation"].as_u64().unwrap();
        assert!(runtime.bind_observation(&device, epoch, helper.id).await);
        assert!(runtime.commit_observation(&device,helper.id,&json!({"observationEpoch":epoch,"observationEnabled":true,"notifications":{"notifications":[{"id":"old-action"}],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}}),None,None,&helper.state).await);
        helper.cancellation.cancel();
        let status = runtime
            .invoke("observation.status", json!({"deviceId":device}))
            .await
            .unwrap();
        assert_eq!(status["notifications"]["live"], false);
        assert_eq!(status["notifications"]["status"], "unknown");
        assert_eq!(status["notifications"]["notifications"], json!([]));
        let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
        assert_eq!(snapshot["observations"][0]["notifications"]["live"], false);
    }

    #[tokio::test]
    async fn wanted_observation_rebinds_after_helper_loss_and_connection_replacement() {
        tokio::time::timeout(Duration::from_secs(30), async {
            let (_directory, runtime, device, old_helper, mut old_requests) = cached_companion().await;
            runtime.store.write().await.devices[0].status = "connected".into();
            runtime.invoke("observation.start", json!({"deviceId":device})).await.unwrap();
            let request = old_requests.recv().await.unwrap();
            let old_epoch = request.payload["epoch"].as_u64().unwrap();
            wire_response(&runtime, &device, &old_helper, request, json!({"observationEpoch":old_epoch,"observationEnabled":true,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}})).await;
            old_helper.cancellation.cancel();
            runtime.observation_helper_stopped(&device, old_helper.id, "transport lost").await;
            let failed = runtime.invoke("observation.status", json!({"deviceId":device})).await.unwrap();
            assert_eq!(failed["wanted"], true);
            assert_eq!(failed["notifications"]["live"], false);

            let (sender, mut requests) = mpsc::channel(32);
            let (_, stopped) = watch::channel(false);
            let helper = Arc::new(Companion { id:uuid::Uuid::new_v4(), cancellation:CancellationToken::new(), requests:sender, state:Arc::new(RwLock::new(json!({}))), stopped });
            runtime.companions.lock().await.insert(device.clone(), helper.clone());
            let request = requests.recv().await.unwrap();
            assert_eq!(request.payload["command"], "observation.set", "recovery never replays a user action");
            let epoch = request.payload["epoch"].as_u64().unwrap();
            assert!(epoch > old_epoch);
            assert!(!runtime.commit_observation(&device,old_helper.id,&json!({"observationEpoch":epoch,"observationEnabled":true}),None,None,&old_helper.state).await);
            wire_response(&runtime,&device,&helper,request,json!({"observationEpoch":epoch,"observationEnabled":true,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}})).await;
            runtime.observation_helper_stopped(&device,old_helper.id,"late old exit").await;
            assert_eq!(runtime.observation_status(&device).await.unwrap()["notifications"]["live"],true);

            runtime.store.write().await.devices[0].status="offline".into();
            runtime.observation_connection_changed(&device).await;
            let waiting=runtime.observation_status(&device).await.unwrap();
            assert_eq!(waiting["wanted"],true);
            assert_eq!(waiting["phase"],"waiting_connection");
            assert_eq!(helper.state.read().await["notifications"]["live"],false);
            runtime.store.write().await.devices[0].status="connected".into();
            runtime.observation_connection_changed(&device).await;
            let request=requests.recv().await.unwrap();
            let reconnected_epoch=request.payload["epoch"].as_u64().unwrap();
            assert!(reconnected_epoch>epoch);
            assert!(!runtime.commit_observation(&device,helper.id,&json!({"observationEpoch":epoch,"observationEnabled":true}),None,None,&helper.state).await);
            wire_response(&runtime,&device,&helper,request,json!({"observationEpoch":reconnected_epoch,"observationEnabled":true,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}})).await;
            assert_eq!(runtime.invoke("observation.status",json!({"deviceId":device})).await.unwrap()["notifications"]["live"],true);
            assert!(runtime.commit_observation(&device,helper.id,&json!({"observationEpoch":reconnected_epoch,"observationEnabled":true,"notifications":{"notifications":[],"status":"limited","live":false,"reason":"permission changed"},"calls":{"calls":[],"status":"limited","live":true}}),None,None,&helper.state).await);
            let retry=runtime.invoke("observation.start",json!({"deviceId":device})).await.unwrap();
            assert!(retry["generation"].as_u64().unwrap()>reconnected_epoch,"explicit start retries unavailable listeners");
        }).await.expect("wanted observation recovers after bounded backoff");
    }

    #[tokio::test]
    async fn observation_stop_preserves_clipboard_media_and_rejects_late_observation_data() {
        tokio::time::timeout(Duration::from_secs(30), async {
            let (_directory,runtime,device,helper,mut requests)=cached_companion().await;
            runtime.store.write().await.devices[0].status="connected".into();
            runtime.invoke("observation.start",json!({"deviceId":device})).await.unwrap();
            let start=requests.recv().await.unwrap();
            assert_eq!(start.payload["command"],"observation.set");
            assert_eq!(start.payload["enabled"],true);
            let epoch=start.payload["epoch"].as_u64().unwrap();
            wire_response(&runtime,&device,&helper,start,json!({"observationEpoch":epoch,"observationEnabled":true,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}})).await;
            assert_eq!(runtime.invoke("observation.status",json!({"deviceId":device})).await.unwrap()["notifications"]["live"],true);
            let owner=runtime.clone();let target=device.clone();
            let late_list=tokio::spawn(async move {owner.invoke("notifications.list",json!({"deviceId":target,"allowStart":false})).await});
            let list_request=requests.recv().await.unwrap();
            assert_eq!(list_request.payload["command"],"notifications.list");
            let thumbnail=CancellationToken::new();
            runtime.device_operations.lock().await.insert(format!("thumbnail:{device}:owned"),thumbnail.clone());
            let owner=runtime.clone();let target=device.clone();
            let clipboard=tokio::spawn(async move {owner.invoke("clipboard.get",json!({"deviceId":target,"allowStart":false})).await});
            let clipboard_request=requests.recv().await.unwrap();
            assert_eq!(clipboard_request.payload["command"],"clipboard.get");
            let owner=runtime.clone();let target=device.clone();
            let stopping=tokio::spawn(async move {owner.invoke("observation.stop",json!({"deviceId":target})).await});
            let stop=requests.recv().await.unwrap();
            assert_eq!(stop.payload["command"],"observation.set");assert_eq!(stop.payload["enabled"],false);
            let stopped_epoch=stop.payload["epoch"].as_u64().unwrap();
            assert!(stopped_epoch>epoch);
            let mut events=runtime.subscribe();
            let context=ObservationContext {runtime:Arc::downgrade(&runtime),helper:helper.id,device:device.clone()};
            commit_message(json!({"event":"notifications.changed","data":{"notifications":[{"id":"late"}],"status":"available","live":true,"observationEpoch":epoch,"observationEnabled":true}}),&mut HashMap::new(),&helper.state,&runtime.events,&device,Some(&context)).await.unwrap();
            assert!(events.try_recv().is_err(),"stopped epochs cannot publish late observations");
            wire_response(&runtime,&device,&helper,stop,json!({"observationEpoch":stopped_epoch,"observationEnabled":false,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"stopped","live":false},"calls":{"calls":[],"status":"stopped","live":false}})).await;
            let stopped=stopping.await.unwrap().unwrap();assert_eq!(stopped["phase"],"stopped");assert_eq!(stopped["wanted"],false);
            wire_response(&runtime,&device,&helper,list_request,json!({"observationEpoch":epoch,"observationEnabled":true,"notifications":[{"id":"late-action"}],"status":"available","live":true})).await;
            let late_result=late_list.await.unwrap().unwrap();
            assert_eq!(late_result["status"],"stopped","an old list receipt cannot restore stopped observation authority");
            assert_eq!(late_result["live"],false);
            assert!(helper.is_active());assert!(!thumbnail.is_cancelled());assert!(!clipboard_request.result.is_closed());
            wire_response(&runtime,&device,&helper,clipboard_request,json!({"text":"still owned","available":true,"live":true})).await;
            assert_eq!(clipboard.await.unwrap().unwrap()["text"],"still owned");
            assert_eq!(runtime.invoke("notifications.list",json!({"deviceId":device,"allowStart":true})).await.unwrap()["status"],"stopped");
            assert!(requests.try_recv().is_err(),"list must not enqueue a new helper/observation request");
            runtime.store.write().await.devices[0].status="offline".into();
            runtime.observation_connection_changed(&device).await;
            runtime.store.write().await.devices[0].status="connected".into();
            runtime.observation_connection_changed(&device).await;
            tokio::task::yield_now().await;
            assert_eq!(runtime.observation_status(&device).await.unwrap()["wanted"],false);
            assert!(requests.try_recv().is_err(),"reconnecting cannot reset the stopped intent");
            runtime.invoke("observation.start",json!({"deviceId":device})).await.unwrap();
            let restarted=requests.recv().await.unwrap();
            let new_epoch=restarted.payload["epoch"].as_u64().unwrap();
            assert!(new_epoch>stopped_epoch);
            let before=runtime.events.cursor();
            assert!(!runtime.commit_observation(&device,helper.id,&json!({"observationEpoch":stopped_epoch,"observationEnabled":false}),None,None,&helper.state).await);
            assert!(!runtime.commit_observation(&device,uuid::Uuid::new_v4(),&json!({"observationEpoch":new_epoch,"observationEnabled":true}),None,None,&helper.state).await);
            assert_eq!(runtime.events.cursor().sequence,before.sequence,"old intent and foreign helper receipts cannot publish");
            wire_response(&runtime,&device,&helper,restarted,json!({"observationEpoch":new_epoch,"observationEnabled":true,"cleanupConfirmed":true,"notifications":{"notifications":[],"status":"available","live":true},"calls":{"calls":[],"status":"limited","live":true}})).await;
            assert_eq!(runtime.observation_status(&device).await.unwrap()["notifications"]["live"],true);
        }).await.expect("shared helper observation transitions must complete");
    }
}
