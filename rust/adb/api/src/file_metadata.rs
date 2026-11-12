//! 原始路径与元数据事实，不保存遍历、冲突策略或设备记录。
use crate::{
    api::{AdbFileExecutionEntry, AdbFileExecutionStamp},
    file_system::{FileError, FileResult, HelperResources},
};
use interop_adb::{
    Client, OperationOptions,
    sync::{FileStat, RemotePath},
};
use serde_json::Value;
use std::path::PathBuf;

pub(crate) fn path(bytes: &[u8]) -> FileResult<PathBuf> {
    if bytes.is_empty() || bytes.contains(&0) {
        return Err(FileError::new("invalid_path", "文件路径为空或包含空字节。"));
    }
    #[cfg(unix)]
    let path = {
        use std::os::unix::ffi::OsStringExt;
        PathBuf::from(std::ffi::OsString::from_vec(bytes.to_vec()))
    };
    #[cfg(not(unix))]
    let path = PathBuf::from(
        std::str::from_utf8(bytes)
            .map_err(|_| FileError::new("invalid_path", "宿主路径不是有效 Unicode。"))?,
    );
    if !path.is_absolute() {
        return Err(FileError::new("invalid_path", "文件路径必须为绝对路径。"));
    }
    Ok(path)
}
pub(crate) fn remote_path(bytes: &[u8]) -> FileResult<()> {
    if bytes.first() != Some(&b'/') || bytes.len() > 4095 || bytes.contains(&0) {
        return Err(FileError::new(
            "invalid_path",
            "设备路径必须为不含空字节的绝对路径。",
        ));
    }
    Ok(())
}
pub(crate) fn alias(path: &[u8], follow: bool) -> Vec<u8> {
    if follow && matches!(path, b"/sdcard" | b"/mnt/sdcard" | b"/storage/self/primary") {
        [path, b"/."].concat()
    } else {
        path.to_vec()
    }
}
pub(crate) fn stamp(stat: FileStat) -> AdbFileExecutionStamp {
    AdbFileExecutionStamp {
        identity: None,
        mode: stat.mode,
        size: stat.size,
        modified_seconds: stat.modified_seconds,
        modified_nanos: 0,
        nanosecond_precision: false,
    }
}
pub(crate) async fn local_stat(path_bytes: &[u8]) -> FileResult<AdbFileExecutionStamp> {
    let metadata = tokio::fs::symlink_metadata(path(path_bytes)?).await?;
    local_stamp(&metadata)
}
pub(crate) fn local_stamp(metadata: &std::fs::Metadata) -> FileResult<AdbFileExecutionStamp> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        Ok(AdbFileExecutionStamp {
            identity: Some(format!(
                "{:x}-{:x}-{:x}-{:x}",
                metadata.dev(),
                metadata.ino(),
                metadata.ctime(),
                metadata.ctime_nsec()
            )),
            mode: metadata.mode(),
            size: metadata.len(),
            modified_seconds: metadata.mtime(),
            modified_nanos: metadata
                .mtime_nsec()
                .try_into()
                .map_err(|_| FileError::new("invalid_timestamp", "宿主时间戳无效。"))?,
            nanosecond_precision: true,
        })
    }
    #[cfg(not(unix))]
    {
        let (seconds, nanos) = match metadata.modified()?.duration_since(std::time::UNIX_EPOCH) {
            Ok(time) => (
                i64::try_from(time.as_secs())
                    .map_err(|_| FileError::new("invalid_timestamp", "宿主时间戳超限。"))?,
                time.subsec_nanos(),
            ),
            Err(error) => {
                let time = error.duration();
                let seconds = i64::try_from(time.as_secs())
                    .map_err(|_| FileError::new("invalid_timestamp", "宿主时间戳超限。"))?;
                if time.subsec_nanos() == 0 {
                    (-seconds, 0)
                } else {
                    (-seconds - 1, 1_000_000_000 - time.subsec_nanos())
                }
            }
        };
        let mode = if metadata.file_type().is_symlink() {
            0o120000
        } else if metadata.is_dir() {
            0o040000
        } else if metadata.is_file() {
            0o100000
        } else {
            0
        };
        Ok(AdbFileExecutionStamp {
            identity: None,
            mode,
            size: metadata.len(),
            modified_seconds: seconds,
            modified_nanos: nanos,
            nanosecond_precision: true,
        })
    }
}
pub(crate) async fn stat(
    client: &Client,
    helpers: &HelperResources,
    path: &[u8],
    follow_alias: bool,
    options: OperationOptions,
) -> FileResult<AdbFileExecutionStamp> {
    remote_path(path)?;
    let resolved = alias(path, follow_alias);
    if client.info().features.contains("stat_v2")
        && let Ok(path) = RemotePath::new(&resolved)
    {
        let mut sync = client.sync(options.clone()).await?;
        match sync.lstat(&path).await {
            Ok(value) => return Ok(stamp(value)),
            Err(
                interop_adb::Error::RemoteErrno {
                    errno: 1 | 13 | 38 | 95,
                    ..
                }
                | interop_adb::Error::Remote(_)
                | interop_adb::Error::Unsupported(_),
            ) => {}
            Err(error) => return Err(error.into()),
        }
    }
    from_value(
        &crate::file_helper::remote_metadata(client, helpers, &resolved, "lstat", 1, options)
            .await?,
    )
}
fn invalid() -> FileError {
    FileError::new("invalid_metadata", "设备文件元数据格式无效。")
}
fn from_value(value: &Value) -> FileResult<AdbFileExecutionStamp> {
    Ok(AdbFileExecutionStamp {
        identity: value["identity"].as_str().map(str::to_owned),
        mode: value["mode"]
            .as_u64()
            .and_then(|v| v.try_into().ok())
            .ok_or_else(invalid)?,
        size: value["size"].as_u64().ok_or_else(invalid)?,
        modified_seconds: value["modifiedSeconds"].as_i64().ok_or_else(invalid)?,
        modified_nanos: 0,
        nanosecond_precision: false,
    })
}
fn fact(name: Vec<u8>, result: FileResult<AdbFileExecutionStamp>) -> AdbFileExecutionEntry {
    match result {
        Ok(stamp) => AdbFileExecutionEntry {
            name,
            stamp: Some(stamp),
            error_code: None,
            error_message: None,
            errno: None,
        },
        Err(error) => AdbFileExecutionEntry {
            name,
            stamp: None,
            errno: error.errno(),
            error_code: Some(error.code),
            error_message: Some(error.message),
        },
    }
}
fn name(value: &Value) -> FileResult<Vec<u8>> {
    let text = value.as_str().ok_or_else(invalid)?;
    if text.is_empty() || text.len() > 510 || !text.len().is_multiple_of(2) {
        return Err(invalid());
    }
    let mut bytes = Vec::with_capacity(text.len() / 2);
    for pair in text.as_bytes().as_chunks::<2>().0 {
        let digit = |v| match v {
            b'0'..=b'9' => Some(v - b'0'),
            b'a'..=b'f' => Some(v - b'a' + 10),
            _ => None,
        };
        bytes.push(digit(pair[0]).ok_or_else(invalid)? * 16 + digit(pair[1]).ok_or_else(invalid)?);
    }
    if matches!(bytes.as_slice(), b"." | b"..") || bytes.contains(&0) || bytes.contains(&b'/') {
        return Err(invalid());
    }
    Ok(bytes)
}
fn listing(reply: &Value, limit: usize) -> FileResult<(Vec<AdbFileExecutionEntry>, bool)> {
    let values = reply["entries"]
        .as_array()
        .filter(|entries| entries.len() <= limit)
        .ok_or_else(invalid)?;
    let truncated = reply["truncated"].as_bool().ok_or_else(invalid)?;
    let mut entries = Vec::with_capacity(values.len());
    for value in values {
        let errno = value["errno"]
            .as_u64()
            .filter(|v| *v < 4096)
            .ok_or_else(invalid)? as u32;
        entries.push(fact(
            name(&value["nameHex"])?,
            if errno == 0 {
                from_value(value)
            } else {
                Err(interop_adb::Error::RemoteErrno {
                    operation: "metadata",
                    errno,
                }
                .into())
            },
        ));
    }
    Ok((entries, truncated))
}
pub(crate) async fn list(
    client: &Client,
    helpers: &HelperResources,
    path: &[u8],
    local: bool,
    limit: usize,
    options: OperationOptions,
) -> FileResult<(Vec<AdbFileExecutionEntry>, bool)> {
    if !(1..=10_000).contains(&limit) {
        return Err(FileError::new(
            "invalid_argument",
            "目录上限必须为 1 至 10000。",
        ));
    }
    if local {
        return local_list(path, limit, &options.cancellation).await;
    }
    remote_path(path)?;
    let root = stat(client, helpers, path, true, options.clone()).await?;
    if root.mode & 0o170000 != 0o040000 {
        return Err(FileError::new("not_directory", "设备路径不是可浏览目录。"));
    }
    let resolved = alias(path, true);
    // 原生助手保留逐项 errno；ls_v2 的空 DONE 不能单独证明目录可读。
    let reply = crate::file_helper::remote_metadata(
        client,
        helpers,
        &resolved,
        "list",
        limit,
        options.clone(),
    )
    .await?;
    let result = listing(&reply, limit)?;
    if stat(client, helpers, path, true, options).await? != root {
        return Err(FileError::new("source_changed", "读取期间设备目录已变化。"));
    }
    Ok(result)
}

