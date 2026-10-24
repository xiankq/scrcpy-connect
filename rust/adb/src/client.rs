use crate::{
    Error, Identity, Result,
    error::bounded,
    protocol::{self, Frame},
    read_trace::{ReceivedPayload, Subscription},
};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::{TcpStream, ToSocketAddrs},
    sync::{Notify, mpsc, oneshot},
};
use tokio_util::sync::CancellationToken;

pub trait Transport: AsyncRead + AsyncWrite + Unpin + Send + 'static {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send + 'static> Transport for T {}

#[derive(Debug, Clone)]
pub struct OperationOptions {
    /// 每次操作的最长时间；sync 传输方法将其应用于整个传输。
    pub timeout: Duration,
    pub cancellation: CancellationToken,
}
impl Default for OperationOptions {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(30),
            cancellation: CancellationToken::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ConnectOptions {
    /// 桌面主机服务地址。设备传输与授权由官方 server 拥有，此处不直接进行协议握手。
    pub adb_server: Option<std::net::SocketAddr>,
    pub tcp: crate::TcpOptions,
    pub identity: Option<Identity>,
    /// 通告实验性 AOSP delayed_ack，仅对端也支持时启用。每流保守预留 64 KiB 接收窗口及一个协商 max_payload 的超额包；连接总预留 128 MiB，包含小包元数据的最坏开销。预算耗尽只拒绝新流，不中断现有流。默认关闭。
    pub burst_mode: bool,
    /// 密钥签名被拒绝后，显式允许触发设备授权提示。
    pub request_authorization: bool,
    pub public_key_comment: String,
    pub tls: Option<crate::wireless::TlsConfig>,
    /// 该端点的 STLS 是可选还是强制。
    pub tls_policy: TlsPolicy,
    pub operations: OperationOptions,
}

/// 传输安全策略，独立于 TLS 提供者是否已配置。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum TlsPolicy {
    /// 旧 TCP/USB 可使用 AUTH 或未认证 CNXN；STLS 仍要求配置 tls。
    #[default]
    Optional,
    /// 现代无线端点必须先完成 STLS/TLS，才能接收 CNXN 或 AUTH。
    Required,
}
impl Default for ConnectOptions {
    fn default() -> Self {
        Self {
            adb_server: None,
            tcp: crate::TcpOptions::default(),
            identity: None,
            burst_mode: false,
            request_authorization: false,
            public_key_comment: "interop-adb".into(),
            tls: None,
            tls_policy: TlsPolicy::Optional,
            operations: OperationOptions::default(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub version: u32,
    pub max_payload: usize,
    pub banner: String,
    pub features: HashSet<String>,
}

/// 本连接实际观察到的协商方式，不代表目标设备已证明自己的身份。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandshakeKind {
    /// 外部连接器只交入已协商传输，未提供握手证据。
    Unknown,
    /// 收到 CNXN 前未进行 AUTH 或 STLS。
    Plaintext,
    /// 已发送 RSA AUTH 响应后收到 CNXN。
    Auth,
    /// 已完成 STLS/TLS 后在加密通道收到 CNXN；不证明服务端要求或验证了客户端证书。
    Tls,
    /// 官方 server 负责传输和认证，smart socket 不提供实际握手证据。
    DelegatedServer,
}

/// 连接建立时的公开事实；不保存私钥，也不重新读取之后可能已替换的身份文件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectionSecurity {
    pub handshake: HandshakeKind,
    /// 同次连接配置的 ADB 公钥，使用空注释及 NUL 编码；配置不等同于实际认证。
    pub configured_public_key: Option<Vec<u8>>,
}
impl ConnectionSecurity {
    fn unknown() -> Self {
        Self {
            handshake: HandshakeKind::Unknown,
            configured_public_key: None,
        }
    }
}

/// 探测响应所在协议层；官方服务器响应不证明设备传输层 OPEN 的发送时刻。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpenProbeLayer {
    DirectAdb,
    OfficialServer,
}

/// 仅描述本次服务打开的事实，不判定整个连接是否健康。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpenProbeOutcome {
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

#[derive(Clone, Debug)]
pub struct OpenProbeFacts {
    pub layer: OpenProbeLayer,
    /// 完整 OPEN 或 smart-socket 服务请求已写入本机传输；不是仅进入发送队列。
    pub open_written: bool,
    pub outcome: OpenProbeOutcome,
    pub inbound_activity: usize,
}

#[derive(Default)]
pub(crate) struct OpenProbeTrace {
    written: AtomicBool,
    response: Mutex<Option<OpenProbeOutcome>>,
}
impl OpenProbeTrace {
    pub(crate) fn written(&self) {
        self.written.store(true, Ordering::Release);
    }
    pub(crate) fn response(&self, response: OpenProbeOutcome) {
        // 匹配本次请求的响应也证明请求确实已发出，避免读写任务调度顺序改变事实。
        self.written();
        self.response
            .lock()
            .expect("open probe response")
            .get_or_insert(response);
    }
}

struct Route {
    closed: CancellationToken,
    remote: u32,
    awaiting_ack: bool,
    data: mpsc::Sender<ReceivedPayload>,
    ack: mpsc::Sender<u32>,
    trace: Option<Subscription>,
    open_probe: Option<Arc<OpenProbeTrace>>,
    burst: Option<crate::burst::Flow>,
}
impl Drop for Route {
    fn drop(&mut self) {
        self.closed.cancel();
    }
}
type Routes = Arc<Mutex<HashMap<u32, Route>>>;

enum ControlResponse {
    // 必须排在该逻辑流已接纳的帧之后。
    OrderedClose(Frame),
    // 此设备发起的流从未准入，不存在待保留的数据顺序。
    RejectOpen(Frame),
    // 确认先前关闭帧已写出；不表示设备进程已退出。
    FlushClosed(oneshot::Sender<()>),
}

static NEXT_CONNECTION_ID: AtomicU64 = AtomicU64::new(1);

// 完成登记独立于 Client 的 Arc，驱动不能靠持有 Client 自己阻止最后一个 owner 释放。
#[derive(Default)]
struct DriverState {
    state: Mutex<DriverCount>,
    changed: Notify,
}
#[derive(Default)]
struct DriverCount {
    closing: bool,
    active: usize,
}
pub(crate) struct DriverGuard(Arc<DriverState>);
impl DriverGuard {
    pub(crate) fn child(&self) -> Self {
        self.0.state.lock().expect("driver mutex").active += 1;
        Self(self.0.clone())
    }
    pub(crate) fn spawn<F>(&self, future: F) -> Result<()>
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        spawn_driver(future, self.0.register()?)
    }
}
fn spawn_driver<F>(future: F, completion: DriverGuard) -> Result<()>
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    let mut tracked = DriverResource::new(Box::pin(future), completion);
    let runtime = tokio::runtime::Handle::try_current()
        .map_err(|_| Error::InvalidArgument("ADB driver requires a Tokio runtime"))?;
    runtime.spawn(async move { tracked.get_mut().as_mut().await });
    Ok(())
}
impl Drop for DriverGuard {
    fn drop(&mut self) {
        let mut state = self.0.state.lock().expect("driver mutex");
        state.active -= 1;
        if state.active == 0 {
            self.0.changed.notify_waiters();
        }
    }
}
impl DriverState {
    fn register(self: &Arc<Self>) -> Result<DriverGuard> {
        let mut state = self.state.lock().expect("driver mutex");
        if state.closing {
            return Err(Error::Closed);
        }
        state.active += 1;
        Ok(DriverGuard(self.clone()))
    }
    fn begin_close(self: &Arc<Self>) -> Option<DriverGuard> {
        let mut state = self.state.lock().expect("driver mutex");
        if state.closing {
            return None;
        }
        state.closing = true;
        // 保留同步撤销到远端映射尽力清理任务之间的完成责任，不能出现短暂的零计数。
        state.active += 1;
        Some(DriverGuard(self.clone()))
    }
    async fn released(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.state.lock().expect("driver mutex").active == 0 {
                return;
            }
            changed.await;
        }
    }
}
// 字段按声明顺序释放：真实流/未来必须先释放，完成登记才可唤醒等待者。
pub(crate) struct DriverResource<T> {
    resource: T,
    _completion: DriverGuard,
}
impl<T> DriverResource<T> {
    fn new(resource: T, completion: DriverGuard) -> Self {
        Self {
            resource,
            _completion: completion,
        }
    }
    fn get_mut(&mut self) -> &mut T {
        &mut self.resource
    }
}

