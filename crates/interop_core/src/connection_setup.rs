//! Bounded native execution leases. Retry decisions belong to the Dart caller.
use crate::{CoreError, CoreResult, Runtime, device::Metadata};
use interop_adb::Client;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex as StdMutex},
    time::{Duration, Instant},
};
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

pub(crate) enum PendingResource {
    None,
    Pairing(crate::device::PairingDiscovery),
    Usb {
        client: Option<Client>,
        info: Metadata,
    },
    Tcpip {
        serial: String,
        port: u16,
    },
}

impl Drop for PendingResource {
    fn drop(&mut self) {
        if let Self::Usb {
            client: Some(client),
            ..
        } = self
        {
            client.close();
        }
    }
}

pub(crate) struct SetupOperation {
    pub(crate) id: String,
    pub(crate) attempt_id: String,
    pub(crate) device: StdMutex<Option<String>>,
    pub(crate) identity: String,
    pub(crate) dedicated_identity: tokio::sync::OnceCell<Arc<crate::host_identity::Material>>,
    selected_device: Option<String>,
    pub(crate) token: CancellationToken,
    pub(crate) execution: Mutex<()>,
    pub(crate) resource: StdMutex<PendingResource>,
    outcome: StdMutex<Value>,
    deadline: Instant,
    expires_at: u64,
}
impl SetupOperation {
    pub(crate) fn check(&self) -> CoreResult<()> {
        if self.token.is_cancelled() || Instant::now() >= self.deadline {
            self.cancel();
            Err(CoreError::new("cancelled", "连接执行租约已结束。"))
        } else {
            Ok(())
        }
    }
    pub(crate) fn reauthorizing(&self) -> bool {
        self.selected_device.is_some()
    }
    pub(crate) fn device_id(&self) -> Option<String> {
        self.device
            .lock()
            .expect("operation device poisoned")
            .clone()
    }
    pub(crate) fn cancel(&self) {
        self.token.cancel();
        *self.resource.lock().expect("operation resource poisoned") = PendingResource::None;
    }
    fn projection(&self) -> Value {
        json!({"operationId":self.id,"attemptId":self.attempt_id,"deviceId":self.device_id(),
            "expiresAt":self.expires_at,"cancelled":self.token.is_cancelled(),
            "outcome":self.outcome.lock().expect("operation outcome poisoned").clone()})
    }
}
impl Drop for SetupOperation {
    fn drop(&mut self) {
        self.token.cancel();
    }
}

#[derive(Default)]
pub(crate) struct SetupOperations {
    entries: Mutex<HashMap<String, Arc<SetupOperation>>>,
}
impl SetupOperations {
    pub(crate) async fn get(&self, id: &str) -> CoreResult<Arc<SetupOperation>> {
        let entries = self.entries.lock().await;
        let operation = entries
            .get(id)
            .or_else(|| entries.values().find(|op| op.attempt_id == id))
            .cloned()
            .ok_or_else(|| CoreError::new("operation_expired", "连接执行租约已释放。"))?;
        operation.check()?;
        Ok(operation)
    }
    pub(crate) async fn release_alias(&self, alias: &str) {
        let mut entries = self.entries.lock().await;
        entries.retain(|id, op| {
            let remove =
                id == alias || op.attempt_id == alias || op.device_id().as_deref() == Some(alias);
            if remove {
                op.cancel();
            }
            !remove
        });
    }
    pub(crate) async fn release_all(&self) {
        for (_, op) in self.entries.lock().await.drain() {
            op.cancel();
        }
    }
    pub(crate) async fn invalidate_devices(&self, affected: &[String], global: bool) {
        let mut entries = self.entries.lock().await;
        entries.retain(|_, op| {
            let id = op.device_id();
            let remove = id.as_ref().is_some_and(|id| affected.contains(id))
                || (global
                    && op.selected_device.is_none()
                    && op.dedicated_identity.get().is_none());
            if remove {
                op.cancel();
            }
            !remove
        });
    }
    pub(crate) async fn snapshot(&self) -> Vec<Value> {
        self.entries
            .lock()
            .await
            .values()
            .filter(|op| !op.token.is_cancelled() && Instant::now() < op.deadline)
            .map(|op| op.projection())
            .collect()
    }
}