/// 无需 ADB 连接的本机 lstat/原始名称枚举，与远端执行复用相同事实类型。
pub(crate) async fn local_list(
    path: &[u8],
    limit: usize,
    cancellation: &interop_adb::CancellationToken,
) -> FileResult<(Vec<AdbFileExecutionEntry>, bool)> {
    if !(1..=10_000).contains(&limit) {
        return Err(FileError::new(
            "invalid_argument",
            "目录上限必须为 1 至 10000。",
        ));
    }
    let before = local_stat(path).await?;
    if before.mode & 0o170000 != 0o040000 {
        return Err(FileError::new("not_directory", "本机路径不是普通目录。"));
    }
    let mut directory = tokio::fs::read_dir(self::path(path)?).await?;
    let mut entries = Vec::new();
    let mut truncated = false;
    while let Some(entry) = directory.next_entry().await? {
        if cancellation.is_cancelled() {
            return Err(interop_adb::Error::Cancelled.into());
        }
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
        #[cfg(unix)]
        let entry_path = {
            use std::os::unix::ffi::OsStrExt;
            entry.path().as_os_str().as_bytes().to_vec()
        };
        #[cfg(not(unix))]
        let entry_path = entry.path().to_string_lossy().as_bytes().to_vec();
        entries.push(fact(name, local_stat(&entry_path).await));
    }
    if local_stat(path).await? != before {
        return Err(FileError::new("source_changed", "读取期间本机目录已变化。"));
    }
    Ok((entries, truncated))
}
