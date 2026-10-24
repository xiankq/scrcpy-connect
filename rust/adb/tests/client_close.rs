//! 连接关闭的本机资源释放边界，不以远端进程结果代替驱动退出。
use interop_adb::{CancellationToken, Client, DeviceInfo, Error, OperationOptions, protocol};
use std::{
    collections::HashSet,
    pin::Pin,
    sync::{Arc, Condvar, Mutex},
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, ReadBuf},
    net::{TcpListener, TcpStream},
};

fn info() -> DeviceInfo {
    DeviceInfo {
        version: protocol::VERSION,
        max_payload: 4096,
        banner: "close-fixture".into(),
        features: HashSet::new(),
    }
}
fn options(timeout: Duration) -> OperationOptions {
    OperationOptions {
        timeout,
        cancellation: CancellationToken::new(),
    }
}

#[tokio::test]
async fn close_wait_releases_real_tcp_drivers_without_closing_another_client() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let first = TcpStream::connect(listener.local_addr().unwrap())
        .await
        .unwrap();
    let (mut peer, _) = listener.accept().await.unwrap();
    let second = TcpStream::connect(listener.local_addr().unwrap())
        .await
        .unwrap();
    let (other_peer, _) = listener.accept().await.unwrap();
    let client = Client::from_negotiated_transport(first, info()).unwrap();
    let retained = client.clone();
    let other = Client::from_negotiated_transport(second, info()).unwrap();
    client
        .close_and_wait(options(Duration::from_secs(2)))
        .await
        .unwrap();
    assert!(retained.is_closed());
    assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
    assert!(!other.is_closed());
    assert_eq!(
        other_peer.try_read(&mut [0]).unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
    other
        .close_and_wait(options(Duration::from_secs(2)))
        .await
        .unwrap();
    retained
        .close_and_wait(options(Duration::from_secs(2)))
        .await
        .unwrap();
}

struct ReleaseGate {
    released: Mutex<bool>,
    changed: Condvar,
}
impl ReleaseGate {
    fn release(&self) {
        *self.released.lock().unwrap() = true;
        self.changed.notify_all();
    }
}
struct ReleaseOnDrop(Arc<ReleaseGate>);
impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        self.0.release();
    }
}
struct HeldTransport {
    socket: Option<TcpStream>,
    dropping: Option<tokio::sync::oneshot::Sender<()>>,
    gate: Arc<ReleaseGate>,
}
impl AsyncRead for HeldTransport {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(self.get_mut().socket.as_mut().unwrap()).poll_read(cx, buf)
    }
}
impl AsyncWrite for HeldTransport {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(self.get_mut().socket.as_mut().unwrap()).poll_write(cx, bytes)
    }
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(self.get_mut().socket.as_mut().unwrap()).poll_flush(cx)
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(self.get_mut().socket.as_mut().unwrap()).poll_shutdown(cx)
    }
}
impl Drop for HeldTransport {
    fn drop(&mut self) {
        if let Some(dropping) = self.dropping.take() {
            let _ = dropping.send(());
        }
        let mut released = self.gate.released.lock().unwrap();
        while !*released {
            released = self.gate.changed.wait(released).unwrap();
        }
        // 刻意直到栅栏释放才 drop 实际 socket，以区分取消与资源释放。
        drop(self.socket.take());
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn close_wait_timeout_and_cancel_keep_the_same_driver_completion_for_retry() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let socket = TcpStream::connect(listener.local_addr().unwrap())
        .await
        .unwrap();
    let (mut peer, _) = listener.accept().await.unwrap();
    let gate = Arc::new(ReleaseGate {
        released: Mutex::new(false),
        changed: Condvar::new(),
    });
    let _release = ReleaseOnDrop(gate.clone());
    let (dropping, started) = tokio::sync::oneshot::channel();
    let client = Client::from_negotiated_transport(
        HeldTransport {
            socket: Some(socket),
            dropping: Some(dropping),
            gate: gate.clone(),
        },
        info(),
    )
    .unwrap();
    let cancelled = CancellationToken::new();
    cancelled.cancel();
    assert!(matches!(
        client
            .close_and_wait(OperationOptions {
                timeout: Duration::from_secs(2),
                cancellation: cancelled
            })
            .await,
        Err(Error::Cancelled)
    ));
    tokio::time::timeout(Duration::from_secs(2), started)
        .await
        .unwrap()
        .unwrap();
    assert!(client.is_closed());
    assert!(matches!(
        client
            .close_and_wait(options(Duration::from_millis(20)))
            .await,
        Err(Error::Timeout)
    ));
    assert_eq!(
        peer.try_read(&mut [0]).unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
    gate.release();
    client
        .close_and_wait(options(Duration::from_secs(2)))
        .await
        .unwrap();
    assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
}

#[test]
fn invalid_or_unstartable_transport_releases_it_without_leaving_a_driver() {
    struct Transport(Arc<std::sync::atomic::AtomicBool>);
    impl Drop for Transport {
        fn drop(&mut self) {
            self.0.store(true, std::sync::atomic::Ordering::SeqCst);
        }
    }
    impl AsyncRead for Transport {
        fn poll_read(
            self: Pin<&mut Self>,
            _: &mut Context<'_>,
            _: &mut ReadBuf<'_>,
        ) -> Poll<std::io::Result<()>> {
            Poll::Pending
        }
    }
    impl AsyncWrite for Transport {
        fn poll_write(
            self: Pin<&mut Self>,
            _: &mut Context<'_>,
            _: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Pending
        }
        fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Pending
        }
        fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Pending
        }
    }
    for invalid in [true, false] {
        let dropped = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let mut negotiated = info();
        if invalid {
            negotiated.max_payload = 0;
        }
        assert!(matches!(
            Client::from_negotiated_transport(Transport(dropped.clone()), negotiated),
            Err(Error::InvalidArgument(_))
        ));
        assert!(dropped.load(std::sync::atomic::Ordering::SeqCst));
    }
}