struct Inner {
    server: Option<crate::server::Connection>,
    drivers: Arc<DriverState>,
    connection_id: u64,
    info: DeviceInfo,
    security: ConnectionSecurity,
    burst_mode: bool,
    receive_budget: crate::burst::Budget,
    writer: mpsc::Sender<Frame>,
    priority_writer: mpsc::Sender<Frame>,
    control_responses: mpsc::Sender<ControlResponse>,
    routes: Routes,
    next_id: AtomicU32,
    cancellation: CancellationToken,
    failure: Arc<Mutex<Option<String>>>,
    traced_routes: Arc<AtomicUsize>,
    inbound_activity: Arc<AtomicUsize>,
    reverses: Arc<crate::reverse::Registry>,
}
impl Inner {
    fn queue_control(&self, response: ControlResponse) {
        // 读任务和流释放不等待写队列空位，也不创建任务；对端超过有限控制额度时关闭连接。
        if self.control_responses.try_send(response).is_err() {
            *self.failure.lock().expect("failure mutex") =
                Some("control response queue exhausted or closed".into());
            self.cancellation.cancel();
        }
    }

    fn next_stream_id(&self) -> Result<u32> {
        let mut id = self.next_id.load(Ordering::Relaxed);
        loop {
            let next = id
                .checked_add(1)
                .ok_or_else(|| Error::Protocol("stream ID space exhausted; reconnect".into()))?;
            match self
                .next_id
                .compare_exchange_weak(id, next, Ordering::Relaxed, Ordering::Relaxed)
            {
                Ok(id) => return Ok(id),
                Err(current) => id = current,
            }
        }
    }
}
impl Drop for Inner {
    fn drop(&mut self) {
        if let Some(server) = &self.server {
            self.reverses.retire_server(server.clone(), None);
        }
        self.cancellation.cancel();
    }
}

#[derive(Clone)]
pub struct Client {
    inner: Arc<Inner>,
}

impl Client {
    /// 附着到官方 server 的一个精确 transport。后续服务固定使用 transport ID，因此同序列号重连不能把现有逻辑连接重定向到替代设备传输。
    pub async fn connect_server(
        address: std::net::SocketAddr,
        serial: &str,
        options: OperationOptions,
    ) -> Result<Self> {
        let (server, info) = crate::server::Connection::connect(address, serial, &options).await?;
        let (writer, _) = mpsc::channel(1);
        let (priority_writer, _) = mpsc::channel(1);
        let (control_responses, _) = mpsc::channel(1);
        Ok(Self {
            inner: Arc::new(Inner {
                drivers: Default::default(),
                server: Some(server),
                connection_id: NEXT_CONNECTION_ID.fetch_add(1, Ordering::Relaxed),
                info,
                security: ConnectionSecurity {
                    handshake: HandshakeKind::DelegatedServer,
                    configured_public_key: None,
                },
                burst_mode: false,
                receive_budget: Default::default(),
                writer,
                priority_writer,
                control_responses,
                routes: Arc::new(Mutex::new(HashMap::new())),
                next_id: AtomicU32::new(1),
                cancellation: CancellationToken::new(),
                failure: Arc::new(Mutex::new(None)),
                traced_routes: Arc::new(AtomicUsize::new(0)),
                inbound_activity: Arc::new(AtomicUsize::new(0)),
                reverses: Arc::new(Default::default()),
            }),
        })
    }
    pub fn uses_server(&self) -> bool {
        self.inner.server.is_some()
    }
    pub fn server_transport_id(&self) -> Option<u64> {
        self.inner.server.as_ref().map(|server| server.transport_id)
    }
    /// 当前代理实际连接的官方 server 端点；不表示调用方拥有该进程的关闭权。
    pub fn server_address(&self) -> Option<std::net::SocketAddr> {
        self.inner.server.as_ref().map(|server| server.address)
    }
    pub fn security(&self) -> &ConnectionSecurity {
        &self.inner.security
    }
    pub async fn connect_tcp(address: impl ToSocketAddrs, options: ConnectOptions) -> Result<Self> {
        if let Some(server) = options.adb_server {
            let target = tokio::net::lookup_host(address)
                .await?
                .next()
                .ok_or(Error::InvalidArgument("device endpoint has no address"))?;
            let serial = if matches!(options.tls_policy, TlsPolicy::Required) {
                crate::server::tls_service(server, target, &options.operations).await?
            } else {
                target.to_string()
            };
            if !options.request_authorization {
                // 官方 daemon 没有“绝不提供公钥”选项。后台重连只能复用已授权 transport，不能新建未知 transport 并触发授权对话框。
                if crate::server::devices(server, &options.operations)
                    .await?
                    .iter()
                    .any(|device| device.serial == serial && device.state == "device")
                {
                    return Self::connect_server(server, &serial, options.operations).await;
                }
                return Err(Error::AuthorizationRequired);
            }
            let answer = crate::server::query(
                server,
                &format!("host:connect:{serial}"),
                &options.operations,
            )
            .await?;
            let answer = String::from_utf8_lossy(&answer);
            if !answer.starts_with("connected to ") && !answer.starts_with("already connected to ")
            {
                return Err(Error::Remote(answer.into_owned()));
            }
            return Self::connect_server(server, &serial, options.operations).await;
        }
        let deadline = tokio::time::Instant::now() + options.operations.timeout;
        let stream = bounded(
            options.operations.timeout,
            &options.operations.cancellation,
            async { Ok(TcpStream::connect(address).await?) },
        )
        .await
        .map_err(|error| match error {
            Error::Cancelled => error,
            _ => Error::Connect(Box::new(error)),
        })?;
        crate::tcp::configure(&stream, &options.tcp)?;
        let mut options = options;
        // TCP 与协议握手共享同一预算；取得 socket 不会重新开始计时。
        options.operations.timeout =
            deadline.saturating_duration_since(tokio::time::Instant::now());
        if options.operations.timeout.is_zero() {
            return Err(Error::Timeout);
        }
        Self::connect_transport(stream, options).await
    }

