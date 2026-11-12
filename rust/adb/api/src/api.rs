//! 通用 ADB 会话接口。拉取式类型化事件把 Dart 接缝限制为单个 64 KiB 包；文件留在主机文件系统，不进入命令 JSON。
use crate::consumer_activity::ConsumerActivity;
use interop_adb::{
    Client, ConnectOptions, Identity, OperationOptions, ShellEvent, ShellMode, TlsPolicy,
};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};
use tokio::sync::{Mutex as AsyncMutex, mpsc};
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

#[path = "handshake.rs"]
mod handshake;

#[path = "admission_scope.rs"]
mod admission_scope;

#[path = "connection_claim.rs"]
mod connection_claim;

#[path = "server_owner.rs"]
mod server_owner;

/// 连接、配对和本机交接错误；仅传递执行事实，调用方自行决定是否重试。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbConnectionErrorCode {
    InvalidArgument,
    Unsupported,
    AdmissionRejected,
    Identity,
    ConnectionRefused,
    HostUnreachable,
    NetworkUnreachable,
    ConnectTimedOut,
    HandshakeTimedOut,
    Cancelled,
    AuthorizationRequired,
    Protocol,
    Io,
    PairingResultUnknown,
    CleanupUnconfirmed,
    Internal,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdbConnectionError {
    pub code: AdbConnectionErrorCode,
    pub message: String,
}

impl AdbConnectionError {
    fn new(code: AdbConnectionErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    fn admission(message: impl Into<String>) -> Self {
        Self::new(AdbConnectionErrorCode::AdmissionRejected, message)
    }

    fn cleanup(message: impl Into<String>) -> Self {
        Self::new(AdbConnectionErrorCode::CleanupUnconfirmed, message)
    }

    fn connecting(error: interop_adb::Error) -> Self {
        use AdbConnectionErrorCode as Code;
        let code = match &error {
            interop_adb::Error::Timeout => Code::ConnectTimedOut,
            interop_adb::Error::Cancelled => Code::Cancelled,
            interop_adb::Error::Io(error) => match error.kind() {
                std::io::ErrorKind::ConnectionRefused => Code::ConnectionRefused,
                std::io::ErrorKind::HostUnreachable => Code::HostUnreachable,
                std::io::ErrorKind::NetworkUnreachable => Code::NetworkUnreachable,
                std::io::ErrorKind::TimedOut => Code::ConnectTimedOut,
                _ => Code::Io,
            },
            _ => Code::Io,
        };
        Self::new(code, error.to_string())
    }
}

impl From<interop_adb::Error> for AdbConnectionError {
    fn from(error: interop_adb::Error) -> Self {
        use AdbConnectionErrorCode as Code;
        let error = match error {
            interop_adb::Error::Connect(source) => return Self::connecting(*source),
            error => error,
        };
        let code = match &error {
            interop_adb::Error::PairingResultUnknown(_) => Code::PairingResultUnknown,
            interop_adb::Error::InvalidArgument(_) => Code::InvalidArgument,
            interop_adb::Error::Timeout => Code::HandshakeTimedOut,
            interop_adb::Error::Cancelled => Code::Cancelled,
            interop_adb::Error::AuthorizationRequired => Code::AuthorizationRequired,
            interop_adb::Error::Unsupported(_) => Code::Unsupported,
            interop_adb::Error::Identity(_) => Code::Identity,
            interop_adb::Error::Protocol(_) => Code::Protocol,
            _ => Code::Io,
        };
        Self::new(code, error.to_string())
    }
}

impl std::fmt::Display for AdbConnectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for AdbConnectionError {}

/// 官方服务器的准入和清理错误；Dart 按 code 处理，不解析诊断文本。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbServerErrorCode {
    InvalidArgument,
    NotFound,
    StaleLease,
    TransportStateUnknown,
    Closing,
    CleanupUnconfirmed,
    Io,
}
#[derive(Clone, Debug)]
pub struct AdbServerError {
    pub code: AdbServerErrorCode,
    pub message: String,
}
impl std::fmt::Display for AdbServerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for AdbServerError {}
/// 官方服务器的实际启动输入；身份目录与参数含义由 Dart 调用方决定。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdbServerLaunchSpec {
    pub executable: String,
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
    pub endpoint: String,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbServerPhase {
    Reserved,
    Starting,
    Ready,
    Exited,
}
#[derive(Clone, Debug)]
pub struct AdbServerInfo {
    pub server_id: String,
    pub lease_id: String,
    pub launch: AdbServerLaunchSpec,
    pub phase: AdbServerPhase,
    pub transport_state_unknown: bool,
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
}
/// 命令在创建时固定全部输入；preparation 只允许服务器尚未启动时使用。
#[derive(Clone, Debug)]
pub struct AdbServerCommandSpec {
    pub executable: String,
    pub arguments: Vec<String>,
    pub input: Vec<u8>,
    pub timeout_ms: u32,
    pub may_create_transport: bool,
    pub preparation: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbServerCommandStatus {
    Exited,
    Cancelled,
    TimedOut,
    OutputLimit,
    StartFailed,
    IoFailed,
}
/// 运行时状态与操作结果分开；error_message 仅用于诊断，不能承载控制流。
#[derive(Clone, Debug)]
pub struct AdbServerCommandResult {
    pub status: AdbServerCommandStatus,
    pub exit_code: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub error_message: Option<String>,
}
pub async fn adb_server_create(
    launch: AdbServerLaunchSpec,
) -> Result<AdbServerInfo, AdbServerError> {
    server_owner::create(launch)
}
/// 准入核验与服务器清理责任在同一个登记锁内提交。
pub async fn adb_server_create_scoped(
    launch: AdbServerLaunchSpec,
    scope_id: String,
) -> Result<AdbServerInfo, AdbServerError> {
    server_owner::create_scoped(launch, Some(&scope_id))
}
pub async fn adb_server_claim_scoped(
    lease_id: String,
    scope_id: String,
) -> Result<AdbServerInfo, AdbServerError> {
    server_owner::claim_scoped(&lease_id, Some(&scope_id), Duration::from_secs(7)).await
}
/// 只有调用方确认服务器已经完整交付，后继准入域才会保留它供精确恢复。
pub async fn adb_server_confirm_scoped(
    lease_id: String,
    scope_id: String,
) -> Result<(), AdbServerError> {
    server_owner::confirm(&lease_id, &scope_id)
}
pub async fn adb_server_start(
    lease_id: String,
    timeout_ms: u32,
) -> Result<AdbServerInfo, AdbServerError> {
    server_owner::start(&lease_id, timeout_ms).await
}
pub async fn adb_server_list() -> Result<Vec<AdbServerInfo>, AdbServerError> {
    Ok(server_owner::list())
}
pub async fn adb_server_claim(lease_id: String) -> Result<AdbServerInfo, AdbServerError> {
    server_owner::claim(&lease_id, Duration::from_secs(7)).await
}
pub async fn adb_server_close(lease_id: String) -> Result<(), AdbServerError> {
    server_owner::close(&lease_id, Duration::from_secs(7)).await
}
pub async fn adb_server_command_create(
    lease_id: String,
    spec: AdbServerCommandSpec,
) -> Result<String, AdbServerError> {
    server_owner::command::create(&lease_id, spec)
}
pub async fn adb_server_command_run(
    command_id: String,
) -> Result<AdbServerCommandResult, AdbServerError> {
    server_owner::command::run(&command_id).await
}
pub async fn adb_server_command_confirm(command_id: String) -> Result<(), AdbServerError> {
    server_owner::command::confirm(&command_id)
}
pub async fn adb_server_command_cancel(command_id: String) -> Result<(), AdbServerError> {
    server_owner::command::cancel(&command_id);
    Ok(())
}
pub async fn adb_server_command_close(command_id: String) -> Result<(), AdbServerError> {
    server_owner::command::close(&command_id, Duration::from_secs(7)).await
}
pub async fn adb_server_handshake_create(lease_id: String) -> Result<String, AdbServerError> {
    handshake::create_server(&lease_id)
}

/// 直连 adbd 的协议执行选项；不包含设备记录、健康检测或重连策略。
#[derive(Clone, Debug)]
pub struct AdbConnectOptions {
    pub burst_mode: bool,
    /// AUTH 公钥提示中的注释，最多 1024 个 UTF-8 字节，不允许 NUL、CR 或 LF。
    pub public_key_comment: String,
    pub tcp: AdbTcpOptions,
}
impl Default for AdbConnectOptions {
    fn default() -> Self {
        let defaults = ConnectOptions::default();
        Self {
            burst_mode: defaults.burst_mode,
            public_key_comment: defaults.public_key_comment,
            tcp: AdbTcpOptions::default(),
        }
    }
}
/// TCP socket 选项；USB 连接不应用这些字段，但仍检查输入范围。
#[derive(Clone, Debug)]
pub struct AdbTcpOptions {
    pub nodelay: bool,
    pub keepalive: Option<AdbKeepaliveOptions>,
    /// Android/Linux 的 TCP_USER_TIMEOUT；其他系统显式设置时返回不支持。
    pub user_timeout_ms: Option<u32>,
}
impl Default for AdbTcpOptions {
    fn default() -> Self {
        let defaults = interop_adb::TcpOptions::default();
        Self {
            nodelay: defaults.nodelay,
            keepalive: None,
            user_timeout_ms: None,
        }
    }
}
/// 保守采用各宿主共同支持的范围；时间按整秒向下取整。
#[derive(Clone, Debug)]
pub struct AdbKeepaliveOptions {
    /// 1000..=32767000 毫秒。
    pub idle_ms: u32,
    /// 1000..=32767000 毫秒。
    pub interval_ms: u32,
    /// 1..=127 次。
    pub retries: u32,
}
fn connection_options(
    requested: AdbConnectOptions,
    authorize: bool,
    timeout_ms: u32,
) -> Result<ConnectOptions, AdbConnectionError> {
    if requested.public_key_comment.len() > 1024
        || requested
            .public_key_comment
            .bytes()
            .any(|byte| matches!(byte, 0 | b'\r' | b'\n'))
    {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "adb_invalid_public_key_comment",
        ));
    }
    let keepalive = requested
        .tcp
        .keepalive
        .map(|value| {
            if !(1000..=32_767_000).contains(&value.idle_ms)
                || !(1000..=32_767_000).contains(&value.interval_ms)
                || !(1..=127).contains(&value.retries)
            {
                return Err(AdbConnectionError::new(
                    AdbConnectionErrorCode::InvalidArgument,
                    "adb_invalid_tcp_keepalive",
                ));
            }
            Ok(interop_adb::KeepaliveOptions {
                idle: Duration::from_millis(u64::from(value.idle_ms)),
                interval: Duration::from_millis(u64::from(value.interval_ms)),
                retries: value.retries,
            })
        })
        .transpose()?;
    if requested
        .tcp
        .user_timeout_ms
        .is_some_and(|value| value == 0 || value > i32::MAX as u32)
    {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "adb_invalid_tcp_user_timeout",
        ));
    }
    #[cfg(not(any(target_os = "android", target_os = "linux")))]
    if requested.tcp.user_timeout_ms.is_some() {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::Unsupported,
            "adb_tcp_user_timeout_unsupported",
        ));
    }
    Ok(ConnectOptions {
        request_authorization: authorize,
        burst_mode: requested.burst_mode,
        public_key_comment: requested.public_key_comment,
        tcp: interop_adb::TcpOptions {
            nodelay: requested.tcp.nodelay,
            keepalive,
            user_timeout: requested
                .tcp
                .user_timeout_ms
                .map(|value| Duration::from_millis(u64::from(value))),
        },
        operations: options(timeout_ms, CancellationToken::new()).map_err(|message| {
            AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, message)
        })?,
        ..Default::default()
    })
}

