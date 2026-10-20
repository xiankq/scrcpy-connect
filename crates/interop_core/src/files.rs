use crate::{
    CoreError, CoreResult, Runtime,
    model::{mime, now, quote, remote_path, required},
};
use base64::Engine as _;
use interop_adb::{
    CancellationToken, OperationOptions,
    sync::{FileStat, RemotePath},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{Mutex as StdMutex, OnceLock, Weak};
use std::{
    path::{Path, PathBuf},
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    fs,
    io::{AsyncRead, AsyncWrite, ReadBuf},
};

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Transfer {
    pub id: String,
    pub device_id: String,
    pub direction: String,
    pub source: String,
    pub destination: String,
    pub name: String,
    pub status: String,
    pub transferred: u64,
    pub total: Option<u64>,
    pub error: Option<String>,
    pub policy: String,
    pub created_at: u64,
    #[serde(default)]
    pub batch_id: String,
    #[serde(default)]
    pub item_index: usize,
    #[serde(default = "one")]
    pub item_count: usize,
    #[serde(default)]
    pub default_policy: Option<String>,
    #[serde(default)]
    pub generation: u64,
    #[serde(default)]
    pub error_code: Option<String>,
    #[serde(default)]
    pub source_stamp: Option<SourceStamp>,
    #[serde(default)]
    pub save_mode: Option<String>,
    #[serde(default)]
    pub partial_destination_possible: bool,
    #[serde(default)]
    pub temporary_path: Option<String>,
    #[serde(default = "file_kind")]
    pub kind: String,
    #[serde(default)]
    pub parent_id: Option<String>,
    #[serde(default)]
    pub tree_verified: bool,
    #[serde(default)]
    pub tree_complete: bool,
    #[serde(default = "local_scope")]
    pub destination_scope: String,
    #[serde(default)]
    pub cache_evicted: bool,
    #[serde(skip)]
    pub cancellation: CancellationToken,
}
fn one() -> usize {
    1
}
fn file_kind() -> String {
    "file".into()
}
fn local_scope() -> String {
    "localPath".into()
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SourceStamp {
    pub(crate) size: u64,
    mode: u32,
    modified_seconds: i64,
    modified_nanos: u32,
}
impl From<FileStat> for SourceStamp {
    fn from(s: FileStat) -> Self {
        Self {
            size: s.size,
            mode: s.mode,
            modified_seconds: s.modified_seconds,
            modified_nanos: 0,
        }
    }
}
pub(crate) async fn local_stamp(path: &str) -> CoreResult<SourceStamp> {
    let meta = fs::symlink_metadata(path).await?;
    if !meta.is_file() {
        return Err(CoreError::new(
            "not_a_file",
            "源路径已不再是普通文件；不会跟随符号链接。",
        ));
    }
    metadata_stamp(&meta)
}
pub(crate) fn metadata_stamp(meta: &std::fs::Metadata) -> CoreResult<SourceStamp> {
    let modified = meta
        .modified()?
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| CoreError::new("invalid_timestamp", "源文件时间戳无效。"))?;
    Ok(SourceStamp {
        size: meta.len(),
        mode: 0,
        modified_seconds: modified.as_secs().min(i64::MAX as u64) as i64,
        modified_nanos: modified.subsec_nanos(),
    })
}
fn valid_policy(policy: &str) -> CoreResult<()> {
    if ["ask", "keepBoth", "replace", "skip"].contains(&policy) {
        Ok(())
    } else {
        Err(CoreError::new("invalid_argument", "同名处理方式无效。"))
    }
}
fn terminal(status: &str) -> bool {
    matches!(
        status,
        "completed" | "skipped" | "failed" | "cancelled" | "interrupted"
    )
}
fn transfer_value(task: &Transfer) -> Value {
    let mut value = serde_json::to_value(task).unwrap_or(Value::Null);
    value["canResume"] = json!(false);
    value["canRestart"] = json!(
        matches!(task.kind.as_str(), "file" | "directory")
            && matches!(task.status.as_str(), "failed" | "cancelled" | "interrupted")
            && !matches!(
                task.error_code.as_deref(),
                Some("result_unknown" | "source_changed")
            )
    );
    value["restartFromBeginning"] = json!(true);
    value["restartRequiresSourceCheck"] = json!(true);
    value["canCancel"] = json!(!terminal(&task.status));
    let cache_evicted = task.cache_evicted
        || (task.direction == "pull"
            && task.destination_scope == "privateCache"
            && terminal(&task.status)
            && std::fs::symlink_metadata(&task.destination).is_err());
    value["cacheEvicted"] = json!(cache_evicted);
    let can_export = !cache_evicted
        && task.direction == "pull"
        && task.status == "completed"
        && (task.kind == "file"
            || (task.kind == "directory" && task.tree_verified && task.tree_complete));
    value["canExport"] = json!(can_export);
    value["canExportPartial"] = json!(
        !cache_evicted
            && task.direction == "pull"
            && task.kind == "directory"
            && task.tree_verified
            && !task.tree_complete
            && task.save_mode.as_deref() == Some("directoryMerge")
    );
    if value["canExportPartial"] == true {
        value["partialLocalPath"] = json!(task.destination);
    }
    if task.kind == "directory" && !can_export {
        value["exportReason"] = json!(if !task.tree_verified {
            "目录仍在传输或核验，暂不能保存到系统位置。"
        } else {
            "目录存在失败、变化或跳过项目；请先核对取回内容，不能作为完整目录保存。"
        });
    }
    if can_export {
        value["localPath"] = json!(task.destination);
    }
    value
}
fn batch_values(tasks: &[Transfer]) -> Vec<Value> {
    let mut groups: std::collections::BTreeMap<&str, Vec<&Transfer>> = Default::default();
    for task in tasks {
        groups.entry(&task.batch_id).or_default().push(task);
    }
    groups.into_iter().map(|(id,tasks)| {
        let count=|status:&str|tasks.iter().filter(|task|task.status==status).count();
        let active=tasks.iter().any(|task|matches!(task.status.as_str(),"queued"|"running"|"finalizing"|"cancelling") || (task.kind=="directory"&&task.status=="completed"&&!task.tree_verified));
        let failed=count("failed");let cancelled=count("cancelled");let skipped=count("skipped");let interrupted=count("interrupted");
        let status=if count("conflict")>0 {"conflict"} else if active {"running"} else if failed>0 {"partialFailure"}
            else if interrupted>0 {"interrupted"} else if cancelled>0 {"cancelled"} else if skipped>0 {"completedWithSkips"} else {"completed"};
        json!({"batchId":id,"deviceId":tasks[0].device_id,"direction":tasks[0].direction,"destinationScope":tasks[0].destination_scope,"status":status,"itemCount":tasks.len(),
            "fileCount":tasks.iter().filter(|task|task.kind=="file").count(),"directoryCount":tasks.iter().filter(|task|task.kind=="directory").count(),
            "completed":count("completed"),"failed":failed,"cancelled":cancelled,"skipped":skipped,"interrupted":interrupted,
            "transferred":tasks.iter().fold(0_u64,|sum,task|sum.saturating_add(task.transferred)),"total":tasks.iter().filter_map(|task|task.total).fold(0_u64,u64::saturating_add),
            "canResume":false,"canRestart":false,"canCancel":active||count("conflict")>0,"selectionSnapshot":true,
            "selectedRootCount":tasks.iter().filter(|task|task.parent_id.is_none()).count()})
    }).collect()
}
fn check_cancel(token: &CancellationToken) -> CoreResult<()> {
    if token.is_cancelled() {
        Err(CoreError::new("cancelled", "传输已取消。"))
    } else {
        Ok(())
    }
}

#[derive(Serialize, Deserialize)]
struct MediaCache {
    source: SourceStamp,
    local_size: u64,
    sha256: String,
}

const MAX_THUMBNAIL: usize = 256 * 1024;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ThumbnailSource {
    device: String,
    inode: String,
    mode: u32,
    size: u64,
    modified_seconds: i64,
    changed_seconds: i64,
    modified_nanos: Option<u32>,
    changed_nanos: Option<u32>,
}
impl ThumbnailSource {
    fn parse(value: &Value) -> CoreResult<Self> {
        let source: Self = serde_json::from_value(value.clone())?;
        if source.mode & 0o170000 != 0o100000
            || source.size > 64 * 1024 * 1024 * 1024
            || source.device.parse::<i64>().is_err()
            || source.inode.parse::<i64>().is_err()
            || source.modified_nanos.is_some_and(|n| n >= 1_000_000_000)
            || source.changed_nanos.is_some_and(|n| n >= 1_000_000_000)
        {
            return Err(CoreError::new("invalid_data", "缩略图源元数据无效。"));
        }
        Ok(source)
    }
    fn validation(&self) -> &'static str {
        if self.modified_nanos.is_some() && self.changed_nanos.is_some() {
            "descriptorDeviceInodeSizeModeMtimeCtimeWithNanosecondFields"
        } else {
            "descriptorDeviceInodeSizeModeMtimeCtimeSeconds"
        }
    }
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ThumbnailCache {
    version: u32,
    source: ThumbnailSource,
    sha256: String,
    jpeg_bytes: u64,
    width: u32,
    height: u32,
    #[serde(default)]
    artifact: String,
}
fn jpeg_dimensions(bytes: &[u8]) -> CoreResult<(u32, u32)> {
    let invalid = || CoreError::new("invalid_thumbnail", "缩略图 JPEG 结构或尺寸无效。");
    if !bytes.starts_with(&[0xff, 0xd8]) || !bytes.ends_with(&[0xff, 0xd9]) {
        return Err(invalid());
    }
    let mut offset = 2;
    while offset + 4 <= bytes.len() {
        if bytes[offset] != 0xff {
            return Err(invalid());
        }
        while offset < bytes.len() && bytes[offset] == 0xff {
            offset += 1;
        }
        let marker = *bytes.get(offset).ok_or_else(invalid)?;
        offset += 1;
        if marker == 0xda || marker == 0xd9 {
            return Err(invalid());
        }
        if marker == 0x01 || (0xd0..=0xd8).contains(&marker) {
            continue;
        }
        let length_bytes = bytes.get(offset..offset + 2).ok_or_else(invalid)?;
        let length = u16::from_be_bytes(length_bytes.try_into().expect("length")) as usize;
        if length < 2 || offset + length > bytes.len() {
            return Err(invalid());
        }
        if matches!(marker, 0xc0..=0xc2) {
            if length < 8 || bytes[offset + 2] != 8 {
                return Err(invalid());
            }
            let height =
                u16::from_be_bytes(bytes[offset + 3..offset + 5].try_into().expect("height"))
                    as u32;
            let width =
                u16::from_be_bytes(bytes[offset + 5..offset + 7].try_into().expect("width")) as u32;
            if width == 0 || height == 0 || width > 512 || height > 512 {
                return Err(invalid());
            }
            return Ok((width, height));
        }
        offset += length;
    }
    Err(invalid())
}

fn thumbnail_claim(key: &str, cancelled: bool) -> CoreResult<bool> {
    static SEEN: OnceLock<StdMutex<HashMap<String, bool>>> = OnceLock::new();
    let mut seen = SEEN
        .get_or_init(Default::default)
        .lock()
        .map_err(|_| CoreError::new("media_error", "缩略图操作标识不可用。"))?;
    if let Some(was_cancelled) = seen.get(key) {
        if cancelled {
            return Ok(false);
        }
        return Err(CoreError::new(
            if *was_cancelled {
                "cancelled"
            } else {
                "operation_reused"
            },
            "此缩略图操作已结束或取消，请使用新的操作标识。",
        ));
    }
    if seen.len() >= 65536 {
        return Err(CoreError::new(
            "operation_limit",
            "缩略图操作标识已达到本次进程上限，请重新打开应用。",
        ));
    }
    seen.insert(key.into(), cancelled);
    Ok(true)
}
fn thumbnail_identity(root: &Path, device: &str, operation: &str) -> (String, String) {
    let active = format!("thumbnail:{device}:{operation}");
    let seen = hex::encode(Sha256::digest(format!("{}:{active}", root.display())));
    (active, seen)
}
struct ThumbnailOperation {
    runtime: Weak<Runtime>,
    key: String,
    device: String,
    token: CancellationToken,
    phase: Arc<StdMutex<Option<String>>>,
    armed: bool,
}
impl Drop for ThumbnailOperation {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        self.token.cancel();
        let phase = self.phase.lock().ok().and_then(|mut phase| phase.take());
        let Some(runtime) = self.runtime.upgrade() else {
            return;
        };
        let key = self.key.clone();
        let device = self.device.clone();
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                if let Some(phase) = phase {
                    let _ = tokio::time::timeout(
                        Duration::from_secs(6),
                        runtime.cancel_companion_media(&device, &phase),
                    )
                    .await;
                }
                runtime.device_operations.lock().await.remove(&key);
            });
        }
    }
}
type CacheLocks = HashMap<String, Weak<tokio::sync::Mutex<()>>>;
fn cache_lock(key: &str) -> CoreResult<Arc<tokio::sync::Mutex<()>>> {
    static LOCKS: OnceLock<StdMutex<CacheLocks>> = OnceLock::new();
    let mut locks = LOCKS
        .get_or_init(Default::default)
        .lock()
        .map_err(|_| CoreError::new("cache_error", "媒体缓存锁不可用。"))?;
    locks.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = locks.get(key).and_then(Weak::upgrade) {
        return Ok(lock);
    }
    let lock = Arc::new(tokio::sync::Mutex::new(()));
    locks.insert(key.into(), Arc::downgrade(&lock));
    Ok(lock)
}
async fn file_digest(path: &Path) -> CoreResult<String> {
    use tokio::io::AsyncReadExt;
    let mut file = fs::File::open(path).await?;
    let mut buffer = vec![0u8; 64 * 1024];
    let mut hash = Sha256::new();
    loop {
        let n = file.read(&mut buffer).await?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
    }
    Ok(hex::encode(hash.finalize()))
}

