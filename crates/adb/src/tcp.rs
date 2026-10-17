use socket2::{SockRef, TcpKeepalive};
use std::{io, time::Duration};
use tokio::net::TcpStream;

/// Configure the ADB transport before it can be wrapped in TLS. Healthy idle
/// transports have no application read deadline: static video is valid.
pub(crate) fn configure(stream: &TcpStream) -> io::Result<()> {
    stream.set_nodelay(true)?;
    let socket = SockRef::from(stream);
    // Match AOSP ADB's default 1-second interval and ten failed probes.
    // https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/sysdeps_unix.cpp
    socket.set_tcp_keepalive(
        &TcpKeepalive::new()
            .with_time(Duration::from_secs(1))
            .with_interval(Duration::from_secs(1))
            .with_retries(10),
    )?;
    // Keepalive covers idle sockets. Outstanding unacknowledged data otherwise
    // follows a much longer TCP retransmission timeout on Android/Linux.
    #[cfg(any(target_os = "android", target_os = "linux"))]
    socket.set_tcp_user_timeout(Some(Duration::from_secs(11)))?;
    Ok(())
}
