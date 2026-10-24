//! 真实 ADB 帧与受控本机背压：协议响应、发送完成及关闭回执分别验证。
use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn direct_open_ack_and_close_are_responses_without_waiting_for_service_data() {
    for reply in [protocol::OKAY, protocol::CLSE] {
        let (connection, client, mut socket, _) = cleanup_tests::connection();
        let peer = tokio::spawn(async move {
            let open = Frame::read(&mut socket, 4096, true).await.unwrap();
            assert_eq!(
                (open.command, open.payload.as_slice()),
                (protocol::OPEN, b"sync:\0".as_slice())
            );
            Frame::new(
                reply,
                if reply == protocol::OKAY { 7 } else { 0 },
                open.arg0,
                [],
            )
            .write(&mut socket)
            .await
            .unwrap();
            assert_eq!(
                Frame::read(&mut socket, 4096, true).await.unwrap().command,
                protocol::CLSE
            );
            // 保留传输，确认只关闭了本次服务。
            let mut byte = [0];
            assert_eq!(socket.read(&mut byte).await.unwrap(), 0);
        });
        let id = adb_open_probe_create(connection.clone(), "sync:".into(), 2000)
            .await
            .unwrap();
        let facts = adb_open_probe_result(id.clone()).await.unwrap();
        assert_eq!(facts.layer, AdbOpenProbeLayer::DirectAdb);
        assert!(facts.open_written);
        assert_eq!(
            facts.outcome,
            if reply == protocol::OKAY {
                AdbOpenProbeOutcome::Okay
            } else {
                AdbOpenProbeOutcome::Rejected
            }
        );
        assert_ne!(facts.inbound_activity, "0");
        adb_open_probe_close(id, 2000).await.unwrap();
        assert!(!client.is_closed());
        adb_disconnect(connection).await.unwrap();
        client
            .close_and_wait(OperationOptions::default())
            .await
            .unwrap();
        peer.await.unwrap();
    }
}

#[tokio::test]
async fn blocked_writer_is_not_a_network_failure_and_cleanup_keeps_the_exact_retry() {
    let (connection, client, socket, writes) = cleanup_tests::connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let peer = tokio::spawn(cleanup_tests::peer(socket, notice));
    // 另一个打开的 shell 必须贯穿探测取消保持可用。
    let shell = client
        .open("shell:cat", OperationOptions::default())
        .await
        .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    writes.pause();
    let id = adb_open_probe_create(connection.clone(), "sync:".into(), 30)
        .await
        .unwrap();
    let facts = adb_open_probe_result(id.clone()).await.unwrap();
    assert!(!facts.open_written, "进入 writer 队列不是实际写出");
    assert_eq!(facts.outcome, AdbOpenProbeOutcome::NotWritten);
    let error = adb_open_probe_close(id.clone(), 20).await.unwrap_err();
    assert_eq!(error.code, AdbConnectionErrorCode::CleanupUnconfirmed);
    assert!(registry().lock().unwrap().operations.contains_key(&id));
    assert!(!client.is_closed());
    writes.resume();
    adb_open_probe_close(id.clone(), 2000).await.unwrap();
    assert!(!registry().lock().unwrap().operations.contains_key(&id));
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    let before = client.inbound_activity();
    drop(shell);
    client
        .flush_closed_streams(OperationOptions::default())
        .await
        .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    assert!(client.inbound_activity() >= before);
    adb_disconnect(connection).await.unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
    peer.await.unwrap();
}

#[tokio::test]
async fn actually_written_open_without_response_has_a_response_timeout() {
    let (connection, client, mut socket, _) = cleanup_tests::connection();
    let peer = tokio::spawn(async move {
        let frame = Frame::read(&mut socket, 4096, true).await.unwrap();
        assert_eq!(frame.command, protocol::OPEN);
        // 不回复，但持续读到本次 CLSE，不能把服务无数据误当成功。
        assert_eq!(
            Frame::read(&mut socket, 4096, true).await.unwrap().command,
            protocol::CLSE
        );
    });
    let id = adb_open_probe_create(connection.clone(), "sync:".into(), 100)
        .await
        .unwrap();
    let facts = adb_open_probe_result(id.clone()).await.unwrap();
    assert!(facts.open_written);
    assert_eq!(facts.outcome, AdbOpenProbeOutcome::TimedOut);
    adb_open_probe_close(id, 2000).await.unwrap();
    adb_disconnect(connection).await.unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
    peer.await.unwrap();
}

