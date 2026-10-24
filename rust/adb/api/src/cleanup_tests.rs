//! 通过真实 ADB 流核验取消回执和连接撤销；受控 writer 仅模拟主机传输背压。
use super::*;
use interop_adb::{
    DeviceInfo,
    protocol::{self, Frame},
};
use std::{
    pin::Pin,
    sync::atomic::{AtomicBool, Ordering},
    task::{Context, Poll, Waker},
};
use tokio::io::{AsyncRead, AsyncWrite, DuplexStream, ReadBuf};

#[derive(Default)]
pub(super) struct Writes {
    paused: AtomicBool,
    wake: Mutex<Option<Waker>>,
}
impl Writes {
    pub(super) fn pause(&self) {
        self.paused.store(true, Ordering::SeqCst);
    }
    pub(super) fn resume(&self) {
        self.paused.store(false, Ordering::SeqCst);
        if let Some(wake) = self.wake.lock().unwrap().take() {
            wake.wake();
        }
    }
}
struct Transport {
    stream: DuplexStream,
    writes: Arc<Writes>,
}
impl AsyncRead for Transport {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_read(cx, buffer)
    }
}
impl AsyncWrite for Transport {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        if self.writes.paused.load(Ordering::SeqCst) {
            *self.writes.wake.lock().unwrap() = Some(cx.waker().clone());
            return Poll::Pending;
        }
        Pin::new(&mut self.stream).poll_write(cx, bytes)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_shutdown(cx)
    }
}
pub(super) fn connection() -> (String, Client, DuplexStream, Arc<Writes>) {
    connection_with_ownership(false)
}
pub(super) fn connection_with_ownership(
    owned: bool,
) -> (String, Client, DuplexStream, Arc<Writes>) {
    let (stream, peer) = tokio::io::duplex(1024 * 1024);
    let writes = Arc::new(Writes::default());
    let client = Client::from_negotiated_transport(
        Transport {
            stream,
            writes: writes.clone(),
        },
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let id = insert_connection(client.clone(), "cleanup-fixture".into(), owned)
        .unwrap()
        .id;
    (id, client, peer, writes)
}
pub(super) fn raw() -> AdbServiceRequest {
    AdbServiceRequest {
        kind: AdbServiceKind::Raw,
        service: "shell:cat".into(),
        arguments: vec![],
        max_output: 4096,
    }
}
pub(super) async fn peer(mut stream: DuplexStream, notices: mpsc::UnboundedSender<u32>) {
    while let Ok(frame) = Frame::read(&mut stream, protocol::MAX_PAYLOAD, true).await {
        match frame.command {
            protocol::OPEN | protocol::WRTE => {
                Frame::new(protocol::OKAY, 7, frame.arg0, [])
                    .write(&mut stream)
                    .await
                    .unwrap();
                let _ = notices.send(frame.command);
            }
            protocol::CLSE => {
                let _ = notices.send(protocol::CLSE);
            }
            protocol::OKAY => {}
            other => panic!("unexpected {other:x}"),
        }
    }
}

#[tokio::test]
async fn cancellation_of_a_borrowed_connection_waits_until_its_clse_is_written() {
    let (connection, client, socket, writes) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let operation = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    writes.paused.store(true, Ordering::SeqCst);
    assert!(
        tokio::time::timeout(Duration::from_millis(30), adb_cancel(operation.clone()))
            .await
            .is_err(),
        "流关闭帧仍被 writer 阻塞时不能向调用方确认取消完成"
    );
    writes.resume();
    adb_cancel(operation).await.unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), notices.recv())
            .await
            .unwrap(),
        Some(protocol::CLSE)
    );
    assert!(!client.is_closed(), "取消借用流不能关闭共享 Client");
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn held_worker_timeout_retains_retry_and_disconnect_refuses_late_admission() {
    let (connection, client, socket, _) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let (id, op, _events) = operation(connection.clone()).unwrap();
    let release = CancellationToken::new();
    let released = release.clone();
    let worker_op = op.clone();
    let worker = tokio::spawn(async move {
        let _finished = Completion(worker_op.finished.clone());
        let stream = worker_op
            .client
            .open("shell:held", OperationOptions::default())
            .await
            .unwrap();
        worker_op.stop.cancelled().await;
        // 模拟已进入不可丢弃本机工作的执行者，保留真实 ADB 流直到工作释放。
        released.cancelled().await;
        drop(stream);
    });
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    assert_eq!(
        cancel_with_timeout(&id, Duration::from_millis(20))
            .await
            .unwrap_err(),
        "adb_operation_cleanup_unconfirmed"
    );
    assert_eq!(
        adb_next(id.clone()).await.err().unwrap(),
        "adb_operation_cancelled"
    );
    assert!(
        disconnect_with_timeout(&connection, Duration::from_millis(20))
            .await
            .unwrap_err()
            .ends_with("cleanup_unconfirmed")
    );
    assert_eq!(
        adb_service(connection.clone(), raw(), 5000)
            .await
            .unwrap_err(),
        "adb_connection_closed"
    );
    assert!(
        operation(connection.clone()).is_err(),
        "连接克隆后迟到登记也必须拒绝"
    );
    assert!(
        adb_devices()
            .iter()
            .any(|item| item.id == connection && item.state == "offline")
    );

    let (other, other_client, other_socket, _) = self::connection();
    let (other_notice, mut other_notices) = mpsc::unbounded_channel();
    let other_serving = tokio::spawn(peer(other_socket, other_notice));
    let independent = adb_service(other.clone(), raw(), 5000).await.unwrap();
    assert_eq!(other_notices.recv().await, Some(protocol::OPEN));
    adb_write(
        independent.clone(),
        AdbInput {
            kind: AdbInputKind::Bytes,
            bytes: b"alive".to_vec(),
            rows: 0,
            columns: 0,
        },
    )
    .await
    .unwrap();
    assert_eq!(other_notices.recv().await, Some(protocol::WRTE));
    release.cancel();
    worker.await.unwrap();
    let (first, concurrent) = tokio::join!(adb_cancel(id.clone()), adb_cancel(id));
    first.unwrap();
    concurrent.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    adb_disconnect(connection.clone()).await.unwrap();
    assert!(!adb_devices().iter().any(|item| item.id == connection));
    assert!(!client.is_closed());
    assert!(!adb_connection_facts(other.clone()).unwrap().closed);
    adb_cancel(independent).await.unwrap();
    adb_disconnect(other).await.unwrap();
    client.close();
    other_client.close();
    serving.await.unwrap();
    other_serving.await.unwrap();
}