#[derive(Clone)]
pub struct AdbDeviceInfo {
    pub id: String,
    pub serial: String,
    pub state: String,
    pub features: Vec<String>,
}
pub struct AdbEvent {
    pub kind: String,
    pub bytes: Vec<u8>,
    pub exit_code: Option<u32>,
    pub transferred: u64,
    pub done: bool,
}
pub struct AdbServiceEvent {
    /// stdout、stderr、exit 或 transfer；旧 shell 无 exit_code。
    pub kind: String,
    pub bytes: Vec<u8>,
    pub exit_code: Option<u32>,
    pub transferred: u64,
    pub done: bool,
    pub facts: Option<AdbServiceFacts>,
}
struct Connection {
    client: Client,
    serial: String,
    owned: bool,
    /// 实际连接登记的终身身份，不随操作句柄轮换，也不与 Client 的物理身份混用。
    owner: String,
    server_id: Option<String>,
    /// 最近一次确认交付所属的调用方准入域；不由端点、身份或物理 Client 推断。
    admission_scope_key: Option<String>,
    /// 捕获继承 lifetime，普通 Dart 服务继承可撤销的 service_scope。
    scope: CancellationToken,
    service_scope: CancellationToken,
    accepting: bool,
    transition: Arc<AsyncMutex<()>>,
}
impl Connection {
    fn accepts(&self) -> bool {
        self.accepting
            && !self.scope.is_cancelled()
            && !self.service_scope.is_cancelled()
            && !self.client.is_closed()
    }
}

/// 实际观察到的握手；TLS 不证明设备验证了客户端证书，官方 server 不公开认证过程。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbHandshakeKind {
    Unknown,
    Plaintext,
    Auth,
    Tls,
    DelegatedServer,
}
/// 服务打开探测所观察的协议层；官方服务器不公开设备侧 OPEN 时刻。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbOpenProbeLayer {
    DirectAdb,
    OfficialServer,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AdbOpenProbeOutcome {
    Okay,
    Rejected,
    TimedOut,
    NotWritten,
    LocalCapacity,
    Cancelled,
    TransportClosed,
    Io,
    Protocol,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdbOpenProbeFacts {
    pub layer: AdbOpenProbeLayer,
    /// 确认完整请求已经写入本机传输；false 不证明请求永远不会写出。
    pub open_written: bool,
    pub outcome: AdbOpenProbeOutcome,
    /// 不透明快照，只能与同一实际连接的快照比较相等性。
    pub inbound_activity: String,
}
impl From<interop_adb::OpenProbeFacts> for AdbOpenProbeFacts {
    fn from(facts: interop_adb::OpenProbeFacts) -> Self {
        use interop_adb::OpenProbeOutcome as Core;
        Self {
            layer: match facts.layer {
                interop_adb::OpenProbeLayer::DirectAdb => AdbOpenProbeLayer::DirectAdb,
                interop_adb::OpenProbeLayer::OfficialServer => AdbOpenProbeLayer::OfficialServer,
            },
            open_written: facts.open_written,
            outcome: match facts.outcome {
                Core::Okay => AdbOpenProbeOutcome::Okay,
                Core::Rejected => AdbOpenProbeOutcome::Rejected,
                Core::TimedOut => AdbOpenProbeOutcome::TimedOut,
                Core::NotWritten => AdbOpenProbeOutcome::NotWritten,
                Core::LocalCapacity => AdbOpenProbeOutcome::LocalCapacity,
                Core::Cancelled => AdbOpenProbeOutcome::Cancelled,
                Core::TransportClosed => AdbOpenProbeOutcome::TransportClosed,
                Core::Io => AdbOpenProbeOutcome::Io,
                Core::Protocol => AdbOpenProbeOutcome::Protocol,
            },
            inbound_activity: facts.inbound_activity.to_string(),
        }
    }
}

pub struct AdbConnectionFacts {
    /// 同一 Client 的进程内实际连接身份；认领只轮换操作句柄，不改变此值。
    pub connection_id: String,
    /// 实际代理端点；端点相等不能证明官方 server 进程仍是原实例。
    pub server_address: Option<String>,
    /// 原生监督的官方服务器身份；外部服务器不推断此归属。
    pub server_id: Option<String>,
    /// 最近一次 scoped 握手或认领确认时的调用方命名域；不是设备身份或授权证明。
    pub admission_scope_key: Option<String>,
    pub official_server: bool,
    pub transport_id: Option<u64>,
    pub protocol_version: Option<u32>,
    pub max_payload: Option<u32>,
    pub burst_mode: Option<bool>,
    pub closed: bool,
    /// 任意非空入站读取的进程内快照；不是时间、流量或有效帧数量。
    pub inbound_activity: String,
    pub features: Vec<String>,
    pub handshake: AdbHandshakeKind,
    /// 建立此连接时配置的公开身份；独立于实际握手，不表示已经完成身份认证。
    pub configured_identity: Option<AdbIdentityInfo>,
}
pub struct AdbFileMetadata {
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
}
pub struct AdbDirectoryEntry {
    pub name: Vec<u8>,
    pub metadata: AdbFileMetadata,
}
/// 文件机制使用调用方提供的受控 ELF 字节；不读取任何应用资源目录。
pub struct AdbFileHelper {
    pub abi: String,
    pub bytes: Vec<u8>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbFileExecutionKind {
    Stat,
    List,
    Copy,
    Mkdir,
    Rename,
    Delete,
    Commit,
    ReleasePart,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdbFileExecutionStamp {
    /// Opaque dev/inode/ctime identity, absent for legacy SYNC metadata.
    pub identity: Option<String>,
    pub mode: u32,
    pub size: u64,
    pub modified_seconds: i64,
    pub modified_nanos: u32,
    /// SYNC 与当前设备助手只报告秒；零纳秒不能冒充已验证的纳秒精度。
    pub nanosecond_precision: bool,
}
#[derive(Clone)]
pub struct AdbFileExecutionRequest {
    pub kind: AdbFileExecutionKind,
    pub path: Vec<u8>,
    pub destination: Vec<u8>,
    pub local: bool,
    pub follow_storage_alias: bool,
    pub limit: u32,
    pub push: bool,
    pub replace: bool,
    pub expected: Option<AdbFileExecutionStamp>,
    /// 本机暂存文件的精确句柄；提交和释放不能只按路径取得另一操作的描述符。
    pub part_id: String,
    /// 空串表示明确不使用作用域；非空句柄只能用于仍接受操作的同代文件作用域。
    pub scope_id: String,
}
pub struct AdbFileExecutionEntry {
    pub name: Vec<u8>,
    pub stamp: Option<AdbFileExecutionStamp>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub errno: Option<u32>,
}
pub struct AdbFileExecutionEvent {
    /// stat、entries、progress、done 或 error；terminal 事件只交付一次。
    pub kind: String,
    pub entries: Vec<AdbFileExecutionEntry>,
    pub stamp: Option<AdbFileExecutionStamp>,
    pub transferred: u64,
    pub truncated: bool,
    pub save_mode: Option<String>,
    pub part_id: Option<String>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub errno: Option<u32>,
}

pub fn adb_initialize_file_helpers(helpers: Vec<AdbFileHelper>) -> Result<(), String> {
    crate::file_system::initialize_helpers(helpers)
}
/// 先登记精确连接下的操作，再调度实际 I/O；业务任务状态不进入此登记表。
pub async fn adb_file_execute(
    connection_id: String,
    request: AdbFileExecutionRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    crate::file_system::execute(connection_id, request, timeout_ms).await
}
pub async fn adb_file_next(operation_id: String) -> Result<Option<AdbFileExecutionEvent>, String> {
    crate::file_system::next(operation_id).await
}
/// 返回成功只表示本机 worker 和流已回收；不声称远端变更已回滚或远端进程已退出。
pub async fn adb_file_cancel(operation_id: String) -> Result<(), String> {
    crate::file_system::cancel(&operation_id).await
}
/// 同一拥有者重新附着前，撤销旧代操作并等待其本机资源回收；不关闭设备连接。
pub async fn adb_file_scope_attach(owner_key: String) -> Result<String, String> {
    crate::file_system::attach_scope(owner_key).await
}
/// 将文件域交接受准入权限约束；旧权限不能撤销后继文件域。
pub async fn adb_file_scope_attach_scoped(
    owner_key: String,
    scope_id: String,
) -> Result<String, String> {
    admission_scope::attach_file_scope(owner_key, scope_id).await
}
/// 仅撤销此精确作用域；失败时仍可用同一句柄重试清理。
pub async fn adb_file_scope_close(scope_id: String) -> Result<(), String> {
    crate::file_system::close_scope(&scope_id).await
}
/// 本机文件事实不要求设备连接，保留原始名称字节与链接自身元数据。
pub async fn adb_local_file_stat(path: Vec<u8>) -> AdbFileExecutionEvent {
    let mut event = local_file_event("stat");
    match crate::file_metadata::local_stat(&path).await {
        Ok(stamp) => event.stamp = Some(stamp),
        Err(error) => set_local_file_error(&mut event, error),
    }
    event
}
pub async fn adb_local_file_list(path: Vec<u8>, limit: u32) -> AdbFileExecutionEvent {
    let mut event = local_file_event("entries");
    match crate::file_metadata::local_list(&path, limit as usize, &CancellationToken::new()).await {
        Ok((entries, truncated)) => {
            event.entries = entries;
            event.truncated = truncated;
        }
        Err(error) => set_local_file_error(&mut event, error),
    }
    event
}
fn local_file_event(kind: &str) -> AdbFileExecutionEvent {
    AdbFileExecutionEvent {
        kind: kind.into(),
        entries: vec![],
        stamp: None,
        transferred: 0,
        truncated: false,
        save_mode: None,
        part_id: None,
        error_code: None,
        error_message: None,
        errno: None,
    }
}
fn set_local_file_error(event: &mut AdbFileExecutionEvent, error: crate::file_system::FileError) {
    event.kind = "error".into();
    event.errno = error.errno();
    event.error_code = Some(error.code);
    event.error_message = Some(error.message);
}

pub struct AdbReverseMapping {
    pub serial: String,
    pub device_service: String,
    pub host_service: String,
}
pub struct AdbServiceFacts {
    pub metadata: Option<AdbFileMetadata>,
    pub entries: Vec<AdbDirectoryEntry>,
    pub pids: Vec<u32>,
    pub mappings: Vec<AdbReverseMapping>,
    pub device_service: Option<String>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbServiceKind {
    Raw,
    Exec,
    ShellRaw,
    ShellPty,
    Abb,
    AbbExec,
    Cmd,
    Response,
    Reboot,
    TcpIp,
    Usb,
    Jdwp,
    TrackJdwp,
}
/// service 按 kind 表示原始名称、命令、重启目标或 TCP 端口；Binder/cmd 使用 arguments，其他 kind 拒绝无用参数。
pub struct AdbServiceRequest {
    pub kind: AdbServiceKind,
    pub service: String,
    pub arguments: Vec<String>,
    pub max_output: u32,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbSyncKind {
    Stat,
    Lstat,
    List,
    Pull,
    Push,
    PullFile,
    PushFile,
}
#[derive(Clone, Copy)]
pub enum AdbCompression {
    None,
    Brotli,
    Lz4,
    Zstd,
}
pub struct AdbSyncRequest {
    pub kind: AdbSyncKind,
    pub path: Vec<u8>,
    pub local_path: String,
    pub max_bytes: u64,
    pub max_entries: u32,
    pub permissions: u32,
    pub modified_seconds: u32,
    pub compression: AdbCompression,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AdbInputKind {
    Bytes,
    CloseStdin,
    Resize,
    Finish,
}
pub struct AdbInput {
    pub kind: AdbInputKind,
    pub bytes: Vec<u8>,
    pub rows: u16,
    pub columns: u16,
}
#[derive(Clone, Copy)]
pub enum AdbReverseKind {
    Forward,
    List,
    Remove,
    RemoveAll,
}
pub struct AdbReverseRequest {
    pub kind: AdbReverseKind,
    pub device_service: String,
    pub host_address: String,
    pub no_rebind: bool,
}
struct SessionCommand {
    input: AdbInput,
    reply: tokio::sync::oneshot::Sender<Result<(), String>>,
}
fn event(kind: &str, done: bool) -> AdbServiceEvent {
    AdbServiceEvent {
        kind: kind.into(),
        bytes: Vec::new(),
        exit_code: None,
        transferred: 0,
        done,
        facts: None,
    }
}
fn facts() -> AdbServiceFacts {
    AdbServiceFacts {
        metadata: None,
        entries: Vec::new(),
        pids: Vec::new(),
        mappings: Vec::new(),
        device_service: None,
    }
}
fn metadata(value: interop_adb::sync::FileStat) -> AdbFileMetadata {
    AdbFileMetadata {
        mode: value.mode,
        size: value.size,
        modified_seconds: value.modified_seconds,
    }
}

/// 桌面服务始终经过调用方已拥有的官方 server，仅允许数字回环地址；此接口不建立 adbd 传输或执行认证。
pub async fn adb_connect_server(
    server_address: String,
    serial: String,
    timeout_ms: u32,
    handshake_id: Option<String>,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    if cfg!(any(target_os = "android", target_os = "ios")) {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::Unsupported,
            "official_adb_server_is_desktop_only",
        ));
    }
    let address: std::net::SocketAddr = server_address.parse().map_err(|_| {
        AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "invalid_adb_server_address",
        )
    })?;
    if !address.ip().is_loopback() || address.port() == 0 {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "invalid_adb_server_address",
        ));
    }
    let mut options = options(timeout_ms, CancellationToken::new()).map_err(|message| {
        AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, message)
    })?;
    handshake::run_server(handshake_id, address, move |stop, owner| async move {
        options.cancellation = stop;
        let client = Client::connect_server(address, &serial, options)
            .await
            .map_err(AdbConnectionError::from)?;
        server_owner::publish_connection(client, serial, owner, address)
            .map_err(AdbConnectionError::admission)
    })
    .await
}
pub fn adb_connection_facts(connection_id: String) -> Result<AdbConnectionFacts, String> {
    // 清理或认领失败撤销服务准入后，仍允许核对原精确登记的事实。
    let (client, server_id, admission_scope_key) = registry()
        .lock()
        .expect("adb registry")
        .connections
        .get(&connection_id)
        .map(|connection| {
            (
                connection.client.clone(),
                connection.server_id.clone(),
                connection.admission_scope_key.clone(),
            )
        })
        .ok_or("adb_connection_closed")?;
    let direct = !client.uses_server();
    Ok(AdbConnectionFacts {
        connection_id: client.connection_id().to_string(),
        server_address: client.server_address().map(|address| address.to_string()),
        server_id,
        admission_scope_key,
        official_server: !direct,
        transport_id: client.server_transport_id(),
        protocol_version: direct.then_some(client.info().version),
        max_payload: direct.then_some(client.info().max_payload as u32),
        burst_mode: direct.then_some(client.burst_mode()),
        closed: client.is_closed(),
        inbound_activity: client.inbound_activity().to_string(),
        features: client.info().features.iter().cloned().collect(),
        handshake: match client.security().handshake {
            interop_adb::HandshakeKind::Unknown => AdbHandshakeKind::Unknown,
            interop_adb::HandshakeKind::Plaintext => AdbHandshakeKind::Plaintext,
            interop_adb::HandshakeKind::Auth => AdbHandshakeKind::Auth,
            interop_adb::HandshakeKind::Tls => AdbHandshakeKind::Tls,
            interop_adb::HandshakeKind::DelegatedServer => AdbHandshakeKind::DelegatedServer,
        },
        configured_identity: client
            .security()
            .configured_public_key
            .as_deref()
            .map(crate::identity::public_key_info)
            .transpose()?
            .map(Into::into),
    })
}
/// 登记并启动单个服务打开探测；返回值只是操作句柄，不表示 OPEN 已写出。
/// 调用方必须保留句柄并显式 close，关闭失败时用同一句柄重试。
pub async fn adb_open_probe_create(
    connection_id: String,
    service: String,
    timeout_ms: u32,
) -> Result<String, AdbConnectionError> {
    let _ = options(timeout_ms, CancellationToken::new()).map_err(|message| {
        AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, message)
    })?;
    if service.is_empty() || service.len() > 65535 || service.as_bytes().contains(&0) {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "invalid_adb_service",
        ));
    }
    let (id, op, _) = operation_kind(connection_id, true).map_err(AdbConnectionError::admission)?;
    let options = OperationOptions {
        timeout: Duration::from_millis(timeout_ms.into()),
        cancellation: op.stop.clone(),
    };
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let result = op
            .client
            .probe_service_open(&service, options)
            .await
            .map(AdbOpenProbeFacts::from)
            .map_err(AdbConnectionError::from);
        *op.open_probe
            .as_ref()
            .expect("probe operation")
            .lock()
            .expect("probe facts") = Some(result);
    });
    Ok(id)
}

