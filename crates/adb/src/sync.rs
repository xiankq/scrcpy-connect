//! Streaming ADB sync. No shell interpolation and no whole-file buffering.
pub use crate::compression::Compression;
use crate::compression::{Worker, finished};
use crate::{AdbStream, Error, OperationOptions, Result, error::bounded};
use std::collections::HashSet;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

const MAX_PATH: usize = 1024;
const MAX_DATA: usize = 64 * 1024;
const MAX_ERROR: usize = 64 * 1024;

/// A push owns this buffer only until its completion response. Aggregate SYNC
/// records, not arbitrary interactive stream writes, and never send on drop.
struct PushWriter<'a> {
    stream: &'a mut AdbStream,
    bytes: Vec<u8>,
    max_payload: usize,
}

impl<'a> PushWriter<'a> {
    fn new(stream: &'a mut AdbStream) -> Self {
        let max_payload = stream.max_payload();
        Self {
            stream,
            bytes: Vec::with_capacity(max_payload),
            max_payload,
        }
    }

    async fn write(&mut self, mut bytes: &[u8]) -> Result<()> {
        while !bytes.is_empty() {
            let count = bytes.len().min(self.max_payload - self.bytes.len());
            self.bytes.extend_from_slice(&bytes[..count]);
            bytes = &bytes[count..];
            if self.bytes.len() == self.max_payload {
                self.flush().await?;
            }
        }
        Ok(())
    }

    async fn request(&mut self, id: &[u8; 4], body: &[u8]) -> Result<()> {
        let mut header = [0; 8];
        header[..4].copy_from_slice(id);
        header[4..].copy_from_slice(&(body.len() as u32).to_le_bytes());
        self.write(&header).await?;
        self.write(body).await
    }

    async fn flush(&mut self) -> Result<()> {
        if !self.bytes.is_empty() {
            self.stream.write_all(&self.bytes).await?;
            self.bytes.clear();
        }
        Ok(())
    }
}

