//! 握手取消使用真实 socket；全宿主关闭夹具单独运行，避免撤销其他并行测试的资源。
use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::io::AsyncReadExt;

pub(super) async fn identity_path() -> (tempfile::TempDir, String) {
    static PEM: OnceLock<String> = OnceLock::new();
    let pem = PEM.get_or_init(|| {
        Identity::generate()
            .unwrap()
            .to_pkcs8_pem()
            .unwrap()
            .to_string()
    });
    let directory = tempfile::tempdir().unwrap();
    let path = directory
        .path()
        .join("host.pem")
        .to_string_lossy()
        .into_owned();
    adb_replace_identity(path.clone(), pem.clone(), None)
        .await
        .unwrap();
    (directory, path)
}

async fn connect_direct(
    address: String,
    path: String,
    handshake: Option<String>,
) -> Result<AdbDeviceInfo, AdbConnectionError> {
    connect_tcp(
        address,
        path,
        false,
        true,
        60_000,
        AdbConnectOptions::default(),
        handshake,
    )
    .await
}

async fn read_server_request(peer: &mut tokio::net::TcpStream) {
    let mut header = [0; 4];
    peer.read_exact(&mut header).await.unwrap();
    let length = usize::from_str_radix(std::str::from_utf8(&header).unwrap(), 16).unwrap();
    peer.read_exact(&mut vec![0; length]).await.unwrap();
}

async fn eof(peer: &mut tokio::net::TcpStream) {
    let mut bytes = Vec::new();
    let result = tokio::time::timeout(Duration::from_secs(2), peer.read_to_end(&mut bytes))
        .await
        .expect("取消完成后真实 socket 必须已关闭");
    if let Err(error) = result {
        assert_eq!(error.kind(), std::io::ErrorKind::ConnectionReset);
    }
}

#[tokio::test]
async fn cancelled_reservation_never_starts_and_each_id_is_single_use() {
    let pending = adb_handshake_create().await.unwrap();
    adb_handshake_cancel(pending.clone()).await.unwrap();
    assert_eq!(
        handshake::run(Some(pending.clone()), |_| async { Ok(()) })
            .await
            .unwrap_err(),
        "adb_handshake_cancelled"
    );
    adb_handshake_close(pending.clone()).await.unwrap();
    assert_eq!(
        handshake::run(Some(pending), |_| async { Ok(()) })
            .await
            .unwrap_err(),
        "adb_handshake_closed"
    );

    let used = adb_handshake_create().await.unwrap();
    handshake::run(Some(used.clone()), |_| async { Ok(()) })
        .await
        .unwrap();
    assert_eq!(
        handshake::run(Some(used.clone()), |_| async { Ok(()) })
            .await
            .unwrap_err(),
        "adb_handshake_already_used"
    );
    adb_handshake_close(used).await.unwrap();

    let closed = adb_handshake_create().await.unwrap();
    adb_handshake_close(closed.clone()).await.unwrap();
    assert_eq!(
        handshake::run(Some(closed), |_| async { Ok(()) })
            .await
            .unwrap_err(),
        "adb_handshake_closed"
    );
}

async fn stalled_direct(auth: bool) {
    let (_directory, path) = identity_path().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let id = adb_handshake_create().await.unwrap();
    let mut connecting = tokio::spawn(connect_direct(
        listener.local_addr().unwrap().to_string(),
        path,
        Some(id.clone()),
    ));
    let (mut peer, _) = tokio::select! {
        result = listener.accept() => result.unwrap(),
        result = &mut connecting => panic!("握手在接受连接前提前结束: {:?}", result.err()),
    };
    assert_eq!(
        Frame::read(&mut peer, 4096, false).await.unwrap().command,
        protocol::CNXN
    );
    if auth {
        Frame::new(protocol::AUTH, 1, 0, [0x5a; 20])
            .write(&mut peer)
            .await
            .unwrap();
        let signature = Frame::read(&mut peer, 4096, false).await.unwrap();
        assert_eq!((signature.command, signature.arg0), (protocol::AUTH, 2));
    }
    adb_handshake_cancel(id.clone()).await.unwrap();
    adb_handshake_close(id).await.unwrap();
    assert!(connecting.await.unwrap().is_err());
    eof(&mut peer).await;
}

#[tokio::test]
async fn cancellation_releases_a_real_tcp_handshake_waiting_for_cnxn() {
    stalled_direct(false).await;
}

#[tokio::test]
async fn cancellation_releases_a_real_handshake_waiting_for_auth_authorization() {
    stalled_direct(true).await;
}

