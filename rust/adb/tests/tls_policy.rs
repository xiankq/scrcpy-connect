//! 公开传输接缝上的现代无线降级尝试回归。
use interop_adb::{
    Client, ConnectOptions, Error, HandshakeKind, Identity, OperationOptions, TlsPolicy,
    protocol::{self, Frame},
    wireless::TlsConfig,
};
use std::{
    sync::{Arc, OnceLock},
    time::Duration,
};
use tokio::{io::AsyncReadExt, net::TcpListener};

fn configured_tls() -> (Identity, TlsConfig) {
    static CONFIG: OnceLock<(Identity, TlsConfig)> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let identity = Identity::generate().unwrap();
            let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
            (identity, tls)
        })
        .clone()
}

#[tokio::test]
async fn tls_certificate_rejections_are_structured_authorization_errors() {
    use tokio::io::AsyncWriteExt;
    // 使用真实 TLS record，不依赖 rustls Display 文本。adbd 可在收到加密 ADB CNXN 前拒绝客户端证书；HandshakeFailure（40）是 TLS 失败，不代表授权决定。
    for (alert, authorization) in [
        (42, true),
        (46, true),
        (48, true),
        (49, true),
        (116, true),
        (40, false),
    ] {
        let (identity, tls) = configured_tls();
        let (transport, mut peer) = tokio::io::duplex(16384);
        let server = tokio::spawn(async move {
            assert_eq!(
                Frame::read(&mut peer, 4096, false).await.unwrap().command,
                protocol::CNXN
            );
            Frame::new(protocol::STLS, 0x0100_0000, 0, Vec::new())
                .write(&mut peer)
                .await
                .unwrap();
            assert_eq!(
                Frame::read(&mut peer, 4096, false).await.unwrap().command,
                protocol::STLS
            );
            peer.write_all(&[21, 3, 3, 0, 2, 2, alert]).await.unwrap();
            let _ = peer.read(&mut [0; 4096]).await;
        });
        let result = Client::connect_transport(
            transport,
            ConnectOptions {
                identity: Some(identity),
                tls: Some(tls),
                tls_policy: TlsPolicy::Required,
                ..Default::default()
            },
        )
        .await;
        assert_eq!(
            matches!(result, Err(Error::AuthorizationRequired)),
            authorization,
            "alert {alert}: {:?}",
            result.err()
        );
        server.await.unwrap();
    }
}

