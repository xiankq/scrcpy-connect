//! Local no-clobber publication without hard-link permissions.
use crate::{CoreError, CoreResult};
use std::{
    ffi::{CStr, CString},
    fs::{File, Metadata, OpenOptions},
    io,
    os::{
        fd::{AsRawFd, FromRawFd, RawFd},
        unix::{
            ffi::OsStrExt,
            fs::{MetadataExt, OpenOptionsExt},
        },
    },
    path::Path,
};

pub(crate) fn rename_noreplace(
    source_parent: RawFd,
    source: &CStr,
    target_parent: RawFd,
    target: &CStr,
) -> io::Result<()> {
    // Bionic's renameat2 symbol requires API 30. syscall is available on older
    // Android versions; libc supplies each architecture's syscall number.
    let result = unsafe {
        libc::syscall(
            libc::SYS_renameat2,
            source_parent,
            source.as_ptr(),
            target_parent,
            target.as_ptr(),
            libc::RENAME_NOREPLACE as libc::c_uint,
        )
    };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn same(a: &Metadata, b: &Metadata) -> bool {
    a.is_file()
        && b.is_file()
        && a.dev() == b.dev()
        && a.ino() == b.ino()
        && a.len() == b.len()
        && a.mtime() == b.mtime()
        && a.mtime_nsec() == b.mtime_nsec()
}

fn location(path: &Path) -> io::Result<(File, CString)> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(parent)?;
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::from(io::ErrorKind::InvalidInput))?;
    let name = CString::new(name.as_bytes()).map_err(|_| io::ErrorKind::InvalidInput)?;
    Ok((directory, name))
}

fn open_at(parent: &File, name: &CStr) -> io::Result<File> {
    let raw = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
        )
    };
    if raw < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(unsafe { File::from_raw_fd(raw) })
    }
}

/// The caller retains the completed, synced temporary file until publication.
pub(crate) fn publish_file(source: &File, from: &Path, to: &Path) -> CoreResult<()> {
    publish_file_mode(source, from, to, false)
}

pub(crate) fn publish_file_replace(source: &File, from: &Path, to: &Path) -> CoreResult<()> {
    publish_file_mode(source, from, to, true)
}

fn publish_file_mode(source: &File, from: &Path, to: &Path, replace: bool) -> CoreResult<()> {
    let (source_parent, source_name) = location(from)?;
    let (target_parent, target_name) = location(to)?;
    let before = source.metadata()?;
    let named = open_at(&source_parent, &source_name)?;
    if !same(&before, &named.metadata()?) {
        return Err(CoreError::new(
            "source_changed",
            "暂存文件在提交前变化，未发布替换内容。",
        ));
    }
    let renamed = if replace {
        let result = unsafe {
            libc::renameat(
                source_parent.as_raw_fd(),
                source_name.as_ptr(),
                target_parent.as_raw_fd(),
                target_name.as_ptr(),
            )
        };
        if result < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    } else {
        rename_noreplace(
            source_parent.as_raw_fd(),
            &source_name,
            target_parent.as_raw_fd(),
            &target_name,
        )
    };
    renamed.map_err(|error| {
        if error.kind() == io::ErrorKind::AlreadyExists {
            CoreError::new(
                "conflict",
                "保存时出现同名目标，原文件未被覆盖；临时文件保留。",
            )
        } else {
            CoreError::new(
                "atomic_save_unavailable",
                format!("保存位置不支持原子防覆盖提交；临时文件保留。{error}"),
            )
        }
    })?;
    // After rename, failure means the destination may already be published.
    // Never retry, remove it, or turn this into a normal pre-publication error.
    let verify = || -> io::Result<bool> {
        let published = open_at(&target_parent, &target_name)?;
        if !same(&before, &published.metadata()?) || !same(&before, &source.metadata()?) {
            return Ok(false);
        }
        target_parent.sync_all()?;
        source_parent.sync_all()?;
        Ok(true)
    };
    match verify() {
        Ok(true) => Ok(()),
        _ => Err(CoreError::new(
            "result_unknown",
            "提交后暂存身份或目录同步无法确认，请核对目标；不会自动重试。",
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replace_checks_retained_inode_and_preserves_existing_target_on_replacement() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("part");
        let target = root.path().join("target");
        std::fs::write(&source, b"verified").unwrap();
        std::fs::write(&target, b"existing").unwrap();
        let held = File::open(&source).unwrap();
        std::fs::rename(&source, root.path().join("retained")).unwrap();
        std::fs::write(&source, b"replaced").unwrap();
        assert_eq!(
            publish_file_replace(&held, &source, &target)
                .unwrap_err()
                .code,
            "source_changed"
        );
        assert_eq!(std::fs::read(&target).unwrap(), b"existing");
        assert_eq!(std::fs::read(&source).unwrap(), b"replaced");
        let current = File::open(&source).unwrap();
        publish_file_replace(&current, &source, &target).unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), b"replaced");
        assert!(!source.exists());
    }
}
