//! A deliberately narrow shell-UID filesystem helper: no APK, daemon or root.
//! CLI arguments stay OS byte strings; no path is parsed as shell source.
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
    // A trailing slash otherwise makes the kernel follow the last named link,
    // even with AT_SYMLINK_NOFOLLOW/O_NOFOLLOW. Explicit `alias/.` remains a
    // caller-authorized way to traverse a known shared-storage root alias.
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
    // Bionic's 32-bit API 21 time_t is narrower than the JSON integer. Widen
    // with sign extension; never narrow the 64-bit platforms' timestamps.
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
        // fdopendir owns fd from here. Metadata stays relative to this opened
        // directory even if its pathname is renamed or replaced by a symlink.
        let mut directory = Self { handle, fd: -1 };
        directory.fd = unsafe { libc::dirfd(handle) };
        if directory.fd < 0 {
            return Err(errno());
        }
        Ok(directory)
    }

    fn next(&mut self) -> Result<Option<&CStr>, i32> {
        // readdir leaves errno unchanged at EOF. fstatat failures from an
        // earlier child must not be mistaken for an enumeration failure.
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
        // libc owns this NUL-terminated name until the next readdir call.
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
    // Both operations are one kernel rename. In particular, never unlink the
    // source after a link/copy: it may then name a different concurrently-created inode.
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
    // Deliberately return no path text. This machine result works even with
    // non-UTF8 names, old shell transports without exit status and private paths.
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
