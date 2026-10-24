use socket2::{SockRef, TcpKeepalive};
use std::{io, time::Duration};
use tokio::net::TcpStream;

/// TCP 传输选项，协议操作另有各自期限。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TcpOptions {
    pub nodelay: bool,
    /// None 表示新 socket 不启用 keepalive。
    pub keepalive: Option<KeepaliveOptions>,
    /// 仅应用于 Android/Linux，其他宿主不可用。
    pub user_timeout: Option<Duration>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeepaliveOptions {
    pub idle: Duration,
    pub interval: Duration,
    pub retries: u32,
}

impl Default for TcpOptions {
    fn default() -> Self {
        Self {
            nodelay: true,
            keepalive: None,
            user_timeout: None,
        }
    }
}

pub(crate) fn configure(stream: &TcpStream, options: &TcpOptions) -> io::Result<()> {
    stream.set_nodelay(options.nodelay)?;
    let socket = SockRef::from(stream);
    if let Some(keepalive) = &options.keepalive {
        if keepalive.idle.is_zero() || keepalive.interval.is_zero() || keepalive.retries == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "TCP keepalive values must be positive",
            ));
        }
        socket.set_tcp_keepalive(
            &TcpKeepalive::new()
                .with_time(keepalive.idle)
                .with_interval(keepalive.interval)
                .with_retries(keepalive.retries),
        )?;
    }
    #[cfg(any(target_os = "android", target_os = "linux"))]
    socket.set_tcp_user_timeout(options.user_timeout)?;
    Ok(())
}
