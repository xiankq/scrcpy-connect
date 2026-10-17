//! Cross-platform ownership for imported files, independent of a Flutter engine.
//! Platform adapters only validate user authority and lend descriptors/paths.
mod legacy;
mod policy;
mod source;
use crate::{CoreError, CoreResult, Runtime};
pub use policy::{Limits, SharedFile};
use policy::{Policy, valid_id};
use serde_json::{Value, json};
pub use source::Source;
use std::{
    collections::HashMap,
    fs::{File, OpenOptions},
    future::Future,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard, Weak},
};
use tokio::sync::{Semaphore, broadcast};
use tokio_util::sync::CancellationToken;

pub struct ImportManager {
    state: Mutex<Policy>,
    jobs: Mutex<HashMap<String, CancellationToken>>,
    workers: Arc<Semaphore>,
    io_slots: Arc<Semaphore>,
    submissions: Mutex<HashMap<String, Weak<tokio::sync::Mutex<()>>>>,
    events: broadcast::Sender<Value>,
}
fn lock<T>(value: &Mutex<T>) -> MutexGuard<'_, T> {
    value.lock().unwrap_or_else(|e| e.into_inner())
}
impl ImportManager {
    pub fn open(
        root: impl AsRef<Path>,
        allowed_cache_root: impl AsRef<Path>,
        limits: Limits,
    ) -> CoreResult<Arc<Self>> {
        let cache = std::fs::canonicalize(allowed_cache_root)?;
        let requested = root.as_ref();
        if !requested.is_absolute()
            || requested.file_name().is_none_or(|name| name != "incoming")
            || requested
                .parent()
                .and_then(|p| std::fs::canonicalize(p).ok())
                .as_ref()
                != Some(&cache)
        {
            return Err(CoreError::new(
                "invalid_share_root",
                "分享来源必须保存在本机已授权缓存的 incoming 子目录。",
            ));
        }
        std::fs::create_dir_all(requested)?;
        if std::fs::canonicalize(requested)? != cache.join("incoming") {
            return Err(CoreError::new(
                "invalid_share_root",
                "分享来源目录不能跳转到缓存范围以外。",
            ));
        }
        if limits.pending == 0
            || limits.sources == 0
            || limits.sources > 32
            || limits.pending > 8
            || limits.batches > 64
            || limits.leases > 128
        {
            return Err(CoreError::new(
                "invalid_share_limits",
                "分享导入保护配置无效。",
            ));
        }
        let (events, _) = broadcast::channel(64);
        Ok(Arc::new(Self {
            state: Mutex::new(Policy::open(cache.join("incoming"), limits)?),
            jobs: Mutex::new(HashMap::new()),
            workers: Arc::new(Semaphore::new(1)),
            io_slots: Arc::new(Semaphore::new(1)),
            submissions: Mutex::new(HashMap::new()),
            events,
        }))
    }
    pub fn root(&self) -> PathBuf {
        lock(&self.state).root.clone()
    }
    pub fn subscribe(&self) -> broadcast::Receiver<Value> {
        self.events.subscribe()
    }
    fn existing_import(&self, id: &str) -> Option<Value> {
        Self::existing_view(&lock(&self.state), id)
    }
    fn existing_view(state: &Policy, id: &str) -> Option<Value> {
        state.batches.get(id).map(|batch| {
            let mut receipt = state.view(batch);
            if batch.status == "importing" {
                receipt["status"] = json!("starting");
            }
            receipt["reusedImport"] = json!(true);
            receipt
        })
    }
    fn emit(&self, value: Value) {
        let _ = self
            .events
            .send(json!({"type":"share.received","data":value}));
    }
    fn forward_current(&self, event: &Value, output: &crate::events::EventBus) {
        let state = lock(&self.state);
        let current = event["data"]["shareId"]
            .as_str()
            .and_then(|id| state.batches.get(id))
            .filter(|batch| batch.visible);
        // Import events use a separate bounded queue. Give the runtime's
        // sequence to the current projection under its guard, not to stale
        // content captured before that queue was drained.
        let event = match current {
            Some(batch) => json!({"type":"share.received","data":state.view(batch)}),
            None => json!({"type":"state.resync","data":{"source":"sharing"}}),
        };
        let _ = output.send(event);
    }
    pub fn command(&self, command: &str, p: &Value) -> CoreResult<Value> {
        let id = || {
            p["shareId"]
                .as_str()
                .ok_or_else(|| CoreError::new("invalid_argument", "缺少分享标识。"))
        };
        let mut state = lock(&self.state);
        match command {
            "sharing.pending" => Ok(state.pending()),
            "sharing.sources" => Ok(state.sources()),
            "sharing.retain" => state.retain(id()?),
            "sharing.bind" => state.bind(required(p, "leaseId")?, required(p, "transferId")?),
            "sharing.release" => {
                if state
                    .leases
                    .get(required(p, "leaseId")?)
                    .is_some_and(|lease| lease.transfer_id.is_some() || lease.publication.is_some())
                {
                    return Err(CoreError::new(
                        "share_lease_in_use",
                        "分享来源仍属于任务或提交结果待核对；只能由完整任务协调回收。",
                    ));
                }
                state.release(required(p, "leaseId")?)?;
                Ok(json!({"released":true}))
            }
            "sharing.reconcile" => state.reconcile(&p["transfers"], p["complete"] == true),
            "sharing.reject" => {
                let id = id()?;
                // A late platform open failure belongs to that attempt, never
                // to an already accepted import owned by another engine.
                if state.batches.contains_key(id) {
                    return Ok(state.pending());
                }
                state.reserve(id, None, None)?;
                if let Some(event) =
                    state.fail(id, p["reason"].as_str().unwrap_or("系统未能打开分享来源。"))?
                {
                    self.emit(event);
                }
                Ok(state.pending())
            }
            "sharing.consume" => {
                if let Some(token) = lock(&self.jobs).get(id()?) {
                    token.cancel();
                }
                state.consume(id()?)?;
                Ok(json!({"consumed":true}))
            }
            "sharing.cancel" => {
                if let Some(token) = lock(&self.jobs).get(id()?) {
                    token.cancel();
                }
                if let Some(event) = state.fail(id()?, "分享导入已取消。")? {
                    self.emit(event);
                }
                Ok(json!({"cancelled":true,"shareId":id()?}))
            }
            _ => Err(CoreError::new("unknown_command", "分享来源操作无效。")),
        }
    }
    pub fn import(
        self: &Arc<Self>,
        id: &str,
        text: Option<String>,
        mime: Option<String>,
        sources: Vec<Source>,
    ) -> CoreResult<Value> {
        let cancellation = CancellationToken::new();
        let (maximum, timeout) = {
            let mut state = lock(&self.state);
            if let Some(receipt) = Self::existing_view(&state, id) {
                return Ok(receipt);
            }
            if sources.len() > state.limits.sources {
                return Err(CoreError::new(
                    "share_source_limit",
                    "一次最多分享32个来源。",
                ));
            }
            let mut jobs = lock(&self.jobs);
            if jobs.len() >= state.limits.pending {
                return Err(CoreError::new(
                    "share_cache_busy",
                    "分享导入队列仍在处理或清理，请稍后重试。",
                ));
            }
            if jobs.contains_key(id) {
                return Err(CoreError::new(
                    "share_import_in_progress",
                    "此分享的来源交接仍在清理，不能重放。",
                ));
            }
            state.reserve(id, text, mime)?;
            jobs.insert(id.into(), cancellation.clone());
            (state.limits.file_bytes, state.limits.timeout)
        };
        let adopted: CoreResult<Vec<_>> = sources.into_iter().map(|s| s.open(maximum)).collect();
        let sources = match adopted {
            Ok(sources) => sources,
            Err(error) => {
                lock(&self.jobs).remove(id);
                if let Some(event) = lock(&self.state).fail(id, &error.message)? {
                    self.emit(event);
                }
                return Err(error);
            }
        };
        let starting = json!({"shareId":id,"status":"starting"});
        let manager = self.clone();
        let id = id.to_owned();
        tokio::spawn(async move {
            let operation = manager.copy_batch(&id, sources, &cancellation);
            let result = tokio::select! {_ = cancellation.cancelled()=>Err(CoreError::new("cancelled","分享导入已取消。")),result=tokio::time::timeout(timeout,operation)=>match result{Ok(result)=>result,Err(_)=>Err(CoreError::new("timeout","分享导入超时，未发布部分文件。"))}};
            cancellation.cancel();
            if let Err(error) = result
                && let Ok(Some(event)) = lock(&manager.state).fail(&id, &error.message)
            {
                manager.emit(event);
            }
            lock(&manager.jobs).remove(&id);
            let _ = lock(&manager.state).cleanup_aborted(&id);
        });
        Ok(starting)
    }
    async fn copy_batch(
        self: &Arc<Self>,
        id: &str,
        sources: Vec<source::OpenSource>,
        token: &CancellationToken,
    ) -> CoreResult<()> {
        let _worker = self
            .workers
            .acquire()
            .await
            .map_err(|_| CoreError::new("cancelled", "分享导入已停止。"))?;
        let mut files = Vec::new();
        for (index, source) in sources.into_iter().enumerate() {
            if token.is_cancelled() {
                return Err(CoreError::new("cancelled", "分享导入已取消。"));
            }
            let disk = format!("{index}-{}", uuid::Uuid::new_v4());
            let path = lock(&self.state).directory(id)?.join(&disk);
            let mut options = OpenOptions::new();
            options.create_new(true).write(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let output = options.open(path)?;
            let size = self
                .copy_file(id, source.file, output, source.length, source.before, token)
                .await?;
            files.push(SharedFile {
                disk_name: disk,
                name: source.name,
                size,
            });
        }
        if token.is_cancelled() {
            return Err(CoreError::new("cancelled", "分享导入已取消。"));
        }
        if let Some(event) = lock(&self.state).complete(id, files)? {
            self.emit(event);
        }
        Ok(())
    }
    async fn copy_file(
        self: &Arc<Self>,
        id: &str,
        mut input: File,
        mut output: File,
        length: Option<u64>,
        before: Option<(u64, Option<std::time::SystemTime>)>,
        token: &CancellationToken,
    ) -> CoreResult<u64> {
        let mut size = 0u64;
        loop {
            if length == Some(size) {
                break;
            }
            let permit = self
                .io_slots
                .clone()
                .acquire_owned()
                .await
                .map_err(|_| CoreError::new("cancelled", "分享导入已停止。"))?;
            let manager = self.clone();
            let id = id.to_owned();
            let cancel = token.clone();
            let maximum = length.map_or(65536, |n| (n - size).min(65536) as usize);
            let chunk = tokio::task::spawn_blocking(move || {
                let _permit = permit;
                let mut buffer = vec![0; maximum];
                if cancel.is_cancelled() {
                    return Err(CoreError::new("cancelled", "分享导入已取消。"));
                }
                let count = match input.read(&mut buffer) {
                    Ok(n) => Some(n),
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => None,
                    Err(error) => return Err(error.into()),
                };
                if let Some(count) = count
                    && count > 0
                {
                    if cancel.is_cancelled() {
                        return Err(CoreError::new("cancelled", "分享导入已取消。"));
                    }
                    let mut state = lock(&manager.state);
                    if size.saturating_add(count as u64) > state.limits.file_bytes {
                        return Err(CoreError::new(
                            "share_byte_limit",
                            "单个分享文件超过容量上限。",
                        ));
                    }
                    if source::space_available(&state.root)
                        .is_some_and(|free| free < (32 * 1024 * 1024 + count as u64))
                    {
                        return Err(CoreError::new(
                            "insufficient_space",
                            "本机可用暂存空间不足。",
                        ));
                    }
                    state.append(&id, count as u64)?;
                    drop(state);
                    output.write_all(&buffer[..count])?;
                }
                Ok::<_, CoreError>((input, output, count))
            })
            .await
            .map_err(|_| CoreError::new("share_worker_failed", "分享复制任务意外结束。"))??;
            (input, output) = (chunk.0, chunk.1);
            match chunk.2 {
                Some(0) => {
                    if length.is_some_and(|n| n != size) {
                        return Err(CoreError::new("source_changed", "分享来源比声明范围短。"));
                    }
                    break;
                }
                Some(count) => size += count as u64,
                None => tokio::time::sleep(std::time::Duration::from_millis(5)).await,
            }
        }
        if let Some((old_size, old_modified)) = before {
            let current = input.metadata()?;
            if current.len() != old_size
                || (old_modified.is_some() && current.modified().ok() != old_modified)
            {
                return Err(CoreError::new(
                    "source_changed",
                    "分享来源在复制期间发生变化。",
                ));
            }
        }
        let permit = self
            .io_slots
            .clone()
            .acquire_owned()
            .await
            .map_err(|_| CoreError::new("cancelled", "分享导入已停止。"))?;
        tokio::task::spawn_blocking(move || {
            let _permit = permit;
            output.sync_all()
        })
        .await
        .map_err(|_| CoreError::new("share_worker_failed", "分享写入任务意外结束。"))??;
        Ok(size)
    }
    pub async fn submit_once<F, Fut>(
        self: &Arc<Self>,
        share: &str,
        params: &Value,
        operation: F,
    ) -> CoreResult<Value>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = CoreResult<Value>>,
    {
        self.submit_checked(share, params, || async {
            operation().await.map_err(|error| (error, false))
        })
        .await
    }
    pub(crate) async fn submit_checked<F, Fut>(
        self: &Arc<Self>,
        share: &str,
        params: &Value,
        operation: F,
    ) -> CoreResult<Value>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<Value, (CoreError, bool)>>,
    {
        let shared = {
            let mut locks = lock(&self.submissions);
            locks.retain(|_, value| value.strong_count() > 0);
            let value = locks
                .get(share)
                .and_then(Weak::upgrade)
                .unwrap_or_else(|| Arc::new(tokio::sync::Mutex::new(())));
            locks.insert(share.into(), Arc::downgrade(&value));
            value
        };
        let _guard = shared.lock().await;
        if let Some(mut receipt) = lock(&self.state).begin_publication(share, params)? {
            receipt["reusedTransfer"] = json!(true);
            return Ok(receipt);
        }
        let mut guard = PublicationGuard {
            manager: self.clone(),
            share: share.into(),
            finished: false,
        };
        match operation().await {
            Ok(receipt) => {
                let result = lock(&self.state).publication_finished(share, Some(&receipt));
                guard.finished = true;
                if result.is_err() {
                    let mut receipt = receipt;
                    receipt["sourceLeaseReconciliationPending"] = json!(true);
                    Ok(receipt)
                } else {
                    Ok(receipt)
                }
            }
            Err((error, definitely_unpublished)) => {
                if definitely_unpublished {
                    let _ = lock(&self.state).publication_aborted(share);
                } else {
                    let _ = lock(&self.state).publication_finished(share, None);
                }
                guard.finished = true;
                Err(error)
            }
        }
    }
}
struct PublicationGuard {
    manager: Arc<ImportManager>,
    share: String,
    finished: bool,
}
impl Drop for PublicationGuard {
    fn drop(&mut self) {
        if !self.finished {
            let _ = lock(&self.manager.state).publication_finished(&self.share, None);
        }
    }
}
fn required<'a>(value: &'a Value, key: &str) -> CoreResult<&'a str> {
    value[key]
        .as_str()
        .ok_or_else(|| CoreError::new("invalid_argument", format!("缺少参数 {key}。")))
}

