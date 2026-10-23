//! File execution facts; Dart owns traversal, ordering and durable task state.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{quote, remote_path},
};
use interop_adb::{
    CancellationToken, OperationOptions,
    sync::{FileStat, RemotePath},
};
use std::{
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};
use std::{
    pin::Pin,
    task::{Context, Poll},
};
use tokio::{
    fs,
    io::{AsyncRead, AsyncWrite, ReadBuf},
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileStamp {
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
    pub modified_nanos: u32,
}
impl From<FileStat> for FileStamp {
    fn from(s: FileStat) -> Self {
        Self {
            mode: s.mode,
            size: s.size,
            modified_seconds: s.modified_seconds,
            modified_nanos: 0,
        }
    }
}
#[derive(Clone)]
pub struct EntryFact {
    pub name: Vec<u8>,
    pub stamp: Option<FileStamp>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}
pub struct DirectoryFacts {
    pub entries: Vec<EntryFact>,
    pub truncated: bool,
}
fn options(token: CancellationToken) -> OperationOptions {
    OperationOptions {
        cancellation: token,
        timeout: Duration::from_secs(120),
    }
}
fn cancelled(token: &CancellationToken) -> CoreResult<()> {
    if token.is_cancelled() {
        Err(CoreError::new("cancelled", "文件执行已取消。"))
    } else {
        Ok(())
    }
}
fn file_io(error: std::io::Error) -> CoreError {
    let code = match error.kind() {
        std::io::ErrorKind::NotFound => "not_found",
        std::io::ErrorKind::AlreadyExists => "conflict",
        std::io::ErrorKind::PermissionDenied => "permission_denied",
        _ => "io_error",
    };
    CoreError::new(code, error.to_string())
}
fn local(path: &str) -> CoreResult<PathBuf> {
    let p = PathBuf::from(path);
    if !p.is_absolute() || path.contains('\0') {
        return Err(CoreError::new("invalid_path", "本机路径必须为绝对路径。"));
    }
    Ok(p)
}
async fn local_stat(path: &str) -> CoreResult<FileStamp> {
    let meta = fs::symlink_metadata(local(path)?).await.map_err(file_io)?;
    let time = meta
        .modified()?
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| CoreError::new("invalid_timestamp", "源文件时间戳无效。"))?;
    let mode = if meta.file_type().is_symlink() {
        0o120000
    } else if meta.is_dir() {
        0o040000
    } else if meta.is_file() {
        0o100000
    } else {
        0
    };
    Ok(FileStamp {
        mode,
        size: meta.len(),
        modified_seconds: time.as_secs().min(i64::MAX as u64) as i64,
        modified_nanos: time.subsec_nanos(),
    })
}
impl Runtime {
    pub(crate) async fn cancel_file_executions(&self, device: &str) {
        let prefix = format!("file:{device}:");
        self.file_parts
            .lock()
            .expect("file parts")
            .retain(|_, (owner, _)| owner != device);
        let mut active = self.device_operations.lock().await;
        let keys = active
            .keys()
            .filter(|key| key.starts_with(&prefix))
            .cloned()
            .collect::<Vec<_>>();
        for key in keys {
            if let Some(token) = active.remove(&key) {
                token.cancel();
            }
        }
    }

