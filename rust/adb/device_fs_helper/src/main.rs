//! 用途受限的 shell UID 文件系统助手，不安装 APK、daemon，也不使用 root。CLI 参数始终为系统字节串，不将路径解析为 shell 程序。
use std::{
    ffi::{CStr, CString, OsString},
    io::{self, Read, Write},
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    os::unix::ffi::OsStrExt,
};

fn errno() -> i32 {
    std::io::Error::last_os_error()
        .raw_os_error()
        .unwrap_or(libc::EIO)
}

struct Metadata {
    mode: u32,
    size: u64,
    modified_seconds: i64,
    identity: String,
    device: u64,
    inode: u64,
}

fn nofollow_path(mut path: &[u8]) -> &[u8] {
    // 即使带 AT_SYMLINK_NOFOLLOW/O_NOFOLLOW，末尾斜杠也会使内核跟随最后的链接；显式 alias/. 仍可用于调用方已授权的已知共享存储根别名。
    while path.len() > 1 && path.ends_with(b"/") {
        path = &path[..path.len() - 1];
    }
    path
}

fn metadata_at(directory: i32, path: &CStr, nofollow: bool) -> Result<Metadata, i32> {
    let mut metadata = std::mem::MaybeUninit::<libc::stat64>::uninit();
    let flags = if nofollow {
        libc::AT_SYMLINK_NOFOLLOW
    } else {
        0
    };
    if unsafe { libc::fstatat64(directory, path.as_ptr(), metadata.as_mut_ptr(), flags) } != 0 {
        return Err(errno());
    }
    metadata_value(unsafe { metadata.assume_init() })
}

fn metadata_value(metadata: libc::stat64) -> Result<Metadata, i32> {
    let size = u64::try_from(metadata.st_size).map_err(|_| libc::EOVERFLOW)?;
    // Bionic 的 32 位 API 21 time_t 比 JSON 整数窄；扩展时保留符号，64 位平台时间戳绝不窄化。
    #[allow(clippy::unnecessary_cast)]
    let modified_seconds = metadata.st_mtime as i64;
    // libc stat64 的设备/inode 宽度随目标 ABI 变化；统一扩展为 u64，宿主已为 u64。
    #[allow(clippy::unnecessary_cast)]
    let (device, inode) = (metadata.st_dev as u64, metadata.st_ino as u64);
    Ok(Metadata {
        mode: metadata.st_mode,
        size,
        modified_seconds,
        device,
        inode,
        identity: format!(
            "{:x}-{:x}-{:x}-{:x}",
            metadata.st_dev, metadata.st_ino, metadata.st_ctime, metadata.st_ctime_nsec
        ),
    })
}

fn metadata(path: &[u8], nofollow: bool) -> Result<Metadata, i32> {
    let path = CString::new(if nofollow { nofollow_path(path) } else { path })
        .map_err(|_| libc::EINVAL)?;
    metadata_at(libc::AT_FDCWD, &path, nofollow)
}

fn write_status(output: &mut impl Write, result: Result<(), i32>) -> io::Result<()> {
    let (ok, errno) = match result {
        Ok(()) => (true, 0),
        Err(errno) => (false, errno),
    };
    writeln!(output, "{{\"protocol\":1,\"ok\":{ok},\"errno\":{errno}}}")
}

struct Directory {
    handle: *mut libc::DIR,
    fd: i32,
}

impl Directory {
    fn open(path: &[u8]) -> Result<Self, i32> {
        let path = CString::new(nofollow_path(path)).map_err(|_| libc::EINVAL)?;
        let fd = unsafe {
            libc::open(
                path.as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            )
        };
        if fd < 0 {
            return Err(errno());
        }
        let handle = unsafe { libc::fdopendir(fd) };
        if handle.is_null() {
            let error = errno();
            unsafe { libc::close(fd) };
            return Err(error);
        }
        // 从此由 fdopendir 拥有 fd；即使原路径改名或被符号链接替换，元数据查询仍相对于已打开目录。
        let mut directory = Self { handle, fd: -1 };
        directory.fd = unsafe { libc::dirfd(handle) };
        if directory.fd < 0 {
            return Err(errno());
        }
        Ok(directory)
    }