impl Runtime {
    pub(crate) async fn sharing_manager(&self) -> CoreResult<Arc<ImportManager>> {
        self.sharing.lock().await.clone().ok_or_else(|| {
            CoreError::new("sharing_not_configured", "分享来源尚未连接本机授权缓存。")
        })
    }
    pub(crate) async fn sharing_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        if command == "sharing.configure" {
            let root = PathBuf::from(required(params, "absoluteRoot")?);
            let cache = PathBuf::from(required(params, "allowedCacheRoot")?);
            let mut slot = self.sharing.lock().await;
            if let Some(manager) = slot.as_ref() {
                if std::fs::canonicalize(&root)? != manager.root() {
                    return Err(CoreError::new(
                        "sharing_root_changed",
                        "本进程分享缓存已经配置，不能切换来源目录。",
                    ));
                }
                return Ok(json!({"configured":true,"absoluteRoot":manager.root()}));
            }
            let manager = ImportManager::open(root, cache, Limits::default())?;
            let mut events = manager.subscribe();
            let output = self.events.clone();
            let source = Arc::downgrade(&manager);
            tokio::spawn(async move {
                loop {
                    match events.recv().await {
                        Ok(event) => {
                            let Some(manager) = source.upgrade() else {
                                break;
                            };
                            manager.forward_current(&event, &output);
                        }
                        Err(broadcast::error::RecvError::Lagged(_)) => {
                            events = events.resubscribe();
                            let _ = output
                                .send(json!({"type":"state.resync","data":{"source":"sharing"}}));
                        }
                        Err(_) => break,
                    }
                }
            });
            let result = json!({"configured":true,"absoluteRoot":manager.root()});
            *slot = Some(manager);
            drop(slot);
            self.reconcile_shares_from_transfers().await?;
            return Ok(result);
        }
        let manager = self.sharing_manager().await?;
        if command == "sharing.import" {
            let id = required(params, "shareId")?;
            if !valid_id(id) {
                return Err(CoreError::new("invalid_argument", "分享标识必须是UUID。"));
            }
            if let Some(receipt) = manager.existing_import(id) {
                return Ok(receipt);
            }
            if params["sources"]
                .as_array()
                .is_none_or(|sources| sources.len() > 32)
            {
                return Err(CoreError::new(
                    "share_source_limit",
                    "分享来源必须是最多32项的列表。",
                ));
            }
            let sources: Vec<Source> = serde_json::from_value(params["sources"].clone())?;
            return manager.import(
                id,
                params["text"].as_str().map(String::from),
                params["mime"].as_str().map(String::from),
                sources,
            );
        }
        if command == "sharing.reconcile" && !params.get("transfers").is_some() {
            return self.reconcile_shares_from_transfers().await;
        }
        manager.command(command, params)
    }
    pub(crate) async fn reconcile_shares_from_transfers(&self) -> CoreResult<Value> {
        let Some(manager) = self.sharing.lock().await.clone() else {
            return Ok(json!({"reconciled":false,"reason":"not_configured"}));
        };
        let known: std::collections::HashSet<_> = manager
            .command("sharing.sources", &Value::Null)?["sourcePaths"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(String::from)
            .collect();
        // Match transfer persistence's lock order. Keep the snapshot stable until
        // journal reconciliation finishes: a memory-only completed transition is
        // never evidence that a resumable source may be deleted.
        let _persistence = self.persistence.lock().await;
        let tasks = self.transfers.lock().await;
        let snapshot: Vec<_> = tasks.values().collect();
        let persisted = async {
            Self::private_write(
                &self.root.join("transfers.json"),
                &serde_json::to_vec(&snapshot)?,
            )
            .await?;
            #[cfg(unix)]
            {
                let root = self.root.clone();
                tokio::task::spawn_blocking(move || File::open(root)?.sync_all())
                    .await
                    .map_err(|error| CoreError::new("persistence_failed", error.to_string()))??;
            }
            Ok::<_, CoreError>(())
        }
        .await;
        if persisted.is_err() {
            return Ok(
                json!({"reconciled":false,"snapshotComplete":false,"reason":"transfer_snapshot_not_durable","sourcesRetained":true}),
            );
        }
        let mut groups: std::collections::BTreeMap<
            String,
            (bool, std::collections::BTreeSet<String>),
        > = std::collections::BTreeMap::new();
        let mut relevant = std::collections::HashSet::new();
        for task in tasks
            .values()
            .filter(|task| task.direction == "push" && known.contains(&task.source))
        {
            relevant.insert(task.batch_id.clone());
            if relevant.len() > 1024 {
                return manager.command(
                    "sharing.reconcile",
                    &json!({"transfers":vec![Value::Null;1025],"complete":true}),
                );
            }
        }
        for task in tasks
            .values()
            .filter(|t| t.direction == "push" && relevant.contains(&t.batch_id))
        {
            let entry = groups
                .entry(task.batch_id.clone())
                .or_insert((true, Default::default()));
            entry.0 &= task.status == "completed";
            if known.contains(&task.source) {
                entry.1.insert(task.source.clone());
            }
        }
        let refs:Vec<_>=groups.into_iter().map(|(id,(complete,sources))|json!({"id":id,"status":if complete{"completed"}else{"retained"},"sources":sources})).collect();
        manager.command(
            "sharing.reconcile",
            &json!({"transfers":refs,"complete":true}),
        )
    }
}
