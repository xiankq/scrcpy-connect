//! 官方 CLI 的不可变输入、精确 Child 监督和提交未知标记；不解析 argv 或输出语义。
use super::*;
use std::sync::atomic::{AtomicU32, Ordering};
use tokio::io::AsyncWriteExt;
const OUTPUT_LIMIT: usize = 1024 * 1024;
struct Command {
    id: String,
    server: Arc<Server>,
    lease: String,
    spec: AdbServerCommandSpec,
    stop: CancellationToken,
    finished: CancellationToken,
    result: Mutex<Option<AdbServerCommandResult>>,
    retry: tokio::sync::Notify,
    #[cfg(all(test, unix))]
    failed_terminations: AtomicU32,
}
pub(in crate::api) struct CommandRecord {
    owner: Arc<Command>,
    started: bool,
    issued: bool,
    confirmed: bool,
}
fn command_result(
    status: AdbServerCommandStatus,
    reason: Option<String>,
) -> AdbServerCommandResult {
    AdbServerCommandResult {
        status,
        exit_code: None,
        stdout: vec![],
        stderr: vec![],
        error_message: reason,
    }
}
pub(in crate::api) fn create(lease: &str, spec: AdbServerCommandSpec) -> Result<String> {
    validate_command(&spec.executable, &spec.arguments)?;
    options(spec.timeout_ms, CancellationToken::new())
        .map_err(|e| error(AdbServerErrorCode::InvalidArgument, e))?;
    if spec.input.len() > OUTPUT_LIMIT || (spec.preparation && spec.may_create_transport) {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "准备命令不能创建服务器传输，输入须保持有界。",
        ));
    }
    let mut state = registry().lock().expect("adb registry");
    if state.closing {
        return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
    }
    let server = find(&state, lease)?;
    admission(server, spec.preparation)?;
    if !spec.preparation && spec.executable != server.owner.launch.executable {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "普通命令必须使用原服务器的实际可执行文件。",
        ));
    }
    if state.server_commands.len() >= 128 {
        return Err(error(AdbServerErrorCode::Closing, "官方命令登记已达上限。"));
    }
    let id = uuid::Uuid::new_v4().to_string();
    let owner = Arc::new(Command {
        id: id.clone(),
        server: server.owner.clone(),
        lease: lease.to_owned(),
        spec,
        stop: server.control.child_token(),
        finished: CancellationToken::new(),
        result: Mutex::new(None),
        retry: tokio::sync::Notify::new(),
        #[cfg(all(test, unix))]
        failed_terminations: AtomicU32::new(0),
    });
    state.server_commands.insert(
        id.clone(),
        CommandRecord {
            owner,
            started: false,
            issued: false,
            confirmed: false,
        },
    );
    Ok(id)
}
pub(in crate::api) async fn run(id: &str) -> Result<AdbServerCommandResult> {
    let owner = {
        let mut state = registry().lock().expect("adb registry");
        if state.closing {
            return Err(error(AdbServerErrorCode::Closing, "ADB 宿主正在关闭。"));
        }
        let command = state
            .server_commands
            .get(id)
            .ok_or_else(|| error(AdbServerErrorCode::NotFound, "命令登记不存在。"))?;
        let server = find(&state, &command.owner.lease)?;
        admission(server, command.owner.spec.preparation)?;
        if command.started || command.owner.stop.is_cancelled() {
            return Err(stale());
        }
        let owner = command.owner.clone();
        state.server_commands.get_mut(id).expect("命令登记").started = true;
        owner
    };
    tokio::spawn(run_command(owner.clone()));
    owner.finished.cancelled().await;
    owner
        .result
        .lock()
        .expect("命令回执")
        .clone()
        .ok_or_else(|| io_error("命令监督任务没有结果回执。"))
}
fn taint(state: &mut MobileAdbRegistry, id: &str) {
    let Some(command) = state.server_commands.get(id) else {
        return;
    };
    if command.issued && command.owner.spec.may_create_transport && !command.confirmed {
        let server_id = command.owner.server.id.clone();
        if let Some(server) = state.servers.get_mut(&server_id) {
            server.unknown = true;
        }
    }
}
fn finish_command(owner: &Command, result: AdbServerCommandResult) {
    if result.status != AdbServerCommandStatus::Exited {
        taint(&mut registry().lock().expect("adb registry"), &owner.id);
    }
    *owner.result.lock().expect("命令回执") = Some(result);
    owner.finished.cancel();
}
async fn read_output(
    reader: &mut process::Reader,
    bytes: &mut Vec<u8>,
    count: &AtomicU32,
) -> std::io::Result<()> {
    let mut buffer = [0; 8192];
    loop {
        let read = reader.read(&mut buffer).await?;
        if read == 0 {
            return Ok(());
        }
        let previous = count.fetch_add(read as u32, Ordering::Relaxed) as usize;
        if previous + read > OUTPUT_LIMIT {
            return Err(std::io::Error::other("进程输出达到上限。"));
        }
        bytes.extend_from_slice(&buffer[..read]);
    }
}
async fn run_command(owner: Arc<Command>) {
    {
        let mut state = registry().lock().expect("adb registry");
        if owner.stop.is_cancelled() {
            drop(state);
            finish_command(
                &owner,
                command_result(AdbServerCommandStatus::Cancelled, None),
            );
            return;
        }
        // 开始实际 spawn 前登记可能已提交；claim 必须等待此 worker，不能只取消等待者。
        if let Some(command) = state.server_commands.get_mut(&owner.id) {
            command.issued = true;
        }
    }
    let spawned = process::spawn(
        &owner.spec.executable,
        &owner.spec.arguments,
        &owner.server.launch.environment,
        false,
    )
    .await;
    let process::Spawned {
        mut process,
        input,
        mut output,
        mut error,
        ack: _,
    } = match spawned {
        Ok(process) => process,
        Err(error) => {
            if let Some(record) = registry()
                .lock()
                .expect("adb registry")
                .server_commands
                .get_mut(&owner.id)
            {
                record.issued = false;
            }
            finish_command(
                &owner,
                command_result(AdbServerCommandStatus::StartFailed, Some(error.to_string())),
            );
            return;
        }
    };
    #[cfg(all(test, unix))]
    process.fail_terminations(owner.failed_terminations.load(Ordering::Relaxed));
    let mut input = Some(input);
    let count = AtomicU32::new(0);
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let mut result = {
        let work = async {
            let (exit, (), (), ()) = tokio::try_join!(
                process.wait(),
                read_output(&mut output, &mut stdout, &count),
                read_output(&mut error, &mut stderr, &count),
                async {
                    let mut input = input.take().expect("唯一 stdin 所有者");
                    input.write_all(&owner.spec.input).await?;
                    input.shutdown().await?;
                    // ChildStdin 的 shutdown 只刷新；释放 FD 才能让读取到 EOF 的 CLI 退出。
                    drop(input);
                    Ok::<_, std::io::Error>(())
                }
            )?;
            Ok::<_, std::io::Error>(exit)
        };
        tokio::select! {
            biased;
            _ = owner.stop.cancelled() => command_result(AdbServerCommandStatus::Cancelled, None),
            _ = tokio::time::sleep(Duration::from_millis(owner.spec.timeout_ms.into())) => command_result(AdbServerCommandStatus::TimedOut, None),
            completed = work => match completed {
                Ok(code) => AdbServerCommandResult { exit_code: code, ..command_result(AdbServerCommandStatus::Exited, None) },
                Err(error) => {
                    let status = if count.load(Ordering::Relaxed) as usize > OUTPUT_LIMIT {
                        AdbServerCommandStatus::OutputLimit
                    } else { AdbServerCommandStatus::IoFailed };
                    command_result(status, Some(error.to_string()))
                },
            }
        }
    };
    // 先结束实际进程与本机三条管道，再发出 finished；调用方丢弃 run future 不改变此顺序。
    loop {
        if result.status != AdbServerCommandStatus::Exited
            && let Err(error) = process.terminate()
        {
            result.error_message = Some(error.to_string());
        }
        tokio::select! {
            waited = process.wait() => match waited {
                Ok(code) => { result.exit_code = code; break; },
                Err(error) => { result.error_message = Some(error.to_string()); owner.retry.notified().await; },
            },
            _ = owner.retry.notified() => {},
        }
    }
    drop((input, output, error));
    result.stdout = stdout;
    result.stderr = stderr;
    finish_command(&owner, result);
}
pub(in crate::api) fn confirm(id: &str) -> Result<()> {
    let mut state = registry().lock().expect("adb registry");
    let command = state
        .server_commands
        .get(id)
        .ok_or_else(|| error(AdbServerErrorCode::NotFound, "命令登记不存在。"))?;
    let server = find(&state, &command.owner.lease)?;
    admission(server, command.owner.spec.preparation)?;
    let result = command.owner.result.lock().expect("命令回执");
    if !matches!(
        result.as_ref(),
        Some(AdbServerCommandResult {
            status: AdbServerCommandStatus::Exited,
            exit_code: Some(0),
            ..
        })
    ) {
        return Err(error(
            AdbServerErrorCode::InvalidArgument,
            "命令尚无正常退出回执。",
        ));
    }
    drop(result);
    state
        .server_commands
        .get_mut(id)
        .expect("命令登记")
        .confirmed = true;
    Ok(())
}
pub(in crate::api) fn cancel(id: &str) {
    let mut state = registry().lock().expect("adb registry");
    if let Some(command) = state.server_commands.get(id) {
        command.owner.stop.cancel();
        command.owner.retry.notify_one();
        if !command.started {
            *command.owner.result.lock().expect("命令回执") =
                Some(command_result(AdbServerCommandStatus::Cancelled, None));
            command.owner.finished.cancel();
        }
    }
    taint(&mut state, id);
}
pub(in crate::api) async fn close(id: &str, timeout: Duration) -> Result<()> {
    cancel(id);
    let owner = registry()
        .lock()
        .expect("adb registry")
        .server_commands
        .get(id)
        .map(|entry| entry.owner.clone());
    let Some(owner) = owner else {
        return Ok(());
    };
    tokio::time::timeout(timeout, owner.finished.cancelled())
        .await
        .map_err(|_| cleanup_error())?;
    registry()
        .lock()
        .expect("adb registry")
        .server_commands
        .remove(id);
    Ok(())
}
pub(super) fn revoke_server(state: &mut MobileAdbRegistry, server: &str) -> Vec<String> {
    let ids = state
        .server_commands
        .iter()
        .filter(|(_, command)| command.owner.server.id == server)
        .map(|(id, _)| id.clone())
        .collect::<Vec<_>>();
    for id in &ids {
        let record = state.server_commands.get(id).expect("命令登记");
        record.owner.stop.cancel();
        record.owner.retry.notify_one();
        if !record.started {
            record.owner.finished.cancel();
        }
        taint(state, id);
    }
    ids
}

pub(super) fn has_pending(state: &MobileAdbRegistry, server: &str) -> bool {
    state
        .server_commands
        .values()
        .any(|command| command.owner.server.id == server && !command.owner.finished.is_cancelled())
}

#[cfg(all(test, unix))]
pub(in crate::api) fn fail_terminations_for_test(id: &str, count: u32) {
    registry()
        .lock()
        .unwrap()
        .server_commands
        .get(id)
        .unwrap()
        .owner
        .failed_terminations
        .store(count, Ordering::Relaxed);
}
