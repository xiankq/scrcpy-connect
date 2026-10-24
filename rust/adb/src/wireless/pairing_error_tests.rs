//! 真实 TLS/SPAKE2 peer 在收到主控公钥后断开或取消，必须保留对端信任未知。
use super::*;
use rustls::{ServerConfig, pki_types::PrivatePkcs8KeyDer};
use std::sync::{Arc, OnceLock};
use tokio_util::sync::CancellationToken;

fn credentials() -> (Identity, TlsConfig) {
    static PEM: OnceLock<String> = OnceLock::new();
    let pem = PEM.get_or_init(|| {
        Identity::generate()
            .unwrap()
            .to_pkcs8_pem()
            .unwrap()
            .to_string()
    });
    let identity = Identity::from_pem(pem).unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    (identity, tls)
}

#[derive(Clone, Copy)]
enum Reply {
    Disconnect,
    Cancel,
    Success,
}

async fn exchange(reply: Reply) -> (Result<PairingResult>, CancellationToken) {
    let (identity, tls) = credentials();
    let pem = identity.to_pkcs8_pem().unwrap();
    let key = RsaPrivateKey::from_pkcs8_pem(&pem)
        .unwrap()
        .to_pkcs8_der()
        .unwrap();
    let config = ServerConfig::builder_with_provider(tls.inner.crypto_provider().clone())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(
            vec![tls.certificate_der().to_vec().into()],
            PrivatePkcs8KeyDer::from(key.as_bytes().to_vec()).into(),
        )
        .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let cancellation = CancellationToken::new();
    let stop = cancellation.clone();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut stream = tokio_rustls::TlsAcceptor::from(Arc::new(config))
            .accept(socket)
            .await
            .unwrap();
        let mut exporter = [0; 64];
        stream
            .get_ref()
            .1
            .export_keying_material(&mut exporter, b"adb-label\0", None)
            .unwrap();
        let mut secret = b"123456".to_vec();
        secret.extend_from_slice(&exporter);
        let spake = spake2::Spake2::new(
            spake2::Role::Bob,
            b"adb pair server\0",
            b"adb pair client\0",
            &secret,
            &mut rsa::rand_core::OsRng,
        );
        let incoming = receive(&mut stream, frame::PacketType::Spake2Msg)
            .await
            .unwrap();
        send(&mut stream, frame::PacketType::Spake2Msg, spake.message())
            .await
            .unwrap();
        let material = spake.finish(&incoming).unwrap();
        let mut cipher = aead::Cipher::new(&*material);
        let incoming = receive(&mut stream, frame::PacketType::PeerInfo)
            .await
            .unwrap();
        let public_key = cipher.open(&incoming).unwrap();
        assert_eq!(
            peer_info::decode(&public_key).unwrap().0,
            peer_info::PeerInfoType::RsaPublicKey
        );
        // 到此已真实取得主控公钥；丢弃回执不能再承诺配对未发生。
        match reply {
            Reply::Disconnect => {}
            Reply::Cancel => {
                stop.cancel();
                let mut byte = [0];
                let _ = stream.read(&mut byte).await;
            }
            Reply::Success => {
                let guid =
                    peer_info::encode(peer_info::PeerInfoType::DeviceGuid, b"known-guid").unwrap();
                send(
                    &mut stream,
                    frame::PacketType::PeerInfo,
                    &cipher.seal(&guid),
                )
                .await
                .unwrap();
            }
        }
    });
    let socket = tokio::net::TcpStream::connect(address).await.unwrap();
    let result = pair(
        socket,
        "123456",
        &identity,
        &tls,
        "test",
        &OperationOptions {
            timeout: std::time::Duration::from_secs(20),
            cancellation: cancellation.clone(),
        },
    )
    .await;
    peer.await.unwrap();
    (result, cancellation)
}

use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};

#[tokio::test]
async fn peer_info_receipt_loss_keeps_pairing_result_unknown() {
    let (result, _) = exchange(Reply::Disconnect).await;
    assert!(matches!(result, Err(Error::PairingResultUnknown(_))));
}

#[tokio::test]
async fn cancellation_after_peer_info_preserves_unknown_instead_of_plain_cancelled() {
    let (result, stop) = exchange(Reply::Cancel).await;
    assert!(stop.is_cancelled());
    assert!(
        matches!(result, Err(Error::PairingResultUnknown(source)) if matches!(*source, Error::Cancelled))
    );
}

#[tokio::test]
async fn confirmed_guid_remains_a_successful_pairing_fact() {
    let (result, stop) = exchange(Reply::Success).await;
    stop.cancel();
    assert_eq!(result.unwrap().guid, "known-guid");
}
