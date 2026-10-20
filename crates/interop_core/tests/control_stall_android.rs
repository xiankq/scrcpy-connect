//! Selectively lose a control receipt while real Android video and sync survive.
mod support;
use interop_adb::{CancellationToken, protocol};
use interop_core::Runtime;
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering},
};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

struct ControlAckGate {
    port: u16,
    held: Arc<AtomicBool>,
    keys: Arc<AtomicUsize>,
    closed: Arc<AtomicBool>,
    cancellation: CancellationToken,
}

impl Drop for ControlAckGate {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

impl ControlAckGate {
    async fn start(address: &str, port: u16) -> Self {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let result = Self {
            port: listener.local_addr().unwrap().port(),
            held: Arc::new(AtomicBool::new(false)),
            keys: Arc::new(AtomicUsize::new(0)),
            closed: Arc::new(AtomicBool::new(false)),
            cancellation: CancellationToken::new(),
        };
        let address = address.to_owned();
        let held = result.held.clone();
        let keys = result.keys.clone();
        let closed = result.closed.clone();
        let cancellation = result.cancellation.clone();
        tokio::spawn(async move {
            loop {
                let accepted = tokio::select! {
                    _ = cancellation.cancelled() => break,
                    next = listener.accept() => next,
                };
                let Ok((host, _)) = accepted else { break };
                let Ok(device) = tokio::net::TcpStream::connect((address.as_str(), port)).await
                else {
                    break;
                };
                let (mut host_read, mut host_write) = host.into_split();
                let (mut device_read, mut device_write) = device.into_split();
                let route = Arc::new(AtomicU32::new(0));
                let key_route = route.clone();
                let held = held.clone();
                let keys = keys.clone();
                let closed = closed.clone();
                let cancellation = cancellation.clone();
                tokio::spawn(async move {
                    let to_device = async {
                        loop {
                            let frame =
                                protocol::Frame::read(&mut host_read, protocol::MAX_PAYLOAD, true)
                                    .await?;
                            if frame.command == protocol::WRTE && frame.payload.first() == Some(&0)
                            {
                                keys.fetch_add(1, Ordering::SeqCst);
                                let _ = key_route.compare_exchange(
                                    0,
                                    frame.arg0,
                                    Ordering::SeqCst,
                                    Ordering::SeqCst,
                                );
                            }
                            if frame.command == protocol::CLSE
                                && frame.arg0 == key_route.load(Ordering::SeqCst)
                            {
                                closed.store(true, Ordering::SeqCst);
                            }
                            frame.write(&mut device_write).await?;
                        }
                        #[allow(unreachable_code)]
                        Ok::<(), interop_adb::Error>(())
                    };
                    let to_host = async {
                        loop {
                            let frame = protocol::Frame::read(
                                &mut device_read,
                                protocol::MAX_PAYLOAD,
                                true,
                            )
                            .await?;
                            if frame.command == protocol::OKAY
                                && frame.arg1 == route.load(Ordering::SeqCst)
                            {
                                // Continue forwarding every other route. Blocking this loop
                                // would simulate an entire transport outage instead.
                                held.store(true, Ordering::SeqCst);
                                continue;
                            }
                            frame.write(&mut host_write).await?;
                        }
                        #[allow(unreachable_code)]
                        Ok::<(), interop_adb::Error>(())
                    };
                    tokio::select! {
                        _ = cancellation.cancelled() => {},
                        _ = to_device => {},
                        _ = to_host => {},
                    }
                });
            }
        });
        result
    }
}

async fn invoke(
    runtime: &Arc<Runtime>,
    command: &str,
    params: Value,
) -> Result<Value, interop_core::CoreError> {
    Box::pin(runtime.invoke(command, params)).await
}

#[tokio::test]
#[ignore = "requires an awake authorized legacy TCP Android target at INTEROP_ADBD_PORT"]
async fn stalled_control_expires_without_late_keys_or_device_disconnect() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let proxy = ControlAckGate::start(&address, port).await;
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = invoke(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1", "port":proxy.port}),
    )
    .await
    .unwrap();
    let device = added["deviceId"].as_str().unwrap();
    invoke(&runtime, "observation.stop", json!({"deviceId":device}))
        .await
        .unwrap();
    invoke(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let session = invoke(
        &runtime,
        "session.start",
        support::media_params(json!({"deviceId":device,"maxSize":640,"maxFps":15})),
    )
    .await
    .unwrap();
    let sid = session["sessionId"].as_str().unwrap();
    // A screen session must not bypass the helper startup policy. Reads use
    // request IDs: scrcpy GET has no correlation ID and may legally be silent.
    let guarded = invoke(
        &runtime,
        "clipboard.get",
        json!({"deviceId":device,"allowStart":false}),
    )
    .await
    .unwrap_err();
    assert_eq!(guarded.code, "observation_required");
    let original_clipboard = invoke(
        &runtime,
        "clipboard.get",
        json!({"deviceId":device,"allowStart":true}),
    )
    .await
    .unwrap();
    assert_eq!(original_clipboard["source"], "companion");
    for _ in 0..2 {
        let marker = format!("control-stall-{}", uuid::Uuid::new_v4());
        let applied = invoke(
            &runtime,
            "clipboard.set",
            json!({"deviceId":device,"text":marker}),
        )
        .await
        .unwrap();
        assert_eq!(applied["applied"], true);
        let read = invoke(
            &runtime,
            "clipboard.get",
            json!({"deviceId":device,"allowStart":false}),
        )
        .await
        .unwrap();
        assert_eq!(read["source"], "companion");
        assert_eq!(read["text"], marker);
    }
    let snapshot = invoke(&runtime, "state.snapshot", json!({})).await.unwrap();
    assert_eq!(snapshot["observations"][0]["wanted"], false);
    for section in ["notifications", "calls"] {
        assert_eq!(
            snapshot["companions"][0]["state"][section]["status"],
            "stopped"
        );
    }
    let mut video = tokio::net::TcpStream::connect((
        "127.0.0.1",
        session["videoPort"].as_u64().unwrap() as u16,
    ))
    .await
    .unwrap();
    video
        .write_all(format!("{}\n", session["videoToken"].as_str().unwrap()).as_bytes())
        .await
        .unwrap();
    let video_bytes = Arc::new(AtomicUsize::new(0));
    let bytes = video_bytes.clone();
    let video_reader = tokio::spawn(async move {
        let mut buffer = [0; 65536];
        while let Ok(n) = video.read(&mut buffer).await {
            if n == 0 {
                break;
            }
            bytes.fetch_add(n, Ordering::SeqCst);
        }
    });
    let key_runtime = runtime.clone();
    let key_sid = sid.to_owned();
    let first = tokio::spawn(async move {
        invoke(
            &key_runtime,
            "session.key",
            json!({"sessionId":key_sid,"keyCode":82,"action":"up"}),
        )
        .await
    });
    tokio::time::timeout(Duration::from_secs(5), async {
        while !proxy.held.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("first actual control WRTE must reach Android");
    let bytes_before = video_bytes.load(Ordering::SeqCst);
    let next_runtime = runtime.clone();
    let next_sid = sid.to_owned();
    let next = tokio::spawn(async move {
        invoke(
            &next_runtime,
            "session.key",
            json!({"sessionId":next_sid,"keyCode":3,"action":"up"}),
        )
        .await
    });
    // All listings use the same Runtime/Client through the gated proxy.
    let mut healthy_lists = 0;
    for _ in 0..3 {
        let listed = invoke(
            &runtime,
            "files.list",
            json!({"deviceId":device,"path":"/sdcard"}),
        )
        .await;
        if listed.is_ok() && !proxy.closed.load(Ordering::SeqCst) {
            healthy_lists += 1;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    let first_result = tokio::time::timeout(Duration::from_secs(8), first).await;
    let next_result = tokio::time::timeout(Duration::from_secs(2), next).await;
    let route_closed = tokio::time::timeout(Duration::from_secs(2), async {
        while !proxy.closed.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .is_ok();
    let bytes_after = video_bytes.load(Ordering::SeqCst);
    let listed_after = invoke(
        &runtime,
        "files.list",
        json!({"deviceId":device,"path":"/sdcard"}),
    )
    .await;
    let keys = proxy.keys.load(Ordering::SeqCst);
    let _ = invoke(&runtime, "session.stop", json!({"sessionId":sid})).await;
    if original_clipboard["hasText"] == true {
        invoke(
            &runtime,
            "clipboard.set",
            json!({"deviceId":device,"text":original_clipboard["text"]}),
        )
        .await
        .unwrap();
    }
    invoke(&runtime, "devices.forget", json!({"deviceId":device}))
        .await
        .unwrap();
    video_reader.abort();
    let _ = video_reader.await;
    assert!(
        first_result.unwrap().unwrap().is_err(),
        "unconfirmed delivery must not succeed"
    );
    assert!(
        next_result.unwrap().unwrap().is_err(),
        "queued old input must fail"
    );
    assert!(
        route_closed,
        "only the stalled control route must close within its bound"
    );
    assert_eq!(keys, 1, "a queued old key must never reach Android");
    assert_eq!(
        healthy_lists, 3,
        "other ADB streams must work during the fault"
    );
    assert!(
        listed_after.is_ok(),
        "device connection must remain usable after session termination"
    );
    assert!(
        bytes_after > bytes_before,
        "real video must continue during the control-only fault"
    );
    println!(
        "control-only fault: keys={keys}, healthy_lists={healthy_lists}, video_bytes={bytes_before}..{bytes_after}, route_closed={route_closed}"
    );
}
