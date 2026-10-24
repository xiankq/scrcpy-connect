//! 握手的单次准入与真实完成；运行期 Client 使用独立取消令牌。
use super::*;
use std::future::Future;

const LIMIT: usize = 128;

pub(super) struct Registration {
    state: Arc<State>,
    started: bool,
    owner: Option<server_owner::HandshakeOwner>,
    admission_scope: Option<String>,
    unconfirmed_connection: Option<String>,
    rejected_client: Option<Client>,
}

pub(super) struct State {
    stop: CancellationToken,
    finished: CancellationToken,
}

struct Guard {
    id: String,
    state: Arc<State>,
    anonymous: bool,
    owner: Option<server_owner::HandshakeOwner>,
}

impl Drop for Guard {
    fn drop(&mut self) {
        self.state.finished.cancel();
        if self.anonymous {
            remove(&self.id, &self.state);
        }
    }
}

fn register(state: &mut MobileAdbRegistry, started: bool) -> Result<(String, Arc<State>), String> {
    if state.closing {
        return Err("adb_host_closing".into());
    }
    if state.handshakes.len() >= LIMIT {
        return Err("adb_handshake_limit".into());
    }
    let id = uuid::Uuid::new_v4().to_string();
    let handshake = Arc::new(State {
        stop: CancellationToken::new(),
        finished: CancellationToken::new(),
    });
    state.handshakes.insert(
        id.clone(),
        Registration {
            state: handshake.clone(),
            started,
            owner: None,
            admission_scope: None,
            unconfirmed_connection: None,
            rejected_client: None,
        },
    );
    Ok((id, handshake))
}

pub(super) fn create() -> Result<String, String> {
    let mut state = registry().lock().expect("adb registry");
    register(&mut state, false).map(|(id, _)| id)
}

pub(super) fn create_scoped(scope: &str) -> Result<String, String> {
    let mut state = registry().lock().expect("adb registry");
    admission_scope::validate(&state, scope)?;
    let (id, _) = register(&mut state, false)?;
    state
        .handshakes
        .get_mut(&id)
        .expect("刚创建的握手")
        .admission_scope = Some(scope.into());
    Ok(id)
}

pub(super) fn require_scope(id: &str) -> Result<(), String> {
    let state = registry().lock().expect("adb registry");
    validate_registration(&state, id)?;
    if state
        .handshakes
        .get(id)
        .is_some_and(|entry| entry.admission_scope.is_some())
    {
        Ok(())
    } else {
        Err("adb_handshake_scope_required".into())
    }
}

/// 与注册连接共享同一个锁，旧权限不能在交接快照后发布迟到 Client。
pub(super) fn validate_registration(state: &MobileAdbRegistry, id: &str) -> Result<(), String> {
    validate_connection_registration(state, id).map_err(|error| error.message)
}

fn validate_connection_registration(
    state: &MobileAdbRegistry,
    id: &str,
) -> Result<(), AdbConnectionError> {
    let entry = state
        .handshakes
        .get(id)
        .ok_or_else(|| AdbConnectionError::admission("adb_handshake_closed"))?;
    if entry.state.stop.is_cancelled() {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::Cancelled,
            "adb_handshake_cancelled",
        ));
    }
    if let Some(scope) = &entry.admission_scope {
        admission_scope::validate(state, scope).map_err(AdbConnectionError::admission)?;
    }
    Ok(())
}

pub(super) fn retain_connection(state: &mut MobileAdbRegistry, handshake: &str, connection: &str) {
    if let Some(entry) = state.handshakes.get_mut(handshake)
        && entry.admission_scope.is_some()
    {
        entry.unconfirmed_connection = Some(connection.into());
        state
            .connections
            .get_mut(connection)
            .expect("刚登记的连接")
            .accepting = false;
    }
}

pub(super) fn has_unconfirmed_connection(state: &MobileAdbRegistry, connection: &str) -> bool {
    state
        .handshakes
        .values()
        .any(|entry| entry.unconfirmed_connection.as_deref() == Some(connection))
}

pub(super) fn publish_connection(
    handshake: Option<&str>,
    client: Client,
    serial: String,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    let mut state = registry().lock().expect("adb registry");
    if let Some(id) = handshake {
        let failure = validate_connection_registration(&state, id)
            .err()
            .or_else(|| {
                if state.closing {
                    Some(AdbConnectionError::admission("adb_host_closing"))
                } else if state.connections.len() >= 64 {
                    Some(AdbConnectionError::admission("adb_connection_limit"))
                } else {
                    None
                }
            });
        if let Some(error) = failure {
            if let Some(entry) = state.handshakes.get_mut(id) {
                // 迟到 Client 尚未对外发布，仍登记真实关闭权；scope 接管必须等 driver 退出。
                client.close();
                entry.rejected_client = Some(client);
            } else {
                client.close();
            }
            return Err(error);
        }
    }
    let info = insert_locked(&mut state, client, serial, true, None)
        .map_err(AdbConnectionError::admission)?;
    if let Some(id) = handshake {
        retain_connection(&mut state, id, &info.id);
    }
    Ok(info)
}

