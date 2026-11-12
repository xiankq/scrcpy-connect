// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! 安全通道建立后双方交换的内容：固定 8192 字节、零填充的块，包含类型字节和 NUL 结尾字符串。AOSP 定义于 pairing_connection/include/adb/pairing/pairing_connection.h，并拒绝其他长度。

use std::string::String;
use std::vec;
use std::vec::Vec;

/// 整个块大小，包含填充。
pub(crate) const SIZE: usize = 8192;

/// PeerInfo 携带的内容。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum PeerInfoType {
    /// 主控 ADB 公钥，编码与 USB 授权相同。
    RsaPublicKey,
    /// 设备 GUID，同时也是其 mDNS 服务名。
    DeviceGuid,
}

impl PeerInfoType {
    fn code(self) -> u8 {
        match self {
            Self::RsaPublicKey => 0,
            Self::DeviceGuid => 1,
        }
    }

    fn from_code(code: u8) -> Option<Self> {
        match code {
            0 => Some(Self::RsaPublicKey),
            1 => Some(Self::DeviceGuid),
            _ => None,
        }
    }
}

/// PeerInfo 块构建或读取失败原因。
#[derive(Debug, Clone, PartialEq, Eq)]
#[non_exhaustive]
pub enum PeerInfoError {
    /// 块长度不是 8192 字节；对端同样校验，长度不符即关闭。
    Size(usize),
    /// 类型字节未知。
    Kind(u8),
    /// 设备发送的不是 GUID。
    Unexpected(PeerInfoType),
    /// payload 不是 UTF-8。
    NotUtf8,
    /// payload 一直延伸到块尾而没有 NUL 终止；有效块必须带终止符。
    Unterminated,
    /// 本方 payload 连同终止符超过块大小；对于主控密钥，意味着 user@host 名称达到数 KiB。
    TooLong(usize),
}

impl core::fmt::Display for PeerInfoError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Size(n) => write!(f, "peer info is {n} bytes, not {SIZE}"),
            Self::Kind(k) => write!(f, "peer info type {k} is not one we know"),
            Self::Unexpected(t) => write!(f, "device answered with {t:?}, expected its GUID"),
            Self::NotUtf8 => f.write_str("peer info payload is not UTF-8"),
            Self::Unterminated => f.write_str("peer info payload has no terminating NUL"),
            Self::TooLong(n) => write!(f, "peer info payload of {n} bytes does not fit"),
        }
    }
}

impl core::error::Error for PeerInfoError {}

/// 构建承载 payload 的块，零填充至完整大小；对端校验解密后长度，其他长度即关闭。
pub(crate) fn encode(kind: PeerInfoType, payload: &[u8]) -> Result<Vec<u8>, PeerInfoError> {
    // 一个字节表示类型，另预留一个零字节；设备按 C 字符串读取 payload。
    if payload.len() > SIZE - 2 {
        return Err(PeerInfoError::TooLong(payload.len()));
    }
    let mut block = vec![0u8; SIZE];
    block[0] = kind.code();
    block[1..1 + payload.len()].copy_from_slice(payload);
    Ok(block)
}

/// 按设备读取规则解析，到首个必需的 NUL 为止。
pub(crate) fn decode(block: &[u8]) -> Result<(PeerInfoType, String), PeerInfoError> {
    if block.len() != SIZE {
        return Err(PeerInfoError::Size(block.len()));
    }
    let kind = PeerInfoType::from_code(block[0]).ok_or(PeerInfoError::Kind(block[0]))?;
    let data = &block[1..];
    let end = data
        .iter()
        .position(|&b| b == 0)
        .ok_or(PeerInfoError::Unterminated)?;
    let text = core::str::from_utf8(&data[..end])
        .map_err(|_| PeerInfoError::NotUtf8)?
        .into();
    Ok((kind, text))
}
