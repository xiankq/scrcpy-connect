use crate::{
    Error, Identity, Result,
    error::bounded,
    protocol::{self, Frame},
};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU32, Ordering},
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
    pub identity: Option<Identity>,
    /// Explicitly allow a device authorization prompt after the key signature is rejected.
    pub request_authorization: bool,
    pub public_key_comment: String,
    pub tls: Option<crate::wireless::TlsConfig>,
    pub operations: OperationOptions,
}
impl Default for ConnectOptions {
    fn default() -> Self {
        Self {
            identity: None,
            request_authorization: false,
            public_key_comment: "interop-adb".into(),
            tls: None,
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
    remote: u32,
    awaiting_ack: bool,
    data: mpsc::Sender<Vec<u8>>,
    ack: mpsc::Sender<u32>,
}
type Routes = Arc<Mutex<HashMap<u32, Route>>>;

struct Inner {
    info: DeviceInfo,
    writer: mpsc::Sender<Frame>,
    routes: Routes,
    next_id: AtomicU32,
    cancellation: CancellationToken,
    failure: Arc<Mutex<Option<String>>>,
    reverses: Arc<crate::reverse::Registry>,
}
impl Inner {
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
        self.cancellation.cancel();
    }
}

#[derive(Clone)]
pub struct Client {
    inner: Arc<Inner>,
}

impl Client {
    pub async fn connect_tcp(address: impl ToSocketAddrs, options: ConnectOptions) -> Result<Self> {
        bounded(
            options.operations.timeout,
            &options.operations.cancellation,
            async {
                let stream = TcpStream::connect(address).await?;
                stream.set_nodelay(true)?;
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
        if let (Some(identity), Some(tls)) = (&options.identity, &options.tls)
            && !tls.matches_identity(identity)?
        {
            return Err(Error::Identity(
                "AUTH and TLS must use the same host identity".into(),
            ));
        }
        let mut transport: Box<dyn Transport> = Box::new(transport);
        let operation_options = options.operations.clone();
        let (transport, info) = bounded(
            operation_options.timeout,
            &operation_options.cancellation,
            async move {
            let banner = b"host::features=shell_v2,cmd,stat_v2,ls_v2,abb,abb_exec,sendrecv_v2,sendrecv_v2_brotli,sendrecv_v2_lz4,sendrecv_v2_zstd;\0".to_vec();
                Frame::new(
                    protocol::CNXN,
                    protocol::VERSION,
                    protocol::MAX_PAYLOAD as u32,
                    banner,
                )
                .write(&mut transport)
                .await?;
                let mut signed = false;
                let mut offered = false;
                let mut upgraded = false;
                loop {
                    // Before negotiation ADB restricts payloads to 4 KiB. New peers may omit checksums.
                    let frame = Frame::read(&mut transport, 4096, true).await?;
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
                            } else if options.request_authorization && !offered {
                                offered = true;
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
        Self::from_negotiated_transport(transport, info)
    }

    /// Attach a transport after an external authenticated STLS/TLS connector has completed CNXN.
    pub fn from_negotiated_transport<T: Transport>(transport: T, info: DeviceInfo) -> Result<Self> {
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
        let (tx, mut rx) = mpsc::channel::<Frame>(64);
        let routes: Routes = Arc::new(Mutex::new(HashMap::new()));
        let cancellation = CancellationToken::new();
        let failure = Arc::new(Mutex::new(None));
        let inner = Arc::new(Inner {
            info,
            writer: tx.clone(),
            routes: routes.clone(),
            next_id: AtomicU32::new(1),
            cancellation: cancellation.clone(),
            failure: failure.clone(),
            reverses: Default::default(),
        });
        let writer_failure = failure.clone();
        let writer_cancel = cancellation.clone();
        tokio::spawn(async move {
            loop {
                let frame = tokio::select! { _ = writer_cancel.cancelled() => break, frame = rx.recv() => match frame { Some(frame) => frame, None => break } };
                let result = tokio::select! { _ = writer_cancel.cancelled() => break, result = frame.write(&mut writer) => result };
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
        let read_tx = tx.clone();
        let max_payload = inner.info.max_payload.min(protocol::MAX_PAYLOAD);
        let skip_checksum = inner.info.version >= protocol::VERSION;
        let read_failure = failure.clone();
        let read_inner = Arc::downgrade(&inner);
        tokio::spawn(async move {
            loop {
                let frame = tokio::select! { _ = read_cancel.cancelled() => break, frame = Frame::read(&mut reader, max_payload, skip_checksum) => match frame { Ok(frame) => frame, Err(error) => { *read_failure.lock().expect("failure mutex") = Some(format!("transport read: {error}")); break; } } };
                if frame.command == protocol::OPEN {
                    if let Some(inner) = read_inner.upgrade() {
                        accept_reverse(inner, frame);
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
                    if let Some(route) = routes.get_mut(&frame.arg1) {
                        route_description = Some((route.remote, route.awaiting_ack));
                        if frame.command != protocol::CLSE
                            && (frame.arg0 == 0
                                || (route.remote != 0 && route.remote != frame.arg0))
                        {
                            invalid = true;
                        } else {
                            match frame.command {
                                protocol::OKAY
                                    if frame.payload.is_empty() && route.awaiting_ack =>
                                {
                                    route.remote = frame.arg0;
                                    route.awaiting_ack = false;
                                    if route.ack.try_send(frame.arg0).is_err() {
                                        invalid = true;
                                    }
                                }
                                protocol::WRTE if route.remote != 0 => {
                                    // AOSP's EOF/error path flushes a final packet even
                                    // while an earlier WRTE awaits ACK. Preserve that
                                    // bounded tail instead of rejecting valid shells.
                                    if route.data.try_send(frame.payload).is_err() {
                                        invalid = true;
                                    }
                                }
                                protocol::CLSE
                                    if route.remote == 0 || frame.arg0 == route.remote =>
                                {
                                    response = Some(Frame::new(
                                        protocol::CLSE,
                                        frame.arg1,
                                        frame.arg0,
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
                }
                if invalid {
                    *read_failure.lock().expect("failure mutex") = Some(format!(
                        "invalid stream state: (command,arg0,arg1,length)={description:?} (remote,awaiting_ack)={route_description:?}"
                    ));
                    break;
                }
                if let Some(response) = response
                    && read_tx.send(response).await.is_err()
                {
                    break;
                }
            }
            read_cancel.cancel();
            read_routes.lock().expect("route mutex poisoned").clear();
        });
        Ok(Self { inner })
    }

    pub fn info(&self) -> &DeviceInfo {
        &self.inner.info
    }
    pub fn is_closed(&self) -> bool {
        self.inner.cancellation.is_cancelled()
    }
    /// Last transport/protocol failure; excludes service payloads and identity secrets.
    pub fn close_reason(&self) -> Option<String> {
        self.inner.failure.lock().expect("failure mutex").clone()
    }
    pub fn close(&self) {
        self.inner.cancellation.cancel();
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
        let local = self.inner.next_stream_id()?;
        let (data_tx, data) = mpsc::channel(2);
        let (ack_tx, ack) = mpsc::channel(2);
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
                    remote: 0,
                    awaiting_ack: true,
                    data: data_tx,
                    ack: ack_tx,
                },
            );
        }
        let mut stream = AdbStream {
            inner: self.inner.clone(),
            local,
            remote: 0,
            data,
            ack,
            buffer: Vec::new(),
            offset: 0,
            pending_ack: false,
            options,
            eof: false,
            poisoned: false,
        };
        let mut payload = service.to_vec();
        payload.push(0);
        let open_options = stream.options.clone();
        let result = bounded(open_options.timeout, &open_options.cancellation, async {
            stream
                .send(Frame::new(protocol::OPEN, local, 0, payload))
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

fn accept_reverse(inner: Arc<Inner>, frame: Frame) {
    let reject = |inner: &Inner| {
        if inner
            .writer
            .try_send(Frame::new(protocol::CLSE, 0, frame.arg0, Vec::new()))
            .is_err()
        {
            inner.cancellation.cancel();
        }
    };
    let service = frame.payload.strip_suffix(&[0]).unwrap_or(&frame.payload);
    let destination =
        if frame.arg0 != 0 && frame.arg1 == 0 && service.len() <= 1024 && !service.contains(&0) {
            inner.reverses.destination(service)
        } else {
            None
        };
    let Some(destination) = destination else {
        reject(&inner);
        return;
    };
    let Ok(local) = inner.next_stream_id() else {
        reject(&inner);
        return;
    };
    let (data_tx, data) = mpsc::channel(2);
    let (ack_tx, ack) = mpsc::channel(2);
    {
        let mut routes = inner.routes.lock().expect("route mutex poisoned");
        if routes.len() >= 128 || routes.values().any(|route| route.remote == frame.arg0) {
            drop(routes);
            reject(&inner);
            return;
        }
        routes.insert(
            local,
            Route {
                remote: frame.arg0,
                awaiting_ack: false,
                data: data_tx,
                ack: ack_tx,
            },
        );
    }
    let mut stream = AdbStream {
        inner: inner.clone(),
        local,
        remote: frame.arg0,
        data,
        ack,
        buffer: Vec::new(),
        offset: 0,
        pending_ack: false,
        options: OperationOptions {
            timeout: Duration::from_secs(365 * 86400),
            cancellation: CancellationToken::new(),
        },
        eof: false,
        poisoned: false,
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
        if stream
            .send(Frame::new(protocol::OKAY, local, frame.arg0, Vec::new()))
            .await
            .is_err()
        {
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
                )
                .await?;
            }
        };
        tokio::select! {
            _ = inner.cancellation.cancelled() => {},
            _ = from_device_task => {},
            _ = from_host_task => {},
        }
    });
}

async fn write_stream_frames(
    inner: &Inner,
    local: u32,
    remote: u32,
    acknowledgments: &mut mpsc::Receiver<u32>,
    bytes: &[u8],
) -> Result<()> {
    for chunk in bytes.chunks(inner.info.max_payload) {
        {
            let mut routes = inner.routes.lock().expect("route mutex poisoned");
            let route = routes.get_mut(&local).ok_or(Error::Closed)?;
            if route.awaiting_ack {
                return Err(Error::Protocol(
                    "a stream write is already awaiting acknowledgement".into(),
                ));
            }
            route.awaiting_ack = true;
        }
        tokio::select! {
            _ = inner.cancellation.cancelled() => return Err(Error::Closed),
            result = inner.writer.send(Frame::new(protocol::WRTE, local, remote, chunk.to_vec())) => {
                result.map_err(|_| Error::Closed)?;
            }
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

/// A logical ADB stream. Reads acknowledge only consumed packets, providing per-stream backpressure.
/// An interrupted write closes this stream because the peer's ACK state is then uncertain.
pub struct AdbStream {
    inner: Arc<Inner>,
    local: u32,
    remote: u32,
    data: mpsc::Receiver<Vec<u8>>,
    ack: mpsc::Receiver<u32>,
    buffer: Vec<u8>,
    offset: usize,
    pending_ack: bool,
    options: OperationOptions,
    eof: bool,
    poisoned: bool,
}

impl AdbStream {
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
        bounded(options.timeout, &options.cancellation, async {
            loop {
                if self.offset < self.buffer.len() {
                    let count = output.len().min(self.buffer.len() - self.offset);
                    output[..count].copy_from_slice(&self.buffer[self.offset..self.offset + count]);
                    self.offset += count;
                    if self.offset == self.buffer.len() && self.pending_ack {
                        // Try synchronously so cancelling read cannot lose already-copied bytes.
                        let ack = Frame::new(protocol::OKAY, self.local, self.remote, Vec::new());
                        if self.inner.writer.try_send(ack).is_ok() {
                            self.pending_ack = false;
                        }
                    }
                    return Ok(count);
                }
                if self.pending_ack {
                    // A close can follow the final WRTE; consume queued tail before reporting EOF.
                    if !self.inner.cancellation.is_cancelled() {
                        self.send(Frame::new(
                            protocol::OKAY,
                            self.local,
                            self.remote,
                            Vec::new(),
                        ))
                        .await?;
                    }
                    self.pending_ack = false;
                }
                if self.eof {
                    return Ok(0);
                }
                match self.data.recv().await {
                    Some(bytes) => {
                        self.buffer = bytes;
                        self.offset = 0;
                        self.pending_ack = true;
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
        let result = bounded(options.timeout, &options.cancellation, async {
            write_stream_frames(&self.inner, self.local, self.remote, &mut self.ack, bytes).await?;
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
        let route = self
            .inner
            .routes
            .lock()
            .expect("route mutex poisoned")
            .remove(&self.local);
        if self.remote == 0
            && let Some(route) = route
        {
            self.remote = route.remote;
        }
        if self.eof {
            return;
        }
        let frame = Frame::new(protocol::CLSE, self.local, self.remote, Vec::new());
        if let Err(mpsc::error::TrySendError::Full(frame)) = self.inner.writer.try_send(frame) {
            let tx = self.inner.writer.clone();
            let cancel = self.inner.cancellation.clone();
            if let Ok(runtime) = tokio::runtime::Handle::try_current() {
                runtime.spawn(async move {
                    tokio::select! { _ = cancel.cancelled() => {}, _ = tx.send(frame) => {} }
                });
            }
        }
        self.eof = true;
    }
}
impl Drop for AdbStream {
    fn drop(&mut self) {
        self.close_now();
    }
}