    fn next(&mut self) -> Result<Option<&CStr>, i32> {
        // readdir 在 EOF 时不改变 errno；不能把之前子项 fstatat 的失败误认为目录枚举失败。
        unsafe {
            #[cfg(target_os = "android")]
            {
                *libc::__errno() = 0;
            }
            #[cfg(not(target_os = "android"))]
            {
                *libc::__errno_location() = 0;
            }
        }
        let entry = unsafe { libc::readdir(self.handle) };
        if entry.is_null() {
            let error = std::io::Error::last_os_error()
                .raw_os_error()
                .unwrap_or(libc::EIO);
            return if error == 0 { Ok(None) } else { Err(error) };
        }
        // NUL 结尾的名称由 libc 拥有，直到下一次 readdir 调用。
        Ok(Some(unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) }))
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        unsafe { libc::closedir(self.handle) };
    }
}

fn list(path: &[u8], limit: usize, output: &mut impl Write) -> io::Result<()> {
    let mut directory = match Directory::open(path) {
        Ok(directory) => directory,
        Err(error) => return write_status(output, Err(error)),
    };
    let fd = directory.fd;
    write!(output, "{{\"protocol\":1,\"entries\":[")?;
    let mut count = 0;
    let mut truncated = false;
    let mut error = 0;
    loop {
        let name = match directory.next() {
            Ok(Some(name)) => name,
            Ok(None) => break,
            Err(errno) => {
                error = errno;
                break;
            }
        };
        if matches!(name.to_bytes(), b"." | b"..") {
            continue;
        }
        if count == limit {
            truncated = true;
            break;
        }
        if count != 0 {
            output.write_all(b",")?;
        }
        output.write_all(b"{\"nameHex\":\"")?;
        const HEX: &[u8; 16] = b"0123456789abcdef";
        let mut hex = [0; 512];
        for (index, byte) in name.to_bytes().iter().enumerate() {
            hex[index * 2] = HEX[(byte >> 4) as usize];
            hex[index * 2 + 1] = HEX[(byte & 15) as usize];
        }
        output.write_all(&hex[..name.to_bytes().len() * 2])?;
        output.write_all(b"\",")?;
        let (metadata, errno) = match metadata_at(fd, name, true) {
            Ok(metadata) => (metadata, 0),
            Err(errno) => (
                Metadata {
                    mode: 0,
                    size: 0,
                    modified_seconds: 0,
                    identity: String::new(),
                    device: 0,
                    inode: 0,
                },
                errno,
            ),
        };
        write!(
            output,
            "\"mode\":{},\"size\":{},\"modifiedSeconds\":{},\"identity\":\"{}\",\"errno\":{errno}}}",
            metadata.mode, metadata.size, metadata.modified_seconds, metadata.identity
        )?;
        count += 1;
    }
    writeln!(
        output,
        "],\"truncated\":{truncated},\"ok\":{},\"errno\":{error}}}",
        error == 0
    )
}

fn rename_at(
    source_fd: i32,
    source: &CStr,
    target_fd: i32,
    target: &CStr,
    replace: bool,
) -> Result<(), i32> {
    let result = unsafe {
        if replace {
            libc::renameat(source_fd, source.as_ptr(), target_fd, target.as_ptr()) as libc::c_long
        } else {
            libc::syscall(
                libc::SYS_renameat2,
                source_fd,
                source.as_ptr(),
                target_fd,
                target.as_ptr(),
                1u32,
            )
        }
    };
    if result == 0 { Ok(()) } else { Err(errno()) }
}

fn rename(source: &[u8], target: &[u8], replace: bool) -> Result<(), i32> {
    let source = CString::new(source).map_err(|_| libc::EINVAL)?;
    let target = CString::new(target).map_err(|_| libc::EINVAL)?;
    rename_at(libc::AT_FDCWD, &source, libc::AT_FDCWD, &target, replace)
}

