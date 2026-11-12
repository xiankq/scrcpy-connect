//! 私有授权身份的读取、RSA 校验、首次安装与显式比较替换。
use interop_adb::Identity;
use sha2::{Digest, Sha256};
use std::{
    ffi::{OsStr, OsString},
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
};

/// 公开信息不包含私钥；指纹兼容旧版带注释及结尾 NUL 的 ADB 公钥编码。
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct IdentityInfo {
    pub fingerprint: String,
    pub fingerprint_algorithm: String,
    pub fingerprint_input: String,
    pub bits: u32,
    pub exponent: u32,
}

fn info(identity: &Identity) -> Result<IdentityInfo, String> {
    let public = identity
        .public_key("")
        .map_err(|_| "adb_identity_public_key")?;
    public_key_info(&public)
}

/// 将协议库已校验的空注释公钥快照还原为兼容指纹输入；不读取身份文件。
pub(super) fn public_key_info(public: &[u8]) -> Result<IdentityInfo, String> {
    let encoded = public
        .strip_suffix(b" \0")
        .filter(|value| !value.is_empty())
        .ok_or("adb_identity_public_key_encoding")?;
    let mut hash = Sha256::new();
    hash.update(encoded);
    hash.update(b" interop\0");
    Ok(IdentityInfo {
        fingerprint: hash
            .finalize()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect(),
        fingerprint_algorithm: "sha256".into(),
        fingerprint_input: "adb-public-key-interop-v1".into(),
        bits: 2048,
        exponent: 65537,
    })
}

/// 只读取既有身份；路径不存在不会创建目录或生成私钥。
pub(super) async fn inspect(path: String) -> Result<Option<IdentityInfo>, String> {
    tokio::task::spawn_blocking(move || {
        let path = Path::new(&path);
        require_path(path)?;
        let directory =
            match IdentityDirectory::open(path.parent().ok_or("adb_identity_parent_missing")?) {
                Ok(directory) => directory,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
                Err(error) => return Err(format!("adb_identity_directory: {error}")),
            };
        directory
            .load(path.file_name().unwrap())?
            .as_ref()
            .map(info)
            .transpose()
    })
    .await
    .map_err(|_| "adb_identity_worker".to_owned())?
}

/// RSA 结构、位数及指数统一由协议库验证，不接受仅具有 PEM 包装的任意内容。
pub(super) fn validate(pem: &str) -> Result<IdentityInfo, String> {
    info(&parse(pem)?)
}

fn parse(pem: &str) -> Result<Identity, String> {
    if pem.len() > 32 * 1024 {
        return Err("adb_identity_size_limit".into());
    }
    Identity::from_pem(pem).map_err(|_| "adb_identity_invalid".into())
}