/// A remote Linux pathname, represented as bytes (Android paths need not be UTF-8).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemotePath(Vec<u8>);
impl RemotePath {
    pub fn new(path: impl AsRef<[u8]>) -> Result<Self> {
        let path = path.as_ref();
        if path.is_empty() || path.len() > MAX_PATH || path.contains(&0) {
            return Err(Error::InvalidArgument(
                "remote path is empty, too long, or contains NUL",
            ));
        }
        Ok(Self(path.to_vec()))
    }
    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileStat {
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirEntry {
    pub name: Vec<u8>,
    pub stat: FileStat,
}

pub struct Sync {
    stream: AdbStream,
    options: OperationOptions,
    features: HashSet<String>,
    healthy: bool,
}
impl Sync {
    fn check_compression(&self, compression: Compression) -> Result<()> {
        if !self.features.contains("sendrecv_v2") || !self.features.contains(compression.feature())
        {
            return Err(Error::Unsupported("requested sync v2 compression"));
        }
        Ok(())
    }

    /// Stream compressed SEND_V2 using a bounded codec worker. The byte limit
    /// applies to the original file, independently of compression ratio.
    pub async fn push_compressed<R: AsyncRead + Unpin>(
        &mut self,
        path: &RemotePath,
        input: &mut R,
        permissions: u32,
        modified_seconds: u32,
        max_bytes: u64,
        compression: Compression,
    ) -> Result<u64> {
        if compression == Compression::None {
            return self
                .push(path, input, permissions, modified_seconds, max_bytes)
                .await;
        }
        self.check_compression(compression)?;
        if permissions & !0o777 != 0 {
            return Err(Error::InvalidArgument("push permissions exceed 0777"));
        }
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            let mut writer = PushWriter::new(&mut self.stream);
            writer.request(b"SND2", path.as_bytes()).await?;
            let mut setup = b"SND2".to_vec();
            setup.extend_from_slice(&(0o100000 | permissions).to_le_bytes());
            setup.extend_from_slice(&compression.flag().to_le_bytes());
            writer.write(&setup).await?;
            let Worker {
                input: sender,
                mut output,
                task,
            } = Worker::start(compression, true);
            let producer = async {
                let mut buffer = vec![0; MAX_DATA];
                let mut total = 0u64;
                loop {
                    let count = input.read(&mut buffer).await?;
                    if count == 0 {
                        break;
                    }
                    total = total.checked_add(count as u64).ok_or(Error::OutputLimit)?;
                    if total > max_bytes {
                        return Err(Error::OutputLimit);
                    }
                    sender
                        .send(buffer[..count].to_vec())
                        .await
                        .map_err(|_| Error::Closed)?;
                }
                drop(sender);
                Ok::<_, Error>(total)
            };
            let consumer = async {
                while let Some(bytes) = output.recv().await {
                    writer.request(b"DATA", &bytes).await?;
                }
                finished(task).await
            };
            let (total, ()) = tokio::try_join!(producer, consumer)?;
            let mut done = b"DONE".to_vec();
            done.extend_from_slice(&modified_seconds.to_le_bytes());
            writer.write(&done).await?;
            writer.flush().await?;
            let id = self.id().await?;
            if &id == b"FAIL" {
                return Err(self.fail().await?);
            }
            if &id != b"OKAY" || self.word().await? != 0 {
                return Err(Error::Protocol("invalid compressed push completion".into()));
            }
            Ok(total)
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }

    /// Receive compressed RECV_V2 with a decompressed byte limit. Codec queues
    /// contain at most one 64 KiB chunk in each direction; Zstd windows are capped at 8 MiB.
    pub async fn pull_compressed<W: AsyncWrite + Unpin>(
        &mut self,
        path: &RemotePath,
        output: &mut W,
        max_bytes: u64,
        compression: Compression,
    ) -> Result<u64> {
        if compression == Compression::None {
            return self.pull(path, output, max_bytes).await;
        }
        self.check_compression(compression)?;
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            self.request(b"RCV2", path.as_bytes()).await?;
            let mut setup = b"RCV2".to_vec();
            setup.extend_from_slice(&compression.flag().to_le_bytes());
            self.stream.write_all(&setup).await?;
            let Worker {
                input: sender,
                output: mut receiver,
                task,
            } = Worker::start(compression, false);
            let producer = async {
                loop {
                    let id = self.id().await?;
                    if &id == b"FAIL" {
                        return Err(self.fail().await?);
                    }
                    let length = self.word().await? as usize;
                    if &id == b"DONE" {
                        if length != 0 {
                            return Err(Error::Protocol(
                                "invalid compressed pull terminator".into(),
                            ));
                        }
                        break;
                    }
                    if &id != b"DATA" || length > MAX_DATA {
                        return Err(Error::Protocol(
                            "invalid compressed sync data packet".into(),
                        ));
                    }
                    let mut bytes = vec![0; length];
                    self.stream.read_exact(&mut bytes).await?;
                    sender.send(bytes).await.map_err(|_| {
                        Error::Compression("decoder closed before sync DONE".into())
                    })?;
                }
                drop(sender);
                Ok::<_, Error>(())
            };
            let consumer = async {
                let mut total = 0u64;
                while let Some(bytes) = receiver.recv().await {
                    total = total
                        .checked_add(bytes.len() as u64)
                        .ok_or(Error::OutputLimit)?;
                    if total > max_bytes {
                        return Err(Error::OutputLimit);
                    }
                    output.write_all(&bytes).await?;
                }
                finished(task).await?;
                output.flush().await?;
                Ok::<_, Error>(total)
            };
            let ((), total) = tokio::try_join!(producer, consumer)?;
            Ok(total)
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }

    pub(crate) fn new(
        stream: AdbStream,
        options: OperationOptions,
        features: HashSet<String>,
    ) -> Self {
        Self {
            stream,
            options,
            features,
            healthy: true,
        }
    }

    async fn request(&mut self, id: &[u8; 4], path: &[u8]) -> Result<()> {
        let mut request = Vec::with_capacity(8 + path.len());
        request.extend_from_slice(id);
        request.extend_from_slice(&(path.len() as u32).to_le_bytes());
        request.extend_from_slice(path);
        self.stream.write_all(&request).await
    }

    async fn word(&mut self) -> Result<u32> {
        let mut bytes = [0; 4];
        self.stream.read_exact(&mut bytes).await?;
        Ok(u32::from_le_bytes(bytes))
    }
    async fn id(&mut self) -> Result<[u8; 4]> {
        let mut bytes = [0; 4];
        self.stream.read_exact(&mut bytes).await?;
        Ok(bytes)
    }
    async fn fail(&mut self) -> Result<Error> {
        let length = self.word().await? as usize;
        if length > MAX_ERROR {
            return Err(Error::Protocol("sync failure message exceeds limit".into()));
        }
        let mut bytes = vec![0; length];
        self.stream.read_exact(&mut bytes).await?;
        Ok(Error::Remote(String::from_utf8_lossy(&bytes).into_owned()))
    }

    /// Follow the final symlink using stat_v2, retaining 64-bit sizes. Legacy
    /// adbd only supplies no-follow STAT with 32-bit size/time, used as a fallback.
    pub async fn stat(&mut self, path: &RemotePath) -> Result<FileStat> {
        self.metadata(path, true).await
    }

    /// Inspect one path without following its final symlink (LST2 or legacy
    /// STAT). This does not list the parent directory. Intermediate components
    /// still follow normal kernel pathname resolution. Legacy metadata has
    /// 32-bit size/time and cannot distinguish absence from permission errors.
    pub async fn lstat(&mut self, path: &RemotePath) -> Result<FileStat> {
        self.metadata(path, false).await
    }

    async fn metadata(&mut self, path: &RemotePath, follow: bool) -> Result<FileStat> {
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            let v2 = self.features.contains("stat_v2");
            let request = if v2 {
                if follow { b"STA2" } else { b"LST2" }
            } else {
                b"STAT"
            };
            self.request(request, path.as_bytes()).await?;
            let id = self.id().await?;
            if &id == b"FAIL" {
                return Err(self.fail().await?);
            }
            if v2 {
                if &id != request {
                    return Err(Error::Protocol("unexpected stat_v2 response".into()));
                }
                let mut bytes = [0; 68];
                self.stream.read_exact(&mut bytes).await?;
                let u32_at = |offset| {
                    u32::from_le_bytes(bytes[offset..offset + 4].try_into().expect("stat field"))
                };
                let u64_at = |offset| {
                    u64::from_le_bytes(bytes[offset..offset + 8].try_into().expect("stat field"))
                };
                let errno = u32_at(0);
                if errno != 0 {
                    return Err(Error::RemoteErrno {
                        operation: "stat",
                        errno,
                    });
                }
                Ok(FileStat {
                    mode: u32_at(20),
                    size: u64_at(36),
                    modified_seconds: u64_at(52) as i64,
                })
            } else {
                if &id != b"STAT" {
                    return Err(Error::Protocol("unexpected stat response".into()));
                }
                let mode = self.word().await?;
                let size = self.word().await?;
                let modified = self.word().await?;
                if mode == 0 {
                    return Err(Error::Remote("remote path does not exist".into()));
                }
                Ok(FileStat {
                    mode,
                    size: size as u64,
                    modified_seconds: modified as i64,
                })
            }
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }

    /// Bound the number of entries independently from packet lengths.
    pub async fn list(&mut self, path: &RemotePath, max_entries: usize) -> Result<Vec<DirEntry>> {
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            let v2 = self.features.contains("ls_v2");
            self.request(if v2 { b"LIS2" } else { b"LIST" }, path.as_bytes())
                .await?;
            let mut entries = Vec::new();
            loop {
                let id = self.id().await?;
                if &id == b"FAIL" {
                    return Err(self.fail().await?);
                }
                if &id != (if v2 { b"DNT2" } else { b"DENT" }) && &id != b"DONE" {
                    return Err(Error::Protocol("unexpected directory response".into()));
                }
                let (stat, length) = if v2 {
                    let mut bytes = [0; 72];
                    self.stream.read_exact(&mut bytes).await?;
                    let u32_at = |offset| {
                        u32::from_le_bytes(
                            bytes[offset..offset + 4].try_into().expect("dent field"),
                        )
                    };
                    let u64_at = |offset| {
                        u64::from_le_bytes(
                            bytes[offset..offset + 8].try_into().expect("dent field"),
                        )
                    };
                    if &id != b"DONE" && u32_at(0) != 0 {
                        return Err(Error::RemoteErrno {
                            operation: "list",
                            errno: u32_at(0),
                        });
                    }
                    (
                        FileStat {
                            mode: u32_at(20),
                            size: u64_at(36),
                            modified_seconds: u64_at(52) as i64,
                        },
                        u32_at(68) as usize,
                    )
                } else {
                    let mode = self.word().await?;
                    let size = self.word().await?;
                    let modified = self.word().await?;
                    let length = self.word().await? as usize;
                    (
                        FileStat {
                            mode,
                            size: size as u64,
                            modified_seconds: modified as i64,
                        },
                        length,
                    )
                };
                if &id == b"DONE" {
                    if length != 0 {
                        return Err(Error::Protocol("invalid directory terminator".into()));
                    }
                    break;
                }
                if length == 0 || length > MAX_PATH {
                    return Err(Error::Protocol(
                        "invalid directory entry name length".into(),
                    ));
                }
                if entries.len() >= max_entries {
                    return Err(Error::OutputLimit);
                }
                let mut name = vec![0; length];
                self.stream.read_exact(&mut name).await?;
                if name.iter().any(|b| *b == 0 || *b == b'/') {
                    return Err(Error::Protocol("unsafe directory entry name".into()));
                }
                if name == b"." || name == b".." {
                    continue;
                }
                entries.push(DirEntry { name, stat });
            }
            Ok(entries)
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }

    /// Pull to an async writer with a byte limit and backpressure. Returns transferred bytes.
    pub async fn pull<W: AsyncWrite + Unpin>(
        &mut self,
        path: &RemotePath,
        output: &mut W,
        max_bytes: u64,
    ) -> Result<u64> {
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            self.request(b"RECV", path.as_bytes()).await?;
            let mut total = 0u64;
            loop {
                let id = self.id().await?;
                if &id == b"FAIL" {
                    return Err(self.fail().await?);
                }
                let length = self.word().await? as usize;
                if &id == b"DONE" {
                    if length != 0 {
                        return Err(Error::Protocol("invalid pull terminator".into()));
                    }
                    break;
                }
                if &id != b"DATA" || length > MAX_DATA {
                    return Err(Error::Protocol("invalid sync data packet".into()));
                }
                total = total.checked_add(length as u64).ok_or(Error::OutputLimit)?;
                if total > max_bytes {
                    return Err(Error::OutputLimit);
                }
                let mut buffer = vec![0; length];
                self.stream.read_exact(&mut buffer).await?;
                output.write_all(&buffer).await?;
            }
            output.flush().await?;
            Ok(total)
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }

    /// Push one regular file; mode is limited to Unix permission bits. Does not interpolate a shell command.
    pub async fn push<R: AsyncRead + Unpin>(
        &mut self,
        path: &RemotePath,
        input: &mut R,
        permissions: u32,
        modified_seconds: u32,
        max_bytes: u64,
    ) -> Result<u64> {
        if permissions & !0o777 != 0 {
            return Err(Error::InvalidArgument("push permissions exceed 0777"));
        }
        if !self.healthy {
            return Err(Error::Closed);
        }
        self.healthy = false;
        let options = self.options.clone();
        let result = bounded(options.timeout, &options.cancellation, async {
            let mut destination = path.as_bytes().to_vec();
            destination.extend_from_slice(format!(",{}", 0o100000 | permissions).as_bytes());
            if destination.len() > MAX_PATH {
                return Err(Error::InvalidArgument(
                    "push path plus mode exceeds sync limit",
                ));
            }
            let mut writer = PushWriter::new(&mut self.stream);
            writer.request(b"SEND", &destination).await?;
            let mut buffer = vec![0; MAX_DATA];
            let mut total = 0u64;
            loop {
                let count = input.read(&mut buffer).await?;
                if count == 0 {
                    break;
                }
                total = total.checked_add(count as u64).ok_or(Error::OutputLimit)?;
                if total > max_bytes {
                    return Err(Error::OutputLimit);
                }
                writer.request(b"DATA", &buffer[..count]).await?;
            }
            let mut done = b"DONE".to_vec();
            done.extend_from_slice(&modified_seconds.to_le_bytes());
            writer.write(&done).await?;
            writer.flush().await?;
            let id = self.id().await?;
            if &id == b"FAIL" {
                return Err(self.fail().await?);
            }
            if &id != b"OKAY" || self.word().await? != 0 {
                return Err(Error::Protocol("invalid push completion response".into()));
            }
            Ok(total)
        })
        .await;
        self.healthy = result.is_ok();
        if !self.healthy {
            self.stream.close_now();
        }
        result
    }
}