fn open_at(fd: i32, name: &CStr, flags: i32) -> Result<OwnedFd, i32> {
    let opened = unsafe { libc::openat(fd, name.as_ptr(), flags | libc::O_CLOEXEC) };
    if opened < 0 {
        Err(errno())
    } else {
        Ok(unsafe { OwnedFd::from_raw_fd(opened) })
    }
}

struct MutationError {
    errno: i32,
    recovery: Option<Vec<u8>>,
}
impl From<i32> for MutationError {
    fn from(errno: i32) -> Self {
        Self {
            errno,
            recovery: None,
        }
    }
}

// Every recursive lookup is relative to an opened directory. A symlink inserted
// while descending is unlinked itself, never followed into an unrelated tree.
fn remove_at(parent: i32, name: &CStr) -> Result<(), i32> {
    let opened = open_at(
        parent,
        name,
        libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW,
    );
    match opened {
        Ok(fd) => {
            let raw = std::os::fd::IntoRawFd::into_raw_fd(fd);
            let handle = unsafe { libc::fdopendir(raw) };
            if handle.is_null() {
                let error = errno();
                unsafe {
                    libc::close(raw);
                }
                return Err(error);
            }
            let mut directory = Directory {
                handle,
                fd: unsafe { libc::dirfd(handle) },
            };
            while let Some(child) = directory.next()? {
                if matches!(child.to_bytes(), b"." | b"..") {
                    continue;
                }
                let child = child.to_owned();
                remove_at(directory.fd, &child)?;
            }
            if unsafe { libc::unlinkat(parent, name.as_ptr(), libc::AT_REMOVEDIR) } != 0 {
                return Err(errno());
            }
            Ok(())
        }
        Err(libc::ENOTDIR | libc::ELOOP) => {
            if unsafe { libc::unlinkat(parent, name.as_ptr(), 0) } == 0 {
                Ok(())
            } else {
                Err(errno())
            }
        }
        Err(error) => Err(error),
    }
}