pub(super) fn confirm_connection(
    handshake: &str,
    connection: &str,
) -> Result<(), AdbConnectionError> {
    let mut state = registry().lock().expect("adb registry");
    validate_connection_registration(&state, handshake)?;
    let entry = state
        .handshakes
        .get(handshake)
        .ok_or_else(|| AdbConnectionError::admission("adb_handshake_closed"))?;
    if entry.unconfirmed_connection.as_deref() != Some(connection) {
        return Err(AdbConnectionError::admission(
            "adb_handshake_connection_mismatch",
        ));
    }
    // 权限和确认在同一登记锁内核验；只记录实际 scoped 交付，借用或相同端点不继承归属。
    let scope_key = entry.admission_scope.as_ref().map(|id| {
        state
            .admission_scopes
            .iter()
            .find(|(_, scope)| scope.id == *id)
            .map(|(name, _)| name.clone())
            .expect("已验证的当前准入域")
    });
    let connection = state
        .connections
        .get_mut(connection)
        .ok_or_else(|| AdbConnectionError::admission("adb_connection_closed"))?;
    if connection.scope.is_cancelled() || connection.client.is_closed() {
        return Err(AdbConnectionError::admission("adb_connection_closed"));
    }
    connection.admission_scope_key = scope_key;
    connection.accepting = true;
    state
        .handshakes
        .get_mut(handshake)
        .expect("已核对的握手")
        .unconfirmed_connection = None;
    Ok(())
}

pub(super) fn create_server(lease: &str) -> Result<String, AdbServerError> {
    let mut state = registry().lock().expect("adb registry");
    if state.closing || state.handshakes.len() >= LIMIT {
        return Err(AdbServerError {
            code: AdbServerErrorCode::Closing,
            message: "ADB 握手登记暂不接受新操作。".into(),
        });
    }
    let (owner, stop) = server_owner::handshake_admission(&state, lease)?;
    let id = uuid::Uuid::new_v4().to_string();
    state.handshakes.insert(
        id.clone(),
        Registration {
            state: Arc::new(State {
                stop,
                finished: CancellationToken::new(),
            }),
            started: false,
            owner: Some(owner),
            admission_scope: None,
            unconfirmed_connection: None,
            rejected_client: None,
        },
    );
    Ok(id)
}

fn begin(
    id: Option<String>,
    endpoint: Option<std::net::SocketAddr>,
) -> Result<Guard, AdbConnectionError> {
    let mut state = registry().lock().expect("adb registry");
    if state.closing {
        return Err(AdbConnectionError::admission("adb_host_closing"));
    }
    let anonymous = id.is_none();
    let (id, handshake, owner) = match id {
        Some(id) => {
            validate_connection_registration(&state, &id)?;
            if endpoint.is_some() && state.handshakes[&id].admission_scope.is_some() {
                return Err(AdbConnectionError::admission(
                    "adb_scoped_handshake_direct_only",
                ));
            }
            let owner = state
                .handshakes
                .get(&id)
                .and_then(|entry| entry.owner.clone());
            match endpoint {
                Some(endpoint) => {
                    server_owner::validate_handshake(&state, endpoint, owner.as_ref())
                        .map_err(AdbConnectionError::admission)?
                }
                None if owner.is_some() => {
                    return Err(AdbConnectionError::admission(
                        "adb_server_handshake_wrong_operation",
                    ));
                }
                None => {}
            }
            let entry = state
                .handshakes
                .get_mut(&id)
                .ok_or_else(|| AdbConnectionError::admission("adb_handshake_closed"))?;
            if entry.started {
                return Err(AdbConnectionError::admission("adb_handshake_already_used"));
            }
            entry.started = true;
            (id, entry.state.clone(), owner)
        }
        None => {
            if let Some(endpoint) = endpoint {
                server_owner::validate_handshake(&state, endpoint, None)
                    .map_err(AdbConnectionError::admission)?;
            }
            let (id, handshake) =
                register(&mut state, true).map_err(AdbConnectionError::admission)?;
            (id, handshake, None)
        }
    };
    Ok(Guard {
        id,
        state: handshake,
        anonymous,
        owner,
    })
}