struct ProgressIo<T> {
    inner: T,
    progress: Arc<AtomicU64>,
}
impl<T: AsyncRead + Unpin> AsyncRead for ProgressIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buffer.filled().len();
        let result = Pin::new(&mut self.inner).poll_read(cx, buffer);
        if result.is_ready() {
            self.progress
                .fetch_add((buffer.filled().len() - before) as u64, Ordering::Relaxed);
        }
        result
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for ProgressIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let result = Pin::new(&mut self.inner).poll_write(cx, bytes);
        if let Poll::Ready(Ok(n)) = result {
            self.progress.fetch_add(n as u64, Ordering::Relaxed);
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

impl Runtime {
    pub(crate) async fn list_files(&self, p: &Value) -> CoreResult<Value> {
        let id = required(p, "deviceId")?;
        let path = remote_path(p["path"].as_str().unwrap_or("/sdcard"))?;
        let client = self.client(id).await?;
        let mut sync = client.sync(OperationOptions::default()).await?;
        let listed = if client.info().features.contains("ls_v2") {
            sync.list(&RemotePath::new(&path)?, 10_000).await
        } else {
            Err(interop_adb::Error::Unsupported("ls_v2"))
        };
        let mut entries = match listed {
            Ok(entries) => entries,
            Err(_) => {
                let listing = crate::remote_fs::fallback_children(
                    &client,
                    &path,
                    10_000,
                    OperationOptions::default(),
                )
                .await?;
                if listing.truncated {
                    return Err(CoreError::new(
                        "directory_limit",
                        "目录超过 10000 项，请在手机上将内容分组后读取。",
                    ));
                }
                listing
                    .entries
                    .into_iter()
                    .map(|(name, stat)| stat.map(|stat| interop_adb::sync::DirEntry { name, stat }))
                    .collect::<CoreResult<Vec<_>>>()?
            }
        };
        entries.sort_by(|a, b| {
            let directory = |mode: u32| mode & 0o170000 == 0o040000;
            directory(b.stat.mode)
                .cmp(&directory(a.stat.mode))
                .then_with(|| a.name.cmp(&b.name))
        });
        let entries: Vec<_> = entries.into_iter().map(|entry| {
            let name = String::from_utf8_lossy(&entry.name).into_owned();
            let valid = std::str::from_utf8(&entry.name).is_ok();
            let full = valid.then(|| format!("{}/{}",path.trim_end_matches('/'),name));
            json!({"name":name,"path":full,"isDirectory":entry.stat.mode&0o170000==0o040000,
                "isSymlink":entry.stat.mode&0o170000==0o120000,"size":entry.stat.size,
                "modified":entry.stat.modified_seconds,"mime":mime(full.as_deref().unwrap_or("")),"nameIsUtf8":valid,
                "canOpen":valid,"canManage":valid,"reason":if valid { Value::Null } else { json!("此文件名无法转换为有效文字，暂时无法操作。") }})
        }).collect();
        Ok(json!({"path":path,"entries":entries}))
    }

    pub(crate) async fn mutate_files(&self, command: &str, p: &Value) -> CoreResult<Value> {
        let client = self.client(required(p, "deviceId")?).await?;
        if command == "files.rename" {
            return self.rename_remote_file(&client, p).await;
        }
        let script = match command {
            "files.mkdir" => {
                let path = remote_path(required(p, "path")?)?;
                format!("mkdir {}", quote(&path)?)
            }
            "files.delete" => {
                let paths = p["paths"]
                    .as_array()
                    .filter(|a| !a.is_empty() && a.len() <= 1000)
                    .ok_or_else(|| CoreError::new("invalid_argument", "请选择要删除的文件。"))?;
                let mut quoted = Vec::new();
                for item in paths {
                    let path = remote_path(
                        item.as_str()
                            .ok_or_else(|| CoreError::new("invalid_path", "文件路径无效。"))?,
                    )?;
                    if matches!(
                        path.as_str(),
                        "/" | "/sdcard" | "/storage" | "/storage/emulated" | "/storage/emulated/0"
                    ) {
                        return Err(CoreError::new("invalid_path", "不能删除整个存储根目录。"));
                    }
                    quoted.push(quote(&path)?);
                }
                format!("rm -rf -- {}", quoted.join(" "))
            }
            _ => unreachable!(),
        };
        let result =
            crate::remote_fs::command(&client, &script, 1_048_576, OperationOptions::default())
                .await;
        let result = result.map_err(|e| {
            let mut error = e;
            if command == "files.delete" {
                error.code = "result_unknown".into();
                error.message =
                    "连接中断，删除结果尚不确定；请刷新手机目录核对，不会自动重试。".into();
            }
            error
        })?;
        if result.exit_code != Some(0) {
            return Err(CoreError::new(
                "remote_error",
                String::from_utf8_lossy(&result.stderr).into_owned(),
            ));
        }
        Ok(json!({"status":"completed"}))
    }

    async fn rename_remote_file(
        &self,
        client: &interop_adb::Client,
        p: &Value,
    ) -> CoreResult<Value> {
        let path = remote_path(required(p, "path")?)?;
        let name = required(p, "name")?;
        if name.contains('/') || matches!(name, "." | "..") {
            return Err(CoreError::new("invalid_name", "名称不能包含路径分隔符。"));
        }
        let parent = path.rsplit_once('/').map(|(p, _)| p).unwrap_or("");
        let target = format!("{parent}/{name}");
        if path == target {
            return Ok(json!({"status":"completed","path":target,"changed":false}));
        }
        crate::remote_helper::remote_rename(client, &path, &target, false).await
    }

    pub(crate) async fn restore_transfers(&self) -> CoreResult<()> {
        let transfers: Vec<Transfer> = self
            .transfer_store
            .lock()
            .await
            .snapshot()
            .into_iter()
            .map(serde_json::from_value)
            .collect::<Result<_, _>>()?;
        let mut store = self.activities.transfers.lock().await;
        for mut task in transfers {
            if task.kind == "directory" && task.status == "completed" && !task.tree_verified {
                task.status = "interrupted".into();
                task.error = Some(
                    "上次目录快照尚未核验完毕；已创建目录保留，重新传输需核验源和目标。".into(),
                );
            }
            if matches!(task.status.as_str(), "finalizing" | "cancelling") {
                task.error_code = Some("result_unknown".into());
                task.partial_destination_possible = true;
                task.error = Some("上次进程在保存或取消期间结束；目标可能已有完整或部分文件，请刷新核对后发起新任务。".into());
            }
            if matches!(
                task.status.as_str(),
                "running" | "queued" | "finalizing" | "cancelling"
            ) {
                task.status = "interrupted".into();
                if task.error_code.as_deref() != Some("result_unknown") {
                    task.error =
                        Some("上次进程已结束；重新传输将从头开始并核验源文件和目标。".into());
                }
            }
            if task.batch_id.is_empty() {
                task.batch_id = task.id.clone();
            }
            store.insert(task.id.clone(), task);
        }
        let missing = store
            .values()
            .filter(|task| {
                task.direction == "pull"
                    && task.destination_scope == "privateCache"
                    && task.kind == "file"
                    && task.status == "completed"
                    && std::fs::symlink_metadata(&task.destination).is_err()
            })
            .map(|task| PathBuf::from(&task.destination))
            .collect::<Vec<_>>();
        for task in store
            .values_mut()
            .filter(|task| task.direction == "pull" && task.destination_scope == "privateCache")
        {
            if missing
                .iter()
                .any(|path| path.starts_with(&task.destination))
            {
                task.cache_evicted = true;
            }
        }
        Ok(())
    }
    pub(crate) async fn persist_transfers(&self) -> CoreResult<()> {
        let _guard = self.persistence.lock().await;
        let tasks = self.activities.transfers.lock().await;
        self.transfer_store.lock().await.persist_all(&tasks).await
    }
    async fn persist_transfer(&self, id: &str) -> CoreResult<()> {
        let _guard = self.persistence.lock().await;
        let tasks = self.activities.transfers.lock().await;
        if let Some(task) = tasks.get(id) {
            self.transfer_store
                .lock()
                .await
                .persist_one(id, task)
                .await?;
        }
        Ok(())
    }
    async fn persist_transfer_ids(&self, ids: &[String]) -> CoreResult<()> {
        let _guard = self.persistence.lock().await;
        let tasks = self.activities.transfers.lock().await;
        let mut store = self.transfer_store.lock().await;
        store
            .persist_selected(
                ids.iter()
                    .filter_map(|id| tasks.get(id).map(|task| (id.as_str(), task))),
            )
            .await
    }
    pub(crate) async fn list_transfers(&self) -> CoreResult<Value> {
        let mut tasks: Vec<_> = self
            .activities
            .transfers
            .lock()
            .await
            .values()
            .cloned()
            .collect();
        tasks.sort_by_key(|t| std::cmp::Reverse(t.created_at));
        Ok(
            json!({"transfers":tasks.iter().map(transfer_value).collect::<Vec<_>>(),"batches":batch_values(&tasks)}),
        )
    }

    /// Forget durable history only, after every selected batch has stopped.
    /// Files and cache leases belong to their existing owners, not this action.
    pub(crate) async fn remove_transfer_record(&self, p: &Value) -> CoreResult<Value> {
        let transfer = p["transferId"].as_str().filter(|id| !id.is_empty());
        let batch = p["batchId"].as_str().filter(|id| !id.is_empty());
        if transfer.is_some() == batch.is_some() {
            return Err(CoreError::new(
                "invalid_argument",
                "请选择一条任务或一批传输。",
            ));
        }
        // Settle incoming-share ownership before its transfer evidence disappears.
        self.reconcile_shares_from_transfers().await?;
        let _cache = self.media_cache.gate.lock().await;
        let _persistence = self.persistence.lock().await;
        let mut tasks = self.activities.transfers.lock().await;
        let target_batch = match transfer {
            Some(id) => tasks.get(id).map(|task| task.batch_id.as_str()),
            None => batch,
        }
        .ok_or_else(|| CoreError::new("not_found", "传输记录已不存在。"))?
        .to_owned();
        if tasks.values().any(|task| {
            task.batch_id == target_batch
                && (!terminal(&task.status)
                    || (task.kind == "directory"
                        && task.status == "completed"
                        && !task.tree_verified))
        }) {
            return Err(CoreError::new(
                "transfer_active",
                "同批传输尚未结束，请先停止传输。",
            ));
        }
        let mut ids: std::collections::HashSet<String> = tasks
            .values()
            .filter(|task| match transfer {
                Some(id) => task.id == id,
                None => task.batch_id == target_batch,
            })
            .map(|task| task.id.clone())
            .collect();
        if ids.is_empty() {
            return Err(CoreError::new("not_found", "传输记录已不存在。"));
        }
        // Removing a directory row includes its descendants, never orphaning them.
        loop {
            let children: Vec<_> = tasks
                .values()
                .filter(|task| task.parent_id.as_ref().is_some_and(|id| ids.contains(id)))
                .map(|task| task.id.clone())
                .collect();
            let before = ids.len();
            ids.extend(children);
            if ids.len() == before {
                break;
            }
        }
        let ids: Vec<_> = ids.into_iter().collect();
        self.transfer_store.lock().await.remove(ids.clone()).await?;
        for id in &ids {
            tasks.remove(id);
        }
        drop(tasks);
        self.emit("transfer.changed", None, json!({"removedIds":ids}));
        Ok(json!({"removedIds":ids,"filesRemoved":false}))
    }
    pub(crate) async fn start_transfer(
        self: &Arc<Self>,
        command: &str,
        p: Value,
    ) -> CoreResult<Value> {
        let device_id = required(&p, "deviceId")?.to_owned();
        self.client(&device_id).await?;
        let push = command == "files.push";
        let destination_scope = p["destinationScope"].as_str().unwrap_or("localPath");
        if !["localPath", "privateCache"].contains(&destination_scope) {
            return Err(CoreError::new("invalid_argument", "目标位置类型无效。"));
        }
        let items = match p.get("items") {
            Some(Value::Array(items)) if !items.is_empty() && items.len() <= 1000 => items.clone(),
            Some(_) => {
                return Err(CoreError::new(
                    "invalid_argument",
                    "批任务需包含 1 到 1000 个文件。",
                ));
            }
            None => vec![p.clone()],
        };
        let batch_id = uuid::Uuid::new_v4().to_string();
        let policy = p["conflict"].as_str().unwrap_or("ask");
        valid_policy(policy)?;
        let mut selection = crate::file_tree::Selection::new();
        let client = self.client(&device_id).await?;
        tokio::time::timeout(Duration::from_secs(120), async {
            for item in &items {
                if item["deviceId"].as_str().is_some_and(|v| v != device_id)
                    || item["direction"]
                        .as_str()
                        .is_some_and(|v| v != if push { "push" } else { "pull" })
                {
                    return Err(CoreError::new(
                        "invalid_argument",
                        "一个批任务只能属于同一台设备和同一传输方向。",
                    ));
                }
                let source = if push {
                    required(item, "source")?.to_owned()
                } else {
                    remote_path(required(item, "path")?)?
                };
                let destination = if push {
                    remote_path(required(item, "destination")?)?
                } else {
                    required(item, "destination")?.to_owned()
                };
                if !Path::new(if push { &source } else { &destination }).is_absolute() {
                    return Err(CoreError::new("invalid_path", "本机路径必须使用绝对路径。"));
                }
                if push {
                    selection.local(source, destination).await?;
                } else {
                    selection.remote(&client, source, destination).await?;
                }
            }
            Ok::<(), CoreError>(())
        })
        .await
        .map_err(|_| {
            CoreError::new(
                "tree_scan_timeout",
                "目录扫描超过两分钟；没有写入任何目标，请分批选择。",
            )
        })??;
        let _cache_gate = if !push && destination_scope == "privateCache" {
            let gate = self.media_cache.gate.lock().await;
            for entry in selection
                .entries
                .iter()
                .filter(|entry| entry.parent.is_none())
            {
                self.cache_validate_destination_locked(&entry.destination)
                    .await?;
            }
            let bytes = selection
                .entries
                .iter()
                .filter(|entry| entry.kind == "file")
                .filter_map(|entry| entry.stamp.as_ref())
                .fold(0_u64, |sum, stamp| sum.saturating_add(stamp.size));
            self.cache_admit_locked(bytes).await?;
            Some(gate)
        } else {
            None
        };
        let ids: Vec<_> = selection
            .entries
            .iter()
            .map(|_| uuid::Uuid::new_v4().to_string())
            .collect();
        let count = selection.entries.len();
        let mut tasks = Vec::with_capacity(count);
        for (index, entry) in selection.entries.into_iter().enumerate() {
            let skipped = matches!(entry.kind, "symlink" | "unsupported");
            let status = if skipped {
                "skipped"
            } else if entry.error.is_some() {
                "failed"
            } else {
                "queued"
            };
            let (error_code, error) = if let Some(error) = entry.error {
                (Some(error.code), Some(error.message))
            } else if skipped {
                (
                    Some("not_followed".into()),
                    Some("符号链接和特殊文件不会自动跟随或传输。".into()),
                )
            } else {
                (None, None)
            };
            tasks.push(Transfer {
                id: ids[index].clone(),
                device_id: device_id.clone(),
                direction: if push { "push" } else { "pull" }.into(),
                name: entry.source.rsplit('/').next().unwrap_or("file").into(),
                source: entry.source,
                destination: entry.destination,
                status: status.into(),
                transferred: 0,
                total: if entry.kind == "directory" {
                    Some(0)
                } else {
                    entry.stamp.as_ref().map(|stamp| stamp.size)
                },
                error,
                policy: policy.into(),
                created_at: now(),
                batch_id: batch_id.clone(),
                item_index: index,
                item_count: count,
                default_policy: None,
                generation: 0,
                error_code,
                source_stamp: entry.stamp,
                save_mode: None,
                partial_destination_possible: false,
                temporary_path: None,
                kind: entry.kind.into(),
                parent_id: entry.parent.map(|parent| ids[parent].clone()),
                tree_verified: false,
                tree_complete: false,
                destination_scope: destination_scope.into(),
                cache_evicted: false,
                cancellation: CancellationToken::new(),
            });
        }
        let ids: Vec<_> = tasks.iter().map(|t| t.id.clone()).collect();
        {
            let mut stored = self.activities.transfers.lock().await;
            for task in &tasks {
                stored.insert(task.id.clone(), task.clone());
            }
        }
        self.persist_transfer_ids(&ids).await?;
        if let Some(first) = tasks.iter().find(|task| task.status == "queued") {
            self.spawn_transfer(first.id.clone(), 0);
        }
        Ok(
            json!({"transferId":ids[0],"transferIds":ids,"batchId":batch_id,"status":"queued","transfers":tasks.iter().map(transfer_value).collect::<Vec<_>>()}),
        )
    }
    fn spawn_transfer(self: &Arc<Self>, id: String, generation: u64) {
        let runtime = Arc::clone(self);
        tokio::spawn(async move {
            let result = runtime.run_transfer(&id, generation).await;
            let data = {
                let _gate = runtime.media_cache.gate.lock().await;
                let mut tasks = runtime.activities.transfers.lock().await;
                if let Some(task) = tasks.get_mut(&id).filter(|t| t.generation == generation) {
                    if let Err(error) = result
                        && !matches!(task.status.as_str(), "completed" | "skipped")
                    {
                        task.status = if error.code == "cancelled" {
                            "cancelled"
                        } else if error.code == "conflict" {
                            "conflict"
                        } else {
                            "failed"
                        }
                        .into();
                        task.error_code = Some(error.code);
                        task.error = Some(error.message);
                    }
                    Some(transfer_value(task))
                } else {
                    None
                }
            };
            let mut reconcile = false;
            if let Some(data) = data {
                runtime.emit("transfer.changed", data["deviceId"].as_str(), data.clone());
                let batch = data["batchId"].as_str().unwrap_or_default();
                let mut dirty = runtime.verify_completed_tree(batch).await;
                dirty.push(id.clone());
                if runtime.persist_transfer_ids(&dirty).await.is_err() {
                    return;
                }
                let next = {
                    let tasks = runtime.activities.transfers.lock().await;
                    let pending = tasks
                        .values()
                        .filter(|task| task.batch_id == batch && !terminal(&task.status))
                        .min_by_key(|task| task.item_index);
                    pending
                        .filter(|task| task.status == "queued")
                        .map(|task| (task.id.clone(), task.generation))
                };
                // Only one worker is scheduled per batch; a conflict leaves the
                // next item queued until the explicit resolution completes.
                if let Some((id, generation)) = next {
                    runtime.spawn_transfer(id, generation);
                } else {
                    reconcile = true;
                }
            }
            // The shared owner reclaims only fully confirmed batches. This
            // must run without a Flutter engine or an attached event listener.
            if reconcile {
                let _ = runtime.reconcile_shares_from_transfers().await;
            }
        });
    }
    async fn verify_completed_tree(&self, batch: &str) -> Vec<String> {
        let directories = {
            let tasks = self.activities.transfers.lock().await;
            if tasks
                .values()
                .any(|task| task.batch_id == batch && !terminal(&task.status))
            {
                return Vec::new();
            }
            tasks
                .values()
                .filter(|task| {
                    task.batch_id == batch
                        && task.kind == "directory"
                        && task.status == "completed"
                        && !task.tree_verified
                })
                .cloned()
                .collect::<Vec<_>>()
        };
        for directory in directories {
            let result: CoreResult<SourceStamp> = async {
                if directory.direction == "push" {
                    let metadata = fs::symlink_metadata(&directory.source).await?;
                    if !metadata.is_dir() {
                        return Err(CoreError::new("source_changed", "目录类型已变化。"));
                    }
                    metadata_stamp(&metadata)
                } else {
                    let stat = crate::file_tree::remote_stat(
                        &self.client(&directory.device_id).await?,
                        &directory.source,
                    )
                    .await?;
                    if stat.mode & 0o170000 != 0o040000 {
                        return Err(CoreError::new("source_changed", "目录类型已变化。"));
                    }
                    Ok(stat.into())
                }
            }
            .await;
            let mut tasks = self.activities.transfers.lock().await;
            if let Some(task) = tasks.get_mut(&directory.id).filter(|task| {
                task.generation == directory.generation && task.status == "completed"
            }) {
                task.tree_verified = true;
                if result.as_ref().ok() != directory.source_stamp.as_ref() {
                    task.status = "failed".into();
                    let (code, message) = match result {
                        Ok(_) => (
                            "source_changed".into(),
                            "目录内容在传输期间发生变化；已完成文件保留，目录快照未完整确认。"
                                .into(),
                        ),
                        Err(error) => (
                            error.code,
                            format!("目录传输结束后无法核验源：{}", error.message),
                        ),
                    };
                    task.error_code = Some(code);
                    task.error = Some(message);
                }
                self.emit(
                    "transfer.changed",
                    Some(&task.device_id),
                    transfer_value(task),
                );
            }
        }
        let mut tasks = self.activities.transfers.lock().await;
        let mut order = tasks
            .values()
            .filter(|task| task.batch_id == batch)
            .map(|task| {
                (
                    task.item_index,
                    task.id.clone(),
                    task.parent_id.clone(),
                    task.status == "completed",
                )
            })
            .collect::<Vec<_>>();
        order.sort_by_key(|entry| std::cmp::Reverse(entry.0));
        let mut complete = order
            .iter()
            .map(|(_, id, _, done)| (id.clone(), *done))
            .collect::<HashMap<_, _>>();
        for (_, id, parent, _) in &order {
            if !complete.get(id).copied().unwrap_or(false)
                && let Some(parent) = parent
            {
                complete.insert(parent.clone(), false);
            }
        }
        for (_, id, _, _) in order {
            if let Some(task) = tasks
                .get_mut(&id)
                .filter(|task| task.kind == "directory" && task.tree_verified)
            {
                task.tree_complete = complete.get(&id).copied().unwrap_or(false);
                self.emit(
                    "transfer.changed",
                    Some(&task.device_id),
                    transfer_value(task),
                );
            }
        }
        tasks
            .values()
            .filter(|task| task.batch_id == batch && task.kind == "directory")
            .map(|task| task.id.clone())
            .collect()
    }
    async fn run_transfer(self: &Arc<Self>, id: &str, generation: u64) -> CoreResult<()> {
        // A batch runs in order. A conflict pauses later files, so its selected
        // default is observed before they perform any network or filesystem I/O.
        let mut task = loop {
            let tasks = self.activities.transfers.lock().await;
            let task = tasks
                .get(id)
                .filter(|t| t.generation == generation)
                .cloned()
                .ok_or_else(|| CoreError::new("cancelled", "此传输尝试已替换。"))?;
            check_cancel(&task.cancellation)?;
            let blocked = tasks.values().any(|previous| {
                previous.batch_id == task.batch_id
                    && previous.item_index < task.item_index
                    && !terminal(&previous.status)
            });
            drop(tasks);
            if !blocked {
                break task;
            }
            tokio::select! {_=task.cancellation.cancelled()=>return Err(CoreError::new("cancelled","传输已取消。")),_=tokio::time::sleep(Duration::from_millis(50))=>{}}
        };
        if let Some(parent_id) = &task.parent_id {
            let tasks = self.activities.transfers.lock().await;
            let parent = tasks
                .get(parent_id)
                .ok_or_else(|| CoreError::new("parent_missing", "目录任务记录已缺失。"))?;
            if parent.status == "skipped" {
                drop(tasks);
                task.status = "skipped".into();
                task.error = Some("父目录已跳过，此项未写入。".into());
                self.save_attempt(&task).await?;
                return Ok(());
            }
            if parent.status != "completed" {
                return Err(CoreError::new(
                    "parent_failed",
                    "父目录未成功准备；此项未写入。",
                ));
            }
            let name = Path::new(&task.source)
                .file_name()
                .ok_or_else(|| CoreError::new("invalid_filename", "目录子项名称无效。"))?;
            task.destination = if task.direction == "push" {
                remote_path(&format!(
                    "{}/{}",
                    parent.destination.trim_end_matches('/'),
                    name.to_string_lossy()
                ))?
            } else {
                Path::new(&parent.destination)
                    .join(name)
                    .to_string_lossy()
                    .into_owned()
            };
        }
        let client = self.client(&task.device_id).await?;
        self.check_tree_parents(&task, &client).await?;
        let options = OperationOptions {
            timeout: Duration::from_secs(3600),
            cancellation: task.cancellation.clone(),
        };
        let push = task.direction == "push";
        if task.kind == "directory" {
            return self.transfer_directory(&mut task, &client, options).await;
        }
        let stamp = if push {
            local_stamp(&task.source).await?
        } else {
            let stat = crate::file_tree::remote_stat(&client, &task.source).await?;
            if stat.mode & 0o170000 != 0o100000 {
                return Err(CoreError::new(
                    "not_a_file",
                    "源路径已不再是普通文件；不会跟随符号链接。",
                ));
            }
            SourceStamp::from(stat)
        };
        if task
            .source_stamp
            .as_ref()
            .is_some_and(|original| original != &stamp)
        {
            return Err(CoreError::new(
                "source_changed",
                "源文件已变化；请核对后发起新的传输任务。",
            ));
        }
        task.source_stamp = Some(stamp.clone());
        task.total = Some(stamp.size);
        let exists = if push {
            match crate::remote_fs::stat(&client, &task.destination, false, options.clone()).await {
                Ok(_) => true,
                Err(error) if error.code == "not_found" => false,
                Err(error) => return Err(error),
            }
        } else {
            fs::symlink_metadata(&task.destination)
                .await
                .map(|_| true)
                .or_else(|e| {
                    if e.kind() == std::io::ErrorKind::NotFound {
                        Ok(false)
                    } else {
                        Err(e)
                    }
                })?
        };
        if exists {
            match task.policy.as_str() {
                "ask" => {
                    task.status = "conflict".into();
                    self.save_attempt(&task).await?;
                    return Ok(());
                }
                "skip" => {
                    task.status = "skipped".into();
                    self.save_attempt(&task).await?;
                    return Ok(());
                }
                "keepBoth" => {
                    let path = PathBuf::from(&task.destination);
                    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("file");
                    let ext = path
                        .extension()
                        .and_then(|s| s.to_str())
                        .map(|s| format!(".{s}"))
                        .unwrap_or_default();
                    task.destination = path
                        .with_file_name(format!("{stem} ({}-{}){ext}", now(), uuid::Uuid::new_v4()))
                        .to_string_lossy()
                        .into_owned();
                }
                _ => {}
            }
        }
        task.status = "running".into();
        task.transferred = 0;
        task.error = None;
        task.error_code = None;
        task.partial_destination_possible = false;
        self.save_attempt(&task).await?;
        self.persist_transfer(&task.id).await?;
        let progress = Arc::new(AtomicU64::new(0));
        let ticker_cancel = CancellationToken::new();
        let ticker = {
            let runtime = Arc::clone(self);
            let id = id.to_owned();
            let cancel = ticker_cancel.clone();
            let progress = progress.clone();
            tokio::spawn(async move {
                loop {
                    tokio::select! {_=cancel.cancelled()=>break,_=tokio::time::sleep(Duration::from_millis(200))=>{}}
                    let data = {
                        let mut tasks = runtime.activities.transfers.lock().await;
                        tasks
                            .get_mut(&id)
                            .filter(|t| {
                                t.generation == generation
                                    && matches!(t.status.as_str(), "running" | "finalizing")
                            })
                            .map(|t| {
                                t.transferred = progress.load(Ordering::Relaxed);
                                transfer_value(t)
                            })
                    };
                    if let Some(data) = data {
                        runtime.emit("transfer.changed", data["deviceId"].as_str(), data.clone());
                    }
                }
            })
        };
        let result = self
            .transfer_data(&mut task, &client, options, stamp, progress.clone())
            .await;
        ticker_cancel.cancel();
        let _ = ticker.await;
        match result {
            Ok((count, mode)) => {
                let _gate = self.media_cache.gate.lock().await;
                let mut tasks = self.activities.transfers.lock().await;
                if let Some(saved) = tasks.get_mut(id).filter(|t| t.generation == generation) {
                    saved.status = "completed".into();
                    saved.transferred = count;
                    saved.destination = task.destination;
                    saved.save_mode = Some(mode);
                    saved.error = None;
                    saved.error_code = None;
                    saved.temporary_path = None;
                    saved.cache_evicted = false;
                }
                Ok(())
            }
            Err(error) => {
                let mut tasks = self.activities.transfers.lock().await;
                if let Some(saved) = tasks.get_mut(id).filter(|t| t.generation == generation) {
                    saved.transferred = progress.load(Ordering::Relaxed);
                    saved.partial_destination_possible = matches!(
                        error.code.as_str(),
                        "result_unknown" | "partial_destination"
                    );
                }
                Err(error)
            }
        }
    }
    async fn transfer_data(
        &self,
        task: &mut Transfer,
        client: &interop_adb::Client,
        options: OperationOptions,
        stamp: SourceStamp,
        progress: Arc<AtomicU64>,
    ) -> CoreResult<(u64, String)> {
        let id = task.id.clone();
        let generation = task.generation;
        let push = task.direction == "push";

        // Expected ENOENT during conflict detection poisons that session.
        let mut sync = client.sync(options.clone()).await?;
        if push {
            let temp = format!("{}.interop-{}-{}.part", task.destination, id, generation);
            task.temporary_path = Some(temp.clone());
            self.save_attempt(task).await?;
            let mut input = ProgressIo {
                inner: fs::File::open(&task.source).await?,
                progress: progress.clone(),
            };
            let count = sync
                .push(
                    &RemotePath::new(&temp)?,
                    &mut input,
                    0o644,
                    now().min(u32::MAX as u64) as u32,
                    stamp.size,
                )
                .await?;
            if count != stamp.size || local_stamp(&task.source).await? != stamp {
                return Err(CoreError::new(
                    "source_changed",
                    "传输期间源文件发生变化；临时文件保留，未提交目标。",
                ));
            }
            task.status = "finalizing".into();
            task.transferred = count;
            self.save_attempt(task).await?;
            self.persist_transfer(&task.id).await?;
            check_cancel(&task.cancellation)?;
            // Keep the completed part private until one atomic rename commits
            // it. Android shared storage often rejects hard links; renameat2
            // still provides no-clobber semantics without exposing partial data.
            crate::remote_helper::remote_rename_with_options(
                client,
                &temp,
                &task.destination,
                task.policy == "replace",
                OperationOptions {
                    cancellation: task.cancellation.clone(),
                    ..Default::default()
                },
            )
            .await?;
            let mode = "atomicRename".to_owned();
            Ok((count, mode))
        } else {
            let destination = PathBuf::from(&task.destination);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent).await?;
            }
            let temp = destination.with_file_name(format!(".interop-{id}-{generation}.part"));
            task.temporary_path = Some(temp.to_string_lossy().into_owned());
            self.save_attempt(task).await?;
            let file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)
                .await?;
            let mut output = ProgressIo {
                inner: file,
                progress: progress.clone(),
            };
            let count = sync
                .pull(&RemotePath::new(&task.source)?, &mut output, stamp.size)
                .await?;
            output.inner.sync_all().await?;
            #[cfg(any(target_os = "linux", target_os = "android"))]
            let completed_file = output.inner.into_std().await;
            #[cfg(not(any(target_os = "linux", target_os = "android")))]
            drop(output);
            drop(sync);
            let after = SourceStamp::from(
                crate::remote_fs::stat(client, &task.source, false, options).await?,
            );
            if count != stamp.size || after != stamp {
                return Err(CoreError::new(
                    "source_changed",
                    "手机文件在传输期间发生变化，临时文件保留，未提交目标。",
                ));
            }
            task.status = "finalizing".into();
            task.transferred = count;
            self.save_attempt(task).await?;
            self.persist_transfer(&task.id).await?;
            check_cancel(&task.cancellation)?;
            let mode = if task.policy == "replace" {
                fs::rename(&temp, &destination).await?;
                "atomicRename"
            } else {
                #[cfg(any(target_os = "linux", target_os = "android"))]
                {
                    let from = temp.clone();
                    let to = destination.clone();
                    tokio::task::spawn_blocking(move || {
                        crate::local_publication::publish_file(&completed_file, &from, &to)
                    })
                    .await
                    .map_err(|error| {
                        CoreError::new(
                            "result_unknown",
                            format!("本机提交作业未确认，请核对目标。{error}"),
                        )
                    })??;
                    "atomicRenameNoReplace"
                }
                #[cfg(not(any(target_os = "linux", target_os = "android")))]
                match fs::hard_link(&temp, &destination).await {
                    Ok(()) => {
                        let _ = fs::remove_file(&temp).await;
                        "atomicHardLink"
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                        return Err(CoreError::new(
                            "conflict",
                            "保存时出现同名目标，原文件未被覆盖；临时文件保留。",
                        ));
                    }
                    Err(e) => {
                        return Err(CoreError::new(
                            "atomic_save_unavailable",
                            format!(
                                "保存位置不支持原子防覆盖提交，请选择另一位置或明确选择替换。{e}"
                            ),
                        ));
                    }
                }
            };
            Ok((count, mode.into()))
        }
    }
    async fn check_tree_parents(
        &self,
        task: &Transfer,
        client: &interop_adb::Client,
    ) -> CoreResult<()> {
        let parents = {
            let tasks = self.activities.transfers.lock().await;
            let mut parents = Vec::new();
            let mut parent_id = task.parent_id.clone();
            while let Some(id) = parent_id {
                if parents.len() >= 64 {
                    return Err(CoreError::new("tree_limit", "目录关系超过层级上限。"));
                }
                let parent = tasks
                    .get(&id)
                    .ok_or_else(|| CoreError::new("parent_missing", "父目录记录已缺失。"))?;
                parents.push((parent.source.clone(), parent.destination.clone()));
                parent_id = parent.parent_id.clone();
            }
            parents
        };
        for (source, destination) in parents {
            check_cancel(&task.cancellation)?;
            let (local, remote) = if task.direction == "push" {
                (source, destination)
            } else {
                (destination, source)
            };
            if !fs::symlink_metadata(local).await?.is_dir()
                || crate::file_tree::remote_stat(client, &remote).await?.mode & 0o170000 != 0o040000
            {
                return Err(CoreError::new(
                    "source_changed",
                    "目录路径已被替换或变为符号链接；此项未传输。",
                ));
            }
        }
        Ok(())
    }
    async fn transfer_directory(
        &self,
        task: &mut Transfer,
        client: &interop_adb::Client,
        options: OperationOptions,
    ) -> CoreResult<()> {
        check_cancel(&task.cancellation)?;
        task.status = "running".into();
        self.save_attempt(task).await?;
        let push = task.direction == "push";
        let source_stamp = if push {
            let metadata = fs::symlink_metadata(&task.source).await?;
            if !metadata.is_dir() {
                return Err(CoreError::new(
                    "source_changed",
                    "源目录已变化；不会跟随符号链接。",
                ));
            }
            metadata_stamp(&metadata)?
        } else {
            let stat = crate::file_tree::remote_stat(client, &task.source).await?;
            if stat.mode & 0o170000 != 0o040000 {
                return Err(CoreError::new(
                    "source_changed",
                    "源目录已变化；不会跟随符号链接。",
                ));
            }
            stat.into()
        };
        if task
            .source_stamp
            .as_ref()
            .is_some_and(|stamp| stamp != &source_stamp)
        {
            return Err(CoreError::new(
                "source_changed",
                "源目录已变化；不会跟随符号链接。",
            ));
        }
        let existing = if push {
            match crate::file_tree::remote_stat(client, &task.destination).await {
                Ok(stat) => Some(stat.mode & 0o170000 == 0o040000),
                Err(error) if error.code == "not_found" => None,
                Err(error) => return Err(error),
            }
        } else {
            match fs::symlink_metadata(&task.destination).await {
                Ok(metadata) => Some(metadata.is_dir()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => return Err(error.into()),
            }
        };
        if existing == Some(false) {
            match task.policy.as_str() {
                "ask" => {
                    task.status = "conflict".into();
                    self.save_attempt(task).await?;
                    return Ok(());
                }
                "skip" => {
                    task.status = "skipped".into();
                    self.save_attempt(task).await?;
                    return Ok(());
                }
                "keepBoth" => {
                    let path = Path::new(&task.destination);
                    let name = path
                        .file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or("directory");
                    task.destination = path
                        .with_file_name(format!("{name} ({})", uuid::Uuid::new_v4()))
                        .to_string_lossy()
                        .into_owned();
                }
                _ => {
                    return Err(CoreError::new(
                        "directory_target_conflict",
                        "不能以目录覆盖文件或符号链接；请选择保留两者或跳过。",
                    ));
                }
            }
        }
        task.status = "finalizing".into();
        self.save_attempt(task).await?;
        self.persist_transfer(&task.id).await?;
        check_cancel(&task.cancellation)?;
        if existing != Some(true) {
            if push {
                let result = crate::remote_fs::command(
                    client,
                    &format!("mkdir {}", quote(&task.destination)?),
                    4096,
                    options,
                )
                .await
                .map_err(|_| {
                    CoreError::new("result_unknown", "目录创建结果不确定，请刷新核对。")
                })?;
                if result.exit_code != Some(0) {
                    return Err(CoreError::new(
                        "directory_create_failed",
                        String::from_utf8_lossy(&result.stderr).into_owned(),
                    ));
                }
            } else {
                fs::create_dir(&task.destination).await?;
            }
        }
        task.status = "completed".into();
        task.total = Some(0);
        task.transferred = 0;
        task.save_mode = Some("directoryMerge".into());
        self.save_attempt(task).await
    }
    async fn save_attempt(&self, task: &Transfer) -> CoreResult<()> {
        let _gate = self.media_cache.gate.lock().await;
        let mut tasks = self.activities.transfers.lock().await;
        let saved = tasks
            .get_mut(&task.id)
            .filter(|t| t.generation == task.generation)
            .ok_or_else(|| CoreError::new("cancelled", "此传输尝试已替换。"))?;
        check_cancel(&saved.cancellation)?;
        *saved = task.clone();
        Ok(())
    }
    pub(crate) async fn transfer_command(
        self: &Arc<Self>,
        command: &str,
        p: &Value,
    ) -> CoreResult<Value> {
        let _cache_gate = if command != "transfers.get" {
            Some(self.media_cache.gate.lock().await)
        } else {
            None
        };
        if matches!(command, "transfers.resume" | "transfers.resolve") {
            let previous = self
                .activities
                .transfers
                .lock()
                .await
                .get(required(p, "transferId")?)
                .cloned();
            if let Some(previous) = previous.filter(|task| {
                task.direction == "pull"
                    && task.destination_scope == "privateCache"
                    && (transfer_value(task)["canRestart"] == true || task.status == "conflict")
            }) {
                let bytes = if command == "transfers.resume" {
                    self.cache_validate_destination_locked(&previous.destination)
                        .await?;
                    previous.total.unwrap_or(0)
                } else {
                    if let Some(path) = &previous.temporary_path {
                        fs::symlink_metadata(path)
                            .await
                            .map(|m| m.len())
                            .unwrap_or(0)
                            .min(previous.total.unwrap_or(0))
                    } else {
                        0
                    }
                };
                self.cache_admit_locked(bytes).await?;
            }
        }
        if command == "transfers.cancel"
            && let Some(batch) = p["batchId"].as_str()
        {
            let mut tasks = self.activities.transfers.lock().await;
            let mut found = false;
            let mut dirty = Vec::new();
            for task in tasks.values_mut().filter(|task| task.batch_id == batch) {
                found = true;
                dirty.push(task.id.clone());
                if terminal(&task.status) {
                    if task.kind == "directory" {
                        task.tree_verified = true;
                    }
                    continue;
                }
                task.cancellation.cancel();
                task.status = if matches!(task.status.as_str(), "running" | "finalizing") {
                    "cancelling"
                } else {
                    "cancelled"
                }
                .into();
            }
            if !found {
                return Err(CoreError::new("not_found", "批任务已不存在。"));
            }
            drop(tasks);
            self.persist_transfer_ids(&dirty).await?;
            return Ok(json!({"batchId":batch,"status":"cancelling"}));
        }
        let id = required(p, "transferId")?;
        let mut tasks = self.activities.transfers.lock().await;
        let task = tasks
            .get_mut(id)
            .ok_or_else(|| CoreError::new("not_found", "任务已不存在。"))?;
        if command == "transfers.get" {
            return Ok(transfer_value(task));
        }
        if command == "transfers.cancel" {
            task.cancellation.cancel();
            if matches!(task.status.as_str(), "running" | "finalizing") {
                task.status = "cancelling".into();
            } else if !matches!(task.status.as_str(), "completed" | "skipped") {
                task.status = "cancelled".into();
            }
            let result = transfer_value(task);
            let batch = task.batch_id.clone();
            let next = tasks
                .values()
                .filter(|task| task.batch_id == batch && !terminal(&task.status))
                .min_by_key(|task| task.item_index)
                .filter(|task| task.status == "queued")
                .map(|task| (task.id.clone(), task.generation));
            drop(tasks);
            self.persist_transfer(id).await?;
            if let Some((id, generation)) = next {
                self.spawn_transfer(id, generation);
            }
            return Ok(result);
        }
        let resolve = command == "transfers.resolve";
        if resolve && task.status != "conflict" {
            return Err(CoreError::new(
                "invalid_state",
                "只有同名冲突可以选择处理方式。",
            ));
        }
        if !resolve {
            if !transfer_value(task)["canRestart"]
                .as_bool()
                .unwrap_or(false)
            {
                return Err(CoreError::new(
                    "invalid_state",
                    "当前任务不能重新传输；保存结果不确定时请先核对目标。",
                ));
            }
            if p["restart"] != true {
                return Err(CoreError::new(
                    "resume_unavailable",
                    "当前协议不支持字节断点续传；确认重新传输后将从头开始。",
                ));
            }
        }
        let policy = if resolve {
            p["policy"].as_str().unwrap_or("ask")
        } else {
            p["policy"].as_str().unwrap_or(&task.policy)
        };
        valid_policy(policy)?;
        let policy = policy.to_owned();
        task.cancellation.cancel();
        task.generation = task.generation.saturating_add(1);
        task.cancellation = CancellationToken::new();
        task.status = "queued".into();
        task.tree_verified = false;
        task.tree_complete = false;
        task.policy = policy.clone();
        task.error = None;
        task.error_code = None;
        task.transferred = 0;
        task.temporary_path = None;
        task.cache_evicted = false;
        let generation = task.generation;
        let batch = task.batch_id.clone();
        let index = task.item_index;
        let mut parent = task.parent_id.clone();
        let mut dirty = vec![id.to_owned()];
        for _ in 0..64 {
            let Some(id) = parent else {
                break;
            };
            let Some(directory) = tasks.get_mut(&id) else {
                break;
            };
            directory.tree_verified = false;
            directory.tree_complete = false;
            dirty.push(directory.id.clone());
            parent = directory.parent_id.clone();
        }
        if resolve && p["applyToAll"] == true {
            for candidate in tasks
                .values_mut()
                .filter(|t| t.batch_id == batch && t.item_index >= index && !terminal(&t.status))
            {
                candidate.policy = policy.clone();
                candidate.default_policy = Some(policy.clone());
                dirty.push(candidate.id.clone());
            }
        }
        drop(tasks);
        self.persist_transfer_ids(&dirty).await?;
        self.spawn_transfer(id.into(), generation);
        Ok(
            json!({"status":"queued","transferId":id,"batchId":batch,"restartFromBeginning":!resolve}),
        )
    }

    pub(crate) async fn list_media(self: &Arc<Self>, p: &Value) -> CoreResult<Value> {
        self.gallery_command("media.list", p).await
    }
    async fn thumbnail_rpc(
        self: &Arc<Self>,
        command: &str,
        mut params: Value,
        phase: &Arc<StdMutex<Option<String>>>,
    ) -> CoreResult<Value> {
        let operation = uuid::Uuid::new_v4().to_string();
        params["operationId"] = json!(operation);
        *phase
            .lock()
            .map_err(|_| CoreError::new("media_error", "缩略图操作状态不可用。"))? =
            Some(operation);
        let response = Box::pin(self.companion_command(command, &params)).await;
        *phase
            .lock()
            .map_err(|_| CoreError::new("media_error", "缩略图操作状态不可用。"))? = None;
        response
    }

    pub(crate) async fn cancel_thumbnail_media(self: &Arc<Self>, p: &Value) -> CoreResult<Value> {
        let device = required(p, "deviceId")?;
        self.device(device).await?;
        let operation = uuid::Uuid::parse_str(required(p, "operationId")?)
            .map_err(|_| CoreError::new("invalid_argument", "缩略图操作标识必须是 UUID。"))?
            .to_string();
        let (key, seen) = thumbnail_identity(&self.root, device, &operation);
        let active = self.device_operations.lock().await;
        let token = active.get(&key).cloned();
        let fresh = thumbnail_claim(&seen, true)?;
        if let Some(token) = &token {
            token.cancel();
        }
        drop(active);
        Ok(
            json!({"operationId":operation,"cancelRequested":token.is_some()||fresh,"alreadyFinished":token.is_none()&&!fresh,
            "status":if token.is_some(){"cancelling"}else if fresh{"cancelledBeforeStart"}else{"finished"}}),
        )
    }

    pub(crate) async fn thumbnail_media(self: &Arc<Self>, p: &Value) -> CoreResult<Value> {
        let device = required(p, "deviceId")?.to_owned();
        let path = remote_path(required(p, "path")?)?;
        let max_size = match p.get("maxSize") {
            None => 256,
            Some(value) => value
                .as_u64()
                .filter(|n| (64..=512).contains(n))
                .ok_or_else(|| {
                    CoreError::new("invalid_argument", "缩略图尺寸必须在 64–512 之间。")
                })? as u32,
        };
        let kind = if mime(&path).starts_with("image/") {
            "image"
        } else if mime(&path).starts_with("video/") {
            "video"
        } else {
            return Err(CoreError::new(
                "media_type_unknown",
                "此路径的媒体类型尚未识别，不能自动下载原内容作为缩略图。",
            ));
        };
        let operation = match p.get("operationId") {
            None => uuid::Uuid::new_v4(),
            Some(Value::String(value)) => uuid::Uuid::parse_str(value)
                .map_err(|_| CoreError::new("invalid_argument", "缩略图操作标识必须是 UUID。"))?,
            _ => return Err(CoreError::new("invalid_argument", "缩略图操作标识无效。")),
        }
        .to_string();
        let (key, seen) = thumbnail_identity(&self.root, &device, &operation);
        let token = CancellationToken::new();
        {
            let mut active = self.device_operations.lock().await;
            let prefix = format!("thumbnail:{device}:");
            if active.keys().filter(|key| key.starts_with(&prefix)).count() >= 16 {
                return Err(CoreError::new(
                    "busy",
                    "这台设备正在处理的缩略图请求已达到上限。",
                ));
            }
            // Publish ownership and the cancellation token under the same lock
            // used by cancel, including cancellation arriving before start.
            thumbnail_claim(&seen, false)?;
            active.insert(key.clone(), token.clone());
        }
        let phase = Arc::new(StdMutex::new(None));
        let mut guard = ThumbnailOperation {
            runtime: Arc::downgrade(self),
            key: key.clone(),
            device: device.clone(),
            token: token.clone(),
            phase: phase.clone(),
            armed: true,
        };
        self.emit(
            "media.thumbnail.started",
            Some(&device),
            json!({"operationId":operation}),
        );
        let job = Box::pin(async {
            self.client(&device).await?;
            Box::pin(self.thumbnail_cached(&device, &path, kind, max_size, &operation, &phase))
                .await
        });
        let result = tokio::select! {
            biased;
            _=token.cancelled()=>Err(CoreError::new("cancelled","缩略图请求已取消；不会返回原件或继续发布结果。")),
            result=tokio::time::timeout(Duration::from_secs(45), job)=>result.unwrap_or_else(|_|Err(CoreError::new("media_timeout","缩略图请求超过有界等待时间。"))),
        };
        if result.is_err() {
            let current = phase.lock().ok().and_then(|mut phase| phase.take());
            if let Some(current) = current {
                let cleanup = tokio::time::timeout(
                    Duration::from_secs(6),
                    self.cancel_companion_media(&device, &current),
                )
                .await;
                if !cleanup
                    .as_ref()
                    .is_ok_and(|result| result.as_ref().is_ok_and(|value| value["reaped"] == true))
                {
                    guard.armed = false;
                    self.device_operations.lock().await.remove(&key);
                    return Err(CoreError::new(
                        "media_cleanup_unknown",
                        "解码子进程尚未确认回收；没有发布缩略图。",
                    ));
                }
            }
        }
        guard.armed = false;
        self.device_operations.lock().await.remove(&key);
        let mut result = result?;
        if token.is_cancelled() {
            if let Some(lease) = result["cacheLeaseId"].as_str() {
                let _ = self
                    .cache_command("media.cache.release", &json!({"leaseId":lease}))
                    .await;
            }
            return Err(CoreError::new(
                "cancelled",
                "缩略图请求已取消，没有发布结果。",
            ));
        }
        result["operationId"] = json!(operation);
        Ok(result)
    }

    async fn thumbnail_cached(
        self: &Arc<Self>,
        device: &str,
        path: &str,
        kind: &str,
        max_size: u32,
        operation: &str,
        phase: &Arc<StdMutex<Option<String>>>,
    ) -> CoreResult<Value> {
        // Serial per-device decode keeps media memory/CPU bounded independently
        // of the notification/clipboard worker. Active request count is capped.
        let gate = cache_lock(&format!(
            "{}:thumbnail-device:{device}",
            self.root.display()
        ))?;
        let _guard = gate.lock().await;
        let key = hex::encode(Sha256::digest(format!(
            "thumbnail-v1\0{device}\0{path}\0{max_size}"
        )));
        let params = json!({"deviceId":device,"path":path,"kind":kind,"maxSize":max_size,"ownerOperationId":operation});
        let before = Box::pin(self.thumbnail_rpc("media.stat", params.clone(), phase)).await?;
        let source = ThumbnailSource::parse(&before["sourceStamp"])?;
        let version = hex::encode(Sha256::digest(serde_json::to_vec(&source)?));
        let cache = self
            .root
            .join("media")
            .join("thumbnails")
            .join(format!("{key}-{version}"));
        let lookup = self.cache_writer(cache.clone(), 0).await?;
        fs::create_dir_all(&cache).await?;
        let metadata_path = cache.join("metadata.json");
        let mut transferred = before["rpcBytesReceived"].as_u64().unwrap_or(0);
        let cached = if fs::metadata(&metadata_path)
            .await
            .is_ok_and(|metadata| metadata.len() <= 4096)
        {
            fs::read(&metadata_path)
                .await
                .ok()
                .and_then(|bytes| serde_json::from_slice::<ThumbnailCache>(&bytes).ok())
        } else {
            None
        };
        if let Some(cached) = &cached
            && cached.version == 1
            && cached.source == source
            && cached.jpeg_bytes <= MAX_THUMBNAIL as u64
            && cached.sha256.len() == 64
            && cached.sha256.bytes().all(|byte| byte.is_ascii_hexdigit())
            && !cached.artifact.is_empty()
            && !cached.artifact.contains('/')
            && !cached.artifact.contains('\\')
            && !cached.artifact.contains("..")
        {
            let target = cache.join(&cached.artifact);
            if fs::symlink_metadata(&target)
                .await
                .is_ok_and(|meta| meta.is_file() && meta.len() == cached.jpeg_bytes)
                && let Ok(bytes) = fs::read(&target).await
                && hex::encode(Sha256::digest(&bytes)) == cached.sha256
                && jpeg_dimensions(&bytes).is_ok_and(|dimensions| {
                    dimensions == (cached.width, cached.height)
                        && dimensions.0 <= max_size
                        && dimensions.1 <= max_size
                })
            {
                let _gate = self.media_cache.gate.lock().await;
                let lease = self.media_cache.lease(vec![cache.clone()]);
                return Ok(
                    json!({"localPath":target,"cacheLeaseId":lease,"mime":"image/jpeg","thumbnail":true,"width":cached.width,"height":cached.height,
                "originalSize":source.size,"cacheHit":true,"sourceStamp":source,"sourceValidation":source.validation(),
                "bytesTransferred":transferred,"jpegBytes":cached.jpeg_bytes,"jpegBytesTransferred":0,"originalBytesTransferred":0,"transferAccounting":"companionJsonPayloadBytes"}),
                );
            }
        }
        drop(lookup);
        let writer = self
            .cache_writer(cache.clone(), MAX_THUMBNAIL as u64 + 4096)
            .await?;
        let response =
            Box::pin(self.thumbnail_rpc("media.thumbnail", params.clone(), phase)).await?;
        transferred =
            transferred.saturating_add(response["rpcBytesReceived"].as_u64().unwrap_or(0));
        if ThumbnailSource::parse(&response["sourceStamp"])? != source
            || response["thumbnail"] != true
            || response["mime"] != "image/jpeg"
        {
            return Err(CoreError::new(
                "source_changed",
                "生成期间媒体源或返回的缩略图类型发生变化。",
            ));
        }
        let encoded = response["data"]
            .as_str()
            .filter(|text| text.len() <= MAX_THUMBNAIL.div_ceil(3) * 4)
            .ok_or_else(|| CoreError::new("invalid_thumbnail", "缩略图数据缺失或超过大小限制。"))?;
        let jpeg = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .map_err(|_| CoreError::new("invalid_thumbnail", "缩略图编码无效。"))?;
        let sha256 = hex::encode(Sha256::digest(&jpeg));
        let (width, height) = jpeg_dimensions(&jpeg)?;
        if jpeg.len() > MAX_THUMBNAIL
            || response["sha256"] != sha256
            || response["jpegBytes"] != jpeg.len() as u64
            || response["width"] != width
            || response["height"] != height
            || width > max_size
            || height > max_size
        {
            return Err(CoreError::new(
                "invalid_thumbnail",
                "缩略图摘要、大小或尺寸不一致。",
            ));
        }
        let after = Box::pin(self.thumbnail_rpc("media.stat", params, phase)).await?;
        transferred = transferred.saturating_add(after["rpcBytesReceived"].as_u64().unwrap_or(0));
        if ThumbnailSource::parse(&after["sourceStamp"])? != source {
            return Err(CoreError::new(
                "source_changed",
                "媒体源已经变化，请重新获取缩略图。",
            ));
        }
        let artifact = format!("{}-{sha256}.jpg", uuid::Uuid::new_v4());
        let target = cache.join(&artifact);
        let metadata = ThumbnailCache {
            version: 1,
            source: source.clone(),
            sha256,
            jpeg_bytes: jpeg.len() as u64,
            width,
            height,
            artifact,
        };
        Self::private_write(&target, &jpeg).await?;
        Self::private_write(&metadata_path, &serde_json::to_vec(&metadata)?).await?;
        let _gate = self.media_cache.gate.lock().await;
        let lease = self.media_cache.lease(vec![cache]);
        drop(writer);
        Ok(
            json!({"localPath":target,"cacheLeaseId":lease,"mime":"image/jpeg","thumbnail":true,"width":width,"height":height,"originalSize":source.size,
            "cacheHit":false,"sourceStamp":source,"sourceValidation":source.validation(),"bytesTransferred":transferred,
            "jpegBytes":jpeg.len(),"jpegBytesTransferred":jpeg.len(),"originalBytesTransferred":0,"transferAccounting":"companionJsonPayloadBytes",
            "orientationApplied":response["orientationApplied"],"orientation":response["orientation"],"videoRotation":response["videoRotation"]}),
        )
    }

    pub(crate) async fn preview_media(&self, p: &Value) -> CoreResult<Value> {
        let path = remote_path(required(p, "path")?)?;
        let id = required(p, "deviceId")?;
        let client = self.client(id).await?;
        let key = hex::encode(Sha256::digest(format!("{id}\0{path}")));
        let lock = cache_lock(&format!("{}:{key}", self.root.display()))?;
        let _guard = lock.lock().await;
        let cache = self.root.join("media");
        fs::create_dir_all(&cache).await?;
        let extension = Path::new(&path)
            .extension()
            .and_then(|v| v.to_str())
            .filter(|v| v.len() <= 12 && v.bytes().all(|b| b.is_ascii_alphanumeric()))
            .unwrap_or("bin");
        let options = OperationOptions {
            timeout: Duration::from_secs(300),
            ..Default::default()
        };
        let source = SourceStamp::from(
            crate::remote_fs::stat(&client, &path, false, options.clone()).await?,
        );
        if source.mode & 0o170000 != 0o100000 {
            return Err(CoreError::new("not_a_file", "预览源必须是普通文件。"));
        }
        // Version the artifact by the observed source stamp, and use a fresh
        // filename on repair. An existing player's file is never replaced.
        let version = hex::encode(Sha256::digest(serde_json::to_vec(&source)?));
        let cache = cache.join(format!("{key}-{version}"));
        let lookup = self.cache_writer(cache.clone(), 0).await?;
        fs::create_dir_all(&cache).await?;
        let metadata_path = cache.join("metadata.json");
        let cached = fs::read(&metadata_path)
            .await
            .ok()
            .and_then(|b| serde_json::from_slice::<MediaCache>(&b).ok());
        let target = fs::read_to_string(cache.join("current"))
            .await
            .ok()
            .filter(|name| !name.contains('/') && !name.contains('\\') && !name.contains(".."))
            .map(|name| cache.join(name));
        if let Some(cached) = cached
            && let Some(target) = target
            && cached.source == source
            && fs::metadata(&target)
                .await
                .is_ok_and(|m| m.is_file() && m.len() == cached.local_size)
            && file_digest(&target).await? == cached.sha256
        {
            let _gate = self.media_cache.gate.lock().await;
            let lease = self.media_cache.lease(vec![cache.clone()]);
            return Ok(
                json!({"localPath":target,"cacheLeaseId":lease,"mime":mime(&path),"cacheHit":true,"size":source.size,"sourceValidation":"sizeModeMtimeSeconds","thumbnail":false}),
            );
        }
        drop(lookup);
        let writer = self
            .cache_writer(cache.clone(), source.size.saturating_add(4096))
            .await?;
        let target = cache.join(format!("{}.{}", uuid::Uuid::new_v4(), extension));
        let temp = cache.join(format!(".{key}-{}.part", uuid::Uuid::new_v4()));
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .await?;
        let result: CoreResult<MediaCache> = async {
            let mut sync = client.sync(options.clone()).await?;
            let count = sync
                .pull(&RemotePath::new(&path)?, &mut file, source.size)
                .await?;
            file.sync_all().await?;
            drop(sync);
            let after =
                SourceStamp::from(crate::remote_fs::stat(&client, &path, false, options).await?);
            if count != source.size || after != source {
                return Err(CoreError::new(
                    "source_changed",
                    "预览源文件发生变化，请重新打开。",
                ));
            }
            Ok(MediaCache {
                source,
                local_size: count,
                sha256: file_digest(&temp).await?,
            })
        }
        .await;
        drop(file);
        let metadata = match result {
            Ok(meta) => meta,
            Err(error) => {
                let _ = fs::remove_file(&temp).await;
                return Err(error);
            }
        };
        fs::rename(&temp, &target).await?;
        Self::private_write(&metadata_path, &serde_json::to_vec(&metadata)?).await?;
        Self::private_write(
            &cache.join("current"),
            target.file_name().unwrap().to_string_lossy().as_bytes(),
        )
        .await?;
        let _gate = self.media_cache.gate.lock().await;
        let lease = self.media_cache.lease(vec![cache]);
        drop(writer);
        Ok(
            json!({"localPath":target,"cacheLeaseId":lease,"mime":mime(&path),"cacheHit":false,"size":metadata.source.size,"sourceValidation":"sizeModeMtimeSeconds","thumbnail":false}),
        )
    }
}