fn guarded_mutation(
    source: &[u8],
    target: Option<&[u8]>,
    expected: &str,
    after_pin: impl FnOnce(),
    after_claim: impl FnOnce(),
) -> Result<(), MutationError> {
    let path = std::path::Path::new(std::ffi::OsStr::from_bytes(nofollow_path(source)));
    let name =
        CString::new(path.file_name().ok_or(libc::EINVAL)?.as_bytes()).map_err(|_| libc::EINVAL)?;
    let parent_path = CString::new(path.parent().ok_or(libc::EINVAL)?.as_os_str().as_bytes())
        .map_err(|_| libc::EINVAL)?;
    let parent = open_at(
        libc::AT_FDCWD,
        &parent_path,
        libc::O_PATH | libc::O_DIRECTORY,
    )?;
    let parent_fd = parent.as_raw_fd();
    // Bind the destination parent too; a source ancestor rename must not
    // redirect the final publication into a newly substituted directory.
    let destination = target
        .map(|target| {
            let path = std::path::Path::new(std::ffi::OsStr::from_bytes(nofollow_path(target)));
            let name = CString::new(path.file_name().ok_or(libc::EINVAL)?.as_bytes())
                .map_err(|_| libc::EINVAL)?;
            let directory = CString::new(path.parent().ok_or(libc::EINVAL)?.as_os_str().as_bytes())
                .map_err(|_| libc::EINVAL)?;
            let fd = if directory == parent_path {
                parent
                    .try_clone()
                    .map_err(|error| error.raw_os_error().unwrap_or(libc::EIO))?
            } else {
                open_at(libc::AT_FDCWD, &directory, libc::O_PATH | libc::O_DIRECTORY)?
            };
            Ok::<_, i32>((fd, name))
        })
        .transpose()?;
    let pinned = open_at(parent_fd, &name, libc::O_PATH | libc::O_NOFOLLOW)?;
    let mut stat = std::mem::MaybeUninit::<libc::stat64>::uninit();
    if unsafe { libc::fstat64(pinned.as_raw_fd(), stat.as_mut_ptr()) } != 0 {
        return Err(errno().into());
    }
    let selected = metadata_value(unsafe { stat.assume_init() })?;
    if expected.is_empty()
        || selected.identity != expected
        || !matches!(selected.mode & 0o170000, 0o100000 | 0o040000)
    {
        return Err(libc::ESTALE.into());
    }
    after_pin();
    let mut random = [0; 16];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut file| file.read_exact(&mut random))
        .map_err(|error| error.raw_os_error().unwrap_or(libc::EIO))?;
    let directory_name = CString::new(format!(
        ".interop-mutation-{}",
        random
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    ))
    .unwrap();
    if unsafe { libc::mkdirat(parent_fd, directory_name.as_ptr(), 0o700) } != 0 {
        return Err(errno().into());
    }
    let quarantine = match open_at(
        parent_fd,
        &directory_name,
        libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW,
    ) {
        Ok(fd) => fd,
        Err(error) => {
            unsafe {
                libc::unlinkat(parent_fd, directory_name.as_ptr(), libc::AT_REMOVEDIR);
            }
            return Err(error.into());
        }
    };
    let quarantine_fd = quarantine.as_raw_fd();
    let item = c"item";
    if let Err(error) = rename_at(parent_fd, &name, quarantine_fd, item, false) {
        unsafe {
            libc::unlinkat(parent_fd, directory_name.as_ptr(), libc::AT_REMOVEDIR);
        }
        return Err(error.into());
    }
    let result = (|| {
        // rename changes ctime itself; the pinned FD prevents inode reuse, so
        // compare dev/ino after claiming, rather than comparing the old ctime.
        after_claim();
        let claimed = metadata_at(quarantine_fd, item, true)?;
        if (claimed.device, claimed.inode) != (selected.device, selected.inode) {
            return Err(libc::ESTALE);
        }
        if let Some((directory, target)) = &destination {
            rename_at(quarantine_fd, item, directory.as_raw_fd(), target, false)
        } else {
            remove_at(quarantine_fd, item)
        }
    })();
    if let Err(error) = result {
        // Never replace an object created at the original name after claim.
        if rename_at(quarantine_fd, item, parent_fd, &name, false).is_err() {
            let mut recovery = std::fs::read_link(format!("/proc/self/fd/{parent_fd}"))
                .map(|path| path.as_os_str().as_bytes().to_vec())
                .unwrap_or_else(|_| parent_path.as_bytes().to_vec());
            recovery.push(b'/');
            recovery.extend_from_slice(directory_name.as_bytes());
            recovery.extend_from_slice(b"/item");
            return Err(MutationError {
                errno: error,
                recovery: Some(recovery),
            });
        }
        unsafe {
            libc::unlinkat(parent_fd, directory_name.as_ptr(), libc::AT_REMOVEDIR);
        }
        return Err(error.into());
    }
    unsafe {
        libc::unlinkat(parent_fd, directory_name.as_ptr(), libc::AT_REMOVEDIR);
    }
    Ok(())
}

fn write_mutation_status(
    output: &mut impl Write,
    result: Result<(), MutationError>,
) -> io::Result<()> {
    match result {
        Err(MutationError {
            errno,
            recovery: Some(path),
        }) => {
            let hex = path
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>();
            writeln!(
                output,
                "{{\"protocol\":1,\"ok\":false,\"errno\":{errno},\"recoveryPathHex\":\"{hex}\"}}"
            )
        }
        result => write_status(output, result.map_err(|error| error.errno)),
    }
}

