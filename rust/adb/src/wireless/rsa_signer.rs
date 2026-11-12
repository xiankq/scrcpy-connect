//! 采用随机乘法 RSA 盲化的 RSA-PSS rustls adapter。RSA 0.10 的 PSS SigningKey 默认执行盲化；此处显式传入加密随机源。
use rsa::sha2::{Sha256, Sha384, Sha512};
use rsa::{
    PrivateKey,
    pkcs8::DecodePrivateKey,
    pss::SigningKey as PssSigningKey,
    signature::{RandomizedSigner, SignatureEncoding},
};
use rustls::{
    Error, SignatureAlgorithm, SignatureScheme,
    crypto::KeyProvider,
    pki_types::PrivateKeyDer,
    sign::{Signer, SigningKey},
};
use std::sync::Arc;

#[derive(Debug)]
pub(super) struct BlindedRsaKeyProvider;
impl KeyProvider for BlindedRsaKeyProvider {
    fn load_private_key(
        &self,
        key_der: PrivateKeyDer<'static>,
    ) -> Result<Arc<dyn SigningKey>, Error> {
        let PrivateKeyDer::Pkcs8(der) = key_der else {
            return Err(Error::General("ADB requires RSA PKCS8 identity".into()));
        };
        let key = PrivateKey::from_pkcs8_der(der.secret_pkcs8_der())
            .map_err(|_| Error::General("invalid ADB RSA identity".into()))?;
        Ok(Arc::new(BlindedRsaSigningKey(Arc::new(key))))
    }
}
struct BlindedRsaSigningKey(Arc<PrivateKey>);
impl std::fmt::Debug for BlindedRsaSigningKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("BlindedRsaSigningKey([REDACTED])")
    }
}
impl SigningKey for BlindedRsaSigningKey {
    fn choose_scheme(&self, offered: &[SignatureScheme]) -> Option<Box<dyn Signer>> {
        [
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA256,
        ]
        .into_iter()
        .find(|scheme| offered.contains(scheme))
        .map(|scheme| {
            Box::new(BlindedRsaSigner {
                key: self.0.clone(),
                scheme,
            }) as Box<dyn Signer>
        })
    }
    fn algorithm(&self) -> SignatureAlgorithm {
        SignatureAlgorithm::RSA
    }
}
struct BlindedRsaSigner {
    key: Arc<PrivateKey>,
    scheme: SignatureScheme,
}
impl std::fmt::Debug for BlindedRsaSigner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BlindedRsaSigner")
            .field("scheme", &self.scheme)
            .finish_non_exhaustive()
    }
}
impl Signer for BlindedRsaSigner {
    fn sign(&self, message: &[u8]) -> Result<Vec<u8>, Error> {
        let mut rng = rand::rng();
        let result = match self.scheme {
            SignatureScheme::RSA_PSS_SHA256 => PssSigningKey::<Sha256>::new((*self.key).clone())
                .try_sign_with_rng(&mut rng, message),
            SignatureScheme::RSA_PSS_SHA384 => PssSigningKey::<Sha384>::new((*self.key).clone())
                .try_sign_with_rng(&mut rng, message),
            SignatureScheme::RSA_PSS_SHA512 => PssSigningKey::<Sha512>::new((*self.key).clone())
                .try_sign_with_rng(&mut rng, message),
            _ => return Err(Error::General("ADB TLS requires RSA-PSS".into())),
        };
        result
            .map(|signature| signature.to_vec())
            .map_err(|_| Error::General("ADB RSA-PSS signature failed".into()))
    }
    fn scheme(&self) -> SignatureScheme {
        self.scheme
    }
}
