//! 实际传输协商与公开身份快照；磁盘替换不改变存活连接的事实。
use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn configured_identity_keeps_the_handshake_snapshot_after_the_key_file_is_replaced() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory
        .path()
        .canonicalize()
        .unwrap()
        .join("host.pem")
        .to_string_lossy()
        .into_owned();
    let original = Identity::generate().unwrap();
    let pem = original.to_pkcs8_pem().unwrap();
    let published = adb_replace_identity(path.clone(), pem.to_string(), None)
        .await
        .unwrap()
        .identity
        .unwrap();
    let material = crate::identity::prepare(path.clone()).await.unwrap();
    let (transport, mut peer) = tokio::io::duplex(4096);
    let (release, released) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        assert_eq!(
            Frame::read(&mut peer, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::\0".to_vec(),
        )
        .write(&mut peer)
        .await
        .unwrap();
        released.await.unwrap();
    });
    let client = Client::connect_transport(
        transport,
        ConnectOptions {
            identity: Some(material),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let id = insert_connection(client.clone(), "identity-snapshot".into(), false)
        .unwrap()
        .id;
    let replacement = Identity::generate().unwrap().to_pkcs8_pem().unwrap();
    let changed = adb_replace_identity(
        path.clone(),
        replacement.to_string(),
        Some(published.fingerprint.clone()),
    )
    .await
    .unwrap();
    let current = adb_inspect_identity(path).await.unwrap().unwrap();
    assert_eq!(current.fingerprint, changed.identity.unwrap().fingerprint);
    assert_ne!(current.fingerprint, published.fingerprint);
    let facts = adb_connection_facts(id.clone()).unwrap();
    assert_eq!(
        facts.handshake,
        AdbHandshakeKind::Plaintext,
        "配置密钥不能把未认证 CNXN 改称 AUTH"
    );
    let configured = facts.configured_identity.expect("保留连接时配置的公开身份");
    assert_eq!(configured.fingerprint, published.fingerprint);
    assert_eq!(configured.fingerprint_algorithm, "sha256");
    assert_eq!(configured.fingerprint_input, "adb-public-key-interop-v1");
    assert_eq!((configured.bits, configured.exponent), (2048, 65537));
    adb_disconnect(id).await.unwrap();
    client.close();
    release.send(()).unwrap();
    server.await.unwrap();
}

#[tokio::test]
async fn observed_auth_and_external_negotiation_remain_distinct_from_configured_identity() {
    let identity = Identity::generate().unwrap();
    let (transport, mut peer) = tokio::io::duplex(4096);
    let (release, released) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        assert_eq!(
            Frame::read(&mut peer, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(protocol::AUTH, 1, 0, [0x7a; 20])
            .write(&mut peer)
            .await
            .unwrap();
        let signature = Frame::read(&mut peer, 4096, false).await.unwrap();
        assert_eq!((signature.command, signature.arg0), (protocol::AUTH, 2));
        assert_eq!(signature.payload.len(), 256);
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::\0".to_vec(),
        )
        .write(&mut peer)
        .await
        .unwrap();
        released.await.unwrap();
    });
    let client = Client::connect_transport(
        transport,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let id = insert_connection(client.clone(), "auth-facts".into(), false)
        .unwrap()
        .id;
    let facts = adb_connection_facts(id.clone()).unwrap();
    assert_eq!(facts.handshake, AdbHandshakeKind::Auth);
    assert!(facts.configured_identity.is_some());
    adb_disconnect(id).await.unwrap();
    client.close();
    release.send(()).unwrap();
    server.await.unwrap();

    let (transport, _peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        interop_adb::DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let id = insert_connection(client.clone(), "external-facts".into(), false)
        .unwrap()
        .id;
    let facts = adb_connection_facts(id.clone()).unwrap();
    assert_eq!(facts.handshake, AdbHandshakeKind::Unknown);
    assert!(facts.configured_identity.is_none());
    adb_disconnect(id).await.unwrap();
    client.close();
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::test]
async fn official_server_reports_delegated_handshake_without_an_invented_host_identity() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        for expected in ["host:tport:serial:fixture", "host-transport-id:42:features"] {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut length = [0; 4];
            socket.read_exact(&mut length).await.unwrap();
            let length = usize::from_str_radix(std::str::from_utf8(&length).unwrap(), 16).unwrap();
            let mut service = vec![0; length];
            socket.read_exact(&mut service).await.unwrap();
            assert_eq!(service, expected.as_bytes());
            socket.write_all(b"OKAY").await.unwrap();
            if expected.contains("tport") {
                socket.write_all(&42u64.to_le_bytes()).await.unwrap();
            } else {
                socket.write_all(b"0008shell_v2").await.unwrap();
            }
        }
    });
    let device = adb_connect_server(address.to_string(), "fixture".into(), 1000, None)
        .await
        .unwrap();
    let facts = adb_connection_facts(device.id.clone()).unwrap();
    assert!(facts.official_server);
    assert_eq!(
        facts.server_address.as_deref(),
        Some(address.to_string().as_str())
    );
    assert!(!facts.connection_id.is_empty());
    assert_eq!(facts.transport_id, Some(42));
    assert_eq!(facts.handshake, AdbHandshakeKind::DelegatedServer);
    assert!(
        facts.configured_identity.is_none(),
        "smart socket 没有提供 server 实际配置密钥的事实"
    );
    assert!(facts.protocol_version.is_none());
    adb_disconnect(device.id).await.unwrap();
    server.await.unwrap();
}
