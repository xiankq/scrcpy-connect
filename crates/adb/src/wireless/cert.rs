// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! The self-signed certificate an ADB host presents over TLS.
//!
//! Wireless debugging authenticates the host by the public key inside
//! its client certificate, checked against the same trusted-key store
//! that a USB authorisation prompt fills. So the certificate carries no
//! secret of its own: it is a wrapper that lets an `RsaPrivateKey` travel
//! through a TLS handshake.
//!
//! The shape follows AOSP's `crypto/x509_generator.cpp` field for
//! field. A device only compares the public key, but matching what
//! `adb` emits keeps us out of any future tightening.
//!
//! Most callers want `TlsConfig`, which
//! builds this and keeps it with the key.

use std::time::{Duration, SystemTime};
use std::vec::Vec;

use rsa::pkcs1v15::Pkcs1v15Sign;
use rsa::pkcs8::EncodePublicKey;
use rsa::rand_core::CryptoRngCore;
use rsa::sha2::{Digest, Sha256};
use sha1::Sha1;
use x509_cert::TbsCertificate;
use x509_cert::builder::{Builder, CertificateBuilder, profile::BuilderProfile};
use x509_cert::der::asn1::{BitString, Null, OctetString, UtcTime};
use x509_cert::der::{Any, Encode};
use x509_cert::ext::pkix::{BasicConstraints, KeyUsage, KeyUsages, SubjectKeyIdentifier};
use x509_cert::ext::{Extension, ToExtension};
use x509_cert::name::Name;
use x509_cert::serial_number::SerialNumber;
use x509_cert::spki::{AlgorithmIdentifierOwned, ObjectIdentifier, SubjectPublicKeyInfoOwned};
use x509_cert::time::{Time, Validity};

use rsa::RsaPrivateKey;

/// `sha256WithRSAEncryption`, the algorithm `adb` signs with.
const SHA256_WITH_RSA: ObjectIdentifier = ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.11");

/// How long the certificate stays valid. AOSP uses ten 365-day years.
const LIFETIME: Duration = Duration::from_secs(60 * 60 * 24 * 365 * 10);

/// Subject and issuer, written RFC 4514 style, last RDN first: they
/// encode as C, O, CN, which is the order AOSP writes them in.
const DISTINGUISHED_NAME: &str = "CN=Adb,O=Android,C=US";

/// Why a certificate could not be built.
#[derive(Debug)]
#[non_exhaustive]
pub enum CertError {
    /// Encoding or decoding an ASN.1 structure failed.
    Der(x509_cert::der::Error),
    /// The public key would not round-trip through SPKI.
    Spki(x509_cert::spki::Error),
    /// Encoding the RSA public key failed before crossing the DER boundary.
    RsaSpki(rsa::pkcs8::spki::Error),
    /// Signing the certificate body failed.
    Rsa(rsa::Error),
    /// Assembling the certificate failed.
    Builder(x509_cert::builder::Error),
    /// The start time, the clock's or one handed to [`build_at`], is
    /// one no certificate can carry: before the Unix epoch, or so late
    /// that the ten-year validity would run past the year 9999.
    Clock,
}

impl core::fmt::Display for CertError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Der(e) => write!(f, "certificate encoding: {e}"),
            Self::Spki(e) => write!(f, "certificate public key: {e}"),
            Self::RsaSpki(e) => write!(f, "RSA public key: {e}"),
            Self::Rsa(e) => write!(f, "certificate signature: {e}"),
            Self::Builder(e) => write!(f, "certificate assembly: {e}"),
            Self::Clock => f.write_str("start time is outside what a certificate can carry"),
        }
    }
}

impl core::error::Error for CertError {
    fn source(&self) -> Option<&(dyn core::error::Error + 'static)> {
        match self {
            Self::Der(e) => Some(e),
            Self::Spki(e) => Some(e),
            Self::RsaSpki(e) => Some(e),
            Self::Rsa(e) => Some(e),
            Self::Builder(e) => Some(e),
            Self::Clock => None,
        }
    }
}

impl From<x509_cert::der::Error> for CertError {
    fn from(e: x509_cert::der::Error) -> Self {
        Self::Der(e)
    }
}

impl From<x509_cert::spki::Error> for CertError {
    fn from(e: x509_cert::spki::Error) -> Self {
        Self::Spki(e)
    }
}

impl From<x509_cert::builder::Error> for CertError {
    fn from(e: x509_cert::builder::Error) -> Self {
        Self::Builder(e)
    }
}

