//! 官方 adb-server smart socket。本路径不发送 CNXN/AUTH/STLS/WRTE 帧；随包官方 server 拥有每个设备传输与密钥。AOSP 协议来源：client/adb_client.cpp 的 switch_socket_transport、format_host_command。
use crate::{DeviceInfo, Error, OperationOptions, Result, error::bounded};
use std::{
    collections::HashSet,
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Debug)]
pub struct ServerDevice {
    pub serial: String,
    pub state: String,
    pub description: String,
}

pub(crate) async fn request(stream: &mut TcpStream, service: &[u8]) -> Result<()> {
    if service.is_empty() || service.len() > 65535 {
        return Err(Error::InvalidArgument("invalid smart socket service size"));
    }
    stream
        .write_all(format!("{:04x}", service.len()).as_bytes())
        .await?;
    stream.write_all(service).await?;
    status(stream).await
}
async fn protocol_string(stream: &mut TcpStream) -> Result<Vec<u8>> {
    let mut length = [0; 4];
    stream.read_exact(&mut length).await?;
    if !length.iter().all(u8::is_ascii_hexdigit) {
        return Err(Error::Protocol("invalid smart socket string length".into()));
    }
    let length = std::str::from_utf8(&length)
        .ok()
        .and_then(|s| usize::from_str_radix(s, 16).ok())
        .ok_or_else(|| Error::Protocol("invalid smart socket string length".into()))?;
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes).await?;
    Ok(bytes)
}
async fn status(stream: &mut TcpStream) -> Result<()> {
    let mut status = [0; 4];
    stream.read_exact(&mut status).await?;
    match &status {
        b"OKAY" => Ok(()),
        b"FAIL" => {
            let error = String::from_utf8_lossy(&protocol_string(stream).await?).into_owned();
            if error.contains("unauthorized") {
                Err(Error::AuthorizationRequired)
            } else {
                Err(Error::Remote(error))
            }
        }
        _ => Err(Error::Protocol("invalid smart socket status".into())),
    }
}
pub async fn query(
    address: SocketAddr,
    service: &str,
    options: &OperationOptions,
) -> Result<Vec<u8>> {
    bounded(options.timeout, &options.cancellation, async {
        let mut socket = TcpStream::connect(address).await?;
        socket.set_nodelay(true)?;
        request(&mut socket, service.as_bytes()).await?;
        protocol_string(&mut socket).await
    })
    .await
}
pub async fn devices(address: SocketAddr, options: &OperationOptions) -> Result<Vec<ServerDevice>> {
    let bytes = query(address, "host:devices-l", options).await?;
    let text = std::str::from_utf8(&bytes)
        .map_err(|_| Error::Protocol("device list is not UTF-8".into()))?;
    let mut result = Vec::new();
    for line in text.lines().filter(|l| !l.is_empty()) {
        let mut fields = line.split_ascii_whitespace();
        let serial = fields
            .next()
            .ok_or_else(|| Error::Protocol("device list has no serial".into()))?;
        let state = fields
            .next()
            .ok_or_else(|| Error::Protocol("device list has no state".into()))?;
        if result.len() >= 1024 {
            return Err(Error::OutputLimit);
        }
        result.push(ServerDevice {
            serial: serial.to_owned(),
            state: state.to_owned(),
            description: fields.collect::<Vec<_>>().join(" "),
        });
    }
    Ok(result)
}

/// 仅解析官方 server 发现的安全连接服务；把 fullname 原样交回 adb，保留其安全传输选择分支。
pub async fn tls_service(
    address: SocketAddr,
    endpoint: SocketAddr,
    options: &OperationOptions,
) -> Result<String> {
    let bytes = query(address, "host:mdns:services", options).await?;
    let text = std::str::from_utf8(&bytes)
        .map_err(|_| Error::Protocol("mDNS list is not UTF-8".into()))?;
    let mut found = None;
    for line in text.lines() {
        let fields = line.split_ascii_whitespace().collect::<Vec<_>>();
        if fields.len() != 3 || fields[1].trim_end_matches('.') != "_adb-tls-connect._tcp" {
            continue;
        }
        let Ok(candidate) = fields[2].parse::<SocketAddr>() else {
            continue;
        };
        if candidate != endpoint {
            continue;
        }
        let instance = fields[0];
        if instance.is_empty() || instance.len() > 256 || instance.contains([':', '/', '\\', '\0'])
        {
            return Err(Error::Protocol("invalid mDNS service instance".into()));
        }
        let name = format!("{instance}._adb-tls-connect._tcp");
        if found.as_ref().is_some_and(|previous| previous != &name) {
            return Err(Error::Protocol("ambiguous secure mDNS endpoint".into()));
        }
        found = Some(name);
    }
    found.ok_or(Error::Unsupported(
        "official adb requires a discovered secure mDNS service for forced TLS",
    ))
}