    /// 连接 adbd 字节传输。USB adapter 必须保持包字节，而非 USB transfer 的分段。
    pub async fn connect_transport<T: Transport>(
        transport: T,
        options: ConnectOptions,
    ) -> Result<Self> {
        if options.adb_server.is_some() {
            return Err(Error::InvalidArgument(
                "desktop server backend cannot open a direct transport",
            ));
        }
        if options.tls_policy == TlsPolicy::Required && options.tls.is_none() {
            return Err(Error::InvalidArgument(
                "required TLS policy needs a TLS configuration",
            ));
        }
        if let (Some(identity), Some(tls)) = (&options.identity, &options.tls)
            && !tls.matches_identity(identity)?
        {
            return Err(Error::Identity(
                "AUTH and TLS must use the same host identity".into(),
            ));
        }
        let burst_mode = options.burst_mode;
        let configured_public_key = if let Some(identity) = &options.identity {
            Some(identity.public_key("")?)
        } else {
            options.tls.as_ref().map(|tls| tls.public_key().to_vec())
        };
        let mut transport: Box<dyn Transport> = Box::new(transport);
        let operation_options = options.operations.clone();
        let (transport, info, handshake) = bounded(
            operation_options.timeout,
            &operation_options.cancellation,
            async move {
                let mut banner = b"host::features=shell_v2,cmd,stat_v2,ls_v2,abb,abb_exec,sendrecv_v2,sendrecv_v2_brotli,sendrecv_v2_lz4,sendrecv_v2_zstd".to_vec();
                if burst_mode { banner.extend_from_slice(b",delayed_ack"); }
                banner.extend_from_slice(b";\0");
                Frame::new(
                    protocol::CNXN,
                    protocol::VERSION,
                    protocol::MAX_PAYLOAD as u32,
                    banner,
                )
                .write(&mut transport)
                .await?;
                let mut signed = false;
                let mut upgraded = false;
                loop {
                    // 协商前 ADB 将 payload 限制为 4 KiB；新对端可省略校验和。
                    let frame = Frame::read(&mut transport, 4096, true).await?;
                    if options.tls_policy == TlsPolicy::Required
                        && !upgraded
                        && matches!(frame.command, protocol::CNXN | protocol::AUTH)
                    {
                        return Err(Error::Protocol(
                            "TLS is required for this ADB endpoint; refusing plaintext CNXN/AUTH"
                                .into(),
                        ));
                    }
                    match frame.command {
                        protocol::CNXN => {
                            if frame.arg0 < protocol::LEGACY_VERSION || frame.arg1 == 0 {
                                return Err(Error::Protocol(
                                    "unsupported ADB version or zero maxdata".into(),
                                ));
                            }
                            let banner = std::str::from_utf8(&frame.payload)
                                .map_err(|_| Error::Protocol("non-UTF8 device banner".into()))?
                                .trim_end_matches('\0')
                                .to_owned();
                            let features = banner
                                .split("features=")
                                .nth(1)
                                .unwrap_or("")
                                .split(';')
                                .next()
                                .unwrap_or("")
                                .split(',')
                                .filter(|s| !s.is_empty())
                                .map(str::to_owned)
                                .collect();
                            return Ok((
                                transport,
                                DeviceInfo {
                                    version: frame.arg0.min(protocol::VERSION),
                                    max_payload: (frame.arg1 as usize).min(protocol::MAX_PAYLOAD),
                                    banner,
                                    features,
                                },
                                if upgraded {
                                    HandshakeKind::Tls
                                } else if signed {
                                    HandshakeKind::Auth
                                } else {
                                    HandshakeKind::Plaintext
                                },
                            ));
                        }
                        protocol::AUTH if frame.arg0 == 1 => {
                            if frame.arg1 != 0 || frame.payload.len() != 20 {
                                return Err(Error::Protocol("invalid AUTH TOKEN frame".into()));
                            }
                            let identity = options
                                .identity
                                .as_ref()
                                .ok_or(Error::AuthorizationRequired)?;
                            let response = if !signed {
                                signed = true;
                                Frame::new(
                                    protocol::AUTH,
                                    2,
                                    0,
                                    identity.sign_token(&frame.payload)?,
                                )
                            } else if options.request_authorization {
                                // 旧 adbd 在启动中 framework 就绪后会重发 TOKEN；仅重新提供同一显式授权密钥，外层期限与取消仍限制重试。
                                Frame::new(
                                    protocol::AUTH,
                                    3,
                                    0,
                                    identity.public_key(&options.public_key_comment)?,
                                )
                            } else {
                                return Err(Error::AuthorizationRequired);
                            };
                            response.write(&mut transport).await?;
                        }
                        protocol::STLS => {
                            if upgraded
                                || frame.arg0 != 0x0100_0000
                                || frame.arg1 != 0
                                || !frame.payload.is_empty()
                            {
                                return Err(Error::Protocol(
                                    "invalid or repeated STLS handshake".into(),
                                ));
                            }
                            let tls = options.tls.as_ref().ok_or(Error::Unsupported(
                                "TLS configuration is required for wireless debugging",
                            ))?;
                            Frame::new(protocol::STLS, 0x0100_0000, 0, Vec::new())
                                .write(&mut transport)
                                .await?;
                            transport =
                                Box::new(crate::wireless::upgrade_tls(transport, tls).await?);
                            upgraded = true;
                        }
                        _ => {
                            return Err(Error::Protocol(
                                "unexpected frame during handshake".into(),
                            ));
                        }
                    }
                }
            },
        )
        .await?;
        Self::from_negotiated_transport_with_security(
            transport,
            info,
            burst_mode,
            ConnectionSecurity {
                handshake,
                configured_public_key,
            },
        )
    }

    /// 外部已认证的 STLS/TLS 连接器完成 CNXN 后附着传输。
    pub fn from_negotiated_transport<T: Transport>(transport: T, info: DeviceInfo) -> Result<Self> {
        Self::from_negotiated_transport_with_burst(transport, info, false)
    }

    /// 附着外部已认证、已协商的传输。只有连接器在自身 CNXN 中主动通告 delayed_ack 且对端支持时，burst_mode 才能为 true；旧附着方法始终保留经典流控。
    pub fn from_negotiated_transport_with_burst<T: Transport>(
        transport: T,
        info: DeviceInfo,
        burst_mode: bool,
    ) -> Result<Self> {
        Self::from_negotiated_transport_with_security(
            transport,
            info,
            burst_mode,
            ConnectionSecurity::unknown(),
        )
    }

