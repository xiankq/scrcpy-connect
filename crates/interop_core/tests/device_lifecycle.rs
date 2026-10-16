use interop_core::Runtime;
use serde_json::{Value, json};
use std::time::Duration;

async fn add(runtime: &std::sync::Arc<Runtime>, address: &str, port: u16) -> Value {
    runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap()
}
#[tokio::test]
async fn device_ids_survive_storage_and_equal_addresses_never_merge_records() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    let first = add(&runtime, "127.0.0.1", 5555).await;
    let second = add(&runtime, "127.0.0.1", 5555).await;
    let id = first["deviceId"].as_str().unwrap().to_owned();
    assert_ne!(first["deviceId"], second["deviceId"]);
    assert!(uuid::Uuid::parse_str(&id).is_ok());
    assert_eq!(first["device"]["status"], "offline");
    runtime
        .invoke("devices.rename", json!({"deviceId":id,"name":"我的手机"}))
        .await
        .unwrap();
    let changed = runtime
        .invoke(
            "devices.add",
            json!({"deviceId":id,"address":"192.0.2.7","port":37001}),
        )
        .await
        .unwrap();
    assert_eq!(changed["deviceId"], id);
    assert_eq!(changed["device"]["name"], "我的手机");
    drop(runtime);
    let restored = Runtime::initialize(dir.path()).await.unwrap();
    let list = restored.invoke("devices.list", json!({})).await.unwrap();
    let devices = list["devices"].as_array().unwrap();
    assert_eq!(devices.len(), 2);
    let device = devices.iter().find(|d| d["id"] == id).unwrap();
    assert_eq!(device["address"], "192.0.2.7");
    assert_eq!(device["port"], 37001);
    assert_eq!(device["status"], "offline");
    restored.invoke("settings.update",json!({"deviceQuality":{&id:{"videoCodec":"h265"}},"audioDevices":[&id],"clipboardMode":"fixed","clipboardDevice":&id})).await.unwrap();
    restored
        .invoke("devices.forget", json!({"deviceId":&id}))
        .await
        .unwrap();
    let settings = restored.invoke("settings.get", json!({})).await.unwrap();
    assert!(settings["deviceQuality"].get(&id).is_none());
    assert_eq!(settings["audioDevices"], json!([]));
    assert!(settings["clipboardDevice"].is_null());
}

