//! 真正的 SYNC 拉取、受阻关闭帧与父域交接，核验跨域取消和描述符释放顺序。
use super::*;
use crate::{
    api::{
        AdbFileExecutionKind, AdbFileExecutionRequest, AdbFileExecutionStamp, adb_disconnect,
        insert_connection,
    },
    file_system,
};
use interop_adb::{
    Client, DeviceInfo,
    protocol::{self, Frame},
};
use std::{
    pin::Pin,
    sync::atomic::{AtomicBool, Ordering},
    task::{Context, Poll, Waker},
};
use tokio::{
    io::{AsyncRead, AsyncWrite, DuplexStream, ReadBuf},
    sync::{Notify, mpsc},
};

#[derive(Default)]
struct Writes {
    paused: AtomicBool,
    wake: Mutex<Option<Waker>>,
    blocked: Notify,
}
impl Writes {
    fn resume(&self) {
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
            self.writes.blocked.notify_one();
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
struct Fixture {
    client: Client,
    connection: String,
    writes: Arc<Writes>,
    recv: mpsc::UnboundedReceiver<()>,
    serving: tokio::task::JoinHandle<()>,
    root: tempfile::TempDir,
}
impl Fixture {
    fn new() -> Self {
        let (stream, mut peer) = tokio::io::duplex(64 * 1024);
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
                features: ["stat_v2".into()].into_iter().collect(),
            },
        )
        .unwrap();
        let connection = insert_connection(client.clone(), "scoped-files".into(), false)
            .unwrap()
            .id;
        let (notice, recv) = mpsc::unbounded_channel();
        let serving = tokio::spawn(async move {
            let mut requests = HashMap::<u32, Vec<u8>>::new();
            while let Ok(frame) = Frame::read(&mut peer, protocol::MAX_PAYLOAD, true).await {
                match frame.command {
                    protocol::OPEN => {
                        assert_eq!(frame.payload, b"sync:\0");
                        requests.insert(frame.arg0, vec![]);
                        Frame::new(protocol::OKAY, 7, frame.arg0, [])
                            .write(&mut peer)
                            .await
                            .unwrap();
                    }
                    protocol::WRTE => {
                        Frame::new(protocol::OKAY, 7, frame.arg0, [])
                            .write(&mut peer)
                            .await
                            .unwrap();
                        let bytes = requests.get_mut(&frame.arg0).unwrap();
                        bytes.extend_from_slice(&frame.payload);
                        if bytes.len() < 8 {
                            continue;
                        }
                        let size = u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
                        if bytes.len() < 8 + size {
                            continue;
                        }
                        let kind = bytes[..4].to_vec();
                        bytes.drain(..8 + size);
                        if kind == b"RECV" {
                            notice.send(()).unwrap();
                            continue;
                        }
                        if kind == b"QUIT" {
                            continue;
                        }
                        assert_eq!(kind, b"LST2");
                        let mut reply = b"LST2".to_vec();
                        let mut metadata = [0; 68];
                        metadata[20..24].copy_from_slice(&0o100644u32.to_le_bytes());
                        metadata[36..44].copy_from_slice(&7u64.to_le_bytes());
                        metadata[52..60].copy_from_slice(&(-1i64).to_le_bytes());
                        reply.extend_from_slice(&metadata);
                        Frame::new(protocol::WRTE, 7, frame.arg0, reply)
                            .write(&mut peer)
                            .await
                            .unwrap();
                    }
                    protocol::CLSE => {
                        requests.remove(&frame.arg0);
                        Frame::new(protocol::CLSE, 7, frame.arg0, [])
                            .write(&mut peer)
                            .await
                            .unwrap();
                    }
                    protocol::OKAY => {}
                    other => panic!("unexpected {other:x}"),
                }
            }
        });
        Self {
            client,
            connection,
            writes,
            recv,
            serving,
            root: tempfile::tempdir().unwrap(),
        }
    }
    async fn copy(&mut self, scope: &str) -> String {
        let mut request = request(scope);
        request.kind = AdbFileExecutionKind::Copy;
        request.local = false;
        request.path = b"/source".to_vec();
        request.destination = self
            .root
            .path()
            .join("part")
            .as_os_str()
            .as_encoded_bytes()
            .to_vec();
        request.expected = Some(AdbFileExecutionStamp {
            identity: None,
            mode: 0o100644,
            size: 7,
            modified_seconds: -1,
            modified_nanos: 0,
            nanosecond_precision: false,
        });
        let id = file_system::execute(self.connection.clone(), request, 5000)
            .await
            .unwrap();
        self.recv.recv().await.unwrap();
        id
    }
    async fn assert_usable(&self, scope: &str) {
        let mut request = request(scope);
        request.path = self.root.path().as_os_str().as_encoded_bytes().to_vec();
        let id = file_system::execute(self.connection.clone(), request, 5000)
            .await
            .unwrap();
        loop {
            let event = file_system::next(id.clone()).await.unwrap().unwrap();
            if event.kind == "done" {
                break;
            }
            assert_ne!(event.kind, "error");
        }
        // 另一文件域仍可产生真实本机事实；其通用 Client flush 由恢复写入后的最终清理负责。
    }
    async fn assert_closed(&self, scope: &str) {
        assert_eq!(
            file_system::execute(self.connection.clone(), request(scope), 5000)
                .await
                .unwrap_err(),
            "file_scope_closed"
        );
    }
    async fn finish(self) {
        adb_disconnect(self.connection).await.unwrap();
        self.client
            .close_and_wait(interop_adb::OperationOptions::default())
            .await
            .unwrap();
        self.serving.await.unwrap();
    }
}
fn request(scope: &str) -> AdbFileExecutionRequest {
    AdbFileExecutionRequest {
        kind: AdbFileExecutionKind::Stat,
        path: b"/".to_vec(),
        destination: vec![],
        local: true,
        follow_storage_alias: false,
        limit: 1,
        push: false,
        replace: false,
        expected: None,
        part_id: String::new(),
        scope_id: scope.into(),
    }
}
async fn scope() -> AdbAdmissionScopeInfo {
    attach(
        uuid::Uuid::new_v4().to_string(),
        None,
        Duration::from_secs(1),
    )
    .await
    .unwrap()
}
#[cfg(target_os = "linux")]
fn has_descriptor(path: &std::path::Path) -> bool {
    std::fs::read_dir("/proc/self/fd").unwrap().any(|entry| {
        entry
            .ok()
            .and_then(|entry| std::fs::read_link(entry.path()).ok())
            .as_deref()
            == Some(path)
    })
}

