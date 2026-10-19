//! Read-only shared-storage snapshots. Workers own a client and scan, never Runtime.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{mime, remote_path, required},
};
use interop_adb::{
    Client, OperationOptions,
    sync::{DirEntry, FileStat, RemotePath},
};
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio_util::sync::CancellationToken;

const ROOT: &str = "/sdcard";
const MAX_ENTRIES: usize = 50_000;
const MAX_DIRECTORIES: usize = 4096;
const MAX_DIRECTORY_ENTRIES: usize = 4096;
const MAX_DEPTH: usize = 32;
const MAX_MEDIA: usize = 25_000;
const MAX_ISSUES: usize = 128;
const MAX_SNAPSHOT_BYTES: usize = 8 * 1024 * 1024;
// The final marker can grow a full issue vector (for example 64 -> 128
// slots), so reserve the entire maximum allocation plus its fixed strings.
const BUDGET_ISSUE_RESERVE: usize = MAX_ISSUES * std::mem::size_of::<Issue>() + 1024;
const LIMITATION: &str = "仅按文件扩展名识别图片与视频，不是 Android 系统媒体库；只扫描当前用户的主共享存储 /sdcard，不代表全手机相册。modified 为文件修改时间（Unix 秒），不是拍摄时间。扫描最多 30 秒、50000 项、4096 个目录、32 层、25000 个媒体，每目录最多 4096 项；每个快照保留的容器及所有字符串容量最多 8 MiB，问题最多保留 128 条并另计总数。目录变化检查是尽力而为，不提供文件系统事务隔离。每次刷新创建独立快照，旧快照不增量更新；请按路径、大小和修改时间重新核对源文件。";

#[derive(Serialize)]
struct MediaItem {
    name: String,
    path: String,
    mime: &'static str,
    size: u64,
    modified: i64,
}
#[derive(Serialize)]
struct Issue {
    path: String,
    code: String,
    reason: String,
}
impl Issue {
    fn new(path: &str, code: &str, reason: &str) -> Self {
        Self {
            path: path.to_owned(),
            code: code.to_owned(),
            reason: reason.to_owned(),
        }
    }
    fn string_bytes(&self) -> usize {
        self.path.capacity() + self.code.capacity() + self.reason.capacity()
    }
}
// Account allocated element slots, including spare capacity, and every owned
// string. Typed records avoid retaining serde_json object trees per result.
fn retain<T>(
    records: &mut Vec<T>,
    record: T,
    string_bytes: usize,
    used: &mut usize,
    limit: usize,
) -> bool {
    let old_capacity = records.capacity();
    let target = if old_capacity == records.len() {
        old_capacity.max(2) * 2
    } else {
        old_capacity
    };
    let extra = (target - old_capacity) * std::mem::size_of::<T>() + string_bytes;
    if used.saturating_add(extra) > limit {
        return false;
    }
    if target > old_capacity {
        records.reserve_exact(target - records.len());
    }
    *used += (records.capacity() - old_capacity) * std::mem::size_of::<T>() + string_bytes;
    records.push(record);
    true
}