#[tokio::test]
async fn local_stream_capacity_is_distinct_and_does_not_close_other_streams() {
    let (connection, client, socket, _) = cleanup_tests::connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let peer = tokio::spawn(cleanup_tests::peer(socket, notice));
    let mut streams = Vec::new();
    for _ in 0..128 {
        streams.push(
            client
                .open("shell:held", OperationOptions::default())
                .await
                .unwrap(),
        );
        assert_eq!(notices.recv().await, Some(protocol::OPEN));
    }
    let id = adb_open_probe_create(connection.clone(), "sync:".into(), 2000)
        .await
        .unwrap();
    let facts = adb_open_probe_result(id.clone()).await.unwrap();
    assert_eq!(facts.outcome, AdbOpenProbeOutcome::LocalCapacity);
    assert!(!facts.open_written);
    adb_open_probe_close(id, 2000).await.unwrap();
    assert!(!client.is_closed());
    drop(streams);
    adb_disconnect(connection).await.unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
    peer.await.unwrap();
}

#[tokio::test]
async fn close_cancels_a_pending_probe_and_preserves_its_own_result_waiter() {
    let (connection, client, mut socket, _) = cleanup_tests::connection();
    let id = adb_open_probe_create(connection.clone(), "sync:".into(), 60000)
        .await
        .unwrap();
    let result = tokio::spawn(adb_open_probe_result(id.clone()));
    let frame = Frame::read(&mut socket, 4096, true).await.unwrap();
    assert_eq!(frame.command, protocol::OPEN);
    adb_open_probe_close(id, 2000).await.unwrap();
    let facts = result.await.unwrap().unwrap();
    assert_eq!(facts.outcome, AdbOpenProbeOutcome::Cancelled);
    assert!(facts.open_written);
    assert_eq!(
        Frame::read(&mut socket, 4096, true).await.unwrap().command,
        protocol::CLSE
    );
    adb_disconnect(connection).await.unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
}

async fn request(socket: &mut tokio::net::TcpStream) -> Vec<u8> {
    let mut length = [0; 4];
    socket.read_exact(&mut length).await.unwrap();
    let length = usize::from_str_radix(std::str::from_utf8(&length).unwrap(), 16).unwrap();
    let mut bytes = vec![0; length];
    socket.read_exact(&mut bytes).await.unwrap();
    bytes
}

#[tokio::test]
async fn official_server_probe_exposes_smart_socket_response_and_releases_its_socket() {
    for reply in [b"OKAY", b"FAIL"] {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let peer = tokio::spawn(async move {
            let (mut transport, _) = listener.accept().await.unwrap();
            assert_eq!(request(&mut transport).await, b"host:tport:serial:probe");
            transport.write_all(b"OKAY").await.unwrap();
            transport.write_all(&7u64.to_le_bytes()).await.unwrap();
            drop(transport);
            let (mut features, _) = listener.accept().await.unwrap();
            assert_eq!(
                request(&mut features).await,
                b"host-transport-id:7:features"
            );
            features.write_all(b"OKAY0000").await.unwrap();
            drop(features);
            let (mut service, _) = listener.accept().await.unwrap();
            assert_eq!(request(&mut service).await, b"host:transport-id:7");
            service.write_all(b"OKAY").await.unwrap();
            assert_eq!(request(&mut service).await, b"sync:");
            service.write_all(reply).await.unwrap();
            // FAIL 不需要额外正文就能证明服务器已有明确拒绝响应。
            assert_eq!(service.read(&mut [0]).await.unwrap(), 0);
        });
        let client = Client::connect_server(address, "probe", OperationOptions::default())
            .await
            .unwrap();
        let connection = insert_connection(client.clone(), "probe".into(), true)
            .unwrap()
            .id;
        let id = adb_open_probe_create(connection.clone(), "sync:".into(), 2000)
            .await
            .unwrap();
        let facts = adb_open_probe_result(id.clone()).await.unwrap();
        assert_eq!(facts.layer, AdbOpenProbeLayer::OfficialServer);
        assert_eq!(
            facts.outcome,
            if reply == b"OKAY" {
                AdbOpenProbeOutcome::Okay
            } else {
                AdbOpenProbeOutcome::Rejected
            }
        );
        assert!(facts.open_written);
        assert_ne!(facts.inbound_activity, "0");
        adb_open_probe_close(id, 2000).await.unwrap();
        adb_disconnect(connection).await.unwrap();
        peer.await.unwrap();
    }
}

#[tokio::test]
async fn partial_inbound_bytes_advance_the_opaque_snapshot_without_a_complete_frame() {
    let (connection, client, mut socket, _) = cleanup_tests::connection();
    let before = adb_connection_facts(connection.clone()).unwrap();
    socket.write_all(b"O").await.unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while adb_connection_facts(connection.clone())
            .unwrap()
            .inbound_activity
            == before.inbound_activity
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(!adb_connection_facts(connection.clone()).unwrap().closed);
    adb_disconnect(connection).await.unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
}
