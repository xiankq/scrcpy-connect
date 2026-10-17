//! Public Runtime commands with independently observed real Android task state.
use interop_adb::{Client, ConnectOptions, OperationOptions};
use interop_core::Runtime;
use serde_json::json;
use std::time::Duration;

// Large real-device scenarios keep each public command future on the heap;
// they run with the ordinary test-thread stack, without RUST_MIN_STACK changes.
async fn invoke_runtime(
    runtime: &std::sync::Arc<Runtime>,
    command: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value, interop_core::CoreError> {
    Box::pin(runtime.invoke(command, params)).await
}

struct LostStartReceipt {
    port: u16,
    writes: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    cancellation: interop_adb::CancellationToken,
    release: interop_adb::CancellationToken,
    held: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl Drop for LostStartReceipt {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

impl LostStartReceipt {
    async fn start(address: String, target_port: u16, hold_key: bool) -> Self {
        use interop_adb::protocol::{Frame, MAX_PAYLOAD, OKAY, WRTE};
        use std::sync::{
            Arc,
            atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering},
        };
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let cancellation = interop_adb::CancellationToken::new();
        let token = cancellation.clone();
        let writes = Arc::new(AtomicUsize::new(0));
        let count = writes.clone();
        let armed = Arc::new(AtomicBool::new(true));
        let release = interop_adb::CancellationToken::new();
        let resume = release.clone();
        let held = Arc::new(AtomicBool::new(false));
        let holding = held.clone();
        tokio::spawn(async move {
            loop {
                let accepted = tokio::select! { _ = token.cancelled() => break, next = listener.accept() => next };
                let Ok((incoming, _)) = accepted else {
                    break;
                };
                let Ok(outgoing) =
                    tokio::net::TcpStream::connect((address.as_str(), target_port)).await
                else {
                    break;
                };
                let (mut host_read, mut host_write) = incoming.into_split();
                let (mut device_read, mut device_write) = outgoing.into_split();
                let blocked = Arc::new(AtomicU32::new(0));
                let sent = blocked.clone();
                let count = count.clone();
                let armed = armed.clone();
                let token = token.clone();
                let resume = resume.clone();
                let holding = holding.clone();
                tokio::spawn(async move {
                    let toward_device = async {
                        loop {
                            let frame = Frame::read(&mut host_read, MAX_PAYLOAD, true).await?;
                            let payload = &frame.payload;
                            if frame.command == WRTE
                                && payload.len() == 22
                                && payload[..2] == [16, 20]
                                && &payload[2..] == b"com.android.settings"
                            {
                                count.fetch_add(1, Ordering::SeqCst);
                                if !hold_key && armed.swap(false, Ordering::SeqCst) {
                                    sent.store(frame.arg0, Ordering::SeqCst);
                                }
                            }
                            if hold_key
                                && frame.command == WRTE
                                && payload.first() == Some(&0)
                                && armed.swap(false, Ordering::SeqCst)
                            {
                                sent.store(frame.arg0, Ordering::SeqCst);
                            }
                            // Forward the actual side effect; suppress only its
                            // ADB write receipt on the other direction.
                            frame.write(&mut device_write).await?;
                        }
                        #[allow(unreachable_code)]
                        Ok::<(), interop_adb::Error>(())
                    };
                    let toward_host = async {
                        loop {
                            let frame = Frame::read(&mut device_read, MAX_PAYLOAD, true).await?;
                            if frame.command == OKAY && blocked.load(Ordering::SeqCst) == frame.arg1
                            {
                                if !hold_key {
                                    continue;
                                }
                                holding.store(true, Ordering::SeqCst);
                                resume.cancelled().await;
                                blocked.store(0, Ordering::SeqCst);
                            }
                            frame.write(&mut host_write).await?;
                        }
                        #[allow(unreachable_code)]
                        Ok::<(), interop_adb::Error>(())
                    };
                    tokio::select! { _ = token.cancelled() => {}, _ = toward_device => {}, _ = toward_host => {} }
                });
            }
        });
        Self {
            port,
            writes,
            cancellation,
            release,
            held,
        }
    }
}

#[tokio::test]
#[ignore = "requires an awake authorized legacy TCP Android target at INTEROP_ADBD_PORT"]
async fn lost_phone_screen_start_receipt_is_not_replayed_after_reentry_disconnect_or_restart() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let proxy = LostStartReceipt::start(address.clone(), port, false).await;
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    inspector
        .shell("input keyevent 3", 4096, OperationOptions::default())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(500)).await;
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = invoke_runtime(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":proxy.port}),
    )
    .await
    .unwrap();
    let device = added["deviceId"].as_str().unwrap();
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let screen = invoke_runtime(
        &runtime,
        "session.start",
        json!({"deviceId":device,"maxSize":640,"maxFps":15}),
    )
    .await
    .unwrap();
    let sid = screen["sessionId"].as_str().unwrap();
    let failure = invoke_runtime(
        &runtime,
        "session.launch",
        json!({"sessionId":sid,"packageName":"com.android.settings"}),
    )
    .await
    .unwrap_err();
    assert_eq!(
        failure.code, "app_launch_unknown",
        "a lost real START_APP receipt must be retained as unknown"
    );
    let operation = failure.details["sessionId"]
        .as_str()
        .expect("an independently closable open record");
    assert_ne!(
        operation, sid,
        "closing the failed app open must not close the phone-screen session"
    );
    assert_eq!(failure.details["linkedSessionId"], sid);
    let dump = inspector
        .shell(
            "dumpsys activity activities",
            1024 * 1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert!(
        String::from_utf8_lossy(&dump.stdout)
            .lines()
            .any(|line| line.contains("topResumedActivity=")
                && line.contains("com.android.settings/")),
        "the real app must have opened despite the withheld receipt"
    );
    assert_eq!(proxy.writes.load(std::sync::atomic::Ordering::SeqCst), 1);
    for command in ["session.start", "apps.launch"] {
        let failure = invoke_runtime(
            &runtime,
            command,
            json!({"deviceId":device,"packageName":"com.android.settings"}),
        )
        .await
        .unwrap_err();
        assert_eq!(failure.code, "app_launch_unknown");
        assert_eq!(failure.details["sessionId"], operation);
    }
    invoke_runtime(&runtime, "devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    drop(runtime);
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let retained = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert!(
        retained["sessions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|record| record["sessionId"] == operation && record["launchOutcome"] == "unknown")
    );
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let resumed = invoke_runtime(
        &runtime,
        "session.start",
        json!({"deviceId":device,"maxSize":640,"maxFps":15}),
    )
    .await
    .unwrap();
    let resumed_id = resumed["sessionId"].as_str().unwrap();
    let failure = invoke_runtime(
        &runtime,
        "session.launch",
        json!({"sessionId":resumed_id,"packageName":"com.android.settings"}),
    )
    .await
    .unwrap_err();
    assert_eq!(failure.code, "app_launch_unknown");
    assert_eq!(failure.details["sessionId"], operation);
    assert_eq!(
        proxy.writes.load(std::sync::atomic::Ordering::SeqCst),
        1,
        "readonly recovery and retries cannot repeat START_APP"
    );
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":operation}))
        .await
        .unwrap();
    let allowed = invoke_runtime(
        &runtime,
        "session.launch",
        json!({"sessionId":resumed_id,"packageName":"com.android.settings"}),
    )
    .await
    .unwrap();
    assert_eq!(allowed["sent"], true);
    assert_eq!(
        proxy.writes.load(std::sync::atomic::Ordering::SeqCst),
        2,
        "only the new explicit intent is submitted"
    );
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":resumed_id}))
        .await
        .unwrap();
    invoke_runtime(&runtime, "devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    drop(runtime);
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let completed = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert!(
        completed["sessions"].as_array().unwrap().is_empty(),
        "confirmed phone-screen writes must not become invisible permanent pending records"
    );
    invoke_runtime(&runtime, "devices.forget", json!({"deviceId":device}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires an awake authorized legacy TCP Android target at INTEROP_ADBD_PORT"]
async fn closed_queued_app_open_cannot_execute_after_an_earlier_write_recovers() {
    use std::sync::atomic::Ordering;
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let proxy = LostStartReceipt::start(address.clone(), port, true).await;
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    inspector
        .shell("input keyevent 3", 4096, OperationOptions::default())
        .await
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = invoke_runtime(
        &runtime,
        "devices.add",
        json!({"address":"127.0.0.1","port":proxy.port}),
    )
    .await
    .unwrap();
    let device = added["deviceId"].as_str().unwrap();
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let screen = invoke_runtime(
        &runtime,
        "session.start",
        json!({"deviceId":device,"maxSize":640,"maxFps":15}),
    )
    .await
    .unwrap();
    let sid = screen["sessionId"].as_str().unwrap();
    let key_runtime = runtime.clone();
    let key_sid = sid.to_owned();
    let key = tokio::spawn(async move {
        invoke_runtime(
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
    .expect("the preceding real control write must reach adbd before its ACK is delayed");
    let failure = invoke_runtime(
        &runtime,
        "session.launch",
        json!({"sessionId":sid,"packageName":"com.android.settings"}),
    )
    .await
    .unwrap_err();
    assert_eq!(failure.code, "app_launch_unknown");
    let operation = failure.details["sessionId"].as_str().unwrap();
    assert_eq!(
        proxy.writes.load(Ordering::SeqCst),
        0,
        "the app open is still behind the earlier control write"
    );
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":operation}))
        .await
        .unwrap();
    proxy.release.cancel();
    let _ = key.await.unwrap();
    tokio::time::sleep(Duration::from_millis(800)).await;
    assert_eq!(
        proxy.writes.load(Ordering::SeqCst),
        0,
        "a closed queued intent must never become a late START_APP"
    );
    let sent = invoke_runtime(
        &runtime,
        "session.launch",
        json!({"sessionId":sid,"packageName":"com.android.settings"}),
    )
    .await
    .unwrap();
    assert_eq!(sent["sent"], true);
    assert_eq!(
        proxy.writes.load(Ordering::SeqCst),
        1,
        "the later explicit open is the only submitted START_APP"
    );
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":sid}))
        .await
        .unwrap();
    invoke_runtime(&runtime, "devices.forget", json!({"deviceId":device}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires an awake authorized Android target at INTEROP_ADBD_PORT"]
async fn open_real_application_on_the_existing_phone_screen() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = invoke_runtime(
        &runtime,
        "devices.add",
        json!({"address":address,"port":port}),
    )
    .await
    .unwrap();
    let id = added["deviceId"].as_str().unwrap();
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let screen = invoke_runtime(
        &runtime,
        "session.start",
        json!({"deviceId":id,"maxSize":640,"maxFps":15}),
    )
    .await
    .unwrap();
    let sid = screen["sessionId"].as_str().unwrap();
    let result = async {
        for action in ["down", "up"] {
            invoke_runtime(&runtime, "session.key", json!({"sessionId":sid,"keyCode":3,"action":action})).await?;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
        let before = inspector.shell("dumpsys activity activities", 1024 * 1024, OperationOptions::default()).await.unwrap();
        assert!(!String::from_utf8_lossy(&before.stdout).lines().any(|line| line.contains("topResumedActivity=") && line.contains("com.android.settings/")), "the fixture must start away from Settings");
        for package in ["+com.android.settings", "?Settings", "com.android.settings;id", ""] {
            let rejected = invoke_runtime(&runtime, "session.launch", json!({"sessionId":sid,"packageName":package})).await.unwrap_err();
            assert_eq!(rejected.code, "invalid_argument");
        }
        let mismatch = invoke_runtime(&runtime, "session.launch", json!({"sessionId":sid,"deviceId":"another-device","packageName":"com.android.settings"})).await.unwrap_err();
        assert_eq!(mismatch.code, "invalid_argument");
        let sent = invoke_runtime(&runtime, "session.launch", json!({"deviceId":id,"sessionId":sid,"packageName":"com.android.settings"})).await?;
        assert_eq!(sent["sent"], true); // A write receipt is not application completion.
        tokio::time::timeout(Duration::from_secs(8), async {
            loop {
                let dump = inspector.shell("dumpsys activity activities", 1024 * 1024, OperationOptions::default()).await.unwrap();
                let text = String::from_utf8_lossy(&dump.stdout);
                let main = text.split("Display #0").nth(1).unwrap_or("").split("Display #").next().unwrap();
                if main.lines().any(|line| line.contains("topResumedActivity=") && line.contains("com.android.settings/")) {break;}
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        }).await.expect("the real Settings task must be resumed on display 0");
        let sessions = invoke_runtime(&runtime, "session.list", json!({"deviceId":id})).await?;
        assert_eq!(sessions["sessions"].as_array().unwrap().len(), 1);
        assert_eq!(sessions["sessions"][0]["sessionId"], sid);
        assert!(sessions["sessions"][0]["packageName"].is_null());
        Ok::<(), interop_core::CoreError>(())
    }.await;
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":sid}))
        .await
        .unwrap();
    invoke_runtime(&runtime, "devices.forget", json!({"deviceId":id}))
        .await
        .unwrap();
    result.unwrap();
}

#[tokio::test]
#[ignore = "requires an awake authorized Android target at INTEROP_ADBD_PORT"]
async fn unknown_independent_app_open_is_not_replayed_before_or_after_encoded_frame() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = invoke_runtime(
        &runtime,
        "devices.add",
        json!({"address":address,"port":port}),
    )
    .await
    .unwrap();
    let device = added["deviceId"].as_str().unwrap();
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let rejected = invoke_runtime(
        &runtime,
        "session.start",
        json!({"deviceId":device,"packageName":"+com.android.settings"}),
    )
    .await
    .unwrap_err();
    assert_eq!(rejected.code, "invalid_argument");
    assert_eq!(rejected.details["launchOutcome"], "not_submitted");
    assert!(
        invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
            .await
            .unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    // A valid but absent package accepts the actual START_APP control write,
    // then the undecorated display has no content to generate a first frame.
    let missing = json!({"deviceId":device,"packageName":"dev.interop.nonexistent.a49"});
    let unknown = invoke_runtime(&runtime, "session.start", missing.clone())
        .await
        .unwrap_err();
    assert_eq!(unknown.code, "app_launch_unknown");
    assert_eq!(unknown.details["launchOutcome"], "unknown");
    assert_eq!(unknown.details["failureCode"], "encoder_start_failed");
    let unknown_id = unknown.details["sessionId"].as_str().unwrap();
    for _ in 0..2 {
        let listed = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
            .await
            .unwrap();
        assert_eq!(listed["sessions"].as_array().unwrap().len(), 1);
        assert_eq!(listed["sessions"][0]["sessionId"], unknown_id);
        assert_eq!(listed["sessions"][0]["launchOutcome"], "unknown");
        let blocked = invoke_runtime(&runtime, "session.start", missing.clone())
            .await
            .unwrap_err();
        assert_eq!(blocked.code, "app_launch_unknown");
        assert_eq!(blocked.details["sessionId"], unknown_id);
    }
    // Losing a transport releases capture, never the evidence that START_APP
    // may already have changed a real task. Explicit disconnect follows the
    // same device-activity cleanup path as the connection monitor.
    invoke_runtime(&runtime, "devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    let after_disconnect = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(
        after_disconnect["sessions"].as_array().unwrap().len(),
        1,
        "disconnect must retain the unknown application-open identity"
    );
    assert_eq!(after_disconnect["sessions"][0]["sessionId"], unknown_id);
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let blocked_after_reconnect = invoke_runtime(&runtime, "session.start", missing.clone())
        .await
        .unwrap_err();
    assert_eq!(blocked_after_reconnect.code, "app_launch_unknown");
    assert_eq!(blocked_after_reconnect.details["sessionId"], unknown_id);
    invoke_runtime(&runtime, "devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    let previous = std::sync::Arc::downgrade(&runtime);
    drop(runtime);
    tokio::time::timeout(Duration::from_secs(3), async {
        while previous.upgrade().is_some() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the original Runtime must actually have ended");
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let after_restart = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(
        after_restart["sessions"].as_array().unwrap().len(),
        1,
        "a fresh Runtime must recover the unresolved application-open record"
    );
    assert_eq!(after_restart["sessions"][0]["sessionId"], unknown_id);
    assert_eq!(after_restart["sessions"][0]["launchOutcome"], "unknown");
    assert!(after_restart["sessions"][0]["textureId"].is_null());
    assert!(after_restart["sessions"][0]["videoToken"].is_null());
    invoke_runtime(&runtime, "devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let blocked_after_restart = invoke_runtime(&runtime, "session.start", missing.clone())
        .await
        .unwrap_err();
    assert_eq!(blocked_after_restart.code, "app_launch_unknown");
    assert_eq!(blocked_after_restart.details["sessionId"], unknown_id);
    // Resource admission is released even though the operation record remains.
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            let activities = invoke_runtime(&runtime, "activities.list", json!({}))
                .await
                .unwrap();
            let records = activities["activities"].as_array().unwrap();
            if !records.iter().any(|item| item["reserved"] == true) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("failed startup must release its capture reservation");
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":unknown_id}))
        .await
        .unwrap();
    assert!(
        invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
            .await
            .unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    // Model a local renderer failure after a real encoded frame: the public
    // cleanup command must stop capture while retaining the same open record.
    let request =
        json!({"deviceId":device,"packageName":"com.android.settings","maxSize":640,"maxFps":15});
    let opened = invoke_runtime(&runtime, "session.start", request.clone())
        .await
        .unwrap();
    let sid = opened["sessionId"].as_str().unwrap();
    assert_eq!(opened["encodedKeyFrameReady"], true);
    // A storage failure during renderer cleanup must still stop capture and
    // establish the in-memory gate. The old durable observed record remains
    // conservative if this Runtime later ends.
    let journal = root.path().join("app-opens.json");
    let saved_journal = tokio::fs::read(&journal).await.unwrap();
    tokio::fs::remove_file(&journal).await.unwrap();
    tokio::fs::create_dir(&journal).await.unwrap();
    let cleanup = invoke_runtime(
        &runtime,
        "session.stop",
        json!({"sessionId":sid,"keepLaunchRecord":true}),
    )
    .await
    .unwrap_err();
    assert_eq!(cleanup.code, "app_launch_unknown");
    let retained = invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(retained["sessions"][0]["launchOutcome"], "unknown");
    tokio::fs::remove_dir(&journal).await.unwrap();
    tokio::fs::write(&journal, saved_journal).await.unwrap();
    let blocked = invoke_runtime(&runtime, "session.start", request)
        .await
        .unwrap_err();
    assert_eq!(blocked.code, "app_launch_unknown");
    assert_eq!(blocked.details["sessionId"], sid);
    let primary = invoke_runtime(
        &runtime,
        "session.start",
        json!({
            "deviceId":device,"maxSize":640,"maxFps":15
        }),
    )
    .await
    .unwrap();
    let primary_id = primary["sessionId"].as_str().unwrap();
    let replayed_on_primary = invoke_runtime(
        &runtime,
        "session.launch",
        json!({
            "sessionId":primary_id,"packageName":"com.android.settings"
        }),
    )
    .await;
    invoke_runtime(&runtime, "session.stop", json!({"sessionId":primary_id}))
        .await
        .unwrap();
    let blocked = replayed_on_primary
        .expect_err("phone-screen fallback must not bypass the unknown application open");
    assert_eq!(blocked.code, "app_launch_unknown");
    assert_eq!(blocked.details["sessionId"], sid);
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let dump = inspector
        .shell(
            "dumpsys activity activities",
            1024 * 1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert!(
        String::from_utf8_lossy(&dump.stdout)
            .lines()
            .any(|line| line.contains("ActivityRecord") && line.contains("com.android.settings")),
        "renderer cleanup must preserve the real application task"
    );
    let stopped = invoke_runtime(&runtime, "session.stop", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(stopped["applicationStopped"], false);
    assert!(
        invoke_runtime(&runtime, "session.list", json!({"deviceId":device}))
            .await
            .unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty(),
        "stopping by device ID must close the exact resolved operation record"
    );
    invoke_runtime(&runtime, "devices.forget", json!({"deviceId":device}))
        .await
        .unwrap();
}