#[derive(Clone, Debug)]
pub(crate) struct Connection {
    pub address: SocketAddr,
    pub transport_id: u64,
}
impl Connection {
    pub async fn connect(
        address: SocketAddr,
        serial: &str,
        options: &OperationOptions,
    ) -> Result<(Self, DeviceInfo)> {
        let mut connected = false;
        let result = bounded(options.timeout, &options.cancellation, async {
            let mut socket = TcpStream::connect(address)
                .await
                .map_err(|error| Error::Connect(Box::new(error.into())))?;
            connected = true;
            socket.set_nodelay(true)?;
            request(
                &mut socket,
                format!("host:tport:serial:{serial}").as_bytes(),
            )
            .await?;
            let mut transport = [0; 8];
            socket.read_exact(&mut transport).await?;
            let transport_id = u64::from_le_bytes(transport);
            if transport_id == 0 {
                return Err(Error::Protocol("server selected invalid transport".into()));
            }
            drop(socket);
            let features = query(
                address,
                &format!("host-transport-id:{transport_id}:features"),
                options,
            )
            .await?;
            let features = std::str::from_utf8(&features)
                .map_err(|_| Error::Protocol("server features are not UTF-8".into()))?
                .split(',')
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .collect::<HashSet<_>>();
            Ok((
                Self {
                    address,
                    transport_id,
                },
                DeviceInfo {
                    version: crate::protocol::VERSION,
                    max_payload: 64 * 1024,
                    banner: format!("device::serial={serial}"),
                    features,
                },
            ))
        })
        .await;
        // 第一个 socket 尚未建立时的超时与 smart-socket 回执超时不同；
        // 外层仍覆盖 tport 和 features 的完整单次预算。
        result.map_err(|error| match error {
            Error::Timeout if !connected => Error::Connect(Box::new(error)),
            error => error,
        })
    }
    /// 官方服务器只公开 smart-socket 层；FAIL 也是本次服务请求的实际响应。
    pub(crate) async fn probe_open(
        &self,
        service: &[u8],
        options: &OperationOptions,
        cancellation: CancellationToken,
        activity: Arc<AtomicUsize>,
        trace: Arc<crate::client::OpenProbeTrace>,
    ) -> Result<()> {
        let work = bounded(options.timeout, &options.cancellation, async {
            let mut socket = TcpStream::connect(self.address).await?;
            socket.set_nodelay(true)?;
            request(
                &mut socket,
                format!("host:transport-id:{}", self.transport_id).as_bytes(),
            )
            .await
            .map_err(|error| match error {
                // 此阶段选择的是已固定的精确 transport，而非打开 sync 服务。
                // 明确 FAIL 证明该 transport 已不可用；普通 I/O/超时仍保留原语义。
                Error::Remote(_) | Error::AuthorizationRequired => Error::Closed,
                error => error,
            })?;
            socket
                .write_all(format!("{:04x}", service.len()).as_bytes())
                .await?;
            socket.write_all(service).await?;
            trace.written();
            let mut reply = [0; 4];
            let mut received = 0;
            while received < reply.len() {
                let count = socket.read(&mut reply[received..]).await?;
                if count == 0 {
                    return Err(Error::Closed);
                }
                activity.fetch_add(1, Ordering::Relaxed);
                received += count;
            }
            match &reply {
                b"OKAY" => trace.response(crate::OpenProbeOutcome::Okay),
                b"FAIL" => trace.response(crate::OpenProbeOutcome::Rejected),
                _ => return Err(Error::Protocol("invalid smart socket status".into())),
            }
            // 仅确认响应头即可；不读 FAIL 说明，也不等待 sync 服务主动产生数据。
            Ok(())
        });
        tokio::select! { biased; _ = cancellation.cancelled() => Err(Error::Closed), result = work => result }
    }