fn execute(args: &[OsString], output: &mut impl Write) -> io::Result<()> {
    if args.len() != 4 {
        return write_status(output, Err(libc::EINVAL));
    }
    let operation = args.get(1).and_then(|v| v.to_str()).unwrap_or("");
    if matches!(operation, "stat" | "lstat") {
        return match metadata(args[2].as_bytes(), operation == "lstat") {
            Ok(metadata) => writeln!(
                output,
                "{{\"protocol\":1,\"ok\":true,\"errno\":0,\"mode\":{},\"size\":{},\"modifiedSeconds\":{},\"identity\":\"{}\"}}",
                metadata.mode, metadata.size, metadata.modified_seconds, metadata.identity
            ),
            Err(errno) => write_status(output, Err(errno)),
        };
    }
    if operation == "list" {
        let limit = args[3]
            .to_str()
            .and_then(|limit| limit.parse::<usize>().ok());
        return match limit.filter(|limit| (1..=10_000).contains(limit)) {
            Some(limit) => list(args[2].as_bytes(), limit, output),
            None => write_status(output, Err(libc::EINVAL)),
        };
    }
    if let Some((kind, expected)) = operation.split_once(':')
        && matches!(kind, "rename-expected" | "delete-expected")
    {
        let target = (kind == "rename-expected").then(|| args[3].as_bytes());
        return write_mutation_status(
            output,
            guarded_mutation(args[2].as_bytes(), target, expected, || {}, || {}),
        );
    }
    let result = if matches!(operation, "rename-no-replace" | "publish-replace") {
        rename(
            args[2].as_bytes(),
            args[3].as_bytes(),
            operation == "publish-replace",
        )
    } else {
        Err(libc::EINVAL)
    };
    // 刻意不返回路径文本；机器结果兼容非 UTF-8 名称、无退出状态的旧 shell 传输以及私有路径。
    write_status(output, result)
}