#[tokio::test]
async fn cancelling_one_official_server_handshake_preserves_another() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let first = adb_handshake_create().await.unwrap();
    let second = adb_handshake_create().await.unwrap();
    let connecting = tokio::spawn(adb_connect_server(
        address.clone(),
        "first".into(),
        60_000,
        Some(first.clone()),
    ));
    let (mut first_peer, _) = listener.accept().await.unwrap();
    read_server_request(&mut first_peer).await;
    let other = tokio::spawn(adb_connect_server(
        address,
        "second".into(),
        60_000,
        Some(second.clone()),
    ));
    let (mut second_peer, _) = listener.accept().await.unwrap();
    read_server_request(&mut second_peer).await;
    adb_handshake_close(first).await.unwrap();
    assert!(connecting.await.unwrap().is_err());
    eof(&mut first_peer).await;
    assert!(!other.is_finished(), "独立握手不得被同一宿主的另一取消影响");
    adb_handshake_close(second).await.unwrap();
    assert!(other.await.unwrap().is_err());
    eof(&mut second_peer).await;
}

#[tokio::test]
async fn pairing_cancel_closes_the_real_socket_during_tls_exchange() {
    let (_directory, path) = identity_path().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let id = adb_handshake_create().await.unwrap();
    let mut pairing = tokio::spawn(pair(
        listener.local_addr().unwrap().to_string(),
        "123456".into(),
        path,
        60_000,
        Some(id.clone()),
    ));
    let (mut peer, _) = tokio::select! {
        accepted = listener.accept() => accepted.unwrap(),
        result = &mut pairing => panic!("配对在接入端点前提前结束: {:?}", result.err()),
    };
    let mut hello = [0; 5];
    peer.read_exact(&mut hello).await.unwrap();
    assert_eq!(hello[0], 22, "必须真正进入 TLS 握手");
    adb_handshake_close(id).await.unwrap();
    assert_eq!(
        pairing.await.unwrap().unwrap_err().code,
        AdbConnectionErrorCode::Cancelled
    );
    eof(&mut peer).await;
}

#[tokio::test]
async fn closing_a_completed_handshake_does_not_cancel_the_handed_off_client() {
    let (_directory, path) = identity_path().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let peer = tokio::spawn(async move {
        let (mut peer, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut peer, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::\0".to_vec(),
        )
        .write(&mut peer)
        .await
        .unwrap();
        let open = Frame::read(&mut peer, 4096, true).await.unwrap();
        assert_eq!(open.command, protocol::OPEN);
        Frame::new(protocol::OKAY, 7, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let close = Frame::read(&mut peer, 4096, true).await.unwrap();
        assert_eq!(close.command, protocol::CLSE);
        eof(&mut peer).await;
    });
    let id = adb_handshake_create().await.unwrap();
    let connected = connect_direct(address, path, Some(id.clone()))
        .await
        .unwrap();
    adb_handshake_cancel(id.clone()).await.unwrap();
    adb_handshake_close(id).await.unwrap();
    let client = device(&connected.id).unwrap();
    let stream = client
        .open(
            "shell:alive",
            options(2000, CancellationToken::new()).unwrap(),
        )
        .await
        .unwrap();
    drop(stream);
    client
        .flush_closed_streams(options(2000, CancellationToken::new()).unwrap())
        .await
        .unwrap();
    assert!(!client.is_closed());
    adb_disconnect(connected.id).await.unwrap();
    peer.await.unwrap();
}

#[tokio::test]
async fn invalid_pair_options_do_not_consume_the_reserved_id_or_prepare_identity() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("absent").join("host.pem");
    let id = adb_handshake_create().await.unwrap();
    for (password, timeout, expected) in [
        ("123456", 0, "invalid_adb_timeout"),
        ("", 1000, "invalid argument: invalid pairing password"),
        (
            "bad\0password",
            1000,
            "invalid argument: invalid pairing password",
        ),
    ] {
        assert_eq!(
            pair(
                "127.0.0.1:1".into(),
                password.into(),
                path.to_string_lossy().into_owned(),
                timeout,
                Some(id.clone())
            )
            .await
            .unwrap_err()
            .message,
            expected
        );
        assert!(!path.parent().unwrap().exists());
    }
    handshake::run(Some(id.clone()), |_| async { Ok(()) })
        .await
        .unwrap();
    adb_handshake_close(id).await.unwrap();
}