fn require_path(path: &Path) -> Result<(), String> {
    if !path.is_absolute()
        || path.file_name().is_none()
        || path
            .components()
            .any(|part| matches!(part, Component::ParentDir))
    {
        return Err("adb_identity_path_must_be_absolute".into());
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum IdentityCommitState {
    Committed,
    Unchanged,
    Unknown,
}

/// 错误发生在发布之后时仍返回回执；调用方不能将未知结果当作允许重试。
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct IdentityCommitReceipt {
    pub state: IdentityCommitState,
    pub identity: Option<IdentityInfo>,
    pub error: Option<String>,
}

/// None 表示只安装不存在的身份；替换已有身份须提供此前读取的指纹。
/// 目录由调用方准备，文件锁仅协调遵循此接口的写入者。
pub(super) async fn replace(
    path: String,
    pem: String,
    expected_fingerprint: Option<String>,
) -> Result<IdentityCommitReceipt, String> {
    let pem = zeroize::Zeroizing::new(pem);
    match tokio::task::spawn_blocking(move || {
        replace_blocking(
            Path::new(&path),
            &pem,
            expected_fingerprint.as_deref(),
            &FilesystemCommit,
        )
    })
    .await
    {
        Ok(result) => result,
        Err(_) => Ok(IdentityCommitReceipt {
            state: IdentityCommitState::Unknown,
            identity: None,
            error: Some("adb_identity_worker_result_unknown".into()),
        }),
    }
}

fn replace_blocking(
    path: &Path,
    pem: &str,
    expected: Option<&str>,
    commit: &dyn IdentityCommitIo,
) -> Result<IdentityCommitReceipt, String> {
    require_path(path)?;
    let identity = parse(pem)?;
    let next = info(&identity)?;
    if expected.is_some_and(|value| {
        value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit())
    }) {
        return Err("adb_identity_invalid_fingerprint".into());
    }
    let directory = IdentityDirectory::open(path.parent().ok_or("adb_identity_parent_missing")?)
        .map_err(|error| format!("adb_identity_directory: {error}"))?;
    let target = path.file_name().unwrap();
    let lock_name = OsString::from(format!(
        ".adb-identity-lock-{}",
        Sha256::digest(target.as_encoded_bytes())
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    ));
    let lock = directory
        .open_file(&lock_name, false, true)
        .map_err(|error| format!("adb_identity_lock: {error}"))?;
    private_metadata(&lock)?;
    lock.lock()
        .map_err(|error| format!("adb_identity_lock: {error}"))?;
    let previous = directory.load(target)?.as_ref().map(info).transpose()?;
    let matches = match (&previous, expected) {
        (None, None) => true,
        (Some(previous), Some(expected)) => previous.fingerprint.eq_ignore_ascii_case(expected),
        _ => false,
    };
    if !matches {
        return Ok(IdentityCommitReceipt {
            state: IdentityCommitState::Unchanged,
            identity: previous,
            error: Some("adb_identity_conflict".into()),
        });
    }
    if previous.as_ref() == Some(&next) {
        return Ok(IdentityCommitReceipt {
            state: IdentityCommitState::Unchanged,
            identity: previous,
            error: None,
        });
    }
    let mut temporary = TemporaryIdentity::create(&directory)
        .map_err(|error| format!("adb_identity_create: {error}"))?;
    let canonical = identity
        .to_pkcs8_pem()
        .map_err(|_| "adb_identity_invalid")?;
    temporary
        .file
        .write_all(canonical.as_bytes())
        .map_err(|error| format!("adb_identity_write: {error}"))?;
    temporary
        .file
        .sync_all()
        .map_err(|error| format!("adb_identity_sync: {error}"))?;
    let published = commit.publish(&directory, &temporary.name, target, previous.is_some());
    if let Err(error) = published {
        // 发布系统调用的回执可能丢失，先读取同一目录句柄下的实际目标。
        let observed = directory
            .load(target)
            .and_then(|identity| identity.as_ref().map(info).transpose());
        return Ok(match observed {
            Ok(observed) if observed.as_ref() == Some(&next) => committed(&directory, next, commit),
            Ok(observed) if observed == previous => IdentityCommitReceipt {
                state: IdentityCommitState::Unchanged,
                identity: observed,
                error: Some(format!("adb_identity_install: {error}")),
            },
            observed => IdentityCommitReceipt {
                state: IdentityCommitState::Unknown,
                identity: observed.ok().flatten(),
                error: Some(format!("adb_identity_commit_unknown: {error}")),
            },
        });
    }
    Ok(committed(&directory, next, commit))
}

fn committed(
    directory: &IdentityDirectory,
    identity: IdentityInfo,
    commit: &dyn IdentityCommitIo,
) -> IdentityCommitReceipt {
    if let Err(error) = directory.verify_location() {
        return IdentityCommitReceipt {
            state: IdentityCommitState::Unknown,
            identity: None,
            error: Some(format!("adb_identity_directory_changed: {error}")),
        };
    }
    match commit.sync_directory(directory) {
        Ok(()) => IdentityCommitReceipt {
            state: IdentityCommitState::Committed,
            identity: Some(identity),
            error: None,
        },
        Err(error) => IdentityCommitReceipt {
            state: IdentityCommitState::Unknown,
            identity: Some(identity),
            error: Some(format!("adb_identity_directory_sync: {error}")),
        },
    }
}

trait IdentityCommitIo {
    fn publish(
        &self,
        directory: &IdentityDirectory,
        temporary: &OsStr,
        target: &OsStr,
        replace: bool,
    ) -> std::io::Result<()>;
    fn sync_directory(&self, directory: &IdentityDirectory) -> std::io::Result<()>;
}

struct FilesystemCommit;
impl IdentityCommitIo for FilesystemCommit {
    fn publish(
        &self,
        directory: &IdentityDirectory,
        temporary: &OsStr,
        target: &OsStr,
        replace: bool,
    ) -> std::io::Result<()> {
        directory.publish(temporary, target, replace)
    }
    fn sync_directory(&self, directory: &IdentityDirectory) -> std::io::Result<()> {
        #[cfg(unix)]
        directory.file.sync_all()?;
        Ok(())
    }
}

/// Unix 操作始终相对已打开的目录，父路径改名或替换不能将发布重定向到其他目录。
struct IdentityDirectory {
    #[cfg(unix)]
    file: File,
    path: PathBuf,
    #[cfg(windows)]
    _ancestors: Vec<File>,
}

impl IdentityDirectory {
    fn open(path: &Path) -> std::io::Result<Self> {
        #[cfg(unix)]
        {
            use std::os::fd::{AsRawFd, FromRawFd};
            use std::os::unix::fs::OpenOptionsExt;
            let directory_flags = libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;
            // Android ancestors may permit searching a known path without directory reads.
            // O_PATH pins each directory without requiring permission to list it.
            #[cfg(any(target_os = "linux", target_os = "android"))]
            let traversal_flags = libc::O_PATH | directory_flags;
            #[cfg(not(any(target_os = "linux", target_os = "android")))]
            let traversal_flags = libc::O_RDONLY | directory_flags;
            let mut file = OpenOptions::new()
                .read(true)
                .custom_flags(traversal_flags)
                .open("/")?;
            for part in path.components() {
                let Component::Normal(name) = part else {
                    if matches!(part, Component::RootDir) {
                        continue;
                    }
                    return Err(std::io::Error::other("adb_identity_invalid_parent"));
                };
                let name = c_name(name)?;
                let fd = unsafe { libc::openat(file.as_raw_fd(), name.as_ptr(), traversal_flags) };
                if fd < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                file = unsafe { File::from_raw_fd(fd) };
            }
            #[cfg(any(target_os = "linux", target_os = "android"))]
            {
                // The owned directory needs a regular descriptor for fsync after publication.
                let fd = unsafe {
                    libc::openat(
                        file.as_raw_fd(),
                        c".".as_ptr(),
                        libc::O_RDONLY | directory_flags,
                    )
                };
                if fd < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                file = unsafe { File::from_raw_fd(fd) };
            }
            Ok(Self {
                file,
                path: path.to_owned(),
            })
        }
        #[cfg(not(unix))]
        {
            let mut current = PathBuf::new();
            #[cfg(windows)]
            let mut ancestors = Vec::new();
            for part in path.components() {
                current.push(part);
                if matches!(part, Component::Prefix(_)) {
                    continue;
                }
                #[cfg(windows)]
                let metadata = {
                    use std::os::windows::fs::OpenOptionsExt;
                    // 打开重解析点本身，并禁止删除共享；持有全部祖先句柄期间路径无法被改名重定向。
                    let file = OpenOptions::new()
                        .read(true)
                        .custom_flags(0x00200000 | 0x02000000)
                        .share_mode(0x1 | 0x2)
                        .open(&current)?;
                    let metadata = file.metadata()?;
                    ancestors.push(file);
                    metadata
                };
                #[cfg(not(windows))]
                let metadata = fs::symlink_metadata(&current)?;
                if is_reparse(&metadata) || !metadata.is_dir() {
                    return Err(std::io::Error::other("adb_identity_invalid_parent"));
                }
            }
            Ok(Self {
                path: path.to_owned(),
                #[cfg(windows)]
                _ancestors: ancestors,
            })
        }
    }

    fn verify_location(&self) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            let current = Self::open(&self.path)?;
            let expected = self.file.metadata()?;
            let actual = current.file.metadata()?;
            if (expected.dev(), expected.ino()) != (actual.dev(), actual.ino()) {
                return Err(std::io::Error::other("身份目录已替换"));
            }
        }
        // Windows 的祖先句柄禁止删除共享，直到本次提交结束才允许目录改名。
        Ok(())
    }

    fn open_file(&self, name: &OsStr, exclusive: bool, writable: bool) -> std::io::Result<File> {
        #[cfg(unix)]
        {
            use std::os::fd::{AsRawFd, FromRawFd};
            let name = c_name(name)?;
            let access = if writable {
                libc::O_RDWR | libc::O_CREAT
            } else {
                libc::O_RDONLY
            };
            let flags = access
                | libc::O_CLOEXEC
                | libc::O_NOFOLLOW
                | libc::O_NONBLOCK
                | if exclusive { libc::O_EXCL } else { 0 };
            let fd = unsafe { libc::openat(self.file.as_raw_fd(), name.as_ptr(), flags, 0o600) };
            if fd < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(unsafe { File::from_raw_fd(fd) })
        }
        #[cfg(not(unix))]
        {
            let path = self.path.join(name);
            if let Ok(metadata) = fs::symlink_metadata(&path) {
                if is_reparse(&metadata) {
                    return Err(std::io::Error::other("adb_identity_symbolic_link"));
                }
            }
            let mut options = OpenOptions::new();
            options
                .read(true)
                .write(writable)
                .create(writable && !exclusive)
                .create_new(exclusive);
            #[cfg(windows)]
            {
                use std::os::windows::fs::OpenOptionsExt;
                options.custom_flags(0x00200000);
            }
            options.open(path)
        }
    }

    fn load(&self, name: &OsStr) -> Result<Option<Identity>, String> {
        match self.open_file(name, false, false) {
            Ok(file) => load_file(file).map(Some),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(format!("adb_identity_open: {error}")),
        }
    }

    fn remove(&self, name: &OsStr) {
        #[cfg(unix)]
        {
            use std::os::fd::AsRawFd;
            if let Ok(name) = c_name(name) {
                unsafe {
                    libc::unlinkat(self.file.as_raw_fd(), name.as_ptr(), 0);
                }
            }
        }
        #[cfg(not(unix))]
        {
            let _ = fs::remove_file(self.path.join(name));
        }
    }

    fn publish(&self, temporary: &OsStr, target: &OsStr, replace: bool) -> std::io::Result<()> {
        #[cfg(unix)]
        {
            use std::os::fd::AsRawFd;
            let temporary = c_name(temporary)?;
            let target = c_name(target)?;
            let fd = self.file.as_raw_fd();
            let status = unsafe {
                if replace {
                    libc::renameat(fd, temporary.as_ptr(), fd, target.as_ptr())
                } else {
                    libc::linkat(fd, temporary.as_ptr(), fd, target.as_ptr(), 0)
                }
            };
            if status < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        }
        #[cfg(not(unix))]
        {
            if replace {
                fs::rename(self.path.join(temporary), self.path.join(target))
            } else {
                fs::hard_link(self.path.join(temporary), self.path.join(target))
            }
        }
    }
}

