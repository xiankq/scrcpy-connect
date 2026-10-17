//! Public Runtime recovery through a real TLS transport whose original TCP
//! socket stays open while its incoming packets (including keepalives) drop.
#![cfg(any(target_os = "linux", target_os = "android"))]

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
use socket2::{SockFilter, SockRef};
use std::{sync::Arc, time::Duration};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::{broadcast, mpsc, oneshot},
    task::{JoinHandle, JoinSet},
};

const RECOVERY_DEADLINE: Duration = Duration::from_secs(25);

async fn invoke(
    runtime: &Arc<Runtime>,
    command: &str,
    params: Value,
) -> Result<Value, interop_core::CoreError> {
    // Keep Runtime's large command future off the Android test-thread stack.
    Box::pin(runtime.invoke(command, params)).await
}

fn tls_server() -> Arc<rustls::ServerConfig> {
    // Generate a fixture identity in memory; never use an installed host key.
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let key = RsaPrivateKey::from_pkcs8_pem(&identity.to_pkcs8_pem().unwrap())
        .unwrap()
        .to_pkcs8_der()
        .unwrap();
    Arc::new(
        rustls::ServerConfig::builder_with_provider(Arc::new(rustls_rustcrypto::provider()))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(
                vec![CertificateDer::from(tls.certificate_der().to_vec())],
                PrivatePkcs8KeyDer::from(key.as_bytes().to_vec()).into(),
            )
            .unwrap(),
    )
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

async fn metadata_peer(socket: &mut tokio_rustls::server::TlsStream<TcpStream>) {
    while let Ok(frame) = Frame::read(socket, 4096, false).await {
        if frame.command == protocol::OPEN {
            // Unsupported metadata is a valid ADB service response and does
            // not close the authenticated transport or prevent attachment.
            if Frame::new(protocol::CLSE, 0, frame.arg0, vec![])
                .write(socket)
                .await
                .is_err()
            {
                return;
            }
        }
    }
}

struct Peer {
    port: u16,
    arm: Option<oneshot::Sender<()>>,
    armed: oneshot::Receiver<Result<(), String>>,
    accepted: mpsc::UnboundedReceiver<usize>,
    closed: mpsc::UnboundedReceiver<usize>,
    cancellation: CancellationToken,
    task: JoinHandle<()>,
}

impl Drop for Peer {
    fn drop(&mut self) {
        self.cancellation.cancel();
        // Dropping the server's JoinSet also aborts all accepted-socket tasks,
        // including the intentionally retained first TLS connection.
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
        let cancellation = CancellationToken::new();
        let token = cancellation.clone();
        let task = tokio::spawn(async move {
            let mut first_fault = Some((arm_rx, armed_tx));
            let mut connections = JoinSet::new();
            let mut count = 0;
            loop {
                tokio::select! {
                    _ = token.cancelled() => break,
                    finished = connections.join_next(), if !connections.is_empty() => {
                        finished.unwrap().expect("TLS peer task must not panic");
                    }
                    incoming = listener.accept() => {
                        let (socket, _) = incoming.unwrap();
                        count += 1;
                        let index = count;
                        accepted_tx.send(index).unwrap();
                        let fault = first_fault.take();
                        let config = config.clone();
                        let token = token.clone();
                        let closed_tx = closed_tx.clone();
                        connections.spawn(async move {
                            let mut encrypted = tokio::select! {
                                _ = token.cancelled() => return,
                                socket = handshake(socket, config) => socket,
                            };
                            if let Some((arm, armed)) = fault {
                                tokio::select! {
                                    _ = token.cancelled() => return,
                                    result = arm => result.expect("fault owner must arm the socket"),
                                    _ = metadata_peer(&mut encrypted) => {
                                        panic!("first transport closed before the fault was armed");
                                    }
                                }
                                // BPF_RET | BPF_K, RET 0. This filters only this
                                // owned accepted socket before TCP processes
                                // packets; the listener and reconnect stay live.
                                let result = SockRef::from(encrypted.get_ref().0)
                                    .attach_filter(&[SockFilter::new(0x06, 0, 0, 0)])
                                    .map_err(|error| format!("SO_ATTACH_FILTER: {error}"));
                                armed.send(result).unwrap();
                                // Hold the original TLS/TCP object even after
                                // the host times out: EOF must not cause recovery.
                                token.cancelled().await;
                                drop(encrypted);
                            } else {
                                tokio::select! {
                                    _ = token.cancelled() => return,
                                    _ = metadata_peer(&mut encrypted) => {}
                                }
                                let _ = closed_tx.send(index);
                            }
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
            cancellation,
            task,
        }
    }
}

async fn state_event(events: &mut broadcast::Receiver<Value>, id: &str, status: &str) -> Value {
    loop {
        let event = events
            .recv()
            .await
            .expect("runtime event stream must remain complete");
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
#[ignore = "requires SO_ATTACH_FILTER permission; Android AVD shell su 0 or a permitted Linux process"]
async fn runtime_reconnects_after_tls_tcp_blackhole_and_disconnect_prevents_revival() {
    let mut peer = Peer::start().await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut events = runtime.subscribe();
    let added = invoke(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":peer.port,"transport":"tls"}),
    )
    .await
    .unwrap();
    let id = added["deviceId"].as_str().unwrap().to_owned();
    // Keep this transport otherwise idle: no companion polling should hide a
    // missing keepalive implementation by generating unrelated service I/O.
    invoke(&runtime, "observation.stop", json!({"deviceId":id}))
        .await
        .unwrap();
    let connected = tokio::time::timeout(
        RECOVERY_DEADLINE,
        invoke(&runtime, "devices.connect", json!({"deviceId":id})),
    )
    .await
    .expect("initial manual TLS connection must complete")
    .unwrap();
    assert_eq!(connected["connected"], true);
    assert_eq!(connected["device"]["autoReconnect"], true);
    tokio::time::timeout(
        Duration::from_secs(2),
        state_event(&mut events, &id, "connected"),
    )
    .await
    .unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.accepted.recv())
            .await
            .unwrap(),
        Some(1),
    );

    // Arm only after the public Runtime has committed the first connection.
    peer.arm.take().unwrap().send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), &mut peer.armed)
        .await
        .expect("fault installation must acknowledge")
        .expect("first accepted socket must stay alive")
        .expect("this ignored test requires socket-filter permission");

    let (offline, reconnected) = tokio::time::timeout(RECOVERY_DEADLINE, async {
        let offline = state_event(&mut events, &id, "offline").await;
        let reconnected = state_event(&mut events, &id, "connected").await;
        (offline, reconnected)
    })
    .await
    .expect("blackholed TLS transport must become offline and automatically reconnect");
    assert!(reconnected["sequence"].as_u64().unwrap() > offline["sequence"].as_u64().unwrap());
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.accepted.recv())
            .await
            .unwrap(),
        Some(2),
        "recovery must use a new TCP/TLS connection",
    );
    let devices = invoke(&runtime, "devices.list", json!({})).await.unwrap();
    let devices = devices["devices"].as_array().unwrap();
    assert_eq!(
        devices.len(),
        1,
        "reconnect must not create a second device record"
    );
    assert_eq!(devices[0]["id"], id);
    assert_eq!(devices[0]["status"], "connected");
    assert_eq!(devices[0]["autoReconnect"], true);

    invoke(&runtime, "devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    let disconnected = invoke(&runtime, "device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(disconnected["status"], "offline");
    assert_eq!(disconnected["autoReconnect"], false);
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.closed.recv())
            .await
            .unwrap(),
        Some(2),
        "explicit disconnect must close the replacement transport",
    );
    // Observe actual accept events for more than two monitor periods, instead
    // of sleeping and merely checking a remembered connection status.
    assert!(
        tokio::time::timeout(Duration::from_secs(5), peer.accepted.recv())
            .await
            .is_err(),
        "explicit disconnect must suppress another TCP connection attempt",
    );
}
