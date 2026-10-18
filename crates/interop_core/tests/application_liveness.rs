//! Real TCP/TLS peer: the kernel still ACKs and the socket remains readable,
//! while the first peer stops processing ADB services. No packet filters/root.
use interop_adb::{
    CancellationToken, Identity,
    protocol::{self, Frame},
    wireless::TlsConfig,
};
use interop_core::Runtime;
use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
use serde_json::{Value, json};
use std::{
    sync::{Arc, OnceLock},
    time::Duration,
};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::{broadcast, mpsc, oneshot},
    task::{JoinHandle, JoinSet},
};

const RECOVERY_DEADLINE: Duration = Duration::from_secs(40);

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

async fn handshake(
    mut socket: TcpStream,
    config: Arc<rustls::ServerConfig>,
) -> tokio_rustls::server::TlsStream<TcpStream> {
    socket.set_nodelay(true).unwrap();
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
    Frame::new(
        protocol::CNXN,
        protocol::VERSION,
        4096,
        b"device::features=shell_v2;\0".to_vec(),
    )
    .write(&mut encrypted)
    .await
    .unwrap();
    encrypted
}

struct Peer {
    port: u16,
    arm: Option<oneshot::Sender<()>>,
    armed: oneshot::Receiver<()>,
    accepted: mpsc::UnboundedReceiver<usize>,
    closed: mpsc::UnboundedReceiver<usize>,
    ignored: mpsc::UnboundedReceiver<Vec<u8>>,
    replied: mpsc::UnboundedReceiver<()>,
    cancellation: CancellationToken,
    task: JoinHandle<()>,
}

impl Drop for Peer {
    fn drop(&mut self) {
        self.cancellation.cancel();
        self.task.abort();
    }
}

impl Peer {
    async fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let config = tls_server();
        let (arm, arm_rx) = oneshot::channel();
        let (armed_tx, armed) = oneshot::channel();
        let (accepted_tx, accepted) = mpsc::unbounded_channel();
        let (closed_tx, closed) = mpsc::unbounded_channel();
        let (ignored_tx, ignored) = mpsc::unbounded_channel();
        let (replied_tx, replied) = mpsc::unbounded_channel();
        let cancellation = CancellationToken::new();
        let token = cancellation.clone();
        let task = tokio::spawn(async move {
            let mut first_fault = Some((arm_rx, armed_tx));
            let mut connections = JoinSet::new();
            let mut count = 0;
            loop {
                tokio::select! {
                    _ = token.cancelled() => break,
                    done = connections.join_next(), if !connections.is_empty() => {
                        done.unwrap().expect("TLS peer task must not panic");
                    }
                    incoming = listener.accept() => {
                        let (socket, _) = incoming.unwrap();
                        count += 1;
                        let index = count;
                        let _ = accepted_tx.send(index);
                        let config = config.clone();
                        let fault = first_fault.take();
                        let token = token.clone();
                        let closed_tx = closed_tx.clone();
                        let ignored_tx = ignored_tx.clone();
                        let replied_tx = replied_tx.clone();
                        connections.spawn(async move {
                            let mut encrypted = handshake(socket, config).await;
                            let (mut arm, mut armed) = match fault {
                                Some((arm, armed)) => (Some(arm), Some(armed)),
                                None => (None, None),
                            };
                            let mut stalled = false;
                            loop {
                                tokio::select! {
                                    _ = token.cancelled() => return,
                                    result = async {arm.as_mut().unwrap().await}, if arm.is_some() => {
                                        result.expect("fault owner must arm the peer");
                                        arm = None;
                                        stalled = true;
                                        let _ = armed.take().unwrap().send(());
                                    }
                                    incoming = Frame::read(&mut encrypted, 4096, false) => {
                                        let Ok(frame) = incoming else {break};
                                        if stalled {
                                            if frame.command == protocol::OPEN {
                                                let _ = ignored_tx.send(frame.payload);
                                            }
                                            // Consume real TLS bytes while sending no ADB
                                            // response. TCP ACK/keepalive remain healthy.
                                            continue;
                                        }
                                        if frame.command == protocol::OPEN {
                                            // Service rejection is a valid response from
                                            // a live adbd; it must not cause reconnection.
                                            if Frame::new(protocol::CLSE, 0, frame.arg0, vec![])
                                                .write(&mut encrypted).await.is_err() {break;}
                                            let _ = replied_tx.send(());
                                        }
                                    }
                                }
                            }
                            let _ = closed_tx.send(index);
                        });
                    }
                }
            }
        });
        Self {
            port,
            arm: Some(arm),
            armed,
            accepted,
            closed,
            ignored,
            replied,
            cancellation,
            task,
        }
    }
}

async fn invoke(runtime: &Arc<Runtime>, command: &str, params: Value) -> Value {
    Box::pin(runtime.invoke(command, params)).await.unwrap()
}

async fn state_event(events: &mut broadcast::Receiver<Value>, id: &str, status: &str) -> Value {
    loop {
        let event = events.recv().await.expect("complete runtime event stream");
        let record = match event["type"].as_str() {
            Some("devices.changed") => event["data"]["devices"]
                .as_array()
                .and_then(|devices| devices.iter().find(|device| device["id"] == id)),
            Some("device.changed") if event["deviceId"] == id => Some(&event["data"]),
            _ => None,
        };
        if record.is_some_and(|device| device["id"] == id && device["status"] == status) {
            return event;
        }
    }
}

