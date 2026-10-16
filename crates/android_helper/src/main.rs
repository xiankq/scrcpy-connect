//! A deliberately narrow shell-UID filesystem helper: no APK, daemon or root.
//! CLI arguments stay OS byte strings; no path is parsed as shell source.
use std::{ffi::CString, io::Write, os::unix::ffi::OsStrExt};

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
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error()
            .raw_os_error()
            .unwrap_or(libc::EIO))
    }
}

fn main() {
    let args = std::env::args_os().collect::<Vec<_>>();
    let operation = args.get(1).and_then(|v| v.to_str()).unwrap_or("");
    let result = if args.len() == 4 && matches!(operation, "rename-no-replace" | "publish-replace")
    {
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
    let (ok, errno) = match result {
        Ok(()) => (true, 0),
        Err(errno) => (false, errno),
    };
    let _ = writeln!(
        std::io::stdout().lock(),
        "{{\"protocol\":1,\"ok\":{ok},\"errno\":{errno}}}"
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_nul_before_entering_the_kernel() {
        assert_eq!(rename(b"a\0b", b"c", false), Err(libc::EINVAL));
    }
}
