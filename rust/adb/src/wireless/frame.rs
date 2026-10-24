// Derived from libadb 0.5.0 (MIT), copyright (c) 2026 Igor Tarasov.
// Source: https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5
// Full license: LICENSE-libadb. Adapted to std and the enclosing ADB identity.
//! 配对协议分帧，区别于承载会话的 ADB 帧：6 字节头部、大端长度、仅两种包。AOSP 在 pairing_connection/pairing_connection.cpp 中称其为 PairingPacketHeader。

use std::vec::Vec;

/// 线上头部为 packed 结构，长度为 6 而不是 8 字节。
pub(crate) const HEADER_LEN: usize = 6;

/// 双方唯一支持的版本。
pub(crate) const VERSION: u8 = 1;

/// 对端接纳的最大 payload，为两个 PeerInfo 的大小。
pub(crate) const MAX_PAYLOAD: usize = 16384;

/// 配对包内容。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum PacketType {
    /// 一方 SPAKE2 消息，固定 32 字节。
    Spake2Msg,
    /// 加密后的 PeerInfo 交换。
    PeerInfo,
}

impl PacketType {
    fn code(self) -> u8 {
        match self {
            Self::Spake2Msg => 0,
            Self::PeerInfo => 1,
        }
    }

    fn from_code(code: u8) -> Option<Self> {
        match code {
            0 => Some(Self::Spake2Msg),
            1 => Some(Self::PeerInfo),
            _ => None,
        }
    }
}

/// 读取头部失败原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum FrameError {
    /// 对端使用不支持的分帧版本。
    Version(u8),
    /// 包类型不存在。
    Kind(u8),
    /// payload 为空或超过任一方接纳上限。
    Length(u32),
    /// 包类型有效，但交换当前阶段期望另一种类型。
    Unexpected {
        /// 实际收到的类型。
        got: PacketType,
        /// 当前交换等待的类型。
        expected: PacketType,
    },
}

impl core::fmt::Display for FrameError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Version(v) => write!(f, "pairing header version {v}, expected {VERSION}"),
            Self::Kind(k) => write!(f, "pairing packet type {k} is not one we know"),
            Self::Length(n) => write!(f, "pairing payload of {n} bytes is out of range"),
            Self::Unexpected { got, expected } => {
                write!(f, "pairing packet is {got:?} where {expected:?} was due")
            }
        }
    }
}

impl core::error::Error for FrameError {}

/// 在 payload 前序列化头部。
pub(crate) fn encode(kind: PacketType, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER_LEN + payload.len());
    out.push(VERSION);
    out.push(kind.code());
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(payload);
    out
}

/// 读取头部，采用与对端校验本方头部相同的规则。
pub(crate) fn decode(header: &[u8; HEADER_LEN]) -> Result<(PacketType, usize), FrameError> {
    if header[0] != VERSION {
        return Err(FrameError::Version(header[0]));
    }
    let kind = PacketType::from_code(header[1]).ok_or(FrameError::Kind(header[1]))?;
    let len = u32::from_be_bytes([header[2], header[3], header[4], header[5]]);
    if len == 0 || len as usize > MAX_PAYLOAD {
        return Err(FrameError::Length(len));
    }
    Ok((kind, len as usize))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_header_is_six_bytes_with_a_big_endian_length() {
        let framed = encode(PacketType::PeerInfo, &[0xAA; 300]);

        assert_eq!(&framed[..HEADER_LEN], &[1, 1, 0, 0, 0x01, 0x2C]);
        assert_eq!(framed.len(), HEADER_LEN + 300);
    }

    #[test]
    fn a_header_the_peer_would_refuse_is_refused_here_too() {
        assert_eq!(decode(&[2, 0, 0, 0, 0, 32]), Err(FrameError::Version(2)));
        assert_eq!(decode(&[1, 7, 0, 0, 0, 32]), Err(FrameError::Kind(7)));
        assert_eq!(decode(&[1, 0, 0, 0, 0, 0]), Err(FrameError::Length(0)));
        let over = (MAX_PAYLOAD as u32 + 1).to_be_bytes();
        assert_eq!(
            decode(&[1, 0, over[0], over[1], over[2], over[3]]),
            Err(FrameError::Length(MAX_PAYLOAD as u32 + 1))
        );
    }

    #[test]
    fn the_largest_accepted_payload_is_two_peer_infos() {
        let at_limit = (MAX_PAYLOAD as u32).to_be_bytes();
        let header = [1, 1, at_limit[0], at_limit[1], at_limit[2], at_limit[3]];

        assert_eq!(decode(&header), Ok((PacketType::PeerInfo, MAX_PAYLOAD)));
    }
}