    fn from_negotiated_transport_with_security<T: Transport>(
        transport: T,
        info: DeviceInfo,
        burst_mode: bool,
        security: ConnectionSecurity,
    ) -> Result<Self> {
        let burst_mode = burst_mode && info.features.contains("delayed_ack");
        if info.max_payload == 0
            || info.max_payload > protocol::MAX_PAYLOAD
            || info.version < protocol::LEGACY_VERSION
            || info.version > protocol::VERSION
        {
            return Err(Error::InvalidArgument(
                "invalid negotiated transport parameters",
            ));
        }
        let runtime = tokio::runtime::Handle::try_current()
            .map_err(|_| Error::InvalidArgument("ADB transport requires a Tokio runtime"))?;
        let (reader, writer) = tokio::io::split(transport);
        // 信用不能绕过有界写队列。小型低延迟控制 WRTE 可使用优先队列，普通流帧仍在主队列保持 FIFO。
        let (tx, mut rx) = mpsc::channel::<Frame>(64);
        let (priority_tx, mut priority_rx) = mpsc::channel::<Frame>(16);
        // 空 CLSE 使用独立的有界额度，避免满载数据队列阻塞接收路由；额度泛滥关闭连接，不创建额外任务或无界存储。
        let (control_tx, mut control_rx) = mpsc::channel::<ControlResponse>(128);
        let routes: Routes = Arc::new(Mutex::new(HashMap::new()));
        let cancellation = CancellationToken::new();
        let failure = Arc::new(Mutex::new(None));
        let mut connection_id = NEXT_CONNECTION_ID.load(Ordering::Relaxed);
        loop {
            let next = connection_id
                .checked_add(1)
                .ok_or_else(|| Error::Protocol("connection ID space exhausted".into()))?;
            match NEXT_CONNECTION_ID.compare_exchange_weak(
                connection_id,
                next,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(current) => connection_id = current,
            }
        }
        let inner = Arc::new(Inner {
            server: None,
            drivers: Default::default(),
            connection_id,
            info,
            security,
            burst_mode,
            receive_budget: Default::default(),
            writer: tx.clone(),
            priority_writer: priority_tx,
            control_responses: control_tx,
            routes: routes.clone(),
            next_id: AtomicU32::new(1),
            cancellation: cancellation.clone(),
            failure: failure.clone(),
            traced_routes: Arc::new(AtomicUsize::new(0)),
            inbound_activity: Arc::new(AtomicUsize::new(0)),
            reverses: Default::default(),
        });
        let mut reader = DriverResource::new(reader, inner.drivers.register()?);
        let mut writer = DriverResource::new(writer, inner.drivers.register()?);
        let skip_checksum = inner.info.version >= protocol::VERSION;
        let writer_failure = failure.clone();
        let writer_cancel = cancellation.clone();
        let writer_routes = routes.clone();
        runtime.spawn(async move {
            loop {
                let (frame, preceding_priority, preceding) = tokio::select! {
                    biased;
                    _ = writer_cancel.cancelled() => break,
                    Some(response) = control_rx.recv() => match response {
                        ControlResponse::OrderedClose(frame) => (frame, priority_rx.len(), rx.len()),
                        ControlResponse::RejectOpen(frame) => (frame, 0, 0),
                        ControlResponse::FlushClosed(reply) => { let _ = reply.send(()); continue; },
                    },
                    frame = priority_rx.recv() => match frame { Some(frame) => (frame, 0, 0), None => break },
                    frame = rx.recv() => match frame { Some(frame) => (frame, 0, 0), None => break },
                };
                // 控制响应必须排在本流已接纳的 WRTE/OPEN/OKAY 之后。路由锁串行化移除和数据入队；拍下有界队列水位，在保持顺序的同时避免后续写入饿死控制响应。
                let result = async {
                    for _ in 0..preceding_priority {
                        let queued = priority_rx.recv().await.ok_or(Error::Closed)?;
                        write_transport_frame(writer.get_mut(), queued, &writer_routes, skip_checksum).await?;
                    }
                    for _ in 0..preceding {
                        let queued = rx.recv().await.ok_or(Error::Closed)?;
                        write_transport_frame(writer.get_mut(), queued, &writer_routes, skip_checksum).await?;
                    }
                    write_transport_frame(writer.get_mut(), frame, &writer_routes, skip_checksum).await
                };
                let result = tokio::select! { _ = writer_cancel.cancelled() => break, result = result => result };
                if let Err(error) = result {
                    *writer_failure.lock().expect("failure mutex") =
                        Some(format!("transport write: {error}"));
                    break;
                }
            }
            writer_cancel.cancel();
        });
        let read_cancel = cancellation.clone();
        let read_routes = routes.clone();
        let read_control = inner.control_responses.clone();
        let max_payload = inner.info.max_payload.min(protocol::MAX_PAYLOAD);
        let skip_checksum = inner.info.version >= protocol::VERSION;
        let read_failure = failure.clone();
        let read_inner = Arc::downgrade(&inner);
        let traced_routes = inner.traced_routes.clone();
        let inbound_activity = inner.inbound_activity.clone();
        runtime.spawn(async move {
            loop {
                let receive = Frame::read_observed_progress(
                    reader.get_mut(),
                    max_payload,
                    skip_checksum,
                    |command, remote, local| {
                        if command != protocol::WRTE || traced_routes.load(Ordering::Relaxed) == 0 {
                            return None;
                        }
                        read_routes
                            .lock()
                            .expect("route mutex poisoned")
                            .get(&local)
                            .filter(|route| route.remote != 0 && route.remote == remote)
                            .and_then(|route| route.trace.as_ref())
                            .map(|trace| trace.clock.clone())
                    },
                    || {
                        // 每次非空传输读取（含不完整帧）只做一次 relaxed 递增，不读取时钟，也不逐字节处理。
                        inbound_activity.fetch_add(1, Ordering::Relaxed);
                    },
                );
                let (frame, timing) = tokio::select! { _ = read_cancel.cancelled() => break, frame = receive => match frame { Ok(frame) => frame, Err(error) => { *read_failure.lock().expect("failure mutex") = Some(format!("transport read: {error}")); break; } } };
                if frame.command == protocol::OPEN {
                    if let Some(inner) = read_inner.upgrade() {
                        accept_reverse(inner, frame).await;
                    }
                    continue;
                }
                let description = (
                    frame.command.to_le_bytes(),
                    frame.arg0,
                    frame.arg1,
                    frame.payload.len(),
                );
                let mut response = None;
                let mut invalid = false;
                let mut route_description = None;
                {
                    let mut routes = read_routes.lock().expect("route mutex poisoned");
                    let duplicate_remote = burst_mode
                        && frame.command == protocol::OKAY
                        && routes
                            .get(&frame.arg1)
                            .is_some_and(|route| route.remote == 0)
                        && routes
                            .values()
                            .any(|route| route.remote == frame.arg0 && frame.arg0 != 0);
                    if let Some(route) = routes.get_mut(&frame.arg1) {
                        route_description = Some((route.remote, route.awaiting_ack));
                        if duplicate_remote
                            || (frame.command != protocol::CLSE
                                && (frame.arg0 == 0
                                    || (route.remote != 0 && route.remote != frame.arg0)))
                        {
                            invalid = true;
                        } else {
                            match frame.command {
                                protocol::OKAY if route.burst.is_some() => {
                                    if route
                                        .burst
                                        .as_mut()
                                        .expect("burst flow")
                                        .acknowledge(&frame.payload)
                                        .is_err()
                                    {
                                        invalid = true;
                                    } else if route.remote == 0 {
                                        route.remote = frame.arg0;
                                        route.awaiting_ack = false;
                                        if let Some(probe) = &route.open_probe {
                                            probe.response(OpenProbeOutcome::Okay);
                                        }
                                        if route.ack.try_send(frame.arg0).is_err() {
                                            invalid = true;
                                        }
                                    }
                                }
                                protocol::OKAY if frame.payload.is_empty() => {
                                    // 经典 ADB 的 OKAY 表示 socket 可写而非字节信用；adbd 部分刷新同一 WRTE 时可发送多个 OKAY。空闲时合并就绪信号，不能预授权下一次写入或堆积通道项。
                                    if route.awaiting_ack {
                                        route.remote = frame.arg0;
                                        route.awaiting_ack = false;
                                        if let Some(probe) = &route.open_probe {
                                            probe.response(OpenProbeOutcome::Okay);
                                        }
                                        if route.ack.try_send(frame.arg0).is_err() {
                                            invalid = true;
                                        }
                                    }
                                }
                                protocol::WRTE if route.remote != 0 => {
                                    if let Some(burst) = route.burst.as_mut() {
                                        if !burst.receive(frame.payload.len()) {
                                            invalid = true;
                                        }
                                        // 空 WRTE 不消耗字节信用，也不能分配无界接收或追踪队列项。
                                        if frame.payload.is_empty() {
                                            continue;
                                        }
                                    }
                                    // AOSP 在 EOF/错误路径仍会刷新最后一包，即使前一 WRTE 尚待 ACK；保留这段有界尾部数据，避免拒绝有效 shell。
                                    let trace = timing.and_then(|timing| {
                                        let subscription = route.trace.as_mut()?;
                                        if !Arc::ptr_eq(
                                            &subscription.clock.token,
                                            &timing.clock.token,
                                        ) {
                                            return None;
                                        }
                                        subscription.sequence =
                                            subscription.sequence.saturating_add(1);
                                        Some((
                                            crate::ReadTrace {
                                                sequence: subscription.sequence,
                                                payload_bytes: frame.payload.len(),
                                                payload_started_us: timing.started_us,
                                                payload_read_us: timing.read_us,
                                                routed_us: (timing.clock.read)(),
                                                first_consumed_us: 0,
                                            },
                                            timing.clock,
                                        ))
                                    });
                                    if invalid
                                        || route
                                            .data
                                            .try_send(ReceivedPayload {
                                                bytes: frame.payload,
                                                timing: trace,
                                            })
                                            .is_err()
                                    {
                                        invalid = true;
                                    }
                                }
                                protocol::CLSE
                                    if (route.remote == 0
                                        || frame.arg0 == route.remote
                                        || frame.arg0 == 0)
                                        && (!burst_mode || frame.payload.is_empty()) =>
                                {
                                    // 旧 adbd 在正常关闭时也使用零 sender ID。路由属于该精确传输，接受零 ID 不会关闭其他设备的流。
                                    response = Some(Frame::new(
                                        protocol::CLSE,
                                        frame.arg1,
                                        if frame.arg0 == 0 {
                                            route.remote
                                        } else {
                                            frame.arg0
                                        },
                                        Vec::new(),
                                    ));
                                    if let Some(probe) = &route.open_probe {
                                        probe.response(OpenProbeOutcome::Rejected);
                                    }
                                    routes.remove(&frame.arg1);
                                }
                                _ => invalid = true,
                            }
                        }
                    } else if matches!(
                        frame.command,
                        protocol::WRTE | protocol::OPEN | protocol::OKAY
                    ) {
                        response = Some(Frame::new(
                            protocol::CLSE,
                            frame.arg1,
                            frame.arg0,
                            Vec::new(),
                        ));
                    }
                    if invalid && burst_mode {
                        let remote = routes
                            .remove(&frame.arg1)
                            .map(|route| route.remote)
                            .filter(|remote| *remote != 0)
                            .unwrap_or(frame.arg0);
                        response = Some(Frame::new(protocol::CLSE, frame.arg1, remote, Vec::new()));
                        invalid = false;
                    }
                }
                if invalid {
                    *read_failure.lock().expect("failure mutex") = Some(format!(
                        "invalid stream state: (command,arg0,arg1,length)={description:?} (remote,awaiting_ack)={route_description:?}"
                    ));
                    break;
                }
                if let Some(response) = response
                    && read_control
                        .try_send(ControlResponse::OrderedClose(response))
                        .is_err()
                {
                    *read_failure.lock().expect("failure mutex") =
                        Some("control response queue exhausted or closed".into());
                    break;
                }
            }
            read_cancel.cancel();
            read_routes.lock().expect("route mutex poisoned").clear();
        });
        Ok(Self { inner })
    }

