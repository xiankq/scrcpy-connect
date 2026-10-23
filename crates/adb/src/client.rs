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
        atomic::{AtomicU32, AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::{TcpStream, ToSocketAddrs},
    sync::mpsc,
};
use tokio_util::sync::CancellationToken;

pub trait Transport: AsyncRead + AsyncWrite + Unpin + Send + 'static {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send + 'static> Transport for T {}

#[derive(Debug, Clone)]
pub struct OperationOptions {
    /// Maximum duration of each operation; sync transfer methods apply it to the entire transfer.
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
    /// Desktop host service endpoint. Device transports/authorization belong to
    /// the official server; no direct protocol handshake is performed here.
    pub adb_server: Option<std::net::SocketAddr>,
    pub tcp: crate::TcpOptions,
    pub identity: Option<Identity>,
    /// Advertise experimental AOSP delayed_ack. Active only when the peer also supports it.
    /// Uses a conservative 64 KiB receive window per stream (plus one negotiated
    /// max-payload overshoot), with a 128 MiB connection receive reservation
    /// budget including worst-case tiny-packet metadata. Budget exhaustion
    /// rejects new streams without interrupting existing ones. Default: false.
    pub burst_mode: bool,
    /// Explicitly allow a device authorization prompt after the key signature is rejected.
    pub request_authorization: bool,
    pub public_key_comment: String,
    pub tls: Option<crate::wireless::TlsConfig>,
    /// Whether STLS is optional or mandatory for this endpoint.
    pub tls_policy: TlsPolicy,
    pub operations: OperationOptions,
}

/// Transport security policy, independent of whether a TLS provider is configured.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum TlsPolicy {
    /// Legacy TCP/USB may use AUTH or an unauthenticated CNXN. STLS still needs `tls`.
    #[default]
    Optional,
    /// Modern wireless endpoints must complete STLS/TLS before CNXN or AUTH.
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

struct Route {
    closed: CancellationToken,
    remote: u32,
    awaiting_ack: bool,
    data: mpsc::Sender<ReceivedPayload>,
    ack: mpsc::Sender<u32>,
    trace: Option<Subscription>,
    burst: Option<crate::burst::Flow>,
}
impl Drop for Route {
    fn drop(&mut self) {
        self.closed.cancel();
    }
}
type Routes = Arc<Mutex<HashMap<u32, Route>>>;

enum ControlResponse {
    // Must follow frames already accepted for an existing logical stream.
    OrderedClose(Frame),
    // This device-initiated stream was never admitted, so it has no data order.
    RejectOpen(Frame),
}

static NEXT_CONNECTION_ID: AtomicU64 = AtomicU64::new(1);

struct Inner {
    server: Option<crate::server::Connection>,
    connection_id: u64,
    info: DeviceInfo,
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
        // Reader and stream drops never wait for writer capacity or spawn tasks.
        // A peer that exceeds the finite control allowance loses the connection.
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
            self.reverses.retire_server(server.clone());
        }
        self.cancellation.cancel();
    }
}

#[derive(Clone)]
pub struct Client {
    inner: Arc<Inner>,
}

