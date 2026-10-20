//! rustls adapter for RSA-PSS with randomized multiplicative RSA blinding.
//! The upstream experimental provider uses unblinded `rsa::pss::SigningKey`.
//! All mathematics remains in the pinned RustCrypto RSA implementation. Blinding
//! does not resolve that implementation's outstanding timing-security advisory.
use rsa::sha2::{Sha256, Sha384, Sha512};
use rsa::{
    RsaPrivateKey,
    pkcs8::DecodePrivateKey,
    pss::BlindedSigningKey,
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
        let key = RsaPrivateKey::from_pkcs8_der(der.secret_pkcs8_der())
            .map_err(|_| Error::General("invalid ADB RSA identity".into()))?;
        Ok(Arc::new(BlindedRsaSigningKey(Arc::new(key))))
    }
}
struct BlindedRsaSigningKey(Arc<RsaPrivateKey>);
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
    key: Arc<RsaPrivateKey>,
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
        let mut rng = rsa::rand_core::OsRng;
        let result = match self.scheme {
            SignatureScheme::RSA_PSS_SHA256 => {
                BlindedSigningKey::<Sha256>::new((*self.key).clone())
                    .try_sign_with_rng(&mut rng, message)
            }
            SignatureScheme::RSA_PSS_SHA384 => {
                BlindedSigningKey::<Sha384>::new((*self.key).clone())
                    .try_sign_with_rng(&mut rng, message)
            }
            SignatureScheme::RSA_PSS_SHA512 => {
                BlindedSigningKey::<Sha512>::new((*self.key).clone())
                    .try_sign_with_rng(&mut rng, message)
            }
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