fn main() {
    let args = std::env::args_os().collect::<Vec<_>>();
    let _ = execute(&args, &mut std::io::stdout().lock());
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_nul_and_binds_mutations_across_replacement_and_recovery() {
        use std::{fs, os::unix::fs::symlink};
        assert_eq!(rename(b"a\0b", b"c", false), Err(libc::EINVAL));
        let root = std::env::temp_dir().join(format!("interop-claim-{}", std::process::id()));
        fs::create_dir(&root).unwrap();
        let source = root.join("source");
        let target = root.join("target");
        let outside = root.join("outside");
        fs::create_dir(&outside).unwrap();
        fs::write(outside.join("safe"), b"untouched").unwrap();
        let bytes = |path: &std::path::Path| path.as_os_str().as_bytes().to_vec();
        // Replace after the selected inode has been pinned, before claim.
        // Neither operation may delete/publish the replacement (even a directory).
        for pin_first in [true, false] {
            for delete in [true, false] {
                for replacement in [0, 1, 2] {
                    fs::write(&source, b"selected").unwrap();
                    let expected = metadata(&bytes(&source), true).unwrap().identity;
                    let moved = root.join("selected-moved");
                    let replace = || {
                        fs::rename(&source, &moved).unwrap();
                        match replacement {
                            0 => {
                                let selected_time =
                                    fs::metadata(&moved).unwrap().modified().unwrap();
                                fs::write(&source, b"replaced").unwrap();
                                fs::File::open(&source)
                                    .unwrap()
                                    .set_times(fs::FileTimes::new().set_modified(selected_time))
                                    .unwrap();
                            }
                            1 => {
                                fs::create_dir(&source).unwrap();
                                fs::write(source.join("safe"), b"replacement").unwrap();
                            }
                            _ => symlink(&outside, &source).unwrap(),
                        }
                    };
                    if !pin_first {
                        replace();
                    }
                    let result = guarded_mutation(
                        &bytes(&source),
                        (!delete).then(|| bytes(&target)).as_deref(),
                        &expected,
                        || {
                            if pin_first {
                                replace();
                            }
                        },
                        || {
                            if replacement == 1 && delete {
                                fs::write(&source, b"new source").unwrap();
                            }
                        },
                    );
                    let error = result.err().unwrap();
                    assert_eq!(error.errno, libc::ESTALE);
                    assert_eq!(fs::read(&moved).unwrap(), b"selected");
                    assert!(!target.exists());
                    if replacement == 1 && delete && pin_first {
                        let recovery = std::path::Path::new(std::ffi::OsStr::from_bytes(
                            error.recovery.as_ref().unwrap(),
                        ));
                        assert_eq!(fs::read(recovery.join("safe")).unwrap(), b"replacement");
                        assert_eq!(fs::read(&source).unwrap(), b"new source");
                        fs::remove_file(&source).unwrap();
                    } else if replacement == 1 {
                        assert_eq!(fs::read(source.join("safe")).unwrap(), b"replacement");
                        fs::remove_dir_all(&source).unwrap();
                    } else {
                        fs::remove_file(&source).unwrap();
                    }
                    fs::remove_file(moved).unwrap();
                }
            }
        }
        // A target conflict restores without overwriting any existing path.
        // If a writer occupies the original name, preserve the selected object
        // under the recovery path and expose that location in the receipt.
        for occupied in [false, true] {
            fs::write(&source, b"selected").unwrap();
            fs::write(&target, b"target").unwrap();
            let expected = metadata(&bytes(&source), true).unwrap().identity;
            let error = guarded_mutation(
                &bytes(&source),
                Some(&bytes(&target)),
                &expected,
                || {},
                || {
                    if occupied {
                        fs::write(&source, b"new source").unwrap();
                    }
                },
            )
            .err()
            .unwrap();
            assert_eq!(error.errno, libc::EEXIST);
            assert_eq!(fs::read(&target).unwrap(), b"target");
            if occupied {
                let recovery = error.recovery.as_ref().unwrap();
                assert_eq!(
                    fs::read(std::ffi::OsStr::from_bytes(recovery)).unwrap(),
                    b"selected"
                );
                assert_eq!(fs::read(&source).unwrap(), b"new source");
                let mut receipt = Vec::new();
                write_mutation_status(&mut receipt, Err(error)).unwrap();
                assert!(
                    String::from_utf8(receipt)
                        .unwrap()
                        .contains("recoveryPathHex")
                );
            } else {
                assert!(error.recovery.is_none());
                assert_eq!(fs::read(&source).unwrap(), b"selected");
            }
            fs::remove_file(&source).unwrap();
            fs::remove_file(&target).unwrap();
        }
        // Claiming the selected directory leaves a new same-name tree intact;
        // nested links never authorize deleting their external target.
        fs::create_dir(&source).unwrap();
        fs::create_dir(source.join("child")).unwrap();
        fs::write(source.join("child/file"), b"selected").unwrap();
        symlink(&outside, source.join("link")).unwrap();
        let expected = metadata(&bytes(&source), true).unwrap().identity;
        let selected_root = fs::File::open(&source).unwrap();
        assert!(
            guarded_mutation(
                &bytes(&source),
                None,
                &expected,
                || {},
                || {
                    let claimed = std::path::PathBuf::from(format!(
                        "/proc/self/fd/{}",
                        selected_root.as_raw_fd()
                    ));
                    fs::rename(claimed.join("child"), root.join("child-moved")).unwrap();
                    symlink(&outside, claimed.join("child")).unwrap();
                    fs::create_dir(&source).unwrap();
                    fs::write(source.join("safe"), b"new tree").unwrap();
                }
            )
            .is_ok()
        );
        assert_eq!(fs::read(source.join("safe")).unwrap(), b"new tree");
        assert_eq!(fs::read(outside.join("safe")).unwrap(), b"untouched");
        assert_eq!(
            fs::read(root.join("child-moved/file")).unwrap(),
            b"selected"
        );
        // Parent-path replacement cannot redirect source or destination.
        let parent = root.join("parent");
        fs::create_dir(&parent).unwrap();
        let original = parent.join("file");
        let destination = parent.join("renamed");
        fs::write(&original, b"selected").unwrap();
        let expected = metadata(&bytes(&original), true).unwrap().identity;
        let moved = root.join("parent-moved");
        assert!(
            guarded_mutation(
                &bytes(&original),
                Some(&bytes(&destination)),
                &expected,
                || {
                    fs::rename(&parent, &moved).unwrap();
                    symlink(&outside, &parent).unwrap();
                },
                || {}
            )
            .is_ok()
        );
        assert_eq!(fs::read(moved.join("renamed")).unwrap(), b"selected");
        assert!(!outside.join("renamed").exists());
        fs::remove_dir_all(&root).unwrap();
    }
}
