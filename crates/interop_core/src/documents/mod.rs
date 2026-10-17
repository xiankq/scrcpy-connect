//! Shared document I/O. Android grants descriptor capabilities; this module owns
//! bounded copying, local path safety and cancellation. No provider is trusted
//! to make an existing destination safe to truncate.
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

pub const MAX_ENTRIES: usize = 10_000;
pub const MAX_DEPTH: usize = 64;
pub const MAX_PATH_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_BYTES: u64 = 8 * 1024 * 1024 * 1024;
pub const TIMEOUT_MILLIS: u64 = 10 * 60 * 1000;

#[derive(Debug)]
pub struct DocumentError {
    pub code: &'static str,
    pub message: String,
    pub details: Value,
}
impl std::fmt::Display for DocumentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}
impl std::error::Error for DocumentError {}
fn fail(code: &'static str, message: impl Into<String>) -> DocumentError {
    DocumentError {
        code,
        message: message.into(),
        details: Value::Null,
    }
}
impl From<std::io::Error> for DocumentError {
    fn from(e: std::io::Error) -> Self {
        fail("document_io", e.to_string())
    }
}
fn text<'a>(p: &'a Value, key: &str) -> Result<&'a str, DocumentError> {
    p[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| fail("invalid_argument", format!("缺少 {key}。")))
}

#[derive(Default)]
struct Inner {
    active: Mutex<Option<(String, Arc<AtomicBool>)>>,
    cancelled: Mutex<Vec<String>>,
}
#[derive(Clone, Default)]
pub struct CopyManager(Arc<Inner>);
impl CopyManager {
    pub fn request(&self, command: &str, p: Value) -> Result<Value, DocumentError> {
        if command == "document.limits" {
            return Ok(
                json!({"maxEntries":MAX_ENTRIES,"maxDepth":MAX_DEPTH,"maxPathBytes":MAX_PATH_BYTES,"maxBytes":MAX_BYTES,"timeoutMillis":TIMEOUT_MILLIS,"reserveBytes":32*1024*1024,"maxErrors":1000,"maxSelected":1000}),
            );
        }
        if command == "document.cancel" {
            let id = text(&p, "operationId")?;
            let active = self.0.active.lock().unwrap();
            let matched = active.as_ref().is_some_and(|(key, flag)| {
                if key == id {
                    flag.store(true, Ordering::Release);
                    true
                } else {
                    false
                }
            });
            let mut cancelled = self.0.cancelled.lock().unwrap();
            if !cancelled.iter().any(|s| s == id) {
                if cancelled.len() == 256 {
                    cancelled.remove(0);
                }
                cancelled.push(id.to_owned());
            }
            return Ok(json!({"cancelled":matched,"operationId":id}));
        }
        #[cfg(any(target_os = "linux", target_os = "android"))]
        {
            unix::request(self, command, &p)
        }
        #[cfg(not(any(target_os = "linux", target_os = "android")))]
        {
            let _ = (command, p);
            Err(fail("implementation_pending", "此平台尚未接入文档描述符。"))
        }
    }
}