/// Keep x509-cert's current metadata traits separate from RSA 0.9's signing
/// traits. Only public-key DER crosses the two versions; RSA still performs
/// the blinded private-key operation below.
#[derive(Clone)]
struct SignerMetadata {
    public_key: SubjectPublicKeyInfoOwned,
    algorithm: AlgorithmIdentifierOwned,
}

impl signature::Keypair for SignerMetadata {
    type VerifyingKey = Self;

    fn verifying_key(&self) -> Self {
        self.clone()
    }
}

impl x509_cert::spki::EncodePublicKey for SignerMetadata {
    fn to_public_key_der(&self) -> x509_cert::spki::Result<x509_cert::spki::Document> {
        x509_cert::spki::Document::try_from(&self.public_key)
    }
}

impl x509_cert::spki::DynSignatureAlgorithmIdentifier for SignerMetadata {
    fn signature_algorithm_identifier(&self) -> x509_cert::spki::Result<AlgorithmIdentifierOwned> {
        Ok(self.algorithm.clone())
    }
}

/// AOSP specifies its own extensions, so the builder adds no defaults.
struct AdbProfile(Name);

impl BuilderProfile for AdbProfile {
    fn get_subject(&self) -> Name {
        self.0.clone()
    }

    fn get_issuer(&self, subject: &Name) -> Name {
        subject.clone()
    }

    fn build_extensions(
        &self,
        _spk: x509_cert::spki::SubjectPublicKeyInfoRef<'_>,
        _issuer_spk: x509_cert::spki::SubjectPublicKeyInfoRef<'_>,
        _tbs: &TbsCertificate,
    ) -> x509_cert::builder::Result<Vec<Extension>> {
        Ok(Vec::new())
    }
}

/// Build the self-signed certificate for `key`, valid for ten years
/// from now.
///
/// Returns DER, which is what a TLS stack wants. `rng` blinds the RSA
/// signature; the signature itself comes out the same either way.
///
/// # Errors
///
/// [`CertError::Clock`] if the clock reads a time no certificate can
/// carry; the other variants if encoding or signing fails.
pub fn build<R: CryptoRngCore>(key: &RsaPrivateKey, rng: &mut R) -> Result<Vec<u8>, CertError> {
    build_at(key, rng, SystemTime::now())
}

/// [`build`], dated from `not_before` instead of the clock: for a host
/// whose clock cannot be trusted, or bytes that must come out the same
/// every time.
pub fn build_at<R: CryptoRngCore>(
    key: &RsaPrivateKey,
    rng: &mut R,
    not_before: SystemTime,
) -> Result<Vec<u8>, CertError> {
    let name: Name = DISTINGUISHED_NAME.parse()?;
    let algorithm = AlgorithmIdentifierOwned {
        oid: SHA256_WITH_RSA,
        // An explicit NULL, not an absent parameter: RFC 4055 section 5.
        parameters: Some(Any::from(Null)),
    };

    let spki_der = key
        .to_public_key()
        .to_public_key_der()
        .map_err(CertError::RsaSpki)?;
    let spki = SubjectPublicKeyInfoOwned::try_from(spki_der.as_bytes())?;

    let not_after = not_before.checked_add(LIFETIME).ok_or(CertError::Clock)?;
    let validity = Validity::new(rfc5280_time(not_before)?, rfc5280_time(not_after)?);

    let extensions = extensions(&name, &spki)?;

    let metadata = SignerMetadata {
        public_key: spki.clone(),
        algorithm,
    };
    let mut builder = CertificateBuilder::new(
        AdbProfile(name),
        SerialNumber::new(&[0x01])?,
        validity,
        spki,
    )?;
    for extension in extensions {
        builder.add_extension(extension)?;
    }
    let tbs_der = builder.finalize(&metadata)?;
    let digest = Sha256::digest(&tbs_der);
    // `sign_with_rng`, not `sign`: private-key operations here are blinded.
    let signature = key
        .sign_with_rng(rng, Pkcs1v15Sign::new::<Sha256>(), &digest)
        .map_err(CertError::Rsa)?;

    let certificate = builder.assemble(BitString::from_bytes(&signature)?, &metadata)?;
    Ok(certificate.to_der()?)
}

