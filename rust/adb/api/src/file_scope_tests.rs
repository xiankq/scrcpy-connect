//! 用真实 SYNC worker 和受控传输写阻塞核验文件作用域的释放屏障。
use super::*;
use crate::api::{adb_disconnect, insert_connection};
use interop_adb::{
    DeviceInfo,
    protocol::{self, Frame},
};
use std::{sync::atomic::AtomicBool, task::Waker};
use tokio::io::DuplexStream;

#[derive(Default)]
struct Writes {
    paused: AtomicBool,
    wake: Mutex<Option<Waker>>,
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
fn request(kind: Kind, path: &[u8], scope: &str) -> AdbFileExecutionRequest {
    AdbFileExecutionRequest {
        kind,
        path: path.to_vec(),
        destination: vec![],
        local: false,
        follow_storage_alias: false,
        limit: 10,
        push: false,
        replace: false,
        expected: None,
        part_id: String::new(),
        scope_id: scope.into(),
    }
}
fn stamp() -> AdbFileExecutionStamp {
    AdbFileExecutionStamp {
        identity: None,
        mode: 0o100644,
        size: 7,
        modified_seconds: -1,
        modified_nanos: 0,
        nanosecond_precision: false,
    }
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
fn connection() -> (Client, DuplexStream, Arc<Writes>) {
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
            features: ["stat_v2".into()].into_iter().collect(),
        },
    )
    .unwrap();
    (client, peer, writes)
}
async fn peer(socket: DuplexStream, stall: bool, notices: mpsc::UnboundedSender<&'static str>) {
    peer_with_stall(socket, Arc::new(AtomicBool::new(stall)), notices).await;
}
async fn peer_with_stall(
    mut socket: DuplexStream,
    stall: Arc<AtomicBool>,
    notices: mpsc::UnboundedSender<&'static str>,
) {
    let mut requests: HashMap<u32, Vec<u8>> = HashMap::new();
    while let Ok(frame) = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true).await {
        match frame.command {
            protocol::OPEN => {
                assert_eq!(frame.payload, b"sync:\0");
                requests.insert(frame.arg0, vec![]);
                Frame::new(protocol::OKAY, 7, frame.arg0, [])
                    .write(&mut socket)
                    .await
                    .unwrap();
            }
            protocol::WRTE => {
                Frame::new(protocol::OKAY, 7, frame.arg0, [])
                    .write(&mut socket)
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
                let reply = if kind == b"LST2" {
                    let mut reply = b"LST2".to_vec();
                    let mut metadata = [0; 68];
                    metadata[20..24].copy_from_slice(&0o100644u32.to_le_bytes());
                    metadata[36..44].copy_from_slice(&7u64.to_le_bytes());
                    metadata[52..60].copy_from_slice(&(-1i64).to_le_bytes());
                    reply.extend_from_slice(&metadata);
                    reply
                } else if kind == b"RECV" {
                    notices.send("recv").unwrap();
                    if stall.load(Ordering::SeqCst) {
                        continue;
                    }
                    b"DATA\x07\0\0\0preciseDONE\0\0\0\0".to_vec()
                } else {
                    assert_eq!(kind, b"QUIT");
                    continue;
                };
                Frame::new(protocol::WRTE, 7, frame.arg0, reply)
                    .write(&mut socket)
                    .await
                    .unwrap();
            }
            protocol::CLSE => {
                requests.remove(&frame.arg0);
                let _ = notices.send("closed");
                Frame::new(protocol::CLSE, 7, frame.arg0, [])
                    .write(&mut socket)
                    .await
                    .unwrap();
            }
            protocol::OKAY => {}
            other => panic!("unexpected {other:x}"),
        }
    }
}
async fn terminal(id: &str) -> AdbFileExecutionEvent {
    let mut stamp = None;
    loop {
        let mut event = next(id.into()).await.unwrap().unwrap();
        if event.stamp.is_some() {
            stamp = event.stamp.clone();
        }
        if event.kind == "done" || event.kind == "error" {
            event.stamp = stamp;
            return event;
        }
    }
}
async fn run(connection: &str, request: AdbFileExecutionRequest) -> AdbFileExecutionEvent {
    let id = execute(connection.into(), request, 5000).await.unwrap();
    let event = terminal(&id).await;
    cancel(&id).await.unwrap();
    event
}

