//! Persistent device identity and live connection lifecycle. Network locations
//! never serve as device identifiers; discovery changes endpoints, not trust.
#[cfg(test)]
#[path = "device/qr_pairing_tests.rs"]
mod qr_pairing_tests;

#[path = "device/qr_pairing.rs"]
mod qr_pairing;

use crate::{
    CoreError, CoreResult, Runtime,
    model::{Device, TransportKind, now, required},
};
#[cfg(test)]
use interop_adb::wireless::TlsConfig;
use interop_adb::{
    Client, ConnectOptions, OperationOptions, TlsPolicy,
    wireless::{
        self, QrPairing,
        discovery::{CONNECT_SERVICE, Discovery, DiscoveryEvent, Service, ServiceKind},
    },
};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet, hash_map::Entry},
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio_util::sync::CancellationToken;

pub(crate) type DiscoveredServices = Arc<tokio::sync::RwLock<DiscoveredState>>;

const MAX_DISCOVERED_SERVICES_PER_GUID: usize = 8;

#[derive(Default)]
struct DiscoveredDevice {
    generation: u64,
    observed: bool,
    services: HashMap<String, Service>,
}

#[derive(Default)]
pub(crate) struct DiscoveredState {
    devices: HashMap<String, DiscoveredDevice>,
    revision: u64,
}

impl DiscoveredState {
    fn sync_trusted(&mut self, trusted: HashSet<String>) {
        self.devices.retain(|guid, _| trusted.contains(guid));
        for guid in trusted {
            if let Entry::Vacant(entry) = self.devices.entry(guid) {
                // Rebuilding a forgotten GUID must never reuse its old epoch.
                self.revision += 1;
                entry.insert(DiscoveredDevice {
                    generation: self.revision,
                    ..Default::default()
                });
            }
        }
    }

    fn observe(&mut self, event: DiscoveryEvent) -> Option<String> {
        let instance = match &event {
            DiscoveryEvent::Resolved(service) if service.kind == ServiceKind::Connect => {
                service.instance.clone()
            }
            DiscoveryEvent::Removed { fullname } => fullname
                .strip_suffix(CONNECT_SERVICE)?
                .trim_end_matches('.')
                .to_owned(),
            _ => return None,
        };
        // Only persisted non-USB GUIDs get state. Prefer an exact identity over
        // interpreting its name as another GUID's conflict suffix.
        let guid = if self.devices.contains_key(&instance) {
            instance
        } else {
            self.devices
                .keys()
                .find(|guid| matches_guid(&instance, guid))?
                .clone()
        };
        let device = self.devices.get_mut(&guid)?;
        match event {
            DiscoveryEvent::Resolved(service) => {
                if device.services.get(&service.fullname) == Some(&service) {
                    return None;
                }
                if !device.services.contains_key(&service.fullname)
                    && device.services.len() == MAX_DISCOVERED_SERVICES_PER_GUID
                {
                    if service.instance != guid {
                        return None;
                    }
                    // Conflict aliases cannot crowd out the exact GUID.
                    let alias = device
                        .services
                        .iter()
                        .find(|(_, answer)| answer.instance != guid)
                        .map(|(fullname, _)| fullname.clone())?;
                    device.services.remove(&alias);
                }
                device.services.insert(service.fullname.clone(), service);
            }
            DiscoveryEvent::Removed { fullname } => {
                if device.services.remove(&fullname).is_none() && device.observed {
                    return None;
                }
            }
        }
        // One GUID-level marker suppresses cached endpoints after a goodbye;
        // no per-fullname tombstones survive removal. Every accepted change or
        // eviction advances the epoch, including same-endpoint reannouncements.
        device.observed = true;
        self.revision += 1;
        device.generation = self.revision;
        Some(guid)
    }

    fn generation(&self, guid: &str) -> u64 {
        self.devices.get(guid).map_or(0, |device| device.generation)
    }

    fn endpoints(&self, guid: &str) -> Option<Vec<SocketAddr>> {
        let device = self.devices.get(guid)?;
        if !device.observed {
            return None;
        }
        let mut endpoints = device
            .services
            .values()
            .flat_map(|service| service.endpoints.iter().copied())
            .collect::<Vec<_>>();
        endpoints.sort();
        endpoints.dedup();
        Some(endpoints)
    }
}

pub(crate) struct DiscoveredAttempt {
    services: DiscoveredServices,
    guid: String,
    endpoints: Option<Vec<SocketAddr>>,
    generation: u64,
}

impl DiscoveredAttempt {
    async fn is_current(&self) -> bool {
        self.services.read().await.generation(&self.guid) == self.generation
    }
}

/// Keep the first-pairing browser alive through TLS and metadata publication.
/// Its updates use the same epoch checks as ordinary trusted reconnection.
pub(crate) struct PairingDiscovery {
    services: DiscoveredServices,
    guid: String,
    task: tokio::task::JoinHandle<()>,
}

impl PairingDiscovery {
    #[cfg(test)]
    pub(crate) async fn attempt(&self) -> DiscoveredAttempt {
        let answers = self.services.read().await;
        DiscoveredAttempt {
            services: self.services.clone(),
            guid: self.guid.clone(),
            endpoints: answers.endpoints(&self.guid),
            generation: answers.generation(&self.guid),
        }
    }
}

impl Drop for PairingDiscovery {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn discovery_changed() -> CoreError {
    CoreError::new(
        "discovery_changed",
        "设备网络地址已更新，将使用最新地址重连。",
    )
}

fn authorization_failed(error: &CoreError) -> bool {
    matches!(
        error.code.as_str(),
        "authorization_required" | "identity_changed" | "identity_unavailable"
    )
}

/// Remove admission first, but keep the exact old transport alive while its
/// media owners acknowledge shutdown and delete their temporary artifacts.
/// A cancelled disconnect must still close this detached Client.
struct DetachedConnection(Option<Client>);

impl Drop for DetachedConnection {
    fn drop(&mut self) {
        if let Some(client) = &self.0 {
            client.close();
        }
    }
}

fn operations(seconds: u64, cancellation: CancellationToken) -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(seconds),
        cancellation,
    }
}

#[cfg(test)]
mod recovery_tests {
    use super::*;

