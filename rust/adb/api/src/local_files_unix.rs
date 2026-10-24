use crate::api::*;
use std::{
    collections::HashMap,
    fs::File,
    sync::{Arc, Mutex, OnceLock, Weak},
    time::Duration,
};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;
#[path = "local_files_fs.rs"]
mod filesystem;
use filesystem::{FileScope, Resources};
type Result<T> = std::result::Result<T, LocalFileError>;
fn error(code: LocalFileErrorCode, message: impl Into<String>) -> LocalFileError {
    LocalFileError {
        code,
        message: message.into(),
        bytes_copied: 0,
        partial_destination_possible: false,
    }
}
fn duration(value: u32) -> Result<Duration> {
    if value == 0 {
        Err(error(
            LocalFileErrorCode::InvalidArgument,
            "期限必须为正毫秒数。",
        ))
    } else {
        Ok(Duration::from_millis(value.into()))
    }
}
struct ScopeState {
    accepting: bool,
    active: usize,
}
struct Scope {
    owner_key: String,
    fs: FileScope,
    state: Mutex<ScopeState>,
    stop: CancellationToken,
    changed: Notify,
}
struct Lease(Arc<Scope>);
impl Drop for Lease {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().expect("本机范围状态");
        state.active -= 1;
        self.0.changed.notify_waiters();
    }
}
impl Scope {
    fn admit(self: &Arc<Self>) -> Result<Lease> {
        let mut state = self.state.lock().expect("本机范围状态");
        if !state.accepting {
            return Err(error(
                LocalFileErrorCode::ScopeClosed,
                "本机范围已撤销准入。",
            ));
        }
        state.active += 1;
        Ok(Lease(self.clone()))
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Reserved,
    Running,
    Finished,
}
struct CopyState {
    phase: Phase,
    resources: Option<Resources>,
    result: Option<Result<LocalFileCopyResult>>,
    committing: bool,
    closing: bool,
    cleaning: bool,
    cleaned: bool,
    cleanup_error: Option<LocalFileError>,
}
struct Copy {
    scope_id: String,
    scope: Arc<Scope>,
    stop: CancellationToken,
    state: Mutex<CopyState>,
    changed: Notify,
}
#[derive(Default)]
struct Registry {
    keys: HashMap<String, String>,
    transitions: HashMap<String, Weak<tokio::sync::Mutex<()>>>,
    scopes: HashMap<String, Arc<Scope>>,
    copies: HashMap<String, Arc<Copy>>,
}
fn registry() -> &'static Mutex<Registry> {
    static OWNER: OnceLock<Mutex<Registry>> = OnceLock::new();
    OWNER.get_or_init(|| Mutex::new(Registry::default()))
}
fn scope(id: &str) -> Result<Arc<Scope>> {
    registry()
        .lock()
        .expect("本机文件登记")
        .scopes
        .get(id)
        .cloned()
        .ok_or_else(|| error(LocalFileErrorCode::NotFound, "本机范围不存在。"))
}
fn copy(id: &str) -> Result<Arc<Copy>> {
    registry()
        .lock()
        .expect("本机文件登记")
        .copies
        .get(id)
        .cloned()
        .ok_or_else(|| error(LocalFileErrorCode::NotFound, "本机复制句柄不存在。"))
}
fn join_error(e: tokio::task::JoinError) -> LocalFileError {
    error(LocalFileErrorCode::Io, format!("本机文件任务异常：{e}"))
}
async fn execute<T: Send + 'static>(
    id: String,
    operation: impl FnOnce(&FileScope, &CancellationToken) -> Result<T> + Send + 'static,
) -> Result<T> {
    let scope = scope(&id)?;
    let lease = scope.admit()?;
    // 调用者的等待被丢弃时，阻塞任务仍持有准入租约；scope.close 必须等待真实任务退出。
    tokio::task::spawn_blocking(move || {
        let _lease = lease;
        if scope.stop.is_cancelled() {
            return Err(error(LocalFileErrorCode::Cancelled, "本机范围已取消。"));
        }
        operation(&scope.fs, &scope.stop)
    })
    .await
    .map_err(join_error)?
}
pub async fn open(roots: Vec<Vec<u8>>, owner_key: String, close_timeout_ms: u32) -> Result<String> {
    duration(close_timeout_ms)?;
    if owner_key.is_empty() || owner_key.contains('\0') {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "本机范围资源名称不能为空或包含空字符。",
        ));
    }
    // 独立任务持有完整交接；旧 isolate 消失后，后继仍可按同一资源名称再次排空。
    tokio::spawn(async move {
        let fs = tokio::task::spawn_blocking(move || FileScope::open(roots))
            .await
            .map_err(join_error)??;
        let gate = {
            let mut owner = registry().lock().expect("本机文件登记");
            owner
                .transitions
                .retain(|_, value| value.strong_count() > 0);
            let gate = owner
                .transitions
                .get(&owner_key)
                .and_then(Weak::upgrade)
                .unwrap_or_else(|| Arc::new(tokio::sync::Mutex::new(())));
            owner
                .transitions
                .insert(owner_key.clone(), Arc::downgrade(&gate));
            gate
        };
        let _transition = gate.lock().await;
        let previous = registry()
            .lock()
            .expect("本机文件登记")
            .keys
            .get(&owner_key)
            .cloned();
        if let Some(previous) = previous {
            close_scope(previous, close_timeout_ms).await?;
        }
        let id = uuid::Uuid::new_v4().to_string();
        let mut owner = registry().lock().expect("本机文件登记");
        owner.keys.insert(owner_key.clone(), id.clone());
        owner.scopes.insert(
            id.clone(),
            Arc::new(Scope {
                owner_key,
                fs,
                state: Mutex::new(ScopeState {
                    accepting: true,
                    active: 0,
                }),
                stop: CancellationToken::new(),
                changed: Notify::new(),
            }),
        );
        Ok(id)
    })
    .await
    .map_err(join_error)?
}
pub async fn stat(id: String, path: Vec<u8>) -> Result<LocalFileStat> {
    execute(id, move |fs, _| fs.stat(&path)).await
}
pub async fn list(id: String, path: Vec<u8>, max_entries: u32) -> Result<LocalFileList> {
    execute(id, move |fs, stop| fs.list(&path, max_entries, stop)).await
}
pub async fn mkdir(id: String, path: Vec<u8>, exclusive: bool) -> Result<()> {
    execute(id, move |fs, _| fs.mkdir(&path, exclusive)).await
}
pub async fn remove(id: String, path: Vec<u8>, expected: LocalFileIdentity) -> Result<()> {
    execute(id, move |fs, _| fs.remove(&path, &expected)).await
}
pub async fn create_copy(id: String, request: LocalFileCopyRequest) -> Result<String> {
    duration(request.timeout_ms)?;
    if request.source_path.is_some() == request.source_fd.is_some()
        || request.target_path.is_some() == request.target_fd.is_some()
    {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "每端必须恰好指定一个路径或描述符。",
        ));
    }
    if request.length.is_some_and(|n| n > request.max_bytes) {
        return Err(error(
            LocalFileErrorCode::ByteLimit,
            "声明范围超过调用方的字节上限。",
        ));
    }
    let scope = scope(&id)?;
    let lease = scope.admit()?;
    // FD 在首次挂起前复制；后台等待路径 I/O 时不再借用平台整数句柄。
    let source: Option<File> = request
        .source_fd
        .map(|fd| filesystem::duplicate(fd, true))
        .transpose()?;
    let target: Option<File> = request
        .target_fd
        .map(|fd| filesystem::duplicate(fd, false))
        .transpose()?;
    tokio::task::spawn_blocking(move || {
        let _lease = lease;
        if scope.stop.is_cancelled() {
            return Err(error(LocalFileErrorCode::Cancelled, "复制准入已撤销。"));
        }
        let resources = scope.fs.resources(request, source, target)?;
        #[cfg(test)]
        tests::after_create(&id);
        let admission = scope.state.lock().expect("本机范围状态");
        let accepting = admission.accepting;
        let key = uuid::Uuid::new_v4().to_string();
        registry().lock().expect("本机文件登记").copies.insert(
            key.clone(),
            Arc::new(Copy {
                scope_id: id,
                scope: scope.clone(),
                stop: scope.stop.child_token(),
                state: Mutex::new(CopyState {
                    phase: Phase::Reserved,
                    resources: Some(resources),
                    result: None,
                    committing: false,
                    closing: false,
                    cleaning: false,
                    cleaned: false,
                    cleanup_error: None,
                }),
                changed: Notify::new(),
            }),
        );
        drop(admission);
        if accepting {
            Ok(key)
        } else {
            // 即使准入已撤销，也先登记已绑定的真实资源。close 等待本次创建租约
            // 退出后会枚举该句柄；删除失败仍保留 FD 与范围身份供同 key 重试。
            Err(error(
                LocalFileErrorCode::ScopeClosed,
                "绑定期间本机范围已关闭，资源交回范围清理。",
            ))
        }
    })
    .await
    .map_err(join_error)?
}
pub async fn run_copy(id: String) -> Result<LocalFileCopyResult> {
    let copy = copy(&id)?;
    {
        let mut state = copy.state.lock().expect("本机复制状态");
        if state.closing || copy.stop.is_cancelled() {
            return Err(error(LocalFileErrorCode::Cancelled, "本机复制已取消。"));
        }
        if state.phase == Phase::Reserved {
            let lease = copy.scope.admit()?;
            state.phase = Phase::Running;
            let mut resources = state.resources.take().expect("待运行复制资源");
            let worker = copy.clone();
            tokio::task::spawn_blocking(move || {
                let _lease = lease;
                // 捕获意外 panic 仍保留原始 FD 和未知结果，不能提前发布释放完成。
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    resources.copy(&worker.stop)
                }))
                .unwrap_or_else(|_| {
                    Err(error(
                        LocalFileErrorCode::ResultUnknown,
                        "复制任务异常，结果无法确认。",
                    ))
                });
                let mut state = worker.state.lock().expect("本机复制状态");
                state.resources = Some(resources);
                state.result = Some(result);
                state.phase = Phase::Finished;
                worker.changed.notify_waiters();
            });
        }
    }
    loop {
        let changed = copy.changed.notified();
        if let Some(result) = copy.state.lock().expect("本机复制状态").result.clone() {
            return result;
        }
        changed.await;
    }
}
pub fn cancel_copy(id: String) -> Result<()> {
    if let Some(copy) = registry().lock().expect("本机文件登记").copies.get(&id) {
        copy.stop.cancel();
    }
    Ok(())
}
fn start_cleanup(copy: &Arc<Copy>) {
    let mut state = copy.state.lock().expect("本机复制状态");
    if state.phase != Phase::Finished || state.committing || state.cleaning || state.cleaned {
        return;
    }
    let Some(resources) = state.resources.take() else {
        return;
    };
    state.cleaning = true;
    state.cleanup_error = None;
    let worker = copy.clone();
    tokio::task::spawn_blocking(move || {
        let result = resources.cleanup();
        let mut state = worker.state.lock().expect("本机复制状态");
        state.cleaning = false;
        match result {
            Ok(()) => {
                drop(resources);
                state.cleaned = true;
            }
            Err(error) => {
                state.resources = Some(resources);
                state.cleanup_error = Some(error);
            }
        }
        worker.changed.notify_waiters();
    });
}
async fn drain_copy(id: &str, copy: Arc<Copy>, timeout: Duration) -> Result<()> {
    copy.stop.cancel();
    {
        let mut state = copy.state.lock().expect("本机复制状态");
        state.closing = true;
        if state.phase == Phase::Reserved {
            state.phase = Phase::Finished;
            state.result = Some(Err(error(
                LocalFileErrorCode::Cancelled,
                "尚未开始的复制已关闭。",
            )));
            copy.changed.notify_waiters();
        }
    }
    tokio::time::timeout(timeout, async {
        // 每次显式 close 可以重试一次实际清理；失败不会从登记表丢弃原资源。
        start_cleanup(&copy);
        loop {
            let changed = copy.changed.notified();
            {
                let state = copy.state.lock().expect("本机复制状态");
                if state.cleaned {
                    break;
                }
                if let Some(error) = &state.cleanup_error {
                    return Err(error.clone());
                }
            }
            start_cleanup(&copy);
            // start_cleanup 可在检查与等待之间直接完成，再次检查防止丢通知。
            {
                let state = copy.state.lock().expect("本机复制状态");
                if state.cleaned {
                    break;
                }
                if let Some(error) = &state.cleanup_error {
                    return Err(error.clone());
                }
            }
            changed.await;
        }
        let mut owner = registry().lock().expect("本机文件登记");
        if owner
            .copies
            .get(id)
            .is_some_and(|item| Arc::ptr_eq(item, &copy))
        {
            owner.copies.remove(id);
        }
        Ok(())
    })
    .await
    .map_err(|_| {
        error(
            LocalFileErrorCode::CleanupUnconfirmed,
            "复制及其原始文件句柄尚未确认释放，保留原身份供重试。",
        )
    })?
}
pub async fn close_copy(id: String, timeout_ms: u32) -> Result<()> {
    let timeout = duration(timeout_ms)?;
    let copy = registry()
        .lock()
        .expect("本机文件登记")
        .copies
        .get(&id)
        .cloned();
    match copy {
        Some(copy) => drain_copy(&id, copy, timeout).await,
        None => Ok(()),
    }
}
pub async fn close_scope(id: String, timeout_ms: u32) -> Result<()> {
    let timeout = duration(timeout_ms)?;
    let Some(scope) = registry()
        .lock()
        .expect("本机文件登记")
        .scopes
        .get(&id)
        .cloned()
    else {
        return Ok(());
    };
    {
        let mut state = scope.state.lock().expect("本机范围状态");
        state.accepting = false;
        scope.stop.cancel();
    }
    tokio::time::timeout(timeout, async {
        loop {
            let changed = scope.changed.notified();
            if scope.state.lock().expect("本机范围状态").active == 0 {
                break;
            }
            changed.await;
        }
        // 先等待已获准的 create/commit/普通操作退出，再枚举句柄，避免迟到插入越过关闭。
        let copies: Vec<_> = registry()
            .lock()
            .expect("本机文件登记")
            .copies
            .iter()
            .filter(|(_, copy)| Arc::ptr_eq(&copy.scope, &scope))
            .map(|(id, copy)| (id.clone(), copy.clone()))
            .collect();
        for (key, copy) in copies {
            drain_copy(&key, copy, timeout).await?;
        }
        let mut owner = registry().lock().expect("本机文件登记");
        if owner
            .scopes
            .get(&id)
            .is_some_and(|item| Arc::ptr_eq(item, &scope))
        {
            owner.scopes.remove(&id);
            if owner.keys.get(&scope.owner_key) == Some(&id) {
                owner.keys.remove(&scope.owner_key);
            }
        }
        Ok(())
    })
    .await
    .map_err(|_| {
        error(
            LocalFileErrorCode::CleanupUnconfirmed,
            "本机范围仍有真实操作或句柄待释放，保留原身份供重试。",
        )
    })?
}
pub async fn commit(
    scope_id: String,
    copy_id: String,
    destination: Vec<u8>,
    expected: LocalFileIdentity,
) -> Result<LocalFileIdentity> {
    let scope = scope(&scope_id)?;
    let lease = scope.admit()?;
    let copy = copy(&copy_id)?;
    if copy.scope_id != scope_id {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "复制不属于该本机范围。",
        ));
    }
    let resources = {
        let mut state = copy.state.lock().expect("本机复制状态");
        if state.closing || copy.stop.is_cancelled() {
            return Err(error(LocalFileErrorCode::Cancelled, "复制句柄已取消。"));
        }
        if state.phase != Phase::Finished || state.committing {
            return Err(error(LocalFileErrorCode::Busy, "复制尚未结束或正在提交。"));
        }
        if !matches!(&state.result, Some(Ok(_))) {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "失败的复制不能提交。",
            ));
        }
        state.committing = true;
        state.resources.take().expect("已完成复制资源")
    };
    // 提交 worker 独立持有资源与准入租约；等待者消失不能使 close 提前宣告完成。
    tokio::task::spawn_blocking(move || {
        let _lease = lease;
        let mut resources = resources;
        let result = if copy.stop.is_cancelled() {
            Err(error(LocalFileErrorCode::Cancelled, "提交准入已撤销。"))
        } else {
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                resources.commit(&scope.fs, &destination, &expected)
            }))
            .unwrap_or_else(|_| {
                resources.publication = filesystem::Publication::Unknown;
                Err(error(
                    LocalFileErrorCode::ResultUnknown,
                    "提交任务异常，保留内容且不重放提交。",
                ))
            })
        };
        let mut state = copy.state.lock().expect("本机复制状态");
        state.resources = Some(resources);
        state.committing = false;
        copy.changed.notify_waiters();
        result
    })
    .await
    .map_err(join_error)?
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::{ffi::OsStrExt, fs::PermissionsExt};
    type Barrier = (std::sync::mpsc::Sender<()>, std::sync::mpsc::Receiver<()>);
    fn barriers() -> &'static Mutex<HashMap<String, Barrier>> {
        static VALUE: OnceLock<Mutex<HashMap<String, Barrier>>> = OnceLock::new();
        VALUE.get_or_init(|| Mutex::new(HashMap::new()))
    }
    pub(super) fn after_create(id: &str) {
        let barrier = barriers().lock().unwrap().remove(id);
        if let Some((ready, release)) = barrier {
            ready.send(()).unwrap();
            release.recv().unwrap();
        }
    }
    #[tokio::test]
    async fn revoked_creation_keeps_failed_partial_cleanup_registered_for_scope_retry() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let id = open(
            vec![root.as_os_str().as_bytes().to_vec()],
            uuid::Uuid::new_v4().to_string(),
            2000,
        )
        .await
        .unwrap();
        let source = root.join("source");
        let part = root.join("part");
        std::fs::write(&source, b"bound but not admitted").unwrap();
        let (ready, entered) = std::sync::mpsc::channel();
        let (release, held) = std::sync::mpsc::channel();
        barriers().lock().unwrap().insert(id.clone(), (ready, held));
        let options = LocalFileCopyRequest {
            source_path: Some(source.as_os_str().as_bytes().to_vec()),
            source_fd: None,
            target_path: Some(part.as_os_str().as_bytes().to_vec()),
            target_fd: None,
            source_offset: 0,
            length: None,
            expected_source: None,
            max_bytes: 100,
            timeout_ms: 2000,
        };
        let creating = tokio::spawn(create_copy(id.clone(), options));
        tokio::task::spawn_blocking(move || entered.recv().unwrap())
            .await
            .unwrap();
        assert!(part.exists());
        assert_eq!(
            close_scope(id.clone(), 1).await.unwrap_err().code,
            LocalFileErrorCode::CleanupUnconfirmed
        );
        std::fs::set_permissions(root, std::fs::Permissions::from_mode(0o500)).unwrap();
        release.send(()).unwrap();
        let result = creating.await.unwrap();
        // 先恢复权限，保证断言失败时也不会留下本次测试资源。
        let retry = close_scope(id.clone(), 2000).await;
        std::fs::set_permissions(root, std::fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(result.unwrap_err().code, LocalFileErrorCode::ScopeClosed);
        assert!(retry.is_err());
        assert!(
            registry()
                .lock()
                .unwrap()
                .copies
                .values()
                .any(|copy| copy.scope_id == id)
        );
        close_scope(id, 2000).await.unwrap();
        assert!(!part.exists());
    }
}
