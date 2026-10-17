//! Public Runtime tests with real DNS-SD and TLS sockets. Run explicitly on a
//! multicast-capable network; these do not require Android or an external adb.
use interop_adb::{
    Identity, OperationOptions,
    protocol::{self, Frame},
    wireless::{
        TlsConfig,
        discovery::{CONNECT_SERVICE, Discovery, DiscoveryEvent},
    },
};
use interop_core::Runtime;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
use serde_json::{Value, json};
use std::{
    net::{IpAddr, Ipv4Addr, UdpSocket},
    sync::{Arc, OnceLock},
    time::Duration,
};
use tokio::net::TcpListener;

type Gate = (
    tokio::sync::oneshot::Sender<()>,
    tokio::sync::oneshot::Receiver<()>,
);

fn tls_server() -> Arc<rustls::ServerConfig> {
    static CONFIG: OnceLock<Arc<rustls::ServerConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let identity = Identity::generate().unwrap();
            let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
            let key = RsaPrivateKey::from_pkcs8_pem(&identity.to_pkcs8_pem().unwrap())
                .unwrap()
                .to_pkcs8_der()
                .unwrap();
            Arc::new(
                rustls::ServerConfig::builder_with_provider(
                    Arc::new(rustls_rustcrypto::provider()),
                )
                .with_protocol_versions(&[&rustls::version::TLS13])
                .unwrap()
                .with_no_client_auth()
                .with_single_cert(
                    vec![CertificateDer::from(tls.certificate_der().to_vec())],
                    PrivatePkcs8KeyDer::from(key.as_bytes().to_vec()).into(),
                )
                .unwrap(),
            )
        })
        .clone()
}

fn network_address() -> Ipv4Addr {
    let socket = UdpSocket::bind("0.0.0.0:0").unwrap();
    // Routing lookup only: no datagram is sent.
    socket.connect("224.0.0.251:5353").unwrap();
    let IpAddr::V4(address) = socket.local_addr().unwrap().ip() else {
        panic!("IPv4 interface required")
    };
    address
}

async fn peer(address: Ipv4Addr) -> (u16, tokio::task::JoinHandle<()>) {
    peer_with_gate(address, None).await
}

async fn peer_with_gate(
    address: Ipv4Addr,
    gate: Option<Gate>,
) -> (u16, tokio::task::JoinHandle<()>) {
    peer_with_gates(address, gate, None).await
}

async fn peer_with_gates(
    address: Ipv4Addr,
    tls_gate: Option<Gate>,
    mut metadata_gate: Option<Gate>,
) -> (u16, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind((address, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let config = tls_server();
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
        let mut encrypted = tokio_rustls::TlsAcceptor::from(config)
            .accept(socket)
            .await
            .unwrap();
        if let Some((ready, release)) = tls_gate {
            ready.send(()).unwrap();
            release.await.unwrap();
        }
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0".to_vec(),
        )
        .write(&mut encrypted)
        .await
        .unwrap();
        while let Ok(frame) = Frame::read(&mut encrypted, 4096, false).await {
            if frame.command == protocol::OPEN {
                if let Some((ready, release)) = metadata_gate.take() {
                    ready.send(()).unwrap();
                    release.await.unwrap();
                }
                // Metadata unavailability does not close the TLS transport.
                Frame::new(protocol::CLSE, 0, frame.arg0, vec![])
                    .write(&mut encrypted)
                    .await
                    .unwrap();
            }
        }
    });
    (port, task)
}

async fn restored(directory: &std::path::Path, guid: &str) -> (Arc<Runtime>, String) {
    restored_with_port(directory, guid, 9).await
}