#[tokio::test]
async fn explicit_disconnect_cancels_an_in_progress_connection_and_prevents_revival() {
    use tokio::io::AsyncReadExt;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (accepted, ready) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let frame = interop_adb::protocol::Frame::read(&mut stream, 4096, false)
            .await
            .unwrap();
        assert_eq!(frame.command, interop_adb::protocol::CNXN);
        accepted.send(()).unwrap();
        let mut byte = [0u8; 1];
        assert_eq!(
            stream.read(&mut byte).await.unwrap(),
            0,
            "cancel must close the handshake socket"
        );
    });
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    let device = add(&runtime, "127.0.0.1", port).await;
    let id = device["deviceId"].as_str().unwrap().to_owned();
    let owner = runtime.clone();
    let connect_id = id.clone();
    let connect = tokio::spawn(async move {
        owner
            .invoke("devices.connect", json!({"deviceId":connect_id}))
            .await
    });
    tokio::time::timeout(Duration::from_secs(20), ready)
        .await
        .unwrap()
        .unwrap();
    let disconnect_owner = runtime.clone();
    let disconnect_id = id.clone();
    let disconnect = tokio::spawn(async move {
        disconnect_owner
            .invoke("devices.disconnect", json!({"deviceId":disconnect_id}))
            .await
    });
    // Cancellation must close the socket promptly. Persistent offline state
    // also fsyncs; its completion must not be confused with network release.
    tokio::time::timeout(Duration::from_secs(2), server)
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(20), disconnect)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let result = tokio::time::timeout(Duration::from_secs(20), connect)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(result.unwrap_err().code, "cancelled");
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(record["status"], "offline");
    assert_eq!(record["autoReconnect"], false);
    runtime
        .invoke("devices.forget", json!({"deviceId":id}))
        .await
        .unwrap();
    assert!(
        runtime.invoke("devices.list", json!({})).await.unwrap()["devices"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn cancelling_an_old_form_attempt_never_cancels_its_replacement() {
    use tokio::io::AsyncReadExt;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let (accepted, mut ready) = tokio::sync::mpsc::channel(2);
    let (closed, mut disconnected) = tokio::sync::mpsc::channel(2);
    let server = tokio::spawn(async move {
        let mut tasks = Vec::new();
        for index in 0..2 {
            let (mut stream, _) = listener.accept().await.unwrap();
            let ready = accepted.clone();
            let closed = closed.clone();
            tasks.push(tokio::spawn(async move {
                let frame = interop_adb::protocol::Frame::read(&mut stream, 4096, false)
                    .await
                    .unwrap();
                assert_eq!(frame.command, interop_adb::protocol::CNXN);
                ready.send(()).await.unwrap();
                assert_eq!(stream.read(&mut [0u8; 1]).await.unwrap(), 0);
                closed.send(index).await.unwrap();
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
    });
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    let added = add(&runtime, "127.0.0.1", port).await;
    let id = added["deviceId"].as_str().unwrap().to_owned();
    let connect = |attempt: &'static str| {
        let runtime = runtime.clone();
        let id = id.clone();
        tokio::spawn(async move {
            runtime
                .invoke(
                    "devices.connect",
                    json!({"deviceId":id,"attemptId":attempt}),
                )
                .await
        })
    };
    let first = connect("form-old");
    tokio::time::timeout(Duration::from_secs(20), ready.recv())
        .await
        .unwrap()
        .unwrap();
    let mut second = connect("form-new");
    tokio::time::timeout(Duration::from_secs(20), ready.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first.await.unwrap().unwrap_err().code, "cancelled");
    assert_eq!(disconnected.recv().await, Some(0));
    runtime
        .invoke("devices.cancel", json!({"attemptId":"form-old"}))
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(100), &mut second)
            .await
            .is_err()
    );
    assert_eq!(
        runtime
            .invoke("device.info", json!({"deviceId":id}))
            .await
            .unwrap()["status"],
        "connecting"
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(100), disconnected.recv())
            .await
            .is_err(),
        "cancelling the old alias must leave the replacement socket open"
    );
    let cancelling = {
        let runtime = runtime.clone();
        tokio::spawn(async move {
            runtime
                .invoke("devices.cancel", json!({"attemptId":"form-new"}))
                .await
        })
    };
    // Measure actual transport cancellation independently of the durable state
    // fsyncs awaited by both cancel and connect. Loaded filesystems must not
    // turn a prompt socket close into an apparent protocol cancellation failure.
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), disconnected.recv())
            .await
            .unwrap(),
        Some(1)
    );
    tokio::time::timeout(Duration::from_secs(20), cancelling)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(20), second)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err()
            .code,
        "cancelled"
    );
    assert_eq!(
        runtime
            .invoke("device.info", json!({"deviceId":id}))
            .await
            .unwrap()["status"],
        "offline"
    );
    tokio::time::timeout(Duration::from_secs(2), server)
        .await
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn offline_and_unimplemented_capabilities_remain_unknown_and_pair_codes_are_validated() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    let device = add(&runtime, "127.0.0.1", 5555).await;
    let id = device["deviceId"].as_str().unwrap();
    let capabilities = runtime
        .invoke("device.capabilities", json!({"deviceId":id}))
        .await
        .unwrap();
    for key in [
        "screen",
        "audio",
        "calls",
        "notifications",
        "wirelessPairing",
    ] {
        let item = capabilities["capabilities"]
            .as_array()
            .unwrap()
            .iter()
            .find(|entry| entry["key"] == key)
            .unwrap();
        assert_eq!(item["status"], "unknown");
    }
    let error = runtime
        .invoke(
            "devices.pair",
            json!({"address":"127.0.0.1","port":1,"code":"12345x"}),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "invalid_pairing_code");
    let error = runtime
        .invoke(
            "devices.add",
            json!({"address":"127.0.0.1:5555","port":5555}),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "invalid_address");
}