/// 等待探测事实；终态不代表本机关闭帧已经排空，仍须显式 close。
pub async fn adb_open_probe_result(
    probe_id: String,
) -> Result<AdbOpenProbeFacts, AdbConnectionError> {
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(&probe_id)
        .cloned()
        .ok_or_else(|| AdbConnectionError::admission("adb_operation_closed"))?;
    let result = op.open_probe.as_ref().ok_or_else(|| {
        AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, "not_an_open_probe")
    })?;
    // 和普通事件读取共用闲置保护；等待响应不能被回收器当成无人消费。
    let _reader = op
        .events
        .try_lock()
        .map_err(|_| AdbConnectionError::admission("adb_operation_has_a_reader"))?;
    let _reading = op.consumer.reading();
    op.finished.cancelled().await;
    result.lock().expect("probe facts").clone().ok_or_else(|| {
        AdbConnectionError::new(
            AdbConnectionErrorCode::Internal,
            "open_probe_worker_unconfirmed",
        )
    })?
}

/// 取消并确认本次流和本机关闭排序；超时保留登记供同一句柄重试，不关闭共享连接。
pub async fn adb_open_probe_close(
    probe_id: String,
    timeout_ms: u32,
) -> Result<(), AdbConnectionError> {
    let _ = options(timeout_ms, CancellationToken::new()).map_err(|message| {
        AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, message)
    })?;
    {
        let state = registry().lock().expect("adb registry");
        if state
            .operations
            .get(&probe_id)
            .is_some_and(|op| op.open_probe.is_none())
        {
            return Err(AdbConnectionError::new(
                AdbConnectionErrorCode::InvalidArgument,
                "not_an_open_probe",
            ));
        }
    }
    cancel_with_timeout(&probe_id, Duration::from_millis(timeout_ms.into()))
        .await
        .map_err(AdbConnectionError::cleanup)
}

/// 每个操作最多一个 64 KiB 输入及一个在途 writer；写确认仅表示后端接纳字节，不表示远端执行完成。
pub async fn adb_write(operation_id: String, input: AdbInput) -> Result<(), String> {
    if input.bytes.len() > 65536 {
        return Err("adb_input_limit".into());
    }
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(&operation_id)
        .cloned()
        .ok_or("adb_operation_closed")?;
    if op.stop.is_cancelled() {
        return Err("adb_operation_cancelled".into());
    }
    let _writer = op
        .writer
        .try_lock()
        .map_err(|_| "adb_operation_has_a_writer")?;
    let sender = op
        .input
        .lock()
        .expect("adb input")
        .clone()
        .ok_or("adb_operation_has_no_input")?;
    let (reply, receive) = tokio::sync::oneshot::channel();
    let work = async {
        sender
            .send(SessionCommand { input, reply })
            .await
            .map_err(|_| "adb_operation_closed".to_owned())?;
        receive
            .await
            .map_err(|_| "adb_operation_closed".to_owned())?
    };
    tokio::select! { biased; _=op.stop.cancelled()=>Err("adb_operation_cancelled".into()),
    result=tokio::time::timeout(Duration::from_secs(45),work)=>
        match result { Ok(result) => result, Err(_) => {
            op.stop.cancel(); Err("adb_write_timeout".into())
        }} }
}