    /// 本连接两端是否主动协商了 delayed_ack。
    pub fn burst_mode(&self) -> bool {
        self.inner.burst_mode
    }

    pub fn info(&self) -> &DeviceInfo {
        &self.inner.info
    }
    pub fn is_closed(&self) -> bool {
        self.inner.cancellation.is_cancelled()
    }
    /// 本连接的不透明活动快照，仅可比较相等性。变化表示任意流收到非空字节，包括部分头部和 payload；帧校验独立进行。回绕计数不表示时间，也不能跨连接比较。
    pub fn inbound_activity(&self) -> usize {
        self.inner.inbound_activity.load(Ordering::Relaxed)
    }
    /// 进程内不透明传输标识。克隆共享标识，新连接永不复用；它不是持久设备身份。
    pub fn connection_id(&self) -> u64 {
        self.inner.connection_id
    }

    /// 两个句柄是否共享同一精确传输。克隆共享，重连不共享，即使设备 banner 相同；这不是存活性判断。
    pub fn same_connection(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    /// 最近一次传输或协议失败，不包含服务 payload 或身份秘密。
    pub fn close_reason(&self) -> Option<String> {
        self.inner.failure.lock().expect("failure mutex").clone()
    }
    pub fn close(&self) {
        let completion = self.inner.drivers.begin_close();
        self.inner.cancellation.cancel();
        if let Some(completion) = completion
            && let Some(server) = &self.inner.server
        {
            self.inner
                .reverses
                .retire_server(server.clone(), Some(completion));
        }
    }
    /// 撤销连接准入并等待本机驱动、服务 socket 与反向连接任务实际释放。
    /// 官方 server 流及其独立 writer 必须由调用方释放；保留它们会使等待超时。
    /// 超时或取消只中止本次等待，同一 Client 可以重试；成功不证明远端进程或映射已退出。
    pub async fn close_and_wait(&self, options: OperationOptions) -> Result<()> {
        self.close();
        bounded(options.timeout, &options.cancellation, async {
            self.inner.drivers.released().await;
            Ok(())
        })
        .await
    }

    pub(crate) fn track_driver(&self) -> Result<DriverGuard> {
        self.inner.drivers.register()
    }
    pub(crate) fn spawn_driver<F>(&self, future: F) -> Result<()>
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        spawn_driver(future, self.track_driver()?)
    }
    /// 等待自有传输此前已释放流的关闭帧写出；官方 server 路径只保证本机 socket 已同步关闭。
    /// 两种路径均不提供远端退出证明；官方 server 的跨 socket 转发顺序也不在此保证内。
    pub async fn flush_closed_streams(&self, options: OperationOptions) -> Result<()> {
        if self.inner.server.is_some() {
            // server::Stream 的释放已同步 shutdown，本路径没有应用自有的 ADB 帧写队列。
            return Ok(());
        }
        let (reply, completion) = oneshot::channel();
        bounded(options.timeout, &options.cancellation, async {
            tokio::select! {
                _ = self.inner.cancellation.cancelled() => return Err(Error::Closed),
                sent = self.inner.control_responses.send(ControlResponse::FlushClosed(reply)) => {
                    sent.map_err(|_| Error::Closed)?;
                }
            }
            tokio::select! {
                _ = self.inner.cancellation.cancelled() => Err(Error::Closed),
                done = completion => done.map_err(|_| Error::Closed),
            }
        })
        .await
    }

    pub(crate) fn cancellation(&self) -> CancellationToken {
        self.inner.cancellation.clone()
    }
    pub(crate) fn reverse_registry(&self) -> &Arc<crate::reverse::Registry> {
        &self.inner.reverses
    }

    pub async fn open(&self, service: &str, options: OperationOptions) -> Result<AdbStream> {
        if service.as_bytes().contains(&0) {
            return Err(Error::InvalidArgument("ADB service contains NUL"));
        }
        self.open_service(service.as_bytes(), options).await
    }

    /// 只打开并立即释放本次服务；关闭帧排序由调用方随后 flush_closed_streams 确认。
    /// 超时且未确认写出时返回 NotWritten，不能据此认定对端无响应。
    pub async fn probe_service_open(
        &self,
        service: &str,
        options: OperationOptions,
    ) -> Result<OpenProbeFacts> {
        if service.is_empty()
            || service.as_bytes().contains(&0)
            || service.len() >= self.inner.info.max_payload
        {
            return Err(Error::InvalidArgument(
                "invalid or oversized ADB service name",
            ));
        }
        let trace = Arc::new(OpenProbeTrace::default());
        let result = if let Some(server) = &self.inner.server {
            match self.track_driver() {
                Ok(_completion) => {
                    server
                        .probe_open(
                            service.as_bytes(),
                            &options,
                            self.inner.cancellation.clone(),
                            self.inner.inbound_activity.clone(),
                            trace.clone(),
                        )
                        .await
                }
                Err(error) => Err(error),
            }
        } else {
            self.open_service_traced(service.as_bytes(), options, Some(trace.clone()))
                .await
                .map(drop)
        };
        let written = trace.written.load(Ordering::Acquire);
        let response = *trace.response.lock().expect("open probe response");
        let outcome = response.unwrap_or(match result {
            Ok(()) => OpenProbeOutcome::Okay,
            Err(Error::Timeout) if written => OpenProbeOutcome::TimedOut,
            Err(Error::Timeout) => OpenProbeOutcome::NotWritten,
            // 服务名已在上方验证；打开阶段的 InvalidArgument 只来自本机流/接收预算。
            Err(Error::InvalidArgument(_)) => OpenProbeOutcome::LocalCapacity,
            Err(Error::Cancelled) => OpenProbeOutcome::Cancelled,
            Err(Error::Closed) => OpenProbeOutcome::TransportClosed,
            Err(Error::Protocol(_)) => OpenProbeOutcome::Protocol,
            Err(_) => OpenProbeOutcome::Io,
        });
        Ok(OpenProbeFacts {
            layer: if self.uses_server() {
                OpenProbeLayer::OfficialServer
            } else {
                OpenProbeLayer::DirectAdb
            },
            open_written: written,
            outcome,
            inbound_activity: self.inbound_activity(),
        })
    }

    pub(crate) async fn open_service(
        &self,
        service: &[u8],
        options: OperationOptions,
    ) -> Result<AdbStream> {
        self.open_service_traced(service, options, None).await
    }

