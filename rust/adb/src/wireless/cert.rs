// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! ADB 主控在 TLS 中提交的自签名证书。无线调试按客户端证书公钥在与 USB 授权相同的可信密钥库中认证主控；证书本身无额外秘密，只包装参与 TLS 握手的 RsaPrivateKey。结构逐字段对应 AOSP crypto/x509_generator.cpp。设备当前只比较公钥，仍保持 adb 输出形状以兼容后续收紧；常规调用方使用同时保有证书和密钥的 TlsConfig。

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

/// adb 签名使用的 sha256WithRSAEncryption 算法。
const SHA256_WITH_RSA: ObjectIdentifier = ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.11");

/// 证书有效期，与 AOSP 一样为十个 365 天年。
const LIFETIME: Duration = Duration::from_secs(60 * 60 * 24 * 365 * 10);

/// Subject 与 issuer 按 RFC 4514 从最后一个 RDN 开始书写，编码顺序为 C、O、CN，与 AOSP 一致。
const DISTINGUISHED_NAME: &str = "CN=Adb,O=Android,C=US";

/// 证书构建失败原因。
#[derive(Debug)]
#[non_exhaustive]
pub enum CertError {
    /// ASN.1 结构编码或解码失败。
    Der(x509_cert::der::Error),
    /// 公钥不能经 SPKI 往返转换。
    Spki(x509_cert::spki::Error),
    /// 进入 DER 编码前 RSA 公钥编码失败。
    RsaSpki(rsa::pkcs8::spki::Error),
    /// 证书正文签名失败。
    Rsa(rsa::Error),
    /// 证书组装失败。
    Builder(x509_cert::builder::Error),
    /// 时钟或 build_at 给定的起始时间无法由证书表示：早于 Unix 纪元，或晚到十年有效期将超过 9999 年。
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

/// 分离 x509-cert 当前元数据 trait 与 RSA 0.9 签名 trait；两个版本间只传递公钥 DER，下面的私钥操作仍由 RSA 进行盲化计算。
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

/// 扩展由 AOSP 自行规定，builder 不附加默认扩展。
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

/// 为 key 构建从当前时刻起十年有效的自签名证书，返回 TLS 所需 DER。rng 用于 RSA 签名盲化，不改变签名字节。错误：时钟无法由证书表示时返回 CertError::Clock，编码或签名失败返回对应变体。
pub fn build<R: CryptoRngCore>(key: &RsaPrivateKey, rng: &mut R) -> Result<Vec<u8>, CertError> {
    build_at(key, rng, SystemTime::now())
}

/// 与 build 相同，但从 not_before 而非当前时钟起算，用于时钟不可信或需可重现字节的宿主。
pub fn build_at<R: CryptoRngCore>(
    key: &RsaPrivateKey,
    rng: &mut R,
    not_before: SystemTime,
) -> Result<Vec<u8>, CertError> {
    let name: Name = DISTINGUISHED_NAME.parse()?;
    let algorithm = AlgorithmIdentifierOwned {
        oid: SHA256_WITH_RSA,
        // 显式 NULL，不能省略参数，见 RFC 4055 第 5 节。
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
    // 使用 sign_with_rng 而非 sign，确保此处私钥操作经过盲化。
    let signature = key
        .sign_with_rng(rng, Pkcs1v15Sign::new::<Sha256>(), &digest)
        .map_err(CertError::Rsa)?;

    let certificate = builder.assemble(BitString::from_bytes(&signature)?, &metadata)?;
    Ok(certificate.to_der()?)
}

/// 按 RFC 5280 第 4.1.2.5 节生成时间戳：截至 2049 年使用 UTCTime，之后使用 GeneralizedTime。x509-cert 对所有时间使用后者，与 adb 不同，严格校验器可能拒绝。
fn rfc5280_time(at: SystemTime) -> Result<Time, CertError> {
    // 唯一失败情形是时间不在 1970 至 9999 年内；x509-cert 将其报为编码错误，实际原因是时钟。
    let time = Time::try_from(at).map_err(|_| CertError::Clock)?;
    if let Time::GeneralTime(t) = time {
        let date = t.to_date_time();
        if date.year() <= UtcTime::MAX_YEAR {
            return Ok(Time::UtcTime(UtcTime::from_date_time(date)?));
        }
    }
    Ok(time)
}

/// AOSP 的三个证书扩展。to_extension 与 AOSP 一样将前两个标为 critical，密钥标识不标为 critical。
fn extensions(name: &Name, spki: &SubjectPublicKeyInfoOwned) -> Result<Vec<Extension>, CertError> {
    let mut out = Vec::with_capacity(3);

    let basic = BasicConstraints {
        ca: true,
        path_len_constraint: None,
    };
    out.push(basic.to_extension(name, &out)?);

    let usage = KeyUsage(KeyUsages::DigitalSignature | KeyUsages::KeyCertSign | KeyUsages::CRLSign);
    out.push(usage.to_extension(name, &out)?);

    // 对应 OpenSSL 的 subjectKeyIdentifier = hash，即公钥位串的 SHA-1。
    let key_id = Sha1::digest(spki.subject_public_key.raw_bytes());
    let skid = SubjectKeyIdentifier(OctetString::new(key_id.as_slice())?);
    out.push(skid.to_extension(name, &out)?);

    Ok(out)
}
