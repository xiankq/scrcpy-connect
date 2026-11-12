//! 设备侧 reverse 监听与受白名单限制的主机 TCP 桥。使用 adbd reverse: 协议，不是 adb server 的 host:forward 协议。
use crate::{Client, Error, OperationOptions, Result, error::bounded};
use rsa::rand_core::RngCore;
use std::{collections::HashMap, net::SocketAddr, sync::Mutex, time::Duration};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReverseSocket {
    /// 零表示请求设备临时端口；返回的绑定包含实际端口。
    Tcp(u16),
    LocalAbstract(String),
    LocalFilesystem(String),
}
impl ReverseSocket {
    fn service(&self) -> Result<String> {
        match self {
            Self::Tcp(port) => Ok(format!("tcp:{port}")),
            Self::LocalAbstract(name) | Self::LocalFilesystem(name) => {
                if name.is_empty()
                    || name.len() > 107
                    || name
                        .bytes()
                        .any(|byte| byte == 0 || byte == b';' || byte.is_ascii_whitespace())
                {
                    return Err(Error::InvalidArgument(
                        "reverse socket name is empty, too long, or contains a protocol delimiter",
                    ));
                }
                Ok(format!(
                    "{}:{name}",
                    if matches!(self, Self::LocalAbstract(_)) {
                        "localabstract"
                    } else {
                        "localfilesystem"
                    }
                ))
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReverseBinding {
    pub device: ReverseSocket,
    pub destination: SocketAddr,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReverseMapping {
    pub serial: String,
    pub device_service: String,
    pub host_service: String,
}

#[derive(Clone, Copy)]
pub(crate) struct Destination {
    pub address: SocketAddr,
    pub connect_timeout: Duration,
}
#[derive(Default)]
struct RegistryState {
    destinations: HashMap<String, Destination>,
    bindings: HashMap<String, String>,
    server_listeners: HashMap<String, tokio_util::sync::CancellationToken>,
}
#[derive(Default)]
pub(crate) struct Registry(Mutex<RegistryState>, tokio::sync::Mutex<()>);
impl Registry {
    pub(crate) fn retire_server(
        &self,
        server: crate::server::Connection,
        completion: Option<crate::client::DriverGuard>,
    ) {
        let bindings = {
            let mut state = self.0.lock().expect("reverse registry mutex");
            for stop in state.server_listeners.values() {
                stop.cancel();
            }
            state.server_listeners.clear();
            std::mem::take(&mut state.bindings)
        };
        if bindings.is_empty() {
            return;
        }
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            runtime.spawn(async move {
                // 官方 transport 生命周期长于 Rust Client。仅移除精确拥有的映射，并固定原 transport ID，避免影响替代设备连接。
                let cleanup = async {
                    let bytes =
                        server_reverse_request(&server, "list-forward", completion.as_ref())
                            .await?;
                    let text = std::str::from_utf8(protocol_string(&bytes)?)
                        .map_err(|_| Error::Protocol("invalid reverse list".into()))?;
                    for line in text.lines() {
                        let fields = line.split_ascii_whitespace().collect::<Vec<_>>();
                        if fields.len() == 3
                            && bindings
                                .get(fields[1])
                                .is_some_and(|host| host == fields[2])
                        {
                            let _ = server_reverse_request(
                                &server,
                                &format!("killforward:{}", fields[1]),
                                completion.as_ref(),
                            )
                            .await;
                        }
                    }
                    Ok::<_, Error>(())
                };
                let _ = tokio::time::timeout(Duration::from_secs(3), cleanup).await;
            });
        }
    }
    pub fn destination(&self, service: &[u8]) -> Option<Destination> {
        let service = std::str::from_utf8(service).ok()?;
        self.0
            .lock()
            .expect("reverse registry mutex")
            .destinations
            .get(service)
            .copied()
    }
    fn remove(&self, device: &str) {
        let mut state = self.0.lock().expect("reverse registry mutex");
        if let Some(service) = state.bindings.remove(device) {
            state.destinations.remove(&service);
            if let Some(stop) = state.server_listeners.remove(&service) {
                stop.cancel();
            }
        }
    }
}

async fn server_reverse_request(
    server: &crate::server::Connection,
    command: &str,
    completion: Option<&crate::client::DriverGuard>,
) -> Result<Vec<u8>> {
    let options = OperationOptions {
        timeout: Duration::from_secs(3),
        ..Default::default()
    };
    bounded(options.timeout, &options.cancellation, async {
        let mut stream = server
            .open(
                format!("reverse:{command}").as_bytes(),
                &options,
                tokio_util::sync::CancellationToken::new(),
                std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0)),
                completion.map(crate::client::DriverGuard::child),
            )
            .await?;
        let mut bytes = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let n = stream.read(&mut buffer).await?;
            if n == 0 {
                break;
            }
            if bytes.len() + n > 65543 {
                return Err(Error::OutputLimit);
            }
            bytes.extend_from_slice(&buffer[..n]);
        }
        Ok(bytes)
    })
    .await
}

impl Drop for Registry {
    fn drop(&mut self) {
        for stop in self
            .0
            .get_mut()
            .expect("reverse registry mutex")
            .server_listeners
            .values()
        {
            stop.cancel();
        }
    }
}

struct Registration {
    client: Client,
    token: String,
    committed: bool,
}
impl Drop for Registration {
    fn drop(&mut self) {
        if self.committed {
            return;
        }
        {
            let mut state = self
                .client
                .reverse_registry()
                .0
                .lock()
                .expect("reverse registry mutex");
            state.destinations.remove(&self.token);
            if let Some(stop) = state.server_listeners.remove(&self.token) {
                stop.cancel();
            }
        }
        // OPEN 在超时或取消前可能已安装临时监听；仅移除携带本次随机操作 token 的监听。
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            let client = self.client.clone();
            let token = self.token.clone();
            runtime.spawn(async move {
                let _transaction = client.reverse_registry().1.lock().await;
                let options = OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                };
                if let Ok(entries) = client.reverse_list(options.clone()).await {
                    for entry in entries
                        .into_iter()
                        .filter(|entry| entry.host_service == token)
                    {
                        let _ = client
                            .reverse_request(
                                &format!("killforward:{}", entry.device_service),
                                options.clone(),
                            )
                            .await;
                    }
                }
            });
        }
    }
}

