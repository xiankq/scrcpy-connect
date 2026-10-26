//! 无写入及范围句柄的本机容量快照；容量不代表后续写入预留。
use super::{LocalFileError, LocalFileErrorCode};
use std::{io, path::Path};

type Result<T> = std::result::Result<T, LocalFileError>;

fn error(code: LocalFileErrorCode, message: impl Into<String>) -> LocalFileError {
    LocalFileError {
        code,
        message: message.into(),
        bytes_copied: 0,
        partial_destination_possible: false,
    }
}

fn io_error(cause: io::Error) -> LocalFileError {
    error(
        if cause.kind() == io::ErrorKind::NotFound {
            LocalFileErrorCode::NotFound
        } else {
            LocalFileErrorCode::Io
        },
        cause.to_string(),
    )
}

pub(super) async fn free_bytes(path: String) -> Result<u64> {
    tokio::task::spawn_blocking(move || {
        let directory = Path::new(&path);
        if path.contains('\0') || !directory.is_absolute() {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "容量查询仅接受不含空字符的绝对目录路径。",
            ));
        }
        if !std::fs::metadata(directory).map_err(io_error)?.is_dir() {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "容量查询目标必须是现存目录。",
            ));
        }
        available_bytes(directory)
    })
    .await
    .map_err(|cause| error(LocalFileErrorCode::Io, format!("容量查询任务异常：{cause}")))?
}

#[cfg(unix)]
fn available_bytes(directory: &Path) -> Result<u64> {
    use std::{ffi::CString, mem::MaybeUninit, os::unix::ffi::OsStrExt};

    let path = CString::new(directory.as_os_str().as_bytes())
        .map_err(|_| error(LocalFileErrorCode::InvalidArgument, "路径包含空字符。"))?;
    let mut stats = MaybeUninit::<libc::statvfs>::uninit();
    // 路径以 NUL 结尾，输出仅在系统调用成功后读取。
    if unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) } != 0 {
        return Err(io_error(io::Error::last_os_error()));
    }
    let stats = unsafe { stats.assume_init() };
    let bytes = u128::from(stats.f_bavail) * u128::from(stats.f_frsize);
    u64::try_from(bytes)
        .map_err(|_| error(LocalFileErrorCode::Io, "调用方可用容量超出 64 位范围。"))
}

#[cfg(windows)]
fn available_bytes(directory: &Path) -> Result<u64> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

    let mut path: Vec<u16> = directory.as_os_str().encode_wide().collect();
    // UNC 目录要求尾部分隔符；一般目录同样接受该形式。
    if !matches!(path.last(), Some(47 | 92)) {
        path.push(92);
    }
    path.push(0);
    let mut available = 0;
    // 只读取 caller available，保留配额限制；其余两个输出不请求。
    if unsafe {
        GetDiskFreeSpaceExW(
            path.as_ptr(),
            &mut available,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    } == 0
    {
        return Err(io_error(io::Error::last_os_error()));
    }
    Ok(available)
}

#[cfg(not(any(unix, windows)))]
fn available_bytes(_: &Path) -> Result<u64> {
    Err(error(
        LocalFileErrorCode::Unsupported,
        "当前宿主不支持本机可用容量查询。",
    ))
}
