//! Explicit adbd TCP listener transition. A restart receipt is never connection proof.
use crate::{
    CoreError, CoreResult, Runtime,
    device::{endpoint, host, metadata, port},
    model::required,
};
use interop_adb::{Client, OperationOptions};
use serde_json::{Value, json};
use std::time::Duration;
use tokio_util::sync::CancellationToken;

struct SourceConnection(Client);
impl Drop for SourceConnection {
    fn drop(&mut self) {
        self.0.close();
    }
}

fn requested_port(params: &Value) -> CoreResult<u16> {
    if params.get("port").is_some() {
        port(params)
    } else {
        Ok(5555)
    }
}
fn restart_confirmed(response: &[u8], port: u16) -> bool {
    std::str::from_utf8(response)
        .is_ok_and(|value| value.trim() == format!("restarting in TCP mode port: {port}"))
}
async fn request_restart(client: &Client, port: u16, token: CancellationToken) -> CoreResult<()> {
    let options = OperationOptions {
        timeout: Duration::from_secs(10),
        cancellation: token,
    };
    let cancellation = options.cancellation.clone();
    let mut stream = client
        .open(&format!("tcpip:{port}"), options)
        .await
        .map_err(|_| {
            CoreError::new(
                "wireless_setup_unknown",
                "未能确认设备是否接收监听切换请求，请核对设备当前监听状态。",
            )
        })?;
    let mut bytes = Vec::new();
    let read_result = tokio::time::timeout(Duration::from_secs(10), async {
        let mut buffer = [0; 1024];
        loop {
            match stream.read(&mut buffer).await {
                Ok(0) => break,
                Ok(count) if bytes.len() + count <= 8192 => {
                    bytes.extend_from_slice(&buffer[..count])
                }
                Ok(_) => {
                    return Err(CoreError::new(
                        "wireless_setup_unknown",
                        "设备返回了过长的监听切换结果，请核对设备当前监听状态。",
                    ));
                }
                Err(interop_adb::Error::Closed) if !bytes.is_empty() => break,
                Err(_) => {
                    return Err(CoreError::new(
                        "wireless_setup_unknown",
                        "连接在确认监听切换前中断，请核对设备当前监听状态。",
                    ));
                }
            }
        }
        if restart_confirmed(&bytes, port) {
            Ok(())
        } else {
            Err(CoreError::new(
                "wireless_setup_failed",
                "设备未确认在指定端口开启 TCP 监听，请检查设备设置后重试。",
            ))
        }
    });
    tokio::select! {
        _ = cancellation.cancelled() => Err(CoreError::new("cancelled", "监听切换已取消，请核对设备当前监听状态。")),
        result = read_result => result.map_err(|_| CoreError::new("wireless_setup_unknown", "等待监听切换结果超时，请核对设备当前监听状态。"))?,
    }
}
impl Runtime {
    pub(crate) async fn enable_wireless(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let address = host(params)?;
        let port = requested_port(params)?;
        let token = CancellationToken::new();
        // Cancellation owns this token before any source I/O or transition wait.
        // Never install a fresh token after a cancelled metadata request returns.
        if let Some(previous) = self
            .device_operations
            .lock()
            .await
            .insert(id.into(), token.clone())
        {
            previous.cancel();
        }
        let mut cleanup = self.connections.transition(id).await;
        if token.is_cancelled() {
            return Err(CoreError::new("cancelled", "连接切换已取消。"));
        }
        let record = self.device(id).await?;
        let client = self.client(id).await?;
        let material = self.identities.selected(Some(id)).await?;
        let source = metadata(&client, token.clone()).await;
        if token.is_cancelled() {
            return Err(CoreError::new("cancelled", "连接切换已取消。"));
        }
        let serial = source.serial.as_deref().ok_or_else(|| {
            CoreError::new(
                "device_identity_unverified",
                "无法读取当前设备序列号，暂不能安全切换连接。",
            )
        })?;
        if record
            .serial
            .as_deref()
            .is_some_and(|known| known != serial)
        {
            return Err(CoreError::new(
                "device_identity_mismatch",
                "当前连接的设备身份与记录不同。",
            ));
        }
        {
            let _pending = self.device_operations.lock().await;
            if token.is_cancelled() {
                return Err(CoreError::new("cancelled", "连接切换已取消。"));
            }
            let mut store = self.store.write().await;
            let mut connections = self.connections.lock().await;
            *cleanup = true;
            connections.remove(id);
            if let Some(record) = store.devices.iter_mut().find(|record| record.id == id) {
                record.serial = Some(serial.into());
                record.status = "connecting".into();
                record.auto_reconnect = false;
                record.reason = Some("正在切换 TCP 监听；原连接活动已停止。".into());
            }
        }
        let _source_owner = SourceConnection(client.clone());
        self.stop_device_activities(id).await?;
        self.changed_devices().await?;
        let restart = request_restart(&client, port, token.clone()).await;
        client.close();
        *cleanup = false;
        if let Err(error) = restart {
            self.tcpip_failed(id, &token, &error).await?;
            return Err(error);
        }
        {
            let _pending = self.device_operations.lock().await;
            if token.is_cancelled() {
                return Err(CoreError::new(
                    "cancelled",
                    "连接切换已取消，请核对设备当前监听状态。",
                ));
            }
            let mut store = self.store.write().await;
            let record = store
                .devices
                .iter_mut()
                .find(|device| device.id == id)
                .ok_or_else(|| CoreError::new("not_found", "设备记录已移除。"))?;
            record.status = "connecting".into();
            record.reason = Some("设备已确认 TCP 监听，正在核验目标设备身份。".into());
        }
        self.changed_devices().await?;
        drop(cleanup);
        let result = tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                if token.is_cancelled() { return Err(CoreError::new("cancelled", "连接切换已取消。")); }
                let mut options = self.connect_options_for(Some(id), token.clone()).await?;
                if crate::host_identity::fingerprint(options.identity.as_ref().expect("selected identity"))? != material.fingerprint {
                    return Err(CoreError::new("identity_changed", "授权身份已改变，请重新连接。"));
                }
                options.operations.timeout = Duration::from_secs(4);
                match Client::connect_tcp(endpoint(&address, port), options).await {
                    Ok(client) => {
                        let mut info = metadata(&client, token.clone()).await;
                        if info.serial.as_deref() != Some(serial) {
                            client.close();
                            return Err(CoreError::new(if info.serial.is_some() {"device_identity_mismatch"} else {"device_identity_unverified"}, "目标地址的设备身份无法与原设备核验，请检查地址后重试。"));
                        }
                        info.host_identity = Some(material.fingerprint.clone());
                        return Ok((client, info));
                    }
                    Err(interop_adb::Error::AuthorizationRequired) => return Err(CoreError::new("authorization_required", "TCP 连接需要在被控设备重新确认授权。")),
                    Err(interop_adb::Error::Cancelled) => return Err(CoreError::new("cancelled", "连接切换已取消。")),
                    Err(_) => tokio::select! {
                        _ = token.cancelled() => return Err(CoreError::new("cancelled", "连接切换已取消。")),
                        _ = tokio::time::sleep(Duration::from_millis(300)) => {},
                    },
                }
            }
        }).await.unwrap_or_else(|_| Err(CoreError::new("timeout", "TCP 监听已开启，但目标地址尚未连接；请核对地址和端口后重试。")));
        let result = match result {
            Ok((client, info)) => {
                self.attach_tcpip_client(id, client, info, &token, (address, port))
                    .await
            }
            Err(error) => Err(error),
        };
        match result {
            Ok(mut receipt) => {
                receipt["enabled"] = json!(true);
                receipt["port"] = json!(port);
                receipt["encrypted"] = json!(false);
                Ok(receipt)
            }
            Err(error) => {
                self.tcpip_failed(id, &token, &error).await?;
                Err(error)
            }
        }
    }
    async fn tcpip_failed(
        &self,
        id: &str,
        token: &CancellationToken,
        error: &CoreError,
    ) -> CoreResult<()> {
        let _pending = self.device_operations.lock().await;
        if !token.is_cancelled() {
            let mut store = self.store.write().await;
            if let Some(record) = store.devices.iter_mut().find(|device| device.id == id) {
                record.status = if error.code == "authorization_required" {
                    "unauthorized"
                } else {
                    "offline"
                }
                .into();
                record.auto_reconnect = false;
                record.reason = Some(error.message.clone());
            }
        }
        drop(_pending);
        self.changed_devices().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TransportKind;
    #[test]
    fn listener_port_is_validated_and_receipt_binds_exact_requested_port() {
        assert_eq!(requested_port(&json!({})).unwrap(), 5555);
        assert_eq!(requested_port(&json!({"port":65535})).unwrap(), 65535);
        for value in [json!(0), json!(-1), json!(65536), json!(1.5), json!("bad")] {
            assert!(requested_port(&json!({"port":value})).is_err());
        }
        assert!(restart_confirmed(
            b"restarting in TCP mode port: 5555\n",
            5555
        ));
        assert!(!restart_confirmed(
            b"restarting in TCP mode port: 5556\n",
            5555
        ));
        assert!(!restart_confirmed(
            b"error: restarting in TCP mode port: 5555",
            5555
        ));
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
            runtime.invoke(
                "devices.wireless",
                json!({"deviceId":id,"address":"127.0.0.1","port":port}),
            ),
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
            .invoke(
                "devices.wireless",
                json!({"deviceId":id,"address":"127.0.0.1","port":port}),
            )
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
            .invoke(
                "devices.wireless",
                json!({"deviceId":id,"address":"127.0.0.1","port":port}),
            )
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
            .invoke(
                "devices.wireless",
                json!({"deviceId":id,"address":"127.0.0.1","port":port}),
            )
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
            .invoke(
                "devices.wireless",
                json!({"deviceId":id,"address":"127.0.0.1","port":5555}),
            )
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
                .invoke(
                    "devices.wireless",
                    json!({"deviceId":target_id,"address":"127.0.0.1","port":port}),
                )
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
                .invoke(
                    "devices.wireless",
                    json!({"deviceId":target_id,"address":"127.0.0.1","port":port}),
                )
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
