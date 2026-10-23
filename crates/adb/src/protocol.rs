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
        Self::read_observed_progress(reader, limit, skip_checksum, observe, || {}).await
    }

    /// Internal transport progress hook. Every nonempty read, including a
    /// partial header or payload, counts as activity before frame validation.
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
            // read_buf initializes only the bytes received. A fresh payload
            // need not first be zeroed in full and then overwritten by I/O.
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

/// Preserve outgoing wire bytes while splitting ADB header and payload into
/// separate USB transfers. In particular, never recompute a negotiated checksum.
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

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(all(
        feature = "usb",
        any(
            target_os = "linux",
            target_os = "android",
            target_os = "windows",
            target_os = "macos"
        )
    ))]
    #[tokio::test]
    async fn usb_packet_split_preserves_legacy_and_omitted_checksums() {
        let frame = Frame::new(WRTE, 1, 2, b"usb payload");
        for skip_checksum in [false, true] {
            let mut bytes = Vec::new();
            frame
                .write_with_checksum(&mut bytes, skip_checksum)
                .await
                .unwrap();
            let (header, payload) = read_wire_packet(&mut bytes.as_slice()).await.unwrap();
            assert_eq!(&header[..], &bytes[..24]);
            assert_eq!(payload, frame.payload);
            let actual = u32::from_le_bytes(header[16..20].try_into().unwrap());
            assert_eq!(
                actual,
                if skip_checksum {
                    0
                } else {
                    checksum(&frame.payload)
                }
            );
        }
    }

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