#[cfg(any(target_os = "linux", target_os = "android"))]
mod unix {
    use super::*;
    use std::{
        ffi::{CStr, CString},
        io,
        os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd},
        path::{Component, Path},
        time::{Duration, Instant},
    };
    fn os_error() -> DocumentError {
        io::Error::last_os_error().into()
    }
    fn c(s: &str) -> Result<CString, DocumentError> {
        CString::new(s).map_err(|_| fail("invalid_path", "路径包含空字符。"))
    }
    fn fd(result: i32) -> Result<OwnedFd, DocumentError> {
        if result < 0 {
            Err(os_error())
        } else {
            Ok(unsafe { OwnedFd::from_raw_fd(result) })
        }
    }
    fn stat(fd: RawFd) -> Result<libc::stat, DocumentError> {
        let mut s = std::mem::MaybeUninit::uninit();
        if unsafe { libc::fstat(fd, s.as_mut_ptr()) } < 0 {
            return Err(os_error());
        }
        Ok(unsafe { s.assume_init() })
    }
    fn kind(s: &libc::stat) -> &'static str {
        // Android armv7's stat field and mode_t constants have different
        // widths. Widen both without truncating platform-specific mode bits.
        let mode = u64::from(s.st_mode) & u64::from(libc::S_IFMT);
        if mode == u64::from(libc::S_IFREG) {
            "file"
        } else if mode == u64::from(libc::S_IFDIR) {
            "directory"
        } else if mode == u64::from(libc::S_IFLNK) {
            "symlink"
        } else {
            "unsupported"
        }
    }
    fn identity(s: &libc::stat) -> Value {
        json!({"inode":s.st_ino,"device":s.st_dev,"size":s.st_size,"modified":s.st_mtime,"modifiedNs":s.st_mtime_nsec,"kind":kind(s)})
    }
    fn same(a: &libc::stat, b: &libc::stat) -> bool {
        a.st_ino == b.st_ino
            && a.st_dev == b.st_dev
            && a.st_size == b.st_size
            && a.st_mtime == b.st_mtime
            && a.st_mtime_nsec == b.st_mtime_nsec
            && kind(a) == kind(b)
    }
    fn expected(s: &libc::stat, p: &Value) -> bool {
        let own = identity(s);
        p.is_null()
            || ["inode", "device", "size", "modified", "modifiedNs", "kind"]
                .iter()
                .all(|key| p[*key] == own[*key])
    }
    struct Location {
        parent: OwnedFd,
        name: CString,
    }
    fn location(p: &Value, path: &str) -> Result<Location, DocumentError> {
        let path = Path::new(path);
        if !path.is_absolute()
            || path
                .components()
                .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
        {
            return Err(fail("invalid_path", "仅接受所选暂存范围内的绝对路径。"));
        }
        let roots = p["allowedRoots"]
            .as_array()
            .ok_or_else(|| fail("invalid_path", "缺少本机暂存范围。"))?;
        let (root, relative) = roots
            .iter()
            .filter_map(Value::as_str)
            .filter_map(|r| path.strip_prefix(r).ok().map(|rel| (r, rel)))
            .filter(|(_, rel)| !rel.as_os_str().is_empty())
            .max_by_key(|(r, _)| r.len())
            .ok_or_else(|| fail("invalid_path", "路径不在应用暂存或截图范围内。"))?;
        let root = c(root)?;
        let mut parent = fd(unsafe {
            libc::open(
                root.as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC | libc::O_NOFOLLOW,
            )
        })?;
        let mut components = relative.components().peekable();
        while let Some(component) = components.next() {
            let Component::Normal(name) = component else {
                return Err(fail("invalid_path", "路径不是普通相对路径。"));
            };
            let name = c(name
                .to_str()
                .ok_or_else(|| fail("invalid_path", "文件名无法解析。"))?)?;
            if components.peek().is_none() {
                return Ok(Location { parent, name });
            }
            parent = fd(unsafe {
                libc::openat(
                    parent.as_raw_fd(),
                    name.as_ptr(),
                    libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC | libc::O_NOFOLLOW,
                )
            })?;
        }
        Err(fail("invalid_path", "不能覆盖暂存根目录。"))
    }
    fn open(p: &Value, path: &str, flags: i32) -> Result<OwnedFd, DocumentError> {
        let l = location(p, path)?;
        open_at(&l, flags)
    }
    fn open_at(l: &Location, flags: i32) -> Result<OwnedFd, DocumentError> {
        fd(unsafe {
            libc::openat(
                l.parent.as_raw_fd(),
                l.name.as_ptr(),
                flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
                0o600,
            )
        })
    }
    fn duplicate(p: &Value, key: &str) -> Result<OwnedFd, DocumentError> {
        let raw = p[key]
            .as_i64()
            .and_then(|n| i32::try_from(n).ok())
            .filter(|n| *n >= 0)
            .ok_or_else(|| fail("invalid_fd", "文件描述符无效。"))?;
        let owned = fd(unsafe { libc::fcntl(raw, libc::F_DUPFD_CLOEXEC, 0) })?;
        let flags = unsafe { libc::fcntl(owned.as_raw_fd(), libc::F_GETFL) };
        if flags < 0
            || unsafe { libc::fcntl(owned.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK) }
                < 0
        {
            return Err(os_error());
        }
        Ok(owned)
    }
    fn remove_identity(p: &Value, path: &str, id: &Value) -> Result<(), DocumentError> {
        let l = location(p, path)?;
        let current = open(p, path, libc::O_RDONLY)?;
        let s = stat(current.as_raw_fd())?;
        if id["inode"].as_u64() != Some(s.st_ino) || id["device"].as_u64() != Some(s.st_dev) {
            return Err(fail("target_changed", "暂存位置已变化，未删除替换内容。"));
        }
        if unsafe { libc::unlinkat(l.parent.as_raw_fd(), l.name.as_ptr(), 0) } < 0 {
            return Err(os_error());
        }
        Ok(())
    }
    pub(super) fn request(
        manager: &CopyManager,
        command: &str,
        p: &Value,
    ) -> Result<Value, DocumentError> {
        match command {
            "document.localStat" => {
                let path = text(p, "path")?;
                let file = open(p, path, libc::O_PATH)?;
                let s = stat(file.as_raw_fd())?;
                let mut v = identity(&s);
                let mut space = std::mem::MaybeUninit::uninit();
                if unsafe { libc::fstatvfs(file.as_raw_fd(), space.as_mut_ptr()) } == 0 {
                    let space = unsafe { space.assume_init() };
                    v["freeBytes"] = json!(
                        (u128::from(space.f_bavail) * u128::from(space.f_frsize))
                            .min(u128::from(u64::MAX)) as u64
                    );
                }
                v["path"] = json!(path);
                Ok(v)
            }
            "document.localChildren" => {
                let parent = text(p, "path")?;
                let file = open(p, parent, libc::O_RDONLY | libc::O_DIRECTORY)?;
                let before = stat(file.as_raw_fd())?;
                let dup = fd(unsafe { libc::fcntl(file.as_raw_fd(), libc::F_DUPFD_CLOEXEC, 0) })?;
                let raw = std::os::fd::IntoRawFd::into_raw_fd(dup);
                let dir = unsafe { libc::fdopendir(raw) };
                if dir.is_null() {
                    unsafe { libc::close(raw) };
                    return Err(os_error());
                }
                struct Dir(*mut libc::DIR);
                impl Drop for Dir {
                    fn drop(&mut self) {
                        unsafe { libc::closedir(self.0) };
                    }
                }
                let guard = Dir(dir);
                let mut entries = vec![];
                loop {
                    let e = unsafe { libc::readdir(guard.0) };
                    if e.is_null() {
                        break;
                    }
                    let name = unsafe { CStr::from_ptr((*e).d_name.as_ptr()) };
                    if name.to_bytes() == b"." || name.to_bytes() == b".." {
                        continue;
                    }
                    if entries.len() == MAX_ENTRIES {
                        return Err(fail("tree_limit", "目录超过 10000 项，请分批处理。"));
                    }
                    let name = name.to_str().map_err(|_| {
                        fail(
                            "invalid_path",
                            "源目录包含无法解析的文件名，未猜测目标路径。",
                        )
                    })?;
                    let child_name = c(name)?;
                    let mut child_stat = std::mem::MaybeUninit::uninit();
                    if unsafe {
                        libc::fstatat(
                            file.as_raw_fd(),
                            child_name.as_ptr(),
                            child_stat.as_mut_ptr(),
                            libc::AT_SYMLINK_NOFOLLOW,
                        )
                    } < 0
                    {
                        return Err(os_error());
                    }
                    let child_stat = unsafe { child_stat.assume_init() };
                    entries.push(json!({"name":name,"path":format!("{parent}/{name}"),"identity":identity(&child_stat)}));
                }
                let after = stat(file.as_raw_fd())?;
                if !same(&before, &after) {
                    return Err(fail("source_changed", "列目录期间源目录发生变化。"));
                }
                Ok(json!({"entries":entries,"identity":identity(&before)}))
            }
            "document.mkdir" => {
                let path = text(p, "path")?;
                let l = location(p, path)?;
                if unsafe { libc::mkdirat(l.parent.as_raw_fd(), l.name.as_ptr(), 0o700) } < 0 {
                    if p["exclusive"] == false
                        && io::Error::last_os_error().kind() == io::ErrorKind::AlreadyExists
                    {
                        let existing = open(p, path, libc::O_RDONLY | libc::O_DIRECTORY)?;
                        let _ = stat(existing.as_raw_fd())?;
                        return Ok(json!({"created":false}));
                    }
                    return Err(os_error());
                }
                Ok(json!({"created":true}))
            }
            "document.remove" => {
                remove_identity(p, text(p, "path")?, &p["identity"])?;
                Ok(json!({"removed":true}))
            }
            "document.commit" => {
                let from = text(p, "partPath")?;
                let to = text(p, "path")?;
                let source = location(p, from)?;
                let file = open_at(&source, libc::O_RDONLY)?;
                let s = stat(file.as_raw_fd())?;
                if kind(&s) != "file" || !expected(&s, &p["identity"]) {
                    return Err(fail("source_changed", "暂存文件在提交前发生变化。"));
                }
                let destination = location(p, to)?;
                let current = open_at(&source, libc::O_RDONLY)?;
                if !same(&s, &stat(current.as_raw_fd())?) {
                    return Err(fail("source_changed", "暂存文件在提交前发生变化。"));
                }
                if unsafe { libc::fsync(file.as_raw_fd()) } < 0 {
                    return Err(os_error());
                }
                if crate::local_publication::rename_noreplace(
                    source.parent.as_raw_fd(),
                    &source.name,
                    destination.parent.as_raw_fd(),
                    &destination.name,
                )
                .is_err()
                {
                    return Err(fail(
                        "cache_conflict",
                        "暂存目标已存在或无法安全提交，未覆盖。",
                    ));
                }
                let verified = (|| -> Result<bool, DocumentError> {
                    let published = open_at(&destination, libc::O_RDONLY)?;
                    if !same(&s, &stat(published.as_raw_fd())?)
                        || !same(&s, &stat(file.as_raw_fd())?)
                    {
                        return Ok(false);
                    }
                    if unsafe { libc::fsync(destination.parent.as_raw_fd()) } < 0
                        || unsafe { libc::fsync(source.parent.as_raw_fd()) } < 0
                    {
                        return Err(os_error());
                    }
                    Ok(true)
                })();
                if !matches!(verified, Ok(true)) {
                    return Err(fail(
                        "result_unknown",
                        "暂存提交后身份或目录同步无法核对，请检查本机暂存。",
                    ));
                }
                Ok(json!({"committed":true,"identity":identity(&s)}))
            }
            "document.copy" => copy(manager, p),
            _ => Err(fail("unknown_command", "未知文档命令。")),
        }
    }
    struct Slot<'a>(&'a CopyManager);
    impl Drop for Slot<'_> {
        fn drop(&mut self) {
            *self.0.0.active.lock().unwrap() = None;
        }
    }
    fn copy(manager: &CopyManager, p: &Value) -> Result<Value, DocumentError> {
        let id = text(p, "operationId")?.to_owned();
        if id.len() > 128 {
            return Err(fail("invalid_argument", "操作标识过长。"));
        }
        let cancelled = Arc::new(AtomicBool::new(false));
        {
            let mut active = manager.0.active.lock().unwrap();
            if active.is_some() {
                return Err(fail(
                    "documents_busy",
                    "已有文档数据流仍在处理，请等待其释放。",
                ));
            }
            // Register and inspect early cancellation under the same lock
            // order as cancel, so cancel-before-bind cannot miss this copy.
            cancelled.store(
                manager.0.cancelled.lock().unwrap().iter().any(|s| s == &id),
                Ordering::Release,
            );
            *active = Some((id, cancelled.clone()));
        }
        let _slot = Slot(manager);
        let deadline = Instant::now() + Duration::from_millis(TIMEOUT_MILLIS);
        let source_path = p["sourcePath"].as_str();
        let target_path = p["targetPath"].as_str();
        if source_path.is_some() == p["sourceFd"].is_number()
            || target_path.is_some() == p["targetFd"].is_number()
        {
            return Err(fail("invalid_argument", "每端必须明确指定路径或描述符。"));
        }
        let source = if let Some(path) = source_path {
            open(p, path, libc::O_RDONLY)?
        } else {
            duplicate(p, "sourceFd")?
        };
        let before = stat(source.as_raw_fd())?;
        if source_path.is_some()
            && (kind(&before) != "file" || !expected(&before, &p["sourceIdentity"]))
        {
            return Err(fail("source_changed", "源文件身份或类型已变化。"));
        }
        let target = if let Some(path) = target_path {
            open(p, path, libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL)?
        } else {
            duplicate(p, "targetFd")?
        };
        let target_before = stat(target.as_raw_fd())?;
        let target_id = identity(&target_before);
        if kind(&target_before) != "file" || target_before.st_size != 0 {
            return Err(fail(
                "target_changed",
                "目标不是可核验的空普通文件，未截断或写入。",
            ));
        }
        if unsafe { libc::lseek(target.as_raw_fd(), 0, libc::SEEK_SET) } < 0 {
            return Err(os_error());
        }
        let max = p["maxBytes"].as_u64().unwrap_or(MAX_BYTES).min(MAX_BYTES);
        let mut bytes = 0u64;
        let result = (|| {
            let mut buffer = [0u8; 64 * 1024];
            loop {
                check(&cancelled, deadline)?;
                wait(source.as_raw_fd(), libc::POLLIN, &cancelled, deadline)?;
                let count = unsafe {
                    libc::read(source.as_raw_fd(), buffer.as_mut_ptr().cast(), buffer.len())
                };
                if count < 0 {
                    let e = io::Error::last_os_error();
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) {
                        continue;
                    }
                    return Err(e.into());
                }
                if count == 0 {
                    break;
                }
                let count = count as usize;
                if bytes > max.saturating_sub(count as u64) || count as u64 > max {
                    return Err(fail("byte_limit", "本次复制超过剩余字节上限，请分批处理。"));
                }
                let mut offset = 0;
                while offset < count {
                    check(&cancelled, deadline)?;
                    wait(target.as_raw_fd(), libc::POLLOUT, &cancelled, deadline)?;
                    let n = unsafe {
                        libc::write(
                            target.as_raw_fd(),
                            buffer[offset..count].as_ptr().cast(),
                            count - offset,
                        )
                    };
                    if n < 0 {
                        let e = io::Error::last_os_error();
                        if matches!(
                            e.kind(),
                            io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                        ) {
                            continue;
                        }
                        return Err(e.into());
                    }
                    if n == 0 {
                        return Err(fail("write_failed", "目标数据流未接受内容。"));
                    }
                    offset += n as usize;
                    bytes += n as u64;
                }
            }
            check(&cancelled, deadline)?;
            if unsafe { libc::fsync(target.as_raw_fd()) } < 0 {
                return Err(os_error());
            }
            if let Some(source_path) = source_path {
                let after = stat(source.as_raw_fd())?;
                let reopened = open(p, source_path, libc::O_RDONLY)?;
                if !same(&before, &after) || !same(&before, &stat(reopened.as_raw_fd())?) {
                    return Err(fail(
                        "source_changed",
                        "源文件在保存期间变化，目标可能包含部分内容。",
                    ));
                }
            }
            Ok(
                json!({"bytes":bytes,"identity":identity(&stat(target.as_raw_fd())?),"sourceIdentity":identity(&before)}),
            )
        })();
        match result {
            Ok(v) => Ok(v),
            Err(mut e) => {
                if let Some(path) = target_path {
                    let _ = remove_identity(p, path, &target_id);
                }
                e.details = json!({"bytesCopied":bytes,"partialDestinationPossible":target_path.is_none()&&bytes>0});
                Err(e)
            }
        }
    }
    fn check(cancelled: &AtomicBool, deadline: Instant) -> Result<(), DocumentError> {
        if cancelled.load(Ordering::Acquire) {
            Err(fail("cancelled", "操作已取消；已完成内容保留。"))
        } else if Instant::now() >= deadline {
            Err(fail("timeout", "文档数据流超过十分钟。"))
        } else {
            Ok(())
        }
    }
    fn wait(
        fd: RawFd,
        events: i16,
        cancelled: &AtomicBool,
        deadline: Instant,
    ) -> Result<(), DocumentError> {
        loop {
            check(cancelled, deadline)?;
            let mut p = libc::pollfd {
                fd,
                events,
                revents: 0,
            };
            let n = unsafe { libc::poll(&mut p, 1, 100) };
            if n > 0 {
                if p.revents & libc::POLLNVAL != 0 {
                    return Err(fail("invalid_fd", "文档描述符已失效。"));
                }
                return Ok(());
            }
            if n < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                return Err(os_error());
            }
        }
    }
}
