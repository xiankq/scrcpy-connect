//! 官方服务器的精确进程、可轮换控制租约和命令；不解释产品身份或 CLI 输出。
use super::*;
use std::{net::SocketAddr, path::Path};
use tokio::io::AsyncReadExt;
#[path = "server_process.rs"]
mod process;

type Result<T> = std::result::Result<T, AdbServerError>;
#[path = "server_command.rs"]
pub(super) mod command;
fn error(code: AdbServerErrorCode, message: impl Into<String>) -> AdbServerError {
    AdbServerError {
        code,
        message: message.into(),
    }
}
fn io_error(error: impl std::fmt::Display) -> AdbServerError {
    self::error(AdbServerErrorCode::Io, error.to_string())
}
fn cleanup_error() -> AdbServerError {
    error(
        AdbServerErrorCode::CleanupUnconfirmed,
        "官方 ADB 资源尚未确认释放；原身份保留以便重试。",
    )
}
fn stale() -> AdbServerError {
    error(AdbServerErrorCode::StaleLease, "官方 ADB 控制租约已失效。")
}
fn unknown() -> AdbServerError {
    error(
        AdbServerErrorCode::TransportStateUnknown,
        "服务器在途传输状态未知，只允许关闭原服务器。",
    )
}

pub(super) struct Server {
    pub(super) id: String,
    pub(super) launch: AdbServerLaunchSpec,
    pub(super) lifetime: CancellationToken,
    stop: CancellationToken,
    finished: CancellationToken,
    startup_finished: CancellationToken,
    retry: tokio::sync::Notify,
    gate: AsyncMutex<()>,
}
pub(super) struct ServerRecord {
    pub(super) owner: Arc<Server>,
    lease: String,
    admission: bool,
    control: CancellationToken,
    phase: AdbServerPhase,
    unknown: bool,
    pid: Option<u32>,
    exit_code: Option<i32>,
    startup_error: Option<String>,
    admission_scope: Option<String>,
    confirmed: bool,
}
fn info(record: &ServerRecord) -> AdbServerInfo {
    AdbServerInfo {
        server_id: record.owner.id.clone(),
        lease_id: record.lease.clone(),
        launch: record.owner.launch.clone(),
        phase: record.phase,
        transport_state_unknown: record.unknown,
        pid: record.pid,
        exit_code: record.exit_code,
    }
}
fn find<'a>(state: &'a MobileAdbRegistry, lease: &str) -> Result<&'a ServerRecord> {
    state
        .servers
        .values()
        .find(|entry| entry.lease == lease)
        .ok_or_else(stale)
}
fn admission(record: &ServerRecord, preparation: bool) -> Result<()> {
    if !record.admission || record.control.is_cancelled() {
        return Err(stale());
    }
    if record.unknown {
        return Err(unknown());
    }
    let required = if preparation {
        AdbServerPhase::Reserved
    } else {
        AdbServerPhase::Ready
    };
    if record.phase != required {
        return Err(error(
            AdbServerErrorCode::Closing,
            "官方服务器不处于此操作所需的阶段。",
        ));
    }
    Ok(())
}
fn validate_command(executable: &str, arguments: &[String]) -> Result<()> {
    if !Path::new(executable).is_absolute()
        || executable.contains('\0')
        || arguments.len() > 256
        || arguments.iter().any(|value| value.contains('\0'))
        || arguments.iter().map(String::len).sum::<usize>() > 65536
    {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "无效的进程执行输入。",
        ));
    }
    Ok(())
}
pub(super) fn create(launch: AdbServerLaunchSpec) -> Result<AdbServerInfo> {
    create_scoped(launch, None)
}
pub(super) fn create_scoped(
    mut launch: AdbServerLaunchSpec,
    scope: Option<&str>,
) -> Result<AdbServerInfo> {
    validate_command(&launch.executable, &launch.arguments)?;
    let endpoint: SocketAddr = launch
        .endpoint
        .parse()
        .map_err(|_| error(AdbServerErrorCode::InvalidArgument, "无效的服务器端点。"))?;
    if !endpoint.ip().is_loopback()
        || endpoint.port() == 0
        || launch.arguments.iter().any(|value| value == "--reply-fd")
        || launch.environment.len() > 128
        || launch
            .environment
            .iter()
            .any(|(key, value)| key.is_empty() || key.contains(['=', '\0']) || value.contains('\0'))
        || launch
            .environment
            .iter()
            .map(|(key, value)| key.len() + value.len())
            .sum::<usize>()
            > 65536
    {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "无效的服务器启动输入。",
        ));
    }
    launch.endpoint = endpoint.to_string();
    let mut state = registry().lock().expect("adb registry");
    if state.closing {
        return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
    }
    if let Some(scope) = scope {
        admission_scope::validate(&state, scope).map_err(|_| stale())?;
    }
    if state.servers.len() >= 32 {
        return Err(error(
            AdbServerErrorCode::Closing,
            "官方服务器资源登记已达上限。",
        ));
    }
    // 相同端点只能属于一个进程登记，不能在旧 Child 尚未回收时覆盖它。
    if state
        .servers
        .values()
        .any(|record| record.owner.launch.endpoint == launch.endpoint)
    {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "服务器端点已有精确进程登记。",
        ));
    }
    let owner = Arc::new(Server {
        id: uuid::Uuid::new_v4().to_string(),
        launch,
        lifetime: CancellationToken::new(),
        stop: CancellationToken::new(),
        finished: CancellationToken::new(),
        startup_finished: CancellationToken::new(),
        retry: tokio::sync::Notify::new(),
        gate: AsyncMutex::new(()),
    });
    let record = ServerRecord {
        owner: owner.clone(),
        lease: uuid::Uuid::new_v4().to_string(),
        admission: true,
        control: CancellationToken::new(),
        phase: AdbServerPhase::Reserved,
        unknown: false,
        pid: None,
        exit_code: None,
        startup_error: None,
        admission_scope: scope.map(str::to_owned),
        confirmed: scope.is_none(),
    };
    let result = info(&record);
    state.servers.insert(owner.id.clone(), record);
    Ok(result)
}
pub(super) fn list() -> Vec<AdbServerInfo> {
    let mut infos = registry()
        .lock()
        .expect("adb registry")
        .servers
        .values()
        .map(info)
        .collect::<Vec<_>>();
    infos.sort_by(|a, b| a.server_id.cmp(&b.server_id));
    infos
}
pub(super) async fn start(lease: &str, timeout_ms: u32) -> Result<AdbServerInfo> {
    let timeout = options(timeout_ms, CancellationToken::new())
        .map_err(|e| error(AdbServerErrorCode::InvalidArgument, e))?
        .timeout;
    let owner = {
        let mut state = registry().lock().expect("adb registry");
        if state.closing {
            return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
        }
        let record = find(&state, lease)?;
        admission(record, true)?;
        if command::has_pending(&state, &record.owner.id) {
            return Err(error(
                AdbServerErrorCode::Closing,
                "启动前仍有准备命令未结束。",
            ));
        }
        let owner = record.owner.clone();
        state.servers.get_mut(&owner.id).expect("精确登记").phase = AdbServerPhase::Starting;
        owner
    };
    tokio::spawn(supervise(owner.clone(), timeout));
    tokio::time::timeout(
        timeout + Duration::from_secs(7),
        owner.startup_finished.cancelled(),
    )
    .await
    .map_err(|_| cleanup_error())?;
    let state = registry().lock().expect("adb registry");
    let record = state.servers.get(&owner.id).ok_or_else(stale)?;
    if record.lease != lease {
        return Err(stale());
    }
    if let Some(error) = &record.startup_error {
        return Err(io_error(error));
    }
    if !record.admission || record.control.is_cancelled() {
        return Err(stale());
    }
    if record.phase != AdbServerPhase::Ready {
        return Err(error(AdbServerErrorCode::Closing, "官方服务器已退出。"));
    }
    Ok(info(record))
}
fn publish_exit(owner: &Server, code: Option<i32>) {
    let mut state = registry().lock().expect("adb registry");
    if let Some(record) = state.servers.get_mut(&owner.id) {
        record.phase = AdbServerPhase::Exited;
        record.admission = false;
        record.control.cancel();
        record.exit_code = code;
    }
    owner.lifetime.cancel();
    for connection in state
        .connections
        .values()
        .filter(|entry| entry.server_id.as_deref() == Some(&owner.id))
    {
        connection.scope.cancel();
        connection.client.close();
    }
}
fn startup_failed(owner: &Server, reason: impl Into<String>) {
    if let Some(record) = registry()
        .lock()
        .expect("adb registry")
        .servers
        .get_mut(&owner.id)
    {
        record.startup_error = Some(reason.into());
    }
}
/// 每次 close 重试都会重新尝试终止同一个 Child；失败不会丢失实际进程句柄。
async fn wait_server(process: &mut process::Process, owner: &Server) -> Option<i32> {
    loop {
        if let Err(error) = process.terminate() {
            startup_failed(owner, error.to_string());
        }
        tokio::select! {
            result = process.wait() => match result {
                Ok(exit) => return exit,
                Err(error) => { startup_failed(owner, error.to_string()); owner.retry.notified().await; },
            },
            _ = owner.retry.notified() => {},
        }
    }
}
async fn supervise(owner: Arc<Server>, timeout: Duration) {
    let spawned = process::spawn(
        &owner.launch.executable,
        &owner.launch.arguments,
        &owner.launch.environment,
        true,
    )
    .await;
    let process::Spawned {
        mut process,
        input,
        mut output,
        mut error,
        mut ack,
    } = match spawned {
        Ok(spawned) => spawned,
        Err(error) => {
            startup_failed(&owner, error.to_string());
            publish_exit(&owner, None);
            owner.startup_finished.cancel();
            owner.finished.cancel();
            return;
        }
    };
    drop(input);
    if let Some(record) = registry()
        .lock()
        .expect("adb registry")
        .servers
        .get_mut(&owner.id)
    {
        record.pid = process.id();
    }
    let logs_stop = CancellationToken::new();
    let out_stop = logs_stop.clone();
    let err_stop = logs_stop.clone();
    let out = tokio::spawn(async move {
        let mut sink = tokio::io::sink();
        tokio::select! {
            _ = out_stop.cancelled() => {},
            _ = tokio::io::copy(&mut output, &mut sink) => {},
        }
    });
    let err = tokio::spawn(async move {
        let mut sink = tokio::io::sink();
        tokio::select! {
            _ = err_stop.cancelled() => {},
            _ = tokio::io::copy(&mut error, &mut sink) => {},
        }
    });
    let mut received = [0; 3];
    let ready = tokio::select! {
        biased;
        _ = owner.stop.cancelled() => Err("服务器启动已取消。".to_owned()),
        _ = tokio::time::sleep(timeout) => Err("服务器启动回执超时。".to_owned()),
        exited = process.wait() => Err(format!("服务器在启动回执前退出：{exited:?}")),
        result = ack.as_mut().expect("专用 ACK").read_exact(&mut received) => match result {
            Ok(_) if received == *b"OK\n" => Ok(()),
            Ok(_) => Err("服务器启动回执无效。".to_owned()),
            Err(error) => Err(error.to_string()),
        },
    };
    drop(ack);
    if let Err(reason) = ready {
        startup_failed(&owner, reason);
    } else {
        if let Some(record) = registry()
            .lock()
            .expect("adb registry")
            .servers
            .get_mut(&owner.id)
        {
            // claim 可先撤销旧准入，但启动结果只记录事实，不重新放行旧控制租约。
            record.phase = AdbServerPhase::Ready;
        }
        owner.startup_finished.cancel();
        tokio::select! {
            _ = owner.stop.cancelled() => {},
            _ = process.wait() => {},
        }
    }
    let exit = wait_server(&mut process, &owner).await;
    logs_stop.cancel();
    let _ = tokio::join!(out, err);
    publish_exit(&owner, exit);
    owner.startup_finished.cancel();
    owner.finished.cancel();
}
pub(super) fn revoke_all(state: &mut MobileAdbRegistry) -> Vec<String> {
    let leases = state
        .servers
        .values_mut()
        .map(|server| {
            server.admission = false;
            server.control.cancel();
            server.lease.clone()
        })
        .collect::<Vec<_>>();
    let server_ids = state.servers.keys().cloned().collect::<Vec<_>>();
    for id in server_ids {
        command::revoke_server(state, &id);
    }
    leases
}
fn lease_owner(lease: &str) -> Option<Arc<Server>> {
    find(&registry().lock().expect("adb registry"), lease)
        .ok()
        .map(|entry| entry.owner.clone())
}
pub(super) async fn claim(lease: &str, timeout: Duration) -> Result<AdbServerInfo> {
    claim_scoped(lease, None, timeout).await
}
pub(super) async fn claim_scoped(
    lease: &str,
    scope: Option<&str>,
    timeout: Duration,
) -> Result<AdbServerInfo> {
    let owner = lease_owner(lease).ok_or_else(stale)?;
    tokio::time::timeout(timeout, async {
        let _gate = owner.gate.lock().await;
        let (commands, handshakes, phase) = {
            let mut state = registry().lock().expect("adb registry");
            if state.closing {
                return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
            }
            if let Some(scope) = scope {
                admission_scope::validate(&state, scope).map_err(|_| stale())?;
            }
            let server = state.servers.get(&owner.id).ok_or_else(stale)?;
            if server.lease != lease || (scope.is_none() && server.admission_scope.is_some()) {
                return Err(stale());
            }
            if scope.is_some() {
                // 尚未交付的准备资源不能绕过其准入域被另一调用方认领。
                if !server.confirmed && server.admission_scope.as_deref() != scope {
                    return Err(stale());
                }
                if server.admission_scope.as_deref().is_some_and(|old| {
                    state
                        .admission_scopes
                        .values()
                        .any(|entry| entry.id == old && !entry.accepting)
                }) {
                    return Err(error(AdbServerErrorCode::Closing, "原准入域仍在排空。"));
                }
            }
            let server = state.servers.get_mut(&owner.id).ok_or_else(stale)?;
            if server.lease != lease {
                return Err(stale());
            }
            server.admission = false;
            server.control.cancel();
            if let Some(scope) = scope {
                // 先登记新调用方尚未确认的交付责任，再让出执行权排空旧工作。
                server.admission_scope = Some(scope.to_owned());
                server.confirmed = false;
            }
            let phase = server.phase;
            (
                command::revoke_server(&mut state, &owner.id),
                handshake::revoke_server(&state, &owner.id),
                phase,
            )
        };
        for command in commands {
            command::close(&command, timeout).await?;
        }
        for handshake in handshakes {
            handshake::close(&handshake, timeout)
                .await
                .map_err(|_| cleanup_error())?;
        }
        if phase == AdbServerPhase::Starting {
            owner.startup_finished.cancelled().await;
        }
        let mut state = registry().lock().expect("adb registry");
        if state.closing {
            return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
        }
        if let Some(scope) = scope {
            admission_scope::validate(&state, scope).map_err(|_| stale())?;
        }
        let server = state.servers.get_mut(&owner.id).ok_or_else(stale)?;
        if server.lease != lease {
            return Err(stale());
        }
        server.lease = uuid::Uuid::new_v4().to_string();
        server.control = CancellationToken::new();
        server.admission = server.phase != AdbServerPhase::Exited;
        Ok(info(server))
    })
    .await
    .map_err(|_| cleanup_error())?
}

