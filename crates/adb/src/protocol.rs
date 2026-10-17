//! ADB transport frames. Limits are checked before allocating payload storage.
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
        let mut header = [0; 24];
        reader.read_exact(&mut header).await?;
        let word = |offset| {
            u32::from_le_bytes(header[offset..offset + 4].try_into().expect("header word"))
        };
        let command = word(0);
        if word(20) != command ^ u32::MAX {
            return Err(Error::Protocol("invalid frame magic".into()));
        }
        if !matches!(command, CNXN | AUTH | OPEN | OKAY | WRTE | CLSE | STLS) {
            return Err(Error::Protocol("unknown frame command".into()));
        }
        let length = word(12) as usize;
        if length > limit.min(MAX_PAYLOAD) {
            return Err(Error::Protocol(
                "frame exceeds negotiated payload limit".into(),
            ));
        }
        let mut payload = vec![0; length];
        let clock = observe(command, word(4), word(8));
        let started_us = clock.as_ref().map(|clock| (clock.read)());
        reader.read_exact(&mut payload).await?;
        let timing =
            clock
                .zip(started_us)
                .map(|(clock, started_us)| crate::read_trace::PayloadTiming {
                    started_us,
                    read_us: (clock.read)(),
                    clock,
                });
        if !skip_checksum && checksum(&payload) != word(16) {
            return Err(Error::Protocol("invalid frame checksum".into()));
        }
        Ok((
            Self {
                command,
                arg0: word(4),
                arg1: word(8),
                payload,
            },
            timing,
        ))
    }

    pub async fn write<W: AsyncWrite + Unpin>(&self, writer: &mut W) -> Result<()> {
        if self.payload.len() > MAX_PAYLOAD {
            return Err(Error::InvalidArgument("frame too large"));
        }
        let mut header = [0; 24];
        for (i, value) in [
            self.command,
            self.arg0,
            self.arg1,
            self.payload.len() as u32,
            checksum(&self.payload),
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

fn checksum(bytes: &[u8]) -> u32 {
    bytes
        .iter()
        .fold(0u32, |sum, byte| sum.wrapping_add(*byte as u32))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn verifies_magic_checksum_and_limits() {
        let frame = Frame::new(WRTE, 1, 2, b"hello".to_vec());
        let mut bytes = Vec::new();
        frame.write(&mut bytes).await.unwrap();
        assert_eq!(
            Frame::read(&mut &bytes[..], 4096, false).await.unwrap(),
            frame
        );
        let mut bad = bytes.clone();
        bad[20] ^= 1;
        assert!(Frame::read(&mut &bad[..], 4096, false).await.is_err());
        let mut bad = bytes.clone();
        bad[24] ^= 1;
        assert!(Frame::read(&mut &bad[..], 4096, false).await.is_err());
        assert!(Frame::read(&mut &bytes[..], 4, false).await.is_err());
        assert!(Frame::read(&mut &bytes[..26], 4096, false).await.is_err());
        let mut oversized = bytes[..24].to_vec();
        oversized[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(matches!(
            Frame::read(&mut &oversized[..], MAX_PAYLOAD, true).await,
            Err(Error::Protocol(_))
        ));
    }
}
