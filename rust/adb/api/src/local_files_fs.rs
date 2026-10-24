//! 以已打开的目录和文件描述符核验对象；不保存产品记录或推断用户提交策略。
use super::{Result, error};
use crate::api::*;
use std::{
    ffi::{CStr, CString, OsString},
    fs::{File, OpenOptions},
    io,
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            ffi::{OsStrExt, OsStringExt},
            fs::OpenOptionsExt,
        },
    },
    path::{Component, Path, PathBuf},
    time::Instant,
};
use tokio_util::sync::CancellationToken;

pub struct Root {
    path: PathBuf,
    file: File,
}
pub struct FileScope {
    roots: Vec<Root>,
}
pub struct Location {
    parent: File,
    name: CString,
}
pub struct Resources {
    source: File,
    target: File,
    source_location: Option<Location>,
    target_location: Option<Location>,
    source_before: LocalFileIdentity,
    target_before: LocalFileIdentity,
    request: LocalFileCopyRequest,
    pub publication: Publication,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Publication {
    Unpublished,
    Published,
    Unknown,
}
fn io_error(e: io::Error) -> LocalFileError {
    error(
        if e.kind() == io::ErrorKind::NotFound {
            LocalFileErrorCode::NotFound
        } else {
            LocalFileErrorCode::Io
        },
        e.to_string(),
    )
}
fn c(bytes: &[u8]) -> Result<CString> {
    CString::new(bytes).map_err(|_| error(LocalFileErrorCode::InvalidArgument, "路径包含空字符。"))
}
fn owned(raw: i32) -> Result<File> {
    if raw < 0 {
        Err(io_error(io::Error::last_os_error()))
    } else {
        Ok(unsafe { File::from_raw_fd(raw) })
    }
}
fn checked_path(bytes: &[u8]) -> Result<PathBuf> {
    let path = PathBuf::from(OsString::from_vec(bytes.to_vec()));
    if !path.is_absolute()
        || bytes.contains(&0)
        || bytes.split(|b| *b == b'/').any(|p| p == b"." || p == b"..")
    {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "仅接受不含跳转分段的绝对路径。",
        ));
    }
    Ok(path)
}
fn open_directory(parent: &File, name: &CStr) -> Result<File> {
    owned(unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            libc::O_RDONLY
                | libc::O_DIRECTORY
                | libc::O_CLOEXEC
                | libc::O_NOFOLLOW
                | libc::O_LARGEFILE,
        )
    })
}
fn open_at(location: &Location, flags: i32) -> Result<File> {
    owned(unsafe {
        libc::openat(
            location.parent.as_raw_fd(),
            location.name.as_ptr(),
            flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK | libc::O_LARGEFILE,
            0o600,
        )
    })
}
// 显式使用大文件结构；time_t 仍随 ABI 改变，统一无损扩展到公开的 i64。
// 旧 32 位 time_t 的可观测时间范围不会因此扩大，此入口不承诺额外的 Y2038 支持。
#[allow(clippy::useless_conversion)]
fn identity(s: &libc::stat64) -> LocalFileIdentity {
    let mode = u64::from(s.st_mode) & u64::from(libc::S_IFMT);
    LocalFileIdentity {
        device: s.st_dev,
        inode: s.st_ino,
        size: s.st_size.max(0) as u64,
        modified_seconds: i64::from(s.st_mtime),
        modified_nanos: s.st_mtime_nsec as u32,
        kind: if mode == u64::from(libc::S_IFREG) {
            LocalFileKind::File
        } else if mode == u64::from(libc::S_IFDIR) {
            LocalFileKind::Directory
        } else if mode == u64::from(libc::S_IFLNK) {
            LocalFileKind::Symlink
        } else {
            LocalFileKind::Other
        },
    }
}
fn stat_fd(file: &File) -> Result<LocalFileIdentity> {
    let mut stat = std::mem::MaybeUninit::uninit();
    if unsafe { libc::fstat64(file.as_raw_fd(), stat.as_mut_ptr()) } < 0 {
        return Err(io_error(io::Error::last_os_error()));
    }
    Ok(identity(&unsafe { stat.assume_init() }))
}
fn stat_at(location: &Location) -> Result<LocalFileIdentity> {
    let mut stat = std::mem::MaybeUninit::uninit();
    if unsafe {
        libc::fstatat64(
            location.parent.as_raw_fd(),
            location.name.as_ptr(),
            stat.as_mut_ptr(),
            libc::AT_SYMLINK_NOFOLLOW,
        )
    } < 0
    {
        return Err(io_error(io::Error::last_os_error()));
    }
    Ok(identity(&unsafe { stat.assume_init() }))
}
fn sync(file: &File) -> Result<()> {
    file.sync_all().map_err(io_error)
}
fn same_object(a: &LocalFileIdentity, b: &LocalFileIdentity) -> bool {
    a.device == b.device && a.inode == b.inode && a.kind == b.kind
}
pub fn duplicate(raw: i32, read: bool) -> Result<File> {
    if raw < 0 {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "借入描述符无效。",
        ));
    }
    let file = owned(unsafe { libc::fcntl(raw, libc::F_DUPFD_CLOEXEC, 3) })?;
    let flags = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) };
    if flags < 0 {
        return Err(io_error(io::Error::last_os_error()));
    }
    let access = flags & libc::O_ACCMODE;
    if (read && access == libc::O_WRONLY) || (!read && access == libc::O_RDONLY) {
        return Err(error(
            LocalFileErrorCode::InvalidArgument,
            "借入描述符访问模式不匹配。",
        ));
    }
    // 复制 FD 与原 FD 共享打开文件描述；非阻塞模式也是该能力交接的显式要求。
    if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(io_error(io::Error::last_os_error()));
    }
    Ok(file)
}
impl FileScope {
    pub fn open(paths: Vec<Vec<u8>>) -> Result<Self> {
        if paths.is_empty() {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "至少需要一个已存在的能力根目录。",
            ));
        }
        let mut roots = Vec::new();
        for bytes in paths {
            let path = checked_path(&bytes)?;
            // 只解析调用方明确授予的根，允许宿主系统目录别名。后续请求始终从
            // 本次打开的真实目录 FD 出发，不再次解析根别名或 scope 内的链接。
            let resolved = std::fs::canonicalize(&path).map_err(io_error)?;
            if resolved == Path::new("/") {
                return Err(error(
                    LocalFileErrorCode::InvalidArgument,
                    "不能授予整个文件系统根目录。",
                ));
            }
            let mut file = OpenOptions::new()
                .read(true)
                .custom_flags(
                    libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_LARGEFILE,
                )
                .open("/")
                .map_err(io_error)?;
            for component in resolved.components() {
                if let Component::Normal(name) = component {
                    file = open_directory(&file, &c(name.as_bytes())?)?;
                }
            }
            roots.push(Root { path, file });
        }
        Ok(Self { roots })
    }
    fn location(&self, bytes: &[u8]) -> Result<Location> {
        let path = checked_path(bytes)?;
        let (root, relative) = self
            .roots
            .iter()
            .filter_map(|r| {
                path.strip_prefix(&r.path)
                    .ok()
                    .filter(|p| !p.as_os_str().is_empty())
                    .map(|p| (r, p))
            })
            .max_by_key(|(r, _)| r.path.as_os_str().len())
            .ok_or_else(|| {
                error(
                    LocalFileErrorCode::InvalidArgument,
                    "路径不属于能力根，或正在访问根目录本身。",
                )
            })?;
        let mut parent = root.file.try_clone().map_err(io_error)?;
        let mut parts = relative.components().peekable();
        while let Some(part) = parts.next() {
            let Component::Normal(name) = part else {
                return Err(error(LocalFileErrorCode::InvalidArgument, "路径分段无效。"));
            };
            let name = c(name.as_bytes())?;
            if parts.peek().is_none() {
                return Ok(Location { parent, name });
            }
            parent = open_directory(&parent, &name)?;
        }
        Err(error(
            LocalFileErrorCode::InvalidArgument,
            "路径没有文件名。",
        ))
    }
    pub fn stat(&self, path: &[u8]) -> Result<LocalFileStat> {
        let location = self.location(path)?;
        let id = stat_at(&location)?;
        let mut space = std::mem::MaybeUninit::uninit();
        let free = if unsafe { libc::fstatvfs64(location.parent.as_raw_fd(), space.as_mut_ptr()) }
            == 0
        {
            let s = unsafe { space.assume_init() };
            Some((u128::from(s.f_bavail) * u128::from(s.f_frsize)).min(u128::from(u64::MAX)) as u64)
        } else {
            None
        };
        Ok(LocalFileStat {
            identity: id,
            free_bytes: free,
        })
    }
    pub fn list(
        &self,
        path: &[u8],
        maximum: u32,
        token: &CancellationToken,
    ) -> Result<LocalFileList> {
        let location = self.location(path)?;
        let directory = open_at(&location, libc::O_RDONLY | libc::O_DIRECTORY)?;
        let before = stat_fd(&directory)?;
        let raw = unsafe { libc::fcntl(directory.as_raw_fd(), libc::F_DUPFD_CLOEXEC, 3) };
        if raw < 0 {
            return Err(io_error(io::Error::last_os_error()));
        }
        let stream = unsafe { libc::fdopendir(raw) };
        if stream.is_null() {
            unsafe { libc::close(raw) };
            return Err(io_error(io::Error::last_os_error()));
        }
        struct Directory(*mut libc::DIR);
        impl Drop for Directory {
            fn drop(&mut self) {
                unsafe { libc::closedir(self.0) };
            }
        }
        let stream = Directory(stream);
        let mut entries = Vec::new();
        loop {
            if token.is_cancelled() {
                return Err(error(LocalFileErrorCode::Cancelled, "列举已取消。"));
            }
            // 使用宽 inode 目录入口并清除 errno，区分 EOF、窄结构溢出与实际读取失败。
            #[cfg(target_os = "linux")]
            unsafe {
                *libc::__errno_location() = 0;
            }
            #[cfg(target_os = "android")]
            unsafe {
                *libc::__errno() = 0;
            }
            let entry = unsafe { libc::readdir64(stream.0) };
            if entry.is_null() {
                let e = io::Error::last_os_error();
                if e.raw_os_error() != Some(0) {
                    return Err(io_error(e));
                }
                break;
            }
            let name = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) };
            if matches!(name.to_bytes(), b"." | b"..") {
                continue;
            }
            if entries.len() >= maximum as usize {
                return Err(error(
                    LocalFileErrorCode::EntryLimit,
                    "目录超过调用方允许的条目数。",
                ));
            }
            let child = Location {
                parent: directory.try_clone().map_err(io_error)?,
                name: name.to_owned(),
            };
            entries.push(LocalFileEntry {
                name: name.to_bytes().to_vec(),
                identity: stat_at(&child)?,
            });
        }
        if stat_fd(&directory)? != before || stat_at(&location)? != before {
            return Err(error(
                LocalFileErrorCode::SourceChanged,
                "列举期间目录身份发生变化。",
            ));
        }
        Ok(LocalFileList {
            identity: before,
            entries,
        })
    }
    pub fn mkdir(&self, path: &[u8], exclusive: bool) -> Result<()> {
        let location = self.location(path)?;
        if unsafe { libc::mkdirat(location.parent.as_raw_fd(), location.name.as_ptr(), 0o700) } < 0
        {
            let e = io::Error::last_os_error();
            if !exclusive && e.kind() == io::ErrorKind::AlreadyExists {
                let _ = open_at(&location, libc::O_RDONLY | libc::O_DIRECTORY)?;
                return Ok(());
            }
            return Err(if e.kind() == io::ErrorKind::AlreadyExists {
                error(LocalFileErrorCode::Conflict, "目标已存在。")
            } else {
                io_error(e)
            });
        }
        sync(&location.parent).map_err(|_| {
            error(
                LocalFileErrorCode::ResultUnknown,
                "目录已创建，但同步结果无法确认。",
            )
        })
    }
    pub fn remove(&self, path: &[u8], expected: &LocalFileIdentity) -> Result<()> {
        let location = self.location(path)?;
        if stat_at(&location)? != *expected {
            return Err(error(
                LocalFileErrorCode::TargetChanged,
                "路径身份已经变化，未删除替换内容。",
            ));
        }
        // 私有能力根内的调用方必须串行处理同一路径；不追随链接，也不递归删除。
        let flags = if expected.kind == LocalFileKind::Directory {
            libc::AT_REMOVEDIR
        } else {
            0
        };
        if unsafe { libc::unlinkat(location.parent.as_raw_fd(), location.name.as_ptr(), flags) } < 0
        {
            return Err(io_error(io::Error::last_os_error()));
        }
        sync(&location.parent).map_err(|_| {
            error(
                LocalFileErrorCode::ResultUnknown,
                "删除已执行，但目录同步结果无法确认。",
            )
        })
    }
    pub fn resources(
        &self,
        request: LocalFileCopyRequest,
        source: Option<File>,
        target: Option<File>,
    ) -> Result<Resources> {
        let source_location = request
            .source_path
            .as_deref()
            .map(|p| self.location(p))
            .transpose()?;
        let source = match source {
            Some(f) => f,
            None => open_at(source_location.as_ref().unwrap(), libc::O_RDONLY)?,
        };
        let source_before = stat_fd(&source)?;
        if source_location.is_some() && source_before.kind != LocalFileKind::File {
            return Err(error(
                LocalFileErrorCode::SourceChanged,
                "路径来源不是普通文件。",
            ));
        }
        if request
            .expected_source
            .as_ref()
            .is_some_and(|id| id != &source_before)
        {
            return Err(error(
                LocalFileErrorCode::SourceChanged,
                "来源身份与调用方预期不同。",
            ));
        }
        if request.source_offset > i64::MAX as u64 {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "来源偏移超出平台范围。",
            ));
        }
        if source_before.kind == LocalFileKind::File {
            if request.source_offset > source_before.size
                || request
                    .length
                    .is_some_and(|n| n > source_before.size - request.source_offset)
            {
                return Err(error(
                    LocalFileErrorCode::SourceChanged,
                    "来源范围超出当前文件长度。",
                ));
            }
        } else if request.source_offset != 0 {
            return Err(error(
                LocalFileErrorCode::InvalidArgument,
                "流式来源不支持非零偏移。",
            ));
        }
        let target_location = request
            .target_path
            .as_deref()
            .map(|p| self.location(p))
            .transpose()?;
        let target = match target {
            Some(f) => f,
            None => open_at(
                target_location.as_ref().unwrap(),
                libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
            )?,
        };
        let target_before = stat_fd(&target)?;
        let resources = Resources {
            source,
            target,
            source_location,
            target_location,
            source_before,
            target_before,
            request,
            publication: Publication::Unpublished,
        };
        // 写目标需要可定位、可同步的普通文件；不把管道提供方误报为对象已变化。
        // 借入描述符仅复制持有，此能力既不截断非空文件，也不向流式目标写入。
        if resources.target_before.kind != LocalFileKind::File {
            let _ = resources.cleanup();
            return Err(error(
                LocalFileErrorCode::Unsupported,
                "写目标仅支持空普通文件，不支持管道或其他流式描述符。",
            ));
        }
        if resources.target_before.size != 0 {
            let _ = resources.cleanup();
            return Err(error(
                LocalFileErrorCode::TargetChanged,
                "目标文件已经非空，未截断或写入。",
            ));
        }
        Ok(resources)
    }
}
impl Resources {
    pub fn cleanup(&self) -> Result<()> {
        if self.publication != Publication::Unpublished {
            return Ok(());
        }
        let Some(location) = &self.target_location else {
            return Ok(());
        };
        match stat_at(location) {
            Ok(current) if same_object(&current, &self.target_before) => {}
            Ok(_) => return Ok(()),
            Err(e) if e.code == LocalFileErrorCode::NotFound => return Ok(()),
            Err(e) => return Err(e),
        }
        if unsafe { libc::unlinkat(location.parent.as_raw_fd(), location.name.as_ptr(), 0) } < 0 {
            return Err(io_error(io::Error::last_os_error()));
        }
        sync(&location.parent)
    }
    pub fn copy(&mut self, token: &CancellationToken) -> Result<LocalFileCopyResult> {
        let deadline =
            Instant::now() + std::time::Duration::from_millis(self.request.timeout_ms.into());
        let mut bytes = 0u64;
        let result = (|| {
            if stat_fd(&self.source)? != self.source_before {
                return Err(error(
                    LocalFileErrorCode::SourceChanged,
                    "来源在执行前变化。",
                ));
            }
            if stat_fd(&self.target)? != self.target_before {
                return Err(error(
                    LocalFileErrorCode::TargetChanged,
                    "目标在执行前变化。",
                ));
            }
            if unsafe { libc::lseek(self.target.as_raw_fd(), 0, libc::SEEK_SET) } < 0 {
                return Err(io_error(io::Error::last_os_error()));
            }
            let mut buffer = [0u8; 65536];
            loop {
                check(token, deadline)?;
                if self.request.length == Some(bytes) {
                    break;
                }
                wait(&self.source, libc::POLLIN, token, deadline)?;
                let maximum = self.request.length.map_or(buffer.len(), |n| {
                    (n - bytes).min(buffer.len() as u64) as usize
                });
                let count = if self.source_before.kind == LocalFileKind::File {
                    let offset = self
                        .request
                        .source_offset
                        .checked_add(bytes)
                        .and_then(|n| i64::try_from(n).ok())
                        .ok_or_else(|| {
                            error(
                                LocalFileErrorCode::InvalidArgument,
                                "来源偏移超出平台范围。",
                            )
                        })?;
                    // dup 共享原 FD 的文件游标；普通文件必须按本请求偏移读取，
                    // 既不能干扰另一复制请求，也不能移动平台仍持有的原描述符。
                    unsafe {
                        libc::pread64(
                            self.source.as_raw_fd(),
                            buffer.as_mut_ptr().cast(),
                            maximum,
                            offset,
                        )
                    }
                } else {
                    unsafe {
                        libc::read(self.source.as_raw_fd(), buffer.as_mut_ptr().cast(), maximum)
                    }
                };
                if count < 0 {
                    let e = io::Error::last_os_error();
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) {
                        continue;
                    }
                    return Err(io_error(e));
                }
                if count == 0 {
                    if self.request.length.is_some_and(|n| n != bytes) {
                        return Err(error(
                            LocalFileErrorCode::SourceChanged,
                            "来源比声明范围短。",
                        ));
                    }
                    break;
                }
                if count as u64 > self.request.max_bytes.saturating_sub(bytes) {
                    return Err(error(
                        LocalFileErrorCode::ByteLimit,
                        "复制超过调用方的字节上限。",
                    ));
                }
                let mut written = 0;
                while written < count as usize {
                    wait(&self.target, libc::POLLOUT, token, deadline)?;
                    let count = unsafe {
                        libc::write(
                            self.target.as_raw_fd(),
                            buffer[written..count as usize].as_ptr().cast(),
                            count as usize - written,
                        )
                    };
                    if count < 0 {
                        let e = io::Error::last_os_error();
                        if matches!(
                            e.kind(),
                            io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                        ) {
                            continue;
                        }
                        return Err(io_error(e));
                    }
                    if count == 0 {
                        return Err(error(LocalFileErrorCode::Io, "目标没有接受数据。"));
                    }
                    written += count as usize;
                    bytes += count as u64;
                }
            }
            check(token, deadline)?;
            sync(&self.target)?;
            if self.source_before.kind == LocalFileKind::File
                && stat_fd(&self.source)? != self.source_before
            {
                return Err(error(
                    LocalFileErrorCode::SourceChanged,
                    "复制期间来源发生变化。",
                ));
            }
            if let Some(location) = &self.source_location
                && stat_at(location)? != self.source_before
            {
                return Err(error(
                    LocalFileErrorCode::SourceChanged,
                    "来源路径已被替换。",
                ));
            }
            if let Some(location) = &self.target_location
                && stat_at(location)? != stat_fd(&self.target)?
            {
                return Err(error(
                    LocalFileErrorCode::TargetChanged,
                    "复制目标路径已被替换。",
                ));
            }
            Ok(LocalFileCopyResult {
                bytes,
                identity: stat_fd(&self.target)?,
                source_identity: self.source_before.clone(),
            })
        })();
        result.map_err(|mut e| {
            e.bytes_copied = bytes;
            e.partial_destination_possible = self.target_location.is_none() && bytes > 0;
            e
        })
    }
    pub fn commit(
        &mut self,
        scope: &FileScope,
        destination: &[u8],
        expected: &LocalFileIdentity,
    ) -> Result<LocalFileIdentity> {
        if self.publication != Publication::Unpublished {
            return Err(error(
                LocalFileErrorCode::ResultUnknown,
                "该提交权已使用，不能重放。",
            ));
        }
        let source = self.target_location.as_ref().ok_or_else(|| {
            error(
                LocalFileErrorCode::InvalidArgument,
                "外部描述符没有可提交的本机路径。",
            )
        })?;
        let before = stat_fd(&self.target)?;
        if before != *expected || stat_at(source)? != before {
            return Err(error(
                LocalFileErrorCode::SourceChanged,
                "待提交文件身份已经变化。",
            ));
        }
        let target = scope.location(destination)?;
        sync(&self.target)?;
        if unsafe {
            libc::syscall(
                libc::SYS_renameat2,
                source.parent.as_raw_fd(),
                source.name.as_ptr(),
                target.parent.as_raw_fd(),
                target.name.as_ptr(),
                libc::RENAME_NOREPLACE as libc::c_uint,
            )
        } < 0
        {
            let e = io::Error::last_os_error();
            return Err(if e.kind() == io::ErrorKind::AlreadyExists {
                error(LocalFileErrorCode::Conflict, "目标已存在，未覆盖。")
            } else {
                io_error(e)
            });
        }
        self.publication = Publication::Unknown;
        let verify = || -> Result<()> {
            if stat_at(&target)? != before || stat_fd(&self.target)? != before {
                return Err(error(
                    LocalFileErrorCode::ResultUnknown,
                    "提交后对象身份无法核验。",
                ));
            }
            sync(&target.parent)?;
            sync(&source.parent)?;
            Ok(())
        };
        verify().map_err(|_| {
            error(
                LocalFileErrorCode::ResultUnknown,
                "提交已发生，但身份或目录同步未确认；不会重放。",
            )
        })?;
        self.publication = Publication::Published;
        Ok(before)
    }
}
fn check(token: &CancellationToken, deadline: Instant) -> Result<()> {
    if token.is_cancelled() {
        Err(error(LocalFileErrorCode::Cancelled, "文件执行已取消。"))
    } else if Instant::now() >= deadline {
        Err(error(
            LocalFileErrorCode::TimedOut,
            "文件执行超过调用方期限。",
        ))
    } else {
        Ok(())
    }
}
fn wait(file: &File, events: i16, token: &CancellationToken, deadline: Instant) -> Result<()> {
    loop {
        check(token, deadline)?;
        let mut fd = libc::pollfd {
            fd: file.as_raw_fd(),
            events,
            revents: 0,
        };
        let timeout = deadline
            .saturating_duration_since(Instant::now())
            .as_millis()
            .min(50) as i32;
        let result = unsafe { libc::poll(&mut fd, 1, timeout) };
        if result > 0 {
            return Ok(());
        }
        if result < 0 {
            let e = io::Error::last_os_error();
            if e.kind() != io::ErrorKind::Interrupted {
                return Err(io_error(e));
            }
        }
    }
}