#[tokio::test]
async fn application_stall_recovers_and_explicit_disconnect_prevents_revival() {
    let mut peer = Peer::start().await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut events = runtime.subscribe();
    let added = invoke(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":peer.port,"transport":"tls"}),
    )
    .await;
    let id = added["deviceId"].as_str().unwrap().to_owned();
    invoke(&runtime, "observation.stop", json!({"deviceId":id})).await;
    let connected = invoke(&runtime, "devices.connect", json!({"deviceId":id})).await;
    assert_eq!(connected["connected"], true);
    assert_eq!(peer.accepted.recv().await, Some(1));
    tokio::time::timeout(
        Duration::from_secs(2),
        state_event(&mut events, &id, "connected"),
    )
    .await
    .unwrap();
    peer.arm.take().unwrap().send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), &mut peer.armed)
        .await
        .unwrap()
        .unwrap();

    let recovery = tokio::time::timeout(RECOVERY_DEADLINE, async {
        let offline = state_event(&mut events, &id, "offline").await;
        let online = state_event(&mut events, &id, "connected").await;
        (offline, online)
    })
    .await;
    assert!(
        recovery.is_ok(),
        "an ADB application stall with healthy TCP ACKs must become offline and reconnect"
    );
    let (offline, online) = recovery.unwrap();
    assert!(online["sequence"].as_u64().unwrap() > offline["sequence"].as_u64().unwrap());
    assert_eq!(peer.accepted.recv().await, Some(2));
    assert_eq!(peer.closed.recv().await, Some(1));
    assert_eq!(peer.ignored.try_recv().unwrap(), b"sync:\0");
    let devices = invoke(&runtime, "devices.list", json!({})).await;
    assert_eq!(devices["devices"].as_array().unwrap().len(), 1);
    assert_eq!(devices["devices"][0]["id"], id);
    assert_eq!(devices["devices"][0]["status"], "connected");

    invoke(&runtime, "devices.disconnect", json!({"deviceId":id})).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.closed.recv())
            .await
            .unwrap(),
        Some(2)
    );
    assert_eq!(
        invoke(&runtime, "device.info", json!({"deviceId":id})).await["autoReconnect"],
        false
    );
    assert!(
        tokio::time::timeout(Duration::from_secs(5), peer.accepted.recv())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn healthy_idle_peer_can_reject_services_without_being_disconnected() {
    let mut peer = Peer::start().await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = invoke(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":peer.port,"transport":"tls"}),
    )
    .await;
    let id = added["deviceId"].as_str().unwrap().to_owned();
    invoke(&runtime, "observation.stop", json!({"deviceId":id})).await;
    assert_eq!(
        invoke(&runtime, "devices.connect", json!({"deviceId":id})).await["connected"],
        true
    );
    assert_eq!(peer.accepted.recv().await, Some(1));
    while peer.replied.try_recv().is_ok() {}
    // Two independently observed protocol responses after metadata has ended.
    // OPEN rejection must count as liveness, not permission to reconnect.
    for _ in 0..2 {
        tokio::time::timeout(Duration::from_secs(18), peer.replied.recv())
            .await
            .expect("idle connection must eventually be probed")
            .expect("healthy peer must answer the probe");
    }
    assert_eq!(
        invoke(&runtime, "device.info", json!({"deviceId":id})).await["status"],
        "connected"
    );
    assert!(
        peer.accepted.try_recv().is_err(),
        "no replacement transport for a live peer"
    );
    assert!(
        peer.closed.try_recv().is_err(),
        "original transport must remain open"
    );
    invoke(&runtime, "devices.disconnect", json!({"deviceId":id})).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.closed.recv())
            .await
            .unwrap(),
        Some(1)
    );
}

#[tokio::test]
async fn explicit_replacement_during_a_stalled_probe_keeps_new_connection_alive() {
    let mut peer = Peer::start().await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = invoke(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":peer.port,"transport":"tls"}),
    )
    .await;
    let id = added["deviceId"].as_str().unwrap().to_owned();
    invoke(&runtime, "observation.stop", json!({"deviceId":id})).await;
    invoke(&runtime, "devices.connect", json!({"deviceId":id})).await;
    assert_eq!(peer.accepted.recv().await, Some(1));
    peer.arm.take().unwrap().send(()).unwrap();
    (&mut peer.armed).await.unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(18), peer.ignored.recv())
            .await
            .unwrap()
            .unwrap(),
        b"sync:\0"
    );
    invoke(&runtime, "devices.disconnect", json!({"deviceId":id})).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.closed.recv())
            .await
            .unwrap(),
        Some(1)
    );
    invoke(&runtime, "devices.connect", json!({"deviceId":id})).await;
    assert_eq!(peer.accepted.recv().await, Some(2));
    while peer.replied.try_recv().is_ok() {}
    tokio::time::timeout(Duration::from_secs(18), peer.replied.recv())
        .await
        .expect("replacement must survive old probe completion and be probed itself")
        .unwrap();
    assert_eq!(
        invoke(&runtime, "device.info", json!({"deviceId":id})).await["status"],
        "connected"
    );
    assert!(
        peer.closed.try_recv().is_err(),
        "old probe must not close replacement"
    );
    assert!(
        peer.accepted.try_recv().is_err(),
        "old probe must not provoke a third transport"
    );
    invoke(&runtime, "devices.disconnect", json!({"deviceId":id})).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.closed.recv())
            .await
            .unwrap(),
        Some(2)
    );
}