#[cfg(test)]
mod thumbnail_tests {
    use super::*;
    #[test]
    fn thumbnail_metadata_checks_stamp_fields_and_bounded_jpeg_dimensions() {
        let stamp = json!({"device":"1","inode":"2","mode":0o100600,"size":512,
            "modifiedSeconds":1,"changedSeconds":2,"modifiedNanos":null,"changedNanos":null});
        let source = ThumbnailSource::parse(&stamp).unwrap();
        assert!(source.validation().ends_with("Seconds"));
        let mut nanos = stamp.clone();
        nanos["modifiedNanos"] = json!(999_999_999);
        nanos["changedNanos"] = json!(0);
        assert!(
            ThumbnailSource::parse(&nanos)
                .unwrap()
                .validation()
                .ends_with("WithNanosecondFields")
        );
        nanos["modifiedNanos"] = json!(1_000_000_000);
        assert!(ThumbnailSource::parse(&nanos).is_err());
        let mut link = stamp;
        link["mode"] = json!(0o120777);
        assert!(ThumbnailSource::parse(&link).is_err());
        let jpeg = [255, 216, 255, 192, 0, 8, 8, 0, 64, 0, 128, 1, 255, 217];
        assert_eq!(jpeg_dimensions(&jpeg).unwrap(), (128, 64));
        for i in 0..jpeg.len() {
            assert!(jpeg_dimensions(&jpeg[..i]).is_err());
        }
        let mut oversized = jpeg;
        oversized[9] = 3;
        assert!(jpeg_dimensions(&oversized).is_err());
        let mut segment = jpeg;
        segment[5] = 255;
        assert!(jpeg_dimensions(&segment).is_err());
    }
}
