//! Durable admission for saves whose destination may outlive the UI or process.
use crate::{CoreError, CoreResult, Runtime, model::now};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};
use tokio::{fs, io::AsyncReadExt, sync::Mutex};

const MAX_RECORDS: usize = 1024;
const MAX_BYTES: usize = 4 * 1024 * 1024;
const MAX_OPERATIONS: usize = 16384;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Record {
    operation_id: String,
    source_id: String,
    local_path: String,
    kind: String,
    name: String,
    status: String,
    result: Value,
    updated_at: u64,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Ledger {
    version: u32,
    records: BTreeMap<String, Record>,
    operations: BTreeSet<String>,
}

pub(crate) struct DeliveryJournal {
    path: PathBuf,
    ledger: Mutex<Ledger>,
}

fn invalid(message: &str) -> CoreError {
    CoreError::new("invalid_argument", message)
}

fn text<'a>(params: &'a Value, field: &str, max: usize) -> CoreResult<&'a str> {
    params
        .get(field)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && s.len() <= max && !s.contains('\0'))
        .ok_or_else(|| invalid(&format!("缺少或无效的保存字段：{field}")))
}

fn key(params: &Value) -> CoreResult<String> {
    let source = text(params, "sourceId", 256)?;
    let path = text(params, "localPath", 4096)?;
    let kind = text(params, "kind", 32)?;
    if !matches!(kind, "file" | "directory") {
        return Err(invalid("保存类型无效。"));
    }
    Ok(serde_json::to_string(&(source, path, kind))?)
}

fn clean_result(input: &Value) -> CoreResult<Value> {
    if !input.is_object() {
        return Err(invalid("保存结果必须是对象。"));
    }
    let status = match input["status"].as_str() {
        Some("resultUnknown" | "result_unknown") => "result_unknown",
        Some(status @ ("saved" | "partial" | "failed" | "cancelled")) => status,
        _ => return Err(invalid("保存结果状态无效。")),
    };
    let mut result = json!({"status":status});
    if let Some(value) = input.get("name") {
        result["name"] = json!(
            value
                .as_str()
                .filter(|s| s.len() <= 1024 && !s.contains('\0'))
                .ok_or_else(|| invalid("保存结果名称无效。"))?
        );
    }
    for field in ["files", "directories", "bytes", "skipped"] {
        if let Some(value) = input.get(field) {
            result[field] = json!(
                value
                    .as_u64()
                    .ok_or_else(|| invalid("保存结果计数无效。"))?
            );
        }
    }
    for field in ["partialDestinationPossible", "cacheRetained"] {
        if let Some(value) = input.get(field) {
            result[field] = json!(
                value
                    .as_bool()
                    .ok_or_else(|| invalid("保存结果标记无效。"))?
            );
        }
    }
    if status == "result_unknown"
        || (status != "saved" && result.get("partialDestinationPossible").is_none())
    {
        result["partialDestinationPossible"] = json!(true);
    }
    if let Some(errors) = input.get("errors") {
        let errors = errors
            .as_array()
            .ok_or_else(|| invalid("保存错误明细无效。"))?;
        let mut clean = Vec::new();
        for error in errors.iter().take(100) {
            if !error.is_object() {
                return Err(invalid("保存错误明细必须是对象。"));
            }
            let mut item = json!({});
            for (field, limit) in [("path", 4096), ("code", 256), ("message", 4096)] {
                if let Some(value) = error.get(field) {
                    let value = value
                        .as_str()
                        .filter(|v| !v.contains('\0'))
                        .ok_or_else(|| invalid("保存错误字段无效。"))?;
                    let end = if value.len() <= limit {
                        value.len()
                    } else {
                        value
                            .char_indices()
                            .map(|(i, _)| i)
                            .take_while(|i| *i <= limit)
                            .last()
                            .unwrap_or(0)
                    };
                    item[field] = json!(&value[..end]);
                }
            }
            clean.push(item);
        }
        result["errors"] = json!(clean);
    }
    Ok(result)
}