pub(super) fn confirm(lease: &str, scope: &str) -> Result<()> {
    let mut state = registry().lock().expect("adb registry");
    admission_scope::validate(&state, scope).map_err(|_| stale())?;
    let server = find(&state, lease)?;
    if server.admission_scope.as_deref() != Some(scope) {
        return Err(stale());
    }
    admission(server, false)?;
    let id = server.owner.id.clone();
    state.servers.get_mut(&id).expect("精确登记").confirmed = true;
    Ok(())
}

pub(super) struct ScopeRetirement {
    lease: String,
    confirmed: bool,
    commands: Vec<String>,
    handshakes: Vec<String>,
}

/// 调用方持有同一登记锁；撤销快照之后，旧 scope 无法再发布服务器或工作。
pub(super) fn revoke_scope(state: &mut MobileAdbRegistry, scope: &str) -> Vec<ScopeRetirement> {
    let servers = state
        .servers
        .values_mut()
        .filter_map(|server| {
            if server.admission_scope.as_deref() != Some(scope) {
                return None;
            }
            server.admission = false;
            server.control.cancel();
            Some((
                server.owner.id.clone(),
                server.lease.clone(),
                server.confirmed,
            ))
        })
        .collect::<Vec<_>>();
    servers
        .into_iter()
        .map(|(id, lease, confirmed)| ScopeRetirement {
            lease,
            confirmed,
            commands: command::revoke_server(state, &id),
            handshakes: handshake::revoke_server(state, &id),
        })
        .collect()
}

