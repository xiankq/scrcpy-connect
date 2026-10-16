//! ADB's RSA-2048 identity. Debug output deliberately excludes private key material.
use crate::{Error, Result};
use base64::Engine;
use rsa::{
    BigUint, Pkcs1v15Sign, RsaPrivateKey,
    pkcs1::DecodeRsaPrivateKey,
    pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding},
    traits::PublicKeyParts,
};

#[derive(Clone)]
pub struct Identity {
    key: RsaPrivateKey,
}

impl std::fmt::Debug for Identity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Identity(RSA-2048, private key redacted)")
    }
}

impl Identity {
    pub fn generate() -> Result<Self> {
        RsaPrivateKey::new(&mut rand::rngs::OsRng, 2048)
            .map(|key| Self { key })
            .map_err(|e| Error::Identity(e.to_string()))
    }

    pub fn from_pem(pem: &str) -> Result<Self> {
        let key = RsaPrivateKey::from_pkcs8_pem(pem)
            .or_else(|_| RsaPrivateKey::from_pkcs1_pem(pem))
            .map_err(|_| Error::Identity("invalid RSA private key PEM".into()))?;
        if key.n().bits() != 2048 || key.e() != &BigUint::from(65537u32) {
            return Err(Error::Identity(
                "ADB requires RSA-2048 with exponent 65537".into(),
            ));
        }
        key.validate()
            .map_err(|_| Error::Identity("invalid RSA private key".into()))?;
        Ok(Self { key })
    }

    /// Caller owns secure persistence. The returned allocation zeroizes on drop.
    pub fn to_pkcs8_pem(&self) -> Result<rsa::pkcs8::der::zeroize::Zeroizing<String>> {
        self.key
            .to_pkcs8_pem(LineEnding::LF)
            .map_err(|e| Error::Identity(e.to_string()))
    }

    /// Signs the already-hashed 20-byte ADB token with SHA1 DigestInfo (no second hash).
    pub fn sign_token(&self, token: &[u8]) -> Result<Vec<u8>> {
        if token.len() != 20 {
            return Err(Error::Protocol("AUTH token must contain 20 bytes".into()));
        }
        self.key
            .sign_with_rng(
                &mut rand::rngs::OsRng,
                Pkcs1v15Sign::new::<sha1::Sha1>(),
                token,
            )
            .map_err(|e| Error::Identity(e.to_string()))
    }

    /// Android's little-endian RSAPublicKey, base64 + comment + NUL.
    pub fn public_key(&self, comment: &str) -> Result<Vec<u8>> {
        if comment.len() > 1024 || comment.bytes().any(|b| b == 0 || b == b'\n' || b == b'\r') {
            return Err(Error::InvalidArgument("invalid public key comment"));
        }
        let n = self.key.n();
        let modulus = n.to_bytes_le();
        let low = u32::from_le_bytes(modulus[..4].try_into().expect("2048-bit modulus"));
        let mut inverse = 1u32;
        for _ in 0..5 {
            inverse = inverse.wrapping_mul(2u32.wrapping_sub(low.wrapping_mul(inverse)));
        }
        let rr = (BigUint::from(1u32) << 4096usize) % n;
        let mut binary = Vec::with_capacity(524);
        binary.extend_from_slice(&64u32.to_le_bytes());
        binary.extend_from_slice(&inverse.wrapping_neg().to_le_bytes());
        binary.extend_from_slice(&modulus);
        let rr = rr.to_bytes_le();
        binary.extend_from_slice(&rr);
        binary.resize(520, 0);
        binary.extend_from_slice(&65537u32.to_le_bytes());
        let mut result = base64::engine::general_purpose::STANDARD
            .encode(binary)
            .into_bytes();
        result.push(b' ');
        result.extend_from_slice(comment.as_bytes());
        result.push(0);
        Ok(result)
    }
}