#[test]
fn identity_preparation_is_drained_even_when_the_callers_wait_is_dropped() {
    // 独占 blocking pool，让真实身份准备排队，避免以磁盘快慢制造竞态。
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .max_blocking_threads(1)
        .build()
        .unwrap();
    runtime.block_on(async {
        let (release, held) = std::sync::mpsc::channel();
        let (ready, started) = tokio::sync::oneshot::channel();
        let blocker = tokio::task::spawn_blocking(move || {
            ready.send(()).unwrap();
            held.recv().unwrap();
        });
        started.await.unwrap();
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("host.pem")
            .to_string_lossy()
            .into_owned();
        let id = adb_handshake_create().await.unwrap();
        let (ready, queued) = tokio::sync::oneshot::channel();
        let prepared_path = path.clone();
        let (identity_finished, identity_done) = tokio::sync::oneshot::channel();
        let waiting = tokio::spawn(handshake::run(Some(id.clone()), move |stop| async move {
            ready.send(()).unwrap();
            let result = connection_identity(&prepared_path, &stop)
                .await
                .map(|_| ())
                .map_err(|error| error.message);
            identity_finished.send(()).unwrap();
            result
        }));
        queued.await.unwrap();
        adb_handshake_cancel(id.clone()).await.unwrap();
        waiting.abort();
        assert!(waiting.await.unwrap_err().is_cancelled());
        assert_eq!(
            handshake::close(&id, Duration::from_millis(20))
                .await
                .unwrap_err(),
            "adb_handshake_cleanup_unconfirmed"
        );
        assert!(registry().lock().unwrap().handshakes.contains_key(&id));
        release.send(()).unwrap();
        blocker.await.unwrap();
        // 生成 RSA 和持久化没有 7 秒 SLA；只在实际磁盘 worker 完成后核验重试回执。
        identity_done.await.unwrap();
        adb_handshake_close(id.clone()).await.unwrap();
        assert!(
            std::path::Path::new(&path).is_file(),
            "取消后仍须等实际身份准备完成"
        );
        assert!(!registry().lock().unwrap().handshakes.contains_key(&id));
    });
}

#[test]
fn host_close_drains_anonymous_handshake() {
    const CHILD: &str = "INTEROP_ADB_HANDSHAKE_CLOSE_CHILD";
    if std::env::var_os(CHILD).is_some() {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let (_directory, path) = identity_path().await;
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let connecting = tokio::spawn(connect_direct(address.to_string(), path, None));
            let (mut peer, _) = listener.accept().await.unwrap();
            assert_eq!(
                Frame::read(&mut peer, 4096, false).await.unwrap().command,
                protocol::CNXN
            );
            adb_close_all().await.unwrap();
            let mut byte = [0];
            assert_eq!(
                tokio::time::timeout(Duration::from_millis(300), peer.read(&mut byte))
                    .await
                    .expect("宿主关闭成功后，匿名握手 socket 必须已经释放")
                    .unwrap(),
                0
            );
            assert!(connecting.await.unwrap().is_err());
            host_close_failure_preserves_the_fence_and_retry().await;
        });
        return;
    }
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "api::handshake_tests::host_close_drains_anonymous_handshake",
            "--nocapture",
        ])
        .env(CHILD, "1")
        .status()
        .unwrap();
    assert!(status.success(), "独立进程内的真实握手清理必须成功");
}

async fn host_close_failure_preserves_the_fence_and_retry() {
    let id = adb_handshake_create().await.unwrap();
    let pending = adb_handshake_create().await.unwrap();
    let (stream, _peer) = tokio::io::duplex(1024);
    let client = Client::from_negotiated_transport(
        stream,
        interop_adb::DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let late = client.clone();
    let release = CancellationToken::new();
    let held = release.clone();
    let (ready, started) = tokio::sync::oneshot::channel();
    let worker = tokio::spawn(handshake::run(Some(id.clone()), move |_| async move {
        ready.send(()).unwrap();
        // 模拟不可提前丢弃的身份/平台准备，退出前才尝试交接真实 Client。
        held.cancelled().await;
        insert(late, "late".into()).map(|_| ())
    }));
    started.await.unwrap();
    assert_eq!(
        close_all_with_timeout(Duration::from_millis(20))
            .await
            .unwrap_err(),
        "adb_host_cleanup_unconfirmed"
    );
    assert_eq!(
        adb_handshake_create().await.unwrap_err().message,
        "adb_host_closing"
    );
    assert!(registry().lock().unwrap().handshakes.contains_key(&id));
    release.cancel();
    assert_eq!(worker.await.unwrap().unwrap_err(), "adb_host_closing");
    assert!(client.is_closed(), "禁止交接时必须释放自有迟到 Client");
    adb_close_all().await.unwrap();
    assert!(registry().lock().unwrap().handshakes.is_empty());
    assert_eq!(
        handshake::run(Some(pending), |_| async { Ok(()) })
            .await
            .unwrap_err(),
        "adb_handshake_closed"
    );
    let next = adb_handshake_create().await.unwrap();
    adb_handshake_close(next).await.unwrap();
}