#[cfg(any(target_os = "linux", target_os = "android"))]
#[tokio::test]
async fn invalid_usb_fd_does_not_take_ownership_of_the_platform_descriptor() {
    use std::os::fd::AsRawFd;
    let file = std::fs::File::open("/dev/null").unwrap();
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    assert!(
        runtime
            .invoke("devices.usb", json!({"fd":file.as_raw_fd()}))
            .await
            .is_err()
    );
    assert!(file.metadata().is_ok());
}

#[tokio::test]
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn actual_android_device_metadata_and_services_are_read_through_runtime() {
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("INTEROP_CORE_TEST_ENDPOINT")
        .parse::<std::net::SocketAddr>()
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
    let added = add(&runtime, &endpoint.ip().to_string(), endpoint.port()).await;
    let id = added["deviceId"].as_str().unwrap();
    let connected = runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(connected["connected"], true);
    assert!(
        connected["device"]["model"]
            .as_str()
            .is_some_and(|model| !model.is_empty())
    );
    assert!(
        connected["device"]["apiLevel"]
            .as_u64()
            .is_some_and(|api| api >= 21)
    );
    assert!(connected["device"]["lastSeen"].as_u64().is_some());
    let caps = runtime
        .invoke("device.capabilities", json!({"deviceId":id}))
        .await
        .unwrap();
    for key in ["shell", "files"] {
        assert_eq!(
            caps["capabilities"]
                .as_array()
                .unwrap()
                .iter()
                .find(|cap| cap["key"] == key)
                .unwrap()["status"],
            "available"
        );
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "changes sleep state on an explicitly designated isolated Android test device"]
async fn sleeping_target_requires_explicit_wake_without_starting_capture() {
    use interop_adb::{Client, ConnectOptions, Identity, OperationOptions};
    assert_eq!(
        std::env::var("INTEROP_ALLOW_DEVICE_SLEEP_TEST").as_deref(),
        Ok("1"),
        "This test must only run on an isolated test target."
    );
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT").unwrap();
    let (address, port) = endpoint.rsplit_once(':').unwrap();
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = add(&runtime, address, port.parse().unwrap()).await;
    let id = added["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let identity = Identity::from_pem(
        &tokio::fs::read_to_string(directory.path().join("host_identity.pem"))
            .await
            .unwrap(),
    )
    .unwrap();
    let client = Client::connect_tcp(
        endpoint,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    client
        .shell("input keyevent 223", 1024, OperationOptions::default())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    let start = runtime
        .invoke("session.start", json!({"deviceId":id}))
        .await;
    let asleep = client
        .shell(
            "dumpsys power | sed -n 's/^ *mWakefulness=//p'",
            4096,
            OperationOptions::default(),
        )
        .await;
    // Restore the isolated target before making assertions, including when the
    // actual start probe returned an unexpected result.
    let wake = runtime.invoke("devices.wake", json!({"deviceId":id})).await;
    client.close();
    assert_eq!(start.unwrap_err().code, "device_asleep");
    let asleep = asleep.unwrap();
    let wakefulness = String::from_utf8_lossy(&asleep.stdout);
    assert!(matches!(wakefulness.trim(), "Asleep" | "Dozing"));
    assert_eq!(wake.unwrap()["awake"], true);
    let sessions = runtime.invoke("session.list", json!({})).await.unwrap();
    assert!(sessions["sessions"].as_array().unwrap().is_empty());
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}