async fn restored_with_port(
    directory: &std::path::Path,
    guid: &str,
    port: u16,
) -> (Arc<Runtime>, String) {
    let runtime = Runtime::initialize(directory).await.unwrap();
    let added = runtime
        .invoke(
            "devices.add",
            json!({"address":"127.0.0.1","port":9,"transport":"tls"}),
        )
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap().to_owned();
    drop(runtime);
    let path = directory.join("devices.json");
    let mut store: Value = serde_json::from_slice(&tokio::fs::read(&path).await.unwrap()).unwrap();
    store["devices"][0]["guid"] = json!(guid);
    store["devices"][0]["port"] = json!(port);
    // A restored GUID still requires TLS even if old transport metadata says TCP.
    store["devices"][0]["transport"] = json!("tcp");
    store["devices"][0]["autoReconnect"] = json!(true);
    store["devices"][0]["observationWanted"] = json!(false);
    tokio::fs::write(path, serde_json::to_vec(&store).unwrap())
        .await
        .unwrap();
    (Runtime::initialize(directory).await.unwrap(), id)
}

fn publish(publisher: &ServiceDaemon, guid: &str, addresses: &str, port: u16) -> String {
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
    let fullname = service.get_fullname().to_owned();
    publisher.register(service).unwrap();
    fullname
}

