//! Managed media ownership and byte admission. The gate orders admission,
//! durable delivery ownership and eviction; network work never holds it.
use crate::{CoreError, CoreResult, Runtime, model::required};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeSet, HashMap},
    path::{Component, Path, PathBuf},
    sync::{Arc, Mutex as StdMutex},
    time::SystemTime,
};
use tokio::{fs, sync::Mutex};

const DEFAULT_BUDGET: u64 = 512 * 1024 * 1024;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Configuration {
    budget_bytes: u64,
    outgoing_directory: Option<PathBuf>,
    retained_shares: BTreeSet<PathBuf>,
}
impl Default for Configuration {
    fn default() -> Self {
        Self {
            budget_bytes: DEFAULT_BUDGET,
            outgoing_directory: None,
            retained_shares: BTreeSet::new(),
        }
    }
}
#[derive(Clone)]
struct Reservation {
    path: PathBuf,
    bytes: u64,
    baseline: u64,
}
#[derive(Default)]
struct Ownership {
    leases: HashMap<String, Vec<PathBuf>>,
    writers: HashMap<String, Reservation>,
}
pub(crate) struct MediaCache {
    pub(crate) gate: Mutex<()>,
    configuration: Mutex<Configuration>,
    ownership: Arc<StdMutex<Ownership>>,
    path: PathBuf,
}
pub(crate) struct Writer {
    id: String,
    ownership: Arc<StdMutex<Ownership>>,
}
impl Drop for Writer {
    fn drop(&mut self) {
        if let Ok(mut ownership) = self.ownership.lock() {
            ownership.writers.remove(&self.id);
        }
    }
}
struct File {
    path: PathBuf,
    bytes: u64,
    modified: SystemTime,
}
struct Snapshot {
    files: Vec<File>,
    protected: Vec<PathBuf>,
    used: u64,
    reserved: u64,
    protected_bytes: u64,
}
fn covered(path: &Path, protections: &[PathBuf]) -> bool {
    protections.iter().any(|root| path.starts_with(root))
}
fn invalid(message: &str) -> CoreError {
    CoreError::new("invalid_argument", message)
}