async fn raw_session(
    stream: interop_adb::AdbStream,
    send: &Events,
    input: &mut mpsc::Receiver<SessionCommand>,
    stop: &CancellationToken,
) -> Result<(), String> {
    let (mut reader, mut writer) = stream.into_split();
    let reading = async {
        let mut bytes = vec![0; 65536];
        loop {
            let count = reader.read(&mut bytes).await.map_err(|e| e.to_string())?;
            let mut result = event(if count == 0 { "end" } else { "data" }, count == 0);
            result.bytes = bytes[..count].to_vec();
            if !send_event(send, Ok(result), stop).await || count == 0 {
                return Ok(());
            }
        }
    };
    let writing = async {
        while let Some(command) = input.recv().await {
            let result = if command.input.kind == AdbInputKind::Bytes {
                writer
                    .write_all(&command.input.bytes)
                    .await
                    .map_err(|e| e.to_string())
            } else {
                Err("adb_raw_service_has_no_half_close_or_terminal_control".into())
            };
            let failed = result.is_err();
            let _ = command.reply.send(result);
            if failed {
                return Err("adb_service_write_failed".into());
            }
        }
        Ok(())
    };
    tokio::select! { result=reading=>result, result=writing=>result }
}
async fn shell_session(
    shell: interop_adb::ShellSession,
    send: &Events,
    input: &mut mpsc::Receiver<SessionCommand>,
    stop: &CancellationToken,
) -> Result<(), String> {
    let (mut reader, mut writer) = shell.into_split();
    let reading = async {
        while let Some(next) = reader.next_event().await.map_err(|e| e.to_string())? {
            let result = match next {
                ShellEvent::Stdout(bytes) => AdbServiceEvent {
                    bytes,
                    ..event("stdout", false)
                },
                ShellEvent::Stderr(bytes) => AdbServiceEvent {
                    bytes,
                    ..event("stderr", false)
                },
                ShellEvent::Exit(code) => AdbServiceEvent {
                    exit_code: Some(code.into()),
                    ..event("exit", true)
                },
            };
            if !send_event(send, Ok(result), stop).await {
                break;
            }
        }
        Ok(())
    };
    let writing = async {
        while let Some(command) = input.recv().await {
            let result = match command.input.kind {
                AdbInputKind::Bytes => writer.write_stdin(&command.input.bytes).await,
                AdbInputKind::CloseStdin => writer.close_stdin().await,
                AdbInputKind::Resize => {
                    writer
                        .resize(command.input.rows, command.input.columns)
                        .await
                }
                AdbInputKind::Finish => Err(interop_adb::Error::InvalidArgument(
                    "use closeStdin for a shell",
                )),
            }
            .map_err(|e| e.to_string());
            let failed = result.is_err();
            let _ = command.reply.send(result);
            if failed {
                return Err("adb_shell_write_failed".into());
            }
        }
        Ok(())
    };
    tokio::select! { result=reading=>result, result=writing=>result }
}

