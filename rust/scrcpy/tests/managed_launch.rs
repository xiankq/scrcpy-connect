//! 通过真实 ADB 帧验证启动授权、停止回执与精确退出核验，不读取内部状态。
use interop_adb::{
    CancellationToken, Client, DeviceInfo,
    protocol::{self, Frame},
};
use interop_scrcpy::{config::Options, session::Session};
use std::time::Duration;

fn client() -> (Client, tokio::io::DuplexStream) {
    let (transport, peer) = tokio::io::duplex(64 * 1024);
    (
        Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 64 * 1024,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap(),
        peer,
    )
}
async fn read(peer: &mut tokio::io::DuplexStream) -> Frame {
    tokio::time::timeout(Duration::from_secs(1), Frame::read(peer, 64 * 1024, true))
        .await
        .unwrap()
        .unwrap()
}
async fn accept(peer: &mut tokio::io::DuplexStream) -> u32 {
    let frame = read(peer).await;
    assert_eq!(frame.command, protocol::OPEN);
    Frame::new(protocol::OKAY, 77, frame.arg0, [])
        .write(peer)
        .await
        .unwrap();
    frame.arg0
}
async fn command(peer: &mut tokio::io::DuplexStream, local: u32) -> String {
    loop {
        let frame = read(peer).await;
        if frame.command == protocol::OKAY {
            continue;
        }
        assert_eq!((frame.command, frame.arg0), (protocol::WRTE, local));
        Frame::new(protocol::OKAY, 77, local, [])
            .write(peer)
            .await
            .unwrap();
        return String::from_utf8(frame.payload).unwrap();
    }
}
async fn output(peer: &mut tokio::io::DuplexStream, local: u32, bytes: impl AsRef<[u8]>) {
    Frame::new(protocol::WRTE, 77, local, bytes.as_ref())
        .write(peer)
        .await
        .unwrap();
}
async fn remote_close(peer: &mut tokio::io::DuplexStream, local: u32) {
    Frame::new(protocol::CLSE, 77, local, [])
        .write(peer)
        .await
        .unwrap();
}
fn session(client: &Client, cancellation: &CancellationToken) -> Session {
    Session::new(client.clone(), 1, Options::default(), cancellation.clone()).unwrap()
}

#[tokio::test]
async fn pre_cancelled_launch_never_sends_open_or_start() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    cancellation.cancel();
    let session = session(&client, &cancellation);
    let state = session.launch_state();
    assert!(session.launch_prepared("fixture").await.is_err());
    state.wait_exited(&client).await.unwrap();
    assert!(
        tokio::time::timeout(
            Duration::from_millis(20),
            Frame::read(&mut peer, 65536, true)
        )
        .await
        .is_err()
    );
    client.close();
}

#[tokio::test]
async fn launch_waits_for_run_write_and_stop_waits_for_its_unique_done() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session = session(&client, &cancellation);
    let state = session.launch_state();
    let launching = tokio::spawn(session.launch_prepared("fixture"));
    let local = accept(&mut peer).await;
    let start = command(&mut peer, local).await;
    let nonce = start.strip_prefix("START:").unwrap().trim_end().to_owned();
    assert_eq!(nonce.len(), 32);
    output(&mut peer, local, b"__INTEROP_PID__123:456\n").await;
    // PID 已到达仍不能交付：本次 RUN 必须真正写入并获得 ADB ACK。
    let run = loop {
        let frame = read(&mut peer).await;
        if frame.command == protocol::WRTE {
            break frame;
        }
        assert_eq!(frame.command, protocol::OKAY);
    };
    assert_eq!(run.payload, format!("RUN:{nonce}\n").as_bytes());
    assert!(!launching.is_finished());
    Frame::new(protocol::OKAY, 77, local, [])
        .write(&mut peer)
        .await
        .unwrap();
    let mut launched = launching.await.unwrap().unwrap();
    assert_eq!((launched.pid, launched.started), (123, 456));
    cancellation.cancel();
    assert_eq!(command(&mut peer, local).await, format!("STOP:{nonce}\n"));
    let reading = tokio::spawn(async move {
        let mut log = Vec::new();
        let mut bytes = [0; 1024];
        loop {
            let count = launched.process.read(&mut bytes).await.unwrap();
            if count == 0 {
                break;
            }
            log.extend_from_slice(&bytes[..count]);
        }
        log
    });
    output(
        &mut peer,
        local,
        b"log\n__INTEROP_PID__999:999\n__INTEROP_DONE__wrong\n",
    )
    .await;
    assert!(!reading.is_finished(), "错误 nonce 不能完成停止");
    output(&mut peer, local, format!("\n__INTEROP_DONE__{nonce}\n")).await;
    let log = reading.await.unwrap();
    assert!(String::from_utf8_lossy(&log).contains("__INTEROP_PID__999:999"));
    state.wait_exited(&client).await.unwrap();
    client.close();
}

