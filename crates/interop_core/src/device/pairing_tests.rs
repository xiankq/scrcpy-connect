//! Exercise completion of an already authenticated pairing through real DNS-SD
//! and STLS/TLS/CNXN sockets. PAKE itself is tested independently in interop-adb.
use super::*;
use interop_adb::{
    Identity,
    protocol::{self, Frame},
};
use mdns_sd::{ServiceDaemon, ServiceInfo};
use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
use std::net::{IpAddr, Ipv4Addr, UdpSocket};
use tokio::net::TcpListener;

// Each test owns its publisher and tasks. Unwinding an assertion must still
// withdraw advertisements and stop listeners, including a stalled TLS peer.
struct AbortTask<T>(tokio::task::JoinHandle<T>);

impl<T> Drop for AbortTask<T> {
    fn drop(&mut self) {
        self.0.abort();
    }
}

struct Advertisement {
    daemon: ServiceDaemon,
    fullname: String,
}

impl Advertisement {
    fn new(guid: &str, addresses: &str, port: u16) -> Self {
        let daemon = ServiceDaemon::new().unwrap();
        let mut advertisement = Self {
            daemon,
            fullname: String::new(),
        };
        advertisement.publish(guid, addresses, port);
        advertisement
    }

    fn publish(&mut self, guid: &str, addresses: &str, port: u16) {
        let mut service = ServiceInfo::new(
            CONNECT_SERVICE,
            guid,
            &format!("{guid}.local."),
            addresses,
            port,
            None,
        )
        .unwrap();
        service.set_requires_probe(false);
        self.fullname = service.get_fullname().to_owned();
        self.daemon.register(service).unwrap();
    }

    fn withdraw(&self) {
        self.daemon.unregister(&self.fullname).unwrap();
    }
}

impl Drop for Advertisement {
    fn drop(&mut self) {
        let _ = self.daemon.unregister(&self.fullname);
        let _ = self.daemon.shutdown();
    }
}

async fn resolved(browser: &Discovery, fullname: &str) -> Service {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            if let DiscoveryEvent::Resolved(service) =
                browser.next(&OperationOptions::default()).await.unwrap()
                && service.fullname == fullname
            {
                break service;
            }
        }
    })
    .await
    .expect("the real DNS-SD advertisement must be observable")
}

async fn stored_devices(directory: &std::path::Path) -> Value {
    serde_json::from_slice(
        &tokio::fs::read(directory.join("devices.json"))
            .await
            .unwrap(),
    )
    .unwrap()
}

fn network_address() -> Ipv4Addr {
    let socket = UdpSocket::bind("0.0.0.0:0").unwrap();
    // Route lookup only; this sends no datagram.
    socket.connect("224.0.0.251:5353").unwrap();
    let IpAddr::V4(address) = socket.local_addr().unwrap().ip() else {
        panic!("multicast-capable IPv4 interface required")
    };
    address
}

