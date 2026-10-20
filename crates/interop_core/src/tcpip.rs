//! Native TCP listener execution and verified endpoint admission. No retry scheduler.
use crate::{
    CoreError, CoreResult, Runtime,
    connection_setup::PendingResource,
    device::{endpoint, host, metadata, port},
    model::required,
};
use interop_adb::{Client, OperationOptions};
use serde_json::{Value, json};
use std::time::Duration;
#[cfg(test)]
use tokio_util::sync::CancellationToken;

struct SourceConnection(Client);
impl Drop for SourceConnection {
    fn drop(&mut self) {
        self.0.close();
    }
}

impl Runtime {
    pub(crate) async fn tcpip_begin(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let expected = required(params, "connectionId")?;
        let port = port(params)?;
        let material = self.identities.selected(Some(id)).await?;
        let op = self
            .new_setup_operation(params, Some(id), material.fingerprint.clone())
            .await?;
        let result = async {
            let mut cleanup = self.connections.transition(id).await;
            op.check()?;
            let record = self.device(id).await?;
            let client = self.client(id).await?;
            if client.connection_id().to_string() != expected {
                return Err(CoreError::new("stale_connection", "源连接已替换。"));
            }
            let source = metadata(&client, op.token.clone()).await;
            op.check()?;
            let serial = source.serial.ok_or_else(|| {
                CoreError::new("device_identity_unverified", "源设备序列号不可用。")
            })?;
            if record.serial.as_ref().is_some_and(|known| known != &serial) {
                return Err(CoreError::new(
                    "device_identity_mismatch",
                    "源设备序列号不匹配。",
                ));
            }
            {
                let _pending = self.device_operations.lock().await;
                op.check()?;
                self.identities
                    .state
                    .read()
                    .await
                    .validate(id, &op.identity)?;
                let mut store = self.store.write().await;
                let mut connections = self.connections.lock().await;
                if !connections
                    .get(id)
                    .is_some_and(|current| current.same_connection(&client))
                {
                    return Err(CoreError::new("stale_connection", "源连接已替换。"));
                }
                *cleanup = true;
                connections.remove(id);
                let record = store
                    .devices
                    .iter_mut()
                    .find(|d| d.id == id)
                    .ok_or_else(|| CoreError::new("not_found", "设备记录已移除。"))?;
                record.serial = Some(serial.clone());
                record.status = "connecting".into();
                record.auto_reconnect = false;
                record.reason = None;
            }
            let source_owner = SourceConnection(client.clone());
            self.stop_device_activities(id).await?;
            self.changed_devices().await?;
            let response = client
                .tcpip(
                    port,
                    OperationOptions {
                        timeout: Duration::from_millis(
                            self.connection_policy.tcpip_restart_timeout_ms,
                        ),
                        cancellation: op.token.clone(),
                    },
                )
                .await;
            drop(source_owner);
            *cleanup = false;
            {
                let mut store = self.store.write().await;
                if let Some(record) = store.devices.iter_mut().find(|d| d.id == id) {
                    record.status = "offline".into();
                }
            }
            self.changed_devices().await?;
            let response = response.map_err(|error| {
                CoreError::new(
                    if matches!(error, interop_adb::Error::Cancelled) {
                        "cancelled"
                    } else {
                        "wireless_setup_unknown"
                    },
                    "监听切换执行未取得完整响应。",
                )
            })?;
            op.check()?;
            *op.resource.lock().expect("operation resource poisoned") =
                PendingResource::Tcpip { serial, port };
            Ok(json!({"operationId":op.id,"deviceId":id,"port":port,"responseBytes":response}))
        }
        .await;
        self.setup_outcome(&op, &result);
        result
    }
    pub(crate) async fn tcpip_connect(&self, params: &Value) -> CoreResult<Value> {
        let op = self
            .setup_operations
            .get(required(params, "operationId")?)
            .await?;
        let _execution = op
            .execution
            .try_lock()
            .map_err(|_| CoreError::new("operation_busy", "执行正在进行。"))?;
        let id = op
            .device_id()
            .ok_or_else(|| CoreError::new("invalid_operation", "执行没有设备身份。"))?;
        let address = host(params)?;
        let (serial, port) = {
            let resource = op.resource.lock().expect("operation resource poisoned");
            match &*resource {
                PendingResource::Tcpip { serial, port } => (serial.clone(), *port),
                _ => return Err(CoreError::new("invalid_operation", "执行不是TCP监听转换。")),
            }
        };
        let result = async {
            op.check()?;
            let mut options = self
                .connect_options_for(Some(&id), op.token.clone())
                .await?;
            if crate::host_identity::fingerprint(options.identity.as_ref().expect("identity"))?
                != op.identity
            {
                return Err(CoreError::new("identity_changed", "授权身份已改变。"));
            }
            options.operations.timeout =
                Duration::from_millis(self.connection_policy.tcpip_attempt_timeout_ms);
            {
                let pending = self.device_operations.lock().await;
                op.check()?;
                if pending.get(&id) != Some(&op.token) {
                    return Err(CoreError::new("cancelled", "执行已被替换。"));
                }
                let mut store = self.store.write().await;
                let record = store
                    .devices
                    .iter_mut()
                    .find(|d| d.id == id)
                    .ok_or_else(|| CoreError::new("not_found", "设备记录已移除。"))?;
                record.status = "connecting".into();
            }
            self.changed_devices().await?;
            let client = Client::connect_tcp(endpoint(&address, port), options)
                .await
                .map_err(|error| match error {
                    interop_adb::Error::Io(error) => CoreError::new(
                        if error.kind() == std::io::ErrorKind::PermissionDenied {
                            "permission_denied"
                        } else {
                            "unreachable"
                        },
                        error.to_string(),
                    ),
                    other => CoreError::from(other),
                })?;
            let guarded = client.clone();
            let mut info = metadata(&client, op.token.clone()).await;
            if info.serial.as_deref() != Some(&serial) {
                guarded.close();
                return Err(CoreError::new(
                    if info.serial.is_some() {
                        "device_identity_mismatch"
                    } else {
                        "device_identity_unverified"
                    },
                    "目标设备序列号无法与源设备核对。",
                ));
            }
            info.host_identity = Some(op.identity.clone());
            let receipt = self
                .attach_tcpip_client(&id, client, info, &op.token, (address, port))
                .await;
            if receipt.is_err() {
                guarded.close();
            }
            if receipt.is_ok() {
                *op.resource.lock().expect("operation resource poisoned") = PendingResource::None;
            }
            receipt
        }
        .await;
        if let Err(error) = &result {
            let pending = self.device_operations.lock().await;
            if !op.token.is_cancelled() && pending.get(&id) == Some(&op.token) {
                let mut store = self.store.write().await;
                if let Some(record) = store.devices.iter_mut().find(|d| d.id == id) {
                    record.status = if error.code == "authorization_required" {
                        "unauthorized"
                    } else {
                        "offline"
                    }
                    .into();
                    record.reason = Some(error.message.clone());
                }
            }
            drop(pending);
            self.changed_devices().await?;
        }
        self.setup_outcome(&op, &result);
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TransportKind;
    impl Runtime {
        // This test driver models the two explicit caller-owned stages, with
        // no retry: source/target fixtures are already listening.
        async fn raw_tcpip(&self, params: Value) -> CoreResult<Value> {
            let id = required(&params, "deviceId")?;
            let client = self.client(id).await?;
            let port = params["port"].as_u64().unwrap_or(5555);
            let begin=self.tcpip_begin(&json!({"deviceId":id,"connectionId":client.connection_id().to_string(),"port":port,"attemptId":uuid::Uuid::new_v4().to_string(),"leaseMs":180000})).await?;
            let mut receipt = self
                .tcpip_connect(
                    &json!({"operationId":begin["operationId"],"address":params["address"]}),
                )
                .await?;
            receipt["enabled"] = json!(true);
            receipt["port"] = json!(port);
            receipt["encrypted"] = json!(false);
            Ok(receipt)
        }
    }
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    use std::sync::Arc;
    use tokio::io::{AsyncRead, AsyncWrite};
    struct AbortTask(tokio::task::JoinHandle<()>);
    impl Drop for AbortTask {
        fn drop(&mut self) {
            self.0.abort();
        }
    }

    async fn serve(
        mut socket: impl AsyncRead + AsyncWrite + Unpin,
        serial: &'static str,
        restart: bool,
        activity: Option<CancellationToken>,
    ) {
        while let Ok(frame) = Frame::read(&mut socket, 4096, true).await {
            if frame.command != protocol::OPEN {
                continue;
            }
            let command = String::from_utf8_lossy(&frame.payload);
            let response = if command.starts_with("shell:") {
                format!("Test Phone\n12\n31\n{serial}\n").into_bytes()
            } else if command.starts_with("tcpip:") {
                if let Some(activity) = &activity {
                    assert!(
                        activity.is_cancelled(),
                        "activity must stop before restarting adbd"
                    );
                }
                if !restart {
                    return;
                }
                let port = command
                    .trim_end_matches('\0')
                    .strip_prefix("tcpip:")
                    .unwrap();
                format!("restarting in TCP mode port: {port}\n").into_bytes()
            } else {
                vec![]
            };
            for output in [
                Frame::new(protocol::OKAY, 1, frame.arg0, vec![]),
                Frame::new(protocol::WRTE, 1, frame.arg0, response),
                Frame::new(protocol::CLSE, 1, frame.arg0, vec![]),
            ] {
                if output.write(&mut socket).await.is_err() {
                    return;
                }
            }
        }
    }
    async fn source_transport(runtime: &Arc<Runtime>) -> (String, Client, tokio::io::DuplexStream) {
        let added = runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":1}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        let (transport, peer) = tokio::io::duplex(8192);
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
            .insert(id.clone(), client.clone());
        {
            let mut store = runtime.store.write().await;
            let record = store.devices.iter_mut().find(|d| d.id == id).unwrap();
            record.status = "connected".into();
            record.serial = Some("serial-original".into());
            record.observation_wanted = false;
        }
        (id, client, peer)
    }
    async fn source(
        runtime: &Arc<Runtime>,
        restart: bool,
        activity: Option<CancellationToken>,
    ) -> (String, Client, AbortTask) {
        let (id, client, peer) = source_transport(runtime).await;
        let peer = AbortTask(tokio::spawn(serve(
            peer,
            "serial-original",
            restart,
            activity,
        )));
        (id, client, peer)
    }
    async fn target(serial: &'static str) -> (u16, AbortTask) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = AbortTask(tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(
                Frame::read(&mut socket, 4096, false).await.unwrap().command,
                protocol::CNXN
            );
            Frame::new(
                protocol::CNXN,
                protocol::VERSION,
                4096,
                b"device::\0".to_vec(),
            )
            .write(&mut socket)
            .await
            .unwrap();
            serve(socket, serial, false, None).await;
        }));
        (port, task)
    }
    async fn remember_tls_source(runtime: &Runtime, id: &str) -> Value {
        let mut store = runtime.store.write().await;
        let record = store.devices.iter_mut().find(|d| d.id == id).unwrap();
        record.address = "original.example".into();
        record.port = 37123;
        record.transport = TransportKind::Tls;
        record.guid = Some("paired-guid".into());
        connection_details(&json!(record))
    }
    fn connection_details(record: &Value) -> Value {
        json!({"address":record["address"],"port":record["port"],"transport":record["transport"],"guid":record["guid"]})
    }
    async fn assert_connection_preserved(runtime: &Runtime, id: &str, before: &Value) {
        assert_eq!(
            connection_details(&json!(runtime.device(id).await.unwrap())),
            *before
        );
        let saved: Value = serde_json::from_slice(
            &tokio::fs::read(runtime.root.join("devices.json"))
                .await
                .unwrap(),
        )
        .unwrap();
        let record = saved["devices"]
            .as_array()
            .unwrap()
            .iter()
            .find(|d| d["id"] == id)
            .unwrap();
        assert_eq!(connection_details(record), *before);
    }
    #[tokio::test]
    async fn tcpip_uses_a_current_tcp_connection_stops_activities_and_only_publishes_verified_target()
     {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let cancelled = CancellationToken::new();
        let (id, old, _source) = source(&runtime, true, Some(cancelled.clone())).await;
        let _activity = runtime
            .activities
            .admission
            .reserve_session(
                "session".into(),
                id.clone(),
                "screen".into(),
                cancelled.clone(),
            )
            .unwrap();
        let (port, _target) = target("serial-original").await;
        let receipt = tokio::time::timeout(
            Duration::from_secs(8),
            runtime.raw_tcpip(json!({"deviceId":id,"address":"127.0.0.1","port":port})),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(receipt["connected"], true);
        assert_eq!(receipt["enabled"], true);
        assert_eq!(receipt["deviceId"], id);
        assert_eq!(receipt["device"]["transport"], "tcp");
        assert_eq!(receipt["device"]["port"], port);
        assert!(old.is_closed());
        assert!(cancelled.is_cancelled());
        runtime
            .invoke("devices.disconnect", json!({"deviceId":id}))
            .await
            .unwrap();
    }
    #[tokio::test]
    async fn tcpip_never_admits_another_device_at_the_requested_address() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, old, _source) = source(&runtime, true, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let (port, _target) = target("another-device").await;
        let error = runtime
            .raw_tcpip(json!({"deviceId":id,"address":"127.0.0.1","port":port}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "device_identity_mismatch");
        assert!(old.is_closed());
        assert!(runtime.client(&id).await.is_err());
        let record = runtime.device(&id).await.unwrap();
        assert_eq!(record.status, "offline");
        assert_eq!(record.serial.as_deref(), Some("serial-original"));
        assert!(!record.auto_reconnect);
        assert_connection_preserved(&runtime, &id, &before).await;
    }
    #[tokio::test]
    async fn verified_tcpip_commits_tls_endpoint_and_connection_together() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, _old, _source) = source(&runtime, true, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let mut events = runtime.subscribe();
        let (port, _target) = target("serial-original").await;
        let receipt = runtime
            .raw_tcpip(json!({"deviceId":id,"address":"127.0.0.1","port":port}))
            .await
            .unwrap();
        let expected = json!({"address":"127.0.0.1","port":port,"transport":"tcp","guid":null});
        assert_eq!(receipt["connected"], true);
        assert_eq!(connection_details(&receipt["device"]), expected);
        assert_connection_preserved(&runtime, &id, &expected).await;
        let mut connected = false;
        while let Ok(event) = events.try_recv() {
            if event["type"] != "devices.changed" {
                continue;
            }
            let device = event["data"]["devices"]
                .as_array()
                .unwrap()
                .iter()
                .find(|d| d["id"] == id)
                .unwrap();
            if device["status"] == "connected" {
                connected = true;
                assert_eq!(connection_details(device), expected);
            } else {
                assert_eq!(connection_details(device), before);
            }
        }
        assert!(
            connected,
            "successful conversion must publish its verified connection"
        );
        runtime
            .invoke("devices.disconnect", json!({"deviceId":id}))
            .await
            .unwrap();
    }
    #[tokio::test]
    async fn tcpip_without_target_serial_preserves_tls_record() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, _old, _source) = source(&runtime, true, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let (port, _target) = target("unknown").await;
        let error = runtime
            .raw_tcpip(json!({"deviceId":id,"address":"127.0.0.1","port":port}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "device_identity_unverified");
        assert!(runtime.client(&id).await.is_err());
        assert_connection_preserved(&runtime, &id, &before).await;
    }
    #[tokio::test]
    async fn tcpip_admission_rechecks_identity_before_committing_endpoint() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, _old, _source) = source(&runtime, true, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let identity = runtime.identities.selected(Some(&id)).await.unwrap();
        runtime
            .invoke("identity.global.reset", json!({}))
            .await
            .unwrap();
        let (transport, _peer) = tokio::io::duplex(4096);
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
        let mut info = crate::device::Metadata::default();
        info.serial = Some("serial-original".into());
        info.host_identity = Some(identity.fingerprint.clone());
        let error = runtime
            .attach_tcpip_client(
                &id,
                client.clone(),
                info,
                &CancellationToken::new(),
                ("127.0.0.1".into(), 5555),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "identity_changed");
        assert!(client.is_closed());
        assert!(runtime.client(&id).await.is_err());
        assert_connection_preserved(&runtime, &id, &before).await;
    }
    #[tokio::test]
    async fn unknown_restart_releases_old_connection_without_fabricating_a_target() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, old, _source) = source(&runtime, false, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let error = runtime
            .raw_tcpip(json!({"deviceId":id,"address":"127.0.0.1","port":5555}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "wireless_setup_unknown");
        assert!(old.is_closed());
        assert!(runtime.client(&id).await.is_err());
        assert_eq!(runtime.device(&id).await.unwrap().status, "offline");
        assert_connection_preserved(&runtime, &id, &before).await;
    }
    #[tokio::test]
    async fn cancelling_tcpip_during_target_handshake_rejects_late_connection() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, old, _source) = source(&runtime, true, None).await;
        let before = remember_tls_source(&runtime, &id).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (accepted, waiting) = tokio::sync::oneshot::channel();
        let release = Arc::new(tokio::sync::Notify::new());
        let server_release = release.clone();
        let _target = AbortTask(tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(
                Frame::read(&mut socket, 4096, false).await.unwrap().command,
                protocol::CNXN
            );
            accepted.send(()).unwrap();
            server_release.notified().await;
            let _ = Frame::new(
                protocol::CNXN,
                protocol::VERSION,
                4096,
                b"device::\0".to_vec(),
            )
            .write(&mut socket)
            .await;
            serve(socket, "serial-original", false, None).await;
        }));
        let owner = runtime.clone();
        let target_id = id.clone();
        let converting = tokio::spawn(async move {
            owner
                .raw_tcpip(json!({"deviceId":target_id,"address":"127.0.0.1","port":port}))
                .await
        });
        tokio::time::timeout(Duration::from_secs(8), waiting)
            .await
            .unwrap()
            .unwrap();
        assert!(old.is_closed());
        assert_eq!(runtime.device(&id).await.unwrap().status, "connecting");
        assert_connection_preserved(&runtime, &id, &before).await;
        runtime
            .invoke("devices.cancel", json!({"deviceId":id}))
            .await
            .unwrap();
        release.notify_one();
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), converting)
                .await
                .unwrap()
                .unwrap()
                .unwrap_err()
                .code,
            "cancelled"
        );
        assert!(runtime.client(&id).await.is_err());
        assert_eq!(runtime.device(&id).await.unwrap().status, "offline");
        assert!(!runtime.device(&id).await.unwrap().auto_reconnect);
        assert_connection_preserved(&runtime, &id, &before).await;
    }
    #[tokio::test]
    async fn cancelling_tcpip_during_source_metadata_prevents_restart_and_target_admission() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let (id, original, mut peer) = source_transport(&runtime).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let (metadata_opened, ready) = tokio::sync::oneshot::channel();
        let release = Arc::new(tokio::sync::Notify::new());
        let peer_release = release.clone();
        let restart_sent = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let observed_restart = restart_sent.clone();
        let _source = AbortTask(tokio::spawn(async move {
            let request = Frame::read(&mut peer, 4096, true).await.unwrap();
            assert_eq!(request.command, protocol::OPEN);
            assert!(request.payload.starts_with(b"shell:"));
            Frame::new(protocol::OKAY, 1, request.arg0, vec![])
                .write(&mut peer)
                .await
                .unwrap();
            metadata_opened.send(()).unwrap();
            peer_release.notified().await;
            for reply in [
                Frame::new(
                    protocol::WRTE,
                    1,
                    request.arg0,
                    b"Test Phone\n12\n31\nserial-original\n".to_vec(),
                ),
                Frame::new(protocol::CLSE, 1, request.arg0, vec![]),
            ] {
                if reply.write(&mut peer).await.is_err() {
                    return;
                }
            }
            while let Ok(frame) = Frame::read(&mut peer, 4096, true).await {
                if frame.command == protocol::OPEN && frame.payload.starts_with(b"tcpip:") {
                    observed_restart.store(true, std::sync::atomic::Ordering::SeqCst);
                    return;
                }
            }
        }));
        let owner = runtime.clone();
        let target_id = id.clone();
        let converting = tokio::spawn(async move {
            owner
                .raw_tcpip(json!({"deviceId":target_id,"address":"127.0.0.1","port":port}))
                .await
        });
        tokio::time::timeout(Duration::from_secs(5), ready)
            .await
            .unwrap()
            .unwrap();
        runtime
            .invoke("devices.cancel", json!({"deviceId":id}))
            .await
            .unwrap();
        release.notify_one();
        let result = tokio::time::timeout(Duration::from_secs(5), converting)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(result.unwrap_err().code, "cancelled");
        assert!(
            !restart_sent.load(std::sync::atomic::Ordering::SeqCst),
            "cancelled source metadata must never send tcpip"
        );
        assert!(
            tokio::time::timeout(Duration::from_millis(50), listener.accept())
                .await
                .is_err(),
            "cancelled source metadata must never attempt target connection"
        );
        assert!(
            runtime
                .client(&id)
                .await
                .unwrap()
                .same_connection(&original),
            "cancelling the preflight must retain the original authorized connection"
        );
        assert_eq!(runtime.device(&id).await.unwrap().port, 1);
        original.close();
    }
}
