//! Typed bounded file execution; business snapshots and task ownership stay in Dart.
use interop_core::{
    CoreError, CoreResult,
    file_execution::{EntryFact, FileStamp},
};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};
use tokio::sync::{Mutex as AsyncMutex, mpsc};
use tokio_util::sync::CancellationToken;

pub struct FileExecutionRequest {
    pub action: String,
    pub device_id: String,
    pub path: String,
    pub destination: String,
    pub local: bool,
    pub follow_storage_alias: bool,
    pub limit: u32,
    pub push: bool,
    pub replace: bool,
    pub expected: Option<FileExecutionStamp>,
}
pub struct FileExecutionStamp {
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
    pub modified_nanos: u32,
}
pub struct FileExecutionEntry {
    pub name: Vec<u8>,
    pub stamp: Option<FileExecutionStamp>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}
pub struct FileExecutionEvent {
    pub kind: String,
    pub entries: Vec<FileExecutionEntry>,
    pub stamp: Option<FileExecutionStamp>,
    pub transferred: u64,
    pub truncated: bool,
    pub save_mode: Option<String>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}
fn event(kind: &str) -> FileExecutionEvent {
    FileExecutionEvent {
        kind: kind.into(),
        entries: Vec::new(),
        stamp: None,
        transferred: 0,
        truncated: false,
        save_mode: None,
        error_code: None,
        error_message: None,
    }
}
impl From<FileStamp> for FileExecutionStamp {
    fn from(s: FileStamp) -> Self {
        Self {
            mode: s.mode,
            size: s.size,
            modified_seconds: s.modified_seconds,
            modified_nanos: s.modified_nanos,
        }
    }
}
impl From<FileExecutionStamp> for FileStamp {
    fn from(s: FileExecutionStamp) -> Self {
        Self {
            mode: s.mode,
            size: s.size,
            modified_seconds: s.modified_seconds,
            modified_nanos: s.modified_nanos,
        }
    }
}
impl From<EntryFact> for FileExecutionEntry {
    fn from(e: EntryFact) -> Self {
        Self {
            name: e.name,
            stamp: e.stamp.map(Into::into),
            error_code: e.error_code,
            error_message: e.error_message,
        }
    }
}
#[flutter_rust_bridge::frb(ignore)]
struct FileOperation {
    token: CancellationToken,
    finished: CancellationToken,
    receiver: Arc<AsyncMutex<mpsc::Receiver<FileExecutionEvent>>>,
}
#[flutter_rust_bridge::frb(ignore)]
struct FileExecutionRegistry {
    operations: HashMap<String, FileOperation>,
}
fn registry() -> &'static Mutex<FileExecutionRegistry> {
    static OWNER: OnceLock<Mutex<FileExecutionRegistry>> = OnceLock::new();
    OWNER.get_or_init(|| {
        Mutex::new(FileExecutionRegistry {
            operations: HashMap::new(),
        })
    })
}
async fn send(
    tx: &mpsc::Sender<FileExecutionEvent>,
    token: &CancellationToken,
    e: FileExecutionEvent,
) -> CoreResult<()> {
    tokio::select! {biased;_=token.cancelled()=>Err(CoreError::new("cancelled","文件执行已取消。")),result=tokio::time::timeout(Duration::from_secs(45),tx.send(e))=>result.map_err(|_|CoreError::new("consumer_timeout","文件结果无人读取。"))?.map_err(|_|CoreError::new("cancelled","文件消费者已离开。"))}
}