    pub async fn open(
        &self,
        service: &[u8],
        options: &OperationOptions,
        cancellation: CancellationToken,
        activity: Arc<AtomicUsize>,
        completion: Option<crate::client::DriverGuard>,
    ) -> Result<Stream> {
        bounded(options.timeout, &options.cancellation, async {
            let mut socket = TcpStream::connect(self.address).await?;
            socket.set_nodelay(true)?;
            request(
                &mut socket,
                format!("host:transport-id:{}", self.transport_id).as_bytes(),
            )
            .await?;
            request(&mut socket, service).await?;
            Stream::new(socket, cancellation, activity, completion)
        })
        .await
    }
}

// 流、独立 writer 和关闭监听共享同一资源；最后一个所有者释放两个描述符后才报告完成。
struct Socket {
    socket: TcpStream,
    shutdown: std::net::TcpStream,
    _completion: Option<crate::client::DriverGuard>,
}
pub(crate) struct Stream {
    socket: Arc<Socket>,
    stop: CancellationToken,
    activity: Arc<AtomicUsize>,
}
impl Stream {
    fn new(
        socket: TcpStream,
        cancellation: CancellationToken,
        activity: Arc<AtomicUsize>,
        completion: Option<crate::client::DriverGuard>,
    ) -> Result<Self> {
        // 复制描述符仅用于 shutdown，不作中转。Client 释放时立即关闭空闲服务 socket。
        let socket = socket.into_std()?;
        let shutdown = socket.try_clone()?;
        let socket = TcpStream::from_std(socket)?;
        let socket = Arc::new(Socket {
            socket,
            shutdown,
            _completion: completion,
        });
        let stop = CancellationToken::new();
        let stopping = stop.clone();
        let closing = socket.clone();
        tokio::spawn(async move {
            tokio::select! {_=cancellation.cancelled()=>{},_=stopping.cancelled()=>{}};
            let _ = closing.shutdown.shutdown(std::net::Shutdown::Both);
        });
        Ok(Self {
            socket,
            stop,
            activity,
        })
    }
    pub async fn read(&mut self, output: &mut [u8]) -> Result<usize> {
        let n = loop {
            self.socket.socket.readable().await?;
            match self.socket.socket.try_read(output) {
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                result => break result?,
            }
        };
        if n > 0 {
            self.activity.fetch_add(1, Ordering::Relaxed);
        }
        Ok(n)
    }
    pub async fn write_all(&mut self, bytes: &[u8]) -> Result<()> {
        self.writer().write_all(bytes).await
    }
    pub async fn close(&mut self) -> Result<()> {
        self.stop.cancel();
        self.socket.shutdown.shutdown(std::net::Shutdown::Both)?;
        Ok(())
    }

    pub(crate) fn writer(&self) -> Writer {
        Writer {
            socket: self.socket.clone(),
            stop: self.stop.clone(),
        }
    }
}
pub(crate) struct Writer {
    socket: Arc<Socket>,
    stop: CancellationToken,
}
impl Writer {
    pub fn close(&self) {
        self.stop.cancel();
        let _ = self.socket.shutdown.shutdown(std::net::Shutdown::Both);
    }
    pub async fn write_all(&mut self, mut bytes: &[u8]) -> Result<()> {
        while !bytes.is_empty() {
            self.socket.socket.writable().await?;
            match self.socket.socket.try_write(bytes) {
                Ok(0) => return Err(std::io::Error::from(std::io::ErrorKind::WriteZero).into()),
                Ok(count) => bytes = &bytes[count..],
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(error) => return Err(error.into()),
            }
        }
        Ok(())
    }
}
impl Drop for Stream {
    fn drop(&mut self) {
        // 关闭本机 socket 不依赖另一个任务被调度；不把它当作 server 已转发 CLSE 的回执。
        let _ = self.socket.shutdown.shutdown(std::net::Shutdown::Both);
        self.stop.cancel();
    }
}
