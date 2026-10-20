//! Bounded async/blocking codec bridge. Network errors never enter ruzstd's
//! infallible encoder I/O API: disconnected channels become EOF/discard, and the
//! async owner reports the actual I/O/cancellation error. Memory is per chunk.
use crate::{Error, Result};
use std::{
    io::{self, Read, Write},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tokio::{sync::mpsc, task::JoinHandle};

pub(crate) const CHUNK: usize = 64 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compression {
    None,
    Brotli,
    Lz4,
    Zstd,
}
impl Compression {
    pub(crate) fn flag(self) -> u32 {
        match self {
            Self::None => 0,
            Self::Brotli => 1,
            Self::Lz4 => 2,
            Self::Zstd => 4,
        }
    }
    pub(crate) fn feature(self) -> &'static str {
        match self {
            Self::None => "sendrecv_v2",
            Self::Brotli => "sendrecv_v2_brotli",
            Self::Lz4 => "sendrecv_v2_lz4",
            Self::Zstd => "sendrecv_v2_zstd",
        }
    }
}

pub(crate) struct Worker {
    pub input: mpsc::Sender<Vec<u8>>,
    pub output: mpsc::Receiver<Vec<u8>>,
    pub task: JoinHandle<Result<()>>,
}
impl Worker {
    pub fn start(codec: Compression, encode: bool) -> Self {
        let (input_tx, input_rx) = mpsc::channel(1);
        let (output_tx, output_rx) = mpsc::channel(1);
        let task = tokio::task::spawn_blocking(move || {
            let disconnected = Arc::new(AtomicBool::new(false));
            let mut input = ChannelRead {
                receiver: input_rx,
                buffer: vec![],
                offset: 0,
                disconnected: disconnected.clone(),
            };
            let mut output = ChannelWrite {
                sender: output_tx,
                disconnected: disconnected.clone(),
            };
            transform(codec, encode, &mut input, &mut output)
                .map_err(|error| Error::Compression(error.to_string()))?;
            if disconnected.load(Ordering::Relaxed) {
                return Err(Error::Closed);
            }
            Ok(())
        });
        Self {
            input: input_tx,
            output: output_rx,
            task,
        }
    }
}

struct ChannelRead {
    receiver: mpsc::Receiver<Vec<u8>>,
    buffer: Vec<u8>,
    offset: usize,
    disconnected: Arc<AtomicBool>,
}
impl Read for ChannelRead {
    fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
        if output.is_empty() || self.disconnected.load(Ordering::Relaxed) {
            return Ok(0);
        }
        while self.offset == self.buffer.len() {
            match self.receiver.blocking_recv() {
                Some(bytes) => {
                    self.buffer = bytes;
                    self.offset = 0;
                }
                None => return Ok(0),
            }
        }
        let count = output.len().min(self.buffer.len() - self.offset);
        output[..count].copy_from_slice(&self.buffer[self.offset..self.offset + count]);
        self.offset += count;
        Ok(count)
    }
}
struct ChannelWrite {
    sender: mpsc::Sender<Vec<u8>>,
    disconnected: Arc<AtomicBool>,
}
impl Write for ChannelWrite {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if !self.disconnected.load(Ordering::Relaxed) {
            for chunk in bytes.chunks(CHUNK) {
                if self.sender.blocking_send(chunk.to_vec()).is_err() {
                    self.disconnected.store(true, Ordering::Relaxed);
                    break;
                }
            }
        }
        // ruzstd unconditionally unwraps Write results. This adapter is deliberately
        // infallible; disconnection is separately observed and reported by the worker.
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn transform(
    codec: Compression,
    encode: bool,
    input: &mut impl Read,
    output: &mut impl Write,
) -> io::Result<()> {
    match (codec, encode) {
        (Compression::None, _) => {
            io::copy(input, output)?;
        }
        (Compression::Brotli, true) => {
            let mut encoder = brotli::CompressorWriter::new(output, CHUNK, 3, 22);
            io::copy(input, &mut encoder)?;
            encoder.into_inner();
        }
        (Compression::Lz4, true) => {
            let mut encoder = lz4_flex::frame::FrameEncoder::new(output);
            io::copy(input, &mut encoder)?;
            encoder.finish().map_err(io::Error::other)?;
        }
        (Compression::Zstd, true) => {
            let mut encoder =
                ruzstd::encoding::FrameCompressor::new(ruzstd::encoding::CompressionLevel::Fastest);
            encoder.set_source(input);
            encoder.set_drain(output);
            encoder.compress();
        }
        (Compression::Brotli, false) => {
            io::copy(&mut brotli::Decompressor::new(input, CHUNK), output)?;
        }
        (Compression::Lz4, false) => {
            io::copy(&mut lz4_flex::frame::FrameDecoder::new(input), output)?;
        }
        (Compression::Zstd, false) => {
            let mut decoder = ruzstd::decoding::StreamingDecoder::new_with_max_window_size(
                &mut *input,
                8 * 1024 * 1024,
            )
            .map_err(io::Error::other)?;
            io::copy(&mut decoder, output)?;
            if let Some(expected) = decoder.decoder.get_checksum_from_data()
                && Some(expected) != decoder.decoder.get_calculated_checksum()
            {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Zstd checksum mismatch",
                ));
            }
            let mut trailing = [0];
            if decoder.into_inner().read(&mut trailing)? != 0 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "trailing bytes after Zstd frame",
                ));
            }
        }
    }
    Ok(())
}

pub(crate) async fn finished(task: JoinHandle<Result<()>>) -> Result<()> {
    task.await
        .map_err(|error| Error::Compression(format!("codec worker failed: {error}")))?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn dropping_output_during_encoding_terminates_without_panicking() {
        let Worker {
            input,
            output,
            task,
        } = Worker::start(Compression::Zstd, true);
        drop(output);
        input.send(vec![42; CHUNK]).await.unwrap();
        drop(input);
        assert!(matches!(finished(task).await, Err(Error::Closed)));
    }
}