    async fn open_service_traced(
        &self,
        service: &[u8],
        options: OperationOptions,
        open_probe: Option<Arc<OpenProbeTrace>>,
    ) -> Result<AdbStream> {
        if service.is_empty() || service.len() >= self.inner.info.max_payload {
            return Err(Error::InvalidArgument(
                "invalid or oversized ADB service name",
            ));
        }
        if self.is_closed() {
            return Err(Error::Closed);
        }
        if let Some(server) = &self.inner.server {
            let completion = self.track_driver()?;
            let socket = tokio::select! {
                _=self.inner.cancellation.cancelled()=>return Err(Error::Closed),
                result=server.open(service,&options,self.inner.cancellation.clone(),self.inner.inbound_activity.clone(),Some(completion))=>result?,
            };
            let (_, data) = mpsc::channel(1);
            let (_, ack) = mpsc::channel(1);
            return Ok(AdbStream {
                server: Some(socket),
                closed: self.inner.cancellation.child_token(),
                inner: self.inner.clone(),
                local: 0,
                remote: 0,
                data,
                ack,
                buffer: Vec::new(),
                read_trace: None,
                trace_token: None,
                offset: 0,
                pending_ack: false,
                pending_credit: 0,
                _receive_reservation: None,
                options,
                eof: false,
                poisoned: false,
                priority_write: false,
            });
        }
        let reservation = if self.inner.burst_mode {
            Some(
                self.inner
                    .receive_budget
                    .reserve(self.inner.info.max_payload)?,
            )
        } else {
            None
        };
        let local = self.inner.next_stream_id()?;
        let (data_tx, data) = mpsc::channel(if self.inner.burst_mode {
            crate::burst::RECEIVE_PACKETS
        } else {
            2
        });
        let (ack_tx, ack) = mpsc::channel(2);
        let closed = CancellationToken::new();
        {
            let mut routes = self.inner.routes.lock().expect("route mutex poisoned");
            if routes.len() >= 128 {
                return Err(Error::InvalidArgument(
                    "maximum concurrent ADB streams reached",
                ));
            }
            routes.insert(
                local,
                Route {
                    closed: closed.clone(),
                    remote: 0,
                    awaiting_ack: true,
                    data: data_tx,
                    ack: ack_tx,
                    trace: None,
                    open_probe,
                    burst: reservation
                        .as_ref()
                        .map(|reservation| crate::burst::Flow::new(reservation.clone(), 0, true)),
                },
            );
        }
        let mut stream = AdbStream {
            server: None,
            inner: self.inner.clone(),
            closed,
            local,
            remote: 0,
            data,
            ack,
            buffer: Vec::new(),
            read_trace: None,
            trace_token: None,
            offset: 0,
            pending_ack: false,
            pending_credit: 0,
            _receive_reservation: reservation,
            options,
            eof: false,
            poisoned: false,
            priority_write: false,
        };
        let mut payload = service.to_vec();
        payload.push(0);
        let open_options = stream.options.clone();
        let result = bounded(open_options.timeout, &open_options.cancellation, async {
            stream
                .send_open(Frame::new(
                    protocol::OPEN,
                    local,
                    if self.inner.burst_mode {
                        crate::burst::RECEIVE_WINDOW as u32
                    } else {
                        0
                    },
                    payload,
                ))
                .await?;
            stream.remote = stream.ack.recv().await.ok_or(Error::Closed)?;
            Ok(())
        })
        .await;
        if let Err(error) = result {
            stream.poisoned = true;
            return Err(error);
        }
        Ok(stream)
    }
}

async fn write_transport_frame<W: AsyncWrite + Unpin>(
    writer: &mut W,
    frame: Frame,
    routes: &Routes,
    skip_checksum: bool,
) -> Result<()> {
    let probe = if frame.command == protocol::OPEN {
        routes
            .lock()
            .expect("route mutex poisoned")
            .get(&frame.arg0)
            .and_then(|route| route.open_probe.clone())
    } else {
        None
    };
    frame.write_with_checksum(writer, skip_checksum).await?;
    if let Some(probe) = probe {
        probe.written();
    }
    Ok(())
}

async fn reject_reverse(inner: &Inner, remote: u32) {
    inner.queue_control(ControlResponse::RejectOpen(Frame::new(
        protocol::CLSE,
        0,
        remote,
        Vec::new(),
    )));
}

async fn accept_reverse(inner: Arc<Inner>, frame: Frame) {
    let service = frame.payload.strip_suffix(&[0]).unwrap_or(&frame.payload);
    let destination = if frame.arg0 != 0
        && (frame.arg1 != 0) == inner.burst_mode
        && service.len() <= 1024
        && !service.contains(&0)
    {
        inner.reverses.destination(service)
    } else {
        None
    };
    let Some(destination) = destination else {
        reject_reverse(&inner, frame.arg0).await;
        return;
    };
    let Ok(local) = inner.next_stream_id() else {
        reject_reverse(&inner, frame.arg0).await;
        return;
    };
    let reservation = if inner.burst_mode {
        match inner.receive_budget.reserve(inner.info.max_payload) {
            Ok(reservation) => Some(reservation),
            Err(_) => {
                reject_reverse(&inner, frame.arg0).await;
                return;
            }
        }
    } else {
        None
    };
    let (data_tx, data) = mpsc::channel(if inner.burst_mode {
        crate::burst::RECEIVE_PACKETS
    } else {
        2
    });
    let (ack_tx, ack) = mpsc::channel(2);
    let closed = CancellationToken::new();
    let inserted = {
        let mut routes = inner.routes.lock().expect("route mutex poisoned");
        if routes.len() >= 128 || routes.values().any(|route| route.remote == frame.arg0) {
            false
        } else {
            routes.insert(
                local,
                Route {
                    closed: closed.clone(),
                    remote: frame.arg0,
                    awaiting_ack: false,
                    data: data_tx,
                    ack: ack_tx,
                    trace: None,
                    open_probe: None,
                    burst: reservation.as_ref().map(|reservation| {
                        crate::burst::Flow::new(reservation.clone(), i64::from(frame.arg1), false)
                    }),
                },
            );
            true
        }
    };
    if !inserted {
        reject_reverse(&inner, frame.arg0).await;
        return;
    }
    let mut stream = AdbStream {
        server: None,
        inner: inner.clone(),
        closed,
        local,
        remote: frame.arg0,
        data,
        ack,
        buffer: Vec::new(),
        read_trace: None,
        trace_token: None,
        offset: 0,
        pending_ack: false,
        pending_credit: 0,
        _receive_reservation: reservation,
        options: OperationOptions {
            timeout: Duration::from_secs(365 * 86400),
            cancellation: CancellationToken::new(),
        },
        eof: false,
        poisoned: false,
        priority_write: false,
    };
    let client = Client {
        inner: inner.clone(),
    };
    let _ = client.spawn_driver(async move {
        let result = bounded(destination.connect_timeout, &inner.cancellation, async {
            Ok(TcpStream::connect(destination.address).await?)
        })
        .await;
        let Ok(socket) = result else {
            inner
                .routes
                .lock()
                .expect("route mutex poisoned")
                .remove(&local);
            stream.eof = true;
            let _ = stream
                .send(Frame::new(protocol::CLSE, 0, frame.arg0, Vec::new()))
                .await;
            return;
        };
        if !inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .contains_key(&local)
        {
            stream.eof = true;
            drop(stream);
            return;
        }
        if stream.accept_reverse().await.is_err() {
            return;
        }
        let _ = socket.set_nodelay(true);
        let (mut read, mut write) = socket.into_split();
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let mut from_device = vec![0; 64 * 1024];
        let mut from_host = vec![0; 64 * 1024];
        // 读写独立推进：等待 WRTE 确认不能阻止另一方向消费数据并返回确认。
        let (_, mut acknowledgments) = mpsc::channel(1);
        std::mem::swap(&mut acknowledgments, &mut stream.ack);
        let from_device_task = async {
            loop {
                let count = stream.read(&mut from_device).await?;
                if count == 0 {
                    return Ok::<(), Error>(());
                }
                write.write_all(&from_device[..count]).await?;
            }
        };
        let from_host_task = async {
            loop {
                let count = read.read(&mut from_host).await?;
                if count == 0 {
                    return Ok::<(), Error>(());
                }
                write_stream_frames(
                    &inner,
                    local,
                    frame.arg0,
                    &mut acknowledgments,
                    &from_host[..count],
                    false,
                )
                .await?;
            }
        };
        tokio::pin!(from_device_task);
        tokio::select! {
            _ = inner.cancellation.cancelled() => {},
            _ = &mut from_device_task => {},
            result = from_host_task => {
                // 远端 CLSE 也会唤醒等待 ACK 或信用的发送方。先交付已路由输入再关闭 TCP 目标；选择已唤醒的写任务不能丢失尾部数据。
                if matches!(result, Err(Error::Closed))
                    && !inner.cancellation.is_cancelled()
                {
                    tokio::select! {
                        _ = inner.cancellation.cancelled() => {},
                        _ = &mut from_device_task => {},
                    }
                }
            },
        }
    });
}

