//! ADB 传输帧，在分配 payload 存储前检查限额。
use crate::{Error, Result};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

pub const VERSION: u32 = 0x0100_0001;
pub const LEGACY_VERSION: u32 = 0x0100_0000;
pub const MAX_PAYLOAD: usize = 1024 * 1024;
pub const CNXN: u32 = u32::from_le_bytes(*b"CNXN");
pub const AUTH: u32 = u32::from_le_bytes(*b"AUTH");
pub const OPEN: u32 = u32::from_le_bytes(*b"OPEN");
pub const OKAY: u32 = u32::from_le_bytes(*b"OKAY");
pub const WRTE: u32 = u32::from_le_bytes(*b"WRTE");
pub const CLSE: u32 = u32::from_le_bytes(*b"CLSE");
pub const STLS: u32 = u32::from_le_bytes(*b"STLS");

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub command: u32,
    pub arg0: u32,
    pub arg1: u32,
    pub payload: Vec<u8>,
}

impl Frame {
    pub fn new(command: u32, arg0: u32, arg1: u32, payload: impl Into<Vec<u8>>) -> Self {
        Self {
            command,
            arg0,
            arg1,
            payload: payload.into(),
        }
    }

    pub async fn read<R: AsyncRead + Unpin>(
        reader: &mut R,
        limit: usize,
        skip_checksum: bool,
    ) -> Result<Self> {
        Self::read_observed(reader, limit, skip_checksum, |_, _, _| None)
            .await
            .map(|(frame, _)| frame)
    }

    pub(crate) async fn read_observed<R: AsyncRead + Unpin>(
        reader: &mut R,
        limit: usize,
        skip_checksum: bool,
        observe: impl FnOnce(u32, u32, u32) -> Option<crate::read_trace::TraceClock>,
    ) -> Result<(Self, Option<crate::read_trace::PayloadTiming>)> {
        Self::read_observed_progress(reader, limit, skip_checksum, observe, || {}).await
    }

    /// 内部传输进度钩子。每次非空读取（含部分头部或 payload）在帧校验前即计为活动。
    pub(crate) async fn read_observed_progress<R: AsyncRead + Unpin>(
        reader: &mut R,
        limit: usize,
        skip_checksum: bool,
        observe: impl FnOnce(u32, u32, u32) -> Option<crate::read_trace::TraceClock>,
        mut progress: impl FnMut(),
    ) -> Result<(Self, Option<crate::read_trace::PayloadTiming>)> {
        let mut header = [0; 24];
        read_exact_progress(reader, &mut header, &mut progress).await?;
        let words = validate_header(&header, limit)?;
        let [command, arg0, arg1, length, wire_checksum, _] = words;
        let length = length as usize;
        let mut payload = Vec::with_capacity(length);
        let clock = observe(command, arg0, arg1);
        let started_us = clock.as_ref().map(|clock| (clock.read)());
        while payload.len() < length {
            // read_buf 只初始化实际收到的字节；新 payload 无需先全部清零再由 I/O 覆盖。
            let remaining = length - payload.len();
            let count = (&mut *reader)
                .take(remaining as u64)
                .read_buf(&mut payload)
                .await?;
            if count == 0 {
                return Err(std::io::Error::from(std::io::ErrorKind::UnexpectedEof).into());
            }
            progress();
        }
        let timing =
            clock
                .zip(started_us)
                .map(|(clock, started_us)| crate::read_trace::PayloadTiming {
                    started_us,
                    read_us: (clock.read)(),
                    clock,
                });
        if !skip_checksum && checksum(&payload) != wire_checksum {
            return Err(Error::Protocol("invalid frame checksum".into()));
        }
        Ok((
            Self {
                command,
                arg0,
                arg1,
                payload,
            },
            timing,
        ))
    }

    pub async fn write<W: AsyncWrite + Unpin>(&self, writer: &mut W) -> Result<()> {
        self.write_with_checksum(writer, false).await
    }

    pub(crate) async fn write_with_checksum<W: AsyncWrite + Unpin>(
        &self,
        writer: &mut W,
        skip_checksum: bool,
    ) -> Result<()> {
        if self.payload.len() > MAX_PAYLOAD {
            return Err(Error::InvalidArgument("frame too large"));
        }
        let mut header = [0; 24];
        for (i, value) in [
            self.command,
            self.arg0,
            self.arg1,
            self.payload.len() as u32,
            if skip_checksum {
                0
            } else {
                checksum(&self.payload)
            },
            self.command ^ u32::MAX,
        ]
        .iter()
        .enumerate()
        {
            header[i * 4..i * 4 + 4].copy_from_slice(&value.to_le_bytes());
        }
        writer.write_all(&header).await?;
        writer.write_all(&self.payload).await?;
        writer.flush().await?;
        Ok(())
    }
}

/// ADB 头部与 payload 分为独立 USB transfer 时仍保持原始发送字节，尤其不能重新计算已协商校验和。
#[cfg(all(
    feature = "usb",
    any(
        target_os = "linux",
        target_os = "android",
        target_os = "windows",
        target_os = "macos"
    )
))]
#[cfg(test)]
pub(crate) async fn read_wire_packet<R: AsyncRead + Unpin>(
    reader: &mut R,
) -> Result<([u8; 24], Vec<u8>)> {
    let mut header = [0; 24];
    reader.read_exact(&mut header).await?;
    let words = validate_header(&header, MAX_PAYLOAD)?;
    let mut payload = vec![0; words[3] as usize];
    reader.read_exact(&mut payload).await?;
    Ok((header, payload))
}

pub(crate) fn validate_header(header: &[u8; 24], limit: usize) -> Result<[u32; 6]> {
    let words = std::array::from_fn(|index| {
        u32::from_le_bytes(
            header[index * 4..index * 4 + 4]
                .try_into()
                .expect("header word"),
        )
    });
    let command = words[0];
    if words[5] != command ^ u32::MAX {
        return Err(Error::Protocol("invalid frame magic".into()));
    }
    if !matches!(command, CNXN | AUTH | OPEN | OKAY | WRTE | CLSE | STLS) {
        return Err(Error::Protocol("unknown frame command".into()));
    }
    if words[3] as usize > limit.min(MAX_PAYLOAD) {
        return Err(Error::Protocol(
            "frame exceeds negotiated payload limit".into(),
        ));
    }
    Ok(words)
}

async fn read_exact_progress<R: AsyncRead + Unpin>(
    reader: &mut R,
    mut bytes: &mut [u8],
    progress: &mut impl FnMut(),
) -> std::io::Result<()> {
    while !bytes.is_empty() {
        let count = reader.read(bytes).await?;
        if count == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        progress();
        bytes = &mut bytes[count..];
    }
    Ok(())
}

fn checksum(bytes: &[u8]) -> u32 {
    bytes
        .iter()
        .fold(0u32, |sum, byte| sum.wrapping_add(*byte as u32))
}
