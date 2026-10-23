//! One control-only keep-active process per device, independent of capture
//! generations. The official server uses userActivity, never a wake/lock action.
use super::*;
use std::collections::HashMap;

#[derive(Default)]
pub(crate) struct KeepActiveOwner {
    devices: Mutex<HashMap<String, Arc<DeviceLease>>>,
}
impl KeepActiveOwner {
    async fn device(&self, id: &str) -> Arc<DeviceLease> {
        self.devices
            .lock()
            .await
            .entry(id.into())
            .or_default()
            .clone()
    }
}
#[derive(Default)]
struct DeviceLease {
    lease: Mutex<Option<Lease>>,
    wanted: AtomicBool,
}
struct Lease {
    id: String,
    client: interop_adb::Client,
    cancellation: CancellationToken,
    closed: Arc<AtomicBool>,
    process: OwnedProcess,
}
impl Drop for Lease {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}
impl Lease {
    fn active(&self) -> bool {
        !self.client.is_closed()
            && !self.cancellation.is_cancelled()
            && !self.closed.load(Ordering::Acquire)
    }
    async fn stop(&self) -> CoreResult<()> {
        self.cancellation.cancel();
        tokio::time::timeout(Duration::from_secs(3), async {
            while !self.closed.load(Ordering::Acquire) {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .map_err(|_| CoreError::new("keep_active_cleanup", "保持唤醒服务仍在释放。"))?;
        // Only the launcher's owned job is signalled by managed_shell_command.
        // Never kill a retained numeric PID. Verify its exact identity has gone
        // using the original connection, never a subsequent reconnected client.
        let identity = quote(&format!(
            "interop.scrcpy:{}:{}",
            self.process.scid, self.process.jar
        ))?;
        let command = format!(
            r#"p={pid}
remaining=40
while [ "$remaining" -gt 0 ]; do
    [ -d /proc/$p ] || {{ echo __KEEP_ACTIVE_RELEASED__; exit 0; }}
    IFS= read -r stat < /proc/$p/stat || exit 43
    rest=${{stat##*) }}; set -- $rest; state=$1; shift 19 || exit 43
    if [ "$1" != {started} ]; then echo __KEEP_ACTIVE_RELEASED__; exit 0; fi
    case "$state" in Z|X) echo __KEEP_ACTIVE_RELEASED__; exit 0 ;; esac
    IFS= read -r -d '' cmd < /proc/$p/cmdline || exit 43
    if [ "$cmd" != {identity} ]; then echo __KEEP_ACTIVE_RELEASED__; exit 0; fi
    remaining=$((remaining - 1)); sleep .05
done
exit 43"#,
            pid = self.process.pid,
            started = self.process.started
        );
        let output = self
            .client
            .shell(
                &command,
                4096,
                OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                },
            )
            .await?;
        if !output.stdout.starts_with(b"__KEEP_ACTIVE_RELEASED__")
            || output.exit_code.is_some_and(|code| code != 0)
        {
            return Err(CoreError::new(
                "keep_active_cleanup",
                "尚未确认保持唤醒服务已退出，请检查设备连接。",
            ));
        }
        Ok(())
    }
}

fn command(path: &str, scid: u32) -> CoreResult<String> {
    Ok(format!(
        "CLASSPATH={} exec app_process / --nice-name={} com.genymobile.scrcpy.Server 5.0.1 scid={scid:08x} log_level=warn video=false audio=false control=true display_id=0 keep_active=true power_on=false power_off_on_close=false stay_awake=false clipboard_autosync=false tunnel_forward=true cleanup=false send_dummy_byte=true send_device_meta=false",
        quote(path)?,
        quote(&format!("interop.scrcpy:{scid:08x}:{path}"))?
    ))
}
async fn start(
    client: interop_adb::Client,
    activities: Arc<crate::activities::ActivityOwner>,
    device: &str,
    events: crate::events::EventBus,
    intent: Arc<DeviceLease>,
) -> CoreResult<Lease> {
    let id = uuid::Uuid::new_v4().to_string();
    let path = format!("/data/local/tmp/interop-keep-active-{id}.jar");
    let scid =
        u32::from_be_bytes(uuid::Uuid::new_v4().as_bytes()[..4].try_into().unwrap()) & 0x7fff_ffff;
    let cancellation = CancellationToken::new();
    let mut guard = CancelOnDrop(Some(cancellation.clone()));
    let server = crate::bundled_servers::get("scrcpy")?;
    let launched = std::sync::Mutex::new(None::<OwnedProcess>);
    let operation = async {
        let mut sync = client.sync(options(&cancellation)).await?;
        sync.push_compressed(
            &RemotePath::new(&path)?,
            &mut &server[..],
            0o644,
            now().min(u32::MAX as u64) as u32,
            server.len() as u64,
            super::server_upload_compression(&client.info().features),
        )
        .await?;
        drop(sync);
        let mut shell = client
            .exec(
                &managed_shell_command(&path, &command(&path, scid)?, true)?,
                options(&cancellation),
            )
            .await?;
        let mut line = Vec::new();
        loop {
            let mut byte = [0];
            shell.read_exact(&mut byte).await?;
            let byte = byte[0];
            if byte == b'\n' {
                break;
            }
            line.push(byte);
            if line.len() > 64 {
                return Err(CoreError::new("process_identity", "保持唤醒进程身份无效。"));
            }
        }
        let (pid, started) = launch_identity(&line)?;
        *launched.lock().expect("keep-active process identity") = Some(OwnedProcess {
            pid,
            started,
            jar: path.clone(),
            scid: format!("{scid:08x}"),
        });
        let socket = RemoteSocket::LocalAbstract(format!("scrcpy_{scid:08x}"));
        let mut control = loop {
            if client.is_closed() {
                return Err(CoreError::new("disconnected", "保持唤醒所属连接已结束。"));
            }
            match tokio::time::timeout(
                Duration::from_millis(400),
                client.connect_socket(&socket, options(&cancellation)),
            )
            .await
            {
                Ok(Ok(stream)) => break stream,
                _ => tokio::time::sleep(Duration::from_millis(40)).await,
            }
        };
        let mut dummy = [0];
        control.read_exact(&mut dummy).await?;
        if dummy != [0] {
            return Err(CoreError::new(
                "keep_active_protocol",
                "保持唤醒控制通道握手无效。",
            ));
        }
        let process =
            OwnedProcess::capture(&client, pid, started, &path, format!("{scid:08x}")).await?;
        let closed = Arc::new(AtomicBool::new(false));
        let done = closed.clone();
        let cancel = cancellation.clone();
        let owner = Arc::downgrade(&activities);
        let monitor_id = id.clone();
        let monitor_device = device.to_owned();
        tokio::spawn(async move {
            let mut logs = [0; 4096];
            let mut control_bytes = [0; 256];
            loop {
                tokio::select! {
                    _=cancel.cancelled()=>break,
                    result=shell.read(&mut logs)=>if matches!(result,Ok(0)|Err(_)) {break;},
                    result=control.read(&mut control_bytes)=>if matches!(result,Ok(0)|Err(_)) {break;},
                }
            }
            let unexpected = !cancel.is_cancelled();
            cancel.cancel();
            drop(control);
            drop(shell);
            done.store(true, Ordering::Release);
            if unexpected && let Some(owner) = owner.upgrade() {
                let slot = owner.keep_active.device(&monitor_device).await;
                let current = slot.lease.lock().await;
                if current.as_ref().is_some_and(|lease| lease.id == monitor_id) {
                    for session in owner
                        .sessions
                        .lock()
                        .await
                        .values()
                        .filter(|session| session.device_id == monitor_device)
                    {
                        let mut state = session.state.write().await;
                        state["keepActiveApplied"] = json!(false);
                        state["keepActiveLeaseActive"] = json!(false);
                        state["keepActiveError"] = json!({"code":"keep_active_ended","reason":"保持唤醒控制服务已结束，画面仍可关闭或重试。"});
                        event(&events, "session.updated", &monitor_device, state.clone());
                    }
                }
            }
        });
        Ok::<_, CoreError>(Lease {
            id,
            client: client.clone(),
            cancellation: cancellation.clone(),
            closed,
            process,
        })
    };
    let mut result = tokio::select! {
        result = tokio::time::timeout(Duration::from_secs(12), operation) => result.unwrap_or_else(|_|Err(CoreError::new("keep_active_timeout", "保持唤醒控制通道未及时就绪。"))),
        _ = async {
            while intent.wanted.load(Ordering::Acquire) && !client.is_closed() && owns_window(&activities,device).await { tokio::time::sleep(Duration::from_millis(20)).await; }
        } => Err(CoreError::new("cancelled", "最后画面或设备连接已结束，未保留保持唤醒服务。")),
    };
    if result.is_ok() {
        guard.0 = None;
    }
    if result.is_err() {
        cancellation.cancel();
        let process = launched
            .lock()
            .expect("keep-active process identity")
            .clone();
        if let Some(process) = process {
            let failed = Lease {
                id: String::new(),
                client: client.clone(),
                cancellation: cancellation.clone(),
                closed: Arc::new(AtomicBool::new(true)),
                process,
            };
            if let Err(cleanup) = failed.stop().await
                && let Err(error) = &mut result
            {
                error.details = json!({"cleanupConfirmed":false,"cleanupReason":cleanup.message});
            }
        }
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

async fn owns_window(activities: &crate::activities::ActivityOwner, device: &str) -> bool {
    for session in activities.sessions.lock().await.values() {
        if session.device_id == device && !session.lifetime.is_cancelled() {
            let state = session.state.read().await;
            if !session.cancellation.is_cancelled()
                || state["qualityRetryable"] == true
                || state["qualityRebuilding"] == true
            {
                return true;
            }
        }
    }
    false
}

pub(super) async fn stop_unowned(
    activities: &crate::activities::ActivityOwner,
    events: &crate::events::EventBus,
    device: &str,
) -> CoreResult<Value> {
    Box::pin(stop_unowned_inner(activities, events, device)).await
}
async fn stop_unowned_inner(
    activities: &crate::activities::ActivityOwner,
    events: &crate::events::EventBus,
    device: &str,
) -> CoreResult<Value> {
    let slot = activities.keep_active.device(device).await;
    let mut lease = slot.lease.lock().await;
    if owns_window(activities, device).await || lease.is_none() {
        return Ok(json!({"required":false}));
    }
    let current = lease.as_ref().expect("unowned lease selected for release");
    let mut receipt = json!({"required":true,"leaseId":current.id,
        "pid":current.process.pid,"connectionId":current.client.connection_id().to_string()});
    if let Err(mut error) = current.stop().await {
        receipt["status"] = json!("cleanup_unconfirmed");
        receipt["cleanupConfirmed"] = json!(false);
        receipt["keepActiveApplied"] = json!(false);
        receipt["releasePending"] = json!(true);
        receipt["error"] =
            json!({"code":error.code,"reason":error.message,"details":error.details});
        // No remaining window can carry this observation. Preserve the exact
        // original lease even after a disconnect and publish device-owned fact.
        // A later verification must never query/kill a PID on a new connection.
        event(
            events,
            "device.keep_active.updated",
            device,
            receipt.clone(),
        );
        error.details = receipt;
        return Err(error);
    }
    lease.take();
    receipt["status"] = json!("released");
    receipt["cleanupConfirmed"] = json!(true);
    receipt["releasePending"] = json!(false);
    event(
        events,
        "device.keep_active.updated",
        device,
        receipt.clone(),
    );
    Ok(receipt)
}

impl Runtime {
    pub(crate) async fn sync_changed_keep_active(&self, devices: Vec<String>) -> CoreResult<()> {
        let mut failures = Vec::new();
        for device in devices {
            if let Err(error) = Box::pin(self.sync_keep_active(&device, Some(false))).await {
                failures.push(json!({"deviceId":device,"code":error.code,"reason":error.message,"details":error.details}));
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            let mut error = CoreError::new(
                "keep_active_partial",
                "设置已保存，部分设备的保持唤醒服务尚未应用，请检查连接后重试。",
            );
            error.details = json!({"saved":true,"action":"keep_active","failures":failures});
            Err(error)
        }
    }

    pub(crate) async fn sync_keep_active(
        &self,
        device: &str,
        fallback: Option<bool>,
    ) -> CoreResult<Value> {
        Box::pin(self.apply_keep_active(device, fallback)).await
    }
    async fn apply_keep_active(&self, device: &str, fallback: Option<bool>) -> CoreResult<Value> {
        let slot = self.activities.keep_active.device(device).await;
        // Publish the latest saved intent before waiting behind startup. A
        // disable cancels a pending handshake rather than admitting a late job.
        let wanted = self.store.read().await.settings["deviceSettings"][device]["stayAwake"]
            .as_bool()
            .unwrap_or(fallback.unwrap_or_else(|| slot.wanted.load(Ordering::Acquire)));
        slot.wanted.store(wanted, Ordering::Release);
        let mut lease = slot.lease.lock().await;
        let enabled = self.store.read().await.settings["deviceSettings"][device]["stayAwake"]
            .as_bool()
            .unwrap_or(fallback.unwrap_or_else(|| slot.wanted.load(Ordering::Acquire)));
        slot.wanted.store(enabled, Ordering::Release);
        let owns = owns_window(&self.activities, device).await;
        let applied: CoreResult<()> = async {
            let client = if enabled && owns {
                Some(self.client(device).await?)
            } else {
                None
            };
            if lease.as_ref().is_some_and(|current| {
                !enabled
                    || !owns
                    || !current.active()
                    || client.as_ref().is_some_and(|client| {
                        client.connection_id() != current.client.connection_id()
                    })
            }) {
                let previous = lease.as_ref().expect("lease selected for release");
                if let Err(error) = previous.stop().await
                    && !previous.client.is_closed()
                {
                    return Err(error);
                }
                lease.take();
            }
            if enabled && owns && lease.is_none() {
                let current = Box::pin(start(
                    client.expect("enabled owner has connection"),
                    self.activities.clone(),
                    device,
                    self.events.clone(),
                    slot.clone(),
                ))
                .await?;
                // A close/disconnect during upload cannot acquire a late lease.
                if !owns_window(&self.activities, device).await {
                    current.stop().await?;
                } else {
                    *lease = Some(current);
                }
            }
            Ok(())
        }
        .await;
        let active = lease.as_ref().is_some_and(Lease::active);
        let receipt = json!({"keepActive":enabled,"keepActiveApplied":applied.is_ok() && (enabled==active || !owns),
            "keepActiveLeaseActive":active,"keepActiveLeaseId":lease.as_ref().map(|lease|&lease.id),
            "keepActivePid":lease.as_ref().map(|lease|lease.process.pid),
            "keepActiveConnectionId":lease.as_ref().map(|lease|lease.client.connection_id().to_string()),
            "keepActiveError":applied.as_ref().err().map(|error|json!({"code":error.code,"reason":error.message}))});
        for session in self
            .activities
            .sessions
            .lock()
            .await
            .values()
            .filter(|session| session.device_id == device)
        {
            let mut state = session.state.write().await;
            for (key, value) in receipt.as_object().unwrap() {
                state[key] = value.clone();
            }
            self.emit("session.updated", Some(device), state.clone());
        }
        match applied {
            Ok(()) => Ok(receipt),
            Err(mut error) => {
                if !error.details.is_object() {
                    error.details = json!({});
                }
                for (key, value) in receipt.as_object().expect("keep-active receipt") {
                    error.details[key] = value.clone();
                }
                Err(error)
            }
        }
    }
}

#[cfg(test)]
#[path = "scrcpy_keep_active_tests.rs"]
mod tests;