// Reject links in every existing component, including the registered root.
async fn plain_path(path: &Path) -> CoreResult<()> {
    if !path.is_absolute()
        || path
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
    {
        return Err(invalid("缓存路径必须是没有相对分量的绝对路径。"));
    }
    let mut current = PathBuf::new();
    for component in path.components() {
        current.push(component);
        // A Windows prefix (for example \\?\C:) is not a filesystem object
        // until RootDir is appended. Querying it returns ERROR_INVALID_FUNCTION.
        // Keep checking the complete root and every following directory.
        if matches!(component, Component::Prefix(_)) {
            continue;
        }
        match fs::symlink_metadata(&current).await {
            Ok(meta) if meta.is_symlink() => return Err(invalid("缓存路径不能经过符号链接。")),
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}
async fn scan(roots: &[PathBuf]) -> CoreResult<Vec<File>> {
    let mut pending = roots.to_vec();
    let mut files = Vec::new();
    while let Some(path) = pending.pop() {
        let meta = match fs::symlink_metadata(&path).await {
            Ok(meta) => meta,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };
        if meta.is_symlink() {
            continue;
        }
        if meta.is_dir() {
            let mut entries = fs::read_dir(path).await?;
            while let Some(entry) = entries.next_entry().await? {
                pending.push(entry.path());
            }
        } else if meta.is_file() {
            files.push(File {
                path,
                bytes: meta.len(),
                modified: meta.modified().unwrap_or(SystemTime::UNIX_EPOCH),
            });
        }
    }
    files.sort_by(|a, b| a.modified.cmp(&b.modified).then(a.path.cmp(&b.path)));
    Ok(files)
}
impl MediaCache {
    pub(crate) async fn open(root: &Path) -> CoreResult<Self> {
        let path = root.join("media-cache.json");
        let configuration = match fs::read(&path).await {
            Ok(bytes) if bytes.len() <= 1024 * 1024 => {
                serde_json::from_slice::<Configuration>(&bytes).map_err(|_| {
                    CoreError::new("cache_storage_invalid", "媒体缓存所有权记录损坏。")
                })?
            }
            Ok(_) => {
                return Err(CoreError::new(
                    "cache_storage_invalid",
                    "媒体缓存所有权记录过大。",
                ));
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Configuration::default(),
            Err(error) => return Err(error.into()),
        };
        if configuration.budget_bytes == 0 {
            return Err(invalid("缓存限额必须大于零。"));
        }
        if let Some(outgoing) = &configuration.outgoing_directory {
            Self::validate_outgoing(root, outgoing).await?;
        }
        Ok(Self {
            gate: Mutex::new(()),
            configuration: Mutex::new(configuration),
            ownership: Arc::new(StdMutex::new(Ownership::default())),
            path,
        })
    }
    async fn validate_outgoing(root: &Path, outgoing: &Path) -> CoreResult<()> {
        plain_path(outgoing).await?;
        if outgoing.file_name().and_then(|s| s.to_str()) != Some("outgoing")
            || root.starts_with(outgoing)
            || outgoing.starts_with(root.join("media"))
        {
            return Err(invalid(
                "仅可登记应用缓存中的 outgoing 目录，不能登记应用根目录。",
            ));
        }
        Ok(())
    }
    async fn roots(&self, root: &Path) -> CoreResult<Vec<PathBuf>> {
        let mut roots = vec![root.join("media")];
        if let Some(outgoing) = &self.configuration.lock().await.outgoing_directory {
            roots.push(outgoing.clone());
        }
        for path in &roots {
            plain_path(path).await?;
        }
        Ok(roots)
    }
    pub(crate) fn lease(&self, paths: Vec<PathBuf>) -> String {
        let id = uuid::Uuid::new_v4().to_string();
        self.ownership
            .lock()
            .unwrap()
            .leases
            .insert(id.clone(), paths);
        id
    }
    async fn write_configuration(&self, configuration: &Configuration) -> CoreResult<()> {
        let bytes = serde_json::to_vec(configuration)?;
        if bytes.len() > 1024 * 1024 {
            return Err(CoreError::new(
                "cache_capacity",
                "媒体分享保留记录已满，请先保留当前原件。",
            ));
        }
        Runtime::private_write(&self.path, &bytes).await
    }
}
impl Runtime {
    /// Admit and protect paths selected by the Dart task owner. No transfer
    /// status or conflict policy is retained in this execution layer.
    pub async fn execute_file_cache_reserve(
        &self,
        paths: Vec<String>,
        bytes: Vec<u64>,
    ) -> CoreResult<String> {
        if paths.is_empty() || paths.len() > 2000 || paths.len() != bytes.len() {
            return Err(invalid("缓存保留路径必须为1至2000项。"));
        }
        let _gate = self.media_cache.gate.lock().await;
        let roots = self.media_cache.roots(&self.root).await?;
        let mut records = Vec::new();
        let fresh_reservation = bytes.iter().any(|bytes| *bytes > 0);
        let mut total = 0u64;
        for (path, bytes) in paths.into_iter().zip(bytes) {
            let path = PathBuf::from(path);
            plain_path(&path).await?;
            if fresh_reservation {
                self.cache_validate_destination_locked(path.to_string_lossy().as_ref())
                    .await?;
            }
            if !roots.iter().any(|root| path.starts_with(root)) {
                return Err(invalid("目标不属于已登记缓存目录。"));
            }
            let baseline = scan(std::slice::from_ref(&path))
                .await?
                .iter()
                .map(|f| f.bytes)
                .sum();
            total = total
                .checked_add(bytes)
                .ok_or_else(|| invalid("缓存大小溢出。"))?;
            records.push(Reservation {
                path,
                bytes,
                baseline,
            });
        }
        if total > 0 {
            self.cache_admit_locked(total).await?;
        }
        let id = uuid::Uuid::new_v4().to_string();
        let mut owner = self.media_cache.ownership.lock().unwrap();
        if owner.leases.len() >= 1024 {
            return Err(CoreError::new("busy", "缓存租约达到上限。"));
        }
        owner
            .leases
            .insert(id.clone(), records.iter().map(|r| r.path.clone()).collect());
        for (index, record) in records.into_iter().enumerate() {
            owner.writers.insert(format!("{id}:{index}"), record);
        }
        Ok(id)
    }
    pub async fn execute_file_cache_release(&self, id: &str) -> CoreResult<()> {
        self.cache_command("media.cache.release", &serde_json::json!({"leaseId":id}))
            .await?;
        Ok(())
    }
    async fn cache_snapshot(&self) -> CoreResult<Snapshot> {
        let files = scan(&self.media_cache.roots(&self.root).await?).await?;
        let (mut protected, writers) = {
            let owner = self.media_cache.ownership.lock().unwrap();
            (
                owner.leases.values().flatten().cloned().collect::<Vec<_>>(),
                owner.writers.values().cloned().collect::<Vec<_>>(),
            )
        };
        protected.extend(
            self.media_cache
                .configuration
                .lock()
                .await
                .retained_shares
                .iter()
                .cloned(),
        );
        protected.extend(self.deliveries.protected_paths().await);
        let mut reserved = 0_u64;
        for writer in writers {
            let actual = files
                .iter()
                .filter(|file| file.path.starts_with(&writer.path))
                .map(|f| f.bytes)
                .sum::<u64>();
            reserved = reserved.saturating_add(
                writer
                    .bytes
                    .saturating_sub(actual.saturating_sub(writer.baseline)),
            );
            protected.push(writer.path);
        }
        let used = files.iter().map(|f| f.bytes).sum();
        let protected_bytes = files
            .iter()
            .filter(|f| covered(&f.path, &protected))
            .map(|f| f.bytes)
            .sum();
        Ok(Snapshot {
            files,
            protected,
            used,
            reserved,
            protected_bytes,
        })
    }
    async fn cache_status_locked(&self) -> CoreResult<Value> {
        let snapshot = self.cache_snapshot().await?;
        let configuration = self.media_cache.configuration.lock().await;
        Ok(
            json!({"budgetBytes":configuration.budget_bytes,"usedBytes":snapshot.used,"protectedBytes":snapshot.protected_bytes,
            "reclaimableBytes":snapshot.used.saturating_sub(snapshot.protected_bytes),"reservedBytes":snapshot.reserved,
            "retainedShareCount":configuration.retained_shares.len(),"retentionReason":if configuration.retained_shares.is_empty(){Value::Null}else{json!("系统分享尚无可靠的读取完成回执，已分享的缓存会继续保留。")}}),
        )
    }
    // Caller owns the cache gate. Eviction uses the same ownership snapshot as
    // admission; delivery.begin cannot publish between snapshot and deletion.
    pub(crate) async fn cache_admit_locked(&self, bytes: u64) -> CoreResult<()> {
        let budget = self.media_cache.configuration.lock().await.budget_bytes;
        let snapshot = self.cache_snapshot().await?;
        let required = snapshot
            .used
            .saturating_add(snapshot.reserved)
            .saturating_add(bytes);
        if required <= budget {
            return Ok(());
        }
        let reclaimable = snapshot.used.saturating_sub(snapshot.protected_bytes);
        if required.saturating_sub(reclaimable) > budget {
            return Err(CoreError::new(
                "cache_budget_exceeded",
                "媒体缓存空间不足；正在使用、保存或系统分享的内容会继续保留。",
            ));
        }
        self.cache_delete_locked(snapshot, required - budget)
            .await?;
        let after = self.cache_snapshot().await?;
        if after
            .used
            .saturating_add(after.reserved)
            .saturating_add(bytes)
            > budget
        {
            return Err(CoreError::new(
                "cache_budget_exceeded",
                "媒体缓存空间不足；未覆盖仍在使用的内容。",
            ));
        }
        Ok(())
    }
    async fn cache_delete_locked(&self, snapshot: Snapshot, wanted: u64) -> CoreResult<u64> {
        let mut deleted = 0_u64;
        let mut deleted_paths = Vec::new();
        let mut failure = None;
        for file in snapshot.files {
            if deleted >= wanted {
                break;
            }
            if covered(&file.path, &snapshot.protected) {
                continue;
            }
            if plain_path(&file.path).await.is_err() {
                continue;
            }
            match fs::symlink_metadata(&file.path).await {
                Ok(meta) if meta.is_file() => match fs::remove_file(&file.path).await {
                    Ok(()) => {
                        deleted = deleted.saturating_add(meta.len());
                        deleted_paths.push(file.path);
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => {
                        failure = Some(error);
                        break;
                    }
                },
                Ok(_) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => {
                    failure = Some(error);
                    break;
                }
            }
        }
        if let Some(error) = failure {
            return Err(error.into());
        }
        Ok(deleted)
    }
    pub(crate) async fn cache_writer(&self, path: PathBuf, bytes: u64) -> CoreResult<Writer> {
        let _gate = self.media_cache.gate.lock().await;
        plain_path(&path).await?;
        if bytes > 0 {
            self.cache_admit_locked(bytes).await?;
        }
        let baseline = scan(std::slice::from_ref(&path))
            .await?
            .iter()
            .map(|f| f.bytes)
            .sum();
        let id = uuid::Uuid::new_v4().to_string();
        self.media_cache.ownership.lock().unwrap().writers.insert(
            id.clone(),
            Reservation {
                path,
                bytes,
                baseline,
            },
        );
        Ok(Writer {
            id,
            ownership: self.media_cache.ownership.clone(),
        })
    }
    pub(crate) async fn cache_command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        let _gate = self.media_cache.gate.lock().await;
        match command {
            "media.cache.status" => self.cache_status_locked().await,
            "media.cache.configure" => {
                let mut configuration = self.media_cache.configuration.lock().await;
                let mut next = configuration.clone();
                if let Some(value) = params.get("budgetBytes") {
                    next.budget_bytes = value
                        .as_u64()
                        .filter(|n| *n > 0)
                        .ok_or_else(|| invalid("缓存限额必须为正整数。"))?;
                }
                if let Some(value) = params.get("outgoingDirectory") {
                    let path =
                        PathBuf::from(value.as_str().ok_or_else(|| invalid("缓存目录无效。"))?);
                    MediaCache::validate_outgoing(&self.root, &path).await?;
                    if configuration
                        .outgoing_directory
                        .as_ref()
                        .is_some_and(|old| old != &path)
                    {
                        return Err(CoreError::new(
                            "cache_configuration_conflict",
                            "已登记的原件缓存目录不能被另一目录替换。",
                        ));
                    }
                    fs::create_dir_all(&path).await?;
                    next.outgoing_directory = Some(path);
                }
                self.media_cache.write_configuration(&next).await?;
                *configuration = next;
                drop(configuration);
                let result = self.cache_status_locked().await?;
                self.emit("media.cache.changed", None, result.clone());
                Ok(result)
            }
            "media.cache.clear" => {
                let snapshot = self.cache_snapshot().await?;
                let deleted = self.cache_delete_locked(snapshot, u64::MAX).await?;
                let mut result = self.cache_status_locked().await?;
                result["deletedBytes"] = json!(deleted);
                self.emit("media.cache.changed", None, result.clone());
                Ok(result)
            }
            "media.cache.release" => {
                let id = uuid::Uuid::parse_str(required(params, "leaseId")?)
                    .map_err(|_| invalid("缓存租约标识必须为 UUID。"))?
                    .to_string();
                let mut ownership = self.media_cache.ownership.lock().unwrap();
                let released = ownership.leases.remove(&id).is_some();
                let prefix = format!("{id}:");
                ownership.writers.retain(|key, _| !key.starts_with(&prefix));
                Ok(json!({"leaseId":id,"released":released}))
            }
            "media.cache.acquire" => Err(CoreError::new(
                "owner_moved",
                "缓存任务路径由 Dart device_files 核验后保留。",
            )),
            "media.cache.retain" => {
                let path = PathBuf::from(required(params, "localPath")?);
                plain_path(&path).await?;
                if !self
                    .media_cache
                    .roots(&self.root)
                    .await?
                    .iter()
                    .any(|root| path.starts_with(root))
                {
                    if params["ifManaged"] == true {
                        return Ok(json!({"managed":false,"retained":false}));
                    }
                    return Err(invalid("只能保留已登记媒体缓存中的内容。"));
                }
                let meta = fs::symlink_metadata(&path).await.map_err(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        CoreError::new("cache_evicted", "此媒体缓存已经清理，请重新取回。")
                    } else {
                        error.into()
                    }
                })?;
                if !meta.is_file() && !meta.is_dir() {
                    return Err(invalid("只能保留普通文件或目录。"));
                }
                let mut configuration = self.media_cache.configuration.lock().await;
                let mut next = configuration.clone();
                next.retained_shares.insert(path);
                self.media_cache.write_configuration(&next).await?;
                *configuration = next;
                Ok(json!({"managed":true,"retained":true,"reason":"systemShareLifetimeUnknown"}))
            }
            _ => Err(CoreError::new("unknown_command", "未知媒体缓存操作。")),
        }
    }
    pub(crate) async fn cache_validate_destination_locked(&self, path: &str) -> CoreResult<()> {
        let path = Path::new(path);
        plain_path(path).await?;
        if !self
            .media_cache
            .roots(&self.root)
            .await?
            .iter()
            .any(|root| path.starts_with(root))
        {
            return Err(invalid("私有原件必须存入已登记的缓存目录。"));
        }
        let snapshot = self.cache_snapshot().await?;
        if covered(path, &snapshot.protected)
            || snapshot.protected.iter().any(|p| p.starts_with(path))
        {
            return Err(CoreError::new(
                "cache_in_use",
                "目标缓存正被其他操作使用，请使用新的取回位置。",
            ));
        }
        Ok(())
    }
    pub(crate) async fn cache_validate_delivery_locked(&self, params: &Value) -> CoreResult<()> {
        let Some(path) = params["localPath"].as_str().map(Path::new) else {
            return Ok(());
        };
        if self
            .media_cache
            .roots(&self.root)
            .await?
            .iter()
            .any(|root| path.starts_with(root))
        {
            plain_path(path).await?;
            if fs::symlink_metadata(path).await.is_err() {
                return Err(CoreError::new(
                    "cache_evicted",
                    "此媒体缓存已经清理，请重新取回。",
                ));
            }
        }
        Ok(())
    }
}
