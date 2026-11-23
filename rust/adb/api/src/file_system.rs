//! 精确连接上的文件 worker、取消和暂存描述符；不持有产品任务、缓存或交付规则。
use crate::api::{
    AdbFileExecutionEntry, AdbFileExecutionEvent, AdbFileExecutionKind as Kind,
    AdbFileExecutionRequest, AdbFileExecutionStamp, AdbFileHelper,
};
use crate::consumer_activity::ConsumerActivity;
use interop_adb::{CancellationToken, Client, OperationOptions, sync::RemotePath};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    path::PathBuf,
    pin::Pin,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncWrite, ReadBuf},
    sync::{Mutex as AsyncMutex, mpsc},
    time::Instant,
};
pub(crate) type FileResult<T> = Result<T, FileError>;
#[derive(Debug)]
pub(crate) struct FileError {
    pub code: String,
    pub message: String,
    pub details: Value,
}
impl FileError {
    pub(crate) fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            details: Value::Null,
        }
    }
    pub(crate) fn errno(&self) -> Option<u32> {
        self.details["errno"]
            .as_u64()
            .and_then(|v| v.try_into().ok())
    }
}
impl From<std::io::Error> for FileError {
    fn from(error: std::io::Error) -> Self {
        let code = match error.kind() {
            std::io::ErrorKind::NotFound => "not_found",
            std::io::ErrorKind::AlreadyExists => "conflict",
            std::io::ErrorKind::PermissionDenied => "permission_denied",
            _ => "io_error",
        };
        Self::new(code, error.to_string())
    }
}
impl From<interop_adb::Error> for FileError {
    fn from(error: interop_adb::Error) -> Self {
        let code = match &error {
            interop_adb::Error::Cancelled => "cancelled",
            interop_adb::Error::Timeout => "timeout",
            interop_adb::Error::Closed => "disconnected",
            interop_adb::Error::InvalidArgument(_) => "invalid_argument",
            interop_adb::Error::RemoteErrno { errno, .. } => match errno {
                1 | 13 => "permission_denied",
                2 => "not_found",
                17 => "conflict",
                20 => "not_directory",
                36 => "invalid_path",
                _ => "remote_error",
            },
            interop_adb::Error::Unsupported(_) => "unsupported",
            _ => "device_error",
        };
        let mut result = Self::new(code, error.to_string());
        if let interop_adb::Error::RemoteErrno { errno, .. } = error {
            result.details = json!({"errno":errno});
        }
        result
    }
}
pub(crate) type HelperResources = HashMap<String, Arc<[u8]>>;
fn resources() -> &'static Mutex<HelperResources> {
    static RESOURCES: OnceLock<Mutex<HelperResources>> = OnceLock::new();
    RESOURCES.get_or_init(|| Mutex::new(HashMap::new()))
}
pub(crate) fn initialize_helpers(helpers: Vec<AdbFileHelper>) -> Result<(), String> {
    let mut next = HashMap::new();
    let mut size = 0usize;
    for helper in helpers {
        if !matches!(
            helper.abi.as_str(),
            "arm64-v8a" | "armeabi-v7a" | "x86_64" | "x86"
        ) || helper.bytes.is_empty()
            || helper.bytes.len() > 16 * 1024 * 1024
        {
            return Err("invalid_file_helper".into());
        }
        size += helper.bytes.len();
        if size > 32 * 1024 * 1024
            || next
                .insert(helper.abi, Arc::<[u8]>::from(helper.bytes))
                .is_some()
        {
            return Err("invalid_file_helper".into());
        }
    }
    if next.is_empty() {
        return Err("invalid_file_helper".into());
    }
    let mut current = resources().lock().expect("文件助手资源");
    if !current.is_empty() && *current != next {
        return Err("file_helper_configuration_mismatch".into());
    }
    *current = next;
    Ok(())
}
struct Part {
    connection: String,
    scope: String,
    path: PathBuf,
    file: Arc<std::fs::File>,
}
struct Operation {
    connection: String,
    scope: String,
    client: Client,
    stop: CancellationToken,
    finished: CancellationToken,
    events: AsyncMutex<mpsc::Receiver<AdbFileExecutionEvent>>,
    consumer: ConsumerActivity,
    unclaimed_part: Mutex<Option<String>>,
}
#[derive(Default)]
struct Registry {
    operations: HashMap<String, Arc<Operation>>,
    parts: HashMap<String, Part>,
    scope_owners: HashMap<String, Arc<AsyncMutex<()>>>,
    scopes: HashMap<String, FileScope>,
}
struct FileScope {
    owner: String,
    admission: Option<String>,
    accepting: bool,
}
fn registry() -> &'static Mutex<Registry> {
    static OWNER: OnceLock<Mutex<Registry>> = OnceLock::new();
    OWNER.get_or_init(|| Mutex::new(Registry::default()))
}
pub(crate) async fn attach_scope(owner_key: String) -> Result<String, String> {
    attach_scope_inner(owner_key, None).await
}