#[tokio::test]
async fn parent_takeover_waits_for_file_flush_and_rejects_late_old_attaches() {
    let mut fixture = Fixture::new();
    let parent = scope().await;
    let key = uuid::Uuid::new_v4().to_string();
    let files = attach_file_scope(key.clone(), parent.scope_id.clone())
        .await
        .unwrap();
    let other = file_system::attach_scope(uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    fixture.copy(&files).await;
    #[cfg(target_os = "linux")]
    assert!(has_descriptor(&fixture.root.path().join("part")));
    fixture.writes.paused.store(true, Ordering::SeqCst);
    let mut replacing = tokio::spawn(attach(
        parent.scope_key.clone(),
        Some(parent.scope_id.clone()),
        Duration::from_secs(1),
    ));
    tokio::select! {
        _ = fixture.writes.blocked.notified() => {},
        result = &mut replacing => panic!("父域不能越过文件 worker 的关闭屏障: {result:?}"),
    }
    assert!(!replacing.is_finished());
    assert!(!inspect(&parent.scope_key).unwrap().unwrap().accepting);
    fixture.assert_closed(&files).await;
    fixture.assert_usable(&other).await;
    #[cfg(target_os = "linux")]
    assert!(
        !has_descriptor(&fixture.root.path().join("part")),
        "关闭帧仍受阻时，worker 本机文件已经释放"
    );
    fixture.writes.resume();
    let replacement = replacing.await.unwrap().unwrap();
    assert!(
        attach_file_scope(key.clone(), parent.scope_id.clone())
            .await
            .is_err()
    );
    let new_files = attach_file_scope(key, replacement.scope_id.clone())
        .await
        .unwrap();
    file_system::close_scope(&files).await.unwrap();
    close(&parent.scope_id, Duration::from_secs(1))
        .await
        .unwrap();
    fixture.assert_usable(&new_files).await;
    close(&replacement.scope_id, Duration::from_secs(1))
        .await
        .unwrap();
    file_system::close_scope(&other).await.unwrap();
    fixture.finish().await;
}

#[tokio::test]
async fn failed_parent_cleanup_retains_revoked_files_and_can_retry_the_same_parent() {
    let mut fixture = Fixture::new();
    let parent = scope().await;
    let key = uuid::Uuid::new_v4().to_string();
    let files = attach_file_scope(key.clone(), parent.scope_id.clone())
        .await
        .unwrap();
    let worker = fixture.copy(&files).await;
    fixture.writes.paused.store(true, Ordering::SeqCst);
    assert_eq!(
        attach(
            parent.scope_key.clone(),
            Some(parent.scope_id.clone()),
            Duration::from_millis(30)
        )
        .await
        .unwrap_err(),
        "adb_admission_scope_cleanup_unconfirmed"
    );
    let failed = inspect(&parent.scope_key).unwrap().unwrap();
    assert_eq!(failed.scope_id, parent.scope_id);
    assert!(!failed.accepting);
    fixture.assert_closed(&files).await;
    assert!(
        attach_file_scope(key.clone(), parent.scope_id.clone())
            .await
            .is_err()
    );
    fixture.writes.resume();
    let replacement = attach(
        parent.scope_key,
        Some(parent.scope_id),
        Duration::from_secs(1),
    )
    .await
    .unwrap();
    assert!(file_system::next(worker).await.is_err());
    let new_files = attach_file_scope(key, replacement.scope_id.clone())
        .await
        .unwrap();
    fixture.assert_usable(&new_files).await;
    close(&replacement.scope_id, Duration::from_secs(1))
        .await
        .unwrap();
    fixture.finish().await;
}

#[tokio::test]
async fn already_started_file_attach_finishes_before_parent_cas_and_is_then_drained() {
    let mut fixture = Fixture::new();
    let parent = scope().await;
    let key = uuid::Uuid::new_v4().to_string();
    let previous = file_system::attach_scope(key.clone()).await.unwrap();
    fixture.copy(&previous).await;
    fixture.writes.paused.store(true, Ordering::SeqCst);
    let attaching = tokio::spawn(attach_file_scope(key.clone(), parent.scope_id.clone()));
    fixture.writes.blocked.notified().await;
    let mut replacing = Box::pin(attach(
        parent.scope_key.clone(),
        Some(parent.scope_id.clone()),
        Duration::from_secs(1),
    ));
    // 明确把父域 CAS 排在正在附着的文件域之后，再安排旧代的迟到附着；不依赖任务调度顺序。
    std::future::poll_fn(|cx| {
        assert!(std::future::Future::poll(replacing.as_mut(), cx).is_pending());
        Poll::Ready(())
    })
    .await;
    assert!(
        inspect(&parent.scope_key).unwrap().unwrap().accepting,
        "已开始的附着仍持有父域转换锁"
    );
    let late = tokio::spawn(attach_file_scope(key.clone(), parent.scope_id.clone()));
    fixture.writes.resume();
    let old_files = attaching.await.unwrap().unwrap();
    let replacement = replacing.await.unwrap();
    assert!(late.await.unwrap().is_err());
    fixture.assert_closed(&old_files).await;
    let new_files = attach_file_scope(key, replacement.scope_id.clone())
        .await
        .unwrap();
    file_system::close_scope(&old_files).await.unwrap();
    fixture.assert_usable(&new_files).await;
    close(&replacement.scope_id, Duration::from_secs(1))
        .await
        .unwrap();
    fixture.finish().await;
}