#[tokio::test]
async fn cancellation_before_identity_keeps_the_reader_until_done() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session = session(&client, &cancellation);
    let state = session.launch_state();
    let launching = tokio::spawn(session.launch_prepared("fixture"));
    let local = accept(&mut peer).await;
    let start = command(&mut peer, local).await;
    let nonce = start.strip_prefix("START:").unwrap().trim_end();
    cancellation.cancel();
    assert!(launching.await.unwrap().is_err());
    assert_eq!(command(&mut peer, local).await, format!("STOP:{nonce}\n"));
    let waiting = tokio::spawn({
        let client = client.clone();
        async move { state.wait_exited(&client).await }
    });
    assert!(!waiting.is_finished());
    output(&mut peer, local, format!("\n__INTEROP_DONE__{nonce}\n")).await;
    waiting.await.unwrap().unwrap();
    client.close();
}

#[tokio::test]
async fn missing_identity_and_done_is_unknown_and_never_runs_external_cleanup() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session = session(&client, &cancellation);
    let state = session.launch_state();
    let launching = tokio::spawn(session.launch_prepared("fixture"));
    let local = accept(&mut peer).await;
    command(&mut peer, local).await;
    remote_close(&mut peer, local).await;
    assert!(launching.await.unwrap().is_err());
    let error = state.wait_exited(&client).await.unwrap_err();
    assert!(matches!(
        error,
        interop_scrcpy::Error::Failure {
            code: "process_cleanup_unverified",
            ..
        }
    ));
    // 只允许原流的关闭帧，不得依据未知身份发 rm 或按名称搜索。
    loop {
        match tokio::time::timeout(
            Duration::from_millis(20),
            Frame::read(&mut peer, 65536, true),
        )
        .await
        {
            Err(_) => break,
            Ok(Ok(frame)) => assert_eq!(frame.command, protocol::CLSE),
            other => panic!("意外帧：{other:?}"),
        }
    }
    client.close();
}

#[tokio::test]
async fn missing_done_retries_only_the_original_identity_and_rejects_invalid_receipts() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session = session(&client, &cancellation);
    let state = session.launch_state();
    let launching = tokio::spawn(session.launch_prepared("fixture"));
    let local = accept(&mut peer).await;
    command(&mut peer, local).await;
    output(&mut peer, local, b"__INTEROP_PID__123:456\n").await;
    command(&mut peer, local).await;
    let launched = launching.await.unwrap().unwrap();
    // 后续 PID 样式是日志，不能覆盖原身份。
    output(&mut peer, local, b"__INTEROP_PID__999:999\n").await;
    cancellation.cancel();
    command(&mut peer, local).await;
    remote_close(&mut peer, local).await;
    drop(launched);
    for (receipt, successful) in [
        ("released:unknown\n", false),
        ("released:absent\nextra\n", false),
        ("released:replaced\n", true),
    ] {
        let waiting = tokio::spawn({
            let state = state.clone();
            let client = client.clone();
            async move { state.wait_exited(&client).await }
        });
        let query = loop {
            let frame = read(&mut peer).await;
            if frame.command == protocol::OPEN {
                break frame;
            }
            assert!(matches!(frame.command, protocol::OKAY | protocol::CLSE));
        };
        let text = String::from_utf8_lossy(&query.payload);
        assert!(text.contains("p=123") && text.contains("expected=456"));
        assert!(!text.contains("rm -f") && !text.contains("p=999"));
        Frame::new(protocol::OKAY, 77, query.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        output(&mut peer, query.arg0, receipt).await;
        remote_close(&mut peer, query.arg0).await;
        assert_eq!(waiting.await.unwrap().is_ok(), successful);
    }
    client.close();
}