pub(super) async fn drain_scope(servers: Vec<ScopeRetirement>, timeout: Duration) -> Result<()> {
    let mut failure = None;
    for server in servers {
        if !server.confirmed {
            if let Err(error) = close(&server.lease, timeout).await {
                failure.get_or_insert(error);
            }
            continue;
        }
        // 明确交付的 Child 与运行期连接保留，旧 CLI 和未交付握手仍必须实际排空。
        for command in server.commands {
            if let Err(error) = command::close(&command, timeout).await {
                failure.get_or_insert(error);
            }
        }
        for handshake in server.handshakes {
            if handshake::close(&handshake, timeout).await.is_err() {
                failure.get_or_insert_with(cleanup_error);
            }
        }
    }
    failure.map_or(Ok(()), Err)
}
fn closing_diagnostic(stage: &Mutex<String>) -> AdbServerError {
    error(
        AdbServerErrorCode::CleanupUnconfirmed,
        format!(
            "官方 ADB 资源尚未确认释放（{}）；原身份保留以便重试。",
            stage.lock().expect("关闭阶段")
        ),
    )
}
pub(super) async fn close(lease: &str, timeout: Duration) -> Result<()> {
    let Some(owner) = lease_owner(lease) else {
        return Ok(());
    };
    let stage = Mutex::new("等待原服务器交接锁".to_owned());
    tokio::time::timeout(timeout, async {
        let _gate = owner.gate.lock().await;
        let (commands, handshakes, connections, reserved) = {
            let mut state = registry().lock().expect("adb registry");
            let Some(server) = state.servers.get_mut(&owner.id) else {
                return Ok(());
            };
            if server.lease != lease {
                return Ok(());
            }
            server.admission = false;
            server.control.cancel();
            // 先撤销所有权和服务准入；原 Child 留到流与 CLI 排空后才终止。
            owner.lifetime.cancel();
            let reserved = server.phase == AdbServerPhase::Reserved;
            let commands = command::revoke_server(&mut state, &owner.id);
            let handshakes = handshake::revoke_server(&state, &owner.id);
            let connections = state
                .connections
                .iter()
                .filter(|(_, entry)| entry.server_id.as_deref() == Some(&owner.id))
                .map(|(id, entry)| {
                    entry.scope.cancel();
                    id.clone()
                })
                .collect::<Vec<_>>();
            (commands, handshakes, connections, reserved)
        };
        for command in commands {
            *stage.lock().expect("关闭阶段") = format!("排空命令 {command}");
            command::close(&command, timeout).await.map_err(|failure| {
                if failure.code == AdbServerErrorCode::CleanupUnconfirmed {
                    closing_diagnostic(&stage)
                } else {
                    failure
                }
            })?;
        }
        for handshake in handshakes {
            *stage.lock().expect("关闭阶段") = format!("排空握手 {handshake}");
            handshake::close(&handshake, timeout)
                .await
                .map_err(|_| closing_diagnostic(&stage))?;
        }
        for connection in connections {
            *stage.lock().expect("关闭阶段") = format!("排空连接 {connection}");
            adb_disconnect(connection)
                .await
                .map_err(|_| closing_diagnostic(&stage))?;
        }
        *stage.lock().expect("关闭阶段") = "等待原 Child 实际退出及日志流释放".to_owned();
        owner.stop.cancel();
        owner.retry.notify_one();
        if reserved {
            publish_exit(&owner, None);
            owner.finished.cancel();
            owner.startup_finished.cancel();
        }
        owner.finished.cancelled().await;
        registry()
            .lock()
            .expect("adb registry")
            .servers
            .remove(&owner.id);
        Ok(())
    })
    .await
    .map_err(|_| closing_diagnostic(&stage))?
}

