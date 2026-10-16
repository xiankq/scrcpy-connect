//! TLS 1.3 for ADB pairing and STLS. The provider is chosen explicitly by the caller.
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

/// A TLS identity bound to the same RSA key used for legacy AUTH and pairing.
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
    /// Use the selected provider without changing the process-global rustls provider.
    /// ADB accepts self-signed peer certificates; CertificateVerify signatures are verified.
    /// Pairing authenticates the channel using SPAKE2 and its TLS exporter. On subsequent
    /// connections adbd verifies the host public key against its authorized key store.
    pub fn with_provider(identity: &Identity, provider: Arc<CryptoProvider>) -> Result<Self> {
        let pem = identity.to_pkcs8_pem()?;
        let key =
            RsaPrivateKey::from_pkcs8_pem(&pem).map_err(|e| Error::Identity(e.to_string()))?;
        let certificate = CertificateDer::from(
            super::cert::build(&key, &mut rand::rngs::OsRng)
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
        // ADB identifies the peer by pairing/public key, not a DNS virtual host.
        config.enable_sni = false;
        Ok(Self {
            inner: Arc::new(config),
            certificate,
            public_key: identity.public_key("")?,
        })
    }
    /// Experimental pure-Rust provider, pinned to rustls-rustcrypto 0.0.2-alpha.
    ///
    /// Its upstream README explicitly says "DO NOT USE THIS IN PRODUCTION".
    /// Selecting this method acknowledges that restriction; interoperability testing
    /// does not constitute a cryptographic security review or production approval.
    pub fn experimental_rustcrypto(identity: &Identity) -> Result<Self> {
        let mut provider = rustls_rustcrypto::provider();
        provider.key_provider = &super::rsa_signer::BlindedRsaKeyProvider;
        Self::with_provider(identity, Arc::new(provider))
    }
    pub fn certificate_der(&self) -> &[u8] {
        self.certificate.as_ref()
    }
    /// Checks that AUTH, pairing PeerInfo and TLS use the same host identity.
    pub fn matches_identity(&self, identity: &Identity) -> Result<bool> {
        Ok(self.public_key == identity.public_key("")?)
    }
}

/// Upgrade an already exchanged STLS transport, or a fresh pairing socket.
/// This performs only TLS; callers remain responsible for ADB STLS/CNXN negotiation.
pub async fn upgrade_tls<T: Transport>(stream: T, config: &TlsConfig) -> Result<TlsStream<T>> {
    TlsConnector::from(config.inner.clone())
        .connect(
            ServerName::try_from("adb.local").expect("constant DNS name"),
            stream,
        )
        .await
        .map_err(Error::Io)
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
