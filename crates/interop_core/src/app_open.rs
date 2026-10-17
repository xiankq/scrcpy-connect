//! Side-effect evidence survives capture cleanup and Runtime reconstruction.
use crate::{CoreError, CoreResult, Runtime, model::now};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU8, Ordering},
    },
};
use tokio::{fs, io::AsyncReadExt, sync::Mutex};
use tokio_util::sync::CancellationToken;

const MAX_RECORDS: usize = 1024;
const MAX_BYTES: usize = 2 * 1024 * 1024;

// Admission is separate from the durable result. Closing a queued intent must
// prevent a later actor wake-up from submitting it to the phone.
#[derive(Clone, Default)]
pub(crate) struct LaunchPermit {
    phase: Arc<AtomicU8>,
    cancellation: CancellationToken,
}
impl LaunchPermit {
    pub(crate) fn claim(&self) -> bool {
        self.phase
            .compare_exchange(0, 1, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
    }
    pub(crate) fn cancel(&self) {
        let _ = self
            .phase
            .compare_exchange(0, 3, Ordering::SeqCst, Ordering::SeqCst);
        self.cancellation.cancel();
    }
    pub(crate) fn complete(&self) {
        self.phase.store(2, Ordering::SeqCst);
    }
    pub(crate) async fn cancelled(&self) {
        self.cancellation.cancelled().await;
    }
    pub(crate) fn is_cancelled(&self) -> bool {
        self.cancellation.is_cancelled()
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Record {
    operation_id: String,
    session_id: String,
    device_id: String,
    package_name: String,
    status: String,
    failure_code: Option<String>,
    updated_at: u64,
    #[serde(skip)]
    permit: LaunchPermit,
}

impl Record {
    fn unresolved(&self) -> bool {
        matches!(self.status.as_str(), "pending" | "unknown")
    }

    fn projection(&self) -> Value {
        json!({"sessionId":self.operation_id,"launchOperationId":self.operation_id,
            "linkedSessionId": if self.operation_id != self.session_id { Some(&self.session_id) } else { None },
            "deviceId":self.device_id,"packageName":self.package_name,"name":self.package_name,
            "status":"failed","kind":"app","launchOutcome":"unknown","recordOnly":true,
            "failureCode":self.failure_code,"reason":"应用打开请求可能已提交。请先核对手机并明确关闭本次记录，再选择重新打开。"})
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Ledger {
    version: u32,
    records: BTreeMap<String, Record>,
}

pub(crate) struct AppOpens {
    path: PathBuf,
    ledger: Mutex<Ledger>,
}

pub(crate) fn unknown(record: Value) -> CoreError {
    let mut error = CoreError::new(
        "app_launch_unknown",
        "应用打开结果尚待核对，不会再次提交打开请求。请先核对手机并明确关闭本次记录。",
    );
    error.details = record;
    error
}

impl AppOpens {
    pub(crate) async fn open(root: &Path) -> CoreResult<Self> {
        let path = root.join("app-opens.json");
        let mut ledger = match fs::File::open(&path).await {
            Ok(file) => {
                let mut bytes = Vec::new();
                file.take((MAX_BYTES + 1) as u64)
                    .read_to_end(&mut bytes)
                    .await?;
                if bytes.len() > MAX_BYTES {
                    return Err(CoreError::new(
                        "app_open_storage_invalid",
                        "应用打开记录超出容量。",
                    ));
                }
                serde_json::from_slice::<Ledger>(&bytes).map_err(|_| {
                    CoreError::new(
                        "app_open_storage_invalid",
                        "应用打开记录损坏，请保留本机记录。",
                    )
                })?
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ledger {
                version: 1,
                records: BTreeMap::new(),
            },
            Err(error) => return Err(error.into()),
        };
        if ledger.version != 1 || ledger.records.len() > MAX_RECORDS {
            return Err(CoreError::new(
                "app_open_storage_invalid",
                "应用打开记录格式或容量无效。",
            ));
        }
        let mut changed = false;
        for (id, record) in &mut ledger.records {
            if id != &record.operation_id
                || uuid::Uuid::parse_str(id).is_err()
                || uuid::Uuid::parse_str(&record.session_id).is_err()
                || record.device_id.is_empty()
                || record.device_id.len() > 256
                || record.device_id.contains('\0')
                || crate::scrcpy::package_name(&record.package_name).is_err()
                || !matches!(
                    record.status.as_str(),
                    "pending" | "unknown" | "observed" | "closed"
                )
                || record
                    .failure_code
                    .as_ref()
                    .is_some_and(|code| code.len() > 128 || code.contains('\0'))
            {
                return Err(CoreError::new(
                    "app_open_storage_invalid",
                    "应用打开记录内容无效。",
                ));
            }
            // Lost presentation ownership never establishes the remote task's
            // current state. Recovery must inspect it instead of relaunching.
            // No native handles, media tokens or process IDs are restored.
            if matches!(record.status.as_str(), "pending" | "observed") {
                record.status = "unknown".into();
                record.failure_code = Some("interrupted".into());
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
        if bytes.len() > MAX_BYTES {
            return Err(CoreError::new(
                "app_open_capacity",
                "应用打开记录已满，请先核对并关闭待处理记录。",
            ));
        }
        Runtime::private_write(path, &bytes).await
    }

    pub(crate) async fn ensure_available(&self, device: &str, package: &str) -> CoreResult<()> {
        let ledger = self.ledger.lock().await;
        if let Some(record) = ledger.records.values().find(|record| {
            record.device_id == device && record.package_name == package && record.unresolved()
        }) {
            return Err(unknown(record.projection()));
        }
        Ok(())
    }

    pub(crate) async fn begin(
        &self,
        operation: &str,
        session: &str,
        device: &str,
        package: &str,
    ) -> CoreResult<LaunchPermit> {
        let mut ledger = self.ledger.lock().await;
        if let Some(record) = ledger.records.values().find(|record| {
            record.device_id == device && record.package_name == package && record.unresolved()
        }) {
            return Err(unknown(record.projection()));
        }
        if ledger.records.contains_key(operation) {
            return Err(CoreError::new(
                "app_open_conflict",
                "这次打开意图已经处理。",
            ));
        }
        let mut next = ledger.clone();
        if next.records.len() >= MAX_RECORDS {
            let oldest = next
                .records
                .iter()
                .filter(|(_, record)| record.status == "closed")
                .min_by_key(|(_, record)| record.updated_at)
                .map(|(id, _)| id.clone());
            if let Some(id) = oldest {
                next.records.remove(&id);
            } else {
                return Err(CoreError::new(
                    "app_open_capacity",
                    "应用打开记录已满，请先核对并关闭待处理记录。",
                ));
            }
        }
        let permit = LaunchPermit::default();
        next.records.insert(
            operation.into(),
            Record {
                operation_id: operation.into(),
                session_id: session.into(),
                device_id: device.into(),
                package_name: package.into(),
                status: "pending".into(),
                failure_code: None,
                updated_at: now(),
                permit: permit.clone(),
            },
        );
        Self::write(&self.path, &next).await?;
        *ledger = next;
        Ok(permit)
    }

    pub(crate) async fn finish(&self, operation: &str, failure: Option<&str>) -> CoreResult<()> {
        let mut ledger = self.ledger.lock().await;
        let previous = ledger
            .records
            .get(operation)
            .ok_or_else(|| CoreError::new("app_open_not_found", "找不到这次应用打开记录。"))?;
        if previous.status == "closed" || (previous.status == "unknown" && failure.is_none()) {
            return Err(CoreError::new(
                "cancelled",
                "这次应用打开已关闭或需要核对，不接受迟到结果。",
            ));
        }
        if failure.is_some() {
            previous.permit.cancel();
        }
        let mut next = ledger.clone();
        let record = next
            .records
            .get_mut(operation)
            .expect("validated operation");
        record.status = if failure.is_some() {
            "unknown"
        } else if record.operation_id != record.session_id {
            "closed"
        } else {
            "observed"
        }
        .into();
        record.failure_code = failure.map(str::to_owned);
        record.updated_at = now();
        let persisted = Self::write(&self.path, &next).await;
        // A local storage error cannot make an uncertain side effect replayable
        // in this Runtime. The earlier durable pending/observed entry is also
        // restored as unknown after restart.
        if persisted.is_ok() || failure.is_some() {
            *ledger = next;
        }
        persisted
    }

    pub(crate) async fn close(&self, operation: &str, device: Option<&str>) -> CoreResult<bool> {
        let mut ledger = self.ledger.lock().await;
        let Some(previous) = ledger.records.get(operation) else {
            return Ok(false);
        };
        if device.is_some_and(|device| previous.device_id != device) {
            return Err(CoreError::new(
                "invalid_argument",
                "应用打开记录不属于所选设备。",
            ));
        }
        if previous.status == "closed" {
            return Ok(true);
        }
        previous.permit.cancel();
        let mut next = ledger.clone();
        let record = next
            .records
            .get_mut(operation)
            .expect("validated operation");
        record.status = "closed".into();
        record.updated_at = now();
        Self::write(&self.path, &next).await?;
        *ledger = next;
        Ok(true)
    }

    pub(crate) async fn unresolved(&self, device: Option<&str>) -> Vec<Value> {
        self.ledger
            .lock()
            .await
            .records
            .values()
            .filter(|record| {
                record.unresolved() && device.is_none_or(|device| record.device_id == device)
            })
            .map(Record::projection)
            .collect()
    }
}