impl DeliveryJournal {
    pub(crate) async fn protected_paths(&self) -> Vec<PathBuf> {
        self.ledger
            .lock()
            .await
            .records
            .values()
            .filter(|record| {
                matches!(record.status.as_str(), "pending" | "result_unknown")
                    || record.result["partialDestinationPossible"] == true
            })
            .map(|record| PathBuf::from(&record.local_path))
            .collect()
    }
    pub(crate) async fn open(root: &Path) -> CoreResult<Self> {
        let path = root.join("deliveries.json");
        let mut ledger = match fs::File::open(&path).await {
            Ok(file) => {
                let mut bytes = Vec::new();
                file.take((MAX_BYTES + 1) as u64)
                    .read_to_end(&mut bytes)
                    .await?;
                if bytes.len() > MAX_BYTES {
                    return Err(CoreError::new(
                        "delivery_storage_invalid",
                        "保存记录超出容量。",
                    ));
                }
                serde_json::from_slice::<Ledger>(&bytes)
                    .map_err(|_| CoreError::new("delivery_storage_invalid", "保存记录损坏。"))?
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ledger {
                version: 1,
                records: BTreeMap::new(),
                operations: BTreeSet::new(),
            },
            Err(e) => return Err(e.into()),
        };
        if ledger.version != 1
            || ledger.records.len() > MAX_RECORDS
            || ledger.operations.len() > MAX_OPERATIONS
            || ledger
                .operations
                .iter()
                .any(|op| op.is_empty() || op.len() > 256 || op.contains('\0'))
        {
            return Err(CoreError::new(
                "delivery_storage_invalid",
                "保存记录格式或容量无效。",
            ));
        }
        let mut changed = false;
        for (stored_key, record) in &mut ledger.records {
            let params = serde_json::to_value(&*record)?;
            if key(&params).as_ref().ok() != Some(stored_key)
                || text(&params, "operationId", 256).is_err()
                || text(&params, "name", 1024).is_err()
                || !ledger.operations.contains(&record.operation_id)
                || !matches!(
                    record.status.as_str(),
                    "pending" | "saved" | "partial" | "failed" | "cancelled" | "result_unknown"
                )
                || (record.status == "pending" && !record.result.is_null())
                || (record.status != "pending"
                    && (clean_result(&record.result).as_ref().ok() != Some(&record.result)
                        || record.result["status"] != record.status))
            {
                return Err(CoreError::new(
                    "delivery_storage_invalid",
                    "保存记录内容无效。",
                ));
            }
            if record.status == "pending" {
                record.status = "result_unknown".into();
                record.result = json!({"status":"result_unknown","partialDestinationPossible":true,"cacheRetained":true});
                record.updated_at = now();
                changed = true;
            }
        }
        if changed {
            Self::write(&path, &ledger).await?;
        }
        Ok(Self {
            path,
            ledger: Mutex::new(ledger),
        })
    }

    async fn write(path: &Path, ledger: &Ledger) -> CoreResult<()> {
        let bytes = serde_json::to_vec(ledger)?;
        // A pending receipt must still fit after crash recovery adds the
        // conservative unknown result. Preserve that room before admitting it.
        let recovery_reserve = ledger
            .records
            .values()
            .filter(|record| record.status == "pending")
            .count()
            * 256;
        if bytes.len() + recovery_reserve > MAX_BYTES {
            return Err(CoreError::new(
                "delivery_capacity",
                "保存记录已满，请保留当前缓存。",
            ));
        }
        Runtime::private_write(path, &bytes).await
    }

    pub(crate) async fn command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        let key = key(params)?;
        let mut ledger = self.ledger.lock().await;
        if command == "delivery.get" {
            return Ok(json!({"record":ledger.records.get(&key)}));
        }
        if command == "delivery.finish" {
            let operation = text(params, "operationId", 256)?;
            let previous = ledger
                .records
                .get(&key)
                .ok_or_else(|| CoreError::new("delivery_not_found", "找不到本次保存记录。"))?;
            if previous.operation_id != operation {
                return Err(CoreError::new(
                    "delivery_operation_mismatch",
                    "保存回执不属于当前操作。",
                ));
            }
            let result = clean_result(&params["result"])?;
            if previous.status != "pending" {
                if previous.result == result {
                    return Ok(json!({"record":previous}));
                }
                return Err(CoreError::new(
                    "delivery_result_conflict",
                    "已有保存终态，请核对目标内容。",
                ));
            }
            let mut record = previous.clone();
            record.status = result["status"].as_str().unwrap().into();
            record.result = result;
            record.updated_at = now();
            let mut next = ledger.clone();
            next.records.insert(key, record.clone());
            Self::write(&self.path, &next).await?;
            *ledger = next;
            return Ok(json!({"record":record}));
        }
        if command != "delivery.begin" {
            return Err(CoreError::new("unknown_command", "未知保存操作。"));
        }
        let record = Record {
            operation_id: text(params, "operationId", 256)?.into(),
            source_id: text(params, "sourceId", 256)?.into(),
            local_path: text(params, "localPath", 4096)?.into(),
            kind: text(params, "kind", 32)?.into(),
            name: text(params, "name", 1024)?.into(),
            status: "pending".into(),
            result: Value::Null,
            updated_at: now(),
        };
        if let Some(previous) = ledger.records.get(&key) {
            if previous.status == "pending" {
                return Err(CoreError::new(
                    "delivery_busy",
                    "此内容正在保存，请等待结果。",
                ));
            }
            if previous.status == "saved"
                && params["additionalCopyOfOperationId"].as_str()
                    != Some(previous.operation_id.as_str())
            {
                return Err(CoreError::new("delivery_saved", "此内容已经保存。"));
            }
            if (previous.status == "result_unknown"
                || previous.result["partialDestinationPossible"] == true)
                && params["reviewedOperationId"].as_str() != Some(previous.operation_id.as_str())
            {
                return Err(CoreError::new(
                    "delivery_review_required",
                    "请先核对上次目标，再明确重新保存。",
                ));
            }
        }
        if ledger.operations.contains(&record.operation_id) {
            return Err(CoreError::new(
                "delivery_operation_reused",
                "重新保存需要新的操作标识。",
            ));
        }
        if !ledger.records.contains_key(&key) && ledger.records.len() >= MAX_RECORDS {
            return Err(CoreError::new(
                "delivery_capacity",
                "保存记录已满，请保留当前缓存。",
            ));
        }
        if ledger.operations.len() >= MAX_OPERATIONS {
            return Err(CoreError::new(
                "delivery_capacity",
                "保存操作记录已满，请保留当前缓存。",
            ));
        }
        let mut next = ledger.clone();
        next.operations.insert(record.operation_id.clone());
        next.records.insert(key, record.clone());
        Self::write(&self.path, &next).await?;
        *ledger = next;
        Ok(json!({"record":record}))
    }
}