fn hex_length(bytes: &[u8]) -> Result<usize> {
    if bytes.len() != 4 || !bytes.iter().all(u8::is_ascii_hexdigit) {
        return Err(Error::Protocol("invalid reverse protocol length".into()));
    }
    usize::from_str_radix(std::str::from_utf8(bytes).expect("ASCII"), 16)
        .map_err(|_| Error::Protocol("invalid reverse protocol length".into()))
}
fn protocol_string(bytes: &[u8]) -> Result<&[u8]> {
    if bytes.len() < 4 {
        return Err(Error::Protocol("truncated reverse protocol string".into()));
    }
    let length = hex_length(&bytes[..4])?;
    if length != bytes.len() - 4 {
        return Err(Error::Protocol(
            "reverse protocol string length mismatch".into(),
        ));
    }
    Ok(&bytes[4..])
}
fn status(bytes: &[u8]) -> Result<&[u8]> {
    match bytes.get(..4) {
        Some(b"OKAY") => Ok(&bytes[4..]),
        Some(b"FAIL") => Err(Error::Remote(
            String::from_utf8_lossy(protocol_string(&bytes[4..])?).into_owned(),
        )),
        _ => Err(Error::Protocol("invalid reverse service status".into())),
    }
}

impl Client {
    async fn reverse_request(&self, command: &str, options: OperationOptions) -> Result<Vec<u8>> {
        bounded(options.timeout, &options.cancellation, async {
            let mut stream = self
                .open(&format!("reverse:{command}"), options.clone())
                .await?;
            let mut bytes = Vec::new();
            let mut buffer = [0; 4096];
            loop {
                let count = stream.read(&mut buffer).await?;
                if count == 0 {
                    break;
                }
                if bytes.len() + count > 65543 {
                    return Err(Error::OutputLimit);
                }
                bytes.extend_from_slice(&buffer[..count]);
            }
            Ok(bytes)
        })
        .await
    }