struct State {
    status: &'static str,
    items: Vec<MediaItem>,
    issues: Vec<Issue>,
    issue_count: usize,
    truncated: bool,
    visited_entries: usize,
    visited_directories: usize,
    snapshot_bytes: usize,
    budget_exhausted: bool,
}
impl State {
    fn exhaust_budget(&mut self) {
        if self.budget_exhausted {
            return;
        }
        self.budget_exhausted = true;
        self.truncated = true;
        self.issue_count += 1;
        let issue = Issue::new(
            ROOT,
            "snapshot_byte_limit",
            "达到 8 MiB 快照字节预算，已保留可访问结果；扫描不完整。",
        );
        let bytes = issue.string_bytes();
        let stored = retain(
            &mut self.issues,
            issue,
            bytes,
            &mut self.snapshot_bytes,
            MAX_SNAPSHOT_BYTES,
        );
        debug_assert!(stored, "reserved room for the byte-budget issue");
    }
}
struct Scan {
    id: String,
    device: String,
    cancellation: CancellationToken,
    state: Mutex<State>,
}
impl Scan {
    fn active(&self) -> bool {
        self.state.lock().expect("gallery snapshot").status == "scanning"
    }
    fn issue(&self, path: &str, code: &str, reason: &str) {
        let mut state = self.state.lock().expect("gallery snapshot");
        if state.status != "scanning" {
            return;
        }
        state.issue_count += 1;
        state.truncated |= code.ends_with("_limit");
        // Keep one issue slot and a small byte reserve for an explicit budget
        // failure, including when earlier permission issues filled the list.
        if state.issues.len() < MAX_ISSUES - 1 && !state.budget_exhausted {
            let issue = Issue::new(path, code, reason);
            let bytes = issue.string_bytes();
            let State {
                issues,
                snapshot_bytes,
                ..
            } = &mut *state;
            if !retain(
                issues,
                issue,
                bytes,
                snapshot_bytes,
                MAX_SNAPSHOT_BYTES - BUDGET_ISSUE_RESERVE,
            ) {
                state.exhaust_budget();
            }
        }
    }
    fn finish(&self, cancelled: bool) {
        let mut state = self.state.lock().expect("gallery snapshot");
        if state.status != "scanning" {
            return;
        }
        state.items.sort_unstable_by(|a, b| {
            b.modified
                .cmp(&a.modified)
                .then_with(|| a.path.cmp(&b.path))
        });
        state.status = if cancelled {
            "cancelled"
        } else if state.issue_count > 0 {
            "partial"
        } else {
            "completed"
        };
    }
    fn cancel(&self) {
        self.cancellation.cancel();
        self.finish(true);
    }
    fn page(&self, offset: usize, limit: usize) -> Value {
        let state = self.state.lock().expect("gallery snapshot");
        let ready = state.status != "scanning";
        let total = if ready { state.items.len() } else { 0 };
        let end = offset.saturating_add(limit).min(total);
        let items = if ready && offset < total {
            &state.items[offset..end]
        } else {
            &[]
        };
        json!({"scanId":self.id,"deviceId":self.device,"status":state.status,"complete":state.status=="completed",
            "truncated":state.truncated,"items":items,"total":total,"offset":offset,
            "nextOffset":if ready && end<total {Some(end)} else {None},
            "visitedEntries":state.visited_entries,"visitedDirectories":state.visited_directories,
            "snapshotBytes":state.snapshot_bytes,"snapshotByteLimit":MAX_SNAPSHOT_BYTES,"snapshotBudgetAccounting":"retainedContainersAndStringCapacity",
            "issues":state.issues,"issueCount":state.issue_count,
            "scope":{"roots":[ROOT],"excluded":["Android/data 和 Android/obb 私有目录","其他用户、其他存储卷和 /sdcard 之外的路径","子符号链接和特殊文件；不跟随链接","扩展名未识别的文件"],
                "recognition":"fileExtension","modifiedSource":"mtimeUnixSeconds","user":"current","volume":"primarySharedStorage","followsChildSymlinks":false,"consistency":"bestEffortDirectoryMetadata","refresh":"newIndependentSnapshot"},
            "limitation":LIMITATION})
    }
}
#[derive(Default)]
pub(crate) struct GalleryScans(Arc<Mutex<VecDeque<Arc<Scan>>>>);
fn prune(scans: &mut VecDeque<Arc<Scan>>, max_terminal: usize) {
    while scans.iter().filter(|scan| !scan.active()).count() > max_terminal {
        let index = scans.iter().position(|scan| !scan.active()).unwrap();
        scans.remove(index);
    }
}
impl GalleryScans {
    pub(crate) fn cancel_device(&self, device: &str) {
        let mut scans = self.0.lock().expect("gallery registry");
        for scan in scans.iter().filter(|scan| scan.device == device) {
            scan.cancel();
        }
        prune(&mut scans, 8);
    }
}
impl Drop for GalleryScans {
    fn drop(&mut self) {
        for scan in self.0.lock().expect("gallery registry").iter() {
            scan.cancel();
        }
    }
}
fn number(p: &Value, key: &str, default: u64, max: u64) -> CoreResult<usize> {
    let value = p
        .get(key)
        .map_or(Some(default), Value::as_u64)
        .filter(|value| *value <= max && (key != "limit" || *value > 0));
    value
        .and_then(|value| usize::try_from(value).ok())
        .ok_or_else(|| {
            CoreError::new(
                "invalid_argument",
                "相册分页参数无效；limit 必须为 1–200，offset 必须为非负整数。",
            )
        })
}
impl Runtime {
    pub(crate) async fn gallery_command(
        self: &Arc<Self>,
        command: &str,
        p: &Value,
    ) -> CoreResult<Value> {
        let device = required(p, "deviceId")?;
        let offset = number(p, "offset", 0, u64::MAX)?;
        let limit = number(p, "limit", 100, 200)?;
        if p.get("scanId").is_some() || command == "media.scan.cancel" {
            let id = required(p, "scanId")?;
            let mut scans = self.gallery_scans.0.lock().expect("gallery registry");
            let scan = scans.iter().find(|scan| scan.id == id).ok_or_else(|| {
                CoreError::new("media_scan_not_found", "相册扫描记录已过期，请重新扫描。")
            })?;
            if scan.device != device {
                return Err(CoreError::new(
                    "media_scan_device_mismatch",
                    "相册扫描属于另一台设备。",
                ));
            }
            if command == "media.scan.cancel" {
                scan.cancel();
            }
            let page = scan.page(offset, limit);
            prune(&mut scans, 8);
            return Ok(page);
        }
        let client = self.client(device).await?;
        // Match device registration/disconnect order: store, connections, registry.
        let store = self.store.read().await;
        let connections = self.connections.lock().await;
        if !store
            .devices
            .iter()
            .any(|record| record.id == device && record.status == "connected")
            || connections.get(device).is_none_or(Client::is_closed)
        {
            return Err(CoreError::new("disconnected", "设备尚未连接。"));
        }
        let mut scans = self.gallery_scans.0.lock().expect("gallery registry");
        if scans.iter().filter(|scan| scan.active()).count() >= 2 {
            return Err(CoreError::new(
                "media_scan_busy",
                "最多同时扫描 2 次，请取消或等待。",
            ));
        }
        prune(&mut scans, 8);
        let id = uuid::Uuid::new_v4().to_string();
        let device = device.to_owned();
        let snapshot_bytes = std::mem::size_of::<Scan>()
            + 2 * std::mem::size_of::<usize>()
            + id.capacity()
            + device.capacity();
        let scan = Arc::new(Scan {
            id,
            device,
            cancellation: CancellationToken::new(),
            state: Mutex::new(State {
                status: "scanning",
                items: Vec::new(),
                issues: Vec::new(),
                issue_count: 0,
                truncated: false,
                visited_entries: 0,
                visited_directories: 0,
                snapshot_bytes,
                budget_exhausted: false,
            }),
        });
        let receipt = scan.page(offset, limit);
        scans.push_back(scan.clone());
        drop(scans);
        drop(connections);
        drop(store);
        let registry = self.gallery_scans.0.clone();
        tokio::spawn(async move {
            let result = tokio::select! { biased;
                _=scan.cancellation.cancelled()=>None,
                result=tokio::time::timeout(Duration::from_secs(30),walk(&scan,&client))=>Some(result),
            };
            match result {
                None => scan.finish(true),
                Some(Err(_)) => {
                    scan.issue(ROOT, "time_limit", "达到 30 秒扫描时限，结果不完整。");
                    scan.finish(false);
                }
                Some(Ok(Err(error))) => {
                    scan.issue(ROOT, &error.code, &error.message);
                    scan.finish(false);
                }
                Some(Ok(Ok(()))) => scan.finish(scan.cancellation.is_cancelled()),
            }
            prune(&mut registry.lock().expect("gallery registry"), 8);
        });
        Ok(receipt)
    }
}
fn options(scan: &Scan) -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(10),
        cancellation: scan.cancellation.clone(),
    }
}
async fn stat(scan: &Scan, client: &Client, path: &str) -> CoreResult<FileStat> {
    crate::remote_fs::stat(client, path, path == ROOT, options(scan)).await
}
async fn accessible(scan: &Scan, client: &Client, path: &str) -> CoreResult<bool> {
    crate::remote_fs::accessible(client, path, options(scan)).await
}
async fn native_children(
    scan: &Scan,
    client: &Client,
    path: &str,
    limit: usize,
) -> CoreResult<(Vec<DirEntry>, usize)> {
    let listing = crate::remote_fs::fallback_children(client, path, limit, options(scan)).await?;
    if listing.truncated {
        scan.issue(path, "entry_limit", "达到每目录项数量上限，结果不完整。");
    }
    let examined = listing.entries.len();
    let mut entries = Vec::with_capacity(examined);
    for (name, stat) in listing.entries {
        match stat {
            Ok(stat) => entries.push(DirEntry { name, stat }),
            Err(error) => scan.issue(path, &error.code, &error.message),
        }
    }
    Ok((entries, examined))
}
async fn walk(scan: &Scan, client: &Client) -> CoreResult<()> {
    let mut queue = VecDeque::from([(ROOT.to_owned(), 0usize)]);
    let mut queued = 1usize;
    let mut visited = 0usize;
    while let Some((path, depth)) = queue.pop_front() {
        if scan.cancellation.is_cancelled() {
            return Ok(());
        }
        if scan
            .state
            .lock()
            .expect("gallery snapshot")
            .budget_exhausted
        {
            return Ok(());
        }
        let before = match stat(scan, client, &path).await {
            Ok(stat) if stat.mode & 0o170000 == 0o040000 => stat,
            Ok(_) => {
                scan.issue(
                    &path,
                    "source_changed",
                    "目录已变为链接或其他类型，没有继续遍历。",
                );
                continue;
            }
            Err(error) => {
                scan.issue(&path, &error.code, &error.message);
                continue;
            }
        };
        // EACCES may be represented by adbd as successful empty DONE.
        if !accessible(scan, client, &path).await? {
            scan.issue(
                &path,
                "permission_denied",
                "无权读取或遍历此目录，扫描结果不完整。",
            );
            continue;
        }
        let mut sync = client.sync(options(scan)).await?;
        let budget = MAX_DIRECTORY_ENTRIES.min(MAX_ENTRIES - visited);
        let listed = if client.info().features.contains("ls_v2") {
            sync.list(&RemotePath::new(&path)?, budget).await
        } else {
            Err(interop_adb::Error::Unsupported("ls_v2"))
        };
        let (children, consumed) = match listed {
            Ok(children) => {
                let consumed = children.len();
                (children, consumed)
            }
            Err(error) => {
                let overflow = matches!(error, interop_adb::Error::OutputLimit);
                if overflow {
                    scan.issue(&path, "entry_limit", "目录项数量超过上限，结果不完整。");
                }
                match native_children(scan, client, &path, budget).await {
                    Ok((children, examined)) => {
                        // A failed SYNC listing consumed its bounded prefix.
                        // The fallback recovers those entries rather than
                        // granting a fresh global budget for each directory.
                        let consumed = if overflow { budget } else { examined };
                        (children, consumed)
                    }
                    Err(error) => {
                        scan.issue(&path, &error.code, &error.message);
                        if overflow {
                            visited += budget;
                            let mut state = scan.state.lock().expect("gallery snapshot");
                            if state.status != "scanning" {
                                return Ok(());
                            }
                            state.visited_entries = visited;
                            state.visited_directories += 1;
                            if visited >= MAX_ENTRIES {
                                return Ok(());
                            }
                        }
                        continue;
                    }
                }
            }
        };
        {
            let mut state = scan.state.lock().expect("gallery snapshot");
            if state.status != "scanning" {
                return Ok(());
            }
            state.visited_directories += 1;
            visited += consumed;
            state.visited_entries = visited;
        }
        for child in children {
            {
                let state = scan.state.lock().expect("gallery snapshot");
                if state.status != "scanning" {
                    return Ok(());
                }
                if state.budget_exhausted {
                    return Ok(());
                }
            }
            let name = match String::from_utf8(child.name) {
                Ok(name) => name,
                Err(_) => {
                    scan.issue(
                        &path,
                        "invalid_filename",
                        "目录包含无效 UTF-8 文件名，已跳过且未生成可操作路径。",
                    );
                    continue;
                }
            };
            if name == "." || name == ".." || name.contains('/') || name.contains('\0') {
                scan.issue(&path, "invalid_filename", "目录项名称无效，已跳过。");
                continue;
            }
            let child_path = match remote_path(&format!("{path}/{name}")) {
                Ok(path) => path,
                Err(_) => {
                    scan.issue(&path, "invalid_path", "目录项路径不能安全操作，已跳过。");
                    continue;
                }
            };
            let kind = child.stat.mode & 0o170000;
            if child_path.eq_ignore_ascii_case("/sdcard/Android/data")
                || child_path.eq_ignore_ascii_case("/sdcard/Android/obb")
            {
                continue;
            }
            if kind == 0o040000 {
                if depth >= MAX_DEPTH {
                    scan.issue(&child_path, "depth_limit", "达到 32 层目录深度上限。");
                } else if queued >= MAX_DIRECTORIES {
                    scan.issue(&child_path, "directory_limit", "达到 4096 个目录上限。");
                } else {
                    queue.push_back((child_path.clone(), depth + 1));
                    queued += 1;
                }
            } else if kind == 0o100000
                && (mime(&child_path).starts_with("image/")
                    || mime(&child_path).starts_with("video/"))
            {
                let mut state = scan.state.lock().expect("gallery snapshot");
                if state.status != "scanning" {
                    return Ok(());
                }
                if state.items.len() >= MAX_MEDIA {
                    drop(state);
                    scan.issue(&path, "media_limit", "达到 25000 个媒体上限，结果不完整。");
                    return Ok(());
                }
                let item = MediaItem {
                    name,
                    mime: mime(&child_path),
                    path: child_path,
                    size: child.stat.size,
                    modified: child.stat.modified_seconds,
                };
                let bytes = item.name.capacity() + item.path.capacity();
                let State {
                    items,
                    snapshot_bytes,
                    ..
                } = &mut *state;
                if !retain(
                    items,
                    item,
                    bytes,
                    snapshot_bytes,
                    MAX_SNAPSHOT_BYTES - BUDGET_ISSUE_RESERVE,
                ) {
                    state.exhaust_budget();
                    return Ok(());
                }
            }
        }
        // Includes skipped, excluded and unrepresentable names.
        if visited >= MAX_ENTRIES {
            scan.issue(&path, "entry_limit", "达到 50000 项扫描上限。");
            return Ok(());
        }
        match stat(scan, client, &path).await {
            Ok(after) if after == before => {}
            _ => scan.issue(
                &path,
                "source_changed",
                "扫描期间目录元数据已变化，结果可能不完整。",
            ),
        }
        if !accessible(scan, client, &path).await? {
            scan.issue(
                &path,
                "permission_denied",
                "扫描期间目录权限已变化，结果不完整。",
            );
        }
    }
    Ok(())
}