/// 调用方持有父准入域的转换锁，直到文件域交付；父域接管不能越过本次附着。
pub(crate) async fn attach_scope_with_admission(
    owner_key: String,
    admission: String,
) -> Result<String, String> {
    attach_scope_inner(owner_key, Some(admission)).await
}

async fn attach_scope_inner(
    owner_key: String,
    admission: Option<String>,
) -> Result<String, String> {
    if owner_key.is_empty() || owner_key.len() > 1024 {
        return Err("invalid_file_scope_owner".into());
    }
    let gate = {
        let mut owner = registry().lock().expect("文件作用域登记表");
        // 没有存活作用域或等待者的名称不占永久容量；仍被持有的转换锁不能替换。
        let Registry {
            scope_owners,
            scopes,
            ..
        } = &mut *owner;
        scope_owners.retain(|key, gate| {
            Arc::strong_count(gate) > 1 || scopes.values().any(|scope| scope.owner == *key)
        });
        if !owner.scope_owners.contains_key(&owner_key) && owner.scope_owners.len() >= 128 {
            return Err("file_scope_limit".into());
        }
        owner
            .scope_owners
            .entry(owner_key.clone())
            .or_insert_with(|| Arc::new(AsyncMutex::new(())))
            .clone()
    };
    // 转换锁独立于登记表；取消与磁盘/传输等待期间仍可拒绝旧代请求或操作其他作用域。
    let _transition = gate.lock().await;
    let previous = registry()
        .lock()
        .expect("文件作用域登记表")
        .scopes
        .iter()
        .find(|(_, scope)| scope.owner == owner_key)
        .map(|(id, _)| id.clone());
    if let Some(id) = previous {
        drain_scope(&id).await?;
    }
    let id = uuid::Uuid::new_v4().to_string();
    registry().lock().expect("文件作用域登记表").scopes.insert(
        id.clone(),
        FileScope {
            owner: owner_key,
            admission,
            accepting: true,
        },
    );
    Ok(id)
}
/// 在父准入域登记锁内调用；锁序与文件准入一致，均为 ADB 登记表再文件登记表。
/// 先同步撤准入并发取消，之后由锁外的精确关闭等待 worker 和描述符真正释放。
pub(crate) fn revoke_admission(admission: &str) -> Vec<String> {
    let mut owner = registry().lock().expect("文件作用域登记表");
    let scopes = owner
        .scopes
        .iter_mut()
        .filter_map(|(id, scope)| {
            if scope.admission.as_deref() != Some(admission) {
                return None;
            }
            scope.accepting = false;
            Some(id.clone())
        })
        .collect::<Vec<_>>();
    for op in owner.operations.values() {
        if scopes.contains(&op.scope) {
            op.stop.cancel();
        }
    }
    scopes
}

pub(crate) async fn drain_admission(scopes: Vec<String>) -> Result<(), String> {
    let mut failure = None;
    for id in scopes {
        if let Err(error) = close_scope(&id).await {
            failure.get_or_insert(error);
        }
    }
    failure.map_or(Ok(()), Err)
}