async fn write_burst_frame(
    inner: &Inner,
    local: u32,
    remote: u32,
    bytes: &[u8],
    priority: bool,
) -> Result<()> {
    let (changed, closed) = inner
        .routes
        .lock()
        .expect("route mutex poisoned")
        .get(&local)
        .and_then(|route| {
            route
                .burst
                .as_ref()
                .map(|flow| (flow.changed.clone(), route.closed.clone()))
        })
        .ok_or(Error::Closed)?;
    loop {
        let notified = changed.notified();
        tokio::pin!(notified);
        // 先登记通知再检查信用，避免丢失并发到达的 OKAY/CLSE。
        notified.as_mut().enable();
        let ready = {
            let routes = inner.routes.lock().expect("route mutex poisoned");
            let route = routes.get(&local).ok_or(Error::Closed)?;
            route.burst.as_ref().expect("burst flow").send_credit > 0
        };
        if ready {
            let permit = tokio::select! {
                _ = inner.cancellation.cancelled() => return Err(Error::Closed),
                _ = closed.cancelled() => return Err(Error::Closed),
                permit = async {
                    if priority {
                        inner.priority_writer.reserve().await
                    } else {
                        inner.writer.reserve().await
                    }
                } => permit.map_err(|_| Error::Closed)?,
            };
            let mut routes = inner.routes.lock().expect("route mutex poisoned");
            let route = routes.get_mut(&local).ok_or(Error::Closed)?;
            let flow = route.burst.as_mut().expect("burst flow");
            // 等待写队列期间可能已经收到负信用 OKAY。
            if flow.send_credit > 0 {
                flow.send_credit -= bytes.len() as i64;
                permit.send(Frame::new(protocol::WRTE, local, remote, bytes.to_vec()));
                return Ok(());
            }
        }
        tokio::select! {
            _ = inner.cancellation.cancelled() => return Err(Error::Closed),
            _ = &mut notified => {},
        }
    }
}

async fn write_stream_frames(
    inner: &Inner,
    local: u32,
    remote: u32,
    acknowledgments: &mut mpsc::Receiver<u32>,
    bytes: &[u8],
    priority: bool,
) -> Result<()> {
    for chunk in bytes.chunks(inner.info.max_payload) {
        if inner.burst_mode {
            write_burst_frame(inner, local, remote, chunk, priority).await?;
            continue;
        }
        let closed = inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .get(&local)
            .map(|route| route.closed.clone())
            .ok_or(Error::Closed)?;
        let permit = tokio::select! {
            _ = inner.cancellation.cancelled() => return Err(Error::Closed),
            _ = closed.cancelled() => return Err(Error::Closed),
            permit = async {
                if priority {
                    inner.priority_writer.reserve().await
                } else {
                    inner.writer.reserve().await
                }
            } => permit.map_err(|_| Error::Closed)?,
        };
        {
            let mut routes = inner.routes.lock().expect("route mutex poisoned");
            let route = routes.get_mut(&local).ok_or(Error::Closed)?;
            if route.awaiting_ack {
                return Err(Error::Protocol(
                    "a stream write is already awaiting acknowledgement".into(),
                ));
            }
            route.awaiting_ack = true;
            permit.send(Frame::new(protocol::WRTE, local, remote, chunk.to_vec()));
        }
        let acknowledged_remote = acknowledgments.recv().await.ok_or(Error::Closed)?;
        if acknowledged_remote != remote {
            return Err(Error::Protocol(
                "WRTE acknowledgement changed remote stream ID".into(),
            ));
        }
    }
    Ok(())
}

/// 逻辑 ADB 流。读取只确认已消费字节（经典模式确认完整包），形成逐流背压；写入被中断后关闭本流，因为对端 ACK 状态已不确定。
pub struct AdbStream {
    server: Option<crate::server::Stream>,
    closed: CancellationToken,
    inner: Arc<Inner>,
    local: u32,
    remote: u32,
    data: mpsc::Receiver<ReceivedPayload>,
    ack: mpsc::Receiver<u32>,
    buffer: Vec<u8>,
    read_trace: Option<crate::ReadTrace>,
    trace_token: Option<Arc<()>>,
    offset: usize,
    pending_ack: bool,
    pending_credit: usize,
    _receive_reservation: Option<Arc<crate::burst::Reservation>>,
    options: OperationOptions,
    eof: bool,
    poisoned: bool,
    priority_write: bool,
}

impl AdbStream {
    /// 该协商传输单次 WRTE 接纳的最大 payload。调用者可据此合并完整控制消息批次；实际分帧仍由 write_all 执行。
    pub fn max_payload(&self) -> usize {
        self.inner.info.max_payload
    }

    /// 后续 WRTE 使用有界优先写队列。这只改变传输调度，不绕过逐流 ACK/信用，也不允许同一流并发写入。
    pub fn set_write_priority(&mut self, priority: bool) -> Result<()> {
        if self.server.is_some() {
            return if self.closed.is_cancelled() {
                Err(Error::Closed)
            } else {
                self.priority_write = priority;
                Ok(())
            };
        }
        if !self
            .inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .contains_key(&self.local)
        {
            return Err(Error::Closed);
        }
        self.priority_write = priority;
        Ok(())
    }

    async fn accept_reverse(&self) -> Result<()> {
        let permit = tokio::select! {
            _ = self.inner.cancellation.cancelled() => return Err(Error::Closed),
            _ = self.closed.cancelled() => return Err(Error::Closed),
            permit = self.inner.writer.reserve() => permit.map_err(|_| Error::Closed)?,
        };
        let mut routes = self.inner.routes.lock().expect("route mutex poisoned");
        let route = routes.get_mut(&self.local).ok_or(Error::Closed)?;
        let payload = if let Some(flow) = route.burst.as_mut() {
            flow.receive_credit = crate::burst::RECEIVE_WINDOW as i64;
            (crate::burst::RECEIVE_WINDOW as i32).to_le_bytes().to_vec()
        } else {
            Vec::new()
        };
        permit.send(Frame::new(protocol::OKAY, self.local, self.remote, payload));
        Ok(())
    }

    fn return_packet_ack(&self, permit: mpsc::Permit<'_, Frame>) {
        let routes = self.inner.routes.lock().expect("route mutex poisoned");
        if routes.contains_key(&self.local) {
            permit.send(Frame::new(
                protocol::OKAY,
                self.local,
                self.remote,
                Vec::new(),
            ));
        }
    }

    fn try_return_credit(&mut self) {
        if self.pending_credit == 0 {
            return;
        }
        let Ok(permit) = self.inner.writer.try_reserve() else {
            return;
        };
        self.return_credit(permit);
        self.pending_credit = 0;
    }

    fn return_credit(&self, permit: mpsc::Permit<'_, Frame>) {
        let mut routes = self.inner.routes.lock().expect("route mutex poisoned");
        if let Some(flow) = routes
            .get_mut(&self.local)
            .and_then(|route| route.burst.as_mut())
        {
            flow.receive_credit += self.pending_credit as i64;
            debug_assert!(flow.receive_credit <= crate::burst::RECEIVE_WINDOW as i64);
            permit.send(Frame::new(
                protocol::OKAY,
                self.local,
                self.remote,
                (self.pending_credit as i32).to_le_bytes().to_vec(),
            ));
        }
    }

    async fn flush_credit(&mut self) -> Result<()> {
        if self.pending_credit == 0 {
            return Ok(());
        }
        let changed = self
            .inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .get(&self.local)
            .and_then(|route| route.burst.as_ref())
            .map(|flow| flow.changed.clone());
        let Some(changed) = changed else {
            self.pending_credit = 0;
            return Ok(());
        };
        loop {
            let notified = changed.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if !self
                .inner
                .routes
                .lock()
                .expect("route mutex poisoned")
                .contains_key(&self.local)
            {
                // CLSE 使剩余接收信用失效；满载写队列不能阻止交付已路由的尾部数据。
                self.pending_credit = 0;
                return Ok(());
            }
            let permit = tokio::select! {
                _ = self.inner.cancellation.cancelled() => { self.pending_credit = 0; return Ok(()); },
                permit = self.inner.writer.reserve() => permit.map_err(|_| Error::Closed)?,
                _ = &mut notified => continue,
            };
            self.return_credit(permit);
            self.pending_credit = 0;
            return Ok(());
        }
    }

