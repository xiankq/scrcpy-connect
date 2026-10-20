//! Durable transfer state. A checkpoint anchors ordered task deltas; committing
//! one file never requires encoding or rewriting every retained transfer.
use crate::{CoreError, CoreResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};
use tokio::{fs, io::AsyncWriteExt};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Checkpoint {
    version: u32,
    sequence: u64,
    transfers: Vec<Value>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Delta {
    version: u32,
    sequence: u64,
    upserts: HashMap<String, Value>,
    removed: Vec<String>,
}

pub(crate) struct TransferStore {
    root: PathBuf,
    tasks: HashMap<String, Value>,
    sequence: u64,
    checkpoint_present: bool,
    checkpoint_bytes: usize,
    journal_present: bool,
    journal_bytes: usize,
    journal_records: usize,
    obsolete_journal: bool,
    poisoned: bool,
}

fn corrupt(message: impl Into<String>) -> CoreError {
    CoreError::new("transfer_storage_corrupt", message)
}

impl TransferStore {
    pub(crate) fn open(root: &Path) -> CoreResult<Self> {
        let mut store = Self {
            root: root.to_owned(),
            tasks: HashMap::new(),
            sequence: 0,
            checkpoint_present: false,
            checkpoint_bytes: 0,
            journal_present: false,
            journal_bytes: 0,
            journal_records: 0,
            obsolete_journal: false,
            poisoned: false,
        };
        match std::fs::read(root.join("transfers.json")) {
            Ok(bytes) => {
                store.checkpoint_bytes = bytes.len();
                let value: Value = serde_json::from_slice(&bytes)?;
                let tasks = if value.is_array() {
                    serde_json::from_value::<Vec<Value>>(value)?
                } else {
                    let checkpoint: Checkpoint = serde_json::from_value(value)?;
                    if checkpoint.version != 1 {
                        return Err(corrupt("传输存储版本不受支持。"));
                    }
                    store.sequence = checkpoint.sequence;
                    store.checkpoint_present = true;
                    checkpoint.transfers
                };
                for task in tasks {
                    let id = task["id"]
                        .as_str()
                        .filter(|id| !id.is_empty())
                        .ok_or_else(|| corrupt("传输记录缺少身份。"))?
                        .to_owned();
                    if store.tasks.insert(id, task).is_some() {
                        return Err(corrupt("传输记录身份重复。"));
                    }
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        let checkpoint_sequence = store.sequence;
        match std::fs::read(root.join("transfers.journal")) {
            Ok(bytes) => {
                store.journal_present = true;
                store.journal_bytes = bytes.len();
                if !bytes.is_empty() && !store.checkpoint_present {
                    return Err(corrupt("传输日志缺少对应检查点，无法确认保存结果。"));
                }
                if !bytes.is_empty() && bytes.last() != Some(&b'\n') {
                    return Err(corrupt("传输日志尾部不完整，无法确认最后的保存结果。"));
                }
                let mut previous_sequence = None;
                for line in bytes.split_inclusive(|byte| *byte == b'\n') {
                    store.journal_records += 1;
                    let line = &line[..line.len() - 1];
                    let delta: Delta = serde_json::from_slice(line)
                        .map_err(|_| corrupt("传输日志损坏，保存结果需要核对。"))?;
                    if delta.version != 1 {
                        return Err(corrupt("传输日志版本不受支持。"));
                    }
                    if delta.sequence == 0
                        || previous_sequence.is_some_and(|previous: u64| {
                            previous.checked_add(1) != Some(delta.sequence)
                        })
                    {
                        return Err(corrupt("传输日志序号重复或不连续。"));
                    }
                    previous_sequence = Some(delta.sequence);
                    if delta.sequence <= checkpoint_sequence {
                        continue;
                    }
                    if delta.sequence
                        != store
                            .sequence
                            .checked_add(1)
                            .ok_or_else(|| corrupt("传输日志序号溢出。"))?
                    {
                        return Err(corrupt("传输日志序号不连续，无法确认保存结果。"));
                    }
                    for (id, task) in delta.upserts {
                        if task["id"].as_str() != Some(id.as_str()) {
                            return Err(corrupt("传输日志身份不一致。"));
                        }
                        store.check_generation(&id, &task)?;
                        store.tasks.insert(id, task);
                    }
                    for id in delta.removed {
                        store.tasks.remove(&id);
                    }
                    store.sequence = delta.sequence;
                }
                store.obsolete_journal =
                    previous_sequence.is_some_and(|last| last < checkpoint_sequence);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        Ok(store)
    }

    pub(crate) fn snapshot(&self) -> Vec<Value> {
        self.tasks.values().cloned().collect()
    }

    fn check_generation(&self, id: &str, task: &Value) -> CoreResult<()> {
        let generation = |task: &Value| -> CoreResult<u64> {
            match task.get("generation") {
                None => Ok(0),
                Some(value) => value.as_u64().ok_or_else(|| corrupt("传输尝试代际无效。")),
            }
        };
        let incoming = generation(task)?;
        if let Some(saved) = self.tasks.get(id)
            && generation(saved)? > incoming
        {
            return Err(corrupt("旧传输尝试不能覆盖较新的保存结果。"));
        }
        Ok(())
    }

    pub(crate) async fn persist_one<T: Serialize>(&mut self, id: &str, task: &T) -> CoreResult<()> {
        self.persist_selected(std::iter::once((id, task))).await
    }

    pub(crate) async fn persist_selected<'a, T: Serialize + 'a>(
        &mut self,
        tasks: impl IntoIterator<Item = (&'a str, &'a T)>,
    ) -> CoreResult<()> {
        let mut upserts = HashMap::new();
        for (id, task) in tasks {
            let value = serde_json::to_value(task)?;
            if value["id"].as_str() != Some(id) {
                return Err(corrupt("传输记录身份不一致。"));
            }
            self.check_generation(id, &value)?;
            if self.tasks.get(id) != Some(&value) {
                upserts.insert(id.to_owned(), value);
            }
        }
        self.persist_delta(upserts, Vec::new()).await
    }

    pub(crate) async fn persist_all<T: Serialize>(
        &mut self,
        tasks: &HashMap<String, T>,
    ) -> CoreResult<()> {
        let mut upserts = HashMap::new();
        for (id, task) in tasks {
            let value = serde_json::to_value(task)?;
            if value["id"].as_str() != Some(id.as_str()) {
                return Err(corrupt("传输记录身份不一致。"));
            }
            self.check_generation(id, &value)?;
            if self.tasks.get(id) != Some(&value) {
                upserts.insert(id.clone(), value);
            }
        }
        let removed = self
            .tasks
            .keys()
            .filter(|id| !tasks.contains_key(*id))
            .cloned()
            .collect();
        self.persist_delta(upserts, removed).await
    }

    pub(crate) async fn remove(&mut self, ids: Vec<String>) -> CoreResult<()> {
        self.persist_delta(HashMap::new(), ids).await
    }

    async fn persist_delta(
        &mut self,
        upserts: HashMap<String, Value>,
        removed: Vec<String>,
    ) -> CoreResult<()> {
        if self.poisoned {
            return Err(corrupt("上次传输持久化未完成，请重新启动并核对保存结果。"));
        }
        // Reject a blocked destination before touching the log, so fixing a
        // filesystem permission/path problem can safely retry this instance.
        match fs::symlink_metadata(self.root.join("transfers.json")).await {
            Ok(metadata) if !metadata.file_type().is_file() => {
                return Err(CoreError::new(
                    "persistence_failed",
                    "传输检查点路径不是普通文件。",
                ));
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.checkpoint_present = false
            }
            Err(error) => return Err(error.into()),
        }
        if !self.checkpoint_present {
            self.checkpoint().await?;
        }
        self.compact_if_needed().await?;
        if upserts.is_empty() && removed.is_empty() {
            return Ok(());
        }
        let sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| corrupt("传输日志序号溢出。"))?;
        let delta = Delta {
            version: 1,
            sequence,
            upserts,
            removed,
        };
        let mut bytes = serde_json::to_vec(&delta)?;
        bytes.push(b'\n');
        // Any cancelled or failed append leaves this instance unusable. A
        // later writer must not append behind an uncertain partial record.
        self.poisoned = true;
        let mut options = fs::OpenOptions::new();
        options.append(true);
        if !self.journal_present {
            options.create_new(true);
        }
        #[cfg(unix)]
        {
            options.mode(0o600);
        }
        let mut output = options.open(self.root.join("transfers.journal")).await?;
        output.write_all(&bytes).await?;
        output.sync_all().await?;
        if !self.journal_present {
            self.sync_directory().await?;
        }
        for (id, task) in delta.upserts {
            self.tasks.insert(id, task);
        }
        for id in delta.removed {
            self.tasks.remove(&id);
        }
        self.sequence = sequence;
        self.journal_present = true;
        self.journal_bytes = self.journal_bytes.saturating_add(bytes.len());
        self.journal_records = self.journal_records.saturating_add(1);
        self.poisoned = false;
        self.compact_if_needed().await
    }

    async fn compact_if_needed(&mut self) -> CoreResult<()> {
        // Scale thresholds with retained state so a growing batch does not
        // repeatedly rewrite its whole prefix at a fixed per-file interval.
        let record_limit = 256.max(self.tasks.len().saturating_mul(2));
        let byte_limit = (1024 * 1024).max(self.checkpoint_bytes.saturating_mul(2));
        if !self.obsolete_journal
            && self.journal_records < record_limit
            && self.journal_bytes < byte_limit
        {
            return Ok(());
        }
        self.poisoned = true;
        // Install+sync the new sequence anchor before truncating old deltas.
        // A crash between these steps leaves an old log that replay skips.
        self.checkpoint().await?;
        let output = fs::OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(self.root.join("transfers.journal"))
            .await?;
        output.sync_all().await?;
        self.journal_bytes = 0;
        self.journal_records = 0;
        self.obsolete_journal = false;
        self.poisoned = false;
        Ok(())
    }

    async fn checkpoint(&mut self) -> CoreResult<()> {
        let checkpoint = Checkpoint {
            version: 1,
            sequence: self.sequence,
            transfers: self.snapshot(),
        };
        let bytes = serde_json::to_vec(&checkpoint)?;
        let temporary = self
            .root
            .join(format!("transfers-{}.tmp", uuid::Uuid::new_v4()));
        let mut options = fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            options.mode(0o600);
        }
        let result: CoreResult<()> = async {
            let mut output = options.open(&temporary).await?;
            output.write_all(&bytes).await?;
            output.sync_all().await?;
            drop(output);
            fs::rename(&temporary, self.root.join("transfers.json")).await?;
            Ok(())
        }
        .await;
        if result.is_err() {
            let _ = fs::remove_file(&temporary).await;
        }
        result?;
        self.sync_directory().await?;
        self.checkpoint_present = true;
        self.checkpoint_bytes = bytes.len();
        Ok(())
    }

    async fn sync_directory(&self) -> CoreResult<()> {
        #[cfg(unix)]
        {
            let root = self.root.clone();
            tokio::task::spawn_blocking(move || std::fs::File::open(root)?.sync_all())
                .await
                .map_err(|error| CoreError::new("persistence_failed", error.to_string()))??;
        }
        Ok(())
    }
}