/// A timestamp as RFC 5280 section 4.1.2.5 wants it: `UTCTime` through
/// 2049, `GeneralizedTime` after. `x509-cert` hands out the latter for
/// everything, which `adb` does not and a strict verifier may refuse.
fn rfc5280_time(at: SystemTime) -> Result<Time, CertError> {
    // Its only failure is a time outside 1970 to 9999, which `x509-cert`
    // reports as an encoding error; the cause is the clock.
    let time = Time::try_from(at).map_err(|_| CertError::Clock)?;
    if let Time::GeneralTime(t) = time {
        let date = t.to_date_time();
        if date.year() <= UtcTime::MAX_YEAR {
            return Ok(Time::UtcTime(UtcTime::from_date_time(date)?));
        }
    }
    Ok(time)
}

/// The three extensions AOSP puts on the certificate. `to_extension`
/// marks the first two critical and the key identifier not, as AOSP
/// does.
fn extensions(name: &Name, spki: &SubjectPublicKeyInfoOwned) -> Result<Vec<Extension>, CertError> {
    let mut out = Vec::with_capacity(3);

    let basic = BasicConstraints {
        ca: true,
        path_len_constraint: None,
    };
    out.push(basic.to_extension(name, &out)?);

    let usage = KeyUsage(KeyUsages::DigitalSignature | KeyUsages::KeyCertSign | KeyUsages::CRLSign);
    out.push(usage.to_extension(name, &out)?);

    // `subjectKeyIdentifier = hash` in OpenSSL terms: SHA-1 of the key bits.
    let key_id = Sha1::digest(spki.subject_public_key.raw_bytes());
    let skid = SubjectKeyIdentifier(OctetString::new(key_id.as_slice())?);
    out.push(skid.to_extension(name, &out)?);

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use x509_cert::{Certificate, Version, der::Decode};

    #[test]
    fn built_certificate_preserves_aosp_identity_fields_and_verifiable_signature() {
        let mut rng = rsa::rand_core::OsRng;
        let key = RsaPrivateKey::new(&mut rng, 2048).unwrap();
        let start = SystemTime::UNIX_EPOCH + Duration::from_secs(1_600_000_000);
        let encoded = build_at(&key, &mut rng, start).unwrap();
        let certificate = Certificate::from_der(&encoded).unwrap();
        let tbs = certificate.tbs_certificate();

        assert_eq!(tbs.version(), Version::V3);
        assert_eq!(tbs.serial_number(), &SerialNumber::new(&[1]).unwrap());
        assert_eq!(tbs.subject(), &DISTINGUISHED_NAME.parse::<Name>().unwrap());
        assert_eq!(tbs.issuer(), tbs.subject());
        assert_eq!(tbs.validity().not_before.to_system_time(), start);
        assert_eq!(tbs.validity().not_after.to_system_time(), start + LIFETIME);
        assert!(matches!(tbs.validity().not_before, Time::UtcTime(_)));
        assert!(matches!(tbs.validity().not_after, Time::UtcTime(_)));
        assert_eq!(tbs.signature().oid, SHA256_WITH_RSA);
        assert_eq!(tbs.signature().parameters, Some(Any::from(Null)));
        assert_eq!(certificate.signature_algorithm(), tbs.signature());
        assert_eq!(
            tbs.subject_public_key_info().to_der().unwrap(),
            key.to_public_key().to_public_key_der().unwrap().as_bytes()
        );

        let extensions = tbs.extensions().unwrap();
        assert_eq!(
            extensions
                .iter()
                .map(|extension| (extension.extn_id.to_string(), extension.critical))
                .collect::<Vec<_>>(),
            [
                ("2.5.29.19", true),
                ("2.5.29.15", true),
                ("2.5.29.14", false)
            ]
            .map(|(oid, critical)| (oid.to_owned(), critical))
        );
        let (_, constraints) = tbs.get_extension::<BasicConstraints>().unwrap().unwrap();
        assert!(constraints.ca);
        assert_eq!(constraints.path_len_constraint, None);
        let (_, usage) = tbs.get_extension::<KeyUsage>().unwrap().unwrap();
        assert_eq!(
            usage,
            KeyUsage(KeyUsages::DigitalSignature | KeyUsages::KeyCertSign | KeyUsages::CRLSign)
        );
        let (_, skid) = tbs
            .get_extension::<SubjectKeyIdentifier>()
            .unwrap()
            .unwrap();
        assert_eq!(
            skid.0.as_bytes(),
            Sha1::digest(tbs.subject_public_key_info().subject_public_key.raw_bytes()).as_slice()
        );

        key.to_public_key()
            .verify(
                Pkcs1v15Sign::new::<Sha256>(),
                &Sha256::digest(tbs.to_der().unwrap()),
                certificate.signature().raw_bytes(),
            )
            .unwrap();
    }
}
