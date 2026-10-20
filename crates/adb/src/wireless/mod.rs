//! Android 11+ wireless debugging: pairing, TLS 1.3, QR payloads and mDNS.
//! Pairing and connection use separate ports. This module never starts an adb server.
mod aead;
mod cert;
pub mod discovery;
mod frame;
mod peer_info;
mod rsa_signer;
mod spake2;
mod tls;
use crate::{Error, Identity, OperationOptions, Result, Transport};
pub use tls::{TlsConfig, upgrade_tls};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use zeroize::Zeroizing;

/// Persist the GUID alongside the host identity for mDNS reconnect selection.
/// This does not mean a device connection has been established.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingResult {
    pub guid: String,
}

/// Pair on a fresh pairing socket. `password` is the displayed code or QR password.
/// The entire exchange is bounded by the supplied deadline/cancellation. Retrying
/// requires a new socket and may require a newly displayed code on the device.
pub async fn pair<T: Transport>(
    transport: T,
    password: &str,
    identity: &Identity,
    tls: &TlsConfig,
    comment: &str,
    options: &OperationOptions,
) -> Result<PairingResult> {
    if password.is_empty() || password.len() > 1024 || password.as_bytes().contains(&0) {
        return Err(Error::InvalidArgument("invalid pairing password"));
    }
    if !tls.matches_identity(identity)? {
        return Err(Error::InvalidArgument("pairing and TLS identities differ"));
    }
    crate::error::bounded(options.timeout, &options.cancellation, async {
        let mut stream = upgrade_tls(transport, tls).await?;
        let mut exporter = Zeroizing::new([0u8; 64]);
        stream
            .get_ref()
            .1
            .export_keying_material(&mut *exporter, b"adb-label\0", None)
            .map_err(|e| Error::Protocol(format!("pairing TLS exporter: {e}")))?;
        let mut secret = Zeroizing::new(password.as_bytes().to_vec());
        secret.extend_from_slice(&*exporter);
        let spake = spake2::Spake2::new(
            spake2::Role::Alice,
            b"adb pair client\0",
            b"adb pair server\0",
            &secret,
            &mut rsa::rand_core::OsRng,
        );
        send(&mut stream, frame::PacketType::Spake2Msg, spake.message()).await?;
        let peer = receive(&mut stream, frame::PacketType::Spake2Msg).await?;
        let material = spake
            .finish(&peer)
            .map_err(|e| Error::Protocol(e.to_string()))?;
        let mut cipher = aead::Cipher::new(&*material);
        let public_key = identity.public_key(comment)?;
        let info = peer_info::encode(peer_info::PeerInfoType::RsaPublicKey, &public_key)
            .map_err(|e| Error::Protocol(e.to_string()))?;
        send(
            &mut stream,
            frame::PacketType::PeerInfo,
            &cipher.seal(&info),
        )
        .await?;
        let answer = receive(&mut stream, frame::PacketType::PeerInfo).await?;
        if answer.len() != peer_info::SIZE + aead::TAG_LEN {
            return Err(Error::Protocol(
                "invalid encrypted pairing PeerInfo size".into(),
            ));
        }
        let opened = cipher.open(&answer).ok_or_else(|| {
            Error::Protocol("pairing authentication failed (incorrect code or channel)".into())
        })?;
        let (kind, guid) =
            peer_info::decode(&opened).map_err(|e| Error::Protocol(e.to_string()))?;
        if kind != peer_info::PeerInfoType::DeviceGuid {
            return Err(Error::Protocol(
                peer_info::PeerInfoError::Unexpected(kind).to_string(),
            ));
        }
        if guid.is_empty() {
            return Err(Error::Protocol(
                "pairing server did not return a device GUID".into(),
            ));
        }
        Ok(PairingResult { guid })
    })
    .await
}
async fn send<T: Transport>(stream: &mut T, kind: frame::PacketType, bytes: &[u8]) -> Result<()> {
    stream.write_all(&frame::encode(kind, bytes)).await?;
    stream.flush().await?;
    Ok(())
}
async fn receive<T: Transport>(stream: &mut T, expected: frame::PacketType) -> Result<Vec<u8>> {
    let mut header = [0; frame::HEADER_LEN];
    stream.read_exact(&mut header).await?;
    let (kind, size) = frame::decode(&header).map_err(|e| Error::Protocol(e.to_string()))?;
    if kind != expected {
        return Err(Error::Protocol(
            frame::FrameError::Unexpected {
                got: kind,
                expected,
            }
            .to_string(),
        ));
    }
    let expected_len = match expected {
        frame::PacketType::Spake2Msg => 32,
        frame::PacketType::PeerInfo => peer_info::SIZE + aead::TAG_LEN,
    };
    if size != expected_len {
        return Err(Error::Protocol(format!(
            "invalid pairing packet length: {size}"
        )));
    }
    let mut payload = vec![0; size];
    stream.read_exact(&mut payload).await?;
    Ok(payload)
}

/// QR content consumed by Android Wireless debugging. Encode the payload as a QR
/// image in the UI and watch for the named pairing service.
pub struct QrPairing {
    service_name: String,
    password: Zeroizing<String>,
}
impl QrPairing {
    pub fn generate() -> Self {
        use rsa::rand_core::RngCore;
        let mut random = Zeroizing::new([0u8; 32]);
        rsa::rand_core::OsRng.fill_bytes(&mut *random);
        let service_name = format!(
            "studio-{}",
            random[..8]
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        );
        let password = Zeroizing::new(random[8..].iter().map(|b| format!("{b:02x}")).collect());
        Self {
            service_name,
            password,
        }
    }
    pub fn service_name(&self) -> &str {
        &self.service_name
    }
    pub fn password(&self) -> &str {
        &self.password
    }
    /// Contains a secret: do not log or persist the returned payload.
    pub fn payload(&self) -> Zeroizing<String> {
        Zeroizing::new(format!(
            "WIFI:T:ADB;S:{};P:{};;",
            self.service_name, *self.password
        ))
    }
}
impl std::fmt::Debug for QrPairing {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("QrPairing")
            .field("service_name", &self.service_name)
            .field("password", &"[REDACTED]")
            .finish()
    }
}
