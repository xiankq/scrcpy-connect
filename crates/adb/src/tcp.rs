use socket2::{SockRef, TcpKeepalive};
use std::{io, time::Duration};
use tokio::net::TcpStream;

/// TCP transport options. Protocol operations have their own deadlines.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TcpOptions {
    pub nodelay: bool,
    /// None leaves keepalive disabled on a newly created socket.
    pub keepalive: Option<KeepaliveOptions>,
    /// Applied on Android/Linux; unavailable on other hosts.
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
