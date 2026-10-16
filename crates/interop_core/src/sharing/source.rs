use crate::{CoreError, CoreResult};
use serde::Deserialize;
use std::{
    fs::{File, OpenOptions},
    io::{Seek, SeekFrom},
    path::PathBuf,
};

/// `fd` is borrowed from the platform until this request returns. Rust duplicates
/// it immediately. The platform closes its original lease in its own finally.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Source {
    pub name: String,
    #[serde(default)]
    pub fd: Option<i32>,
    #[serde(default)]
    pub path: Option<PathBuf>,
    #[serde(default)]
    pub offset: u64,
    pub declared_length: Option<u64>,
}
pub(super) struct OpenSource {
    pub name: String,
    pub file: File,
    pub length: Option<u64>,
    pub before: Option<(u64, Option<std::time::SystemTime>)>,
}
impl Source {
    pub(super) fn open(self, max_bytes: u64) -> CoreResult<OpenSource> {
        if self.name.len() > 4096
            || self
                .path
                .as_ref()
                .is_some_and(|path| path.as_os_str().len() > 16384)
        {
            return Err(CoreError::new("invalid_source", "已授权来源元数据过长。"));
        }
        if self.declared_length.is_some_and(|n| n > max_bytes) {
            return Err(CoreError::new(
                "share_byte_limit",
                "单个分享来源超过容量上限。",
            ));
        }
        let mut file = match (self.fd, self.path) {
            (Some(fd), None) => duplicate_fd(fd)?,
            (None, Some(path)) => {
                if !path.is_absolute() || !std::fs::symlink_metadata(&path)?.is_file() {
                    return Err(CoreError::new(
                        "invalid_path",
                        "已授权文件来源必须是绝对路径的普通文件。",
                    ));
                }
                let mut options = OpenOptions::new();
                options.read(true);
                #[cfg(any(target_os = "android", target_os = "linux"))]
                {
                    use std::os::unix::fs::OpenOptionsExt;
                    options.custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK);
                }
                let opened = options.open(path)?;
                if !opened.metadata()?.is_file() {
                    return Err(CoreError::new("source_changed", "已授权来源类型已改变。"));
                }
                opened
            }
            _ => {
                return Err(CoreError::new(
                    "invalid_source",
                    "来源必须提供一个已授权 FD 或本机路径。",
                ));
            }
        };
        let metadata = file.metadata()?;
        let before = metadata
            .is_file()
            .then(|| (metadata.len(), metadata.modified().ok()));
        if metadata.is_file() {
            if self.offset > metadata.len() {
                return Err(CoreError::new("invalid_source", "来源偏移超过文件长度。"));
            }
            file.seek(SeekFrom::Start(self.offset))?;
            if self
                .declared_length
                .is_some_and(|len| len > metadata.len() - self.offset)
            {
                return Err(CoreError::new("source_changed", "来源范围超出文件长度。"));
            }
        } else if self.offset != 0 {
            return Err(CoreError::new(
                "unsupported_source_offset",
                "流式来源无法定位到非零偏移。",
            ));
        }
        let name = self
            .name
            .rsplit(['/', '\\'])
            .next()
            .unwrap_or("")
            .replace('\0', "_")
            .chars()
            .take(180)
            .collect::<String>();
        let name = if name.is_empty() || name == "." || name == ".." {
            "共享文件".into()
        } else {
            name
        };
        Ok(OpenSource {
            name,
            file,
            length: self.declared_length,
            before,
        })
    }
}

#[cfg(any(target_os = "android", target_os = "linux"))]
fn duplicate_fd(fd: i32) -> CoreResult<File> {
    use std::os::fd::FromRawFd;
    if fd < 0 {
        return Err(CoreError::new(
            "invalid_source_fd",
            "已授权文件描述符无效。",
        ));
    }
    // fcntl validates the borrowed integer; only its successful new descriptor
    // becomes an OwnedFd/File. Never close the caller's original descriptor.
    let cloned = unsafe { libc::fcntl(fd, libc::F_DUPFD_CLOEXEC, 0) };
    if cloned < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    let file = unsafe { File::from_raw_fd(cloned) };
    let flags = unsafe { libc::fcntl(cloned, libc::F_GETFL) };
    if flags < 0 || flags & libc::O_ACCMODE == libc::O_WRONLY {
        return Err(CoreError::new("invalid_source_fd", "来源描述符不可读取。"));
    }
    if unsafe { libc::fcntl(cloned, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(file)
}
#[cfg(not(any(target_os = "android", target_os = "linux")))]
fn duplicate_fd(_: i32) -> CoreResult<File> {
    Err(CoreError::new(
        "unsupported_source_fd",
        "此平台请交接已授权本机路径。",
    ))
}

pub(super) fn space_available(path: &std::path::Path) -> Option<u64> {
    #[cfg(any(target_os = "android", target_os = "linux"))]
    {
        use std::os::unix::ffi::OsStrExt;
        let path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
        let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
        if unsafe { libc::statvfs(path.as_ptr(), stat.as_mut_ptr()) } != 0 {
            return None;
        }
        let stat = unsafe { stat.assume_init() };
        Some(((stat.f_bavail as u128) * (stat.f_frsize as u128)).min(u64::MAX as u128) as u64)
    }
    #[cfg(not(any(target_os = "android", target_os = "linux")))]
    {
        let _ = path;
        None
    }
}