    /// 启停本流逐 WRTE 的有界接收计时。时钟须返回调用方时钟域的单调微秒值，快速完成且不能回调本 Client；更换时钟只丢弃待处理诊断，不丢弃流字节。
    pub fn set_read_trace_clock(&mut self, clock: Option<fn() -> u64>) -> Result<()> {
        // smart socket 暴露服务字节，不暴露 server 的 WRTE 接收分段；不能用 socket 读取伪造传输计时。
        if self.server.is_some() {
            self.read_trace = None;
            return Ok(());
        }
        let mut routes = self.inner.routes.lock().expect("route mutex poisoned");
        let route = routes.get_mut(&self.local).ok_or(Error::Closed)?;
        route.trace = clock.map(|clock| Subscription::new(clock, self.inner.traced_routes.clone()));
        self.trace_token = route.trace.as_ref().map(|trace| trace.clock.token.clone());
        self.read_trace = None;
        Ok(())
    }

    /// 提供最近一次非空读取数据的 WRTE 回执。
    pub fn read_trace(&self) -> Option<crate::ReadTrace> {
        self.read_trace
    }

    async fn send_open(&self, frame: Frame) -> Result<()> {
        let permit = tokio::select! {
            _ = self.inner.cancellation.cancelled() => return Err(Error::Closed),
            _ = self.closed.cancelled() => return Err(Error::Closed),
            permit = self.inner.writer.reserve() => permit.map_err(|_| Error::Closed)?,
        };
        // OPEN 入队与路由移除同 WRTE/OKAY 一样串行化。等待容量时收到关闭后，不能在有序关闭响应后迟到发送同一 local ID 的 OPEN。
        let routes = self.inner.routes.lock().expect("route mutex poisoned");
        if !routes.contains_key(&self.local) {
            return Err(Error::Closed);
        }
        permit.send(frame);
        Ok(())
    }

    async fn send(&self, frame: Frame) -> Result<()> {
        tokio::select! { _ = self.inner.cancellation.cancelled() => Err(Error::Closed), result = self.inner.writer.send(frame) => result.map_err(|_| Error::Closed) }
    }

    pub async fn read(&mut self, output: &mut [u8]) -> Result<usize> {
        if output.is_empty() {
            return Ok(0);
        }
        if self.poisoned {
            return Err(Error::Closed);
        }
        let options = self.options.clone();
        if let Some(server) = self.server.as_mut() {
            return bounded(options.timeout, &options.cancellation, async {
                tokio::select! {
                    _=self.inner.cancellation.cancelled()=>Err(Error::Closed),
                    result=server.read(output)=>result,
                }
            })
            .await;
        }
        bounded(options.timeout, &options.cancellation, async {
            loop {
                if self.offset < self.buffer.len() {
                    let count = output.len().min(self.buffer.len() - self.offset);
                    output[..count].copy_from_slice(&self.buffer[self.offset..self.offset + count]);
                    self.offset += count;
                    if self.inner.burst_mode {
                        self.pending_credit += count;
                        self.try_return_credit();
                    }
                    if self.offset == self.buffer.len() && self.pending_ack {
                        // 先同步尝试，避免读取取消丢失已复制字节。
                        if self.closed.is_cancelled() {
                            self.pending_ack = false;
                        } else if let Ok(permit) = self.inner.writer.try_reserve() {
                            self.return_packet_ack(permit);
                            self.pending_ack = false;
                        }
                    }
                    return Ok(count);
                }
                if self.inner.burst_mode {
                    self.flush_credit().await?;
                }
                if self.pending_ack {
                    // 最后一个 WRTE 后可能紧跟 CLSE；报告 EOF 前先消费已排队尾部。
                    tokio::select! {
                        _ = self.inner.cancellation.cancelled() => {},
                        _ = self.closed.cancelled() => {},
                        permit = self.inner.writer.reserve() => {
                            self.return_packet_ack(permit.map_err(|_| Error::Closed)?);
                        },
                    }
                    self.pending_ack = false;
                }
                if self.eof {
                    return Ok(0);
                }
                match self.data.recv().await {
                    Some(bytes) => {
                        self.buffer = bytes.bytes;
                        if !self.buffer.is_empty() {
                            self.read_trace = bytes
                                .timing
                                .filter(|(_, clock)| {
                                    self.trace_token
                                        .as_ref()
                                        .is_some_and(|token| Arc::ptr_eq(token, &clock.token))
                                })
                                .map(|(mut trace, clock)| {
                                    trace.first_consumed_us = (clock.read)();
                                    trace
                                });
                        }
                        self.offset = 0;
                        self.pending_ack = !self.inner.burst_mode;
                    }
                    None => {
                        self.eof = true;
                        return if self.inner.cancellation.is_cancelled() {
                            Err(Error::Closed)
                        } else {
                            Ok(0)
                        };
                    }
                }
            }
        })
        .await
    }

    pub async fn read_exact(&mut self, output: &mut [u8]) -> Result<()> {
        let mut offset = 0;
        while offset < output.len() {
            let n = self.read(&mut output[offset..]).await?;
            if n == 0 {
                return Err(Error::Protocol("truncated service response".into()));
            }
            offset += n;
        }
        Ok(())
    }

    pub async fn write_all(&mut self, bytes: &[u8]) -> Result<()> {
        if self.poisoned || self.eof {
            return Err(Error::Closed);
        }
        // 等待前先置位，避免 future 被丢弃后允许结果不明的第二次写入。
        self.poisoned = true;
        let options = self.options.clone();
        if let Some(server) = self.server.as_mut() {
            let result = bounded(options.timeout, &options.cancellation, async {
                tokio::select! {
                    _=self.inner.cancellation.cancelled()=>Err(Error::Closed),
                    result=server.write_all(bytes)=>result,
                }
            })
            .await;
            if result.is_err() {
                self.close_now();
            } else {
                self.poisoned = false;
            }
            return result;
        }
        let result = bounded(options.timeout, &options.cancellation, async {
            write_stream_frames(
                &self.inner,
                self.local,
                self.remote,
                &mut self.ack,
                bytes,
                self.priority_write,
            )
            .await?;
            Ok(())
        })
        .await;
        if result.is_err() {
            self.close_now();
        } else {
            self.poisoned = false;
        }
        result
    }

    pub async fn close(mut self) -> Result<()> {
        if let Some(mut server) = self.server.take() {
            self.eof = true;
            return server.close().await;
        }
        let options = self.options.clone();
        let result = bounded(
            options.timeout,
            &options.cancellation,
            self.send(Frame::new(
                protocol::CLSE,
                self.local,
                self.remote,
                Vec::new(),
            )),
        )
        .await;
        if result.is_err() {
            self.close_now();
            return result;
        }
        self.inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .remove(&self.local);
        self.eof = true;
        result
    }

    pub(crate) fn close_now(&mut self) {
        if self.server.take().is_some() {
            self.closed.cancel();
            self.eof = true;
            return;
        }
        let route = self
            .inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .remove(&self.local);
        if self.remote == 0
            && let Some(route) = route.as_ref()
        {
            self.remote = route.remote;
        }
        if self.eof {
            return;
        }
        let frame = Frame::new(protocol::CLSE, self.local, self.remote, Vec::new());
        if route.is_some() {
            self.inner
                .queue_control(ControlResponse::OrderedClose(frame));
        }
        self.eof = true;
    }
}
impl Drop for AdbStream {
    fn drop(&mut self) {
        self.close_now();
    }
}

#[path = "duplex.rs"]
mod duplex;
pub use duplex::{AdbReader, AdbWriter};
