//! Authenticated loopback ADB peer used by connection-lifecycle tests.
use interop_adb::{
    Identity,
    protocol::{self, Frame},
    wireless::TlsConfig,
};
use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
use std::sync::{Arc, OnceLock};
use tokio::net::TcpStream;

pub type Gate = (
    tokio::sync::oneshot::Sender<()>,
    tokio::sync::oneshot::Receiver<()>,
);

pub fn server_config() -> Arc<rustls::ServerConfig> {
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

pub async fn handshake(
    mut socket: TcpStream,
    config: Arc<rustls::ServerConfig>,
    gate: Option<Gate>,
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
    if let Some((ready, release)) = gate {
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
    encrypted
}