    #[tokio::test]
    async fn connection_projection_is_ephemeral_and_wake_rejects_replaced_transport() {
        use interop_adb::{
            DeviceInfo,
            protocol::{self, Frame},
        };
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let added = runtime
            .add_device(&json!({"address":"127.0.0.1","port":5555}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        let fixture = || {
            let (transport, peer) = tokio::io::duplex(4096);
            let client = Client::from_negotiated_transport(
                transport,
                DeviceInfo {
                    version: protocol::VERSION,
                    max_payload: 4096,
                    banner: "device::".into(),
                    features: Default::default(),
                },
            )
            .unwrap();
            (client, peer)
        };
        let (first, _first_peer) = fixture();
        assert_eq!(first.connection_id(), first.clone().connection_id());
        runtime
            .connections
            .lock()
            .await
            .insert(id.clone(), first.clone());
        runtime.store.write().await.devices[0].status = "connected".into();
        let projection = runtime.invoke("devices.list", json!({})).await.unwrap();
        assert_eq!(
            projection["devices"][0]["connectionId"],
            first.connection_id().to_string()
        );
        runtime.persist().await.unwrap();
        let saved = tokio::fs::read_to_string(directory.path().join("devices.json"))
            .await
            .unwrap();
        assert!(!saved.contains("connectionId"));
        let gate = runtime.connections.transition(&id).await;
        let executor = runtime.clone();
        let device = id.clone();
        let old_id = first.connection_id().to_string();
        let wake = tokio::spawn(async move { executor.wake_device(&device, Some(&old_id)).await });
        let (second, mut second_peer) = fixture();
        assert_ne!(first.connection_id(), second.connection_id());
        runtime
            .connections
            .lock()
            .await
            .insert(id.clone(), second.clone());
        drop(gate);
        assert_eq!(wake.await.unwrap().unwrap_err().code, "stale_connection");
        assert!(
            tokio::time::timeout(
                Duration::from_millis(25),
                Frame::read(&mut second_peer, 4096, true)
            )
            .await
            .is_err(),
            "an old connection generation must not send wake input to its replacement"
        );
        let snapshot = runtime.state_snapshot().await.unwrap();
        assert_eq!(
            snapshot["devices"][0]["connectionId"],
            second.connection_id().to_string()
        );
        first.close();
        second.close();
    }

    #[tokio::test]
    async fn delayed_forget_cannot_publish_old_settings_after_a_snapshot() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let device = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":9}))
            .await
            .unwrap()["deviceId"]
            .as_str()
            .unwrap()
            .to_owned();
        let mut events = runtime.subscribe();
        let barrier = runtime.persistence.lock().await;
        let owner = runtime.clone();
        let forgetting = tokio::spawn(async move {
            owner
                .invoke("devices.forget", json!({"deviceId":device}))
                .await
                .unwrap()
        });
        tokio::time::timeout(Duration::from_secs(2), async {
            while !runtime.invoke("devices.list", Value::Null).await.unwrap()["devices"]
                .as_array()
                .unwrap()
                .is_empty()
            {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        let owner = runtime.clone();
        let updating = tokio::spawn(async move {
            owner
                .invoke("settings.update", json!({"appearance":"dark"}))
                .await
                .unwrap()
        });
        tokio::time::timeout(Duration::from_secs(2), async {
            while runtime.invoke("settings.get", Value::Null).await.unwrap()["appearance"] != "dark"
            {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        let snapshot = runtime.invoke("state.snapshot", Value::Null).await.unwrap();
        assert_eq!(snapshot["settings"]["appearance"], "dark");
        assert_eq!(snapshot["devices"], json!([]));

        drop(barrier);
        forgetting.await.unwrap();
        updating.await.unwrap();
        let mut settings_events = 0;
        while let Ok(event) = events.try_recv() {
            if event["type"] == "settings.changed" {
                settings_events += 1;
                assert!(
                    event["sequence"].as_u64().unwrap() > snapshot["sequence"].as_u64().unwrap()
                );
                assert_eq!(
                    event["data"]["appearance"], "dark",
                    "late forget publication must use current settings"
                );
            }
        }
        assert_eq!(settings_events, 2);
    }
}
#[cfg(test)]
#[path = "device/connection_cleanup_tests.rs"]
mod connection_cleanup_tests;

#[cfg(test)]
#[path = "device/pairing_tests.rs"]
mod pairing_tests;

#[cfg(test)]
#[path = "device/configuration_tests.rs"]
mod configuration_tests;
#[cfg(test)]
#[path = "device/metadata_tests.rs"]
mod metadata_tests;

#[cfg(all(
    test,
    any(
        target_os = "linux",
        target_os = "android",
        target_os = "windows",
        target_os = "macos"
    )
))]
#[path = "device/usb_tests.rs"]
mod usb_tests;

#[cfg(any(
    target_os = "linux",
    target_os = "android",
    target_os = "windows",
    target_os = "macos"
))]
fn select_usb_device(ids: &[String], requested: Option<&str>) -> CoreResult<Option<usize>> {
    if let Some(requested) = requested {
        return ids
            .iter()
            .position(|id| id == requested)
            .map(Some)
            .ok_or_else(|| CoreError::new("usb_removed", "所选 USB 设备已断开，请重新检查连接。"));
    }
    match ids.len() {
        0 => Err(CoreError::new(
            "usb_not_found",
            "未识别到 ADB 设备，请检查数据线、USB 角色和被控手机的 USB 调试。",
        )),
        1 => Ok(Some(0)),
        _ => Ok(None),
    }
}

pub(crate) fn host(params: &Value) -> CoreResult<String> {
    let value = required(params, "address")?.trim();
    if value.is_empty()
        || value.len() > 253
        || value
            .bytes()
            .any(|b| b.is_ascii_whitespace() || matches!(b, 0 | b'/' | b'\\' | b'[' | b']'))
    {
        return Err(CoreError::new(
            "invalid_address",
            "请输入不含端口的设备 IP 或主机名。",
        ));
    }
    if value.contains(':')
        && value
            .split('%')
            .next()
            .unwrap_or_default()
            .parse::<std::net::Ipv6Addr>()
            .is_err()
    {
        return Err(CoreError::new(
            "invalid_address",
            "IPv6 地址无效；端口请单独填写。",
        ));
    }
    Ok(value.to_owned())
}
pub(crate) fn port(params: &Value) -> CoreResult<u16> {
    params
        .get("port")
        .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
        .and_then(|p| u16::try_from(p).ok())
        .filter(|p| *p != 0)
        .ok_or_else(|| CoreError::new("invalid_port", "端口必须是 1 到 65535 之间的数字。"))
}
pub(crate) fn endpoint(address: &str, port: u16) -> String {
    if address.contains(':') {
        format!("[{address}]:{port}")
    } else {
        format!("{address}:{port}")
    }
}
fn address_of(address: SocketAddr) -> String {
    match address {
        SocketAddr::V4(v4) => v4.ip().to_string(),
        SocketAddr::V6(v6) if v6.scope_id() != 0 => format!("{}%{}", v6.ip(), v6.scope_id()),
        SocketAddr::V6(v6) => v6.ip().to_string(),
    }
}
fn blank_device(address: String, port: u16, transport: TransportKind) -> Device {
    Device {
        id: uuid::Uuid::new_v4().to_string(),
        name: "Android 设备".into(),
        address,
        port,
        guid: None,
        serial: None,
        transport,
        status: "offline".into(),
        model: None,
        android_version: None,
        api_level: None,
        battery: None,
        charging: None,
        battery_updated_at: None,
        last_seen: None,
        reason: None,
        auto_reconnect: false,
        observation_wanted: true,
    }
}
fn matches_guid(instance: &str, guid: &str) -> bool {
    if guid.is_empty() {
        return false;
    }
    instance == guid
        || instance
            .strip_prefix(guid)
            .and_then(|s| s.strip_prefix(" ("))
            .and_then(|s| s.strip_suffix(')'))
            .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
}

#[derive(Default, Clone, serde::Serialize)]
pub(crate) struct Metadata {
    model: Option<String>,
    release: Option<String>,
    api: Option<u32>,
    pub(crate) serial: Option<String>,
    battery: Option<u32>,
    error: Option<String>,
    pub(crate) host_identity: Option<String>,
}
enum AttachedEndpoint {
    Usb {
        create: bool,
    },
    Tls(SocketAddr),
    Tcp {
        address: String,
        port: u16,
    },
    Configured {
        address: String,
        port: u16,
        transport: TransportKind,
    },
}
fn verify_same_target(original: &Device, info: &Metadata) -> CoreResult<()> {
    match (&original.serial, &info.serial) {
        (Some(known), Some(actual)) if known == actual => Ok(()),
        (Some(_), Some(_)) => Err(CoreError::new(
            "device_identity_mismatch",
            "连接目标与原设备身份不符，未更新连接配置。",
        )),
        _ => Err(CoreError::new(
            "device_identity_unverified",
            "无法核验原设备身份，请检查设备授权与连接。",
        )),
    }
}
fn nonempty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "unknown" && *s != "null")
        .map(str::to_owned)
}
pub(crate) async fn metadata(client: &Client, token: CancellationToken) -> Metadata {
    let command = "getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.serialno";
    let output = match client.shell(command, 64 * 1024, operations(8, token)).await {
        Ok(output) => output,
        Err(error) => {
            return Metadata {
                error: Some(format!("读取设备信息失败：{error}")),
                ..Default::default()
            };
        }
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let mut lines = text.lines();
    let model = nonempty(lines.next());
    let release = nonempty(lines.next());
    let api = lines.next().and_then(|s| s.trim().parse().ok());
    let serial = nonempty(lines.next());
    Metadata {
        model,
        release,
        api,
        serial,
        battery: None,
        error: None,
        host_identity: None,
    }
}

pub(crate) fn project_device(device: &Device, clients: &HashMap<String, Client>) -> Value {
    let mut projection = json!(device);
    projection["connectionId"] = clients
        .get(&device.id)
        .filter(|client| device.status == "connected" && !client.is_closed())
        .map(|client| json!(client.connection_id().to_string()))
        .unwrap_or(Value::Null);
    projection
}

impl Runtime {
    pub(crate) async fn projected_devices(&self) -> Vec<Value> {
        let store = self.store.read().await;
        let clients = self.connections.lock().await;
        store
            .devices
            .iter()
            .map(|device| project_device(device, &clients))
            .collect()
    }

    pub(crate) async fn changed_devices(&self) -> CoreResult<()> {
        self.persist().await?;
        self.emit(
            "devices.changed",
            None,
            json!({"devices": self.projected_devices().await}),
        );
        Ok(())
    }
    #[cfg(test)]
    async fn connect_options(&self, token: CancellationToken) -> CoreResult<ConnectOptions> {
        self.connect_options_for(None, token).await
    }
    pub(crate) async fn connect_options_for(
        &self,
        id: Option<&str>,
        token: CancellationToken,
    ) -> CoreResult<ConnectOptions> {
        let material = self.identities.selected(id).await?;
        self.connect_options_with_material(material, token).await
    }
    async fn connect_options_with_material(
        &self,
        material: std::sync::Arc<crate::host_identity::Material>,
        token: CancellationToken,
    ) -> CoreResult<ConnectOptions> {
        Ok(ConnectOptions {
            tcp: self.connection_policy.tcp.options(),
            identity: Some(material.identity.clone()),
            tls: Some(material.tls().await?),
            tls_policy: TlsPolicy::Optional,
            request_authorization: self.connection_policy.request_authorization,
            public_key_comment: self.connection_policy.public_key_comment.clone(),
            burst_mode: self.store.read().await.settings["adbBurstMode"] == true,
            operations: OperationOptions {
                timeout: Duration::from_millis(self.connection_policy.connect_timeout_ms),
                cancellation: token,
            },
        })
    }
    pub(crate) async fn add_device(&self, params: &Value) -> CoreResult<Value> {
        let address = host(params)?;
        let port = port(params)?;
        let transport = match params.get("transport") {
            None => None,
            Some(Value::String(kind)) if matches!(kind.as_str(), "tls" | "tcp") => {
                TransportKind::parse(kind)
            }
            Some(_) => {
                return Err(CoreError::new(
                    "invalid_transport",
                    "请选择现代无线调试或旧式 TCP 连接。",
                ));
            }
        };
        let explicit = params.get("deviceId").and_then(Value::as_str);
        let (material, dedicated) = self.identities.for_attempt(params, explicit).await?;
        let mut created = blank_device(
            address.clone(),
            port,
            transport.clone().unwrap_or(TransportKind::Tcp),
        );
        if explicit.is_none() && dedicated {
            self.identities
                .bind_new(&self.root, &created.id, material.clone())
                .await?;
        }
        let device = {
            let mut store = self.store.write().await;
            if let Some(id) = explicit {
                let existing = store
                    .devices
                    .iter_mut()
                    .find(|d| d.id == id)
                    .ok_or_else(|| CoreError::new("not_found", "原设备记录已不存在。"))?;
                if existing.status == "connected" || existing.status == "connecting" {
                    return Err(CoreError::new(
                        "device_busy",
                        "请先断开设备，再修改连接地址。",
                    ));
                }
                existing.address = address;
                existing.port = port;
                // Endpoint edits never weaken a known modern wireless identity.
                // Legacy callers may omit transport, so retain the old record's
                // policy rather than reclassifying it from its current port.
                existing.transport = if existing.guid.is_some()
                    || matches!(existing.transport, TransportKind::Tls)
                {
                    TransportKind::Tls
                } else {
                    transport.unwrap_or(TransportKind::Tcp)
                };
                existing.reason = None;
                existing.clone()
            } else {
                if dedicated {
                    store
                        .device_identity_fingerprints
                        .insert(created.id.clone(), material.fingerprint.clone());
                }
                created.address = address;
                store.devices.push(created.clone());
                created
            }
        };
        self.changed_devices().await?;
        Ok(json!({"deviceId":device.id,"device":device}))
    }
    /// Validate a candidate using the bound identity before replacing any
    /// endpoint or existing live transport. Failures leave the saved config.
    pub(crate) async fn configure_device(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let original = self.device(id).await?;
        let address = host(params)?;
        let port = port(params)?;
        let requested = params["transport"]
            .as_str()
            .and_then(TransportKind::parse)
            .filter(|kind| matches!(kind, TransportKind::Tcp | TransportKind::Tls))
            .ok_or_else(|| CoreError::new("invalid_transport", "请选择有效的连接方式。"))?;
        let transport = if original.transport.requires_tls(original.guid.as_deref()) {
            TransportKind::Tls
        } else {
            requested
        };
        let (material, _) = self.identities.for_attempt(params, Some(id)).await?;
        let token = CancellationToken::new();
        let attempt = params["attemptId"].as_str();
        if let Some(attempt) = attempt
            && (attempt.is_empty() || attempt.len() > 200 || attempt == id)
        {
            return Err(CoreError::new("invalid_argument", "连接尝试标识无效。"));
        }
        self.register_connection_operation(id, true, &token).await?;
        if let Some(attempt) = attempt {
            let mut pending = self.device_operations.lock().await;
            if let Some(old) = pending.insert(attempt.into(), token.clone()) {
                old.cancel();
            }
        }
        let result = async {
            let mut options = self
                .connect_options_with_material(material.clone(), token.clone())
                .await?;
            if transport.requires_tls(original.guid.as_deref()) {
                options.tls_policy = TlsPolicy::Required;
            }
            let client = Client::connect_tcp(endpoint(&address, port), options).await?;
            let guarded = client.clone();
            let mut info = metadata(&client, token.clone()).await;
            info.host_identity = Some(material.fingerprint.clone());
            if token.is_cancelled() {
                guarded.close();
                return Err(CoreError::new("cancelled", "连接配置已取消。"));
            }
            if let Err(error) = verify_same_target(&original, &info) {
                guarded.close();
                return Err(error);
            }
            let result = self
                .attach_client_at(
                    id,
                    client,
                    info,
                    &token,
                    Some(AttachedEndpoint::Configured {
                        address,
                        port,
                        transport,
                    }),
                    None,
                )
                .await;
            if result.is_err() {
                guarded.close();
            }
            result
        }
        .await;
        if let Some(attempt) = attempt {
            let mut pending = self.device_operations.lock().await;
            if pending.get(attempt) == Some(&token) {
                pending.remove(attempt);
            }
        }
        result
    }
    pub(crate) async fn rename_device(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let name = required(params, "name")?.trim();
        if name.is_empty() || name.chars().count() > 80 || name.chars().any(char::is_control) {
            return Err(CoreError::new(
                "invalid_name",
                "设备名称需为 1 到 80 个可见字符。",
            ));
        }
        let device = {
            let mut store = self.store.write().await;
            let record = store
                .devices
                .iter_mut()
                .find(|d| d.id == id)
                .ok_or_else(|| CoreError::new("not_found", "设备记录已不存在。"))?;
            record.name = name.into();
            record.clone()
        };
        self.changed_devices().await?;
        Ok(json!({"device":device}))
    }
    /// A form attempt gets its own cancellation alias. The device alias remains
    /// available to explicit disconnect; finishing an old attempt never removes
    /// the token installed by a newer attempt.
    pub(crate) async fn connect_device_with_attempt(
        &self,
        id: &str,
        attempt_id: Option<&str>,
        automatic: bool,
        owner_id: Option<&str>,
        candidate_source: Option<&str>,
        parent_operation_id: Option<&str>,
    ) -> CoreResult<Value> {
        if attempt_id.is_some_and(|attempt| {
            attempt.is_empty() || attempt == id || attempt.contains('\0') || attempt.len() > 200
        }) {
            return Err(CoreError::new("invalid_argument", "连接尝试标识无效。"));
        }
        if candidate_source.is_some_and(|value| !matches!(value, "saved" | "discovery")) {
            return Err(CoreError::new("invalid_argument", "候选地址来源无效。"));
        }
        let parent = if let Some(operation) = parent_operation_id {
            let parent = self.setup_operations.get(operation).await?;
            if automatic || parent.device_id().as_deref() != Some(id) {
                return Err(CoreError::new("invalid_operation", "父执行与设备不匹配。"));
            }
            if parent.reauthorizing() && self.device(id).await?.serial.is_none() {
                return Err(CoreError::new(
                    "device_identity_unverified",
                    "无法核验原设备身份，请重新添加并授权。",
                ));
            }
            Some(parent)
        } else {
            None
        };
        let token = if let Some(parent) = &parent {
            parent.token.clone()
        } else if automatic {
            let owners = self.reconnect_owner.lock().await;
            let lease = owners
                .as_ref()
                .filter(|lease| Some(lease.id.as_str()) == owner_id)
                .ok_or_else(|| CoreError::new("cancelled", "自动重连协调器已释放。"))?;
            lease.cancellation.child_token()
        } else {
            CancellationToken::new()
        };
        if automatic {
            // Cleanup ownership stays native even though retry scheduling is
            // in Dart. A recovery snapshot can observe the detached old
            // transport before its activities publish their final retirement.
            let mut transition = tokio::select! {
                _ = token.cancelled() => return Err(CoreError::new("cancelled", "自动重连协调器已释放。")),
                transition = self.connections.transition(id) => transition,
            };
            self.retire_closed_connection_locked(id, &mut transition)
                .await?;
        }
        let _parent_execution = parent
            .as_ref()
            .map(|op| {
                op.execution
                    .try_lock()
                    .map_err(|_| CoreError::new("operation_busy", "执行正在进行。"))
            })
            .transpose()?;
        let parent_discovery = if let Some(parent) = &parent {
            let resource = parent.resource.lock().expect("operation resource poisoned");
            match &*resource {
                crate::connection_setup::PendingResource::Pairing(discovery) => {
                    Some((discovery.services.clone(), discovery.guid.clone()))
                }
                _ => {
                    return Err(CoreError::new(
                        "invalid_operation",
                        "父执行不是已配对的连接继续租约。",
                    ));
                }
            }
        } else {
            None
        };
        let discovered = if automatic || candidate_source == Some("discovery") {
            let record = self.device(id).await?;
            if !record.transport.is_usb() || parent_discovery.is_some() {
                if let Some(guid) = parent_discovery
                    .as_ref()
                    .map(|(_, guid)| guid.clone())
                    .or(record.guid)
                {
                    let services = parent_discovery
                        .as_ref()
                        .map(|(services, _)| services.clone())
                        .unwrap_or_else(|| self.discovered_services.clone());
                    let answers = services.read().await;
                    Some(DiscoveredAttempt {
                        services: services.clone(),
                        generation: answers.generation(&guid),
                        endpoints: answers.endpoints(&guid),
                        guid,
                    })
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };
        if candidate_source == Some("discovery")
            && discovered
                .as_ref()
                .is_none_or(|answer| answer.endpoints.as_ref().is_none_or(Vec::is_empty))
        {
            return Err(CoreError::new(
                "discovery_pending",
                "尚无当前可信连接地址。",
            ));
        }
        if let Some(parent) = &parent {
            self.identities
                .state
                .read()
                .await
                .validate(id, &parent.identity)?;
        }
        if let Some(attempt) = attempt_id {
            let mut pending = self.device_operations.lock().await;
            if let Some(previous) = pending.insert(attempt.into(), token.clone())
                && previous != token
            {
                previous.cancel();
            }
        }
        let result = self
            .connect_device_with_candidates(id, !automatic, token.clone(), discovered)
            .await;
        if let Some(attempt) = attempt_id {
            let mut pending = self.device_operations.lock().await;
            if !token.is_cancelled()
                || pending
                    .get(attempt)
                    .is_some_and(CancellationToken::is_cancelled)
            {
                pending.remove(attempt);
            }
        }
        result
    }
    async fn connect_device_with_candidates(
        &self,
        id: &str,
        request_authorization: bool,
        token: CancellationToken,
        discovered: Option<DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        if discovered.is_none()
            && !token.is_cancelled()
            && let Ok(client) = self.client(id).await
        {
            return Ok(
                json!({"connected":!client.is_closed(),"deviceId":id,"device":self.device(id).await?,"adbBurstActive":client.burst_mode()}),
            );
        }
        self.register_connection_operation(id, request_authorization, &token)
            .await?;
        self.connect_registered_candidates(id, request_authorization, token, discovered)
            .await
    }

    async fn register_connection_operation(
        &self,
        id: &str,
        request_authorization: bool,
        token: &CancellationToken,
    ) -> CoreResult<()> {
        let mut pending = self.device_operations.lock().await;
        let store = self.store.read().await;
        let record = store
            .devices
            .iter()
            .find(|d| d.id == id)
            .ok_or_else(|| CoreError::new("not_found", "设备记录已不存在。"))?;
        if token.is_cancelled()
            || (!request_authorization && (!record.auto_reconnect || record.status != "offline"))
        {
            return Err(CoreError::new(
                "cancelled",
                "连接已取消或已有连接正在处理。",
            ));
        }
        if let Some(previous) = pending.insert(id.into(), token.clone())
            && previous != *token
        {
            previous.cancel();
        }
        Ok(())
    }

    /// The caller already owns the device-operation slot. Retrying discovered
    /// addresses must not replace/cancel that same operation's token.
    async fn connect_registered_candidates(
        &self,
        id: &str,
        request_authorization: bool,
        token: CancellationToken,
        discovered: Option<DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        if token.is_cancelled() {
            return Err(CoreError::new("cancelled", "连接已取消。"));
        }
        if discovered.is_none()
            && let Ok(client) = self.client(id).await
        {
            return Ok(
                json!({"connected":!client.is_closed(),"deviceId":id,"device":self.device(id).await?,"adbBurstActive":client.burst_mode()}),
            );
        }
        let device = {
            let _pending = self.device_operations.lock().await;
            let mut store = self.store.write().await;
            let record = store
                .devices
                .iter_mut()
                .find(|d| d.id == id)
                .ok_or_else(|| CoreError::new("not_found", "设备记录已不存在。"))?;
            if token.is_cancelled()
                || (!request_authorization
                    && (!record.auto_reconnect || record.status != "offline"))
            {
                return Err(CoreError::new(
                    "cancelled",
                    "自动重连已取消或已有连接正在处理。",
                ));
            }
            if !record.transport.is_usb()
                && record.port == 0
                && discovered
                    .as_ref()
                    .and_then(|answer| answer.endpoints.as_ref())
                    .is_none_or(Vec::is_empty)
            {
                return Err(CoreError::new(
                    "connection_port_required",
                    "配对已完成，请填写无线调试页面上的连接端口，无需再次配对。",
                ));
            }
            record.status = "connecting".into();
            record.reason = None;
            record.auto_reconnect = true;
            record.clone()
        };
        self.changed_devices().await?;
        let mut attempt = async {
            let mut options = self.connect_options_for(Some(id), token.clone()).await?;
            let host_identity = crate::host_identity::fingerprint(
                options.identity.as_ref().expect("selected identity"),
            )?;
            options.request_authorization &= request_authorization;
            if device.transport.requires_tls(device.guid.as_deref()) {
                options.tls_policy = TlsPolicy::Required;
            }
            let (client, connected_endpoint) = if device.transport.is_usb() && discovered.is_none()
            {
                (self.connect_usb_record(&device, options).await?, None)
            } else if let Some((discovered, endpoints)) = discovered.as_ref().and_then(|answer| {
                answer
                    .endpoints
                    .as_ref()
                    .map(|endpoints| (answer, endpoints))
            }) {
                // Modern discovery never weakens the persisted trust policy.
                options.tls_policy = TlsPolicy::Required;
                // An unreachable interface must not consume the entire retry
                // window before another advertised address can be attempted.
                options.operations.timeout =
                    Duration::from_millis(self.connection_policy.endpoint_timeout_ms);
                let mut result = Err(CoreError::new("unreachable", "当前发现地址均不可达。"));
                for address in endpoints {
                    if token.is_cancelled() {
                        return Err(CoreError::new("cancelled", "连接已取消。"));
                    }
                    if !discovered.is_current().await {
                        return Err(discovery_changed());
                    }
                    match Client::connect_tcp(*address, options.clone()).await {
                        Ok(client) => {
                            result = Ok((client, Some(*address)));
                            break;
                        }
                        Err(interop_adb::Error::Cancelled) => {
                            return Err(CoreError::new("cancelled", "连接已取消。"));
                        }
                        Err(error) => {
                            // An obsolete socket's rejection must not disable
                            // automatic retries for the replacement endpoint.
                            if !discovered.is_current().await {
                                return Err(discovery_changed());
                            }
                            let error = CoreError::from(error);
                            if authorization_failed(&error) {
                                return Err(error);
                            }
                            result = Err(error);
                        }
                    }
                }
                result?
            } else {
                (
                    Client::connect_tcp(endpoint(&device.address, device.port), options).await?,
                    None,
                )
            };
            let mut info = metadata(&client, token.clone()).await;
            info.host_identity = Some(host_identity);
            self.attach_client(
                id,
                client,
                info,
                &token,
                connected_endpoint,
                discovered.as_ref(),
            )
            .await
        }
        .await;
        if attempt.is_err() {
            let pending = self.device_operations.lock().await;
            if !token.is_cancelled() || pending.get(id).is_some_and(CancellationToken::is_cancelled)
            {
                let mut store = self.store.write().await;
                // Take the discovery guard after waiting for the publication
                // locks: an old socket's rejection cannot revoke retries for a
                // newer answer that arrived during those waits.
                let services = if let Some(discovered) = &discovered {
                    let services = discovered.services.read().await;
                    if services.generation(&discovered.guid) != discovered.generation
                        && !token.is_cancelled()
                    {
                        attempt = Err(discovery_changed());
                    }
                    Some(services)
                } else {
                    None
                };
                let error = attempt.as_ref().expect_err("failed connection attempt");
                if let Some(record) = store.devices.iter_mut().find(|d| d.id == id) {
                    let unauthorized = authorization_failed(error);
                    record.status = if unauthorized {
                        "unauthorized"
                    } else {
                        "offline"
                    }
                    .into();
                    record.reason = Some(error.message.clone());
                    if unauthorized || (token.is_cancelled() && request_authorization) {
                        record.auto_reconnect = false;
                    }
                }
                drop(services);
            }
            drop(pending);
            self.changed_devices().await?;
        }
        attempt
    }
    async fn retire_closed_connection(&self, id: &str) -> CoreResult<()> {
        let mut transition = self.connections.transition(id).await;
        self.retire_closed_connection_locked(id, &mut transition)
            .await
    }

    async fn retire_closed_connection_locked(
        &self,
        id: &str,
        cleanup_pending: &mut tokio::sync::OwnedMutexGuard<bool>,
    ) -> CoreResult<()> {
        {
            // Match attach_client's store -> connections lock order. Recheck
            // after acquiring the transition: a stale monitor list is not
            // authority to remove a healthy replacement or write it offline.
            let mut store = self.store.write().await;
            let mut connections = self.connections.lock().await;
            if connections.get(id).is_some_and(Client::is_closed) {
                **cleanup_pending = true;
                connections.remove(id);
                if let Some(record) = store.devices.iter_mut().find(|device| device.id == id) {
                    record.status = "offline".into();
                    record.reason =
                        Some("设备连接已中断，活动已停止；将按重连设置恢复连接。".into());
                }
            }
        }
        if **cleanup_pending {
            self.stop_device_activities(id).await?;
            self.changed_devices().await?;
            **cleanup_pending = false;
        }
        Ok(())
    }

    pub(crate) async fn attach_client(
        &self,
        id: &str,
        client: Client,
        info: Metadata,
        token: &CancellationToken,
        connected_endpoint: Option<SocketAddr>,
        discovered: Option<&DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        self.attach_client_at(
            id,
            client,
            info,
            token,
            connected_endpoint.map(AttachedEndpoint::Tls),
            discovered,
        )
        .await
    }

    pub(crate) async fn attach_tcpip_client(
        &self,
        id: &str,
        client: Client,
        info: Metadata,
        token: &CancellationToken,
        endpoint: (String, u16),
    ) -> CoreResult<Value> {
        self.attach_client_at(
            id,
            client,
            info,
            token,
            Some(AttachedEndpoint::Tcp {
                address: endpoint.0,
                port: endpoint.1,
            }),
            None,
        )
        .await
    }

    async fn attach_client_at(
        &self,
        id: &str,
        client: Client,
        info: Metadata,
        token: &CancellationToken,
        connected_endpoint: Option<AttachedEndpoint>,
        discovered: Option<&DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        // A connected record admits new video, audio and helper work. Finish
        // the old connection's device-wide cleanup before publishing it.
        let mut transition = self.connections.transition(id).await;
        self.retire_closed_connection_locked(id, &mut transition)
            .await?;
        if token.is_cancelled() {
            client.close();
            return Err(CoreError::new("cancelled", "连接配置已取消。"));
        }
        if connected_endpoint.is_some() {
            if let Ok(original) = self.device(id).await
                && original.serial.is_some()
                && let Err(error) = verify_same_target(&original, &info)
            {
                client.close();
                return Err(error);
            }
            let retired = self.connections.lock().await.remove(id);
            if let Some(retired) = retired {
                retired.close();
                *transition = true;
                {
                    let mut store = self.store.write().await;
                    if let Some(record) = store.devices.iter_mut().find(|d| d.id == id) {
                        record.status = "offline".into();
                    }
                }
                self.stop_device_activities(id).await?;
                *transition = false;
            }
        }
        let _pending = self.device_operations.lock().await;
        if token.is_cancelled() {
            client.close();
            return Err(CoreError::new("cancelled", "连接已取消。"));
        }
        if client.is_closed() {
            return Err(CoreError::new(
                "disconnected",
                "设备在读取连接信息时已断开。",
            ));
        }
        let identity_state = self.identities.state.read().await;
        if let Some(expected) = &info.host_identity
            && let Err(error) = identity_state.validate(id, expected)
        {
            client.close();
            return Err(error);
        }
        let burst_active = client.burst_mode();
        let metadata_client = client.clone();
        let device = {
            let mut store = self.store.write().await;
            // Keep the generation check atomic with the record/client update.
            // Even a cached attempt has a baseline, and withdraw/reannounce at
            // the same address is a new generation rather than the old answer.
            let _services = if let Some(discovered) = discovered {
                let services = discovered.services.read().await;
                if services.generation(&discovered.guid) != discovered.generation {
                    client.close();
                    return Err(discovery_changed());
                }
                Some(services)
            } else {
                None
            };
            if matches!(
                connected_endpoint,
                Some(AttachedEndpoint::Usb { create: true })
            ) {
                if store.devices.iter().any(|d| d.id == id) {
                    client.close();
                    return Err(CoreError::new("device_exists", "设备记录已存在。"));
                }
                let mut created = blank_device(String::new(), 0, TransportKind::Usb);
                created.id = id.to_owned();
                store.devices.push(created);
            }
            let record = store
                .devices
                .iter_mut()
                .find(|d| d.id == id)
                .ok_or_else(|| CoreError::new("not_found", "设备记录已移除。"))?;
            if let (Some(known), Some(actual)) = (&record.serial, &info.serial)
                && known != actual
            {
                client.close();
                return Err(CoreError::new(
                    "device_identity_mismatch",
                    "连接地址上的设备序列号与原记录不同，请作为另一台设备添加。",
                ));
            }
            if record.name == "Android 设备"
                && let Some(model) = &info.model
            {
                record.name = model.clone();
            }
            if info.model.is_some() {
                record.model = info.model;
            }
            if info.release.is_some() {
                record.android_version = info.release;
            }
            if info.api.is_some() {
                record.api_level = info.api;
            }
            if info.serial.is_some() {
                record.serial = info.serial;
            }
            match connected_endpoint {
                Some(AttachedEndpoint::Usb { .. }) => {
                    record.transport = TransportKind::Usb;
                }
                Some(AttachedEndpoint::Tls(endpoint)) => {
                    if let Some(discovered) = discovered {
                        record.guid = Some(discovered.guid.clone());
                    }
                    record.address = address_of(endpoint);
                    record.port = endpoint.port();
                    record.transport = TransportKind::Tls;
                }
                Some(AttachedEndpoint::Tcp { address, port }) => {
                    // Commit an explicit TCP transition only with the verified,
                    // live client, under the same identity and cancellation fence.
                    record.address = address;
                    record.port = port;
                    record.transport = TransportKind::Tcp;
                    record.guid = None;
                }
                Some(AttachedEndpoint::Configured {
                    address,
                    port,
                    transport,
                }) => {
                    record.address = address;
                    record.port = port;
                    record.transport = transport;
                }
                None => {}
            }
            record.battery = info.battery;
            record.charging = None;
            record.battery_updated_at = None;
            record.status = "connected".into();
            record.reason = info.error;
            record.auto_reconnect = true;
            record.last_seen = Some(now());
            let mut clients = self.connections.lock().await;
            if let Some(old) = clients.insert(id.into(), client) {
                old.close();
            }
            record.clone()
        };
        drop(identity_state);
        drop(_pending);
        self.observation_connection_changed(id).await;
        self.changed_devices().await?;
        {
            let store = self.store.read().await;
            if let Some(current) = store.devices.iter().find(|device| device.id == id) {
                self.emit("device.changed", Some(id), json!(current));
            }
        }
        let _ = self
            .metadata_updates
            .try_send(crate::device_metadata::Request {
                id: id.to_owned(),
                client: metadata_client,
            });
        Ok(json!({"connected":true,"deviceId":id,"device":device,"adbBurstActive":burst_active}))
    }
    pub(crate) async fn disconnect_device(&self, id: &str, forget: bool) -> CoreResult<Value> {
        let mut cleanup_pending = self.connections.transition(id).await;
        self.device(id).await?;
        let _detached = DetachedConnection({
            let mut pending = self.device_operations.lock().await;
            if let Some(token) = pending.remove(id) {
                token.cancel();
            }
            let mut store = self.store.write().await;
            let mut connections = self.connections.lock().await;
            *cleanup_pending = true;
            if let Some(record) = store.devices.iter_mut().find(|d| d.id == id) {
                record.auto_reconnect = false;
                record.status = "offline".into();
                record.reason = None;
            }
            connections.remove(id)
        });
        self.stop_device_activities(id).await?;
        if forget {
            let mut store = self.store.write().await;
            store.devices.retain(|d| d.id != id);
            store.device_identity_fingerprints.remove(id);
            if let Some(quality) = store.settings["deviceQuality"].as_object_mut() {
                quality.remove(id);
            }
            if let Some(settings) = store.settings["deviceSettings"].as_object_mut() {
                settings.remove(id);
            }
        }
        self.changed_devices().await?;
        if forget {
            self.forget_observation(id).await;
            // Persistence can wait behind newer settings writes. Publish the
            // current projection under its guard, never a pre-wait clone.
            let store = self.store.read().await;
            self.emit("settings.changed", None, store.settings.clone());
        }
        *cleanup_pending = false;
        drop(cleanup_pending);
        if forget {
            self.forget_device_identity(id).await?;
        }
        Ok(json!({"deviceId":id,"disconnected":true,"forgotten":forget}))
    }
    pub(crate) async fn discover_devices(&self) -> CoreResult<Value> {
        let discovery = Discovery::new()?;
        let timeout = Duration::from_millis(self.connection_policy.discovery_timeout_ms);
        let options = OperationOptions {
            timeout,
            cancellation: CancellationToken::new(),
        };
        let deadline = Instant::now() + timeout;
        let mut found = HashMap::<String, Service>::new();
        while Instant::now() < deadline {
            let remaining = deadline.saturating_duration_since(Instant::now());
            match tokio::time::timeout(remaining, discovery.next(&options)).await {
                Ok(Ok(DiscoveryEvent::Resolved(service))) => {
                    found.insert(service.fullname.clone(), service);
                }
                Ok(Ok(DiscoveryEvent::Removed { fullname })) => {
                    found.remove(&fullname);
                }
                Ok(Err(interop_adb::Error::Timeout)) | Err(_) => break,
                Ok(Err(error)) => return Err(error.into()),
            }
        }
        let known = self.store.read().await.devices.clone();
        let devices = found.values().map(|service| {
            let trusted = if service.kind == ServiceKind::Connect { known.iter().find(|device|device.guid.as_ref().is_some_and(|guid|matches_guid(&service.instance,guid))) } else { None };
            json!({"instance":service.instance,"hostname":service.hostname,
            "fullname":service.fullname,"kind":match service.kind {ServiceKind::Pairing=>"pairing",ServiceKind::Connect=>"tls",ServiceKind::Legacy=>"tcp"},
            "endpoints":service.endpoints.iter().map(|address| json!({"address":address_of(*address),"port":address.port()})).collect::<Vec<_>>(),
            "properties":service.properties,"trusted":trusted.is_some(),"deviceId":trusted.map(|device|&device.id)})
        }).collect::<Vec<_>>();
        Ok(json!({"devices":devices,"manualConnectionAvailable":true}))
    }
    pub(crate) async fn pair_device(&self, params: &Value) -> CoreResult<Value> {
        let explicit = params["deviceId"].as_str();
        if let Some(id) = explicit {
            self.device(id).await?;
        }
        let address = host(params)?;
        let port = port(params)?;
        let code = required(params, "code")?;
        if code.len() != 6 || !code.bytes().all(|b| b.is_ascii_digit()) {
            return Err(CoreError::new(
                "invalid_pairing_code",
                "请输入设备当前显示的六位配对码。",
            ));
        }
        let (material, dedicated) = self.identities.for_attempt(params, explicit).await?;
        let op = self
            .new_setup_operation(params, explicit, material.fingerprint.clone())
            .await?;
        if dedicated {
            let _ = op.dedicated_identity.set(material.clone());
        }
        let options = OperationOptions {
            timeout: Duration::from_millis(self.connection_policy.pairing_timeout_ms),
            cancellation: op.token.clone(),
        };
        let result = async {
            let paired = tokio::select! {
                _ = op.token.cancelled() => return Err(CoreError::new("cancelled", "配对执行已取消。")),
                result = tokio::time::timeout(options.timeout, async {
                    let tls = material.tls().await?;
                    let socket = tokio::net::TcpStream::connect(endpoint(&address, port)).await?;
                    Ok::<_,CoreError>(wireless::pair(socket, code, &material.identity, &tls, &self.connection_policy.public_key_comment, &options).await?)
                }) => result.map_err(|_|CoreError::new("timeout", "配对执行超时。"))??,
            };
            self.finish_pairing_record(paired.guid, address, explicit, &op).await
        }.await;
        self.setup_outcome(&op, &result);
        result
    }
    #[cfg(test)]
    async fn finish_pairing(
        &self,
        guid: String,
        address: String,
        explicit: Option<&str>,
        token: &CancellationToken,
    ) -> CoreResult<Value> {
        let material = self.identities.selected(explicit).await?;
        let op = self
            .new_setup_operation(
                &json!({"attemptId":uuid::Uuid::new_v4().to_string(),"leaseMs":180000}),
                explicit,
                material.fingerprint.clone(),
            )
            .await?;
        if token.is_cancelled() {
            op.cancel();
        }
        self.finish_pairing_record(guid, address, explicit, &op)
            .await
    }
    async fn finish_pairing_record(
        &self,
        guid: String,
        address: String,
        explicit: Option<&str>,
        op: &crate::connection_setup::SetupOperation,
    ) -> CoreResult<Value> {
        op.check()?;
        let existing = {
            let store = self.store.read().await;
            if let Some(id) = explicit {
                Some(
                    store
                        .devices
                        .iter()
                        .find(|d| d.id == id)
                        .ok_or_else(|| CoreError::new("not_found", "设备记录已移除。"))?
                        .clone(),
                )
            } else {
                store
                    .devices
                    .iter()
                    .find(|d| d.guid.as_deref() == Some(&guid))
                    .cloned()
            }
        };
        if let Some(record) = &existing
            && record.guid.as_ref().is_some_and(|known| known != &guid)
        {
            return Err(CoreError::new(
                "device_identity_mismatch",
                "配对的是另一台设备。",
            ));
        }
        let mut created = blank_device(address.clone(), 0, TransportKind::Tls);
        created.guid = Some(guid.clone());
        let target_id = existing
            .as_ref()
            .map(|d| d.id.as_str())
            .unwrap_or(&created.id)
            .to_owned();
        if existing.is_none()
            && let Some(material) = op.dedicated_identity.get()
        {
            self.identities
                .bind_new(&self.root, &target_id, material.clone())
                .await?;
        }
        let outcome = async {
        let identity = self.identities.state.read().await;
        if op.dedicated_identity.get().is_none()
            && identity.selected(explicit)?.fingerprint != op.identity
        {
            return Err(CoreError::new("identity_changed", "配对授权身份已改变。"));
        }
        identity.validate(&target_id, &op.identity)?;
        let mut pending = self.device_operations.lock().await;
        let id = {
            let mut store = self.store.write().await;
            op.check()?;
            if existing.is_none() {
                // Concurrent pairing to the same GUID must not create duplicates.
                if store
                    .devices
                    .iter()
                    .any(|d| d.guid.as_deref() == Some(&guid))
                {
                    return Err(CoreError::new(
                        "device_exists",
                        "此设备已配对，请打开原设备记录。",
                    ));
                }
                if op.dedicated_identity.get().is_some() {
                    store
                        .device_identity_fingerprints
                        .insert(target_id.clone(), op.identity.clone());
                }
                store.devices.push(created);
            }
            target_id.clone()
        };
        *op.device.lock().expect("operation device poisoned") = Some(id.clone());
        if let Some(old) = pending.insert(id.clone(), op.token.clone())
            && old != op.token
        {
            old.cancel();
        }
        drop(pending);
        drop(identity);
        let discovery = self.start_pairing_discovery(&guid, &op.token).await?;
        *op.resource.lock().expect("operation resource poisoned") =
            crate::connection_setup::PendingResource::Pairing(discovery);
        self.changed_devices().await?;
        Ok(
            json!({"paired":true,"deviceId":id,"address":address,"device":self.device(&id).await?,"connected":false,"operationId":op.id}),
        )
        }.await;
        if outcome.is_err()
            && existing.is_none()
            && op.dedicated_identity.get().is_some()
            && self.device(&target_id).await.is_err()
        {
            self.forget_device_identity(&target_id).await?;
        }
        outcome
    }
    async fn start_pairing_discovery(
        &self,
        guid: &str,
        token: &CancellationToken,
    ) -> CoreResult<PairingDiscovery> {
        let discovery = Discovery::new()?;
        let trusted: HashSet<String> = self
            .store
            .read()
            .await
            .devices
            .iter()
            .filter_map(|d| d.guid.clone())
            .collect();
        // A reauthorization candidate is only trusted by its own operation.
        // Persisted reconnection state must not acquire that GUID before the
        // candidate's live target has been verified against the original.
        let (services, trusted) = if trusted.contains(guid) {
            (self.discovered_services.clone(), trusted)
        } else {
            (
                Arc::new(tokio::sync::RwLock::new(DiscoveredState::default())),
                HashSet::from([guid.to_owned()]),
            )
        };
        services.write().await.sync_trusted(trusted);
        let observed = services.clone();
        let options = OperationOptions {
            timeout: Duration::from_secs(60),
            cancellation: token.clone(),
        };
        // This task only observes protocol announcements; it never connects,
        // retries a connection, or decides what the application should do next.
        let task = tokio::spawn(async move {
            loop {
                match discovery.next(&options).await {
                    Ok(event) => {
                        observed.write().await.observe(event);
                    }
                    Err(interop_adb::Error::Timeout) => continue,
                    Err(_) => break,
                }
            }
        });
        Ok(PairingDiscovery {
            services,
            guid: guid.into(),
            task,
        })
    }
    pub(crate) async fn usb_open(&self, params: &Value) -> CoreResult<Value> {
        #[cfg(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        ))]
        {
            let explicit = params["deviceId"].as_str();
            if let Some(id) = explicit {
                self.device(id).await?;
            }
            let (material, dedicated) = self.identities.for_attempt(params, explicit).await?;
            let op = self
                .new_setup_operation(params, explicit, material.fingerprint.clone())
                .await?;
            if dedicated {
                let _ = op.dedicated_identity.set(material.clone());
            }
            let result = async {
                let options = self
                    .connect_options_with_material(material.clone(), op.token.clone())
                    .await?;
                let transport = if params.get("fd").is_some() {
                    #[cfg(any(target_os = "linux", target_os = "android"))]
                    {
                        use std::os::fd::FromRawFd;
                        let fd = params["fd"]
                            .as_i64()
                            .and_then(|v| i32::try_from(v).ok())
                            .filter(|v| *v >= 0)
                            .ok_or_else(|| CoreError::new("invalid_fd", "USB描述符无效。"))?;
                        // The Java lease remains alive until the caller acknowledges
                        // this execution. Rust only owns this duplicate.
                        let duplicate = unsafe { libc::fcntl(fd, libc::F_DUPFD_CLOEXEC, 0) };
                        if duplicate < 0 {
                            return Err(std::io::Error::last_os_error().into());
                        }
                        let owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(duplicate) };
                        interop_adb::usb::from_owned_fd(owned, options.operations.clone()).await?
                    }
                    #[cfg(not(any(target_os = "linux", target_os = "android")))]
                    {
                        return Err(CoreError::new(
                            "unsupported_platform",
                            "当前宿主不接收USB描述符。",
                        ));
                    }
                } else {
                    let devices =
                        interop_adb::usb::list_devices(options.operations.clone()).await?;
                    op.check()?;
                    let ids = devices.iter().map(|device| device.id()).collect::<Vec<_>>();
                    let index = select_usb_device(&ids, params["usbDeviceId"].as_str())?;
                    let Some(index) = index else {
                        let devices = devices
                            .iter()
                            .map(|device| {
                                json!({
                                    "usbDeviceId": device.id(),
                                    "name": device.product_name(),
                                    "serial": device.serial_number(),
                                    "vendorId": device.vendor_id(),
                                    "productId": device.product_id(),
                                })
                            })
                            .collect::<Vec<_>>();
                        return Ok(json!({"selectionRequired":true,"devices":devices}));
                    };
                    devices[index].open(options.operations.clone()).await?
                };
                let client = Client::connect_transport(transport, options).await?;
                let mut info = metadata(&client, op.token.clone()).await;
                info.host_identity = Some(op.identity.clone());
                if op.check().is_err() || client.is_closed() {
                    client.close();
                    return Err(CoreError::new("cancelled", "USB执行已结束。"));
                }
                let facts = json!({"operationId":op.id,"metadata":info});
                *op.resource.lock().expect("operation resource poisoned") =
                    crate::connection_setup::PendingResource::Usb {
                        client: Some(client),
                        info,
                    };
                op.check()?;
                Ok(facts)
            }
            .await;
            self.setup_outcome(&op, &result);
            // Neither selection receipts nor errors hand an operation ID to
            // Dart. Reclaim their lease immediately, including cancellation.
            if result.is_err()
                || result
                    .as_ref()
                    .is_ok_and(|value| value["selectionRequired"] == true)
            {
                self.setup_operations.release_alias(&op.id).await;
                self.device_operations
                    .lock()
                    .await
                    .retain(|_, current| current != &op.token);
            }
            result
        }
        #[cfg(not(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        )))]
        {
            let _ = params;
            Err(CoreError::new(
                "unsupported_platform",
                "当前宿主不支持USB连接。",
            ))
        }
    }
    pub(crate) async fn usb_attach(&self, params: &Value) -> CoreResult<Value> {
        let op = self
            .setup_operations
            .get(required(params, "operationId")?)
            .await?;
        let _execution = op
            .execution
            .try_lock()
            .map_err(|_| CoreError::new("operation_busy", "执行正在进行。"))?;
        let explicit = params["deviceId"].as_str();
        if op
            .device_id()
            .as_deref()
            .is_some_and(|id| Some(id) != explicit)
        {
            return Err(CoreError::new(
                "device_identity_mismatch",
                "执行绑定了另一条设备记录。",
            ));
        }
        let (client, info) = {
            let mut resource = op.resource.lock().expect("operation resource poisoned");
            match &mut *resource {
                crate::connection_setup::PendingResource::Usb { client, info } => (
                    client.take().ok_or_else(|| {
                        CoreError::new("operation_consumed", "USB连接已接入或释放。")
                    })?,
                    info.clone(),
                ),
                _ => {
                    return Err(CoreError::new(
                        "invalid_operation",
                        "执行不是待接入USB连接。",
                    ));
                }
            }
        };
        let guarded = client.clone();
        let result = async {
            op.check()?;
            let id = if let Some(id) = explicit {
                self.device(id).await?;
                id.to_owned()
            } else {
                uuid::Uuid::new_v4().to_string()
            };
            if explicit.is_none() {
                if let Some(material) = op.dedicated_identity.get() {
                    self.identities
                        .bind_new(&self.root, &id, material.clone())
                        .await?;
                    self.store
                        .write()
                        .await
                        .device_identity_fingerprints
                        .insert(id.clone(), material.fingerprint.clone());
                }
            } else {
                let original = self.device(&id).await?;
                verify_same_target(&original, &info)?;
            }
            *op.device.lock().expect("operation device poisoned") = Some(id.clone());
            {
                let mut pending = self.device_operations.lock().await;
                op.check()?;
                if let Some(old) = pending.insert(id.clone(), op.token.clone())
                    && old != op.token
                {
                    old.cancel();
                }
            }
            let receipt = self
                .attach_client_at(
                    &id,
                    client,
                    info,
                    &op.token,
                    Some(AttachedEndpoint::Usb {
                        create: explicit.is_none(),
                    }),
                    None,
                )
                .await?;
            Ok(receipt)
        }
        .await;
        if result.is_err() {
            guarded.close();
        }
        self.setup_outcome(&op, &result);
        result
    }
    async fn connect_usb_record(
        &self,
        device: &Device,
        options: ConnectOptions,
    ) -> CoreResult<Client> {
        #[cfg(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        ))]
        {
            if cfg!(target_os = "android") {
                return Err(CoreError::new(
                    "usb_permission_required",
                    "USB 连接需要主控系统重新提供授权描述符；无需开启主控调试。",
                ));
            }
            let serial = device.serial.as_deref().ok_or_else(|| {
                CoreError::new(
                    "usb_selection_required",
                    "设备没有可核验的 USB 序列号，请重新选择并授权。",
                )
            })?;
            let devices = interop_adb::usb::list_devices(options.operations.clone()).await?;
            let matches = devices
                .iter()
                .filter(|d| d.serial_number() == Some(serial))
                .collect::<Vec<_>>();
            if matches.len() != 1 {
                return Err(CoreError::new(
                    "usb_disconnected",
                    "USB 设备已断开或需要重新选择。",
                ));
            }
            let transport = matches[0].open(options.operations.clone()).await?;
            Ok(Client::connect_transport(transport, options).await?)
        }
        #[cfg(not(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        )))]
        {
            let _ = (device, options);
            Err(CoreError::new(
                "unsupported_platform",
                "此平台的 USB 后端尚未实现。",
            ))
        }
    }
    pub(crate) async fn device_sleeping(&self, id: &str) -> CoreResult<Option<bool>> {
        let client = self.client(id).await?;
        let output = client
            .shell(
                "dumpsys power | sed -n 's/^ *mWakefulness=//p'",
                4096,
                operations(5, CancellationToken::new()),
            )
            .await?;
        Ok(match String::from_utf8_lossy(&output.stdout).trim() {
            "Asleep" | "Dozing" => Some(true),
            "Awake" | "Dreaming" => Some(false),
            // An unrecognized OEM dump is unknown, never evidence of sleep.
            _ => None,
        })
    }

    pub(crate) async fn wake_device(
        &self,
        id: &str,
        connection_id: Option<&str>,
    ) -> CoreResult<Value> {
        let _transition = self.connections.transition(id).await;
        let client = self.client(id).await?;
        if connection_id.is_some_and(|expected| expected != client.connection_id().to_string()) {
            return Err(CoreError::new(
                "stale_connection",
                "设备连接已替换，已放弃旧连接的唤醒请求。",
            ));
        }
        let output = client
            .shell(
                "input keyevent 224",
                4096,
                operations(5, CancellationToken::new()),
            )
            .await
            .map_err(|error| {
                CoreError::new(
                    "result_unknown",
                    format!("唤醒请求结果未知，请查看手机状态后再决定是否重试。{error}"),
                )
            })?;
        if output.exit_code.is_some_and(|code| code != 0) {
            return Err(CoreError::new(
                "wake_failed",
                "手机系统未接受唤醒请求，请在被控手机上手动唤醒。",
            ));
        }
        let sleeping = self.device_sleeping(id).await.unwrap_or(None);
        Ok(
            json!({"deviceId":id,"requested":true,"awake":sleeping.map(|value|!value),
            "reason":"仅请求系统唤醒，仍使用手机自身的锁屏与解锁方式。"}),
        )
    }

    pub(crate) async fn schedule_connection_cleanup(self: &Arc<Self>) {
        for id in self.connections.pending_retirements().await {
            let owner = self.clone();
            self.connections
                .schedule_retirement(id.clone(), async move {
                    let _ = owner.retire_closed_connection(&id).await;
                });
        }
    }

    pub(crate) fn spawn_connection_monitor(self: &Arc<Self>) {
        let interval = Duration::from_millis(self.connection_policy.monitor_interval_ms);
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            let mut health = crate::connection_health::ConnectionHealth::default();
            let discovery = Discovery::new().ok();
            loop {
                tokio::time::sleep(interval).await;
                let Some(runtime) = weak.upgrade() else {
                    break;
                };
                // Native work owns protocol liveness and retirement, never a
                // product retry timer or an automatic connection attempt.
                health.tick(
                    &*runtime.connections.lock().await,
                    &runtime.connection_policy,
                );
                runtime.schedule_connection_cleanup().await;
                let trusted = runtime
                    .store
                    .read()
                    .await
                    .devices
                    .iter()
                    .filter(|device| !device.transport.is_usb())
                    .filter_map(|device| device.guid.clone())
                    .filter(|guid| !guid.is_empty())
                    .collect();
                runtime
                    .discovered_services
                    .write()
                    .await
                    .sync_trusted(trusted);
                if let Some(discovery) = &discovery {
                    let options = operations(1, CancellationToken::new());
                    for _ in 0..8 {
                        let Ok(Ok(event)) = tokio::time::timeout(
                            Duration::from_millis(5),
                            discovery.next(&options),
                        )
                        .await
                        else {
                            break;
                        };
                        if let Some(guid) = runtime.discovered_services.write().await.observe(event)
                        {
                            runtime.emit("adb.discovery.changed", None, json!({"guid": guid}));
                        }
                    }
                }
            }
        });
    }
}
