//! 类型化错误沿真实 TCP 和已登记 worker 传递；不依赖错误展示文本。
use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::io::AsyncReadExt;

#[tokio::test]
async fn closed_tcp_port_is_explicitly_refused_for_connect_and_pair() {
    let (_directory, path) = super::handshake_tests::identity_path().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    drop(listener);
    let connecting = connect_tcp(
        address.clone(),
        path.clone(),
        false,
        true,
        2000,
        AdbConnectOptions::default(),
        None,
    )
    .await
    .err()
    .expect("关闭的 TCP 端口不能建立连接");
    assert_eq!(connecting.code, AdbConnectionErrorCode::ConnectionRefused);
    let pairing = pair(address, "123456".into(), path, 2000, None)
        .await
        .unwrap_err();
    assert_eq!(pairing.code, AdbConnectionErrorCode::ConnectionRefused);
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::test]
async fn unavailable_official_socket_is_explicitly_refused() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    drop(listener);
    let error = adb_connect_server(address, "device".into(), 2000, None)
        .await
        .err()
        .expect("关闭端口不能提供 smart socket");
    assert_eq!(error.code, AdbConnectionErrorCode::ConnectionRefused);
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
async fn stalled_official_socket(cancel: bool) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let id = adb_handshake_create().await.unwrap();
    let worker = tokio::spawn(adb_connect_server(
        address,
        "device".into(),
        if cancel { 60_000 } else { 250 },
        Some(id.clone()),
    ));
    let (mut peer, _) = listener.accept().await.unwrap();
    let mut length = [0; 4];
    peer.read_exact(&mut length).await.unwrap();
    let length = usize::from_str_radix(std::str::from_utf8(&length).unwrap(), 16).unwrap();
    let mut request = vec![0; length];
    peer.read_exact(&mut request).await.unwrap();
    assert_eq!(request, b"host:tport:serial:device");
    if cancel {
        adb_handshake_cancel(id.clone()).await.unwrap();
    }
    let error = worker
        .await
        .unwrap()
        .err()
        .expect("没有 smart-socket 回执不得交付连接");
    assert_eq!(
        error.code,
        if cancel {
            AdbConnectionErrorCode::Cancelled
        } else {
            AdbConnectionErrorCode::HandshakeTimedOut
        }
    );
    adb_handshake_close(id).await.unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.read(&mut [0]))
            .await
            .unwrap()
            .unwrap(),
        0
    );
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::test]
async fn accepted_official_socket_without_ack_has_a_handshake_timeout() {
    stalled_official_socket(false).await;
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::test]
async fn cancelled_official_handshake_is_confirmed_after_its_real_socket_closes() {
    stalled_official_socket(true).await;
}

#[tokio::test]
async fn accepted_tcp_waiting_for_cnxn_has_a_handshake_timeout_and_releases_socket() {
    let (_directory, path) = super::handshake_tests::identity_path().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let worker = tokio::spawn(connect_tcp(
        address,
        path,
        false,
        true,
        250,
        AdbConnectOptions::default(),
        None,
    ));
    let (mut peer, _) = listener.accept().await.unwrap();
    assert_eq!(
        Frame::read(&mut peer, 4096, false).await.unwrap().command,
        protocol::CNXN
    );
    let error = worker
        .await
        .unwrap()
        .err()
        .expect("没有 CNXN 回执不能完成握手");
    assert_eq!(error.code, AdbConnectionErrorCode::HandshakeTimedOut);
    let mut byte = [0];
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.read(&mut byte))
            .await
            .unwrap()
            .unwrap(),
        0
    );
}

#[tokio::test]
async fn cleanup_timeout_retains_same_handshake_for_a_confirmed_retry() {
    let id = adb_handshake_create().await.unwrap();
    let release = CancellationToken::new();
    let held = release.clone();
    let (started, ready) = tokio::sync::oneshot::channel();
    let worker = tokio::spawn(handshake::run_connection(
        Some(id.clone()),
        move |stop| async move {
            started.send(()).unwrap();
            stop.cancelled().await;
            held.cancelled().await;
            Err::<(), _>(interop_adb::Error::Cancelled.into())
        },
    ));
    ready.await.unwrap();
    let error = close_handshake_with_timeout(&id, Duration::from_millis(20))
        .await
        .unwrap_err();
    assert_eq!(error.code, AdbConnectionErrorCode::CleanupUnconfirmed);
    assert!(registry().lock().unwrap().handshakes.contains_key(&id));
    release.cancel();
    assert_eq!(
        worker.await.unwrap().unwrap_err().code,
        AdbConnectionErrorCode::Cancelled
    );
    adb_handshake_close(id.clone()).await.unwrap();
    assert!(!registry().lock().unwrap().handshakes.contains_key(&id));
}

#[tokio::test]
async fn cancelled_reserved_id_is_not_a_network_failure_or_late_identity_write() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("absent").join("host.pem");
    let id = adb_handshake_create().await.unwrap();
    adb_handshake_cancel(id.clone()).await.unwrap();
    let error = connect_tcp(
        "127.0.0.1:1".into(),
        path.to_string_lossy().into_owned(),
        false,
        true,
        1000,
        AdbConnectOptions::default(),
        Some(id.clone()),
    )
    .await
    .err()
    .expect("已取消的准入不得建立连接");
    assert_eq!(error.code, AdbConnectionErrorCode::Cancelled);
    assert!(!path.parent().unwrap().exists());
    adb_handshake_close(id).await.unwrap();
}

#[test]
fn identical_io_causes_are_retry_candidates_only_in_the_socket_connect_stage() {
    use std::io::{Error as IoError, ErrorKind};
    let ordinary = AdbConnectionError::from(interop_adb::Error::Io(IoError::from(
        ErrorKind::ConnectionRefused,
    )));
    assert_eq!(ordinary.code, AdbConnectionErrorCode::Io);
    let connecting = AdbConnectionError::from(interop_adb::Error::Connect(Box::new(
        interop_adb::Error::Io(IoError::from(ErrorKind::ConnectionRefused)),
    )));
    assert_eq!(connecting.code, AdbConnectionErrorCode::ConnectionRefused);
    let timeout = AdbConnectionError::from(interop_adb::Error::Connect(Box::new(
        interop_adb::Error::Timeout,
    )));
    assert_eq!(timeout.code, AdbConnectionErrorCode::ConnectTimedOut);
    for cause in [
        interop_adb::Error::Cancelled,
        interop_adb::Error::Timeout,
        interop_adb::Error::Io(IoError::from(ErrorKind::ConnectionReset)),
    ] {
        assert_eq!(
            AdbConnectionError::from(interop_adb::Error::PairingResultUnknown(Box::new(cause)))
                .code,
            AdbConnectionErrorCode::PairingResultUnknown
        );
    }
}