async fn tls_peer(address: Ipv4Addr) -> (u16, AbortTask<()>) {
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let key = RsaPrivateKey::from_pkcs8_pem(&identity.to_pkcs8_pem().unwrap())
        .unwrap()
        .to_pkcs8_der()
        .unwrap();
    let config =
        rustls::ServerConfig::builder_with_provider(Arc::new(rustls_rustcrypto::provider()))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(
                vec![CertificateDer::from(tls.certificate_der().to_vec())],
                PrivatePkcs8KeyDer::from(key.as_bytes().to_vec()).into(),
            )
            .unwrap();
    let listener = TcpListener::bind((address, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(protocol::STLS, 0x0100_0000, 0, vec![])
            .write(&mut socket)
            .await
            .unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::STLS
        );
        let mut socket = tokio_rustls::TlsAcceptor::from(Arc::new(config))
            .accept(socket)
            .await
            .unwrap();
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0".to_vec(),
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
    (port, AbortTask(task))
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn pairing_completion_tries_the_second_discovered_address() {
    let address = network_address();
    let mut unavailable = address.octets();
    assert_ne!(unavailable[3], 0);
    unavailable[3] = 0;
    let unavailable = Ipv4Addr::from(unavailable);
    let (port, _peer) = tls_peer(address).await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let guid = format!("adb-pair-completion-{}", uuid::Uuid::new_v4());
    let browser = Discovery::new().unwrap();
    let publisher = Advertisement::new(&guid, &format!("{unavailable},{address}"), port);
    let advertised = resolved(&browser, &publisher.fullname).await;
    assert_eq!(
        advertised.endpoints,
        vec![(unavailable, port).into(), (address, port).into()]
    );
    let result = tokio::time::timeout(
        Duration::from_secs(15),
        runtime.finish_pairing(
            guid.clone(),
            address.to_string(),
            None,
            &CancellationToken::new(),
        ),
    )
    .await;
    // Clean the real publisher and peer even when the original first-address
    // implementation blocks for its full 60-second connect timeout.
    drop(publisher);
    if let Ok(Ok(value)) = &result {
        runtime
            .disconnect_device(value["deviceId"].as_str().unwrap(), false)
            .await
            .unwrap();
    }
    let result = result
        .expect("first unreachable address must not consume the whole pairing completion")
        .unwrap();
    assert_eq!(result["connected"], true, "{result}");
    assert_eq!(result["connectionPortRequired"], false);
    assert_eq!(result["device"]["address"], address.to_string());
    assert_eq!(result["device"]["port"], port);
    assert_eq!(result["device"]["guid"], guid);
    assert_eq!(result["device"]["transport"], "tls");
    let stored = stored_devices(directory.path()).await;
    assert_eq!(stored["devices"].as_array().unwrap().len(), 1);
    assert_eq!(stored["devices"][0]["port"], port);
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn pairing_completion_disconnect_cancels_pending_discovery() {
    let address = network_address();
    let listener = std::net::TcpListener::bind((address, 0)).unwrap();
    listener.set_nonblocking(true).unwrap();
    let port = listener.local_addr().unwrap().port();
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let guid = format!("adb-pair-cancel-{}", uuid::Uuid::new_v4());
    let token = CancellationToken::new();
    let mut finish = AbortTask(tokio::spawn({
        let runtime = runtime.clone();
        let guid = guid.clone();
        let token = token.clone();
        async move {
            runtime
                .finish_pairing(guid, address.to_string(), None, &token)
                .await
        }
    }));
    let id = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            // No advertisement exists yet. The device-operation registration
            // witnesses the completion path entering its cancellable discovery
            // phase, before any TCP connection can have been selected.
            let pending = runtime.device_operations.lock().await;
            let store = runtime.store.read().await;
            if let Some(device) = store
                .devices
                .iter()
                .find(|device| device.guid.as_deref() == Some(&guid))
                && pending.contains_key(&device.id)
            {
                break device.id.clone();
            }
            drop(store);
            drop(pending);
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("pairing completion must register discovery as a device operation");
    runtime.disconnect_device(&id, false).await.unwrap();
    assert!(
        token.is_cancelled(),
        "disconnect must cancel the discovery's own token"
    );

    // Make the candidate observable after the explicit disconnect, using real
    // multicast rather than assuming that waiting a fixed delay resolves it.
    let browser = Discovery::new().unwrap();
    let publisher = Advertisement::new(&guid, &address.to_string(), port);
    resolved(&browser, &publisher.fullname).await;
    let result = tokio::time::timeout(Duration::from_secs(3), &mut finish.0)
        .await
        .expect("cancelled discovery must finish promptly")
        .unwrap()
        .unwrap();
    assert_eq!(result["paired"], true);
    assert_eq!(result["connected"], false);
    assert_eq!(result["device"]["autoReconnect"], false);
    assert_eq!(result["device"]["port"], 0);
    assert!(runtime.connections.lock().await.is_empty());
    assert!(
        matches!(listener.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock),
        "the cancelled completion must never open the advertised TCP endpoint"
    );
    let stored = stored_devices(directory.path()).await;
    assert_eq!(stored["devices"][0]["autoReconnect"], false);
    assert_eq!(stored["devices"][0]["port"], 0);
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn pairing_completion_rejects_plaintext_discovered_endpoint() {
    let address = network_address();
    let listener = TcpListener::bind((address, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (plaintext, observed_plaintext) = tokio::sync::oneshot::channel();
    let _peer = AbortTask(tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0".to_vec(),
        )
        .write(&mut socket)
        .await
        .unwrap();
        // Keep the socket alive until the client actively refuses plaintext.
        assert!(Frame::read(&mut socket, 4096, true).await.is_err());
        let _ = plaintext.send(());
    }));
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let guid = format!("adb-pair-plaintext-{}", uuid::Uuid::new_v4());
    let browser = Discovery::new().unwrap();
    let publisher = Advertisement::new(&guid, &address.to_string(), port);
    resolved(&browser, &publisher.fullname).await;
    let result = tokio::time::timeout(
        Duration::from_secs(15),
        runtime.finish_pairing(
            guid.clone(),
            address.to_string(),
            None,
            &CancellationToken::new(),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    tokio::time::timeout(Duration::from_secs(3), observed_plaintext)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(result["paired"], true);
    assert_eq!(result["connected"], false);
    assert_eq!(
        result["connectionPortRequired"], false,
        "a discovered service did exist"
    );
    assert_eq!(result["device"]["guid"], guid);
    assert_eq!(result["device"]["transport"], "tls");
    assert_eq!(
        result["device"]["port"], 0,
        "a rejected endpoint must not be committed"
    );
    assert!(
        result["device"]["reason"]
            .as_str()
            .unwrap()
            .contains("TLS is required"),
        "{result}"
    );
    assert!(runtime.connections.lock().await.is_empty());
    let stored = stored_devices(directory.path()).await;
    assert_eq!(stored["devices"][0]["port"], 0);
    assert_eq!(stored["devices"][0]["transport"], "tls");
}

async fn wait_for_endpoints(
    discovery: &PairingDiscovery,
    endpoints: Vec<SocketAddr>,
) -> DiscoveredAttempt {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            let attempt = discovery.attempt().await;
            if attempt.endpoints.as_ref() == Some(&endpoints) {
                break attempt;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("the pairing guard's real DNS-SD watcher must observe the change")
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn pairing_discovery_updates_and_goodbye_reject_stale_tls_publication() {
    let address = network_address();
    let (old_port, _old_peer) = tls_peer(address).await;
    let (new_port, _new_peer) = tls_peer(address).await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let guid = format!("adb-pair-epoch-{}", uuid::Uuid::new_v4());
    let mut device = blank_device("192.0.2.77".into(), 0, TransportKind::Tls);
    device.guid = Some(guid.clone());
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    runtime.changed_devices().await.unwrap();
    let token = CancellationToken::new();
    runtime
        .register_connection_operation(&id, true, &token)
        .await
        .unwrap();
    let browser = Discovery::new().unwrap();
    let mut publisher = Advertisement::new(&guid, &address.to_string(), old_port);
    resolved(&browser, &publisher.fullname).await;
    let discovery = runtime.find_connect_endpoints(&guid, &token).await.unwrap();
    let original = wait_for_endpoints(&discovery, vec![(address, old_port).into()]).await;
    let mut options = runtime.connect_options(token.clone()).await.unwrap();
    options.tls_policy = TlsPolicy::Required;
    options.operations.timeout = Duration::from_secs(5);
    let original_client = Client::connect_tcp((address, old_port), options.clone())
        .await
        .unwrap();

    // The old TLS connection has completed CNXN. Move the real announcement
    // before publication and inspect this same guard, so a cached answer or an
    // arbitrary delay cannot stand in for evidence that its watcher advanced.
    publisher.publish(&guid, &address.to_string(), new_port);
    let updated = wait_for_endpoints(&discovery, vec![(address, new_port).into()]).await;
    assert_ne!(original.generation, updated.generation);
    assert!(!original.is_current().await);
    let error = runtime
        .attach_client(
            &id,
            original_client,
            Metadata::default(),
            &token,
            Some((address, old_port).into()),
            Some(&original),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "discovery_changed");
    assert!(runtime.connections.lock().await.is_empty());
    assert_eq!(runtime.device(&id).await.unwrap().port, 0);

    let updated_client = Client::connect_tcp((address, new_port), options)
        .await
        .unwrap();
    publisher.withdraw();
    let withdrawn = wait_for_endpoints(&discovery, vec![]).await;
    assert_ne!(updated.generation, withdrawn.generation);
    assert!(!updated.is_current().await);
    let error = runtime
        .attach_client(
            &id,
            updated_client,
            Metadata::default(),
            &token,
            Some((address, new_port).into()),
            Some(&updated),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "discovery_changed");
    assert!(runtime.connections.lock().await.is_empty());
    let stored = stored_devices(directory.path()).await;
    assert_eq!(stored["devices"][0]["address"], "192.0.2.77");
    assert_eq!(stored["devices"][0]["port"], 0);
    assert_eq!(stored["devices"][0]["status"], "offline");
}

#[tokio::test]
async fn pairing_attempt_aliases_cannot_collide_with_device_operations() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let listener = std::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    listener.set_nonblocking(true).unwrap();
    let device = blank_device(
        "127.0.0.1".into(),
        listener.local_addr().unwrap().port(),
        TransportKind::Tls,
    );
    let device_id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let existing = CancellationToken::new();
    runtime
        .device_operations
        .lock()
        .await
        .insert(device_id.clone(), existing.clone());
    for alias in [
        String::new(),
        "x".repeat(201),
        "nul\0alias".into(),
        device_id,
    ] {
        let error = runtime
            .pair_device(&json!({"address":"127.0.0.1",
            "port":listener.local_addr().unwrap().port(), "code":"123456", "attemptId":alias}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "invalid_argument", "{alias:?}");
        assert!(
            !existing.is_cancelled(),
            "invalid aliases must not replace an existing operation"
        );
        assert_eq!(runtime.device_operations.lock().await.len(), 1);
    }
    assert!(
        matches!(listener.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock),
        "invalid pairing aliases must fail before opening any network socket"
    );
}

#[tokio::test]
async fn qr_reauthorization_requires_the_selected_device_identity() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = blank_device("phone.local".into(), 0, TransportKind::Tls);
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let key = Identity::generate().unwrap();
    runtime
        .invoke(
            "identity.device.import",
            json!({"deviceId":id,"privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()}),
        )
        .await
        .unwrap();
    drop(runtime);
    tokio::fs::remove_file(directory.path().join("device_identities.json"))
        .await
        .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let error = runtime
        .invoke("devices.pair.qr", json!({"deviceId":id}))
        .await
        .unwrap_err();
    assert_eq!(error.code, "identity_unavailable");
    assert!(runtime.qr_attempt.lock().await.is_none());
    assert!(runtime.device_operations.lock().await.is_empty());
    assert_eq!(runtime.store.read().await.devices.len(), 1);
    let error = runtime
        .invoke("devices.pair.qr", json!({"deviceId":"missing"}))
        .await
        .unwrap_err();
    assert_eq!(error.code, "not_found");

    // Adding a new device has no device-specific identity to recover.
    let generated = runtime.invoke("devices.pair.qr", json!({})).await.unwrap();
    assert!(
        generated["payload"]
            .as_str()
            .unwrap()
            .starts_with("WIFI:T:ADB;")
    );
    runtime
        .invoke(
            "devices.cancel",
            json!({"attemptId":generated["attemptId"]}),
        )
        .await
        .unwrap();
}

#[tokio::test]
async fn qr_reauthorization_disconnect_cancels_the_original_attempt() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = blank_device("phone.local".into(), 0, TransportKind::Tls);
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    runtime
        .invoke("devices.pair.qr", json!({"deviceId":id}))
        .await
        .unwrap();
    let token = runtime.qr_attempt.lock().await.as_ref().unwrap().1.clone();
    assert_eq!(
        runtime.device_operations.lock().await.get(&id),
        Some(&token)
    );
    runtime.disconnect_device(&id, false).await.unwrap();
    assert!(token.is_cancelled());
    let fingerprint = runtime
        .identities
        .selected(Some(&id))
        .await
        .unwrap()
        .fingerprint
        .clone();
    let error = runtime
        .finish_pairing_with_identity(
            "late-guid".into(),
            "other.local".into(),
            Some(&id),
            &token,
            Some(&fingerprint),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "cancelled");
    assert_eq!(runtime.device(&id).await.unwrap().address, "phone.local");
    assert_eq!(runtime.store.read().await.devices.len(), 1);
}

#[tokio::test]
async fn qr_reauthorization_commits_only_the_selected_identity_to_the_original_record() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = blank_device("phone.local".into(), 0, TransportKind::Tls);
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let original = runtime.identities.selected(Some(&id)).await.unwrap();
    let key = Identity::generate().unwrap();
    let imported = runtime
        .invoke(
            "identity.device.import",
            json!({"deviceId":id,"privateKeyPem":key.to_pkcs8_pem().unwrap().as_str()}),
        )
        .await
        .unwrap();
    let token = CancellationToken::new();
    let error = runtime
        .finish_pairing_with_identity(
            "late-guid".into(),
            "other.local".into(),
            Some(&id),
            &token,
            Some(&original.fingerprint),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "identity_changed");
    assert!(runtime.device(&id).await.unwrap().guid.is_none());

    let (transport, _peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
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
        .insert(id.clone(), client.clone());
    let result = runtime
        .finish_pairing_with_identity(
            "paired-guid".into(),
            "other.local".into(),
            Some(&id),
            &token,
            imported["fingerprint"].as_str(),
        )
        .await
        .unwrap();
    assert_eq!(result["deviceId"], id);
    assert_eq!(result["connected"], true);
    let store = runtime.store.read().await;
    assert_eq!(store.devices.len(), 1);
    assert_eq!(store.devices[0].guid.as_deref(), Some("paired-guid"));
    assert_eq!(store.devices[0].address, "other.local");
    client.close();
}
