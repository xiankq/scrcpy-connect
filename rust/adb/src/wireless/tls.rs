//! 用于 ADB 配对与 STLS 的 TLS 1.3，提供者由调用方显式选择。
use crate::{Error, Identity, Result, Transport};
use rsa::{
    RsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey},
};
use rustls::{
    ClientConfig, DigitallySignedStruct, SignatureScheme,
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::{
        CryptoProvider, WebPkiSupportedAlgorithms, verify_tls12_signature, verify_tls13_signature,
    },
    pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName, UnixTime},
};
use std::sync::Arc;
use tokio_rustls::{TlsConnector, client::TlsStream};

/// TLS 身份绑定到与旧 AUTH 和配对相同的 RSA 密钥。
#[derive(Clone)]
pub struct TlsConfig {
    pub(crate) inner: Arc<ClientConfig>,
    certificate: CertificateDer<'static>,
    public_key: Vec<u8>,
}
impl std::fmt::Debug for TlsConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TlsConfig")
            .field("version", &"TLS1.3")
            .finish_non_exhaustive()
    }
}
impl TlsConfig {
    /// 使用所选提供者，不改变进程全局 rustls provider。ADB 接受对端自签名证书，但验证 CertificateVerify 签名；配对通过 SPAKE2 和 TLS exporter 认证通道，后续连接由 adbd 在授权密钥库中验证主控公钥。
    pub fn with_provider(identity: &Identity, provider: Arc<CryptoProvider>) -> Result<Self> {
        let pem = identity.to_pkcs8_pem()?;
        let key =
            RsaPrivateKey::from_pkcs8_pem(&pem).map_err(|e| Error::Identity(e.to_string()))?;
        let certificate = CertificateDer::from(
            super::cert::build(&key, &mut rsa::rand_core::OsRng)
                .map_err(|e| Error::Identity(e.to_string()))?,
        );
        let private = key
            .to_pkcs8_der()
            .map_err(|e| Error::Identity(e.to_string()))?;
        let verifier = Arc::new(AdbCertificateVerifier {
            algorithms: provider.signature_verification_algorithms,
        });
        let mut config = ClientConfig::builder_with_provider(provider)
            .with_protocol_versions(&[&rustls::version::TLS13])
            .map_err(tls_error)?
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_client_auth_cert(
                vec![certificate.clone()],
                PrivatePkcs8KeyDer::from(private.as_bytes().to_vec()).into(),
            )
            .map_err(tls_error)?;
        // ADB 以配对关系和公钥识别对端，不使用 DNS 虚拟主机。
        config.enable_sni = false;
        Ok(Self {
            inner: Arc::new(config),
            certificate,
            public_key: identity.public_key("")?,
        })
    }
    /// 实验性纯 Rust 提供者，固定 rustls-rustcrypto 0.0.2-alpha。上游 README 明确警告禁止用于生产；选择本方法即承认该限制，互操作测试不等于密码安全审查或生产批准。
    pub fn experimental_rustcrypto(identity: &Identity) -> Result<Self> {
        let mut provider = rustls_rustcrypto::provider();
        provider.key_provider = &super::rsa_signer::BlindedRsaKeyProvider;
        Self::with_provider(identity, Arc::new(provider))
    }
    pub fn certificate_der(&self) -> &[u8] {
        self.certificate.as_ref()
    }
    pub(crate) fn public_key(&self) -> &[u8] {
        &self.public_key
    }
    /// 核对 AUTH、配对 PeerInfo 与 TLS 使用相同主控身份。
    pub fn matches_identity(&self, identity: &Identity) -> Result<bool> {
        Ok(self.public_key == identity.public_key("")?)
    }
}

/// 升级已交换 STLS 的传输，或新的配对 socket；此处仅执行 TLS，ADB STLS/CNXN 协商仍由调用方负责。
pub async fn upgrade_tls<T: Transport>(stream: T, config: &TlsConfig) -> Result<TlsStream<T>> {
    TlsConnector::from(config.inner.clone())
        .connect(
            ServerName::try_from("adb.local").expect("constant DNS name"),
            stream,
        )
        .await
        .map_err(Error::from)
}
fn tls_error(error: rustls::Error) -> Error {
    Error::Protocol(format!("ADB TLS: {error}"))
}
#[derive(Debug)]
struct AdbCertificateVerifier {
    algorithms: WebPkiSupportedAlgorithms,
}
impl ServerCertVerifier for AdbCertificateVerifier {
    fn verify_server_cert(
        &self,
        _: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> std::result::Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(message, cert, dss, &self.algorithms)
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.algorithms)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}
