//! 用途受限的 shell UID 文件系统助手，不安装 APK、daemon，也不使用 root。CLI 参数始终为系统字节串，不将路径解析为 shell 程序。
use std::{
    ffi::{CStr, CString, OsString},
    io::{self, Write},
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
    let metadata = unsafe { metadata.assume_init() };
    let size = u64::try_from(metadata.st_size).map_err(|_| libc::EOVERFLOW)?;
    // Bionic 的 32 位 API 21 time_t 比 JSON 整数窄；扩展时保留符号，64 位平台时间戳绝不窄化。
    #[allow(clippy::unnecessary_cast)]
    let modified_seconds = metadata.st_mtime as i64;
    Ok(Metadata {
        mode: metadata.st_mode,
        size,
        modified_seconds,
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
                },
                errno,
            ),
        };
        write!(
            output,
            "\"mode\":{},\"size\":{},\"modifiedSeconds\":{},\"errno\":{errno}}}",
            metadata.mode, metadata.size, metadata.modified_seconds
        )?;
        count += 1;
    }
    writeln!(
        output,
        "],\"truncated\":{truncated},\"ok\":{},\"errno\":{error}}}",
        error == 0
    )
}

fn rename(source: &[u8], target: &[u8], replace: bool) -> Result<(), i32> {
    let source = CString::new(source).map_err(|_| libc::EINVAL)?;
    let target = CString::new(target).map_err(|_| libc::EINVAL)?;
    // 两个操作均为单次内核 rename；尤其不能 link/copy 后再 unlink 源路径，因为该路径可能已指向并发创建的其他 inode。
    let result = unsafe {
        if replace {
            libc::renameat(
                libc::AT_FDCWD,
                source.as_ptr(),
                libc::AT_FDCWD,
                target.as_ptr(),
            ) as libc::c_long
        } else {
            libc::syscall(
                libc::SYS_renameat2,
                libc::AT_FDCWD,
                source.as_ptr(),
                libc::AT_FDCWD,
                target.as_ptr(),
                1u32,
            )
        }
    };
    if result == 0 { Ok(()) } else { Err(errno()) }
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
                "{{\"protocol\":1,\"ok\":true,\"errno\":0,\"mode\":{},\"size\":{},\"modifiedSeconds\":{}}}",
                metadata.mode, metadata.size, metadata.modified_seconds
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
    fn rejects_nul_before_entering_the_kernel() {
        assert_eq!(rename(b"a\0b", b"c", false), Err(libc::EINVAL));
    }
}
