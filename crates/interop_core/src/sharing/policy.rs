use super::legacy;
use crate::{CoreError, CoreResult};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

pub(super) fn millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}
pub(super) fn valid_id(id: &str) -> bool {
    uuid::Uuid::parse_str(id).is_ok_and(|value| value.to_string() == id)
}
fn bad(message: &str) -> CoreError {
    CoreError::new("share_source_invalid", message)
}

#[derive(Clone, Debug)]
pub struct Limits {
    pub pending: usize,
    pub batches: usize,
    pub leases: usize,
    pub sources: usize,
    pub file_bytes: u64,
    pub batch_bytes: u64,
    pub total_bytes: u64,
    pub timeout: std::time::Duration,
    pub pending_expiry: std::time::Duration,
    pub references: usize,
    pub paths_per_reference: usize,
    pub total_paths: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            pending: 8,
            batches: 64,
            leases: 128,
            sources: 32,
            file_bytes: 512 * 1024 * 1024,
            batch_bytes: 1024 * 1024 * 1024,
            total_bytes: 2 * 1024 * 1024 * 1024,
            timeout: std::time::Duration::from_secs(120),
            pending_expiry: std::time::Duration::from_secs(86400),
            references: 1024,
            paths_per_reference: 2048,
            total_paths: 8192,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedFile {
    pub disk_name: String,
    pub name: String,
    pub size: u64,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Batch {
    version: u32,
    pub id: String,
    pub created: u64,
    pub visible: bool,
    pub status: String,
    pub bytes: u64,
    pub text: Option<String>,
    pub mime: Option<String>,
    pub files: Vec<SharedFile>,
    pub errors: Vec<String>,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Lease {
    version: u32,
    pub id: String,
    pub share_id: String,
    pub transfer_id: Option<String>,
    #[serde(default)]
    pub request: Option<Value>,
    #[serde(default)]
    pub publication: Option<String>,
    #[serde(default)]
    pub receipt: Option<Value>,
}
pub(super) struct Policy {
    pub root: PathBuf,
    pub limits: Limits,
    pub batches: BTreeMap<String, Batch>,
    pub leases: BTreeMap<String, Lease>,
    unknown_bytes: u64,
    unknown_batches: usize,
    uncertain: bool,
}
impl Policy {
    pub fn open(root: PathBuf, limits: Limits) -> CoreResult<Self> {
        fs::create_dir_all(&root)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&root, fs::Permissions::from_mode(0o700))?;
        }
        let mut state = Self {
            root,
            limits,
            batches: BTreeMap::new(),
            leases: BTreeMap::new(),
            unknown_bytes: 0,
            unknown_batches: 0,
            uncertain: false,
        };
        let mut scanned = 0usize;
        for entry in fs::read_dir(&state.root)? {
            let entry = entry?;
            if entry.file_name() == ".leases" {
                continue;
            }
            scanned += 1;
            if scanned > 4096 {
                state.uncertain = true;
                break;
            }
            if !entry.file_type()?.is_dir() {
                state.uncertain = true;
                continue;
            }
            let id = entry.file_name().to_string_lossy().into_owned();
            let loaded = state.load_batch(&id);
            match loaded {
                Ok(batch) if state.batches.len() < state.limits.batches => {
                    state.batches.insert(id, batch);
                }
                _ => {
                    state.unknown_batches += 1;
                    state.uncertain = true;
                }
            }
        }
        let directory = state.root.join(".leases");
        fs::create_dir_all(&directory)?;
        if !fs::symlink_metadata(&directory)?.is_dir() {
            return Err(bad("分享租约目录类型无效，未读取范围外记录。"));
        }
        for (index, entry) in fs::read_dir(&directory)?.enumerate() {
            if index >= state.limits.leases {
                state.uncertain = true;
                break;
            }
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                state.uncertain = true;
                continue;
            }
            let id = entry.file_name().to_string_lossy().into_owned();
            let loaded = (|| {
                if !valid_id(&id) {
                    return Err(bad("分享租约标识无效。"));
                }
                let bytes = bounded_read(&entry.path(), 16 * 1024)?;
                let mut lease: Lease = if bytes.first() == Some(&b'{') {
                    serde_json::from_slice(&bytes)?
                } else {
                    let p = legacy::properties(&entry.path(), 16 * 1024)?;
                    Lease {
                        version: 2,
                        id: id.clone(),
                        share_id: p
                            .get("share")
                            .cloned()
                            .ok_or_else(|| bad("分享租约缺少来源。"))?,
                        transfer_id: p.get("transfer").cloned(),
                        request: None,
                        publication: None,
                        receipt: None,
                    }
                };
                if lease.version != 2
                    || lease.id != id
                    || !state.batches.contains_key(&lease.share_id)
                {
                    return Err(bad("分享租约来源无法核对。"));
                }
                if lease.publication.as_deref() == Some("publishing") {
                    lease.publication = Some("unknown".into());
                }
                if let Some(request) = &lease.request
                    && !request
                        .as_str()
                        .is_some_and(|s| s.starts_with("sha256:") && s.len() == 71)
                {
                    lease.request = Some(request_fingerprint(request));
                }
                if let Some(receipt) = &lease.receipt {
                    lease.receipt = Some(publication_receipt(receipt));
                }
                state.save_lease(&lease)?;
                Ok(lease)
            })();
            match loaded {
                Ok(lease) => {
                    state.leases.insert(id, lease);
                }
                Err(_) => state.uncertain = true,
            }
        }
        let interrupted: Vec<_> = state
            .batches
            .values()
            .filter(|b| b.status == "importing")
            .map(|b| b.id.clone())
            .collect();
        for id in interrupted {
            if state.leases.values().any(|lease| lease.share_id == id) {
                state.uncertain = true;
                continue;
            }
            state.fail(&id, "上次分享导入已中断，请重新分享。")?;
        }
        Ok(state)
    }
    fn load_batch(&self, id: &str) -> CoreResult<Batch> {
        if !valid_id(id) {
            return Err(bad("分享标识无效。"));
        }
        let path = self.root.join(id).join(".share");
        let bytes = bounded_read(&path, 8 * 1024 * 1024)?;
        let mut batch: Batch = if bytes.first() == Some(&b'{') {
            serde_json::from_slice(&bytes)?
        } else {
            let p = legacy::properties(&path, 8 * 1024 * 1024)?;
            let count = p
                .get("count")
                .and_then(|s| s.parse::<usize>().ok())
                .ok_or_else(|| bad("分享文件记录无效。"))?;
            if count > self.limits.sources {
                return Err(bad("分享文件数超限。"));
            }
            let mut files = Vec::new();
            for index in 0..count {
                files.push(SharedFile {
                    disk_name: p
                        .get(&format!("file.{index}.disk"))
                        .cloned()
                        .ok_or_else(|| bad("分享磁盘记录缺失。"))?,
                    name: p
                        .get(&format!("file.{index}.name"))
                        .cloned()
                        .ok_or_else(|| bad("分享文件名记录缺失。"))?,
                    size: 0,
                });
            }
            Batch {
                version: 2,
                id: id.into(),
                created: p
                    .get("created")
                    .and_then(|s| s.parse().ok())
                    .ok_or_else(|| bad("分享时间记录无效。"))?,
                visible: p.get("visible").is_some_and(|s| s == "true"),
                status: p
                    .get("status")
                    .cloned()
                    .ok_or_else(|| bad("分享状态缺失。"))?,
                bytes: 0,
                text: p.get("text").cloned(),
                mime: p.get("mime").cloned(),
                files,
                errors: p.get("error").cloned().into_iter().collect(),
            }
        };
        if batch.version != 2 || batch.id != id || batch.files.len() > self.limits.sources {
            return Err(bad("分享记录版本或文件数无效。"));
        }
        let mut unique = BTreeSet::new();
        for file in &mut batch.files {
            if !safe_disk(&file.disk_name) || !unique.insert(file.disk_name.clone()) {
                return Err(bad("分享文件路径无效。"));
            }
            let metadata = fs::symlink_metadata(self.root.join(id).join(&file.disk_name))?;
            if !metadata.is_file() {
                return Err(bad("分享来源不是普通文件。"));
            }
            file.size = metadata.len();
        }
        batch.bytes = batch
            .files
            .iter()
            .fold(0u64, |total, f| total.saturating_add(f.size));
        self.save_batch(&batch)?;
        Ok(batch)
    }
    pub fn directory(&self, id: &str) -> CoreResult<PathBuf> {
        if !valid_id(id) {
            return Err(bad("分享标识无效。"));
        }
        Ok(self.root.join(id))
    }
    fn save_batch(&self, b: &Batch) -> CoreResult<()> {
        write_json(&self.root.join(&b.id).join(".share"), b)
    }
    fn save_lease(&self, l: &Lease) -> CoreResult<()> {
        write_json(&self.root.join(".leases").join(&l.id), l)
    }
    pub fn retained_bytes(&self) -> u64 {
        self.batches
            .values()
            .fold(self.unknown_bytes, |total, b| total.saturating_add(b.bytes))
    }
    pub fn reserve(
        &mut self,
        id: &str,
        text: Option<String>,
        mime: Option<String>,
    ) -> CoreResult<()> {
        if !valid_id(id) || self.batches.contains_key(id) {
            return Err(bad("分享标识无效或已存在。"));
        }
        if self.uncertain
            || self.batches.values().filter(|b| b.visible).count() >= self.limits.pending
            || self.batches.len() + self.unknown_batches >= self.limits.batches
            || self.retained_bytes() >= self.limits.total_bytes
        {
            return Err(CoreError::new(
                "share_cache_busy",
                "分享暂存已满或有待核对来源；已有任务不会被删除。",
            ));
        }
        if text.as_ref().is_some_and(|s| s.chars().count() > 1_048_576)
            || mime.as_ref().is_some_and(|s| s.len() > 256)
        {
            return Err(bad("分享文字或类型过长。"));
        }
        let batch = Batch {
            version: 2,
            id: id.into(),
            created: millis(),
            visible: true,
            status: "importing".into(),
            bytes: 0,
            text,
            mime,
            files: Vec::new(),
            errors: Vec::new(),
        };
        self.save_batch(&batch)?;
        self.batches.insert(id.into(), batch);
        Ok(())
    }
    pub fn append(&mut self, id: &str, count: u64) -> CoreResult<()> {
        let total = self.retained_bytes();
        let b = self
            .batches
            .get_mut(id)
            .ok_or_else(|| bad("分享导入已取消。"))?;
        if !b.visible || b.status != "importing" {
            return Err(CoreError::new("cancelled", "分享导入已取消。"));
        }
        if count > self.limits.batch_bytes.saturating_sub(b.bytes)
            || count > self.limits.total_bytes.saturating_sub(total)
        {
            return Err(CoreError::new(
                "share_byte_limit",
                "分享内容超过暂存容量，已停止导入。",
            ));
        }
        b.bytes += count;
        Ok(())
    }
    pub fn complete(&mut self, id: &str, files: Vec<SharedFile>) -> CoreResult<Option<Value>> {
        let Some(old) = self.batches.get(id) else {
            return Ok(None);
        };
        if !old.visible || old.status != "importing" {
            return Ok(None);
        }
        if files.len() > self.limits.sources || files.iter().any(|f| !safe_disk(&f.disk_name)) {
            return Err(bad("分享文件记录超限或无效。"));
        }
        let mut b = old.clone();
        b.status = "ready".into();
        b.files = files;
        self.save_batch(&b)?;
        let value = self.view(&b);
        self.batches.insert(id.into(), b);
        Ok(Some(value))
    }
    pub fn fail(&mut self, id: &str, message: &str) -> CoreResult<Option<Value>> {
        let Some(old) = self.batches.get(id) else {
            return Ok(None);
        };
        if old.status != "importing" {
            return Ok(None);
        }
        let mut b = old.clone();
        remove_children(&self.root.join(id), false)?;
        b.status = "error".into();
        b.bytes = 0;
        b.files.clear();
        b.errors = vec![message.chars().take(4096).collect()];
        self.save_batch(&b)?;
        let value = self.view(&b);
        self.batches.insert(id.into(), b);
        Ok(Some(value))
    }
    pub fn cleanup_aborted(&mut self, id: &str) -> CoreResult<()> {
        match self.batches.get(id) {
            None => {
                let path = self.directory(id)?;
                if path.exists() {
                    fs::remove_dir_all(path)?;
                }
            }
            Some(b) if b.status == "error" => remove_children(&self.directory(id)?, true)?,
            _ => {}
        }
        Ok(())
    }
    pub fn consume(&mut self, id: &str) -> CoreResult<()> {
        let Some(old) = self.batches.get(id) else {
            return Ok(());
        };
        let mut b = old.clone();
        b.visible = false;
        self.save_batch(&b)?;
        self.batches.insert(id.into(), b);
        self.reclaim(id)
    }
    fn reclaim(&mut self, id: &str) -> CoreResult<()> {
        if !self.uncertain
            && self.batches.get(id).is_some_and(|b| !b.visible)
            && !self.leases.values().any(|l| l.share_id == id)
        {
            let path = self.directory(id)?;
            if path.exists() {
                fs::remove_dir_all(path)?;
            }
            self.batches.remove(id);
        }
        Ok(())
    }
    pub fn retain(&mut self, id: &str) -> CoreResult<Value> {
        if let Some(lease) = self.leases.values().find(|l| l.share_id == id) {
            return Ok(self.lease_view(lease));
        }
        let b = self
            .batches
            .get(id)
            .ok_or_else(|| bad("分享来源已不存在。"))?;
        if b.status != "ready" || b.files.is_empty() {
            return Err(bad("分享文件尚未导入完成。"));
        }
        if self.leases.len() >= self.limits.leases {
            return Err(CoreError::new("share_cache_busy", "分享租约已满。"));
        }
        let l = Lease {
            version: 2,
            id: uuid::Uuid::new_v4().to_string(),
            share_id: id.into(),
            transfer_id: None,
            request: None,
            publication: None,
            receipt: None,
        };
        self.save_lease(&l)?;
        let result = self.lease_view(&l);
        self.leases.insert(l.id.clone(), l);
        Ok(result)
    }
    pub fn bind(&mut self, id: &str, transfer: &str) -> CoreResult<Value> {
        if !valid_id(transfer) {
            return Err(bad("传输标识无效。"));
        }
        let mut l = self
            .leases
            .get(id)
            .cloned()
            .ok_or_else(|| bad("分享租约不存在。"))?;
        if l.transfer_id.as_deref().is_some_and(|old| old != transfer) {
            return Err(CoreError::new(
                "share_submission_mismatch",
                "分享已属于另一批任务。",
            ));
        }
        l.transfer_id = Some(transfer.into());
        self.save_lease(&l)?;
        let result = self.lease_view(&l);
        self.leases.insert(id.into(), l);
        Ok(result)
    }
    pub fn release(&mut self, id: &str) -> CoreResult<()> {
        let Some(l) = self.leases.get(id).cloned() else {
            return Ok(());
        };
        let path = self.root.join(".leases").join(id);
        if path.exists() {
            fs::remove_file(path)?;
            sync_directory(&self.root.join(".leases"))?;
        }
        self.leases.remove(id);
        self.reclaim(&l.share_id)
    }
    pub fn paths(&self, b: &Batch) -> Vec<String> {
        b.files
            .iter()
            .map(|f| {
                self.root
                    .join(&b.id)
                    .join(&f.disk_name)
                    .to_string_lossy()
                    .into_owned()
            })
            .collect()
    }
    pub fn view(&self, b: &Batch) -> Value {
        json!({"shareId":b.id,"status":b.status,"text":b.text,"mime":b.mime,"files":b.files.iter().map(|f|json!({"name":f.name,"size":f.size,"localPath":self.root.join(&b.id).join(&f.disk_name)})).collect::<Vec<_>>(),"errors":b.errors})
    }
    fn lease_view(&self, l: &Lease) -> Value {
        json!({"leaseId":l.id,"shareId":l.share_id,"transferId":l.transfer_id,"status":if l.transfer_id.is_some(){"bound"}else{"unknown"},"files":self.batches.get(&l.share_id).map(|b|self.view(b)["files"].clone()),"publication":l.publication})
    }
    pub fn pending(&self) -> Value {
        json!({"shares":self.batches.values().filter(|b|b.visible).map(|b|self.view(b)).collect::<Vec<_>>()})
    }
    pub fn sources(&self) -> Value {
        json!({"sourcePaths":self.batches.values().flat_map(|b|self.paths(b)).collect::<Vec<_>>(),"leases":self.leases.values().map(|l|self.lease_view(l)).collect::<Vec<_>>(),"limits":{"references":self.limits.references,"sourcesPerReference":self.limits.paths_per_reference,"totalSourceEntries":self.limits.total_paths,"sourcePathChars":4096}})
    }
    fn snapshot(&self, reconciled: bool, complete: bool, reason: Option<&str>) -> Value {
        json!({"reconciled":reconciled,"snapshotComplete":complete,"reason":reason,"leases":self.leases.values().map(|l|self.lease_view(l)).collect::<Vec<_>>(),"retainedBytes":self.retained_bytes(),"unknownBytes":self.unknown_bytes,"unknownBatches":self.unknown_batches,"needsReview":self.uncertain})
    }
    pub fn reconcile(&mut self, input: &Value, complete: bool) -> CoreResult<Value> {
        let Some(rows) = input.as_array() else {
            return Ok(self.snapshot(false, false, Some("invalid_snapshot")));
        };
        if rows.len() > self.limits.references {
            return Ok(self.snapshot(false, false, Some("reference_limit")));
        }
        let mut count = 0usize;
        let mut valid = Vec::new();
        let mut verified = complete;
        for row in rows {
            let (Some(id), Some(status), Some(paths)) = (
                row["id"].as_str(),
                row["status"].as_str(),
                row["sources"].as_array(),
            ) else {
                return Ok(self.snapshot(false, false, Some("invalid_snapshot")));
            };
            if paths.len() > self.limits.paths_per_reference
                || paths.len() > self.limits.total_paths.saturating_sub(count)
            {
                return Ok(self.snapshot(false, false, Some("reference_limit")));
            }
            if id.len() > 128
                || status.len() > 64
                || paths.iter().any(|p| {
                    p.as_str()
                        .is_none_or(|s| s.len() > 16384 || s.chars().count() > 4096)
                })
            {
                return Ok(self.snapshot(false, false, Some("invalid_snapshot")));
            }
            count += paths.len();
            verified &= !paths.is_empty();
            valid.push((id, status, paths));
        }
        let ids: Vec<_> = self.leases.keys().cloned().collect();
        for id in ids {
            let l = self.leases[&id].clone();
            let Some(b) = self.batches.get(&l.share_id) else {
                continue;
            };
            let paths = self.paths(b);
            let matches: Vec<_> = valid
                .iter()
                .filter(|(_, _, p)| {
                    p.iter()
                        .any(|p| p.as_str().is_some_and(|p| paths.iter().any(|s| s == p)))
                })
                .collect();
            let transfer = l
                .transfer_id
                .clone()
                .or_else(|| (matches.len() == 1).then(|| matches[0].0.to_owned()));
            if let Some(transfer) = &transfer
                && l.transfer_id.is_none()
                && valid_id(transfer)
            {
                self.bind(&id, transfer)?;
            }
            if matches.len() == 1
                && l.request.is_some()
                && l.receipt.is_none()
                && paths
                    .iter()
                    .all(|source| matches[0].2.iter().any(|p| p.as_str() == Some(source)))
                && valid_id(matches[0].0)
            {
                self.publication_finished(
                    &l.share_id,
                    Some(
                        &json!({"batchId":matches[0].0,"status":"submitted","reusedTransfer":true}),
                    ),
                )?;
            }
            if verified
                && transfer.as_ref().is_some_and(|transfer| {
                    valid.iter().any(|(id, status, p)| {
                        id == transfer
                            && *status == "completed"
                            && paths
                                .iter()
                                .all(|source| p.iter().any(|p| p.as_str() == Some(source)))
                    })
                })
                && matches.iter().all(|(_, status, _)| *status == "completed")
            {
                self.release(&id)?;
            }
        }
        if verified {
            let expired: Vec<_> = self
                .batches
                .values()
                .filter(|b| {
                    millis().saturating_sub(b.created)
                        > self.limits.pending_expiry.as_millis() as u64
                        && b.status != "importing"
                        && !self.leases.values().any(|l| l.share_id == b.id)
                        && !self.paths(b).iter().any(|p| {
                            valid.iter().any(|(_, _, sources)| {
                                sources.iter().any(|s| s.as_str() == Some(p))
                            })
                        })
                })
                .map(|b| b.id.clone())
                .collect();
            for id in expired {
                self.consume(&id)?;
            }
        }
        Ok(self.snapshot(true, verified, (!verified).then_some("incomplete_snapshot")))
    }
    pub fn begin_publication(&mut self, share: &str, request: &Value) -> CoreResult<Option<Value>> {
        let b = self
            .batches
            .get(share)
            .ok_or_else(|| bad("分享来源已不存在。"))?;
        let allowed: BTreeSet<_> = self.paths(b).into_iter().collect();
        let Some(items) = request["items"].as_array() else {
            return Err(bad("请完整提交本次分享文件。"));
        };
        let requested: Option<BTreeSet<_>> = items
            .iter()
            .map(|i| i["source"].as_str().map(String::from))
            .collect();
        if allowed.is_empty()
            || items.len() != allowed.len()
            || requested.as_ref() != Some(&allowed)
        {
            return Err(bad("请完整提交本次已登记的分享文件。"));
        }
        self.retain(share)?;
        let mut l = self
            .leases
            .values()
            .find(|l| l.share_id == share)
            .cloned()
            .expect("retained");
        let fingerprint = request_fingerprint(request);
        if l.request.as_ref().is_some_and(|old| old != &fingerprint) {
            return Err(CoreError::new(
                "share_submission_mismatch",
                "本次分享已经提交了其他传输参数，请核对原任务。",
            ));
        }
        if let Some(receipt) = l.receipt {
            return Ok(Some(receipt));
        }
        if l.transfer_id.is_some() || l.publication.is_some() {
            let mut e = CoreError::new(
                "share_submission_unknown",
                "此分享已有任务或提交结果待核对，不会重复发布。",
            );
            e.details = json!({"batchId":l.transfer_id,"shareId":share,"sourceRetained":true});
            return Err(e);
        }
        l.request = Some(fingerprint);
        l.publication = Some("publishing".into());
        self.save_lease(&l)?;
        self.leases.insert(l.id.clone(), l);
        Ok(None)
    }
    pub fn publication_finished(&mut self, share: &str, receipt: Option<&Value>) -> CoreResult<()> {
        let Some(mut l) = self.leases.values().find(|l| l.share_id == share).cloned() else {
            return Err(bad("分享租约已不存在。"));
        };
        if let Some(receipt) = receipt {
            let id = receipt["batchId"]
                .as_str()
                .or_else(|| receipt["transferId"].as_str())
                .filter(|id| valid_id(id))
                .ok_or_else(|| bad("任务回执缺少有效批次标识。"))?;
            if l.transfer_id.as_deref().is_some_and(|old| old != id) {
                return Err(bad("分享任务回执与已有绑定不一致。"));
            }
            l.transfer_id = Some(id.into());
            l.receipt = Some(publication_receipt(receipt));
            l.publication = Some("published".into());
        } else {
            l.publication = Some("unknown".into());
        }
        self.save_lease(&l)?;
        self.leases.insert(l.id.clone(), l);
        Ok(())
    }
    pub fn publication_aborted(&mut self, share: &str) -> CoreResult<()> {
        let Some(mut lease) = self
            .leases
            .values()
            .find(|lease| lease.share_id == share)
            .cloned()
        else {
            return Ok(());
        };
        if lease.transfer_id.is_some() || lease.publication.as_deref() != Some("publishing") {
            return Err(CoreError::new(
                "share_submission_unknown",
                "已有提交仍待核对，不能重置。",
            ));
        }
        lease.request = None;
        lease.publication = None;
        self.save_lease(&lease)?;
        self.leases.insert(lease.id.clone(), lease);
        Ok(())
    }
}
fn publication_receipt(receipt: &Value) -> Value {
    // IDs are durable evidence. Full mutable task snapshots belong to the
    // transfer store, not to a second, potentially much larger lease journal.
    let mut compact = serde_json::Map::new();
    for key in ["batchId", "transferId", "transferIds", "status"] {
        if let Some(value) = receipt.get(key) {
            compact.insert(key.into(), value.clone());
        }
    }
    Value::Object(compact)
}
fn request_fingerprint(request: &Value) -> Value {
    fn sized(hasher: &mut Sha256, bytes: &[u8]) {
        hasher.update((bytes.len() as u64).to_be_bytes());
        hasher.update(bytes);
    }
    fn visit(hasher: &mut Sha256, value: &Value) {
        match value {
            Value::Null => hasher.update([0]),
            Value::Bool(value) => hasher.update([1, u8::from(*value)]),
            Value::Number(value) => {
                hasher.update([2]);
                sized(hasher, value.to_string().as_bytes());
            }
            Value::String(value) => {
                hasher.update([3]);
                sized(hasher, value.as_bytes());
            }
            Value::Array(values) => {
                hasher.update([4]);
                hasher.update((values.len() as u64).to_be_bytes());
                for value in values {
                    visit(hasher, value);
                }
            }
            Value::Object(values) => {
                hasher.update([5]);
                hasher.update((values.len() as u64).to_be_bytes());
                let ordered: BTreeMap<_, _> = values.iter().collect();
                for (key, value) in ordered {
                    sized(hasher, key.as_bytes());
                    visit(hasher, value);
                }
            }
        }
    }
    let mut hasher = Sha256::new();
    visit(&mut hasher, request);
    json!(format!("sha256:{}", hex::encode(hasher.finalize())))
}
fn bounded_read(path: &Path, limit: u64) -> CoreResult<Vec<u8>> {
    let meta = fs::symlink_metadata(path)?;
    if !meta.is_file() || meta.len() > limit {
        return Err(bad("分享来源记录类型或长度无效。"));
    }
    Ok(fs::read(path)?)
}
fn safe_disk(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && name != ".share"
        && name.len() <= 255
        && !name.contains(['/', '\\', '\0'])
}
fn write_json(path: &Path, value: &impl Serialize) -> CoreResult<()> {
    let parent = path.parent().ok_or_else(|| bad("分享记录路径无效。"))?;
    fs::create_dir_all(parent)?;
    let temp = parent.join(format!(".{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| {
        let mut options = fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut output = options.open(&temp)?;
        output.write_all(&serde_json::to_vec(value)?)?;
        output.sync_all()?;
        drop(output);
        fs::rename(&temp, path)?;
        sync_directory(parent)?;
        Ok(())
    })();
    if temp.exists() {
        let _ = fs::remove_file(temp);
    }
    result
}
fn sync_directory(path: &Path) -> CoreResult<()> {
    #[cfg(unix)]
    {
        fs::File::open(path)?.sync_all()?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}
fn remove_children(root: &Path, keep_journal: bool) -> CoreResult<()> {
    if !root.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if keep_journal && entry.file_name() == ".share" {
            continue;
        }
        if entry.file_type()?.is_dir() {
            fs::remove_dir_all(entry.path())?;
        } else {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}