#[cfg(unix)]
fn c_name(name: &OsStr) -> std::io::Result<std::ffi::CString> {
    use std::os::unix::ffi::OsStrExt;
    std::ffi::CString::new(name.as_bytes())
        .map_err(|_| std::io::Error::other("adb_identity_invalid_path"))
}

#[cfg(not(unix))]
fn is_reparse(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        metadata.file_type().is_symlink()
    }
}

struct TemporaryIdentity<'a> {
    directory: &'a IdentityDirectory,
    name: OsString,
    file: File,
}
impl<'a> TemporaryIdentity<'a> {
    fn create(directory: &'a IdentityDirectory) -> std::io::Result<Self> {
        let name = OsString::from(format!(".adb-identity-{}.tmp", uuid::Uuid::new_v4()));
        let file = directory.open_file(&name, true, true)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            file.set_permissions(fs::Permissions::from_mode(0o600))?;
        }
        Ok(Self {
            directory,
            name,
            file,
        })
    }
}
impl Drop for TemporaryIdentity<'_> {
    fn drop(&mut self) {
        self.directory.remove(&self.name);
    }
}

pub(super) async fn prepare(path: String) -> Result<Identity, String> {
    tokio::task::spawn_blocking(move || prepare_blocking(Path::new(&path)))
        .await
        .map_err(|error| format!("adb_identity_worker: {error}"))?
}

