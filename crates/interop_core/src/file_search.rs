//! Bounded, cancellable name searches. Workers never retain the Runtime.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{mime, remote_path, required},
};
use interop_adb::{
    Client, OperationOptions,
    sync::{DirEntry, FileStat, RemotePath},
};
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio_util::sync::CancellationToken;

const MAX_RESULTS: usize = 500;
const MAX_ENTRIES: usize = 50_000;
const MAX_DIRECTORIES: usize = 2048;
const MAX_DEPTH: usize = 32;
const MAX_DIRECTORY_ENTRIES: usize = 4096;
const MAX_ISSUES: usize = 128;
const LIMITATION: &str = "仅按文件名搜索，不搜索文件内容；忽略大小写。最多 30 秒、500 个结果、50000 项、2048 个目录、32 层，每目录最多 4096 项；不跟随子符号链接。搜索期间目录变化可能导致结果不完整。";

// ADB pathname operations cannot provide transactional isolation against hostile
// concurrent replacement. Type checks and metadata comparisons detect ordinary
// changes on a best-effort basis; they are not a guarantee against root escape.

struct Search {
    snapshot: Mutex<Value>,
    cancellation: CancellationToken,
}
impl Search {
    fn snapshot(&self) -> Value {
        self.snapshot.lock().expect("search snapshot").clone()
    }
    fn issue(&self, path: &str, code: &str, reason: &str) {
        let mut snapshot = self.snapshot.lock().expect("search snapshot");
        if snapshot["status"] != "running" {
            return;
        }
        let issues = snapshot["issues"].as_array_mut().expect("issues");
        if issues.len() < MAX_ISSUES {
            issues.push(json!({"path":path,"code":code,"reason":reason}));
        }
    }
    fn finish(&self, status: &str) {
        let mut snapshot = self.snapshot.lock().expect("search snapshot");
        let status = if self.cancellation.is_cancelled() {
            "cancelled"
        } else {
            status
        };
        snapshot["status"] = json!(status);
        snapshot["complete"] = json!(status == "completed");
        snapshot["canCancel"] = json!(false);
    }
    fn cancel(&self) {
        let mut snapshot = self.snapshot.lock().expect("search snapshot");
        if snapshot["status"] == "running" {
            self.cancellation.cancel();
            snapshot["status"] = json!("cancelled");
            snapshot["complete"] = json!(false);
            snapshot["canCancel"] = json!(false);
        }
    }
}
#[derive(Default)]
pub(crate) struct Searches(Arc<Mutex<VecDeque<Arc<Search>>>>);
impl Searches {
    pub(crate) fn cancel_device(&self, id: &str) {
        for search in self.0.lock().expect("search registry").iter() {
            if search.snapshot()["deviceId"] == id {
                search.cancel();
            }
        }
    }
}
impl Drop for Searches {
    fn drop(&mut self) {
        for search in self.0.lock().expect("search registry").iter() {
            search.cancel();
        }
    }
}
impl Runtime {
    pub(crate) async fn file_search_command(
        self: &Arc<Self>,
        command: &str,
        p: &Value,
    ) -> CoreResult<Value> {
        let device = required(p, "deviceId")?;
        if command != "files.search.start" {
            let id = required(p, "searchId")?;
            let searches = self.searches.0.lock().expect("search registry");
            let search = searches
                .iter()
                .find(|search| search.snapshot()["searchId"] == id)
                .ok_or_else(|| {
                    CoreError::new("search_not_found", "搜索记录已过期，请重新搜索。")
                })?;
            if search.snapshot()["deviceId"] != device {
                return Err(CoreError::new(
                    "search_device_mismatch",
                    "搜索属于另一台设备。",
                ));
            }
            if command == "files.search.cancel" {
                search.cancel();
            }
            return Ok(search.snapshot());
        }
        let path = remote_path(required(p, "path")?)?;
        let query = p["query"]
            .as_str()
            .ok_or_else(|| CoreError::new("invalid_argument", "搜索文字无效。"))?;
        let filter = p["filter"]
            .as_str()
            .ok_or_else(|| CoreError::new("invalid_argument", "文件类型无效。"))?;
        if query.len() > 256
            || query.contains('\0')
            || (query.trim().is_empty() && filter == "all")
            || !matches!(
                filter,
                "all" | "images" | "videos" | "audio" | "documents" | "archives" | "folders"
            )
        {
            return Err(CoreError::new(
                "invalid_argument",
                "请输入最多 256 字节的文件名或选择有效文件类型。",
            ));
        }
        let client = self.client(device).await?;
        let store = self.store.read().await;
        if !store
            .devices
            .iter()
            .any(|record| record.id == device && record.status == "connected")
        {
            return Err(CoreError::new("disconnected", "设备尚未连接。"));
        }
        let connections = self.connections.lock().await;
        if connections.get(device).is_none_or(Client::is_closed) {
            return Err(CoreError::new("disconnected", "设备尚未连接。"));
        }
        let mut searches = self.searches.0.lock().expect("search registry");
        if searches
            .iter()
            .filter(|search| search.snapshot()["status"] == "running")
            .count()
            >= 4
        {
            return Err(CoreError::new(
                "search_busy",
                "最多同时运行 4 条搜索，请先取消或等待。",
            ));
        }
        while searches
            .iter()
            .filter(|search| search.snapshot()["status"] != "running")
            .count()
            >= 16
        {
            let index = searches
                .iter()
                .position(|search| search.snapshot()["status"] != "running")
                .unwrap();
            searches.remove(index);
        }
        let search = Arc::new(Search {
            snapshot: Mutex::new(
                json!({"searchId":uuid::Uuid::new_v4().to_string(),"deviceId":device,
                "path":path,"query":query,"filter":filter,"status":"running","entries":[],
                "visitedDirectories":0,"visitedEntries":0,"currentDirectory":"","complete":false,"issues":[],"limitation":LIMITATION,"canCancel":true}),
            ),
            cancellation: CancellationToken::new(),
        });
        let receipt = search.snapshot();
        searches.push_back(search.clone());
        drop(searches);
        drop(connections);
        drop(store);
        let query = fold(query);
        let filter = filter.to_owned();
        let registry = self.searches.0.clone();
        tokio::spawn(async move {
            let result = tokio::select! {
                biased;
                _ = search.cancellation.cancelled() => None,
                result = tokio::time::timeout(Duration::from_secs(30), walk(&search, &client, &path, &query, &filter)) => Some(result),
            };
            match result {
                None => search.finish("cancelled"),
                Some(Err(_)) => {
                    search.issue(&path, "time_limit", "达到 30 秒搜索时限，结果不完整。");
                    search.finish("partial");
                }
                Some(Ok(Err(error))) => {
                    search.issue(&path, &error.code, &error.message);
                    search.finish("failed");
                }
                Some(Ok(Ok(()))) => {
                    let partial = !search.snapshot()["issues"].as_array().unwrap().is_empty();
                    search.finish(if partial { "partial" } else { "completed" });
                }
            }
            let mut searches = registry.lock().expect("search registry");
            while searches
                .iter()
                .filter(|search| search.snapshot()["status"] != "running")
                .count()
                > 16
            {
                let index = searches
                    .iter()
                    .position(|search| search.snapshot()["status"] != "running")
                    .unwrap();
                searches.remove(index);
            }
        });
        Ok(receipt)
    }
}
fn options(search: &Search) -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(10),
        cancellation: search.cancellation.clone(),
    }
}
async fn stat(search: &Search, client: &Client, path: &str) -> CoreResult<FileStat> {
    crate::remote_fs::stat(client, path, true, options(search)).await
}
async fn native_children(
    search: &Search,
    client: &Client,
    path: &str,
    limit: usize,
) -> CoreResult<Vec<DirEntry>> {
    let listing = crate::remote_fs::fallback_children(client, path, limit, options(search)).await?;
    if listing.truncated {
        search.issue(path, "entry_limit", "达到目录项数量上限，结果不完整。");
    }
    let mut entries = Vec::with_capacity(listing.entries.len());
    for (name, stat) in listing.entries {
        match stat {
            Ok(stat) => entries.push(DirEntry { name, stat }),
            Err(error) => search.issue(path, &error.code, &error.message),
        }
    }
    Ok(entries)
}
fn alias(path: &str) -> bool {
    crate::remote_fs::storage_alias(path)
}
async fn check_root(search: &Search, client: &Client, path: &str) -> CoreResult<()> {
    let mut prefix = String::new();
    for component in path.split('/').filter(|part| !part.is_empty()) {
        prefix.push('/');
        prefix.push_str(component);
        let metadata = stat(search, client, &prefix).await?;
        if metadata.mode & 0o170000 == 0o120000 && !alias(&prefix) {
            return Err(CoreError::new(
                "search_root_symlink",
                "搜索根包含子符号链接；请选择其实际目录。仅允许 Android 标准共享存储别名。",
            ));
        }
    }
    if stat(search, client, path).await?.mode & 0o170000 != 0o040000 {
        return Err(CoreError::new("invalid_path", "搜索根必须是目录。"));
    }
    Ok(())
}
async fn walk(
    search: &Search,
    client: &Client,
    root: &str,
    query: &str,
    filter: &str,
) -> CoreResult<()> {
    check_root(search, client, root).await?;
    let mut queue = VecDeque::from([(root.to_owned(), 0usize)]);
    let mut visited = 0usize;
    let mut directories = 0usize;
    let mut queued = 1usize;
    while let Some((path, depth)) = queue.pop_front() {
        if search.cancellation.is_cancelled() {
            return Ok(());
        }
        {
            let mut snapshot = search.snapshot.lock().expect("search snapshot");
            if snapshot["status"] == "running" {
                snapshot["currentDirectory"] = json!(path);
            }
        }
        let before = match stat(search, client, &path).await {
            Ok(stat) if stat.mode & 0o170000 == 0o040000 || (path == root && alias(root)) => stat,
            Ok(_) => {
                search.issue(
                    &path,
                    "source_changed",
                    "目录已变为链接或其他类型，未继续遍历。",
                );
                continue;
            }
            Err(error) => {
                search.issue(&path, &error.code, &error.message);
                continue;
            }
        };
        // Some adbd LIST implementations turn opendir(EACCES) into empty DONE.
        // Confirm actual traversal permission before accepting an empty listing.
        if !crate::remote_fs::accessible(client, &path, options(search)).await? {
            search.issue(
                &path,
                "permission_denied",
                "无权读取或遍历此目录，搜索结果不完整。",
            );
            continue;
        }
        let mut sync = client.sync(options(search)).await?;
        let listed = if client.info().features.contains("ls_v2") {
            sync.list(
                &RemotePath::new(&path)?,
                MAX_DIRECTORY_ENTRIES.min(MAX_ENTRIES - visited),
            )
            .await
        } else {
            Err(interop_adb::Error::Unsupported("ls_v2"))
        };
        let children = match listed {
            Ok(children) => children,
            Err(error) => {
                if matches!(error, interop_adb::Error::OutputLimit) {
                    search.issue(&path, "entry_limit", "目录项数量超过上限，结果不完整。");
                    continue;
                }
                match native_children(
                    search,
                    client,
                    &path,
                    MAX_DIRECTORY_ENTRIES.min(MAX_ENTRIES - visited),
                )
                .await
                {
                    Ok(children) => children,
                    Err(error) => {
                        search.issue(&path, &error.code, &error.message);
                        continue;
                    }
                }
            }
        };
        directories += 1;
        {
            let mut snapshot = search.snapshot.lock().expect("search snapshot");
            if snapshot["status"] != "running" {
                return Ok(());
            }
            snapshot["visitedDirectories"] = json!(directories);
        }
        for child in children {
            visited += 1;
            {
                let mut snapshot = search.snapshot.lock().expect("search snapshot");
                if snapshot["status"] != "running" {
                    return Ok(());
                }
                snapshot["visitedEntries"] = json!(visited);
            }
            let name = match String::from_utf8(child.name) {
                Ok(name) => name,
                Err(_) => {
                    search.issue(
                        &path,
                        "invalid_filename",
                        "目录包含无法表示为有效文字的文件名，已跳过且未生成可操作路径。",
                    );
                    continue;
                }
            };
            let child_path = match remote_path(&format!("{}/{}", path.trim_end_matches('/'), name))
            {
                Ok(child_path) => child_path,
                Err(_) => {
                    search.issue(
                        &path,
                        "invalid_path",
                        "目录项路径超过可操作路径上限，已跳过。",
                    );
                    continue;
                }
            };
            let kind = child.stat.mode & 0o170000;
            if kind == 0o040000 {
                if depth >= MAX_DEPTH {
                    search.issue(&child_path, "depth_limit", "达到 32 层目录深度上限。");
                } else if queued >= MAX_DIRECTORIES {
                    search.issue(&child_path, "directory_limit", "达到 2048 个目录上限。");
                } else {
                    queue.push_back((child_path.clone(), depth + 1));
                    queued += 1;
                }
            }
            if fold(&name).contains(query) && matches_filter(filter, &child_path, kind) {
                let mut snapshot = search.snapshot.lock().expect("search snapshot");
                if snapshot["status"] != "running" {
                    return Ok(());
                }
                let entries = snapshot["entries"].as_array_mut().unwrap();
                let ordinary = matches!(kind, 0o040000 | 0o100000);
                entries.push(json!({"name":name,"path":child_path,"isDirectory":kind == 0o040000,
                    "isSymlink":kind == 0o120000,"size":child.stat.size,"modified":child.stat.modified_seconds,
                    "mime":mime(&child_path),"canOpen":ordinary,"canManage":true,"nameIsUtf8":true,
                    "reason":if ordinary { Value::Null } else {json!("链接和特殊文件不跟随打开。")}}));
                if entries.len() >= MAX_RESULTS {
                    drop(snapshot);
                    search.issue(
                        &path,
                        "result_limit",
                        "达到 500 个结果上限，结果不完整；请缩小范围。",
                    );
                    return Ok(());
                }
            }
            if visited >= MAX_ENTRIES {
                search.issue(&path, "entry_limit", "达到 50000 项搜索上限。");
                return Ok(());
            }
        }
        match stat(search, client, &path).await {
            Ok(after)
                if before.mode == after.mode
                    && before.modified_seconds == after.modified_seconds
                    && before.size == after.size => {}
            _ => search.issue(
                &path,
                "source_changed",
                "搜索期间目录已变化，结果可能不完整。",
            ),
        }
    }
    Ok(())
}
fn matches_filter(filter: &str, path: &str, kind: u32) -> bool {
    if filter == "all" {
        return true;
    }
    if filter == "folders" {
        return kind == 0o040000;
    }
    if kind != 0o100000 {
        return false;
    }
    let extension = path.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    let mime = mime(path);
    match filter {
        "images" => mime.starts_with("image/"),
        "videos" => mime.starts_with("video/"),
        "audio" => {
            mime.starts_with("audio/")
                || matches!(
                    extension.as_str(),
                    "mp3" | "m4a" | "aac" | "wav" | "flac" | "ogg" | "opus" | "wma"
                )
        }
        "documents" => matches!(
            extension.as_str(),
            "pdf"
                | "txt"
                | "md"
                | "csv"
                | "rtf"
                | "doc"
                | "docx"
                | "xls"
                | "xlsx"
                | "ppt"
                | "pptx"
                | "odt"
                | "ods"
                | "odp"
                | "epub"
        ),
        "archives" => matches!(
            extension.as_str(),
            "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" | "zst" | "tgz"
        ),
        _ => false,
    }
}
// The 125 exceptional mappings were generated from Python's Unicode 15.0.0
// str.casefold() != str.lower(), excluding the compressed Cherokee ranges.
// Verified against the C + F records in the authoritative pinned source:
// https://www.unicode.org/Public/15.0.0/ucd/CaseFolding.txt
// SHA256 cdd49e55eae3bbf1f0a3f6580c974a0263cb86a6a08daa10fbf705b4808a56f7
// Remaining mappings use Rust's Unicode lowercase tables; this combination is
// not a frozen implementation of every later Unicode version. Changing the
// toolchain or pinned Unicode version requires revalidating these exceptions.
// Cherokee case folding deliberately uses uppercase per the default mapping.
fn fold(value: &str) -> String {
    let mut output = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '\u{13a0}'..='\u{13f5}' | '\u{13f8}'..='\u{13fd}' | '\u{ab70}'..='\u{abbf}' => {
                output.extend(character.to_uppercase())
            }
            '\u{b5}' => output.push('\u{3bc}'),
            '\u{df}' => output.push_str("\u{73}\u{73}"),
            '\u{149}' => output.push_str("\u{2bc}\u{6e}"),
            '\u{17f}' => output.push('\u{73}'),
            '\u{1f0}' => output.push_str("\u{6a}\u{30c}"),
            '\u{345}' => output.push('\u{3b9}'),
            '\u{390}' => output.push_str("\u{3b9}\u{308}\u{301}"),
            '\u{3b0}' => output.push_str("\u{3c5}\u{308}\u{301}"),
            '\u{3c2}' => output.push('\u{3c3}'),
            '\u{3d0}' => output.push('\u{3b2}'),
            '\u{3d1}' => output.push('\u{3b8}'),
            '\u{3d5}' => output.push('\u{3c6}'),
            '\u{3d6}' => output.push('\u{3c0}'),
            '\u{3f0}' => output.push('\u{3ba}'),
            '\u{3f1}' => output.push('\u{3c1}'),
            '\u{3f5}' => output.push('\u{3b5}'),
            '\u{587}' => output.push_str("\u{565}\u{582}"),
            '\u{1c80}' => output.push('\u{432}'),
            '\u{1c81}' => output.push('\u{434}'),
            '\u{1c82}' => output.push('\u{43e}'),
            '\u{1c83}' => output.push('\u{441}'),
            '\u{1c84}' => output.push('\u{442}'),
            '\u{1c85}' => output.push('\u{442}'),
            '\u{1c86}' => output.push('\u{44a}'),
            '\u{1c87}' => output.push('\u{463}'),
            '\u{1c88}' => output.push('\u{a64b}'),
            '\u{1e96}' => output.push_str("\u{68}\u{331}"),
            '\u{1e97}' => output.push_str("\u{74}\u{308}"),
            '\u{1e98}' => output.push_str("\u{77}\u{30a}"),
            '\u{1e99}' => output.push_str("\u{79}\u{30a}"),
            '\u{1e9a}' => output.push_str("\u{61}\u{2be}"),
            '\u{1e9b}' => output.push('\u{1e61}'),
            '\u{1e9e}' => output.push_str("\u{73}\u{73}"),
            '\u{1f50}' => output.push_str("\u{3c5}\u{313}"),
            '\u{1f52}' => output.push_str("\u{3c5}\u{313}\u{300}"),
            '\u{1f54}' => output.push_str("\u{3c5}\u{313}\u{301}"),
            '\u{1f56}' => output.push_str("\u{3c5}\u{313}\u{342}"),
            '\u{1f80}' => output.push_str("\u{1f00}\u{3b9}"),
            '\u{1f81}' => output.push_str("\u{1f01}\u{3b9}"),
            '\u{1f82}' => output.push_str("\u{1f02}\u{3b9}"),
            '\u{1f83}' => output.push_str("\u{1f03}\u{3b9}"),
            '\u{1f84}' => output.push_str("\u{1f04}\u{3b9}"),
            '\u{1f85}' => output.push_str("\u{1f05}\u{3b9}"),
            '\u{1f86}' => output.push_str("\u{1f06}\u{3b9}"),
            '\u{1f87}' => output.push_str("\u{1f07}\u{3b9}"),
            '\u{1f88}' => output.push_str("\u{1f00}\u{3b9}"),
            '\u{1f89}' => output.push_str("\u{1f01}\u{3b9}"),
            '\u{1f8a}' => output.push_str("\u{1f02}\u{3b9}"),
            '\u{1f8b}' => output.push_str("\u{1f03}\u{3b9}"),
            '\u{1f8c}' => output.push_str("\u{1f04}\u{3b9}"),
            '\u{1f8d}' => output.push_str("\u{1f05}\u{3b9}"),
            '\u{1f8e}' => output.push_str("\u{1f06}\u{3b9}"),
            '\u{1f8f}' => output.push_str("\u{1f07}\u{3b9}"),
            '\u{1f90}' => output.push_str("\u{1f20}\u{3b9}"),
            '\u{1f91}' => output.push_str("\u{1f21}\u{3b9}"),
            '\u{1f92}' => output.push_str("\u{1f22}\u{3b9}"),
            '\u{1f93}' => output.push_str("\u{1f23}\u{3b9}"),
            '\u{1f94}' => output.push_str("\u{1f24}\u{3b9}"),
            '\u{1f95}' => output.push_str("\u{1f25}\u{3b9}"),
            '\u{1f96}' => output.push_str("\u{1f26}\u{3b9}"),
            '\u{1f97}' => output.push_str("\u{1f27}\u{3b9}"),
            '\u{1f98}' => output.push_str("\u{1f20}\u{3b9}"),
            '\u{1f99}' => output.push_str("\u{1f21}\u{3b9}"),
            '\u{1f9a}' => output.push_str("\u{1f22}\u{3b9}"),
            '\u{1f9b}' => output.push_str("\u{1f23}\u{3b9}"),
            '\u{1f9c}' => output.push_str("\u{1f24}\u{3b9}"),
            '\u{1f9d}' => output.push_str("\u{1f25}\u{3b9}"),
            '\u{1f9e}' => output.push_str("\u{1f26}\u{3b9}"),
            '\u{1f9f}' => output.push_str("\u{1f27}\u{3b9}"),
            '\u{1fa0}' => output.push_str("\u{1f60}\u{3b9}"),
            '\u{1fa1}' => output.push_str("\u{1f61}\u{3b9}"),
            '\u{1fa2}' => output.push_str("\u{1f62}\u{3b9}"),
            '\u{1fa3}' => output.push_str("\u{1f63}\u{3b9}"),
            '\u{1fa4}' => output.push_str("\u{1f64}\u{3b9}"),
            '\u{1fa5}' => output.push_str("\u{1f65}\u{3b9}"),
            '\u{1fa6}' => output.push_str("\u{1f66}\u{3b9}"),
            '\u{1fa7}' => output.push_str("\u{1f67}\u{3b9}"),
            '\u{1fa8}' => output.push_str("\u{1f60}\u{3b9}"),
            '\u{1fa9}' => output.push_str("\u{1f61}\u{3b9}"),
            '\u{1faa}' => output.push_str("\u{1f62}\u{3b9}"),
            '\u{1fab}' => output.push_str("\u{1f63}\u{3b9}"),
            '\u{1fac}' => output.push_str("\u{1f64}\u{3b9}"),
            '\u{1fad}' => output.push_str("\u{1f65}\u{3b9}"),
            '\u{1fae}' => output.push_str("\u{1f66}\u{3b9}"),
            '\u{1faf}' => output.push_str("\u{1f67}\u{3b9}"),
            '\u{1fb2}' => output.push_str("\u{1f70}\u{3b9}"),
            '\u{1fb3}' => output.push_str("\u{3b1}\u{3b9}"),
            '\u{1fb4}' => output.push_str("\u{3ac}\u{3b9}"),
            '\u{1fb6}' => output.push_str("\u{3b1}\u{342}"),
            '\u{1fb7}' => output.push_str("\u{3b1}\u{342}\u{3b9}"),
            '\u{1fbc}' => output.push_str("\u{3b1}\u{3b9}"),
            '\u{1fbe}' => output.push('\u{3b9}'),
            '\u{1fc2}' => output.push_str("\u{1f74}\u{3b9}"),
            '\u{1fc3}' => output.push_str("\u{3b7}\u{3b9}"),
            '\u{1fc4}' => output.push_str("\u{3ae}\u{3b9}"),
            '\u{1fc6}' => output.push_str("\u{3b7}\u{342}"),
            '\u{1fc7}' => output.push_str("\u{3b7}\u{342}\u{3b9}"),
            '\u{1fcc}' => output.push_str("\u{3b7}\u{3b9}"),
            '\u{1fd2}' => output.push_str("\u{3b9}\u{308}\u{300}"),
            '\u{1fd3}' => output.push_str("\u{3b9}\u{308}\u{301}"),
            '\u{1fd6}' => output.push_str("\u{3b9}\u{342}"),
            '\u{1fd7}' => output.push_str("\u{3b9}\u{308}\u{342}"),
            '\u{1fe2}' => output.push_str("\u{3c5}\u{308}\u{300}"),
            '\u{1fe3}' => output.push_str("\u{3c5}\u{308}\u{301}"),
            '\u{1fe4}' => output.push_str("\u{3c1}\u{313}"),
            '\u{1fe6}' => output.push_str("\u{3c5}\u{342}"),
            '\u{1fe7}' => output.push_str("\u{3c5}\u{308}\u{342}"),
            '\u{1ff2}' => output.push_str("\u{1f7c}\u{3b9}"),
            '\u{1ff3}' => output.push_str("\u{3c9}\u{3b9}"),
            '\u{1ff4}' => output.push_str("\u{3ce}\u{3b9}"),
            '\u{1ff6}' => output.push_str("\u{3c9}\u{342}"),
            '\u{1ff7}' => output.push_str("\u{3c9}\u{342}\u{3b9}"),
            '\u{1ffc}' => output.push_str("\u{3c9}\u{3b9}"),
            '\u{fb00}' => output.push_str("\u{66}\u{66}"),
            '\u{fb01}' => output.push_str("\u{66}\u{69}"),
            '\u{fb02}' => output.push_str("\u{66}\u{6c}"),
            '\u{fb03}' => output.push_str("\u{66}\u{66}\u{69}"),
            '\u{fb04}' => output.push_str("\u{66}\u{66}\u{6c}"),
            '\u{fb05}' => output.push_str("\u{73}\u{74}"),
            '\u{fb06}' => output.push_str("\u{73}\u{74}"),
            '\u{fb13}' => output.push_str("\u{574}\u{576}"),
            '\u{fb14}' => output.push_str("\u{574}\u{565}"),
            '\u{fb15}' => output.push_str("\u{574}\u{56b}"),
            '\u{fb16}' => output.push_str("\u{57e}\u{576}"),
            '\u{fb17}' => output.push_str("\u{574}\u{56d}"),
            other => output.extend(other.to_lowercase()),
        }
    }
    output
}