    pub async fn register_file_execution(&self, key: &str, token: CancellationToken) {
        self.device_operations
            .lock()
            .await
            .insert(key.into(), token);
    }
    pub async fn unregister_file_execution(&self, key: &str) {
        self.device_operations.lock().await.remove(key);
    }
    pub async fn execute_file_stat(
        &self,
        device: &str,
        path: &str,
        local_path: bool,
        follow_alias: bool,
        token: CancellationToken,
    ) -> CoreResult<FileStamp> {
        cancelled(&token)?;
        if local_path {
            return local_stat(path).await;
        }
        let path = remote_path(path)?;
        let client = self.client(device).await?;
        Ok(
            crate::remote_fs::stat(&client, &path, follow_alias, options(token))
                .await?
                .into(),
        )
    }
    pub async fn execute_file_list(
        &self,
        device: &str,
        path: &str,
        local_path: bool,
        limit: usize,
        token: CancellationToken,
    ) -> CoreResult<DirectoryFacts> {
        cancelled(&token)?;
        if !(1..=10_000).contains(&limit) {
            return Err(CoreError::new(
                "invalid_argument",
                "目录上限必须为1至10000。",
            ));
        }
        if local_path {
            let before = local_stat(path).await?;
            if before.mode & 0o170000 != 0o040000 {
                return Err(CoreError::new("not_directory", "目录路径已变化或是链接。"));
            }
            let mut dir = fs::read_dir(local(path)?).await?;
            let mut entries = Vec::new();
            let mut truncated = false;
            while let Some(entry) = dir.next_entry().await? {
                cancelled(&token)?;
                if entries.len() == limit {
                    truncated = true;
                    break;
                }
                #[cfg(unix)]
                let name = {
                    use std::os::unix::ffi::OsStrExt;
                    entry.file_name().as_bytes().to_vec()
                };
                #[cfg(not(unix))]
                let name = entry.file_name().to_string_lossy().as_bytes().to_vec();
                let stat = local_stat(&entry.path().to_string_lossy()).await;
                entries.push(fact(name, stat));
            }
            if local_stat(path).await? != before {
                return Err(CoreError::new("source_changed", "读取期间目录已变化。"));
            }
            return Ok(DirectoryFacts { entries, truncated });
        }
        let path = remote_path(path)?;
        let client = self.client(device).await?;
        let opts = options(token);
        // Child links are never followed. Only explicit storage aliases may be roots.
        let root = crate::remote_fs::stat(&client, &path, true, opts.clone()).await?;
        if root.mode & 0o170000 != 0o040000 {
            return Err(CoreError::new("not_directory", "路径不是可浏览目录。"));
        }
        if client.info().features.contains("ls_v2") {
            let mut sync = client.sync(opts.clone()).await?;
            match sync.list(&RemotePath::new(&path)?, limit + 1).await {
                Ok(list) => {
                    if list.is_empty()
                        && !crate::remote_fs::accessible(&client, &path, opts.clone()).await?
                    {
                        return Err(CoreError::new(
                            "permission_denied",
                            "设备未授予读取此空目录的权限，不能确认目录内容。",
                        ));
                    }
                    if crate::remote_fs::stat(&client, &path, true, opts.clone()).await? != root {
                        return Err(CoreError::new("source_changed", "读取期间目录已变化。"));
                    }
                    let truncated = list.len() > limit;
                    return Ok(DirectoryFacts {
                        entries: list
                            .into_iter()
                            .take(limit)
                            .map(|e| fact(e.name, Ok(e.stat.into())))
                            .collect(),
                        truncated,
                    });
                }
                Err(
                    interop_adb::Error::RemoteErrno {
                        errno: 1 | 13 | 38 | 95,
                        ..
                    }
                    | interop_adb::Error::Remote(_)
                    | interop_adb::Error::Unsupported(_)
                    | interop_adb::Error::OutputLimit,
                ) => {}
                Err(error) => return Err(error.into()),
            }
        }
        let list = crate::remote_fs::fallback_children(&client, &path, limit, opts.clone()).await?;
        if crate::remote_fs::stat(&client, &path, true, opts).await? != root {
            return Err(CoreError::new("source_changed", "读取期间目录已变化。"));
        }
        Ok(DirectoryFacts {
            entries: list
                .entries
                .into_iter()
                .map(|(name, stat)| fact(name, stat.map(Into::into)))
                .collect(),
            truncated: list.truncated,
        })
    }
    // Flat execution fields map directly to typed FFI controls, never business state.
    #[allow(clippy::too_many_arguments)]
    pub async fn execute_file_mutation(
        &self,
        device: &str,
        action: &str,
        path: &str,
        destination: &str,
        local_path: bool,
        replace: bool,
        token: CancellationToken,
    ) -> CoreResult<String> {
        if action == "releasePart" {
            self.file_parts.lock().expect("file parts").remove(path);
            return Ok("released".into());
        }
        cancelled(&token)?;
        if local_path {
            let path = local(path)?;
            match action {
                "mkdir" => {
                    fs::create_dir(&path).await?;
                    Ok("directoryCreated".into())
                }
                "commit" => {
                    let destination = local(destination)?;
                    let meta = fs::symlink_metadata(&path).await?;
                    if !meta.is_file() || meta.file_type().is_symlink() {
                        return Err(CoreError::new("not_a_file", "暂存路径不是普通文件。"));
                    }
                    let file = self
                        .file_parts
                        .lock()
                        .expect("file parts")
                        .remove(path.to_string_lossy().as_ref())
                        .map(|(_, file)| file)
                        .ok_or_else(|| {
                            CoreError::new("source_changed", "暂存句柄已过期，未发布内容。")
                        })?;
                    file.sync_all()?;
                    #[cfg(any(target_os = "linux", target_os = "android"))]
                    {
                        let file = file.clone();
                        tokio::task::spawn_blocking(move || {
                            if replace {
                                crate::local_publication::publish_file_replace(
                                    &file,
                                    &path,
                                    &destination,
                                )
                            } else {
                                crate::local_publication::publish_file(&file, &path, &destination)
                            }
                        })
                        .await
                        .map_err(|e| CoreError::new("result_unknown", e.to_string()))??;
                    }
                    #[cfg(not(any(target_os = "linux", target_os = "android")))]
                    {
                        let held = file.metadata()?;
                        if held.len() != meta.len() || held.modified()? != meta.modified()? {
                            return Err(CoreError::new(
                                "source_changed",
                                "暂存身份已变化，未发布内容。",
                            ));
                        }
                        if replace {
                            fs::rename(&path, &destination).await?;
                        } else {
                            fs::hard_link(&path, &destination).await.map_err(|e| {
                                CoreError::new(
                                    if e.kind() == std::io::ErrorKind::AlreadyExists {
                                        "conflict"
                                    } else {
                                        "atomic_save_unavailable"
                                    },
                                    e.to_string(),
                                )
                            })?;
                            fs::remove_file(&path).await?;
                        }
                        let published = fs::symlink_metadata(&destination)
                            .await
                            .map_err(|e| CoreError::new("result_unknown", e.to_string()))?;
                        if !published.is_file()
                            || published.file_type().is_symlink()
                            || published.len() != held.len()
                            || published.modified()? != held.modified()?
                        {
                            return Err(CoreError::new(
                                "result_unknown",
                                "提交后暂存身份无法确认，请核对目标。",
                            ));
                        }
                    }
                    Ok(if replace {
                        "atomicRename"
                    } else {
                        "atomicNoReplace"
                    }
                    .into())
                }
                _ => Err(CoreError::new("unsupported", "不支持的本机执行原语。")),
            }
        } else {
            let path = remote_path(path)?;
            if matches!(
                path.as_str(),
                "/" | "/sdcard"
                    | "/storage"
                    | "/storage/emulated"
                    | "/storage/emulated/0"
                    | "/mnt/sdcard"
                    | "/storage/self/primary"
            ) && action == "delete"
            {
                return Err(CoreError::new("invalid_path", "不能删除存储根目录。"));
            }
            let client = self.client(device).await?;
            if matches!(action, "rename" | "commit") {
                crate::remote_helper::remote_rename_with_options(
                    &client,
                    &path,
                    &remote_path(destination)?,
                    replace,
                    options(token),
                )
                .await?;
                return Ok(if replace {
                    "atomicRename"
                } else {
                    "atomicRenameNoReplace"
                }
                .into());
            }
            let script = match action {
                "mkdir" => format!("mkdir -- {}", quote(&path)?),
                "delete" => format!("rm -rf -- {}", quote(&path)?),
                _ => return Err(CoreError::new("unsupported", "不支持的设备文件原语。")),
            };
            let result = crate::remote_fs::command(&client, &script, 64 * 1024, options(token))
                .await
                .map_err(|error| {
                    CoreError::new("result_unknown", format!("文件变更回执不可确认：{error}"))
                })?;
            if result.exit_code != Some(0) {
                return Err(CoreError::new(
                    "remote_failed",
                    String::from_utf8_lossy(&result.stderr),
                ));
            }
            Ok("verified".into())
        }
    }
    /// Copy into an unpublished part. The Dart owner persists finalizing before a separate commit.
    #[allow(clippy::too_many_arguments)]
    pub async fn execute_file_copy(
        &self,
        device: &str,
        source: &str,
        temporary: &str,
        push: bool,
        expected: FileStamp,
        token: CancellationToken,
        progress: Arc<AtomicU64>,
    ) -> CoreResult<u64> {
        cancelled(&token)?;
        if expected.mode & 0o170000 != 0o100000 {
            return Err(CoreError::new("not_a_file", "不能传输链接或特殊文件。"));
        }
        let before = self
            .execute_file_stat(device, source, push, false, token.clone())
            .await?;
        if before != expected {
            return Err(CoreError::new("source_changed", "源文件与选择快照不同。"));
        }
        let client = self.client(device).await?;
        let mut sync = client.sync(options(token.clone())).await?;
        let mut completed_file = None;
        let count = if push {
            let temporary = remote_path(temporary)?;
            let mut input = ProgressIo {
                inner: fs::File::open(local(source)?).await?,
                progress,
            };
            sync.push(
                &RemotePath::new(&temporary)?,
                &mut input,
                0o644,
                expected.modified_seconds.clamp(0, u32::MAX as i64) as u32,
                expected.size,
            )
            .await?
        } else {
            let temp = local(temporary)?;
            let mut output = ProgressIo {
                inner: fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&temp)
                    .await?,
                progress,
            };
            let count = sync
                .pull(
                    &RemotePath::new(remote_path(source)?)?,
                    &mut output,
                    expected.size,
                )
                .await?;
            output.inner.sync_all().await?;
            completed_file = Some(output.inner.into_std().await);
            count
        };
        drop(sync);
        cancelled(&token)?;
        if count != expected.size
            || self
                .execute_file_stat(device, source, push, false, token)
                .await?
                != expected
        {
            return Err(CoreError::new(
                "source_changed",
                "传输期间源文件变化；暂存内容保留，未发布目标。",
            ));
        }
        if let Some(file) = completed_file {
            let mut parts = self.file_parts.lock().expect("file parts");
            if parts.len() >= 128 {
                return Err(CoreError::new("busy", "暂存句柄达到上限。"));
            }
            parts.insert(temporary.into(), (device.into(), Arc::new(file)));
        }
        Ok(count)
    }
}
fn fact(name: Vec<u8>, result: CoreResult<FileStamp>) -> EntryFact {
    match result {
        Ok(stamp) => EntryFact {
            name,
            stamp: Some(stamp),
            error_code: None,
            error_message: None,
        },
        Err(e) => EntryFact {
            name,
            stamp: None,
            error_code: Some(e.code),
            error_message: Some(e.message),
        },
    }
}
struct ProgressIo<T> {
    inner: T,
    progress: Arc<AtomicU64>,
}
impl<T: AsyncRead + Unpin> AsyncRead for ProgressIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let result = Pin::new(&mut self.inner).poll_read(cx, buf);
        if matches!(&result, Poll::Ready(Ok(()))) {
            self.progress
                .fetch_add((buf.filled().len() - before) as u64, Ordering::Relaxed);
        }
        result
    }
}
impl<T: AsyncWrite + Unpin> AsyncWrite for ProgressIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let result = Pin::new(&mut self.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(n)) = &result {
            self.progress.fetch_add(*n as u64, Ordering::Relaxed);
        }
        result
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}