async fn rejects_plaintext(response: Frame) {
    let (identity, tls) = configured_tls();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let request = Frame::read(&mut socket, 4096, false).await.unwrap();
        assert_eq!(request.command, protocol::CNXN);
        response.write(&mut socket).await.unwrap();
        tokio::time::timeout(Duration::from_secs(2), socket.read(&mut [0; 1]))
            .await
            .expect("downgrade rejection must close the socket promptly")
            .unwrap()
    });
    let result = Client::connect_tcp(
        address,
        ConnectOptions {
            identity: Some(identity.clone()),
            request_authorization: true,
            tls: Some(tls.clone()),
            tls_policy: TlsPolicy::Required,
            operations: OperationOptions {
                timeout: Duration::from_secs(3),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .await;
    if let Ok(client) = &result {
        client.close();
    }
    let bytes_after_challenge = server.await.unwrap();
    assert!(
        matches!(result, Err(Error::Protocol(ref message)) if message.contains("TLS is required")),
        "a modern wireless endpoint must not connect or authenticate in plaintext"
    );
    assert_eq!(
        bytes_after_challenge, 0,
        "must not send an RSA signature or offer a public key before TLS"
    );
}

#[tokio::test]
async fn required_tls_rejects_plaintext_cnxn() {
    rejects_plaintext(Frame::new(
        protocol::CNXN,
        protocol::VERSION,
        4096,
        b"device::features=shell_v2;\0".to_vec(),
    ))
    .await;
}

#[tokio::test]
async fn required_tls_rejects_plaintext_auth_without_sending_credentials() {
    rejects_plaintext(Frame::new(protocol::AUTH, 1, 0, vec![0x7a; 20])).await;
}

#[tokio::test]
async fn required_tls_completes_stls_and_reads_cnxn_inside_tls() {
    use rsa::{
        RsaPrivateKey,
        pkcs8::{DecodePrivateKey, EncodePrivateKey},
    };
    use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
    let (identity, tls) = configured_tls();
    let configured_public_key = identity.public_key("").unwrap();
    let key = RsaPrivateKey::from_pkcs8_pem(&identity.to_pkcs8_pem().unwrap())
        .unwrap()
        .to_pkcs8_der()
        .unwrap();
    // 本线上夹具验证加密与协商，不验证 adbd 主控密钥库；独立 BoringSSL 测试额外请求主控证书。
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
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(protocol::STLS, 0x0100_0000, 0, Vec::new())
            .write(&mut socket)
            .await
            .unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::STLS
        );
        let mut encrypted = tokio_rustls::TlsAcceptor::from(Arc::new(config))
            .accept(socket)
            .await
            .unwrap();
        assert_eq!(
            encrypted.get_ref().1.protocol_version(),
            Some(rustls::ProtocolVersion::TLSv1_3)
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0".to_vec(),
        )
        .write(&mut encrypted)
        .await
        .unwrap();
        let open = Frame::read(&mut encrypted, 4096, true).await.unwrap();
        assert_eq!(open.command, protocol::OPEN);
        assert_eq!(open.payload, b"shell:encrypted-only\0");
        Frame::new(protocol::CLSE, 0, open.arg0, Vec::new())
            .write(&mut encrypted)
            .await
            .unwrap();
    });
    let client = Client::connect_tcp(
        address,
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            tls_policy: TlsPolicy::Required,
            operations: OperationOptions {
                timeout: Duration::from_secs(5),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert_eq!(client.security().handshake, HandshakeKind::Tls);
    assert_eq!(
        client.security().configured_public_key.as_ref(),
        Some(&configured_public_key)
    );
    assert!(client.info().features.contains("shell_v2"));
    assert!(matches!(
        client
            .open("shell:encrypted-only", OperationOptions::default())
            .await,
        Err(Error::Closed)
    ));
    client.close();
    server.await.unwrap();
}

#[tokio::test]
async fn optional_tls_keeps_legacy_plaintext_auth_and_cnxn_compatible() {
    let (identity, tls) = configured_tls();
    let configured_public_key = identity.public_key("").unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
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
        let signature = Frame::read(&mut socket, 4096, false).await.unwrap();
        assert_eq!((signature.command, signature.arg0), (protocol::AUTH, 2));
        assert_eq!(signature.payload.len(), 256);
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=;\0".to_vec(),
        )
        .write(&mut socket)
        .await
        .unwrap();
        assert_eq!(socket.read(&mut [0; 1]).await.unwrap(), 0);
    });
    let client = Client::connect_tcp(
        address,
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            tls_policy: TlsPolicy::Optional,
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert_eq!(client.security().handshake, HandshakeKind::Auth);
    assert_eq!(
        client.security().configured_public_key.as_ref(),
        Some(&configured_public_key)
    );
    client.close();
    server.await.unwrap();
}

#[tokio::test]
async fn configured_key_does_not_turn_an_unauthenticated_cnxn_into_authentication() {
    let (identity, _) = configured_tls();
    let configured = identity.public_key("").unwrap();
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
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert_eq!(client.security().handshake, HandshakeKind::Plaintext);
    assert_eq!(
        client.security().configured_public_key.as_ref(),
        Some(&configured)
    );
    let mut copied = client.security().clone();
    copied.configured_public_key.as_mut().unwrap().clear();
    assert_eq!(
        client.clone().security().configured_public_key.as_ref(),
        Some(&configured)
    );
    client.close();
    release.send(()).unwrap();
    server.await.unwrap();
}

#[tokio::test]
async fn external_negotiation_does_not_invent_handshake_or_key_facts() {
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
    assert_eq!(client.security().handshake, HandshakeKind::Unknown);
    assert_eq!(client.security().configured_public_key, None);
    client.close();
}

#[tokio::test]
async fn required_tls_without_configuration_fails_before_sending_a_handshake() {
    let (transport, mut peer) = tokio::io::duplex(4096);
    let result = Client::connect_transport(
        transport,
        ConnectOptions {
            tls_policy: TlsPolicy::Required,
            ..Default::default()
        },
    )
    .await;
    assert!(matches!(result, Err(Error::InvalidArgument(_))));
    assert_eq!(peer.read(&mut [0; 1]).await.unwrap(), 0);
}