pub async fn file_execute(request: FileExecutionRequest) -> Result<String, String> {
    if !matches!(
        request.action.as_str(),
        "stat" | "list" | "copy" | "mkdir" | "rename" | "delete" | "commit" | "releasePart"
    ) {
        return Err("unsupported: file execution action".into());
    }
    if request.action == "copy" && request.expected.is_none() {
        return Err("invalid_argument: expected file stamp required".into());
    }
    let runtime = crate::api::runtime().map_err(|e| e.to_string())?;
    let id = uuid::Uuid::new_v4().to_string();
    let token = CancellationToken::new();
    let finished = CancellationToken::new();
    let (tx, rx) = mpsc::channel(1);
    {
        let mut owner = registry().lock().map_err(|_| "file registry unavailable")?;
        if owner.operations.len() >= 128 {
            return Err("busy: file operation limit".into());
        }
        owner.operations.insert(
            id.clone(),
            FileOperation {
                token: token.clone(),
                finished: finished.clone(),
                receiver: Arc::new(AsyncMutex::new(rx)),
            },
        );
    }
    let key = format!("file:{}:{id}", request.device_id);
    runtime.register_file_execution(&key, token.clone()).await;
    tokio::spawn(async move {
        let work = async {
            match request.action.as_str() {
                "stat" => {
                    let stamp = runtime
                        .execute_file_stat(
                            &request.device_id,
                            &request.path,
                            request.local,
                            request.follow_storage_alias,
                            token.clone(),
                        )
                        .await?;
                    let mut e = event("stat");
                    e.stamp = Some(stamp.into());
                    send(&tx, &token, e).await?;
                }
                "list" => {
                    let facts = runtime
                        .execute_file_list(
                            &request.device_id,
                            &request.path,
                            request.local,
                            request.limit as usize,
                            token.clone(),
                        )
                        .await?;
                    let mut entries = facts.entries.into_iter();
                    loop {
                        let chunk = entries
                            .by_ref()
                            .take(128)
                            .map(Into::into)
                            .collect::<Vec<_>>();
                        if chunk.is_empty() {
                            break;
                        }
                        let mut e = event("entries");
                        e.entries = chunk;
                        send(&tx, &token, e).await?;
                    }
                    let mut e = event("done");
                    e.truncated = facts.truncated;
                    send(&tx, &token, e).await?;
                    return Ok::<_, CoreError>(());
                }
                "copy" => {
                    let progress = Arc::new(AtomicU64::new(0));
                    let copy = runtime.execute_file_copy(
                        &request.device_id,
                        &request.path,
                        &request.destination,
                        request.push,
                        request.expected.unwrap().into(),
                        token.clone(),
                        progress.clone(),
                    );
                    tokio::pin!(copy);
                    let mut ticker = tokio::time::interval(Duration::from_millis(100));
                    let mut last = 0;
                    loop {
                        tokio::select! {biased;result=&mut copy=>{let mut e=event("progress");e.transferred=result?;send(&tx,&token,e).await?;break;},_=ticker.tick()=>{let value=progress.load(Ordering::Relaxed);if value!=last{let mut e=event("progress");e.transferred=value;send(&tx,&token,e).await?;last=value;}}}
                    }
                }
                _ => {
                    let mode = runtime
                        .execute_file_mutation(
                            &request.device_id,
                            &request.action,
                            &request.path,
                            &request.destination,
                            request.local,
                            request.replace,
                            token.clone(),
                        )
                        .await?;
                    let mut e = event("receipt");
                    e.save_mode = Some(mode);
                    send(&tx, &token, e).await?;
                }
            }
            send(&tx, &token, event("done")).await
        };
        if let Err(error) = work.await {
            let mut e = event("error");
            e.error_code = Some(error.code);
            e.error_message = Some(error.message);
            let _ = send(&tx, &token, e).await;
        }
        runtime.unregister_file_execution(&key).await;
        finished.cancel();
    });
    Ok(id)
}
pub async fn file_next(operation_id: String) -> Result<Option<FileExecutionEvent>, String> {
    let receiver = {
        let owner = registry().lock().map_err(|_| "file registry unavailable")?;
        owner
            .operations
            .get(&operation_id)
            .ok_or("not_found: file operation")?
            .receiver
            .clone()
    };
    let mut receiver = receiver
        .try_lock()
        .map_err(|_| "busy: one file reader permitted")?;
    Ok(receiver.recv().await)
}
pub async fn file_cancel(operation_id: String) -> Result<(), String> {
    let operation = registry()
        .lock()
        .map_err(|_| "file registry unavailable")?
        .operations
        .remove(&operation_id);
    if let Some(operation) = operation {
        operation.token.cancel();
        tokio::time::timeout(Duration::from_secs(5), operation.finished.cancelled())
            .await
            .map_err(|_| "cleanup_unknown: file worker has not stopped")?;
    }
    Ok(())
}
pub struct FileCacheItem {
    pub path: String,
    pub bytes: u64,
}
pub async fn file_cache_reserve(items: Vec<FileCacheItem>) -> Result<String, String> {
    let (paths, bytes) = items
        .into_iter()
        .map(|item| (item.path, item.bytes))
        .unzip();
    crate::api::runtime()
        .map_err(|e| e.to_string())?
        .execute_file_cache_reserve(paths, bytes)
        .await
        .map_err(|e| format!("{}: {}", e.code, e.message))
}
pub async fn file_cache_release(lease_id: String) -> Result<(), String> {
    crate::api::runtime()
        .map_err(|e| e.to_string())?
        .execute_file_cache_release(&lease_id)
        .await
        .map_err(|e| format!("{}: {}", e.code, e.message))
}
/// Small publication control/lease facts only; never file contents or directory listings.
pub async fn file_share_publication(
    phase: String,
    share_id: String,
    control_json: String,
) -> Result<String, String> {
    if control_json.len() > 4 * 1024 * 1024 {
        return Err("control_limit: share publication control exceeds 4 MiB".into());
    }
    let params =
        serde_json::from_str(&control_json).map_err(|e| format!("invalid_argument: {e}"))?;
    crate::api::runtime()
        .map_err(|e| e.to_string())?
        .execute_file_publication(&phase, &share_id, params)
        .await
        .map(|value| value.to_string())
        .map_err(|e| format!("{}: {}", e.code, e.message))
}