    /// 登记设备监听，并将连接桥接到显式授权的主机 TCP 地址。监听持续到显式移除或传输断开，释放返回的元数据不会移除监听；仅此处安装的不透明端点可接纳设备发起的 OPEN。
    pub async fn reverse_forward(
        &self,
        device: &ReverseSocket,
        destination: SocketAddr,
        no_rebind: bool,
        options: OperationOptions,
    ) -> Result<ReverseBinding> {
        if destination.port() == 0 {
            return Err(Error::InvalidArgument(
                "reverse destination requires a nonzero port",
            ));
        }
        let device_service = device.service()?;
        // 串行化变更，避免并发重绑/移除的完成顺序与 adbd 不同而错误覆盖本地白名单。
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let mut random = [0; 16];
        rsa::rand_core::OsRng.fill_bytes(&mut random);
        let token = if self.uses_server() {
            // 官方 server 仅接受自身回环接口的 tcp:port 目标；拥有的监听保留任意显式主机目标，无需委托 Rust ADB 传输。
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            let token = format!("tcp:{}", listener.local_addr()?.port());
            let stop = self.cancellation().child_token();
            self.reverse_registry()
                .0
                .lock()
                .expect("reverse registry mutex")
                .server_listeners
                .insert(token.clone(), stop.clone());
            let timeout = options.timeout;
            let drivers = self.track_driver()?;
            self.spawn_driver(async move {
                let limit = std::sync::Arc::new(tokio::sync::Semaphore::new(32));
                loop {
                    let accepted = tokio::select! {
                        _ = stop.cancelled() => break,
                        accepted = listener.accept() => accepted,
                    };
                    let Ok((mut incoming, _)) = accepted else {
                        break;
                    };
                    let Ok(permit) = limit.clone().try_acquire_owned() else {
                        continue;
                    };
                    let stopping = stop.clone();
                    let _ = drivers.spawn(async move {
                        let _permit = permit;
                        tokio::select! {
                            _=stopping.cancelled()=>{},
                            _=async {
                                if let Ok(Ok(mut host)) = tokio::time::timeout(timeout, tokio::net::TcpStream::connect(destination)).await {
                                    let _=tokio::io::copy_bidirectional(&mut incoming,&mut host).await;
                                }
                            }=>{},
                        }
                    });
                }
            })?;
            token
        } else {
            format!(
                "localabstract:interop-reverse-{}",
                random
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<String>()
            )
        };
        let mut guard = Registration {
            client: self.clone(),
            token: token.clone(),
            committed: false,
        };
        {
            let mut state = self
                .reverse_registry()
                .0
                .lock()
                .expect("reverse registry mutex");
            if state.destinations.len() >= 128 {
                return Err(Error::InvalidArgument("maximum reverse listeners reached"));
            }
            state.destinations.insert(
                token.clone(),
                Destination {
                    address: destination,
                    connect_timeout: options.timeout,
                },
            );
        }
        let bytes = self
            .reverse_request(
                &format!(
                    "forward:{}{device_service};{token}",
                    if no_rebind { "norebind:" } else { "" }
                ),
                options,
            )
            .await?;
        let extra = status(&bytes)?;
        let actual = if !extra.is_empty() {
            let port = std::str::from_utf8(protocol_string(extra)?)
                .ok()
                .and_then(|port| port.parse::<u16>().ok())
                .filter(|port| *port != 0)
                .ok_or_else(|| Error::Protocol("invalid resolved reverse TCP port".into()))?;
            if !matches!(device, ReverseSocket::Tcp(_)) {
                return Err(Error::Protocol(
                    "unexpected reverse TCP port for Unix listener".into(),
                ));
            }
            ReverseSocket::Tcp(port)
        } else {
            if matches!(device, ReverseSocket::Tcp(0)) {
                return Err(Error::Protocol(
                    "adbd did not return the allocated reverse port".into(),
                ));
            }
            device.clone()
        };
        let mut state = self
            .reverse_registry()
            .0
            .lock()
            .expect("reverse registry mutex");
        // 与 close 的同一 registry 锁核验撤销，避免清理快照之后又发布迟到映射。
        if self.is_closed() {
            return Err(Error::Closed);
        }
        if let Some(previous) = state.bindings.insert(actual.service()?, token) {
            state.destinations.remove(&previous);
            if let Some(stop) = state.server_listeners.remove(&previous) {
                stop.cancel();
            }
        }
        guard.committed = true;
        Ok(ReverseBinding {
            device: actual,
            destination,
        })
    }

    /// 设备监听表，adbd 可能在多个已连接主控之间共享它。
    pub async fn reverse_list(&self, options: OperationOptions) -> Result<Vec<ReverseMapping>> {
        let bytes = self.reverse_request("list-forward", options).await?;
        if bytes.starts_with(b"FAIL") {
            status(&bytes)?;
        }
        let text = std::str::from_utf8(protocol_string(&bytes)?)
            .map_err(|_| Error::Protocol("reverse listener table is not UTF-8".into()))?;
        let mut result = Vec::new();
        for line in text.lines() {
            let fields = line.split_ascii_whitespace().collect::<Vec<_>>();
            if fields.len() != 3 || result.len() >= 1024 {
                return Err(Error::Protocol(
                    "invalid or oversized reverse listener table".into(),
                ));
            }
            result.push(ReverseMapping {
                serial: fields[0].to_owned(),
                device_service: fields[1].to_owned(),
                host_service: fields[2].to_owned(),
            });
        }
        Ok(result)
    }

    pub async fn reverse_remove(
        &self,
        device: &ReverseSocket,
        options: OperationOptions,
    ) -> Result<()> {
        let service = device.service()?;
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let bytes = self
            .reverse_request(&format!("killforward:{service}"), options)
            .await?;
        if !status(&bytes)?.is_empty() {
            return Err(Error::Protocol(
                "unexpected reverse removal response".into(),
            ));
        }
        self.reverse_registry().remove(&service);
        Ok(())
    }

    /// 移除 adbd 完整 reverse 监听表，包含其他主控的监听；单个自有绑定优先使用 reverse_remove。
    pub async fn reverse_remove_all(&self, options: OperationOptions) -> Result<()> {
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let bytes = self.reverse_request("killforward-all", options).await?;
        if !status(&bytes)?.is_empty() {
            return Err(Error::Protocol(
                "unexpected reverse removal response".into(),
            ));
        }
        let mut state = self
            .reverse_registry()
            .0
            .lock()
            .expect("reverse registry mutex");
        for stop in state.server_listeners.values() {
            stop.cancel();
        }
        *state = RegistryState::default();
        Ok(())
    }
}