async fn connected(runtime: &Arc<Runtime>, id: &str, port: u16) -> Value {
    tokio::time::timeout(Duration::from_secs(18), async {
        loop {
            let record = runtime
                .invoke("device.info", json!({"deviceId":id}))
                .await
                .unwrap();
            if record["status"] == "connected" && record["port"] == port {
                return record;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .expect("a trusted service must reconnect through its reachable candidate")
}

async fn discovered(browser: &Discovery, fullname: &str, removed: bool) {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            match browser
                .next(&OperationOptions {
                    timeout: Duration::from_secs(15),
                    ..Default::default()
                })
                .await
                .unwrap()
            {
                DiscoveryEvent::Resolved(service) if !removed && service.fullname == fullname => {
                    break;
                }
                DiscoveryEvent::Removed { fullname: name } if removed && name == fullname => break,
                _ => {}
            }
        }
    })
    .await
    .expect("fixture announcement must be visible over real multicast");
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn runtime_reconnects_using_a_trusted_services_second_address() {
    let address = network_address();
    let mut unavailable = address.octets();
    assert_ne!(unavailable[3], 0, "fixture needs a nonzero host octet");
    unavailable[3] = 0;
    let unavailable = Ipv4Addr::from(unavailable);
    let (port, server) = peer(address).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-fallback-{}", uuid::Uuid::new_v4());
    let publisher = ServiceDaemon::new().unwrap();
    let browser = Discovery::new().unwrap();
    let fullname = publish(&publisher, &guid, &format!("{unavailable},{address}"), port);
    let (runtime, id) = restored_with_port(directory.path(), &guid, 0).await;
    let advertised = tokio::time::timeout(Duration::from_secs(15), async {
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
    .unwrap();
    assert_eq!(
        advertised.endpoints,
        vec![(unavailable, port).into(), (address, port).into()],
        "the actual DNS answer must include the unreachable candidate before the reachable one"
    );
    let record = connected(&runtime, &id, port).await;
    assert_eq!(record["address"], address.to_string());
    assert_eq!(record["transport"], "tls");
    assert_eq!(
        runtime.invoke("devices.list", Value::Null).await.unwrap()["devices"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    server.await.unwrap();
    publisher.unregister(&fullname).unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn runtime_uses_changed_ports_and_does_not_retry_withdrawn_or_untrusted_services() {
    let address = network_address();
    let (first_port, first_server) = peer(address).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-changes-{}", uuid::Uuid::new_v4());
    let publisher = ServiceDaemon::new().unwrap();
    let browser = Discovery::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), first_port);
    let (runtime, id) = restored(directory.path(), &guid).await;
    connected(&runtime, &id, first_port).await;
    discovered(&browser, &fullname, false).await;

    let (second_port, second_server) = peer(address).await;
    publish(&publisher, &guid, &address.to_string(), second_port);
    first_server.abort();
    let record = connected(&runtime, &id, second_port).await;
    assert_eq!(record["id"], id);

    let attacker = TcpListener::bind((address, 0)).await.unwrap();
    let attacker_name = publish(
        &publisher,
        &format!("{guid}-attacker"),
        &address.to_string(),
        attacker.local_addr().unwrap().port(),
    );
    publisher
        .unregister(&fullname)
        .unwrap()
        .recv_async()
        .await
        .unwrap();
    discovered(&browser, &fullname, true).await;
    // Allow the monitor's two-second polling window to consume the goodbye
    // before dropping the existing transport, which may legitimately stay up.
    tokio::time::sleep(Duration::from_secs(3)).await;
    second_server.abort();
    let _ = second_server.await;
    let retired = TcpListener::bind((address, second_port)).await.unwrap();
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            if runtime
                .invoke("device.info", json!({"deviceId":id}))
                .await
                .unwrap()["status"]
                == "offline"
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap();
    assert!(tokio::time::timeout(Duration::from_secs(5), async {
        tokio::select! { result = retired.accept() => result, result = attacker.accept() => result }
    }).await.is_err(), "a goodbye must suppress cached endpoints and a GUID prefix must not confer trust");
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(record["autoReconnect"], true);
    assert_eq!(record["port"], second_port);
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    publisher.unregister(&attacker_name).unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn discovered_candidates_never_accept_a_plaintext_daemon() {
    use tokio::io::AsyncReadExt;
    let address = network_address();
    let listener = TcpListener::bind((address, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(protocol::AUTH, 1, 0, vec![0x7a; 20])
            .write(&mut socket)
            .await
            .unwrap();
        assert_eq!(
            socket.read(&mut [0; 1]).await.unwrap(),
            0,
            "no RSA credential or service may be sent before required TLS"
        );
    });
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-required-{}", uuid::Uuid::new_v4());
    let publisher = ServiceDaemon::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), port);
    let (runtime, id) = restored(directory.path(), &guid).await;
    tokio::time::timeout(Duration::from_secs(15), server)
        .await
        .unwrap()
        .unwrap();
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_ne!(record["status"], "connected");
    assert_eq!(
        record["address"], "127.0.0.1",
        "failed advertisements must not replace the last known endpoint"
    );
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    publisher.unregister(&fullname).unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn an_obsolete_tls_attempt_cannot_publish_a_connected_device_after_an_address_update() {
    let address = network_address();
    let (ready, started) = tokio::sync::oneshot::channel();
    let (release, gate) = tokio::sync::oneshot::channel();
    let (old_port, old_server) = peer_with_gate(address, Some((ready, gate))).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-late-{}", uuid::Uuid::new_v4());
    let publisher = ServiceDaemon::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), old_port);
    let (runtime, id) = restored(directory.path(), &guid).await;
    let mut events = runtime.subscribe();
    tokio::time::timeout(Duration::from_secs(15), started)
        .await
        .unwrap()
        .unwrap();
    let (current_port, current_server) = peer(address).await;
    publish(&publisher, &guid, &address.to_string(), current_port);
    tokio::time::sleep(Duration::from_secs(3)).await;
    release.send(()).unwrap();
    connected(&runtime, &id, current_port).await;
    while let Ok(event) = events.try_recv() {
        if event["type"] == "device.changed" && event["data"]["status"] == "connected" {
            assert_eq!(
                event["data"]["port"], current_port,
                "a retired endpoint must never be presented as a usable connection"
            );
        }
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    old_server.await.unwrap();
    current_server.await.unwrap();
    publisher.unregister(&fullname).unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn a_cached_tls_attempt_cannot_connect_after_discovery_supplies_a_new_endpoint() {
    let address = network_address();
    let (ready, started) = tokio::sync::oneshot::channel();
    let (release, gate) = tokio::sync::oneshot::channel();
    let (cached_port, cached_server) =
        peer_with_gate(Ipv4Addr::LOCALHOST, Some((ready, gate))).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-cached-{}", uuid::Uuid::new_v4());
    let (runtime, id) = restored_with_port(directory.path(), &guid, cached_port).await;
    let mut events = runtime.subscribe();
    tokio::time::timeout(Duration::from_secs(15), started)
        .await
        .unwrap()
        .unwrap();

    let (current_port, current_server) = peer(address).await;
    let publisher = ServiceDaemon::new().unwrap();
    let browser = Discovery::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), current_port);
    discovered(&browser, &fullname, false).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    release.send(()).unwrap();

    let first_connected = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let event = events.recv().await.unwrap();
            if event["type"] == "device.changed" && event["data"]["status"] == "connected" {
                break event;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(
        first_connected["data"]["port"], current_port,
        "discovery must retire a cached attempt that started before its first DNS answer"
    );
    connected(&runtime, &id, current_port).await;
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    cached_server.await.unwrap();
    current_server.await.unwrap();
    publisher.unregister(&fullname).unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn a_cached_tls_attempt_cannot_connect_after_a_discovery_goodbye() {
    let address = network_address();
    let (ready, started) = tokio::sync::oneshot::channel();
    let (release, gate) = tokio::sync::oneshot::channel();
    let (cached_port, cached_server) =
        peer_with_gate(Ipv4Addr::LOCALHOST, Some((ready, gate))).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-cached-goodbye-{}", uuid::Uuid::new_v4());
    let (runtime, id) = restored_with_port(directory.path(), &guid, cached_port).await;
    let mut events = runtime.subscribe();
    tokio::time::timeout(Duration::from_secs(15), started)
        .await
        .unwrap()
        .unwrap();

    let publisher = ServiceDaemon::new().unwrap();
    let browser = Discovery::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), cached_port);
    discovered(&browser, &fullname, false).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    publisher
        .unregister(&fullname)
        .unwrap()
        .recv_async()
        .await
        .unwrap();
    discovered(&browser, &fullname, true).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    release.send(()).unwrap();

    tokio::time::timeout(Duration::from_secs(5), cached_server)
        .await
        .expect("the withdrawn cached attempt must be closed")
        .unwrap();
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(record["status"], "offline");
    assert_eq!(record["autoReconnect"], true);
    assert_eq!(record["port"], cached_port);
    while let Ok(event) = events.try_recv() {
        assert!(
            event["type"] != "device.changed" || event["data"]["status"] != "connected",
            "a goodbye must retire even a connection begun before discovery resolved"
        );
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    publisher.shutdown().unwrap();
}

#[tokio::test]
#[ignore = "requires multicast-capable IPv4 networking"]
async fn withdrawing_and_reannouncing_the_same_endpoint_retires_its_old_attempt() {
    let address = network_address();
    let (ready, started) = tokio::sync::oneshot::channel();
    let (release, gate) = tokio::sync::oneshot::channel();
    let (port, server) = peer_with_gates(address, None, Some((ready, gate))).await;
    let directory = tempfile::tempdir().unwrap();
    let guid = format!("adb-reannounced-{}", uuid::Uuid::new_v4());
    let publisher = ServiceDaemon::new().unwrap();
    let browser = Discovery::new().unwrap();
    let fullname = publish(&publisher, &guid, &address.to_string(), port);
    let (runtime, id) = restored(directory.path(), &guid).await;
    let mut events = runtime.subscribe();
    tokio::time::timeout(Duration::from_secs(15), started)
        .await
        .unwrap()
        .unwrap();
    discovered(&browser, &fullname, false).await;

    publisher
        .unregister(&fullname)
        .unwrap()
        .recv_async()
        .await
        .unwrap();
    discovered(&browser, &fullname, true).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    publish(&publisher, &guid, &address.to_string(), port);
    discovered(&browser, &fullname, false).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    release.send(()).unwrap();

    tokio::time::timeout(Duration::from_secs(3), server)
        .await
        .expect("an old connection cannot survive withdrawal followed by the identical address")
        .unwrap();
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(record["status"], "offline");
    assert_eq!(record["autoReconnect"], true);
    while let Ok(event) = events.try_recv() {
        assert!(
            event["type"] != "device.changed" || event["data"]["status"] != "connected",
            "an unchanged endpoint must not make a withdrawn attempt current again"
        );
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    publisher.unregister(&fullname).unwrap();
    publisher.shutdown().unwrap();
}