impl Runtime {
    pub(crate) async fn new_setup_operation(
        &self,
        params: &Value,
        device: Option<&str>,
        identity: String,
    ) -> CoreResult<Arc<SetupOperation>> {
        let attempt_id = crate::model::required(params, "attemptId")?;
        if attempt_id.len() > 200
            || self
                .store
                .read()
                .await
                .devices
                .iter()
                .any(|d| d.id == attempt_id)
        {
            return Err(CoreError::new("invalid_argument", "执行尝试标识无效。"));
        }
        let lease_ms = params["leaseMs"]
            .as_u64()
            .filter(|ms| (1..=86_400_000).contains(ms))
            .ok_or_else(|| CoreError::new("invalid_argument", "执行租约必须介于1毫秒和一天。"))?;
        let token = CancellationToken::new();
        let op = Arc::new(SetupOperation {
            id: uuid::Uuid::new_v4().to_string(),
            attempt_id: attempt_id.into(),
            device: StdMutex::new(device.map(str::to_owned)),
            selected_device: device.map(str::to_owned),
            identity,
            dedicated_identity: tokio::sync::OnceCell::new(),
            token: token.clone(),
            execution: Mutex::new(()),
            resource: StdMutex::new(PendingResource::None),
            outcome: StdMutex::new(json!({"status":"waiting"})),
            deadline: Instant::now() + Duration::from_millis(lease_ms),
            expires_at: crate::model::now() + lease_ms.div_ceil(1000),
        });
        {
            let mut entries = self.setup_operations.entries.lock().await;
            entries.retain(|_, old| old.check().is_ok());
            if entries.len() >= 64 || entries.values().any(|old| old.attempt_id == attempt_id) {
                return Err(CoreError::new(
                    "operation_limit",
                    "执行租约已存在或已达到容量上限。",
                ));
            }
            entries.insert(op.id.clone(), op.clone());
        }
        {
            let mut pending = self.device_operations.lock().await;
            pending.retain(|_, token| !token.is_cancelled());
            if let Some(old) = pending.insert(attempt_id.into(), token.clone()) {
                old.cancel();
            }
            if let Some(id) = device
                && let Some(old) = pending.insert(id.into(), token.clone())
            {
                old.cancel();
            }
        }
        let weak = Arc::downgrade(&op);
        tokio::spawn(async move {
            tokio::select! { _ = token.cancelled() => {}, _ = tokio::time::sleep(Duration::from_millis(lease_ms)) => {} }
            if let Some(op) = weak.upgrade() {
                op.cancel();
            }
        });
        Ok(op)
    }
    pub(crate) fn setup_outcome(&self, op: &SetupOperation, result: &CoreResult<Value>) {
        let outcome = match result {
            Ok(value) => json!({"status":"completed","result":value}),
            Err(error) => json!({"status":"failed","code":error.code,"message":error.message}),
        };
        *op.outcome.lock().expect("operation outcome poisoned") = outcome;
        self.emit(
            "adb.operation.changed",
            op.device_id().as_deref(),
            op.projection(),
        );
    }
    pub(crate) async fn adb_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        match command {
            "adb.pair" => self.pair_device(params).await,
            "adb.pair.qr" => self.qr_pairing(params).await,
            "adb.usb.open" => self.usb_open(params).await,
            "adb.usb.attach" => self.usb_attach(params).await,
            "adb.tcpip.begin" => self.tcpip_begin(params).await,
            "adb.tcpip.connect" => self.tcpip_connect(params).await,
            "adb.device.probe" => self.device_probe(params).await,
            "adb.operation.get" => Ok(self
                .setup_operations
                .get(crate::model::required(params, "operationId")?)
                .await?
                .projection()),
            "adb.operation.release" => {
                let id = crate::model::required(params, "operationId")?;
                let token = self
                    .setup_operations
                    .get(id)
                    .await
                    .ok()
                    .map(|op| op.token.clone());
                self.setup_operations.release_alias(id).await;
                if let Some(token) = token {
                    self.device_operations
                        .lock()
                        .await
                        .retain(|_, current| current != &token);
                }
                Ok(json!({"released":true}))
            }
            _ => Err(CoreError::new("unknown_command", "未知ADB执行操作。")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{DeviceInfo, protocol};

    fn client() -> (Client, tokio::io::DuplexStream) {
        let (transport, peer) = tokio::io::duplex(4096);
        (
            Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 4096,
                    banner: "device::".into(),
                    features: Default::default(),
                },
            )
            .unwrap(),
            peer,
        )
    }

