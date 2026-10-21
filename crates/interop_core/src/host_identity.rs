//! Private, local-only ADB identities. Public projections contain fingerprints only.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{Store, required},
};
use interop_adb::{Identity, wireless::TlsConfig};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    path::Path,
    sync::Arc,
};
use tokio::{
    fs,
    sync::{Mutex, OnceCell, RwLock},
};

pub(crate) struct Material {
    pub(crate) identity: Identity,
    pub(crate) fingerprint: String,
    tls: OnceCell<TlsConfig>,
}
impl Material {
    fn new(identity: Identity) -> CoreResult<Arc<Self>> {
        Ok(Arc::new(Self {
            fingerprint: fingerprint(&identity)?,
            identity,
            tls: OnceCell::new(),
        }))
    }
    pub(crate) async fn tls(&self) -> CoreResult<TlsConfig> {
        self.tls
            .get_or_try_init(|| async {
                let identity = self.identity.clone();
                tokio::task::spawn_blocking(move || TlsConfig::experimental_rustcrypto(&identity))
                    .await
                    .map_err(|_| CoreError::new("identity_error", "无法准备本机授权身份。"))?
                    .map_err(Into::into)
            })
            .await
            .cloned()
    }
}
pub(crate) fn fingerprint(identity: &Identity) -> CoreResult<String> {
    Ok(hex::encode(Sha256::digest(identity.public_key("interop")?)))
}
pub(crate) struct Identities {
    global: Arc<Material>,
    custom: HashMap<String, Option<Arc<Material>>>,
    blocked: HashSet<String>,
}
impl Identities {
    pub(crate) fn selected(&self, device: Option<&str>) -> CoreResult<Arc<Material>> {
        if device.is_some_and(|id| self.blocked.contains(id)) {
            return Err(CoreError::new(
                "identity_changed",
                "授权身份正在更新，请稍后重新连接。",
            ));
        }
        match device.and_then(|id| self.custom.get(id)) {
            Some(Some(material)) => Ok(material.clone()),
            Some(None) => Err(CoreError::new(
                "identity_unavailable",
                "设备专用授权私钥不可用，请重新导入或明确选择全局密钥。",
            )),
            None => Ok(self.global.clone()),
        }
    }
    pub(crate) fn validate(&self, device: &str, expected: &str) -> CoreResult<()> {
        if self.selected(Some(device))?.fingerprint != expected {
            return Err(CoreError::new(
                "identity_changed",
                "连接使用的授权身份已改变，请重新连接。",
            ));
        }
        Ok(())
    }
}
struct RetiredClient(Option<interop_adb::Client>);
impl Drop for RetiredClient {
    fn drop(&mut self) {
        if let Some(client) = &self.0 {
            client.close();
        }
    }
}
pub(crate) struct IdentityOwner {
    pub(crate) state: RwLock<Identities>,
    mutation: Mutex<()>,
}
impl IdentityOwner {
    pub(crate) async fn load(
        root: &Path,
        global: Identity,
        store: &mut Store,
    ) -> CoreResult<(Self, HashSet<String>)> {
        let saved: HashMap<String, String> =
            match fs::read(root.join("device_identities.json")).await {
                Ok(bytes) => serde_json::from_slice(&bytes)
                    .map_err(|_| CoreError::new("identity_error", "设备授权身份存储损坏。"))?,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => HashMap::new(),
                Err(e) => return Err(e.into()),
            };
        let mut custom = HashMap::new();
        let mut changed = HashSet::new();
        for device in &mut store.devices {
            if let Some(pem) = saved.get(&device.id) {
                let material = Material::new(Identity::from_pem(pem)?)?;
                if store.device_identity_fingerprints.get(&device.id) != Some(&material.fingerprint)
                {
                    changed.insert(device.id.clone());
                    device.auto_reconnect = false;
                }
                store
                    .device_identity_fingerprints
                    .insert(device.id.clone(), material.fingerprint.clone());
                custom.insert(device.id.clone(), Some(material));
            } else if store.device_identity_fingerprints.contains_key(&device.id) {
                changed.insert(device.id.clone());
                custom.insert(device.id.clone(), None);
            }
        }
        Ok((
            Self {
                state: RwLock::new(Identities {
                    global: Material::new(global)?,
                    custom,
                    blocked: HashSet::new(),
                }),
                mutation: Mutex::new(()),
            },
            changed,
        ))
    }
    pub(crate) async fn selected(&self, device: Option<&str>) -> CoreResult<Arc<Material>> {
        self.state.read().await.selected(device)
    }
    /// Uncommitted setup identities never replace the global or an existing
    /// device identity. PEM remains in the private setup owner until binding.
    pub(crate) async fn for_attempt(
        &self,
        params: &Value,
        device: Option<&str>,
    ) -> CoreResult<(Arc<Material>, bool)> {
        let Some(input) = params.get("identity") else {
            return Ok((self.selected(device).await?, false));
        };
        if device.is_some() {
            return Err(CoreError::new(
                "identity_read_only",
                "已有设备的授权私钥仅可查看。",
            ));
        }
        match input.get("scope").and_then(Value::as_str) {
            Some("global") if input.get("privateKeyPem").is_none() => {
                Ok((self.selected(None).await?, false))
            }
            Some("device") => {
                let pem = input
                    .get("privateKeyPem")
                    .and_then(Value::as_str)
                    .filter(|pem| !pem.is_empty() && pem.len() <= 32 * 1024)
                    .ok_or_else(|| {
                        CoreError::new("invalid_identity", "请输入不超过32 KiB的PEM私钥。")
                    })?;
                let identity = Identity::from_pem(pem).map_err(|_| {
                    CoreError::new(
                        "invalid_identity",
                        "请输入有效的ADB RSA-2048私钥PEM（指数65537）。",
                    )
                })?;
                Ok((Material::new(identity)?, true))
            }
            _ => Err(CoreError::new("invalid_identity", "请选择有效的私钥来源。")),
        }
    }
    pub(crate) async fn bind_new(
        &self,
        root: &Path,
        id: &str,
        material: Arc<Material>,
    ) -> CoreResult<()> {
        let _mutation = self.mutation.lock().await;
        let mut state = self.state.write().await;
        if state.custom.contains_key(id) {
            return Err(CoreError::new(
                "identity_read_only",
                "已有设备的授权私钥不可更换。",
            ));
        }
        let mut saved = HashMap::<String, String>::new();
        for (device, existing) in &state.custom {
            if let Some(existing) = existing {
                saved.insert(
                    device.clone(),
                    existing.identity.to_pkcs8_pem()?.to_string(),
                );
            }
        }
        saved.insert(id.into(), material.identity.to_pkcs8_pem()?.to_string());
        Runtime::private_write(
            &root.join("device_identities.json"),
            &serde_json::to_vec(&saved)?,
        )
        .await?;
        state.custom.insert(id.into(), Some(material));
        Ok(())
    }
}
impl Runtime {
    async fn identity_projection(&self, device: Option<&str>) -> CoreResult<Value> {
        if let Some(id) = device {
            self.device(id).await?;
        }
        let state = self.identities.state.read().await;
        let material = state.selected(device)?;
        Ok(
            json!({"deviceId":device,"scope":if device.is_some_and(|id| state.custom.contains_key(id)) {"device"} else {"global"},"fingerprint":material.fingerprint}),
        )
    }
    pub(crate) async fn identity_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        let device = if command.starts_with("identity.device.") {
            Some(required(params, "deviceId")?)
        } else {
            None
        };
        if command.ends_with(".get") {
            return self.identity_projection(device).await;
        }
        if !matches!(
            command,
            "identity.global.import"
                | "identity.global.reset"
                | "identity.device.import"
                | "identity.device.useGlobal"
        ) {
            return Err(CoreError::new("unknown_command", "未知授权身份操作。"));
        }
        if let Some(id) = device {
            self.device(id).await?;
        }
        // Validate before touching storage or an existing connection. Parser errors never echo input.
        let replacement = if command.ends_with(".import") {
            let pem = required(params, "privateKeyPem")?;
            if pem.len() > 32 * 1024 {
                return Err(CoreError::new("invalid_identity", "ADB 私钥 PEM 过长。"));
            }
            Some(Material::new(Identity::from_pem(pem).map_err(|_| {
                CoreError::new(
                    "invalid_identity",
                    "请输入有效的 ADB RSA-2048 私钥 PEM（指数 65537）。",
                )
            })?)?)
        } else if command.ends_with(".reset") {
            Some(Material::new(
                tokio::task::spawn_blocking(Identity::generate)
                    .await
                    .map_err(|_| CoreError::new("identity_error", "生成本机授权身份失败。"))??,
            )?)
        } else {
            None
        };
        // Once the durable replacement begins, finish revocation even when a
        // screen or FFI caller goes away while activities are being stopped.
        let owner = self.clone();
        let device = device.map(str::to_owned);
        tokio::spawn(async move { owner.replace_identity(device.as_deref(), replacement).await })
            .await
            .map_err(|_| {
                CoreError::new(
                    "identity_error",
                    "授权身份更新任务意外结束，请重新核对连接。",
                )
            })?
    }
    async fn replace_identity(
        &self,
        device: Option<&str>,
        replacement: Option<Arc<Material>>,
    ) -> CoreResult<Value> {
        let _mutation = self.identities.mutation.lock().await;
        if let Some(id) = device {
            self.device(id).await?;
        }
        // Publication holds this same read lock through admission. Thus every old
        // admitted client is in this snapshot; every late handshake is rejected.
        let mut state = self.identities.state.write().await;
        let mut saved = HashMap::<String, String>::new();
        for (id, material) in &state.custom {
            if let Some(material) = material {
                saved.insert(id.clone(), material.identity.to_pkcs8_pem()?.to_string());
            }
        }
        let affected = if let Some(id) = device {
            if let Some(material) = &replacement {
                saved.insert(id.into(), material.identity.to_pkcs8_pem()?.to_string());
            } else {
                saved.remove(id);
            }
            Runtime::private_write(
                &self.root.join("device_identities.json"),
                &serde_json::to_vec(&saved)?,
            )
            .await?;
            if let Some(material) = &replacement {
                state.custom.insert(id.into(), Some(material.clone()));
            } else {
                state.custom.remove(id);
            }
            vec![id.to_owned()]
        } else {
            let material = replacement.as_ref().expect("global replacement");
            Runtime::private_write(
                &self.root.join("host_identity.pem"),
                material.identity.to_pkcs8_pem()?.as_bytes(),
            )
            .await?;
            state.global = material.clone();
            self.store
                .read()
                .await
                .devices
                .iter()
                .filter(|device| !state.custom.contains_key(&device.id))
                .map(|device| device.id.clone())
                .collect::<Vec<_>>()
        };
        state.blocked.extend(affected.iter().cloned());
        {
            let mut store = self.store.write().await;
            store.identity_fingerprint = state.global.fingerprint.clone();
            if let Some(id) = device {
                if let Some(material) = &replacement {
                    store
                        .device_identity_fingerprints
                        .insert(id.into(), material.fingerprint.clone());
                } else {
                    store.device_identity_fingerprints.remove(id);
                }
            }
        }
        drop(state);
        self.setup_operations
            .invalidate_devices(&affected, device.is_none())
            .await;
        let mut failure = None;
        for id in &affected {
            if let Err(error) = self.invalidate_identity_connection(id).await {
                failure.get_or_insert(error);
            }
        }
        self.identities
            .state
            .write()
            .await
            .blocked
            .retain(|id| !affected.contains(id));
        self.persist().await?;
        self.emit(
            "devices.changed",
            None,
            json!({"devices":self.projected_devices().await}),
        );
        if let Some(error) = failure {
            return Err(error);
        }
        let mut result = self.identity_projection(device).await?;
        result["affectedDeviceIds"] = json!(affected);
        Ok(result)
    }
    pub(crate) async fn forget_device_identity(&self, id: &str) -> CoreResult<()> {
        let _mutation = self.identities.mutation.lock().await;
        let mut state = self.identities.state.write().await;
        if !state.custom.contains_key(id) {
            return Ok(());
        }
        let mut saved = HashMap::<String, String>::new();
        for (device, material) in &state.custom {
            if device != id
                && let Some(material) = material
            {
                saved.insert(
                    device.clone(),
                    material.identity.to_pkcs8_pem()?.to_string(),
                );
            }
        }
        Self::private_write(
            &self.root.join("device_identities.json"),
            &serde_json::to_vec(&saved)?,
        )
        .await?;
        state.custom.remove(id);
        Ok(())
    }
    async fn invalidate_identity_connection(&self, id: &str) -> CoreResult<()> {
        let mut cleanup = self.connections.transition(id).await;
        let _retired = RetiredClient({
            let mut pending = self.device_operations.lock().await;
            if let Some(token) = pending.remove(id) {
                token.cancel();
            }
            let mut store = self.store.write().await;
            let mut connections = self.connections.lock().await;
            *cleanup = true;
            let retired = connections.remove(id);
            if let Some(device) = store.devices.iter_mut().find(|device| device.id == id) {
                device.status = "unauthorized".into();
                device.reason = Some("授权密钥已改变，请使用新身份重新授权并连接。".into());
                device.auto_reconnect = false;
            }
            retired
        });
        self.stop_device_activities(id).await?;
        *cleanup = false;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{Client, DeviceInfo, protocol};
    use tokio_util::sync::CancellationToken;

    fn fixture_key() -> Identity {
        static KEY: std::sync::OnceLock<Identity> = std::sync::OnceLock::new();
        KEY.get_or_init(|| Identity::generate().unwrap()).clone()
    }
    async fn add(runtime: &Arc<Runtime>) -> String {
        runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":9}))
            .await
            .unwrap()["deviceId"]
            .as_str()
            .unwrap()
            .into()
    }
    async fn live(runtime: &Runtime, id: &str) -> (Client, tokio::io::DuplexStream) {
        let (transport, peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::\0".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        runtime
            .connections
            .lock()
            .await
            .insert(id.into(), client.clone());
        let mut store = runtime.store.write().await;
        let device = store.devices.iter_mut().find(|d| d.id == id).unwrap();
        device.status = "connected".into();
        device.observation_wanted = false;
        (client, peer)
    }
    #[tokio::test]
    async fn setup_identity_is_private_and_does_not_replace_global_or_an_existing_device() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let global = runtime
            .identities
            .selected(None)
            .await
            .unwrap()
            .fingerprint
            .clone();
        let key = fixture_key();
        let custom = runtime
            .add_device(&json!({
                "address":"127.0.0.1","port":9,
                "identity":{"scope":"device","privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()},
            }))
            .await
            .unwrap();
        let id = custom["deviceId"].as_str().unwrap();
        assert_eq!(
            runtime.identities.selected(None).await.unwrap().fingerprint,
            global
        );
        assert_eq!(
            runtime.identity_projection(Some(id)).await.unwrap()["scope"],
            "device"
        );
        assert_eq!(
            runtime
                .identities
                .selected(Some(id))
                .await
                .unwrap()
                .fingerprint,
            fingerprint(&key).unwrap()
        );
        let snapshot = runtime
            .invoke("state.snapshot", json!({}))
            .await
            .unwrap()
            .to_string();
        assert!(!snapshot.contains("PRIVATE KEY"));
        assert!(!snapshot.contains("privateKeyPem"));
        let replacement = json!({"deviceId":id,"identity":{"scope":"global"}});
        assert_eq!(
            runtime
                .identities
                .for_attempt(&replacement, Some(id))
                .await
                .err()
                .unwrap()
                .code,
            "identity_read_only"
        );
        drop(runtime);
        let restored = Runtime::initialize(directory.path()).await.unwrap();
        assert_eq!(
            restored
                .identities
                .selected(Some(id))
                .await
                .unwrap()
                .fingerprint,
            fingerprint(&key).unwrap()
        );
    }

    #[tokio::test]
    async fn invalid_setup_private_keys_do_not_create_records_or_change_identity() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let before = runtime
            .identities
            .selected(None)
            .await
            .unwrap()
            .fingerprint
            .clone();
        for input in [
            "a password",
            "-----BEGIN PUBLIC KEY-----\nAQID\n-----END PUBLIC KEY-----",
        ] {
            let error = runtime
                .add_device(&json!({
                    "address":"127.0.0.1","port":9,
                    "identity":{"scope":"device","privateKeyPem":input},
                }))
                .await
                .unwrap_err();
            assert_eq!(error.code, "invalid_identity");
            assert!(!format!("{error:?}").contains(input));
        }
        assert!(runtime.store.read().await.devices.is_empty());
        assert_eq!(
            runtime.identities.selected(None).await.unwrap().fingerprint,
            before
        );
    }

    #[tokio::test]
    async fn invalid_import_never_changes_identity_connection_or_exposes_secret() {
        let dir = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(dir.path()).await.unwrap();
        let id = add(&runtime).await;
        let (client, _peer) = live(&runtime, &id).await;
        let before = runtime
            .invoke("identity.global.get", json!({}))
            .await
            .unwrap();
        let secret = "a password is not an ADB private key";
        let error = runtime
            .invoke("identity.global.import", json!({"privateKeyPem":secret}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "invalid_identity");
        assert!(!format!("{error:?}").contains(secret));
        assert!(!client.is_closed());
        assert_eq!(
            runtime
                .invoke("identity.global.get", json!({}))
                .await
                .unwrap(),
            before
        );
        assert!(
            runtime
                .invoke("settings.update", json!({"privateKeyPem":secret}))
                .await
                .is_err()
        );
        client.close();
    }
    #[tokio::test]
    async fn reset_only_retires_global_clients_and_their_activities_and_preserves_custom_identity()
    {
        let dir = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(dir.path()).await.unwrap();
        let global = add(&runtime).await;
        let custom = add(&runtime).await;
        let key = fixture_key();
        let imported = runtime
            .invoke(
                "identity.device.import",
                json!({"deviceId":custom,"privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()}),
            )
            .await
            .unwrap();
        assert_eq!(imported["scope"], "device");
        let (global_client, _global_peer) = live(&runtime, &global).await;
        let (custom_client, _custom_peer) = live(&runtime, &custom).await;
        let global_cancel = CancellationToken::new();
        let custom_cancel = CancellationToken::new();
        let _global_activity = runtime
            .activities
            .admission
            .reserve_session(
                "global-session".into(),
                global.clone(),
                "screen".into(),
                global_cancel.clone(),
            )
            .unwrap();
        let _custom_activity = runtime
            .activities
            .admission
            .reserve_session(
                "custom-session".into(),
                custom.clone(),
                "screen".into(),
                custom_cancel.clone(),
            )
            .unwrap();
        let previous = runtime
            .invoke("identity.global.get", json!({}))
            .await
            .unwrap();
        let reset = runtime
            .invoke("identity.global.reset", json!({}))
            .await
            .unwrap();
        assert_ne!(reset["fingerprint"], previous["fingerprint"]);
        assert_eq!(reset["affectedDeviceIds"], json!([global]));
        assert!(global_client.is_closed());
        assert!(global_cancel.is_cancelled());
        assert!(!custom_client.is_closed());
        assert!(!custom_cancel.is_cancelled());
        assert_eq!(
            runtime.device(&global).await.unwrap().status,
            "unauthorized"
        );
        assert!(!runtime.device(&global).await.unwrap().auto_reconnect);
        assert_eq!(runtime.device(&custom).await.unwrap().status, "connected");
        let snapshot = runtime
            .invoke("state.snapshot", json!({}))
            .await
            .unwrap()
            .to_string();
        let export = runtime
            .invoke("settings.export", json!({}))
            .await
            .unwrap()
            .to_string();
        for projection in [snapshot, export] {
            assert!(!projection.contains("PRIVATE KEY"));
            assert!(!projection.contains("privateKeyPem"));
        }
        let expected = fingerprint(&key).unwrap();
        for kind in [
            crate::model::TransportKind::Tcp,
            crate::model::TransportKind::Usb,
            crate::model::TransportKind::Tls,
        ] {
            runtime
                .store
                .write()
                .await
                .devices
                .iter_mut()
                .find(|d| d.id == custom)
                .unwrap()
                .transport = kind;
            let options = runtime
                .connect_options_for(Some(&custom), CancellationToken::new())
                .await
                .unwrap();
            assert_eq!(
                fingerprint(options.identity.as_ref().unwrap()).unwrap(),
                expected
            );
            assert!(
                options
                    .tls
                    .as_ref()
                    .unwrap()
                    .matches_identity(options.identity.as_ref().unwrap())
                    .unwrap()
            );
        }
        custom_client.close();
        drop(runtime);
        let restored = Runtime::initialize(dir.path()).await.unwrap();
        assert_eq!(
            restored
                .invoke("identity.device.get", json!({"deviceId":custom}))
                .await
                .unwrap()["fingerprint"],
            expected
        );
        let inherited = restored
            .invoke("identity.device.useGlobal", json!({"deviceId":custom}))
            .await
            .unwrap();
        assert_eq!(inherited["scope"], "global");
        assert_eq!(inherited["fingerprint"], reset["fingerprint"]);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            for path in ["host_identity.pem", "device_identities.json"] {
                assert_eq!(
                    std::fs::metadata(dir.path().join(path))
                        .unwrap()
                        .permissions()
                        .mode()
                        & 0o777,
                    0o600
                );
            }
        }
    }
    #[tokio::test]
    async fn missing_custom_key_never_silently_falls_back_to_global() {
        let dir = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(dir.path()).await.unwrap();
        let id = add(&runtime).await;
        runtime.invoke("identity.device.import", json!({"deviceId":id,"privateKeyPem":fixture_key().to_pkcs8_pem().unwrap().as_str()})).await.unwrap();
        drop(runtime);
        fs::remove_file(dir.path().join("device_identities.json"))
            .await
            .unwrap();
        let restored = Runtime::initialize(dir.path()).await.unwrap();
        assert_eq!(
            restored
                .connect_options_for(Some(&id), CancellationToken::new())
                .await
                .unwrap_err()
                .code,
            "identity_unavailable"
        );
        restored
            .invoke("identity.device.useGlobal", json!({"deviceId":id}))
            .await
            .unwrap();
        assert!(
            restored
                .connect_options_for(Some(&id), CancellationToken::new())
                .await
                .is_ok()
        );
    }
    #[tokio::test]
    async fn old_identity_handshake_cannot_publish_after_replacement() {
        let dir = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(dir.path()).await.unwrap();
        let id = add(&runtime).await;
        let before = runtime.identities.selected(Some(&id)).await.unwrap();
        runtime.invoke("identity.device.import", json!({"deviceId":id,"privateKeyPem":fixture_key().to_pkcs8_pem().unwrap().as_str()})).await.unwrap();
        let (client, _peer) = live(&runtime, &id).await;
        runtime.connections.lock().await.remove(&id);
        let mut info = crate::device::Metadata::default();
        info.host_identity = Some(before.fingerprint.clone());
        let result = runtime
            .attach_client(
                &id,
                client.clone(),
                info,
                &CancellationToken::new(),
                None,
                None,
            )
            .await;
        assert_eq!(result.unwrap_err().code, "identity_changed");
        assert!(client.is_closed());
        assert!(runtime.client(&id).await.is_err());
    }
    #[test]
    fn adb_identity_accepts_pkcs1_and_pkcs8_but_rejects_wrong_size_or_exponent() {
        use rsa::{
            BigUint, RsaPrivateKey,
            pkcs1::EncodeRsaPrivateKey,
            pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding},
        };
        let key = fixture_key();
        let pkcs8 = key.to_pkcs8_pem().unwrap();
        let rsa_key = RsaPrivateKey::from_pkcs8_pem(&pkcs8).unwrap();
        let pkcs1 = rsa_key.to_pkcs1_pem(LineEnding::LF).unwrap();
        assert_eq!(
            fingerprint(&Identity::from_pem(&pkcs1).unwrap()).unwrap(),
            fingerprint(&key).unwrap()
        );
        for (bits, exponent) in [(1024, 65537), (2048, 3)] {
            let invalid = RsaPrivateKey::new_with_exp(
                &mut rsa::rand_core::OsRng,
                bits,
                &BigUint::from(exponent as u32),
            )
            .unwrap();
            assert!(
                Identity::from_pem(invalid.to_pkcs8_pem(LineEnding::LF).unwrap().as_str()).is_err()
            );
        }
    }
    #[tokio::test]
    async fn reconnect_auth_signs_with_the_saved_device_key_after_global_reset() {
        use interop_adb::protocol::Frame;
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let added = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":port}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap();
        let key = fixture_key();
        runtime
            .invoke(
                "identity.device.import",
                json!({"deviceId":id,"privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()}),
            )
            .await
            .unwrap();
        runtime
            .invoke("identity.global.reset", json!({}))
            .await
            .unwrap();
        runtime
            .store
            .write()
            .await
            .devices
            .iter_mut()
            .find(|d| d.id == id)
            .unwrap()
            .observation_wanted = false;
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(
                Frame::read(&mut socket, 4096, false).await.unwrap().command,
                protocol::CNXN
            );
            let token = vec![0x42; 20];
            Frame::new(protocol::AUTH, 1, 0, token.clone())
                .write(&mut socket)
                .await
                .unwrap();
            let signed = Frame::read(&mut socket, 4096, false).await.unwrap();
            assert_eq!(signed.command, protocol::AUTH);
            assert_eq!(signed.arg0, 2);
            assert_eq!(signed.payload, key.sign_token(&token).unwrap());
            Frame::new(
                protocol::CNXN,
                protocol::VERSION,
                4096,
                b"device::\0".to_vec(),
            )
            .write(&mut socket)
            .await
            .unwrap();
            while let Ok(frame) = Frame::read(&mut socket, 4096, true).await {
                if frame.command == protocol::OPEN {
                    Frame::new(protocol::CLSE, 0, frame.arg0, vec![])
                        .write(&mut socket)
                        .await
                        .unwrap();
                }
            }
        });
        let result = runtime
            .invoke("devices.connect", json!({"deviceId":id}))
            .await
            .unwrap();
        assert_eq!(result["connected"], true);
        runtime
            .invoke("devices.disconnect", json!({"deviceId":id}))
            .await
            .unwrap();
        tokio::time::timeout(std::time::Duration::from_secs(2), server)
            .await
            .unwrap()
            .unwrap();
    }
}