#[tokio::test]
async fn reattach_waits_for_a_real_pull_and_rejects_late_workers_without_closing_client() {
    let root = tempfile::tempdir().unwrap();
    let (client, socket, _) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, true, notice));
    let connection = insert_connection(client.clone(), "scope".into(), false)
        .unwrap()
        .id;
    let key = uuid::Uuid::new_v4().to_string();
    let old = attach_scope(key.clone()).await.unwrap();
    let independent = attach_scope(uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    let part = root.path().join("part");
    let mut copying = request(Kind::Copy, b"/raw", &old);
    copying.destination = part.as_os_str().as_encoded_bytes().to_vec();
    copying.expected = Some(stamp());
    let worker = execute(connection.clone(), copying, 5000).await.unwrap();
    while notices.recv().await != Some("recv") {}
    #[cfg(target_os = "linux")]
    assert!(has_descriptor(&part), "实际拉取 worker 已打开本机目标");
    let replacement = tokio::time::timeout(Duration::from_secs(1), attach_scope(key))
        .await
        .unwrap()
        .unwrap();
    #[cfg(target_os = "linux")]
    assert!(
        !has_descriptor(&part),
        "新代返回前旧拉取 worker 已释放本机目标"
    );
    assert_ne!(old, replacement);
    assert!(!client.is_closed());
    assert!(next(worker).await.is_err());
    // 刻意以旧代发送迟到请求，必须在触碰远端前拒绝。
    assert_eq!(
        execute(connection.clone(), request(Kind::Stat, b"/raw", &old), 5000)
            .await
            .unwrap_err(),
        "file_scope_closed"
    );
    assert_eq!(
        run(&connection, request(Kind::Stat, b"/raw", &independent))
            .await
            .stamp,
        Some(stamp())
    );
    assert_eq!(
        run(&connection, request(Kind::Stat, b"/raw", &replacement))
            .await
            .stamp,
        Some(stamp())
    );
    close_scope(&old).await.unwrap();
    assert_eq!(
        run(&connection, request(Kind::Stat, b"/raw", &replacement))
            .await
            .kind,
        "done"
    );
    close_scope(&replacement).await.unwrap();
    close_scope(&independent).await.unwrap();
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn failed_close_flush_keeps_the_old_scope_revoked_and_retryable() {
    let root = tempfile::tempdir().unwrap();
    let (client, socket, writes) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, true, notice));
    let connection = insert_connection(client.clone(), "scope-retry".into(), false)
        .unwrap()
        .id;
    let key = uuid::Uuid::new_v4().to_string();
    let old = attach_scope(key.clone()).await.unwrap();
    let other = attach_scope(uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    let mut copying = request(Kind::Copy, b"/raw", &old);
    copying.destination = root
        .path()
        .join("part")
        .as_os_str()
        .as_encoded_bytes()
        .to_vec();
    copying.expected = Some(stamp());
    let worker = execute(connection.clone(), copying, 5000).await.unwrap();
    while notices.recv().await != Some("recv") {}
    writes.paused.store(true, Ordering::SeqCst);
    let stop = registry().lock().unwrap().operations[&worker].stop.clone();
    let attaching = tokio::spawn(attach_scope(key.clone()));
    stop.cancelled().await;
    // 新代仍在等关闭帧写出时，迟到的旧代请求已经失去准入资格。
    assert!(!attaching.is_finished());
    assert_eq!(
        execute(connection.clone(), request(Kind::Stat, b"/raw", &old), 5000)
            .await
            .unwrap_err(),
        "file_scope_closed"
    );
    assert_eq!(
        attaching.await.unwrap().unwrap_err(),
        "file_cleanup_unconfirmed"
    );
    assert_eq!(
        execute(connection.clone(), request(Kind::Stat, b"/raw", &old), 5000)
            .await
            .unwrap_err(),
        "file_scope_closed"
    );
    assert!(!client.is_closed());
    // 其他作用域仍能执行本机事实；旧作用域失败不能阻塞登记表或误断连接。
    let local = root.path().join("local");
    std::fs::write(&local, b"available").unwrap();
    let mut stat = request(Kind::Stat, local.as_os_str().as_encoded_bytes(), &other);
    stat.local = true;
    let other_worker = execute(connection.clone(), stat, 5000).await.unwrap();
    assert_eq!(terminal(&other_worker).await.stamp.unwrap().size, 9);
    let retry = tokio::spawn(attach_scope(key));
    tokio::task::yield_now().await;
    assert!(!retry.is_finished());
    writes.resume();
    let replacement = retry.await.unwrap().unwrap();
    cancel(&other_worker).await.unwrap();
    assert_ne!(old, replacement);
    assert!(next(worker).await.is_err());
    assert_eq!(
        run(&connection, request(Kind::Stat, b"/raw", &replacement))
            .await
            .kind,
        "done"
    );
    close_scope(&replacement).await.unwrap();
    close_scope(&other).await.unwrap();
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn parts_cannot_cross_scopes_and_reattach_releases_claimed_descriptors() {
    let root = tempfile::tempdir().unwrap();
    let (client, socket, _) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    tokio::spawn(async move { while notices.recv().await.is_some() {} });
    let serving = tokio::spawn(peer(socket, false, notice));
    let connection = insert_connection(client.clone(), "scope-parts".into(), false)
        .unwrap()
        .id;
    let key = uuid::Uuid::new_v4().to_string();
    let old = attach_scope(key.clone()).await.unwrap();
    let other = attach_scope(uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    let part = root.path().join("part");
    let target = root.path().join("target");
    let mut copying = request(Kind::Copy, b"/raw", &old);
    copying.destination = part.as_os_str().as_encoded_bytes().to_vec();
    copying.expected = Some(stamp());
    let part_id = run(&connection, copying).await.part_id.unwrap();
    #[cfg(target_os = "linux")]
    assert!(has_descriptor(&part), "已交付暂存句柄仍持有原 inode");
    let mut commit = request(Kind::Commit, part.as_os_str().as_encoded_bytes(), &other);
    commit.local = true;
    commit.part_id = part_id.clone();
    commit.destination = target.as_os_str().as_encoded_bytes().to_vec();
    assert_eq!(
        run(&connection, commit.clone()).await.error_code.as_deref(),
        Some("part_owner_mismatch")
    );
    let replacement = attach_scope(key).await.unwrap();
    #[cfg(target_os = "linux")]
    assert!(
        !has_descriptor(&part),
        "新代返回前旧代暂存描述符必须真实释放"
    );
    commit.scope_id = old;
    assert_eq!(
        execute(connection.clone(), commit.clone(), 5000)
            .await
            .unwrap_err(),
        "file_scope_closed"
    );
    commit.scope_id = replacement.clone();
    assert_eq!(
        run(&connection, commit).await.error_code.as_deref(),
        Some("source_changed")
    );
    assert_eq!(std::fs::read(&part).unwrap(), b"precise");
    assert!(!target.exists());
    assert!(!registry().lock().unwrap().parts.contains_key(&part_id));
    close_scope(&replacement).await.unwrap();
    close_scope(&other).await.unwrap();
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn closed_scope_names_do_not_exhaust_the_live_scope_capacity() {
    for _ in 0..129 {
        let scope = attach_scope(uuid::Uuid::new_v4().to_string())
            .await
            .unwrap();
        close_scope(&scope).await.unwrap();
    }
}

#[tokio::test]
async fn failed_connection_cleanup_preserves_claimed_part_and_retries_before_releasing_its_inode() {
    let root = tempfile::tempdir().unwrap();
    let (client, socket, writes) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let stall = Arc::new(AtomicBool::new(false));
    let serving = tokio::spawn(peer_with_stall(socket, stall.clone(), notice));
    let connection = insert_connection(client.clone(), "connection-parts-retry".into(), false)
        .unwrap()
        .id;
    let scope = attach_scope(uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    let claimed = root.path().join("claimed");
    let mut copying = request(Kind::Copy, b"/raw", &scope);
    copying.expected = Some(stamp());
    copying.destination = claimed.as_os_str().as_encoded_bytes().to_vec();
    let part_id = run(&connection, copying.clone()).await.part_id.unwrap();
    while notices.try_recv().is_ok() {}
    stall.store(true, Ordering::SeqCst);
    copying.destination = root
        .path()
        .join("inflight")
        .as_os_str()
        .as_encoded_bytes()
        .to_vec();
    let operation = execute(connection.clone(), copying, 5000).await.unwrap();
    while notices.recv().await != Some("recv") {}
    writes.paused.store(true, Ordering::SeqCst);
    assert!(adb_disconnect(connection.clone()).await.is_err());
    assert!(
        registry().lock().unwrap().parts.contains_key(&part_id),
        "失败不能先移除已交付暂存句柄"
    );
    #[cfg(target_os = "linux")]
    assert!(
        has_descriptor(&claimed),
        "失败时原 inode 的保留描述符仍可用于精确重试"
    );
    assert!(
        execute(
            connection.clone(),
            request(Kind::Stat, b"/raw", &scope),
            5000
        )
        .await
        .is_err()
    );
    writes.resume();
    adb_disconnect(connection).await.unwrap();
    assert!(!registry().lock().unwrap().parts.contains_key(&part_id));
    #[cfg(target_os = "linux")]
    assert!(!has_descriptor(&claimed));
    assert!(next(operation).await.is_err());
    assert_eq!(
        std::fs::read(&claimed).unwrap(),
        b"precise",
        "释放只撤销句柄，不按过期路径删除产物"
    );
    close_scope(&scope).await.unwrap();
    client.close();
    serving.await.unwrap();
}
