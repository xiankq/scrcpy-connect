//! Official adb-server smart sockets. This path sends no CNXN/AUTH/STLS/WRTE
//! frames: the bundled official server owns each device transport and keys.
//!
//! AOSP protocol: client/adb_client.cpp switch_socket_transport, format_host_command.
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

/// Resolve only official-server-discovered secure connect services. Passing
/// this fullname back to adb preserves its secure-transport selection branch.
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
        bounded(options.timeout, &options.cancellation, async {
            let mut socket = TcpStream::connect(address).await?;
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
        .await
    }
    pub async fn open(
        &self,
        service: &[u8],
        options: &OperationOptions,
        cancellation: CancellationToken,
        activity: Arc<AtomicUsize>,
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
            Stream::new(socket, cancellation, activity)
        })
        .await
    }
}

pub(crate) struct Stream {
    socket: Arc<TcpStream>,
    stop: CancellationToken,
    activity: Arc<AtomicUsize>,
}
impl Stream {
    fn new(
        socket: TcpStream,
        cancellation: CancellationToken,
        activity: Arc<AtomicUsize>,
    ) -> Result<Self> {
        // A duplicate descriptor is used only for shutdown, never as a relay.
        // Idle service sockets close immediately when their Client is retired.
        let socket = socket.into_std()?;
        let shutdown = socket.try_clone()?;
        let socket = TcpStream::from_std(socket)?;
        let stop = CancellationToken::new();
        let stopping = stop.clone();
        tokio::spawn(async move {
            tokio::select! {_=cancellation.cancelled()=>{},_=stopping.cancelled()=>{}};
            let _ = shutdown.shutdown(std::net::Shutdown::Both);
        });
        Ok(Self {
            socket: Arc::new(socket),
            stop,
            activity,
        })
    }
    pub async fn read(&mut self, output: &mut [u8]) -> Result<usize> {
        let n = loop {
            self.socket.readable().await?;
            match self.socket.try_read(output) {
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
    socket: Arc<TcpStream>,
    stop: CancellationToken,
}
impl Writer {
    pub fn close(&self) {
        self.stop.cancel();
    }
    pub async fn write_all(&mut self, mut bytes: &[u8]) -> Result<()> {
        while !bytes.is_empty() {
            self.socket.writable().await?;
            match self.socket.try_write(bytes) {
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
        self.stop.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn service(socket: &mut TcpStream) -> String {
        let mut length = [0; 4];
        socket.read_exact(&mut length).await.unwrap();
        let count = usize::from_str_radix(std::str::from_utf8(&length).unwrap(), 16).unwrap();
        let mut bytes = vec![0; count];
        socket.read_exact(&mut bytes).await.unwrap();
        String::from_utf8(bytes).unwrap()
    }
    #[tokio::test]
    async fn official_transport_pins_id_and_delivers_raw_bytes_without_adb_frames() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let fixture = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(service(&mut socket).await, "host:tport:serial:fixture");
            socket.write_all(b"OKAY").await.unwrap();
            socket.write_all(&42u64.to_le_bytes()).await.unwrap();
            drop(socket);
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(service(&mut socket).await, "host-transport-id:42:features");
            socket.write_all(b"OKAY000eshell_v2,stat2").await.unwrap();
            drop(socket);
            let (mut socket, _) = listener.accept().await.unwrap();
            assert_eq!(service(&mut socket).await, "host:transport-id:42");
            socket.write_all(b"OKAY").await.unwrap();
            assert_eq!(service(&mut socket).await, "exec:fixture");
            socket.write_all(b"OKAYraw\0\xff").await.unwrap();
            let mut bytes = [0; 6];
            socket.read_exact(&mut bytes).await.unwrap();
            assert_eq!(&bytes, b"input!");
            let mut end = [0; 1];
            assert_eq!(socket.read(&mut end).await.unwrap(), 0);
        });
        let client = crate::Client::connect_server(address, "fixture", OperationOptions::default())
            .await
            .unwrap();
        assert!(client.uses_server());
        assert!(client.info().features.contains("shell_v2"));
        let mut stream = client
            .open("exec:fixture", OperationOptions::default())
            .await
            .unwrap();
        let mut raw = [0; 5];
        stream.read_exact(&mut raw).await.unwrap();
        assert_eq!(&raw, b"raw\0\xff");
        stream.write_all(b"input!").await.unwrap();
        client.close();
        tokio::time::timeout(std::time::Duration::from_secs(1), fixture)
            .await
            .unwrap()
            .unwrap();
    }
    #[tokio::test]
    async fn forced_tls_uses_only_matching_secure_mdns_and_never_plain_connect() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let fixture = tokio::spawn(async move {
            for text in [
                "plain\t_adb._tcp\t192.0.2.1:5555\nsecure\t_adb-tls-connect._tcp\t192.0.2.1:5555\n",
                "plain\t_adb._tcp\t192.0.2.1:5555\n",
            ] {
                let (mut socket, _) = listener.accept().await.unwrap();
                assert_eq!(service(&mut socket).await, "host:mdns:services");
                socket
                    .write_all(format!("OKAY{:04x}{text}", text.len()).as_bytes())
                    .await
                    .unwrap();
            }
        });
        let endpoint = "192.0.2.1:5555".parse().unwrap();
        assert_eq!(
            tls_service(address, endpoint, &OperationOptions::default())
                .await
                .unwrap(),
            "secure._adb-tls-connect._tcp"
        );
        assert!(matches!(
            tls_service(address, endpoint, &OperationOptions::default()).await,
            Err(Error::Unsupported(_))
        ));
        fixture.await.unwrap();
    }
}
