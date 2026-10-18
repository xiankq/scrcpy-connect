//! Persistent device identity and live connection lifecycle. Network locations
//! never serve as device identifiers; discovery changes endpoints, not trust.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{Device, TransportKind, now, required},
};
use interop_adb::{
    Client, ConnectOptions, OperationOptions, TlsPolicy,
    wireless::{
        self, QrPairing, TlsConfig,
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

type DiscoveredServices = Arc<tokio::sync::RwLock<DiscoveredState>>;

const MAX_DISCOVERED_SERVICES_PER_GUID: usize = 8;

#[derive(Default)]
struct DiscoveredDevice {
    generation: u64,
    observed: bool,
    services: HashMap<String, Service>,
}

#[derive(Default)]
struct DiscoveredState {
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

struct DiscoveredAttempt {
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
struct PairingDiscovery {
    services: DiscoveredServices,
    guid: String,
    task: tokio::task::JoinHandle<()>,
}

impl PairingDiscovery {
    async fn attempt(&self) -> DiscoveredAttempt {
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
    error.code == "authorization_required"
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

fn host(params: &Value) -> CoreResult<String> {
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
fn port(params: &Value) -> CoreResult<u16> {
    params
        .get("port")
        .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
        .and_then(|p| u16::try_from(p).ok())
        .filter(|p| *p != 0)
        .ok_or_else(|| CoreError::new("invalid_port", "端口必须是 1 到 65535 之间的数字。"))
}
fn endpoint(address: &str, port: u16) -> String {
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

#[derive(Default)]
struct Metadata {
    model: Option<String>,
    release: Option<String>,
    api: Option<u32>,
    serial: Option<String>,
    battery: Option<u32>,
    error: Option<String>,
}
fn nonempty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "unknown" && *s != "null")
        .map(str::to_owned)
}
async fn metadata(client: &Client, token: CancellationToken) -> Metadata {
    let command = "getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.serialno; dumpsys battery";
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
    let rest = lines.collect::<Vec<_>>();
    let number = |key: &str| {
        rest.iter()
            .find_map(|line| line.trim().strip_prefix(key)?.trim().parse::<u32>().ok())
    };
    let battery = number("level:").and_then(|level| {
        number("scale:")
            .filter(|n| *n > 0)
            .map(|scale| (u64::from(level) * 100 / u64::from(scale)).min(100) as u32)
    });
    Metadata {
        model,
        release,
        api,
        serial,
        battery,
        error: None,
    }
}

impl Runtime {
    async fn changed_devices(&self) -> CoreResult<()> {
        self.persist().await?;
        self.emit(
            "devices.changed",
            None,
            json!({"devices": self.store.read().await.devices}),
        );
        Ok(())
    }
    async fn tls_config(&self) -> CoreResult<TlsConfig> {
        let identity = self.identity.clone();
        tokio::task::spawn_blocking(move || TlsConfig::experimental_rustcrypto(&identity))
            .await
            .map_err(|e| CoreError::new("tls_error", e.to_string()))?
            .map_err(Into::into)
    }
    async fn connect_options(&self, token: CancellationToken) -> CoreResult<ConnectOptions> {
        Ok(ConnectOptions {
            identity: Some(self.identity.clone()),
            tls: Some(self.tls_config().await?),
            tls_policy: TlsPolicy::Optional,
            request_authorization: true,
            public_key_comment: "interop-controller".into(),
            // Match upstream's experimental, opt-in rollout. Each new
            // transport negotiates independently; an existing client keeps
            // its wire format until it is explicitly disconnected.
            burst_mode: self.store.read().await.settings["adbBurstMode"] == true,
            operations: operations(60, token),
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
                let record = blank_device(address, port, transport.unwrap_or(TransportKind::Tcp));
                store.devices.push(record.clone());
                record
            }
        };
        self.changed_devices().await?;
        Ok(json!({"deviceId":device.id,"device":device}))
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
    ) -> CoreResult<Value> {
        if attempt_id.is_some_and(|attempt| {
            attempt.is_empty() || attempt == id || attempt.contains('\0') || attempt.len() > 200
        }) {
            return Err(CoreError::new("invalid_argument", "连接尝试标识无效。"));
        }
        let token = CancellationToken::new();
        if let Some(attempt) = attempt_id {
            let mut pending = self.device_operations.lock().await;
            if let Some(previous) = pending.insert(attempt.into(), token.clone()) {
                previous.cancel();
            }
        }
        let result = self
            .connect_device_with_token(id, true, token.clone())
            .await;
        if let Some(attempt) = attempt_id {
            let mut pending = self.device_operations.lock().await;
            if !token.is_cancelled() {
                pending.remove(attempt);
            }
        }
        result
    }
    async fn connect_device_with_token(
        &self,
        id: &str,
        request_authorization: bool,
        token: CancellationToken,
    ) -> CoreResult<Value> {
        Box::pin(self.connect_device_with_candidates(id, request_authorization, token, None)).await
    }
    async fn connect_device_with_candidates(
        &self,
        id: &str,
        request_authorization: bool,
        token: CancellationToken,
        discovered: Option<DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        if !token.is_cancelled()
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
        if let Some(previous) = pending.insert(id.into(), token.clone()) {
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
        if let Ok(client) = self.client(id).await {
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
            let mut options = self.connect_options(token.clone()).await?;
            options.request_authorization = request_authorization;
            if device.transport.requires_tls(device.guid.as_deref()) {
                options.tls_policy = TlsPolicy::Required;
            }
            let (client, connected_endpoint) = if device.transport.is_usb() {
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
                options.operations.timeout = Duration::from_secs(5);
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
            let info = metadata(&client, token.clone()).await;
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
                    if unauthorized || token.is_cancelled() {
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

    async fn attach_client(
        &self,
        id: &str,
        client: Client,
        info: Metadata,
        token: &CancellationToken,
        connected_endpoint: Option<SocketAddr>,
        discovered: Option<&DiscoveredAttempt>,
    ) -> CoreResult<Value> {
        // A connected record admits new video, audio and helper work. Finish
        // the old connection's device-wide cleanup before publishing it.
        let mut transition = self.connections.transition(id).await;
        self.retire_closed_connection_locked(id, &mut transition)
            .await?;
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
        let burst_active = client.burst_mode();
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
            if let Some(endpoint) = connected_endpoint {
                record.address = address_of(endpoint);
                record.port = endpoint.port();
                record.transport = TransportKind::Tls;
            }
            record.battery = info.battery;
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
        drop(_pending);
        self.observation_connection_changed(id).await;
        self.changed_devices().await?;
        {
            let store = self.store.read().await;
            if let Some(current) = store.devices.iter().find(|device| device.id == id) {
                self.emit("device.changed", Some(id), json!(current));
            }
        }
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
            if let Some(quality) = store.settings["deviceQuality"].as_object_mut() {
                quality.remove(id);
            }
            if let Some(audio) = store.settings["audioDevices"].as_array_mut() {
                audio.retain(|value| value.as_str() != Some(id));
            }
            if store.settings["clipboardDevice"] == id {
                store.settings["clipboardDevice"] = Value::Null;
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
        Ok(json!({"deviceId":id,"disconnected":true,"forgotten":forget}))
    }
    pub(crate) async fn discover_devices(&self) -> CoreResult<Value> {
        let discovery = Discovery::new()?;
        let options = operations(3, CancellationToken::new());
        let deadline = Instant::now() + Duration::from_secs(3);
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
        if let Some(id) = params.get("deviceId").and_then(Value::as_str) {
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
        let attempt_id = params
            .get("attemptId")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        if attempt_id.is_empty()
            || attempt_id.len() > 200
            || attempt_id.contains('\0')
            || self
                .store
                .read()
                .await
                .devices
                .iter()
                .any(|device| device.id == attempt_id)
        {
            return Err(CoreError::new("invalid_argument", "配对尝试标识无效。"));
        }
        let token = CancellationToken::new();
        if let Some(old) = self
            .device_operations
            .lock()
            .await
            .insert(attempt_id.clone(), token.clone())
        {
            old.cancel();
        }
        self.emit(
            "pairing.changed",
            None,
            json!({"status":"waiting","attemptId":attempt_id}),
        );
        let options = operations(60, token.clone());
        let result: CoreResult<wireless::PairingResult> = tokio::select! {
            biased;
            _ = token.cancelled() => Err(CoreError::new("cancelled","配对操作已取消。")),
            result = tokio::time::timeout(options.timeout,async {
                let tls = self.tls_config().await?;
                let transport=tokio::net::TcpStream::connect(endpoint(&address,port)).await?;
                Ok(wireless::pair(transport,code,&self.identity,&tls,"interop-controller",&options).await?)
            }) => result.unwrap_or_else(|_|Err(CoreError::new("timeout","配对操作超时，请检查当前配对码。"))),
        };
        let result = match result {
            Ok(result) => {
                self.finish_pairing(
                    result.guid,
                    address,
                    params.get("deviceId").and_then(Value::as_str),
                    &token,
                )
                .await
            }
            Err(error) => Err(error),
        };
        {
            let mut pending = self.device_operations.lock().await;
            if !token.is_cancelled() {
                pending.remove(&attempt_id);
            }
        }
        result
    }
    async fn finish_pairing(
        &self,
        guid: String,
        address: String,
        explicit_id: Option<&str>,
        token: &CancellationToken,
    ) -> CoreResult<Value> {
        let id = {
            let mut store = self.store.write().await;
            let index = if let Some(id) = explicit_id {
                Some(
                    store
                        .devices
                        .iter()
                        .position(|d| d.id == id)
                        .ok_or_else(|| {
                            CoreError::new(
                                "not_found",
                                "原设备记录不存在；配对已成功，请重新发现设备。",
                            )
                        })?,
                )
            } else {
                store
                    .devices
                    .iter()
                    .position(|d| d.guid.as_deref() == Some(&guid))
            };
            let record = if let Some(index) = index {
                &mut store.devices[index]
            } else {
                store
                    .devices
                    .push(blank_device(address.clone(), 0, TransportKind::Tls));
                store.devices.last_mut().expect("pushed device")
            };
            if record.guid.as_ref().is_some_and(|known| known != &guid) {
                return Err(CoreError::new(
                    "device_identity_mismatch",
                    "配对的是另一台设备，原记录未被覆盖。",
                ));
            }
            record.guid = Some(guid.clone());
            record.address = address;
            record.transport = TransportKind::Tls;
            record.status = "offline".into();
            record.auto_reconnect = false;
            record.reason = Some("配对已完成，正在发现独立的连接端口。".into());
            record.id.clone()
        };
        self.changed_devices().await?;
        if self.client(&id).await.is_ok() {
            if let Some(record) = self
                .store
                .write()
                .await
                .devices
                .iter_mut()
                .find(|d| d.id == id)
            {
                record.status = "connected".into();
                record.reason = None;
                record.auto_reconnect = true;
            }
            self.changed_devices().await?;
            return Ok(
                json!({"paired":true,"deviceId":id,"device":self.device(&id).await?,"connected":true}),
            );
        }
        // Explicit disconnect/replacement must cancel discovery too, before a
        // socket exists. Keep that same operation through candidate retries.
        let registered = self
            .register_connection_operation(&id, true, token)
            .await
            .is_ok();
        let discovery = if registered {
            self.find_connect_endpoints(&guid, token).await
        } else {
            None
        };
        let discovered_service = discovery.is_some();
        let mut attempted_connection = false;
        let connected = if let Some(discovery) = discovery {
            let mut connected = false;
            for _ in 0..3 {
                let attempt = discovery.attempt().await;
                if attempt.endpoints.as_ref().is_none_or(Vec::is_empty) {
                    break;
                }
                attempted_connection = true;
                let result = self
                    .connect_registered_candidates(&id, true, token.clone(), Some(attempt))
                    .await;
                connected = result.is_ok();
                if !result
                    .as_ref()
                    .is_err_and(|error| error.code == "discovery_changed")
                    || token.is_cancelled()
                {
                    break;
                }
            }
            connected
        } else {
            false
        };
        if !attempted_connection {
            let pending = self.device_operations.lock().await;
            let mut store = self.store.write().await;
            // A cancelled old form cannot overwrite a newer operation's state.
            let replaced = token.is_cancelled()
                && pending
                    .get(&id)
                    .is_some_and(|current| !current.is_cancelled());
            if !replaced
                && let Some(record) = store.devices.iter_mut().find(|d| d.id == id)
                && record.status != "connected"
            {
                record.auto_reconnect = !token.is_cancelled();
                record.reason = Some(
                    if token.is_cancelled() {
                        "配对已完成；后续连接已取消，授权身份仍保留。"
                    } else if discovered_service {
                        "配对已完成；连接服务已更新或撤销，将等待有效地址重连。"
                    } else {
                        "配对已完成；未发现连接服务，请填写无线调试页面的连接端口，无需重新配对。"
                    }
                    .into(),
                );
            }
            drop(store);
            drop(pending);
            self.changed_devices().await?;
        }
        {
            let mut pending = self.device_operations.lock().await;
            if !token.is_cancelled() {
                pending.remove(&id);
            }
        }
        let device = self.device(&id).await?;
        Ok(
            json!({"paired":true,"deviceId":id,"device":device,"connected":connected,"connectionPortRequired":!connected && !discovered_service && device.port == 0}),
        )
    }
    async fn find_connect_endpoints(
        &self,
        guid: &str,
        token: &CancellationToken,
    ) -> Option<PairingDiscovery> {
        let discovery = Discovery::new().ok()?;
        let services = DiscoveredServices::default();
        services
            .write()
            .await
            .sync_trusted(HashSet::from([guid.to_owned()]));
        let options = operations(5, token.clone());
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let event = discovery.next(&options).await.ok()?;
                let mut answers = services.write().await;
                answers.observe(event);
                if answers
                    .endpoints(guid)
                    .is_some_and(|endpoints| !endpoints.is_empty())
                {
                    break Some(());
                }
            }
        })
        .await
        .ok()
        .flatten()?;
        let observed = services.clone();
        let options = operations(60, token.child_token());
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
        Some(PairingDiscovery {
            services,
            guid: guid.to_owned(),
            task,
        })
    }
    pub(crate) async fn qr_pairing(self: &Arc<Self>) -> CoreResult<Value> {
        let qr = QrPairing::generate();
        let response = json!({"payload":qr.payload().as_str(),"serviceName":qr.service_name(),"attemptId":qr.service_name(),"expiresAt":now()+120});
        let token = CancellationToken::new();
        if let Some((_, old)) = self
            .qr_attempt
            .lock()
            .await
            .replace((qr.service_name().into(), token.clone()))
        {
            old.cancel();
        }
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            let Some(runtime) = weak.upgrade() else {
                return;
            };
            runtime.emit(
                "pairing.changed",
                None,
                json!({"status":"waiting","serviceName":qr.service_name(),"attemptId":qr.service_name()}),
            );
            let result = tokio::select! {
                _ = token.cancelled() => Err(CoreError::new("cancelled", "二维码配对已取消。")),
                result = tokio::time::timeout(Duration::from_secs(120), async {
                    let discovery = Discovery::new()?;
                    let tls = runtime.tls_config().await?;
                    let options = operations(120, token.clone());
                    loop {
                        if let DiscoveryEvent::Resolved(service) = discovery.next(&options).await?
                            && service.kind == ServiceKind::Pairing && service.instance == qr.service_name() {
                            let mut last = None;
                            for address in service.endpoints {
                                let attempt = async {
                                    let stream = tokio::net::TcpStream::connect(address).await?;
                                    let paired = wireless::pair(stream, qr.password(), &runtime.identity, &tls, "interop-controller", &options).await?;
                                    Ok::<_,CoreError>((paired.guid,address_of(address)))
                                }.await;
                                match attempt { Ok(value) => return Ok(value), Err(error) => last = Some(error) }
                            }
                            return Err(last.unwrap_or_else(|| CoreError::new("pairing_failed", "已发现配对服务，但没有可达地址。")));
                        }
                    }
                }) => result.unwrap_or_else(|_| Err(CoreError::new("expired", "二维码已过期，请生成新的二维码。"))),
            };
            let result = match result {
                Ok((guid, address)) => runtime.finish_pairing(guid, address, None, &token).await,
                Err(error) => Err(error),
            };
            match result {
                Ok(value) => runtime.emit("pairing.changed", value.get("deviceId").and_then(Value::as_str), json!({"status":"paired","attemptId":qr.service_name(),"result":value})),
                Err(error) => runtime.emit("pairing.changed", None, json!({"attemptId":qr.service_name(),"status":match error.code.as_str() {"expired"=>"expired","cancelled"=>"cancelled",_=>"failed"},"code":error.code,"message":error.message})),
            }
        });
        Ok(response)
    }
    pub(crate) async fn enable_wireless(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let requested = params
            .get("port")
            .map(|_| port(params))
            .transpose()?
            .unwrap_or(5555);
        let client = self.client(id).await?;
        let mut stream = client
            .open(&format!("tcpip:{requested}"), OperationOptions::default())
            .await?;
        let mut bytes = Vec::new();
        tokio::time::timeout(Duration::from_secs(10), async {
            let mut buffer = [0u8; 1024];
            loop {
                match stream.read(&mut buffer).await {
                    Ok(0) => break,
                    Ok(count) => {
                        if bytes.len() + count > 8192 {
                            return Err(interop_adb::Error::OutputLimit);
                        }
                        bytes.extend_from_slice(&buffer[..count]);
                    }
                    Err(interop_adb::Error::Closed) if !bytes.is_empty() => break,
                    Err(error) => return Err(error),
                }
            }
            Ok(())
        })
        .await
        .map_err(|_| CoreError::new("timeout", "等待设备开启无线监听超时。"))??;
        let response = String::from_utf8_lossy(&bytes).into_owned();
        if !response.contains("restarting in TCP mode") {
            return Err(CoreError::new("wireless_setup_failed", response));
        }
        Ok(
            json!({"enabled":true,"port":requested,"encrypted":false,"response":response,
            "connectionRequired":true,"message":"已通过授权连接请求开启旧式 TCP 调试；请填写设备当前网络地址后连接。"}),
        )
    }
    pub(crate) async fn usb_devices(&self, params: &Value) -> CoreResult<Value> {
        let token = CancellationToken::new();
        let connecting = params.get("fd").is_some()
            || params.get("connect").and_then(Value::as_bool) == Some(true);
        let explicit = params.get("deviceId").and_then(Value::as_str);
        // New USB devices have no record yet, but must still be cancellable by Stop All.
        let attempt_id = params["attemptId"]
            .as_str()
            .filter(|id| !id.is_empty() && id.len() <= 128)
            .map(str::to_owned)
            .unwrap_or_else(|| format!("usb:{}", uuid::Uuid::new_v4()));
        if connecting
            && let Some(previous) = self
                .device_operations
                .lock()
                .await
                .insert(attempt_id.clone(), token.clone())
        {
            previous.cancel();
        }
        if connecting && let Some(id) = explicit {
            let mut pending = self.device_operations.lock().await;
            let mut store = self.store.write().await;
            let record = store
                .devices
                .iter_mut()
                .find(|d| d.id == id)
                .ok_or_else(|| CoreError::new("not_found", "设备记录已不存在。"))?;
            if let Some(previous) = pending.insert(id.into(), token.clone()) {
                previous.cancel();
            }
            record.status = "connecting".into();
            record.auto_reconnect = true;
            record.reason = None;
            drop(store);
            drop(pending);
            self.changed_devices().await?;
        }
        let result = self.usb_devices_inner(params, &token).await;
        if let Err(error) = &result
            && connecting
            && !token.is_cancelled()
            && let Some(id) = explicit
        {
            if let Some(record) = self
                .store
                .write()
                .await
                .devices
                .iter_mut()
                .find(|d| d.id == id)
            {
                record.status = if error.code == "authorization_required" {
                    "unauthorized"
                } else {
                    "offline"
                }
                .into();
                record.reason = Some(error.message.clone());
                record.auto_reconnect = false;
            }
            self.changed_devices().await?;
        }
        if !token.is_cancelled() {
            self.device_operations.lock().await.remove(&attempt_id);
        }
        result
    }
    async fn usb_devices_inner(
        &self,
        params: &Value,
        token: &CancellationToken,
    ) -> CoreResult<Value> {
        #[cfg(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        ))]
        {
            if let Some(fd) = params.get("fd") {
                #[cfg(any(target_os = "linux", target_os = "android"))]
                {
                    use std::os::fd::FromRawFd;
                    let fd = fd
                        .as_i64()
                        .and_then(|v| i32::try_from(v).ok())
                        .filter(|n| *n >= 0)
                        .ok_or_else(|| CoreError::new("invalid_fd", "USB 授权描述符无效。"))?;
                    // fcntl atomically duplicates an OS handle without assuming that
                    // an arbitrary caller-supplied integer is a valid BorrowedFd.
                    let duplicate = unsafe { libc::fcntl(fd, libc::F_DUPFD_CLOEXEC, 0) };
                    if duplicate < 0 {
                        return Err(std::io::Error::last_os_error().into());
                    }
                    let owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(duplicate) };
                    let options = self.connect_options(token.clone()).await?;
                    let transport =
                        interop_adb::usb::from_owned_fd(owned, options.operations.clone()).await?;
                    let client = Client::connect_transport(transport, options).await?;
                    return self
                        .adopt_usb(
                            client,
                            params.get("deviceId").and_then(Value::as_str),
                            token,
                        )
                        .await;
                }
                #[cfg(not(any(target_os = "linux", target_os = "android")))]
                {
                    let _ = fd;
                    return Err(CoreError::new(
                        "unsupported_platform",
                        "当前平台不通过文件描述符导入 USB。",
                    ));
                }
            }
            let devices =
                interop_adb::usb::list_devices(operations(10, CancellationToken::new())).await?;
            if params.get("connect").and_then(Value::as_bool) == Some(true) {
                let serial = required(params, "serial")?;
                let matches = devices
                    .iter()
                    .filter(|d| d.serial_number() == Some(serial))
                    .collect::<Vec<_>>();
                if matches.len() != 1 {
                    return Err(CoreError::new(
                        "usb_selection_required",
                        "未找到唯一匹配的 USB 设备，请重新选择。",
                    ));
                }
                let options = self.connect_options(token.clone()).await?;
                let transport = matches[0].open(options.operations.clone()).await?;
                let client = Client::connect_transport(transport, options).await?;
                return self
                    .adopt_usb(
                        client,
                        params.get("deviceId").and_then(Value::as_str),
                        token,
                    )
                    .await;
            }
            Ok(
                json!({"supported":true,"devices":devices.iter().map(|device| json!({"vendorId":device.vendor_id(),"productId":device.product_id(),"serial":device.serial_number(),"permission":"os_authorization_required"})).collect::<Vec<_>>(),"controllerDebuggingRequired":false}),
            )
        }
        #[cfg(not(any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        )))]
        {
            let _ = (params, token);
            Ok(
                json!({"supported":false,"devices":[],"reason":"此平台的 USB 后端尚未实现。","controllerDebuggingRequired":false}),
            )
        }
    }
    #[cfg(any(
        target_os = "linux",
        target_os = "android",
        target_os = "windows",
        target_os = "macos"
    ))]
    async fn adopt_usb(
        &self,
        client: Client,
        explicit_id: Option<&str>,
        token: &CancellationToken,
    ) -> CoreResult<Value> {
        let info = metadata(&client, token.clone()).await;
        if token.is_cancelled() {
            client.close();
            return Err(CoreError::new("cancelled", "USB 连接已取消。"));
        }
        if client.is_closed() {
            return Err(CoreError::new(
                "disconnected",
                "USB 设备在读取信息时已断开。",
            ));
        }
        let id = {
            let mut store = self.store.write().await;
            let index = if let Some(id) = explicit_id {
                Some(
                    store
                        .devices
                        .iter()
                        .position(|d| d.id == id)
                        .ok_or_else(|| CoreError::new("not_found", "设备记录已不存在。"))?,
                )
            } else {
                info.serial.as_ref().and_then(|serial| {
                    store
                        .devices
                        .iter()
                        .position(|d| d.serial.as_ref() == Some(serial))
                })
            };
            let record = if let Some(index) = index {
                &mut store.devices[index]
            } else {
                store
                    .devices
                    .push(blank_device(String::new(), 0, TransportKind::Usb));
                store.devices.last_mut().expect("pushed record")
            };
            if let (Some(known), Some(actual)) = (&record.serial, &info.serial)
                && known != actual
            {
                client.close();
                return Err(CoreError::new(
                    "device_identity_mismatch",
                    "USB 设备与选定记录的序列号不同。",
                ));
            }
            record.transport = TransportKind::Usb;
            record.id.clone()
        };
        self.attach_client(&id, client, info, token, None, None)
            .await
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

    pub(crate) async fn wake_device(&self, id: &str) -> CoreResult<Value> {
        let client = self.client(id).await?;
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

    pub(crate) async fn capabilities(&self, id: &str) -> CoreResult<Value> {
        let device = self.device(id).await?;
        let client = self.client(id).await.ok();
        let companion = self.companions.lock().await.get(id).cloned();
        let companion_snapshot = match companion {
            Some(companion) if client.is_some() => Some(companion.capability_state().await),
            _ => None,
        };
        let mut entries = Vec::new();
        let mut add = |key: &str, status: &str, reason: &str| {
            entries.push(json!({"key":key,"id":key,"name":key,"status":status,"reason":reason}))
        };
        if let Some(client) = &client {
            let shell = client
                .shell(
                    "printf interop-capability-check",
                    1024,
                    operations(5, CancellationToken::new()),
                )
                .await;
            let shell_ok = shell
                .as_ref()
                .is_ok_and(|o| o.stdout == b"interop-capability-check");
            add(
                "shell",
                if shell_ok { "available" } else { "limited" },
                if shell_ok {
                    "已通过当前设备授权连接验证 shell。"
                } else {
                    "ADB 已连接，但 shell 探测未成功。"
                },
            );
            let sync_ok = match client.sync(operations(5, CancellationToken::new())).await {
                Ok(mut sync) => match interop_adb::sync::RemotePath::new("/") {
                    Ok(path) => sync.stat(&path).await.is_ok(),
                    Err(_) => false,
                },
                Err(_) => false,
            };
            add(
                "files",
                if sync_ok { "available" } else { "limited" },
                if sync_ok {
                    "已通过当前连接验证文件服务；受 Android 文件权限限制。"
                } else {
                    "当前文件服务探测失败，可查看连接诊断。"
                },
            );
        } else {
            add("shell", "unknown", "设备尚未连接，无法探测。");
            add("files", "unknown", "设备尚未连接，无法探测。");
        }
        if device.api_level.is_some_and(|api| api < 30) {
            add(
                "wirelessPairing",
                "unavailable",
                "设备 Android 版本低于 11，系统不提供现代无线配对；可使用授权 USB 开启旧式 TCP。",
            );
        } else if device.guid.is_some() {
            add(
                "wirelessPairing",
                "available",
                "已通过配对协议取得该设备 GUID；连接状态单独记录。",
            );
        } else if device.api_level.is_none() {
            add(
                "wirelessPairing",
                "unknown",
                "尚未读取设备 Android 版本，现代无线配对能力待确认。",
            );
        } else {
            add(
                "wirelessPairing",
                "needsSetup",
                "请在被控设备系统中开启无线调试并完成配对。",
            );
        }
        let active_session = self
            .activities()
            .await
            .ok()
            .and_then(|activities| activities.get("sessions").cloned())
            .and_then(|sessions| sessions.as_array().cloned())
            .is_some_and(|sessions| {
                sessions
                    .iter()
                    .any(|session| session["deviceId"] == id && session["status"] == "streaming")
            });
        if client.is_some() && device.api_level.is_some_and(|api| api >= 21) {
            add(
                "screen",
                if active_session {
                    "available"
                } else {
                    "limited"
                },
                if active_session {
                    "当前设备已有实际视频控制会话。"
                } else {
                    "scrcpy 5.0.1 屏幕链路已实现并经 Android 16 验证；当前设备编码器及厂商输入权限在启动时确认。"
                },
            );
            add(
                "clipboard",
                companion_snapshot.as_ref().and_then(|snapshot|snapshot["clipboard"]["status"].as_str()).unwrap_or("unknown"),
                companion_snapshot.as_ref().and_then(|snapshot|snapshot["clipboard"]["reason"].as_str()).unwrap_or("已有屏幕控制与无视频文本通道；状态反映目标当前探测结果，主控自动同步仍须在前台并遵守本机权限。"),
            );
        } else {
            add(
                "screen",
                "unknown",
                "设备未连接或 Android 版本尚未读取，无法确认屏幕能力。",
            );
            add("clipboard", "unknown", "设备尚无可核验的控制会话。");
        }
        if let Some(client) = &client {
            let packages = client
                .shell(
                    "pm list packages",
                    512 * 1024,
                    operations(8, CancellationToken::new()),
                )
                .await;
            if packages.as_ref().is_ok_and(|output| {
                output.exit_code.is_none_or(|code| code == 0)
                    && output.stdout.starts_with(b"package:")
            }) {
                add(
                    "apps",
                    if device.api_level.is_some_and(|api| api >= 29) {
                        "available"
                    } else {
                        "limited"
                    },
                    "已通过当前设备的应用包列表探测；独立应用窗口要求 Android 10+，具体应用能否启动仍受系统及应用条件限制。",
                );
            } else {
                add(
                    "apps",
                    "limited",
                    "当前设备应用列表探测未成功，请查看连接诊断；不能据此认定设备不支持。",
                );
            }
        } else {
            add("apps", "unknown", "设备尚未连接，无法探测应用能力。");
        }
        let audio = self.audio_command("audio.sources", &json!({})).await?;
        let playing = audio["sources"].as_array().is_some_and(|sources| {
            sources.iter().any(|source| {
                source["deviceId"] == id
                    && source["status"] == "playing"
                    && source["nativeAttached"] == true
            })
        });
        add(
            "audio",
            if playing {
                "available"
            } else if device.api_level.is_some_and(|api| api < 30) {
                "unavailable"
            } else {
                "unknown"
            },
            if playing {
                "该设备当前已有实际主控播放器；应用是否允许捕获声音仍按其内容权限处理。"
            } else if device.api_level.is_some_and(|api| api < 30) {
                "scrcpy声音转发要求被控Android 11或更新版本。"
            } else {
                "声音链路已实现；此设备尚无实际播放结果，请在声音页主动开启后确认。"
            },
        );
        if let Some(snapshot) = companion_snapshot {
            for key in ["notifications", "calls"] {
                let feature = &snapshot[key];
                let status = feature["controlStatus"]
                    .as_str()
                    .or_else(|| feature["status"].as_str())
                    .unwrap_or("unknown");
                add(
                    key,
                    status,
                    feature["reason"]
                        .as_str()
                        .unwrap_or("当前临时互联服务已探测；操作资格仍需按最新内容逐项校验。"),
                );
            }
        } else {
            add(
                "notifications",
                "unknown",
                "尚未在当前连接探测通知服务；打开通知页后验证，不能据此认定不支持。",
            );
            add(
                "calls",
                "unknown",
                "尚未读取当前电话状态；安全逐通话控制仍待实现，可在远控中使用手机原电话应用。",
            );
        }
        add(
            "background",
            "unknown",
            "后台保持由主控的系统权限、电量策略与当前活动决定，请在后台与连接页检查。",
        );
        Ok(
            json!({"deviceId":id,"capabilities":entries,"features":client.map(|c| c.info().features.iter().cloned().collect::<Vec<_>>()).unwrap_or_default()}),
        )
    }
    pub(crate) async fn diagnose(&self, id: &str) -> CoreResult<Value> {
        let device = self.device(id).await?;
        let client = self.client(id).await.ok();
        let tcp_reachable = if !device.transport.is_usb() && device.port != 0 {
            Some(
                tokio::time::timeout(
                    Duration::from_secs(3),
                    tokio::net::TcpStream::connect(endpoint(&device.address, device.port)),
                )
                .await
                .is_ok_and(|result| result.is_ok()),
            )
        } else {
            None
        };
        let properties = if let Some(client) = &client {
            client.shell("getprop service.adb.tls.port; getprop persist.adb.tls_server.enable; getprop mdns_service_version", 8192, operations(5,CancellationToken::new())).await
                .ok().map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            None
        };
        Ok(
            json!({"deviceId":id,"device":device,"connected":client.is_some(),"tcpReachable":tcp_reachable,"usbBackendAvailable":interop_adb::usb::supported(),
            "adbBurstActive":client.as_ref().map(Client::burst_mode),
            "adbBurstRequested":self.store.read().await.settings["adbBurstMode"]==true,
            "wirelessProperties":properties,"identityPresent":true,"tlsProvider":"rustls-rustcrypto 0.0.2-alpha (experimental, not production-approved)",
            "notes":["配对端口与连接端口不同。","mDNS 不可用时仍可手动填写可达的连接地址。","网络可达、已配对与设备连接是独立状态。"]}),
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
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            let mut health = crate::connection_health::ConnectionHealth::default();
            let mut backoff = HashMap::<String, (u32, Instant)>::new();
            let mut reconnecting = HashMap::<String, tokio::task::JoinHandle<()>>::new();
            let services = DiscoveredServices::default();
            let discovery = Discovery::new().ok();
            loop {
                tokio::time::sleep(Duration::from_secs(2)).await;
                let Some(runtime) = weak.upgrade() else {
                    break;
                };
                // Health work never awaits a service response under this lock
                // or blocks another device's monitoring/reconnection.
                health.tick(&*runtime.connections.lock().await);
                reconnecting.retain(|_, task| !task.is_finished());
                for record in &runtime.store.read().await.devices {
                    if record.status == "connected" {
                        backoff.remove(&record.id);
                    }
                }
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
                services.write().await.sync_trusted(trusted);
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
                        let changed = {
                            let mut services = services.write().await;
                            let Some(guid) = services.observe(event) else {
                                continue;
                            };
                            guid
                        };
                        for record in &runtime.store.read().await.devices {
                            if record.guid.as_deref() == Some(changed.as_str())
                                && !record.transport.is_usb()
                            {
                                backoff.remove(&record.id);
                            }
                        }
                    }
                }
                let records = runtime
                    .store
                    .read()
                    .await
                    .devices
                    .iter()
                    .filter(|d| d.auto_reconnect && d.status == "offline")
                    .cloned()
                    .collect::<Vec<_>>();
                for device in records {
                    // Retirement publishes the offline projection after all
                    // old activities have stopped. A reconnect must not write
                    // connecting/connected over that unpublished transition.
                    if runtime.connections.is_retiring(&device.id)
                        || reconnecting.contains_key(&device.id)
                    {
                        continue;
                    }
                    if backoff
                        .get(&device.id)
                        .is_some_and(|(_, deadline)| Instant::now() < *deadline)
                    {
                        continue;
                    }
                    let discovered = if !device.transport.is_usb() {
                        if let Some(guid) = &device.guid {
                            let answers = services.read().await;
                            Some(DiscoveredAttempt {
                                services: services.clone(),
                                guid: guid.clone(),
                                endpoints: answers.endpoints(guid),
                                generation: answers.generation(guid),
                            })
                        } else {
                            None
                        }
                    } else {
                        None
                    };
                    if discovered
                        .as_ref()
                        .and_then(|answer| answer.endpoints.as_ref())
                        .is_some_and(Vec::is_empty)
                    {
                        continue;
                    }
                    if !device.transport.is_usb()
                        && device.port == 0
                        && discovered
                            .as_ref()
                            .and_then(|answer| answer.endpoints.as_ref())
                            .is_none()
                    {
                        continue;
                    }
                    let count = backoff
                        .get(&device.id)
                        .map_or(1, |(count, _)| count.saturating_add(1));
                    backoff.insert(
                        device.id.clone(),
                        (
                            count,
                            Instant::now() + Duration::from_secs(1u64 << count.min(6)),
                        ),
                    );
                    // A reconnect never requests a fresh UI authorization prompt.
                    // connect_device's existing identity handles the STLS/auth path;
                    // an authorization failure disables automatic retry.
                    let owner = runtime.clone();
                    let id = device.id.clone();
                    reconnecting.insert(
                        device.id,
                        tokio::spawn(async move {
                            let _ = Box::pin(owner.connect_device_with_candidates(
                                &id,
                                false,
                                CancellationToken::new(),
                                discovered,
                            ))
                            .await;
                        }),
                    );
                }
            }
        });
    }
}