    #[tokio::test]
    async fn expiring_lease_closes_only_its_unadmitted_usb_transport() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let identity = runtime.identities.selected(None).await.unwrap();
        let op = runtime
            .new_setup_operation(
                &json!({"attemptId":"short-usb","leaseMs":30}),
                None,
                identity.fingerprint.clone(),
            )
            .await
            .unwrap();
        let (pending, _peer) = client();
        let (sibling, _other_peer) = client();
        *op.resource.lock().unwrap() = PendingResource::Usb {
            client: Some(pending.clone()),
            info: Metadata::default(),
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            while !pending.is_closed() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        assert!(op.token.is_cancelled());
        assert!(!sibling.is_closed());
        assert!(runtime.setup_operations.snapshot().await.is_empty());
        assert_eq!(
            runtime
                .setup_operations
                .get(&op.id)
                .await
                .err()
                .unwrap()
                .code,
            "cancelled"
        );
        sibling.close();
    }

    #[tokio::test]
    async fn usb_admission_is_explicit_and_releasing_its_setup_lease_preserves_the_admitted_connection()
     {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let record = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":5555}))
            .await
            .unwrap();
        let id = record["deviceId"].as_str().unwrap();
        runtime
            .invoke("observation.stop", json!({"deviceId":id}))
            .await
            .unwrap();
        // This is an existing-device handoff. Its prior verified identity must
        // match the candidate; the lease assertion below does not waive that
        // production ownership check.
        runtime
            .store
            .write()
            .await
            .devices
            .iter_mut()
            .find(|device| device.id == id)
            .unwrap()
            .serial = Some("verified-serial".into());
        let identity = runtime.identities.selected(Some(id)).await.unwrap();
        let op = runtime
            .new_setup_operation(
                &json!({"attemptId":"usb-handoff","leaseMs":60000}),
                Some(id),
                identity.fingerprint.clone(),
            )
            .await
            .unwrap();
        let (pending, _peer) = client();
        let mut info = Metadata::default();
        info.serial = Some("verified-serial".into());
        info.host_identity = Some(identity.fingerprint.clone());
        *op.resource.lock().unwrap() = PendingResource::Usb {
            client: Some(pending.clone()),
            info,
        };
        let result = runtime
            .usb_attach(&json!({"operationId":op.id,"deviceId":id}))
            .await
            .unwrap();
        assert_eq!(result["connected"], true);
        assert_eq!(
            serde_json::to_value(runtime.device(id).await.unwrap()).unwrap()["transport"],
            "usb"
        );
        runtime.setup_operations.release_alias(&op.id).await;
        assert!(
            !pending.is_closed(),
            "setup cancellation cannot close admitted resource ownership"
        );
        assert!(runtime.client(id).await.unwrap().same_connection(&pending));
        runtime.disconnect_device(id, false).await.unwrap();
        assert!(pending.is_closed());
    }

    #[tokio::test]
    async fn resetting_global_identity_invalidates_an_unbound_pairing_even_if_the_same_key_is_imported_again()
     {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let identity = runtime.identities.selected(None).await.unwrap();
        let op = runtime
            .new_setup_operation(
                &json!({"attemptId":"first-pair","leaseMs":60000}),
                None,
                identity.fingerprint.clone(),
            )
            .await
            .unwrap();
        runtime
            .invoke("identity.global.reset", json!({}))
            .await
            .unwrap();
        runtime
            .invoke(
                "identity.global.import",
                json!({"privateKeyPem":identity.identity.to_pkcs8_pem().unwrap().as_str()}),
            )
            .await
            .unwrap();
        assert_eq!(
            runtime.identities.selected(None).await.unwrap().fingerprint,
            identity.fingerprint
        );
        assert!(op.token.is_cancelled());
        assert_eq!(
            runtime
                .setup_operations
                .get(&op.id)
                .await
                .err()
                .unwrap()
                .code,
            "operation_expired"
        );
    }
}