/// 该信息只在同一个 ADB 登记锁内校验和使用，不能变成分离的准入快照。
#[derive(Clone)]
pub(super) struct HandshakeOwner {
    pub(super) server_id: String,
    pub(super) lease: String,
}
pub(super) fn handshake_admission(
    state: &MobileAdbRegistry,
    lease: &str,
) -> Result<(HandshakeOwner, CancellationToken)> {
    let server = find(state, lease)?;
    admission(server, false)?;
    Ok((
        HandshakeOwner {
            server_id: server.owner.id.clone(),
            lease: lease.to_owned(),
        },
        server.control.child_token(),
    ))
}
pub(super) fn validate_handshake(
    state: &MobileAdbRegistry,
    endpoint: SocketAddr,
    owner: Option<&HandshakeOwner>,
) -> std::result::Result<(), String> {
    let managed = state
        .servers
        .values()
        .find(|server| server.owner.launch.endpoint.parse::<SocketAddr>().ok() == Some(endpoint));
    match (managed, owner) {
        (None, None) => Ok(()),
        (Some(server), Some(owner))
            if owner.server_id == server.owner.id && owner.lease == server.lease =>
        {
            admission(server, false).map_err(|e| e.to_string())
        }
        _ => Err("adb_server_lease_invalid".into()),
    }
}
pub(super) fn publish_connection(
    client: Client,
    serial: String,
    owner: Option<HandshakeOwner>,
    endpoint: SocketAddr,
) -> std::result::Result<AdbDeviceInfo, String> {
    let mut state = registry().lock().expect("adb registry");
    if let Err(error) = validate_handshake(&state, endpoint, owner.as_ref()) {
        client.close();
        return Err(error);
    }
    if state.closing {
        client.close();
        return Err("adb_host_closing".into());
    }
    let server_id = owner.map(|owner| owner.server_id);
    insert_locked(&mut state, client, serial, true, server_id)
}