fn load(path: &Path) -> Result<Option<Identity>, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            return Err("adb_identity_open: symbolic link is not allowed".into());
        }
        Ok(metadata) if !metadata.is_file() => return Err("adb_identity_not_a_file".into()),
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("adb_identity_metadata: {error}")),
    }
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    let file = match options.open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("adb_identity_open: {error}")),
    };
    load_file(file).map(Some)
}

fn private_metadata(file: &File) -> Result<(), String> {
    let metadata = file
        .metadata()
        .map_err(|error| format!("adb_identity_metadata: {error}"))?;
    if !metadata.is_file() {
        return Err("adb_identity_not_a_file".into());
    }
    #[cfg(not(unix))]
    if is_reparse(&metadata) {
        return Err("adb_identity_open: symbolic link is not allowed".into());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if metadata.permissions().mode() & 0o077 != 0 {
            return Err("adb_identity_permissions".into());
        }
    }
    Ok(())
}

fn load_file(file: File) -> Result<Identity, String> {
    private_metadata(&file)?;
    let mut pem = zeroize::Zeroizing::new(String::new());
    file.take(65537)
        .read_to_string(&mut pem)
        .map_err(|error| format!("adb_identity_read: {error}"))?;
    if pem.len() > 65536 {
        return Err("adb_identity_size_limit".into());
    }
    Identity::from_pem(&pem).map_err(|error| format!("adb_identity_invalid: {error}"))
}