impl Client {
    /// Attach to one exact official-server transport. Subsequent services use
    /// its transport ID, so reconnecting the same serial cannot retarget a live
    /// logical connection to a replacement device transport.
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
                server: Some(server),
                connection_id: NEXT_CONNECTION_ID.fetch_add(1, Ordering::Relaxed),
                info,
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
                // The official daemon has no 'never offer a public key' flag.
                // Background reconnect may reuse its authorized transport but
                // cannot create an unknown transport and provoke a dialog.
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
        bounded(
            options.operations.timeout,
            &options.operations.cancellation,
            async {
                let stream = TcpStream::connect(address).await?;
                crate::tcp::configure(&stream, &options.tcp)?;
                Self::connect_transport(stream, options.clone()).await
            },
        )
        .await
    }

    /// Connect to an adbd byte transport. USB adapters must preserve packet bytes, not USB transfer boundaries.
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
        let mut transport: Box<dyn Transport> = Box::new(transport);
        let operation_options = options.operations.clone();
        let (transport, info) = bounded(
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
                    // Before negotiation ADB restricts payloads to 4 KiB. New peers may omit checksums.
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
                                // Legacy adbd retries TOKEN after framework
                                // becomes ready during boot. Reoffer the same
                                // explicitly authorized key; the enclosing
                                // deadline/cancellation still bounds retries.
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
        Self::from_negotiated_transport_with_burst(transport, info, burst_mode)
    }

    /// Attach a transport after an external authenticated STLS/TLS connector has completed CNXN.
    pub fn from_negotiated_transport<T: Transport>(transport: T, info: DeviceInfo) -> Result<Self> {
        Self::from_negotiated_transport_with_burst(transport, info, false)
    }

    /// Attach an externally authenticated/negotiated transport. `burst_mode`
    /// must be true only if that connector actively advertised delayed_ack in
    /// its own CNXN; the peer feature is additionally required. The legacy
    /// attach method always retains classic flow control.
    pub fn from_negotiated_transport_with_burst<T: Transport>(
        transport: T,
        info: DeviceInfo,
        burst_mode: bool,
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
        let (mut reader, mut writer) = tokio::io::split(transport);
        // Credit never bypasses these bounded writers. Small latency-sensitive
        // control WRITEs may use the priority queue, while ordinary stream
        // frames retain FIFO order in the main queue.
        let (tx, mut rx) = mpsc::channel::<Frame>(64);
        let (priority_tx, mut priority_rx) = mpsc::channel::<Frame>(16);
        // Empty CLSEs have a separate bounded allowance, so a full data
        // writer cannot suspend inbound routing. Flooding this queue closes
        // the connection instead of allocating tasks or unbounded storage.
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
            connection_id,
            info,
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
        let skip_checksum = inner.info.version >= protocol::VERSION;
        let writer_failure = failure.clone();
        let writer_cancel = cancellation.clone();
        tokio::spawn(async move {
            loop {
                let (frame, preceding_priority, preceding) = tokio::select! {
                    biased;
                    _ = writer_cancel.cancelled() => break,
                    Some(response) = control_rx.recv() => match response {
                        ControlResponse::OrderedClose(frame) => (frame, priority_rx.len(), rx.len()),
                        ControlResponse::RejectOpen(frame) => (frame, 0, 0),
                    },
                    frame = priority_rx.recv() => match frame { Some(frame) => (frame, 0, 0), None => break },
                    frame = rx.recv() => match frame { Some(frame) => (frame, 0, 0), None => break },
                };
                // A control response must follow WRTE/OPEN/OKAY frames already
                // accepted for that stream. Route removal and data enqueue are
                // serialized by the route mutex. Snapshotting the bounded queue
                // preserves that order without starving control on later writes.
                let result = async {
                    for _ in 0..preceding_priority {
                        let queued = priority_rx.recv().await.ok_or(Error::Closed)?;
                        queued
                            .write_with_checksum(&mut writer, skip_checksum)
                            .await?;
                    }
                    for _ in 0..preceding {
                        let queued = rx.recv().await.ok_or(Error::Closed)?;
                        queued
                            .write_with_checksum(&mut writer, skip_checksum)
                            .await?;
                    }
                    frame.write_with_checksum(&mut writer, skip_checksum).await
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
        tokio::spawn(async move {
            loop {
                let receive = Frame::read_observed_progress(
                    &mut reader,
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
                        // One relaxed increment per nonempty transport read,
                        // including partial frames. No clocks or per-byte work.
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
                                        if route.ack.try_send(frame.arg0).is_err() {
                                            invalid = true;
                                        }
                                    }
                                }
                                protocol::OKAY if frame.payload.is_empty() => {
                                    // Classic ADB signals socket readiness, not byte
                                    // credit: adbd can send several OKAYs while
                                    // partially flushing a single WRTE. Coalesce
                                    // readiness while idle; it cannot pre-authorize
                                    // a later write or accumulate channel entries.
                                    if route.awaiting_ack {
                                        route.remote = frame.arg0;
                                        route.awaiting_ack = false;
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
                                        // Empty WRTEs consume no byte credit; do not let them
                                        // allocate unbounded receive/trace queue entries.
                                        if frame.payload.is_empty() {
                                            continue;
                                        }
                                    }
                                    // AOSP's EOF/error path flushes a final packet even
                                    // while an earlier WRTE awaits ACK. Preserve that
                                    // bounded tail instead of rejecting valid shells.
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
                                    // Older adbd also used a zero sender ID for
                                    // normal closes. Routes belong to this exact
                                    // transport, so accepting it cannot close a
                                    // different device's stream.
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

    /// Whether delayed_ack was actively negotiated by both ends of this connection.
    pub fn burst_mode(&self) -> bool {
        self.inner.burst_mode
    }

    pub fn info(&self) -> &DeviceInfo {
        &self.inner.info
    }
    pub fn is_closed(&self) -> bool {
        self.inner.cancellation.is_cancelled()
    }
    /// Opaque activity snapshot for this connection. Compare only for equality:
    /// a change means a nonempty inbound byte read, including partial headers
    /// and payloads, regardless of stream. Frame validation remains independent.
    /// The wrapping counter has no time or cross-connection meaning.
    pub fn inbound_activity(&self) -> usize {
        self.inner.inbound_activity.load(Ordering::Relaxed)
    }
    /// Opaque process-local transport identifier. Clones share it; new connections never reuse it.
    /// It is not a persistent device identity.
    pub fn connection_id(&self) -> u64 {
        self.inner.connection_id
    }

    /// Whether both handles share this exact transport. Clones do; reconnects
    /// do not, even when their device banners match. This is not a liveness test.
    pub fn same_connection(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    /// Last transport/protocol failure; excludes service payloads and identity secrets.
    pub fn close_reason(&self) -> Option<String> {
        self.inner.failure.lock().expect("failure mutex").clone()
    }
    pub fn close(&self) {
        if !self.inner.cancellation.is_cancelled()
            && let Some(server) = &self.inner.server
        {
            self.inner.reverses.retire_server(server.clone());
        }
        self.inner.cancellation.cancel();
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

    pub(crate) async fn open_service(
        &self,
        service: &[u8],
        options: OperationOptions,
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
            let socket = tokio::select! {
                _=self.inner.cancellation.cancelled()=>return Err(Error::Closed),
                result=server.open(service,&options,self.inner.cancellation.clone(),self.inner.inbound_activity.clone())=>result?,
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
    tokio::spawn(async move {
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
        // Read and write independently: awaiting a WRTE acknowledgment must not
        // stop consuming (and acknowledging) data in the other direction.
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
                // A remote CLSE also wakes a sender waiting on an ACK or byte credit.
                // Keep delivering already-routed input before closing its TCP
                // destination; selecting the woken writer must not lose tails.
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
        // Register before checking credit so an OKAY/CLSE cannot be lost.
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
            // A negative OKAY may have arrived while waiting for the writer.
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

/// A logical ADB stream. Reads acknowledge only consumed bytes (or complete
/// packets in classic mode), providing per-stream backpressure.
/// An interrupted write closes this stream because the peer's ACK state is then uncertain.
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
    /// Maximum payload accepted by one WRTE for this negotiated transport.
    /// Callers may use it to preserve complete control-message batches when
    /// coalescing byte-stream writes; `write_all` still performs the framing.
    pub fn max_payload(&self) -> usize {
        self.inner.info.max_payload
    }

    /// Place subsequent WRTE frames on the bounded priority writer queue.
    /// This changes transport scheduling only; it does not bypass per-stream
    /// ACKs/credit or permit concurrent writes on the same stream.
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
                // CLSE makes outstanding receive credit irrelevant. Do not let
                // a full writer queue prevent delivery of already-routed tails.
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

    /// Enable or disable bounded, per-WRTE receive timing for this stream.
    /// The clock must return monotonic microseconds in the caller's domain.
    /// It must be quick and must not call back into this client. Changing the
    /// clock discards pending diagnostics, never pending stream bytes.
    pub fn set_read_trace_clock(&mut self, clock: Option<fn() -> u64>) -> Result<()> {
        // Smart sockets expose service bytes, not the server's WRTE receive
        // boundaries. Do not fabricate transport timing from socket reads.
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

    /// The receipt for the WRTE that supplied the most recent nonempty read.
    pub fn read_trace(&self) -> Option<crate::ReadTrace> {
        self.read_trace
    }

    async fn send_open(&self, frame: Frame) -> Result<()> {
        let permit = tokio::select! {
            _ = self.inner.cancellation.cancelled() => return Err(Error::Closed),
            _ = self.closed.cancelled() => return Err(Error::Closed),
            permit = self.inner.writer.reserve() => permit.map_err(|_| Error::Closed)?,
        };
        // Serialize OPEN enqueue with route removal, just like WRTE/OKAY.
        // A close received while waiting for capacity must not be followed by
        // a late OPEN for that local ID after the ordered close response.
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
                        // Try synchronously so cancelling read cannot lose already-copied bytes.
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
                    // A close can follow the final WRTE; consume queued tail before reporting EOF.
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
        // Set before awaiting, so dropping this future cannot permit an ambiguous second write.
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