#[tokio::test]
async fn consuming_a_terminal_event_keeps_cleanup_until_the_blocked_close_is_confirmed() {
    let (connection, client, mut socket, writes) = connection();
    let peer_writes = writes.clone();
    let serving = tokio::spawn(async move {
        let frame = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        assert_eq!(frame.command, protocol::OPEN);
        peer_writes.paused.store(true, Ordering::SeqCst);
        Frame::new(protocol::OKAY, 7, frame.arg0, [])
            .write(&mut socket)
            .await
            .unwrap();
        Frame::new(protocol::CLSE, 7, frame.arg0, [])
            .write(&mut socket)
            .await
            .unwrap();
        let close = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        assert_eq!(close.command, protocol::CLSE);
        // 读端继续存在，避免夹具断开整个传输而替代本次 flush 证据。
        while Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .is_ok()
        {}
    });
    let mut request = raw();
    request.kind = AdbServiceKind::Response;
    let id = adb_service(connection.clone(), request, 5000)
        .await
        .unwrap();
    assert!(adb_service_next(id.clone()).await.unwrap().unwrap().done);
    assert!(
        cancel_with_timeout(&id, Duration::from_millis(20))
            .await
            .is_err(),
        "消费执行终态不能遗失尚未写出的关闭帧"
    );
    assert_eq!(
        adb_next(id.clone()).await.err().unwrap(),
        "adb_operation_cancelled"
    );
    writes.resume();
    adb_cancel(id.clone()).await.unwrap();
    assert_eq!(adb_next(id).await.err().unwrap(), "adb_operation_closed");
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn orphan_cleanup_retries_after_a_blocked_close_instead_of_abandoning_the_handle() {
    let (connection, client, socket, writes) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let id = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    writes.paused.store(true, Ordering::SeqCst);
    let op = registry().lock().unwrap().operations[&id].clone();
    let reaping = tokio::spawn(reclaim_operation(
        id.clone(),
        Arc::downgrade(&op),
        Duration::from_millis(5),
        Duration::from_millis(10),
    ));
    op.stop.cancelled().await;
    tokio::time::sleep(Duration::from_millis(30)).await;
    assert!(!reaping.is_finished(), "首次清理超时不能丢弃回收责任");
    assert_eq!(
        adb_next(id.clone()).await.err().unwrap(),
        "adb_operation_cancelled"
    );
    writes.resume();
    tokio::time::timeout(Duration::from_secs(1), reaping)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    assert_eq!(adb_next(id).await.err().unwrap(), "adb_operation_closed");
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}
