use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::net::TcpListener;

async fn peer(serial: &'static str) -> (SocketAddr, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0",
        )
        .write(&mut socket)
        .await
        .unwrap();
        while let Ok(frame) = Frame::read(&mut socket, 4096, true).await {
            if frame.command != protocol::OPEN {
                continue;
            }
            if Frame::new(protocol::OKAY, frame.arg0 + 100, frame.arg0, [])
                .write(&mut socket)
                .await
                .is_err()
            {
                break;
            }
            let service = String::from_utf8_lossy(&frame.payload);
            let text = if service.contains("getprop ro.serialno") {
                format!("Fixture\n16\n36\n{serial}\n")
            } else {
                String::new()
            };
            let mut payload = vec![1];
            payload.extend_from_slice(&(text.len() as u32).to_le_bytes());
            payload.extend_from_slice(text.as_bytes());
            payload.extend_from_slice(&[3, 1, 0, 0, 0, 0]);
            if Frame::new(protocol::WRTE, frame.arg0 + 100, frame.arg0, payload)
                .write(&mut socket)
                .await
                .is_err()
            {
                break;
            }
        }
    });
    (address, task)
}

async fn original(runtime: &Runtime) -> String {
    let added = runtime
        .add_device(&json!({"address":"original.local","port":5555,"transport":"tcp"}))
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap().to_owned();
    let mut store = runtime.store.write().await;
    let device = store.devices.iter_mut().find(|d| d.id == id).unwrap();
    device.serial = Some("original-serial".into());
    device.observation_wanted = false;
    id
}

#[tokio::test]
async fn verified_configuration_updates_only_the_original_record() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let id = original(&runtime).await;
    let (address, server) = peer("original-serial").await;
    let result = runtime.configure_device(&json!({
        "deviceId":id,"address":address.ip().to_string(),"port":address.port(),"transport":"tcp",
    })).await.unwrap();
    assert_eq!(result["deviceId"], id);
    assert_eq!(result["connected"], true);
    assert_eq!(runtime.store.read().await.devices.len(), 1);
    let current = runtime.device(&id).await.unwrap();
    assert_eq!(current.port, address.port());
    assert_eq!(current.serial.as_deref(), Some("original-serial"));
    runtime.stop_all().await;
    server.abort();
}

#[tokio::test]
async fn wrong_target_does_not_change_saved_configuration_or_live_client() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let id = original(&runtime).await;
    let (transport, _peer) = tokio::io::duplex(4096);
    let live = Client::from_negotiated_transport(
        transport,
        interop_adb::DeviceInfo {
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
        .insert(id.clone(), live.clone());
    runtime
        .store
        .write()
        .await
        .devices
        .iter_mut()
        .find(|d| d.id == id)
        .unwrap()
        .status = "connected".into();
    let (address, server) = peer("another-phone").await;
    let failure = runtime.configure_device(&json!({
        "deviceId":id,"address":address.ip().to_string(),"port":address.port(),"transport":"tcp",
    })).await.unwrap_err();
    assert_eq!(failure.code, "device_identity_mismatch");
    let current = runtime.device(&id).await.unwrap();
    assert_eq!(current.address, "original.local");
    assert_eq!(current.port, 5555);
    assert_eq!(current.status, "connected");
    assert!(!live.is_closed());
    assert_eq!(runtime.store.read().await.devices.len(), 1);
    runtime.stop_all().await;
    server.abort();
}

#[tokio::test]
async fn reauthorization_retains_original_transport_and_endpoint_until_target_connection() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let id = original(&runtime).await;
    runtime
        .store
        .write()
        .await
        .devices
        .iter_mut()
        .find(|d| d.id == id)
        .unwrap()
        .transport = TransportKind::Usb;
    let result = runtime
        .finish_pairing(
            "new-guid".into(),
            "candidate.local".into(),
            Some(&id),
            &CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(result["connected"], false);
    let current = runtime.device(&id).await.unwrap();
    assert!(current.transport.is_usb());
    assert_eq!(current.address, "original.local");
    assert_eq!(current.guid, None);
    assert_eq!(runtime.store.read().await.devices.len(), 1);
    runtime.stop_all().await;
}

#[tokio::test]
async fn first_pairing_binds_its_dedicated_identity_without_changing_the_global_key() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let global = runtime
        .identities
        .selected(None)
        .await
        .unwrap()
        .fingerprint
        .clone();
    let key = interop_adb::Identity::generate().unwrap();
    let (material, dedicated) = runtime
        .identities
        .for_attempt(
            &json!({
                "identity":{"scope":"device","privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()},
            }),
            None,
        )
        .await
        .unwrap();
    assert!(dedicated);
    let fingerprint = material.fingerprint.clone();
    let op = runtime
        .new_setup_operation(
            &json!({"attemptId":"custom-first-pair","leaseMs":180000}),
            None,
            fingerprint.clone(),
        )
        .await
        .unwrap();
    let _ = op.dedicated_identity.set(material);
    let result = runtime
        .finish_pairing_record("custom-guid".into(), "phone.local".into(), None, &op)
        .await
        .unwrap();
    let id = result["deviceId"].as_str().unwrap().to_owned();
    assert_eq!(
        runtime
            .identities
            .selected(Some(&id))
            .await
            .unwrap()
            .fingerprint,
        fingerprint
    );
    assert_eq!(
        runtime.identities.selected(None).await.unwrap().fingerprint,
        global
    );
    assert_eq!(runtime.store.read().await.devices.len(), 1);
    runtime.stop_all().await;
    drop(runtime);
    let restored = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        restored
            .identities
            .selected(Some(&id))
            .await
            .unwrap()
            .fingerprint,
        fingerprint
    );
}