pub async fn adb_service(
    connection_id: String,
    request: AdbServiceRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    if request.max_output == 0 || request.max_output > 16 * 1024 * 1024 {
        return Err("invalid_adb_output_limit".into());
    }
    if !matches!(
        request.kind,
        AdbServiceKind::Abb | AdbServiceKind::AbbExec | AdbServiceKind::Cmd
    ) && !request.arguments.is_empty()
    {
        return Err("unexpected_adb_arguments".into());
    }
    let client = device(&connection_id)?;
    let (id, op, send) = operation(connection_id)?;
    let (input_send, mut input) = mpsc::channel(1);
    *op.input.lock().expect("adb input") = Some(input_send);
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            let kind = request.kind;
            let command = &request.service;
            let argv: Vec<&str> = request.arguments.iter().map(String::as_str).collect();
            match kind {
                AdbServiceKind::Raw | AdbServiceKind::Exec | AdbServiceKind::AbbExec => {
                    let stream = match kind {
                        AdbServiceKind::Raw => client.open(command, options.clone()).await,
                        AdbServiceKind::Exec => client.exec(command, options.clone()).await,
                        _ => client.abb_exec(&argv, options.clone()).await,
                    }
                    .map_err(|e| e.to_string())?;
                    raw_session(stream, &send, &mut input, &op.stop).await?;
                }
                AdbServiceKind::ShellRaw | AdbServiceKind::ShellPty | AdbServiceKind::Abb => {
                    let shell = if kind == AdbServiceKind::Abb {
                        client
                            .abb(&argv, request.max_output as usize, options.clone())
                            .await
                    } else {
                        client
                            .shell_session(
                                command,
                                if kind == AdbServiceKind::ShellPty {
                                    ShellMode::Pty
                                } else {
                                    ShellMode::Raw
                                },
                                request.max_output as usize,
                                options.clone(),
                            )
                            .await
                    }
                    .map_err(|e| e.to_string())?;
                    shell_session(shell, &send, &mut input, &op.stop).await?;
                }
                AdbServiceKind::Cmd => {
                    let result = client
                        .cmd(&argv, request.max_output as usize, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    for (kind, bytes) in [("stdout", result.stdout), ("stderr", result.stderr)] {
                        for chunk in bytes.chunks(65536) {
                            if !send_event(
                                &send,
                                Ok(AdbServiceEvent {
                                    bytes: chunk.to_vec(),
                                    ..event(kind, false)
                                }),
                                &op.stop,
                            )
                            .await
                            {
                                return Ok(());
                            }
                        }
                    }
                    send_event(
                        &send,
                        Ok(AdbServiceEvent {
                            exit_code: result.exit_code,
                            ..event("exit", true)
                        }),
                        &op.stop,
                    )
                    .await;
                }
                AdbServiceKind::Response | AdbServiceKind::TcpIp | AdbServiceKind::Usb => {
                    let bytes = match kind {
                        AdbServiceKind::TcpIp => {
                            client
                                .tcpip(
                                    command.parse().map_err(|_| "invalid_adb_tcp_port")?,
                                    options.clone(),
                                )
                                .await
                        }
                        AdbServiceKind::Usb => client.usb(options.clone()).await,
                        _ => {
                            client
                                .service_response(
                                    command,
                                    request.max_output as usize,
                                    options.clone(),
                                )
                                .await
                        }
                    }
                    .map_err(|e| e.to_string())?;
                    let chunks = bytes.chunks(65536).collect::<Vec<_>>();
                    if chunks.is_empty() {
                        send_event(&send, Ok(event("response", true)), &op.stop).await;
                    }
                    for (index, chunk) in chunks.iter().enumerate() {
                        send_event(
                            &send,
                            Ok(AdbServiceEvent {
                                bytes: chunk.to_vec(),
                                ..event("response", index + 1 == chunks.len())
                            }),
                            &op.stop,
                        )
                        .await;
                    }
                }
                AdbServiceKind::Reboot => {
                    let target = match command.as_str() {
                        "" => interop_adb::RebootTarget::System,
                        "recovery" => interop_adb::RebootTarget::Recovery,
                        "bootloader" => interop_adb::RebootTarget::Bootloader,
                        "fastboot" => interop_adb::RebootTarget::Fastboot,
                        "sideload" => interop_adb::RebootTarget::Sideload,
                        _ => return Err("invalid_adb_reboot_target".into()),
                    };
                    client
                        .reboot(target, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    send_event(&send, Ok(event("done", true)), &op.stop).await;
                }
                AdbServiceKind::Jdwp | AdbServiceKind::TrackJdwp => {
                    let mut tracker = client
                        .track_jdwp(request.max_output as usize, options.clone())
                        .await
                        .map_err(|e| e.to_string())?;
                    while let Some(pids) = tracker.next_event().await.map_err(|e| e.to_string())? {
                        let mut result = event("jdwp", kind == AdbServiceKind::Jdwp);
                        let mut value = facts();
                        value.pids = pids.into_iter().map(|pid| pid.get()).collect();
                        result.facts = Some(value);
                        if !send_event(&send, Ok(result), &op.stop).await
                            || kind == AdbServiceKind::Jdwp
                        {
                            break;
                        }
                    }
                }
            }
            Ok::<(), String>(())
        };
        let result = tokio::select! { _=op.stop.cancelled()=>return,
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_service_timeout".into())) };
        if let Err(error) = result {
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}

fn compression(value: AdbCompression) -> interop_adb::sync::Compression {
    match value {
        AdbCompression::None => interop_adb::sync::Compression::None,
        AdbCompression::Brotli => interop_adb::sync::Compression::Brotli,
        AdbCompression::Lz4 => interop_adb::sync::Compression::Lz4,
        AdbCompression::Zstd => interop_adb::sync::Compression::Zstd,
    }
}
/// 只执行 SYNC 协议。路径为原始字节，目录列表和队列有界；冲突决策、目录递归与持久任务状态不属于此接口。
pub async fn adb_sync(
    connection_id: String,
    request: AdbSyncRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    if request.max_entries == 0 || request.max_entries > 100_000 || request.permissions > 0o777 {
        return Err("invalid_adb_sync_limits".into());
    }
    let client = device(&connection_id)?;
    let path = interop_adb::sync::RemotePath::new(&request.path).map_err(|e| e.to_string())?;
    let (id, op, send) = operation(connection_id)?;
    let (input_send, mut input) = mpsc::channel(1);
    *op.input.lock().expect("adb input") = Some(input_send);
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let _completion = completion;
        let mut created = false;
        let work = async {
            let mut sync = client
                .sync(options.clone())
                .await
                .map_err(|e| e.to_string())?;
            let mut result = event("sync", true);
            let mut value = facts();
            match request.kind {
                AdbSyncKind::Stat | AdbSyncKind::Lstat => {
                    let stat = if request.kind == AdbSyncKind::Stat {
                        sync.stat(&path).await
                    } else {
                        sync.lstat(&path).await
                    };
                    value.metadata = Some(metadata(stat.map_err(|e| e.to_string())?));
                    result.facts = Some(value);
                }
                AdbSyncKind::List => {
                    let entries = sync
                        .list(&path, request.max_entries as usize)
                        .await
                        .map_err(|e| e.to_string())?;
                    // 发送有界分页，不把整个目录变成 Dart JSON 块。
                    for page in entries.chunks(64) {
                        let mut value = facts();
                        value.entries = page
                            .iter()
                            .map(|entry| AdbDirectoryEntry {
                                name: entry.name.clone(),
                                metadata: AdbFileMetadata {
                                    mode: entry.stat.mode,
                                    size: entry.stat.size,
                                    modified_seconds: entry.stat.modified_seconds,
                                },
                            })
                            .collect();
                        if !send_event(
                            &send,
                            Ok(AdbServiceEvent {
                                facts: Some(value),
                                ..event("entries", false)
                            }),
                            &op.stop,
                        )
                        .await
                        {
                            return Ok(());
                        }
                    }
                }
                AdbSyncKind::PullFile | AdbSyncKind::PushFile => {
                    result.transferred = if request.kind == AdbSyncKind::PushFile {
                        let mut file = tokio::fs::File::open(&request.local_path)
                            .await
                            .map_err(|e| e.to_string())?;
                        sync.push_compressed(
                            &path,
                            &mut file,
                            request.permissions,
                            request.modified_seconds,
                            request.max_bytes,
                            compression(request.compression),
                        )
                        .await
                        .map_err(|e| e.to_string())?
                    } else {
                        let mut file = tokio::fs::OpenOptions::new()
                            .write(true)
                            .create_new(true)
                            .open(&request.local_path)
                            .await
                            .map_err(|e| e.to_string())?;
                        created = true;
                        let count = sync
                            .pull_compressed(
                                &path,
                                &mut file,
                                request.max_bytes,
                                compression(request.compression),
                            )
                            .await
                            .map_err(|e| e.to_string())?;
                        file.flush().await.map_err(|e| e.to_string())?;
                        count
                    };
                }
                AdbSyncKind::Push => {
                    let (mut reader, mut writer) = tokio::io::duplex(65536);
                    let transfer = async {
                        sync.push_compressed(
                            &path,
                            &mut reader,
                            request.permissions,
                            request.modified_seconds,
                            request.max_bytes,
                            compression(request.compression),
                        )
                        .await
                        .map_err(|e| e.to_string())
                    };
                    let feeding = async {
                        while let Some(command) = input.recv().await {
                            let finished = command.input.kind == AdbInputKind::Finish;
                            let result = match command.input.kind {
                                AdbInputKind::Bytes => writer
                                    .write_all(&command.input.bytes)
                                    .await
                                    .map_err(|e| e.to_string()),
                                AdbInputKind::Finish => {
                                    writer.shutdown().await.map_err(|e| e.to_string())
                                }
                                _ => Err("invalid_sync_input_control".into()),
                            };
                            let failed = result.is_err();
                            let _ = command.reply.send(result);
                            if failed {
                                return Err("adb_sync_input_failed".to_owned());
                            }
                            if finished {
                                return Ok(());
                            }
                        }
                        Err("adb_sync_input_closed_without_finish".into())
                    };
                    result.transferred = tokio::try_join!(transfer, feeding)?.0;
                }
                AdbSyncKind::Pull => {
                    let (mut reader, mut writer) = tokio::io::duplex(65536);
                    let transfer = async {
                        let count = sync
                            .pull_compressed(
                                &path,
                                &mut writer,
                                request.max_bytes,
                                compression(request.compression),
                            )
                            .await
                            .map_err(|e| e.to_string())?;
                        writer.shutdown().await.map_err(|e| e.to_string())?;
                        Ok::<_, String>(count)
                    };
                    let draining = async {
                        let mut bytes = vec![0; 65536];
                        loop {
                            let count = reader.read(&mut bytes).await.map_err(|e| e.to_string())?;
                            if count == 0 {
                                break;
                            }
                            if !send_event(
                                &send,
                                Ok(AdbServiceEvent {
                                    bytes: bytes[..count].to_vec(),
                                    ..event("data", false)
                                }),
                                &op.stop,
                            )
                            .await
                            {
                                return Err("adb_sync_reader_closed".into());
                            }
                        }
                        Ok::<_, String>(())
                    };
                    result.transferred = tokio::try_join!(transfer, draining)?.0;
                }
            }
            send_event(&send, Ok(result), &op.stop).await;
            Ok::<(), String>(())
        };
        let result = tokio::select! {_=op.stop.cancelled()=>Err("adb_sync_cancelled".into()),
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_sync_timeout".into()))};
        if let Err(error) = result {
            if created {
                let _ = tokio::fs::remove_file(&request.local_path).await;
            }
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}
fn reverse_socket(service: &str) -> Result<interop_adb::ReverseSocket, String> {
    let (kind, value) = service.split_once(':').ok_or("invalid_reverse_socket")?;
    match kind {
        "tcp" => Ok(interop_adb::ReverseSocket::Tcp(
            value.parse().map_err(|_| "invalid_reverse_port")?,
        )),
        "localabstract" => Ok(interop_adb::ReverseSocket::LocalAbstract(value.into())),
        "localfilesystem" => Ok(interop_adb::ReverseSocket::LocalFilesystem(value.into())),
        _ => Err("unsupported_reverse_socket".into()),
    }
}
fn reverse_service(socket: interop_adb::ReverseSocket) -> String {
    match socket {
        interop_adb::ReverseSocket::Tcp(port) => format!("tcp:{port}"),
        interop_adb::ReverseSocket::LocalAbstract(name) => format!("localabstract:{name}"),
        interop_adb::ReverseSocket::LocalFilesystem(name) => format!("localfilesystem:{name}"),
    }
}
pub async fn adb_reverse(
    connection_id: String,
    request: AdbReverseRequest,
    timeout_ms: u32,
) -> Result<String, String> {
    let client = device(&connection_id)?;
    let _ = options(timeout_ms, CancellationToken::new())?;
    let (id, op, send) = operation(connection_id)?;
    let options = options(timeout_ms, op.stop.clone())?;
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            let mut value = facts();
            match request.kind {
                AdbReverseKind::Forward => {
                    let destination = request
                        .host_address
                        .parse()
                        .map_err(|_| "invalid_reverse_destination")?;
                    let binding = client
                        .reverse_forward(
                            &reverse_socket(&request.device_service)?,
                            destination,
                            request.no_rebind,
                            options.clone(),
                        )
                        .await
                        .map_err(|e| e.to_string())?;
                    value.device_service = Some(reverse_service(binding.device));
                }
                AdbReverseKind::List => {
                    value.mappings = client
                        .reverse_list(options.clone())
                        .await
                        .map_err(|e| e.to_string())?
                        .into_iter()
                        .map(|m| AdbReverseMapping {
                            serial: m.serial,
                            device_service: m.device_service,
                            host_service: m.host_service,
                        })
                        .collect();
                }
                AdbReverseKind::Remove => client
                    .reverse_remove(&reverse_socket(&request.device_service)?, options.clone())
                    .await
                    .map_err(|e| e.to_string())?,
                AdbReverseKind::RemoveAll => client
                    .reverse_remove_all(options.clone())
                    .await
                    .map_err(|e| e.to_string())?,
            }
            send_event(
                &send,
                Ok(AdbServiceEvent {
                    facts: Some(value),
                    ..event("reverse", true)
                }),
                &op.stop,
            )
            .await;
            Ok::<(), String>(())
        };
        let result = tokio::select! {_=op.stop.cancelled()=>return,
        result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_reverse_timeout".into()))};
        if let Err(error) = result {
            send_event(&send, Err(error), &op.stop).await;
        }
    });
    Ok(id)
}

struct Operation {
    connection: String,
    client: Client,
    stop: CancellationToken,
    finished: CancellationToken,
    cleanup: AsyncMutex<()>,
    events: AsyncMutex<mpsc::Receiver<Result<AdbServiceEvent, String>>>,
    consumer: ConsumerActivity,
    input: Mutex<Option<mpsc::Sender<SessionCommand>>>,
    writer: AsyncMutex<()>,
    open_probe: Option<Mutex<Option<Result<AdbOpenProbeFacts, AdbConnectionError>>>>,
}
#[flutter_rust_bridge::frb(ignore)]
struct MobileAdbRegistry {
    connections: HashMap<String, Connection>,
    operations: HashMap<String, Arc<Operation>>,
    handshakes: HashMap<String, handshake::Registration>,
    admission_scopes: HashMap<String, admission_scope::Scope>,
    admission_gates: HashMap<String, Arc<AsyncMutex<()>>>,
    closing: bool,
    servers: HashMap<String, server_owner::ServerRecord>,
    server_commands: HashMap<String, server_owner::command::CommandRecord>,
}
static REGISTRY: OnceLock<Mutex<MobileAdbRegistry>> = OnceLock::new();
fn registry() -> &'static Mutex<MobileAdbRegistry> {
    REGISTRY.get_or_init(|| {
        Mutex::new(MobileAdbRegistry {
            connections: HashMap::new(),
            operations: HashMap::new(),
            handshakes: HashMap::new(),
            admission_scopes: HashMap::new(),
            admission_gates: HashMap::new(),
            closing: false,
            servers: HashMap::new(),
            server_commands: HashMap::new(),
        })
    })
}
fn mobile() -> Result<(), String> {
    if cfg!(any(target_os = "android", target_os = "ios")) {
        Ok(())
    } else {
        Err("direct_mobile_adb_is_unavailable_on_desktop".into())
    }
}
fn options(timeout_ms: u32, stop: CancellationToken) -> Result<OperationOptions, String> {
    if timeout_ms == 0 || timeout_ms > 86_400_000 {
        return Err("invalid_adb_timeout".into());
    }
    Ok(OperationOptions {
        timeout: Duration::from_millis(timeout_ms.into()),
        cancellation: stop,
    })
}
/// 预留一个单次握手身份；必须在发起连接或配对之前取得。
pub async fn adb_handshake_create() -> Result<String, AdbConnectionError> {
    handshake::create().map_err(AdbConnectionError::admission)
}

/// 调用方命名的技术准入域；不保存连接策略或设备记录。
#[derive(Clone, Debug)]
pub struct AdbAdmissionScopeInfo {
    pub scope_key: String,
    pub scope_id: String,
    pub accepting: bool,
}

pub fn adb_admission_scope_inspect(
    scope_key: String,
) -> Result<Option<AdbAdmissionScopeInfo>, String> {
    admission_scope::inspect(&scope_key)
}

/// 以旧权限比较并交换；首次创建时 expected_scope_id 必须为空。
pub async fn adb_admission_scope_attach(
    scope_key: String,
    expected_scope_id: Option<String>,
    timeout_ms: u32,
) -> Result<AdbAdmissionScopeInfo, String> {
    let timeout = options(timeout_ms, CancellationToken::new())?.timeout;
    admission_scope::attach(scope_key, expected_scope_id, timeout).await
}

pub async fn adb_admission_scope_close(scope_id: String, timeout_ms: u32) -> Result<(), String> {
    let timeout = options(timeout_ms, CancellationToken::new())?.timeout;
    admission_scope::close(&scope_id, timeout).await
}

pub async fn adb_scoped_handshake_create(scope_id: String) -> Result<String, AdbConnectionError> {
    handshake::create_scoped(&scope_id).map_err(AdbConnectionError::admission)
}

/// Dart 已取得精确关闭权后确认交付；确认前连接不可开始服务或捕获。
pub async fn adb_handshake_connection_confirm(
    handshake_id: String,
    connection_id: String,
) -> Result<(), AdbConnectionError> {
    handshake::confirm_connection(&handshake_id, &connection_id)
}

/// 在同一准入域内认领现存 Client；未交付的新操作句柄仍受握手交接回收保护。
pub async fn adb_scoped_connection_claim(
    connection_id: String,
    handshake_id: String,
) -> Result<AdbDeviceInfo, String> {
    handshake::require_scope(&handshake_id)?;
    let result_handshake = handshake_id.clone();
    handshake::run(Some(handshake_id), move |_| async move {
        connection_claim::claim_registered(
            &connection_id,
            Duration::from_secs(7),
            Some(&result_handshake),
        )
        .await
    })
    .await
}

/// 只发出取消信号；成功不表示握手、身份磁盘任务或 socket 已释放。
pub async fn adb_handshake_cancel(handshake_id: String) -> Result<(), AdbConnectionError> {
    handshake::cancel(&handshake_id);
    Ok(())
}

/// 撤销单次准入并等待实际握手退出；超时保留身份，允许再次等待清理。
pub async fn adb_handshake_close(handshake_id: String) -> Result<(), AdbConnectionError> {
    close_handshake_with_timeout(&handshake_id, Duration::from_secs(7)).await
}

async fn close_handshake_with_timeout(
    id: &str,
    timeout: Duration,
) -> Result<(), AdbConnectionError> {
    handshake::close(id, timeout)
        .await
        .map_err(AdbConnectionError::cleanup)
}
/// 创建或验证调用方指定的持久授权身份；已有损坏文件、符号链接或过宽权限均拒绝覆盖。
pub async fn adb_initialize_identity(identity_path: String) -> Result<(), String> {
    crate::identity::prepare(identity_path).await.map(|_| ())
}

/// 指纹保留版本和输入编码；不向调用方返回私钥材料。
pub struct AdbIdentityInfo {
    pub fingerprint: String,
    pub fingerprint_algorithm: String,
    pub fingerprint_input: String,
    pub bits: u32,
    pub exponent: u32,
}
impl From<crate::identity::IdentityInfo> for AdbIdentityInfo {
    fn from(value: crate::identity::IdentityInfo) -> Self {
        Self {
            fingerprint: value.fingerprint,
            fingerprint_algorithm: value.fingerprint_algorithm,
            fingerprint_input: value.fingerprint_input,
            bits: value.bits,
            exponent: value.exponent,
        }
    }
}
pub enum AdbIdentityCommitState {
    Committed,
    Unchanged,
    Unknown,
}
/// 发布后的存储失败返回未知回执，不能推断旧身份未改变或自动重试。
pub struct AdbIdentityCommitReceipt {
    pub state: AdbIdentityCommitState,
    pub identity: Option<AdbIdentityInfo>,
    pub error: Option<String>,
}
pub async fn adb_inspect_identity(
    identity_path: String,
) -> Result<Option<AdbIdentityInfo>, String> {
    crate::identity::inspect(identity_path)
        .await
        .map(|value| value.map(Into::into))
}
pub fn adb_validate_identity(pem: String) -> Result<AdbIdentityInfo, String> {
    crate::identity::validate(&pem).map(Into::into)
}
pub async fn adb_replace_identity(
    identity_path: String,
    pem: String,
    expected_fingerprint: Option<String>,
) -> Result<AdbIdentityCommitReceipt, String> {
    let receipt = crate::identity::replace(identity_path, pem, expected_fingerprint).await?;
    Ok(AdbIdentityCommitReceipt {
        state: match receipt.state {
            crate::identity::IdentityCommitState::Committed => AdbIdentityCommitState::Committed,
            crate::identity::IdentityCommitState::Unchanged => AdbIdentityCommitState::Unchanged,
            crate::identity::IdentityCommitState::Unknown => AdbIdentityCommitState::Unknown,
        },
        identity: receipt.identity.map(Into::into),
        error: receipt.error,
    })
}
async fn identity(path: &str) -> Result<Identity, String> {
    crate::identity::prepare(path.to_owned()).await
}

async fn connection_identity(
    path: &str,
    stop: &CancellationToken,
) -> Result<Identity, AdbConnectionError> {
    // 等待真实磁盘工作退出后再报告取消，不能遗失身份写入任务。
    let identity = identity(path)
        .await
        .map_err(|message| AdbConnectionError::new(AdbConnectionErrorCode::Identity, message))?;
    if stop.is_cancelled() {
        return Err(interop_adb::Error::Cancelled.into());
    }
    Ok(identity)
}
#[flutter_rust_bridge::frb(ignore)]
pub fn device(id: &str) -> Result<Client, String> {
    registry()
        .lock()
        .expect("adb registry")
        .connections
        .get(id)
        .filter(|connection| connection.accepts())
        .map(|c| c.client.clone())
        .ok_or_else(|| "adb_connection_closed".into())
}
#[cfg(test)]
fn insert(client: Client, serial: String) -> Result<AdbDeviceInfo, String> {
    insert_connection(client, serial, true)
}
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn admit_file<T>(
    id: &str,
    admit: impl FnOnce(Client, CancellationToken) -> Result<T, String>,
) -> Result<T, String> {
    // 与 disconnect 的删除共享同一短锁，不能在其清理快照之后登记旧连接的操作。
    let state = registry().lock().expect("adb registry");
    let connection = state.connections.get(id).ok_or("adb_connection_closed")?;
    if !connection.accepts() {
        return Err("adb_connection_closed".into());
    }
    admit(
        connection.client.clone(),
        connection.service_scope.child_token(),
    )
}

/// 在同一个短锁内校验操作句柄并登记捕获；认领后不能迟到登记旧句柄的捕获。
#[flutter_rust_bridge::frb(ignore)]
pub fn admit_capture<T>(
    id: &str,
    admit: impl FnOnce(Client, CancellationToken, String) -> Result<T, String>,
) -> Result<T, String> {
    let state = registry().lock().expect("adb registry");
    let connection = state.connections.get(id).ok_or("adb_connection_closed")?;
    if !connection.accepts() {
        return Err("adb_connection_closed".into());
    }
    admit(
        connection.client.clone(),
        connection.scope.child_token(),
        connection.owner.clone(),
    )
}

/// 在操作句柄仍对应原登记时同步回收捕获；回调不能等待或反向获取 ADB 登记锁。
#[flutter_rust_bridge::frb(ignore)]
pub fn with_connection_owner<T>(id: &str, retire: impl FnOnce(&str) -> T) -> Option<T> {
    let state = registry().lock().expect("adb registry");
    state
        .connections
        .get(id)
        .map(|connection| retire(&connection.owner))
}
#[flutter_rust_bridge::frb(ignore)]
pub fn insert_connection(
    client: Client,
    serial: String,
    owned: bool,
) -> Result<AdbDeviceInfo, String> {
    let mut state = registry().lock().expect("adb registry");
    // 同一物理 Client 的借用登记保留服务器归属，但有独立 entry lifetime。
    let server_id = state
        .connections
        .values()
        .find(|entry| entry.client.same_connection(&client))
        .and_then(|entry| entry.server_id.clone());
    insert_locked(&mut state, client, serial, owned, server_id)
}
fn insert_locked(
    state: &mut MobileAdbRegistry,
    client: Client,
    serial: String,
    owned: bool,
    server_id: Option<String>,
) -> Result<AdbDeviceInfo, String> {
    if state.closing || state.connections.len() >= 64 {
        if owned {
            client.close();
        }
        return Err(if state.closing {
            "adb_host_closing"
        } else {
            "adb_connection_limit"
        }
        .into());
    }
    let id = uuid::Uuid::new_v4().to_string();
    let info = AdbDeviceInfo {
        id: id.clone(),
        serial: serial.clone(),
        state: "device".into(),
        features: client.info().features.iter().cloned().collect(),
    };
    let scope = server_id
        .as_ref()
        .and_then(|id| state.servers.get(id))
        .map(|server| server.owner.lifetime.child_token())
        .unwrap_or_default();
    state.connections.insert(
        id,
        Connection {
            client,
            serial,
            owned,
            owner: info.id.clone(),
            server_id,
            admission_scope_key: None,
            service_scope: scope.child_token(),
            scope,
            accepting: true,
            transition: Arc::new(AsyncMutex::new(())),
        },
    );
    Ok(info)
}

/// 使用调用方的持久身份，不逐调用创建密钥。
pub async fn adb_connect_tcp(
    address: String,
    identity_path: String,
    require_tls: bool,
    authorize: bool,
    timeout_ms: u32,
    options: AdbConnectOptions,
    handshake_id: Option<String>,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    mobile()
        .map_err(|message| AdbConnectionError::new(AdbConnectionErrorCode::Unsupported, message))?;
    connect_tcp(
        address,
        identity_path,
        require_tls,
        authorize,
        timeout_ms,
        options,
        handshake_id,
    )
    .await
}
async fn connect_tcp(
    address: String,
    identity_path: String,
    require_tls: bool,
    authorize: bool,
    timeout_ms: u32,
    requested: AdbConnectOptions,
    handshake_id: Option<String>,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    // 全部纯校验先完成，非法参数不能创建密钥、目录或接触端点。
    let mut options = connection_options(requested, authorize, timeout_ms)?;
    let result_handshake = handshake_id.clone();
    handshake::run_connection(handshake_id, move |stop| async move {
        options.operations.cancellation = stop.clone();
        let identity = connection_identity(&identity_path, &stop).await?;
        let tls = interop_adb::wireless::TlsConfig::experimental_rustcrypto(&identity)
            .map_err(AdbConnectionError::from)?;
        options.identity = Some(identity);
        options.tls = Some(tls);
        options.tls_policy = if require_tls {
            TlsPolicy::Required
        } else {
            TlsPolicy::Optional
        };
        let client = Client::connect_tcp(&address, options)
            .await
            .map_err(AdbConnectionError::from)?;
        handshake::publish_connection(result_handshake.as_deref(), client, address)
    })
    .await
}
/// 断开前保持平台拥有的 UsbDeviceConnection 存活；TCP 字段不应用于 USB。
pub async fn adb_connect_usb_fd(
    fd: i32,
    serial: String,
    identity_path: String,
    authorize: bool,
    timeout_ms: u32,
    options: AdbConnectOptions,
    handshake_id: Option<String>,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    mobile()
        .map_err(|message| AdbConnectionError::new(AdbConnectionErrorCode::Unsupported, message))?;
    let options = connection_options(options, authorize, timeout_ms)?;
    if fd < 0 {
        return Err(AdbConnectionError::new(
            AdbConnectionErrorCode::InvalidArgument,
            "invalid_adb_usb_fd",
        ));
    }
    #[cfg(target_os = "android")]
    {
        use std::os::fd::{AsFd, BorrowedFd};
        let mut options = options;
        // 在交给独立 worker 前复制平台 FD，原调用等待结束后不能借用已复用的编号。
        let owned = unsafe { BorrowedFd::borrow_raw(fd) }
            .try_clone_to_owned()
            .map_err(|error| AdbConnectionError::from(interop_adb::Error::from(error)))?;
        let result_handshake = handshake_id.clone();
        handshake::run_connection(handshake_id, move |stop| async move {
            options.operations.cancellation = stop.clone();
            options.identity = Some(connection_identity(&identity_path, &stop).await?);
            // adapter 再取得自身运行期副本；本地 owned 覆盖准备身份期间的生命周期。
            let transport =
                interop_adb::usb::from_authorized_fd(owned.as_fd(), options.operations.clone())
                    .await
                    .map_err(AdbConnectionError::from)?;
            let client = Client::connect_transport(transport, options)
                .await
                .map_err(AdbConnectionError::from)?;
            handshake::publish_connection(result_handshake.as_deref(), client, serial)
        })
        .await
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (fd, serial, identity_path, options, handshake_id);
        Err(AdbConnectionError::new(
            AdbConnectionErrorCode::Unsupported,
            "usb_requires_android_platform_authorization",
        ))
    }
}
pub async fn adb_pair(
    address: String,
    password: String,
    identity_path: String,
    timeout_ms: u32,
    handshake_id: Option<String>,
) -> Result<String, AdbConnectionError> {
    mobile()
        .map_err(|message| AdbConnectionError::new(AdbConnectionErrorCode::Unsupported, message))?;
    pair(address, password, identity_path, timeout_ms, handshake_id).await
}

async fn pair(
    address: String,
    password: String,
    identity_path: String,
    timeout_ms: u32,
    handshake_id: Option<String>,
) -> Result<String, AdbConnectionError> {
    // 与协议库的密码约束一致；纯校验必须先于身份准备和网络连接。
    let mut options = options(timeout_ms, CancellationToken::new()).map_err(|message| {
        AdbConnectionError::new(AdbConnectionErrorCode::InvalidArgument, message)
    })?;
    if password.is_empty() || password.len() > 1024 || password.as_bytes().contains(&0) {
        return Err(interop_adb::Error::InvalidArgument("invalid pairing password").into());
    }
    handshake::run_connection(handshake_id, move |stop| async move {
        options.cancellation = stop.clone();
        let identity = connection_identity(&identity_path, &stop).await?;
        let tls = interop_adb::wireless::TlsConfig::experimental_rustcrypto(&identity)
            .map_err(AdbConnectionError::from)?;
        let deadline = tokio::time::Instant::now() + options.timeout;
        let stream = tokio::select! {
            biased;
            _ = stop.cancelled() => return Err(interop_adb::Error::Cancelled.into()),
            result = tokio::time::timeout(options.timeout, tokio::net::TcpStream::connect(address)) => {
                result.map_err(|_| AdbConnectionError::connecting(interop_adb::Error::Timeout))?.map_err(|error| AdbConnectionError::connecting(error.into()))?
            }
        };
        // 建连和配对交换共用原预算，不给第二阶段重新分配完整 timeout。
        options.timeout = deadline.saturating_duration_since(tokio::time::Instant::now());
        if options.timeout.is_zero() {
            return Err(interop_adb::Error::Timeout.into());
        }
        // 成功表示对端实际完成配对；本机取消不回滚对端可能已保存的信任。
        interop_adb::wireless::pair(stream, &password, &identity, &tls, "adb", &options)
            .await
            .map(|r| r.guid)
            .map_err(AdbConnectionError::from)
    })
    .await
}
pub fn adb_devices() -> Vec<AdbDeviceInfo> {
    registry()
        .lock()
        .expect("adb registry")
        .connections
        .iter()
        .map(|(id, c)| AdbDeviceInfo {
            id: id.clone(),
            serial: c.serial.clone(),
            state: if !c.accepts() { "offline" } else { "device" }.into(),
            features: c.client.info().features.iter().cloned().collect(),
        })
        .collect()
}
/// 认领原 Client：撤销旧操作并换发新操作句柄，保留捕获 lifetime；失败保留原句柄供重试。
pub async fn adb_claim_connection(connection_id: String) -> Result<AdbDeviceInfo, String> {
    connection_claim::claim(&connection_id, Duration::from_secs(7)).await
}
/// 先同步撤销准入；只有自有 worker 和本机关闭帧均释放后才删除连接登记。
pub async fn adb_disconnect(connection_id: String) -> Result<(), AdbConnectionError> {
    disconnect_with_timeout(&connection_id, Duration::from_secs(7))
        .await
        .map_err(AdbConnectionError::cleanup)
}
async fn disconnect_with_timeout(connection_id: &str, timeout: Duration) -> Result<(), String> {
    let gate = {
        let state = registry().lock().expect("adb registry");
        let Some(connection) = state.connections.get(connection_id) else {
            return Ok(());
        };
        connection.transition.clone()
    };
    tokio::time::timeout(timeout, async {
        let _transition = gate.lock().await;
        disconnect_locked(connection_id, timeout).await
    })
    .await
    .map_err(|_| "adb_connection_cleanup_unconfirmed".to_owned())?
}

async fn disconnect_locked(connection_id: &str, timeout: Duration) -> Result<(), String> {
    let (client, owned, operations) = {
        let mut state = registry().lock().expect("adb registry");
        // 等待转换锁后再核验旧 key；它可能已被认领者替换，不能取消后继的 lifetime。
        let Some(connection) = state.connections.get_mut(connection_id) else {
            return Ok(());
        };
        connection.accepting = false;
        connection.service_scope.cancel();
        connection.scope.cancel();
        let client = connection.client.clone();
        let owned = connection.owned;
        let operations = state
            .operations
            .iter()
            .filter(|(_, op)| op.connection == connection_id)
            .map(|(id, op)| (id.clone(), op.clone()))
            .collect::<Vec<_>>();
        for (_, op) in &operations {
            op.stop.cancel();
        }
        (client, owned, operations)
    };
    tokio::time::timeout(timeout, async {
        // 清理某一项失败不妨碍其他已撤销资源回收；失败项仍保留原句柄供重试。
        let mut failure = crate::file_system::cancel_connection(connection_id)
            .await
            .err();
        for (id, _) in operations {
            if let Err(error) = cancel_with_timeout(&id, timeout).await {
                failure.get_or_insert(error);
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        flush_client(&client, timeout).await?;
        if owned {
            client
                .close_and_wait(OperationOptions {
                    timeout,
                    cancellation: CancellationToken::new(),
                })
                .await
                .map_err(|error| error.to_string())?;
        }
        registry()
            .lock()
            .expect("adb registry")
            .connections
            .remove(connection_id);
        Ok(())
    })
    .await
    .map_err(|_| "adb_connection_cleanup_unconfirmed".to_owned())?
}
struct Completion(CancellationToken);
impl Drop for Completion {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
type Events = mpsc::Sender<Result<AdbServiceEvent, String>>;
fn operation(connection: String) -> Result<(String, Arc<Operation>, Events), String> {
    operation_kind(connection, false)
}
fn operation_kind(
    connection: String,
    probe: bool,
) -> Result<(String, Arc<Operation>, Events), String> {
    let mut state = registry().lock().expect("adb registry");
    let owner = state
        .connections
        .get(&connection)
        .ok_or("adb_connection_closed")?;
    if !owner.accepts() {
        return Err("adb_connection_closed".into());
    }
    let client = owner.client.clone();
    let stop = owner.service_scope.child_token();
    if state.operations.len() >= 128 {
        return Err("adb_operation_limit".into());
    }
    let (send, events) = mpsc::channel(1);
    let op = Arc::new(Operation {
        connection,
        client,
        stop,
        finished: CancellationToken::new(),
        cleanup: AsyncMutex::new(()),
        events: AsyncMutex::new(events),
        consumer: ConsumerActivity::new(),
        input: Mutex::new(None),
        writer: AsyncMutex::new(()),
        open_probe: probe.then(|| Mutex::new(None)),
    });
    let id = uuid::Uuid::new_v4().to_string();
    state.operations.insert(id.clone(), op.clone());
    // 无消费者的操作不能永久占用句柄；读取等待及两次拉取间的完整闲置期限由同一活动状态核验。
    let orphan_id = id.clone();
    let weak = Arc::downgrade(&op);
    tokio::spawn(reclaim_operation(
        orphan_id,
        weak,
        Duration::from_secs(45),
        Duration::from_secs(7),
    ));
    Ok((id, op, send))
}
async fn reclaim_operation(
    id: String,
    weak: std::sync::Weak<Operation>,
    idle: Duration,
    cleanup_timeout: Duration,
) {
    loop {
        tokio::time::sleep(idle).await;
        let Some(operation) = weak.upgrade() else {
            return;
        };
        if reclaim_operation_if_idle(&id, &operation, Instant::now(), idle, cleanup_timeout).await {
            return;
        }
        // 超时只撤销准入，原句柄与清理任务继续保留；后续闲置周期重试真实回收。
    }
}
async fn reclaim_operation_if_idle(
    id: &str,
    operation: &Arc<Operation>,
    now: Instant,
    idle: Duration,
    cleanup_timeout: Duration,
) -> bool {
    let registered = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(id)
        .is_some_and(|current| Arc::ptr_eq(current, operation));
    if !registered {
        return true;
    }
    operation
        .consumer
        .cancel_if_idle_at(now, idle, &operation.stop)
        && cancel_with_timeout(id, cleanup_timeout).await.is_ok()
}
async fn send_event(
    send: &Events,
    event: Result<AdbServiceEvent, String>,
    stop: &CancellationToken,
) -> bool {
    tokio::select! { _=stop.cancelled()=>false,
    result=tokio::time::timeout(Duration::from_secs(45),send.send(event))=>matches!(result,Ok(Ok(()))), }
}
/// 每操作只有一个消费者；等待下一事件形成背压。
pub async fn adb_service_next(operation_id: String) -> Result<Option<AdbServiceEvent>, String> {
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(&operation_id)
        .cloned()
        .ok_or("adb_operation_closed")?;
    if op.open_probe.is_some() {
        return Err("open_probe_requires_typed_result".into());
    }
    let mut receiver = op
        .events
        .try_lock()
        .map_err(|_| "adb_operation_has_a_reader")?;
    let _reading = op.consumer.reading();
    let result = tokio::select! { biased; _=op.stop.cancelled()=>return Err("adb_operation_cancelled".into()), event=receiver.recv()=>event };
    // 终态仅说明执行结果；登记由 cancel 或闲置回收在确认 worker/本机流释放后移除。
    result.transpose()
}
/// 保留既有非交互接口；服务消费者使用更完整的类型化事件。
pub async fn adb_next(operation_id: String) -> Result<Option<AdbEvent>, String> {
    Ok(adb_service_next(operation_id).await?.map(|event| AdbEvent {
        kind: event.kind,
        bytes: event.bytes,
        exit_code: event.exit_code,
        transferred: event.transferred,
        done: event.done,
    }))
}
pub async fn adb_cancel(operation_id: String) -> Result<(), String> {
    cancel_with_timeout(&operation_id, Duration::from_secs(7)).await
}
async fn flush_client(client: &Client, timeout: Duration) -> Result<(), String> {
    if !client.is_closed() {
        client
            .flush_closed_streams(OperationOptions {
                timeout,
                cancellation: CancellationToken::new(),
            })
            .await
            .map_err(|error| format!("adb_stream_cleanup_unconfirmed: {error}"))?;
    }
    Ok(())
}
async fn cancel_with_timeout(operation_id: &str, timeout: Duration) -> Result<(), String> {
    let op = registry()
        .lock()
        .expect("adb registry")
        .operations
        .get(operation_id)
        .cloned();
    let Some(op) = op else {
        return Ok(());
    };
    op.stop.cancel();
    tokio::time::timeout(timeout, async {
        let _cleanup = op.cleanup.lock().await;
        op.finished.cancelled().await;
        flush_client(&op.client, timeout).await?;
        let mut state = registry().lock().expect("adb registry");
        if state
            .operations
            .get(operation_id)
            .is_some_and(|current| Arc::ptr_eq(current, &op))
        {
            state.operations.remove(operation_id);
        }
        Ok(())
    })
    .await
    .map_err(|_| "adb_operation_cleanup_unconfirmed".to_owned())?
}
pub async fn adb_shell(
    connection_id: String,
    command: String,
    timeout_ms: u32,
) -> Result<String, String> {
    let _ = options(timeout_ms, CancellationToken::new())?;
    let client = device(&connection_id)?;
    let (id, op, send) = operation(connection_id)?;
    let options = options(timeout_ms, op.stop.clone())?;
    let stop = op.stop.clone();
    let completion = Completion(op.finished.clone());
    tokio::spawn(async move {
        let _completion = completion;
        let work = async {
            if client.info().features.contains("shell_v2") {
                let shell = client
                    .shell_session(&command, ShellMode::Raw, 65536, options.clone())
                    .await
                    .map_err(|e| e.to_string())?;
                let (mut reader, mut writer) = shell.into_split();
                // 快速命令可能已发送 stdout/Exit 并关闭流。写端失败不能污染读端，
                // Closed 后仍须读取真实 Exit；缺失回执由 reader 报错。
                match writer.close_stdin().await {
                    Ok(()) | Err(interop_adb::Error::Closed) => {}
                    Err(error) => return Err(error.to_string()),
                }
                while let Some(event) = reader.next_event().await.map_err(|e| e.to_string())? {
                    let event = match event {
                        ShellEvent::Stdout(bytes) => AdbServiceEvent {
                            kind: "stdout".into(),
                            bytes,
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        },
                        ShellEvent::Stderr(bytes) => AdbServiceEvent {
                            kind: "stderr".into(),
                            bytes,
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        },
                        ShellEvent::Exit(code) => AdbServiceEvent {
                            kind: "exit".into(),
                            bytes: vec![],
                            exit_code: Some(code.into()),
                            transferred: 0,
                            done: true,
                            facts: None,
                        },
                    };
                    if !send_event(&send, Ok(event), &stop).await {
                        return Ok(());
                    }
                }
            } else {
                let mut stream = client
                    .open(&format!("shell:{command}"), options.clone())
                    .await
                    .map_err(|e| e.to_string())?;
                let mut bytes = vec![0; 65536];
                loop {
                    let count = stream.read(&mut bytes).await.map_err(|e| e.to_string())?;
                    if count == 0 {
                        break;
                    }
                    if !send_event(
                        &send,
                        Ok(AdbServiceEvent {
                            kind: "stdout".into(),
                            bytes: bytes[..count].to_vec(),
                            exit_code: None,
                            transferred: 0,
                            done: false,
                            facts: None,
                        }),
                        &stop,
                    )
                    .await
                    {
                        return Ok(());
                    }
                }
                send_event(
                    &send,
                    Ok(AdbServiceEvent {
                        kind: "exit".into(),
                        bytes: vec![],
                        exit_code: None,
                        transferred: 0,
                        done: true,
                        facts: None,
                    }),
                    &stop,
                )
                .await;
            }
            Ok::<_, String>(())
        };
        let result = tokio::select! { _=stop.cancelled()=>return, result=tokio::time::timeout(options.timeout,work)=>result.unwrap_or_else(|_|Err("adb_shell_timeout".into())) };
        if let Err(error) = result {
            send_event(&send, Err(error), &stop).await;
        }
    });
    Ok(id)
}
pub async fn adb_close_all() -> Result<(), String> {
    close_all_with_timeout(Duration::from_secs(7)).await
}

async fn close_all_with_timeout(timeout: Duration) -> Result<(), String> {
    let (connections, handshakes, servers) = {
        let mut state = registry().lock().expect("adb registry");
        state.closing = true;
        let servers = server_owner::revoke_all(&mut state);
        for connection in state.connections.values() {
            connection.scope.cancel();
        }
        for op in state.operations.values() {
            op.stop.cancel();
        }
        (
            state.connections.keys().cloned().collect::<Vec<_>>(),
            handshake::revoke_all(&state),
            servers,
        )
    };
    tokio::time::timeout(timeout, async {
        let mut failure = handshake::drain_all(handshakes, timeout)
            .await
            .map_err(|_| "adb_host_cleanup_unconfirmed".to_owned())
            .err();
        if let Err(error) = crate::file_system::cancel_all().await {
            failure.get_or_insert(error);
        }
        for connection in connections {
            if let Err(error) = adb_disconnect(connection).await {
                failure.get_or_insert(error.message);
            }
        }
        for lease in servers {
            if let Err(error) = server_owner::close(&lease, timeout).await {
                failure.get_or_insert(error.to_string());
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        let mut state = registry().lock().expect("adb registry");
        state.admission_scopes.clear();
        state.closing = false;
        Ok(())
    })
    .await
    .map_err(|_| "adb_host_cleanup_unconfirmed".to_owned())?
}

#[path = "local_files.rs"]
mod local_files;

#[path = "local_storage.rs"]
mod local_storage;

/// 本机文件对象的精确身份；路径与显示名称不授予删除或提交权限。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalFileKind {
    File,
    Directory,
    Symlink,
    Other,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalFileIdentity {
    pub device: u64,
    pub inode: u64,
    pub size: u64,
    pub modified_seconds: i64,
    pub modified_nanos: u32,
    pub kind: LocalFileKind,
}
#[derive(Clone, Debug)]
pub struct LocalFileStat {
    pub identity: LocalFileIdentity,
    pub free_bytes: Option<u64>,
}
#[derive(Clone, Debug)]
pub struct LocalFileEntry {
    pub name: Vec<u8>,
    pub identity: LocalFileIdentity,
}
#[derive(Clone, Debug)]
pub struct LocalFileList {
    pub identity: LocalFileIdentity,
    pub entries: Vec<LocalFileEntry>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocalFileErrorCode {
    InvalidArgument,
    ScopeClosed,
    NotFound,
    Busy,
    Cancelled,
    TimedOut,
    ByteLimit,
    EntryLimit,
    SourceChanged,
    TargetChanged,
    Conflict,
    ResultUnknown,
    CleanupUnconfirmed,
    Unsupported,
    Io,
}
#[derive(Clone, Debug)]
pub struct LocalFileError {
    pub code: LocalFileErrorCode,
    pub message: String,
    pub bytes_copied: u64,
    pub partial_destination_possible: bool,
}
impl std::fmt::Display for LocalFileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for LocalFileError {}
/// 每端恰好提供路径或借入 FD。目标路径由本次复制独占创建，尚未提交时归 copy 句柄回收。
#[derive(Clone, Debug)]
pub struct LocalFileCopyRequest {
    pub source_path: Option<Vec<u8>>,
    pub source_fd: Option<i32>,
    pub target_path: Option<Vec<u8>>,
    pub target_fd: Option<i32>,
    pub source_offset: u64,
    pub length: Option<u64>,
    pub expected_source: Option<LocalFileIdentity>,
    pub max_bytes: u64,
    pub timeout_ms: u32,
}
#[derive(Clone, Debug)]
pub struct LocalFileCopyResult {
    pub bytes: u64,
    pub identity: LocalFileIdentity,
    pub source_identity: LocalFileIdentity,
}
/// 查询现存绝对目录所在文件系统对当前调用方可用的容量；不创建目录或文件范围。
pub async fn adb_local_storage_free_bytes(path: String) -> Result<u64, LocalFileError> {
    local_storage::free_bytes(path).await
}

pub async fn adb_local_scope_open(
    roots: Vec<Vec<u8>>,
    owner_key: String,
    close_timeout_ms: u32,
) -> Result<String, LocalFileError> {
    local_files::open(roots, owner_key, close_timeout_ms).await
}
pub async fn adb_local_scope_close(
    scope_id: String,
    timeout_ms: u32,
) -> Result<(), LocalFileError> {
    local_files::close_scope(scope_id, timeout_ms).await
}
pub async fn adb_local_stat(
    scope_id: String,
    path: Vec<u8>,
) -> Result<LocalFileStat, LocalFileError> {
    local_files::stat(scope_id, path).await
}
pub async fn adb_local_list(
    scope_id: String,
    path: Vec<u8>,
    max_entries: u32,
) -> Result<LocalFileList, LocalFileError> {
    local_files::list(scope_id, path, max_entries).await
}
pub async fn adb_local_mkdir(
    scope_id: String,
    path: Vec<u8>,
    exclusive: bool,
) -> Result<(), LocalFileError> {
    local_files::mkdir(scope_id, path, exclusive).await
}
pub async fn adb_local_remove(
    scope_id: String,
    path: Vec<u8>,
    expected: LocalFileIdentity,
) -> Result<(), LocalFileError> {
    local_files::remove(scope_id, path, expected).await
}
pub async fn adb_local_copy_create(
    scope_id: String,
    request: LocalFileCopyRequest,
) -> Result<String, LocalFileError> {
    local_files::create_copy(scope_id, request).await
}
pub async fn adb_local_copy_run(copy_id: String) -> Result<LocalFileCopyResult, LocalFileError> {
    local_files::run_copy(copy_id).await
}
/// 只发取消信号；实际流释放由 close 确认。
pub async fn adb_local_copy_cancel(copy_id: String) -> Result<(), LocalFileError> {
    local_files::cancel_copy(copy_id)
}
pub async fn adb_local_copy_close(copy_id: String, timeout_ms: u32) -> Result<(), LocalFileError> {
    local_files::close_copy(copy_id, timeout_ms).await
}
/// 保留复制时的原始目标 FD；提交后核验失败返回未知，不能重试该提交权。
pub async fn adb_local_commit(
    scope_id: String,
    copy_id: String,
    destination: Vec<u8>,
    expected_identity: LocalFileIdentity,
) -> Result<LocalFileIdentity, LocalFileError> {
    local_files::commit(scope_id, copy_id, destination, expected_identity).await
}