#[cfg(all(test, unix))]
mod termination_tests {
    use super::*;
    #[tokio::test]
    async fn failed_termination_retains_the_actual_child_until_explicit_retry() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let server = create(AdbServerLaunchSpec {
            executable: "/bin/sh".into(),
            arguments: vec![],
            environment: HashMap::new(),
            endpoint: listener.local_addr().unwrap().to_string(),
        })
        .unwrap();
        let owner = lease_owner(&server.lease_id).unwrap();
        let spawned = process::spawn(
            "/bin/sh",
            &["-c".into(), "exec sleep 60".into()],
            &HashMap::new(),
            false,
        )
        .await
        .unwrap();
        let process::Spawned {
            mut process,
            input,
            output,
            error,
            ack: _,
        } = spawned;
        drop((input, output, error));
        process.fail_terminations(1);
        let retained = owner.clone();
        let mut waiting = tokio::spawn(async move { wait_server(&mut process, &retained).await });
        assert!(
            tokio::time::timeout(Duration::from_millis(20), &mut waiting)
                .await
                .is_err(),
            "首败不能丢弃 Child 或报告完成"
        );
        assert!(
            registry()
                .lock()
                .unwrap()
                .servers
                .get(&owner.id)
                .unwrap()
                .startup_error
                .is_some()
        );
        owner.retry.notify_one();
        tokio::time::timeout(Duration::from_secs(2), waiting)
            .await
            .unwrap()
            .unwrap();
        close(&server.lease_id, Duration::from_secs(2))
            .await
            .unwrap();
    }
}

#[cfg(test)]
pub(super) fn is_finished_for_test(owner: &Server) -> bool {
    owner.finished.is_cancelled()
}