/// 调用方丢弃等待 future 也不丢弃身份磁盘任务；登记直到实际 worker 释放后才完成。
pub(super) async fn run<T, F, Work>(id: Option<String>, work: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce(CancellationToken) -> Work + Send + 'static,
    Work: Future<Output = Result<T, String>> + Send + 'static,
{
    run_with_error(id, None, |stop, _| work(stop), |error| error.message).await
}

pub(super) async fn run_connection<T, F, Work>(
    id: Option<String>,
    work: F,
) -> Result<T, AdbConnectionError>
where
    T: Send + 'static,
    F: FnOnce(CancellationToken) -> Work + Send + 'static,
    Work: Future<Output = Result<T, AdbConnectionError>> + Send + 'static,
{
    run_with_error(id, None, |stop, _| work(stop), |error| error).await
}

async fn run_with_error<T, F, Work, E>(
    id: Option<String>,
    endpoint: Option<std::net::SocketAddr>,
    work: F,
    map_error: fn(AdbConnectionError) -> E,
) -> Result<T, E>
where
    T: Send + 'static,
    E: Send + 'static,
    F: FnOnce(CancellationToken, Option<server_owner::HandshakeOwner>) -> Work + Send + 'static,
    Work: Future<Output = Result<T, E>> + Send + 'static,
{
    let guard = begin(id, endpoint).map_err(map_error)?;
    tokio::spawn(async move {
        let stop = guard.state.stop.clone();
        let owner = guard.owner.clone();
        let _guard = guard;
        if stop.is_cancelled() {
            return Err(map_error(AdbConnectionError::new(
                AdbConnectionErrorCode::Cancelled,
                "adb_handshake_cancelled",
            )));
        }
        work(stop, owner).await
    })
    .await
    .map_err(|_| {
        map_error(AdbConnectionError::new(
            AdbConnectionErrorCode::Internal,
            "adb_handshake_worker_failed",
        ))
    })?
}

/// 官方端点的租约在开始及结果交付时分别核验，匿名调用也不能绕过已登记端点。
pub(super) async fn run_server<T, F, Work>(
    id: Option<String>,
    endpoint: std::net::SocketAddr,
    work: F,
) -> Result<T, AdbConnectionError>
where
    T: Send + 'static,
    F: FnOnce(CancellationToken, Option<server_owner::HandshakeOwner>) -> Work + Send + 'static,
    Work: Future<Output = Result<T, AdbConnectionError>> + Send + 'static,
{
    run_with_error(id, Some(endpoint), work, |error| error).await
}

pub(super) fn revoke_server(state: &MobileAdbRegistry, server_id: &str) -> Vec<String> {
    state
        .handshakes
        .iter()
        .filter_map(|(id, entry)| {
            if entry
                .owner
                .as_ref()
                .is_some_and(|owner| owner.server_id == server_id)
            {
                revoke(entry);
                Some(id.clone())
            } else {
                None
            }
        })
        .collect()
}

pub(super) fn revoke_scope(state: &MobileAdbRegistry, scope: &str) -> Vec<String> {
    state
        .handshakes
        .iter()
        .filter_map(|(id, entry)| {
            if entry.admission_scope.as_deref() == Some(scope) {
                revoke(entry);
                Some(id.clone())
            } else {
                None
            }
        })
        .collect()
}

fn revoke(entry: &Registration) {
    entry.state.stop.cancel();
    if !entry.started {
        entry.state.finished.cancel();
    }
}

pub(super) fn cancel(id: &str) {
    if let Some(entry) = registry().lock().expect("adb registry").handshakes.get(id) {
        revoke(entry);
    }
}

fn remove(id: &str, expected: &Arc<State>) {
    let mut state = registry().lock().expect("adb registry");
    if state
        .handshakes
        .get(id)
        .is_some_and(|entry| Arc::ptr_eq(&entry.state, expected))
    {
        state.handshakes.remove(id);
    }
}

pub(super) async fn close(id: &str, timeout: Duration) -> Result<(), String> {
    let handshake = {
        let state = registry().lock().expect("adb registry");
        let Some(entry) = state.handshakes.get(id) else {
            return Ok(());
        };
        revoke(entry);
        entry.state.clone()
    };
    tokio::time::timeout(timeout, handshake.finished.cancelled())
        .await
        .map_err(|_| "adb_handshake_cleanup_unconfirmed")?;
    let connection = registry()
        .lock()
        .expect("adb registry")
        .handshakes
        .get(id)
        .and_then(|entry| entry.unconfirmed_connection.clone());
    if let Some(connection) = connection {
        disconnect_with_timeout(&connection, timeout).await?;
    }
    let rejected = registry()
        .lock()
        .expect("adb registry")
        .handshakes
        .get(id)
        .and_then(|entry| entry.rejected_client.clone());
    if let Some(client) = rejected {
        client
            .close_and_wait(OperationOptions {
                timeout,
                cancellation: CancellationToken::new(),
            })
            .await
            .map_err(|error| error.to_string())?;
    }
    remove(id, &handshake);
    Ok(())
}

/// 必须在设置 closing 的同一个注册表临界区调用，覆盖显式及旧调用的匿名握手。
pub(super) fn revoke_all(state: &MobileAdbRegistry) -> Vec<(String, Arc<State>)> {
    state
        .handshakes
        .iter()
        .map(|(id, entry)| {
            revoke(entry);
            (id.clone(), entry.state.clone())
        })
        .collect()
}

pub(super) async fn drain_all(
    handshakes: Vec<(String, Arc<State>)>,
    timeout: Duration,
) -> Result<(), String> {
    let mut failure = None;
    for (id, _) in handshakes {
        // 结束工作 Future 不等于迟到 Client 的驱动退出，统一沿精确关闭路径回收。
        if let Err(error) = close(&id, timeout).await {
            failure.get_or_insert(error);
        }
    }
    failure.map_or(Ok(()), Err)
}