pub(crate) async fn close_scope(id: &str) -> Result<(), String> {
    let gate = {
        let owner = registry().lock().expect("文件作用域登记表");
        let Some(scope) = owner.scopes.get(id) else {
            return Ok(());
        };
        owner.scope_owners[&scope.owner].clone()
    };
    let _transition = gate.lock().await;
    drain_scope(id).await
}
async fn drain_scope(id: &str) -> Result<(), String> {
    let operations = {
        let mut owner = registry().lock().expect("文件作用域登记表");
        let Some(scope) = owner.scopes.get_mut(id) else {
            return Ok(());
        };
        scope.accepting = false;
        owner
            .operations
            .iter()
            .filter(|(_, op)| op.scope == id)
            .map(|(id, op)| {
                op.stop.cancel();
                id.clone()
            })
            .collect::<Vec<_>>()
    };
    // 任一步失败都保留已撤销的作用域；下一次 attach/close 继续排空，绝不先准入新代。
    tokio::time::timeout(Duration::from_secs(7), async {
        for operation in operations {
            cancel(&operation)
                .await
                .map_err(|_| "file_cleanup_unconfirmed".to_owned())?;
        }
        Ok::<_, String>(())
    })
    .await
    .map_err(|_| "file_cleanup_unconfirmed")??;
    let mut owner = registry().lock().expect("文件作用域登记表");
    // 仅释放精确暂存描述符；路径可能已由外部替换，不能按旧路径删除其他文件。
    owner.parts.retain(|_, part| part.scope != id);
    owner.scopes.remove(id);
    Ok(())
}
fn event(kind: &str) -> AdbFileExecutionEvent {
    AdbFileExecutionEvent {
        kind: kind.into(),
        entries: vec![],
        stamp: None,
        transferred: 0,
        truncated: false,
        save_mode: None,
        part_id: None,
        error_code: None,
        error_message: None,
        errno: None,
    }
}
fn check(stop: &CancellationToken) -> FileResult<()> {
    if stop.is_cancelled() {
        Err(interop_adb::Error::Cancelled.into())
    } else {
        Ok(())
    }
}
async fn send(
    sender: &mpsc::Sender<AdbFileExecutionEvent>,
    op: &Operation,
    event: AdbFileExecutionEvent,
) -> FileResult<()> {
    tokio::select! {biased;_=op.stop.cancelled()=>Err(interop_adb::Error::Cancelled.into()),result=tokio::time::timeout(Duration::from_secs(45),sender.send(event))=>result.map_err(|_|FileError::new("consumer_timeout","文件结果无人读取。"))?.map_err(|_|FileError::new("cancelled","文件消费者已离开。"))}
}
pub(crate) async fn execute(
    connection: String,
    request: AdbFileExecutionRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    if timeout_ms == 0 || timeout_ms > 86_400_000 {
        return Err("invalid_adb_timeout".into());
    }
    if request.kind == Kind::Copy && request.expected.is_none() {
        return Err("invalid_argument: expected file stamp required".into());
    }
    let helpers = resources().lock().expect("文件助手资源").clone();
    let (id, op, sender) = crate::api::admit_file(&connection, |client, stop| {
        if stop.is_cancelled() {
            return Err("adb_connection_closed".into());
        }
        let mut owner = registry().lock().expect("文件执行登记表");
        if !request.scope_id.is_empty()
            && !owner
                .scopes
                .get(&request.scope_id)
                .is_some_and(|scope| scope.accepting)
        {
            return Err("file_scope_closed".into());
        }
        if owner.operations.len() >= 128 {
            return Err("file_operation_limit".into());
        }
        let (sender, events) = mpsc::channel(1);
        let op = Arc::new(Operation {
            connection: connection.clone(),
            scope: request.scope_id.clone(),
            client,
            stop,
            finished: CancellationToken::new(),
            events: AsyncMutex::new(events),
            consumer: ConsumerActivity::new(),
            unclaimed_part: Mutex::new(None),
        });
        let id = uuid::Uuid::new_v4().to_string();
        owner.operations.insert(id.clone(), op.clone());
        Ok((id, op, sender))
    })?;
    tokio::spawn(reclaim(
        id.clone(),
        Arc::downgrade(&op),
        Duration::from_secs(45),
    ));
    let finished = op.finished.clone().drop_guard();
    tokio::spawn(async move {
        let _finished = finished;
        let options = OperationOptions {
            cancellation: op.stop.clone(),
            timeout: Duration::from_millis(timeout_ms.into()),
        };
        // 发布一旦进入本机系统调用便等待其真实完成，不丢弃 spawn_blocking 让提交在取消返回后继续执行。
        let result = work(&request, &op, &helpers, options, &sender).await;
        if let Err(error) = result {
            let mut result = event("error");
            result.errno = error.errno();
            result.error_code = Some(error.code);
            result.error_message = Some(error.message);
            let _ = send(&sender, &op, result).await;
        }
    });
    Ok(id)
}
async fn work(
    request: &AdbFileExecutionRequest,
    op: &Operation,
    helpers: &HelperResources,
    options: OperationOptions,
    sender: &mpsc::Sender<AdbFileExecutionEvent>,
) -> FileResult<()> {
    check(&op.stop)?;
    let mut done = event("done");
    match request.kind {
        Kind::Stat => {
            let stamp = if request.local {
                crate::file_metadata::local_stat(&request.path).await?
            } else {
                crate::file_metadata::stat(
                    &op.client,
                    helpers,
                    &request.path,
                    request.follow_storage_alias,
                    options,
                )
                .await?
            };
            let mut result = event("stat");
            result.stamp = Some(stamp);
            send(sender, op, result).await?;
        }
        Kind::List => {
            let (entries, truncated) = crate::file_metadata::list(
                &op.client,
                helpers,
                &request.path,
                request.local,
                request.limit as usize,
                options,
            )
            .await?;
            let mut entries = entries.into_iter();
            loop {
                let chunk: Vec<AdbFileExecutionEntry> = entries.by_ref().take(128).collect();
                if chunk.is_empty() {
                    break;
                }
                let mut result = event("entries");
                result.entries = chunk;
                send(sender, op, result).await?;
            }
            done.truncated = truncated;
        }
        Kind::Copy => {
            let progress = Arc::new(AtomicU64::new(0));
            let copying = copy(request, op, helpers, options, progress.clone());
            tokio::pin!(copying);
            let mut interval = tokio::time::interval(Duration::from_millis(100));
            let result = loop {
                tokio::select! {
                    result = &mut copying => break result?,
                    _ = interval.tick() => {
                        let mut update = event("progress");
                        update.transferred = progress.load(Ordering::Relaxed);
                        if let Err(error) = send(sender, op, update).await {
                            // 文件系统的阻塞工作不能因事件发送失败而脱离 worker 的完成屏障。
                            op.stop.cancel();
                            let _ = copying.await;
                            return Err(error);
                        }
                    }
                }
            };
            done.transferred = result.0;
            done.part_id = result.1;
        }
        _ => done.save_mode = Some(mutate(request, op, helpers, options).await?),
    }
    check(&op.stop)?;
    send(sender, op, done).await
}
pub(crate) async fn next(id: String) -> Result<Option<AdbFileExecutionEvent>, String> {
    let op = registry()
        .lock()
        .expect("文件执行登记表")
        .operations
        .get(&id)
        .cloned()
        .ok_or("file_operation_closed")?;
    let mut reader = op
        .events
        .try_lock()
        .map_err(|_| "file_operation_has_a_reader")?;
    let _reading = op.consumer.reading();
    let result = tokio::select! {
        biased;
        _ = op.stop.cancelled() => return Err("cancelled: file operation cancelled".into()),
        result = reader.recv() => result,
    };
    if let Some(ref event) = result
        && event.kind == "done"
        && event.part_id.is_some()
    {
        op.unclaimed_part.lock().expect("暂存交接").take();
    }
    Ok(result)
}
pub(crate) async fn cancel(id: &str) -> Result<(), String> {
    let Some(op) = registry()
        .lock()
        .expect("文件执行登记表")
        .operations
        .get(id)
        .cloned()
    else {
        return Ok(());
    };
    op.stop.cancel();
    tokio::time::timeout(Duration::from_secs(5), op.finished.cancelled())
        .await
        .map_err(|_| "file_cleanup_unconfirmed")?;
    if !op.client.is_closed() {
        tokio::time::timeout(
            Duration::from_secs(2),
            op.client.flush_closed_streams(OperationOptions {
                timeout: Duration::from_secs(2),
                cancellation: CancellationToken::new(),
            }),
        )
        .await
        .map_err(|_| "file_cleanup_unconfirmed")?
        .map_err(|e| e.to_string())?;
    }
    let mut owner = registry().lock().expect("文件执行登记表");
    if let Some(part) = op.unclaimed_part.lock().expect("暂存交接").take() {
        owner.parts.remove(&part);
    }
    owner.operations.remove(id);
    Ok(())
}
pub(crate) async fn cancel_connection(connection: &str) -> Result<(), String> {
    let ids = {
        let owner = registry().lock().expect("文件执行登记表");
        owner
            .operations
            .iter()
            .filter(|(_, op)| op.connection == connection)
            .map(|(id, op)| {
                op.stop.cancel();
                id.clone()
            })
            .collect::<Vec<_>>()
    };
    let mut failure = None;
    for id in ids {
        if let Err(error) = cancel(&id).await {
            failure.get_or_insert(error);
        }
    }
    if let Some(error) = failure {
        return Err(error);
    }
    // 已确认所有 worker 和本机关闭帧完成，才能撤销调用方尚未提交的暂存文件描述符。
    registry()
        .lock()
        .expect("文件执行登记表")
        .parts
        .retain(|_, part| part.connection != connection);
    Ok(())
}
pub(crate) async fn cancel_all() -> Result<(), String> {
    let ids = {
        let owner = registry().lock().expect("文件执行登记表");
        owner.operations.values().for_each(|op| op.stop.cancel());
        owner.operations.keys().cloned().collect::<Vec<_>>()
    };
    let mut failure = None;
    for id in ids {
        if let Err(error) = cancel(&id).await {
            failure.get_or_insert(error);
        }
    }
    if let Some(error) = failure {
        return Err(error);
    }
    registry().lock().expect("文件执行登记表").parts.clear();
    Ok(())
}
async fn reclaim(id: String, weak: std::sync::Weak<Operation>, idle: Duration) {
    loop {
        tokio::time::sleep(idle).await;
        let Some(op) = weak.upgrade() else {
            return;
        };
        let expired = op
            .consumer
            .cancel_if_idle_at(Instant::now(), idle, &op.stop);
        if expired && cancel(&id).await.is_ok() {
            return;
        }
    }
}
async fn copy(
    request: &AdbFileExecutionRequest,
    op: &Operation,
    helpers: &HelperResources,
    options: OperationOptions,
    progress: Arc<AtomicU64>,
) -> FileResult<(u64, Option<String>)> {
    let expected = request
        .expected
        .as_ref()
        .ok_or_else(|| FileError::new("invalid_argument", "缺少源文件快照。"))?;
    if expected.mode & 0o170000 != 0o100000 {
        return Err(FileError::new("not_a_file", "不能传输链接或特殊文件。"));
    }
    let before = source_stat(request, op, helpers, options.clone()).await?;
    if &before != expected {
        return Err(FileError::new("source_changed", "源文件与选择快照不同。"));
    }
    let mut sync = op.client.sync(options.clone()).await?;
    let mut held = None;
    let count = if request.push {
        crate::file_metadata::remote_path(&request.destination)?;
        let mut opening = tokio::fs::OpenOptions::new();
        opening.read(true);
        #[cfg(unix)]
        opening.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
        let input_file = opening
            .open(crate::file_metadata::path(&request.path)?)
            .await?;
        if crate::file_metadata::local_stamp(&input_file.metadata().await?)? != *expected {
            return Err(FileError::new(
                "source_changed",
                "已打开源文件与选择快照不同。",
            ));
        }
        let mut input = ProgressIo {
            inner: input_file,
            progress,
        };
        let count = sync
            .push(
                &RemotePath::new(&request.destination)?,
                &mut input,
                0o644,
                expected.modified_seconds.clamp(0, u32::MAX as i64) as u32,
                expected.size,
            )
            .await?;
        if crate::file_metadata::local_stamp(&input.inner.metadata().await?)? != *expected {
            return Err(FileError::new(
                "source_changed",
                "传输期间已打开源文件发生变化。",
            ));
        }
        count
    } else {
        let mut output = ProgressIo {
            inner: tokio::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(crate::file_metadata::path(&request.destination)?)
                .await?,
            progress,
        };
        let count = sync
            .pull(&RemotePath::new(&request.path)?, &mut output, expected.size)
            .await?;
        output.inner.sync_all().await?;
        held = Some(output.inner.into_std().await);
        count
    };
    drop(sync);
    check(&op.stop)?;
    if count != expected.size || source_stat(request, op, helpers, options).await? != *expected {
        return Err(FileError::new(
            "source_changed",
            "传输期间源文件已变化，暂存内容未发布。",
        ));
    }
    let part = if let Some(file) = held {
        let id = uuid::Uuid::new_v4().to_string();
        let mut owner = registry().lock().expect("文件暂存句柄");
        check(&op.stop)?;
        if owner.parts.len() >= 128 {
            return Err(FileError::new("busy", "暂存句柄达到上限。"));
        }
        owner.parts.insert(
            id.clone(),
            Part {
                connection: op.connection.clone(),
                scope: op.scope.clone(),
                path: crate::file_metadata::path(&request.destination)?,
                file: Arc::new(file),
            },
        );
        *op.unclaimed_part.lock().expect("暂存交接") = Some(id.clone());
        Some(id)
    } else {
        None
    };
    Ok((count, part))
}
async fn source_stat(
    request: &AdbFileExecutionRequest,
    op: &Operation,
    helpers: &HelperResources,
    options: OperationOptions,
) -> FileResult<AdbFileExecutionStamp> {
    if request.push {
        crate::file_metadata::local_stat(&request.path).await
    } else {
        crate::file_metadata::stat(&op.client, helpers, &request.path, false, options).await
    }
}
async fn mutate(
    request: &AdbFileExecutionRequest,
    op: &Operation,
    helpers: &HelperResources,
    options: OperationOptions,
) -> FileResult<String> {
    if request.kind == Kind::ReleasePart {
        let mut owner = registry().lock().expect("文件暂存句柄");
        if let Some(part) = owner.parts.get(&request.part_id)
            && (part.connection != op.connection
                || part.scope != op.scope
                || part.path != crate::file_metadata::path(&request.path)?)
        {
            return Err(FileError::new(
                "part_owner_mismatch",
                "暂存句柄不属于此连接和路径。",
            ));
        }
        owner.parts.remove(&request.part_id);
        return Ok("released".into());
    }
    check(&op.stop)?;
    if request.local {
        let path = crate::file_metadata::path(&request.path)?;
        match request.kind {
            Kind::Mkdir => {
                tokio::fs::create_dir(path).await?;
                return Ok("directoryCreated".into());
            }
            Kind::Delete => {
                let metadata = tokio::fs::symlink_metadata(&path).await?;
                if metadata.is_dir() {
                    tokio::fs::remove_dir_all(path).await?;
                } else {
                    tokio::fs::remove_file(path).await?;
                }
                return Ok("verified".into());
            }
            Kind::Commit => {
                let destination = crate::file_metadata::path(&request.destination)?;
                let part = {
                    let mut owner = registry().lock().expect("文件暂存句柄");
                    let part = owner
                        .parts
                        .get(&request.part_id)
                        .ok_or_else(|| FileError::new("source_changed", "暂存句柄已过期。"))?;
                    if part.connection != op.connection
                        || part.scope != op.scope
                        || part.path != path
                    {
                        return Err(FileError::new(
                            "part_owner_mismatch",
                            "暂存句柄不属于此连接和路径。",
                        ));
                    }
                    owner
                        .parts
                        .remove(&request.part_id)
                        .expect("已核验暂存句柄")
                };
                let replace = request.replace;
                tokio::task::spawn_blocking(move || {
                    part.file.sync_all()?;
                    #[cfg(any(
                        target_os = "linux",
                        target_os = "android",
                        target_os = "macos",
                        target_os = "ios"
                    ))]
                    {
                        if replace {
                            crate::file_publication::publish_file_replace(
                                &part.file,
                                &path,
                                &destination,
                            )
                        } else {
                            crate::file_publication::publish_file(&part.file, &path, &destination)
                        }
                    }
                    #[cfg(not(any(
                        target_os = "linux",
                        target_os = "android",
                        target_os = "macos",
                        target_os = "ios"
                    )))]
                    {
                        let _ = (path, destination, replace);
                        Err(FileError::new(
                            "atomic_save_unavailable",
                            "此宿主尚未提供已核验描述符的原子发布机制。",
                        ))
                    }
                })
                .await
                .map_err(|e| FileError::new("result_unknown", e.to_string()))??;
                return Ok(if request.replace {
                    "atomicRename"
                } else {
                    "atomicNoReplace"
                }
                .into());
            }
            _ => return Err(FileError::new("unsupported", "不支持的本机文件原语。")),
        }
    }
    crate::file_metadata::remote_path(&request.path)?;
    if matches!(request.kind, Kind::Rename | Kind::Delete) {
        if request.path == b"/" {
            return Err(FileError::new("invalid_path", "不能变更文件系统根路径。"));
        }
        if request.kind == Kind::Rename {
            crate::file_metadata::remote_path(&request.destination)?;
        }
        let expected = request
            .expected
            .as_ref()
            .and_then(|stamp| stamp.identity.as_deref())
            .ok_or_else(|| FileError::new("source_changed", "缺少所选文件的身份，请重新选择。"))?;
        crate::file_helper::mutate_expected(
            &op.client,
            helpers,
            &request.path,
            &request.destination,
            request.kind == Kind::Delete,
            expected,
            options,
        )
        .await?;
        return Ok(if request.kind == Kind::Delete {
            "verified"
        } else {
            "atomicRenameNoReplace"
        }
        .into());
    }
    if matches!(request.kind, Kind::Rename | Kind::Commit) {
        crate::file_metadata::remote_path(&request.destination)?;
        crate::file_helper::rename_bytes_with_options(
            &op.client,
            helpers,
            &request.path,
            &request.destination,
            request.replace,
            options,
        )
        .await?;
        return Ok(if request.replace {
            "atomicRename"
        } else {
            "atomicRenameNoReplace"
        }
        .into());
    }
    if request.path == b"/" {
        return Err(FileError::new("invalid_path", "不能变更文件系统根路径。"));
    }
    let assignment = crate::file_helper::path_assignment("source", &request.path)?;
    let command = match request.kind {
        Kind::Mkdir => "mkdir \"$source\"",
        Kind::Delete => "rm -rf \"$source\"",
        _ => return Err(FileError::new("unsupported", "不支持的设备文件原语。")),
    };
    remote_command(&op.client, &format!("{assignment}{command}"), options).await?;
    Ok("verified".into())
}
async fn remote_command(
    client: &Client,
    script: &str,
    options: OperationOptions,
) -> FileResult<()> {
    if client.info().features.contains("shell_v2") {
        let output = client
            .shell(script, 64 * 1024, options)
            .await
            .map_err(|e| FileError::new("result_unknown", e.to_string()))?;
        if output.exit_code != Some(0) {
            return Err(FileError::new(
                "remote_failed",
                String::from_utf8_lossy(&output.stderr),
            ));
        }
        return Ok(());
    }
    let marker = format!("ADB_FILE_EXIT_{}:", uuid::Uuid::new_v4().simple());
    let script = format!("(\n{script}\n); adb_status=$?; print -nr -- '{marker}'\"$adb_status\"");
    let mut stream = client
        .exec(&script, options)
        .await
        .map_err(|e| FileError::new("result_unknown", e.to_string()))?;
    let mut output = Vec::new();
    let mut buffer = [0; 4096];
    loop {
        let count = stream
            .read(&mut buffer)
            .await
            .map_err(|e| FileError::new("result_unknown", e.to_string()))?;
        if count == 0 {
            break;
        }
        if output.len() + count > 64 * 1024 + marker.len() + 3 {
            return Err(FileError::new("result_unknown", "文件变更回执超限。"));
        }
        output.extend_from_slice(&buffer[..count]);
    }
    let index = output
        .windows(marker.len())
        .rposition(|value| value == marker.as_bytes())
        .ok_or_else(|| FileError::new("result_unknown", "缺少设备变更退出状态。"))?;
    let status = std::str::from_utf8(&output[index + marker.len()..])
        .ok()
        .filter(|value| {
            !value.is_empty() && value.len() <= 3 && value.bytes().all(|b| b.is_ascii_digit())
        })
        .and_then(|value| value.parse::<u8>().ok())
        .ok_or_else(|| FileError::new("result_unknown", "设备变更退出状态无效。"))?;
    if status == 0 {
        Ok(())
    } else {
        Err(FileError::new(
            "remote_failed",
            String::from_utf8_lossy(&output[..index]),
        ))
    }
}
struct ProgressIo<T> {
    inner: T,
    progress: Arc<AtomicU64>,
}
impl<T: AsyncRead + Unpin> AsyncRead for ProgressIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let result = Pin::new(&mut self.inner).poll_read(cx, buf);
        if matches!(&result, Poll::Ready(Ok(()))) {
            self.progress
                .fetch_add((buf.filled().len() - before) as u64, Ordering::Relaxed);
        }
        result
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for ProgressIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let result = Pin::new(&mut self.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(count)) = &result {
            self.progress.fetch_add(*count as u64, Ordering::Relaxed);
        }
        result
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}