fn prepare_blocking(path: &Path) -> Result<Identity, String> {
    if !path.is_absolute() || path.file_name().is_none() {
        return Err("adb_identity_path_must_be_absolute".into());
    }
    if let Some(identity) = load(path)? {
        return Ok(identity);
    }
    let parent = path.parent().ok_or("adb_identity_parent_missing")?;
    fs::create_dir_all(parent).map_err(|error| format!("adb_identity_directory: {error}"))?;
    let identity = Identity::generate().map_err(|error| error.to_string())?;
    let pem = identity.to_pkcs8_pem().map_err(|error| error.to_string())?;
    // 临时文件使用 create_new 和仅所有者可读写权限；写完并同步后才原子安装到目标路径。
    let mut pending = tempfile::Builder::new()
        .prefix(".adb-identity-")
        .tempfile_in(parent)
        .map_err(|error| format!("adb_identity_create: {error}"))?;
    pending
        .write_all(pem.as_bytes())
        .map_err(|error| format!("adb_identity_write: {error}"))?;
    pending
        .as_file()
        .sync_all()
        .map_err(|error| format!("adb_identity_sync: {error}"))?;
    match pending.persist_noclobber(path) {
        Ok(_) => {
            #[cfg(unix)]
            fs::File::open(parent)
                .and_then(|directory| directory.sync_all())
                .map_err(|error| format!("adb_identity_directory_sync: {error}"))?;
            Ok(identity)
        }
        Err(error) if error.error.kind() == std::io::ErrorKind::AlreadyExists => {
            load(path)?.ok_or_else(|| "adb_identity_competing_file_disappeared".into())
        }
        Err(error) => Err(format!("adb_identity_install: {}", error.error)),
    }
}
