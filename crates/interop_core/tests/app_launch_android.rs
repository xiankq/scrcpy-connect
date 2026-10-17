//! Public Runtime commands with independently observed real Android task state.
use interop_adb::{Client, ConnectOptions, OperationOptions};
use interop_core::Runtime;
use serde_json::json;
use std::time::Duration;

#[tokio::test]
#[ignore = "requires an awake authorized Android target at INTEROP_ADBD_PORT"]
async fn open_real_application_on_the_existing_phone_screen() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT").unwrap().parse().unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let screen = runtime
        .invoke(
            "session.start",
            json!({"deviceId":id,"maxSize":640,"maxFps":15}),
        )
        .await
        .unwrap();
    let sid = screen["sessionId"].as_str().unwrap();
    let result = async {
        for action in ["down", "up"] {
            runtime.invoke("session.key", json!({"sessionId":sid,"keyCode":3,"action":action})).await?;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
        let before = inspector.shell("dumpsys activity activities", 1024 * 1024, OperationOptions::default()).await.unwrap();
        assert!(!String::from_utf8_lossy(&before.stdout).lines().any(|line| line.contains("topResumedActivity=") && line.contains("com.android.settings/")), "the fixture must start away from Settings");
        for package in ["+com.android.settings", "?Settings", "com.android.settings;id", ""] {
            let rejected = runtime.invoke("session.launch", json!({"sessionId":sid,"packageName":package})).await.unwrap_err();
            assert_eq!(rejected.code, "invalid_argument");
        }
        let mismatch = runtime.invoke("session.launch", json!({"sessionId":sid,"deviceId":"another-device","packageName":"com.android.settings"})).await.unwrap_err();
        assert_eq!(mismatch.code, "invalid_argument");
        let sent = runtime.invoke("session.launch", json!({"deviceId":id,"sessionId":sid,"packageName":"com.android.settings"})).await?;
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
        let sessions = runtime.invoke("session.list", json!({"deviceId":id})).await?;
        assert_eq!(sessions["sessions"].as_array().unwrap().len(), 1);
        assert_eq!(sessions["sessions"][0]["sessionId"], sid);
        assert!(sessions["sessions"][0]["packageName"].is_null());
        Ok::<(), interop_core::CoreError>(())
    }.await;
    runtime
        .invoke("session.stop", json!({"sessionId":sid}))
        .await
        .unwrap();
    runtime
        .invoke("devices.forget", json!({"deviceId":id}))
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
    let added = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let device = added["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let rejected = runtime
        .invoke(
            "session.start",
            json!({"deviceId":device,"packageName":"+com.android.settings"}),
        )
        .await
        .unwrap_err();
    assert_eq!(rejected.code, "invalid_argument");
    assert_eq!(rejected.details["launchOutcome"], "not_submitted");
    assert!(
        runtime
            .invoke("session.list", json!({"deviceId":device}))
            .await
            .unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    // A valid but absent package accepts the actual START_APP control write,
    // then the undecorated display has no content to generate a first frame.
    let missing = json!({"deviceId":device,"packageName":"dev.interop.nonexistent.a49"});
    let unknown = runtime
        .invoke("session.start", missing.clone())
        .await
        .unwrap_err();
    assert_eq!(unknown.code, "app_launch_unknown");
    assert_eq!(unknown.details["launchOutcome"], "unknown");
    assert_eq!(unknown.details["failureCode"], "encoder_start_failed");
    let unknown_id = unknown.details["sessionId"].as_str().unwrap();
    for _ in 0..2 {
        let listed = runtime
            .invoke("session.list", json!({"deviceId":device}))
            .await
            .unwrap();
        assert_eq!(listed["sessions"].as_array().unwrap().len(), 1);
        assert_eq!(listed["sessions"][0]["sessionId"], unknown_id);
        assert_eq!(listed["sessions"][0]["launchOutcome"], "unknown");
        let blocked = runtime
            .invoke("session.start", missing.clone())
            .await
            .unwrap_err();
        assert_eq!(blocked.code, "app_launch_unknown");
        assert_eq!(blocked.details["sessionId"], unknown_id);
    }
    // Resource admission is released even though the operation record remains.
    tokio::time::timeout(Duration::from_secs(6), async {
        loop {
            let activities = runtime.invoke("activities.list", json!({})).await.unwrap();
            let records = activities["activities"].as_array().unwrap();
            if !records.iter().any(|item| item["reserved"] == true) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("failed startup must release its capture reservation");
    runtime
        .invoke("session.stop", json!({"sessionId":unknown_id}))
        .await
        .unwrap();
    assert!(
        runtime
            .invoke("session.list", json!({"deviceId":device}))
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
    let opened = runtime
        .invoke("session.start", request.clone())
        .await
        .unwrap();
    let sid = opened["sessionId"].as_str().unwrap();
    assert_eq!(opened["encodedKeyFrameReady"], true);
    runtime
        .invoke(
            "session.stop",
            json!({"sessionId":sid,"keepLaunchRecord":true}),
        )
        .await
        .unwrap();
    let blocked = runtime.invoke("session.start", request).await.unwrap_err();
    assert_eq!(blocked.code, "app_launch_unknown");
    assert_eq!(blocked.details["sessionId"], sid);
    let primary = runtime
        .invoke(
            "session.start",
            json!({
                "deviceId":device,"maxSize":640,"maxFps":15
            }),
        )
        .await
        .unwrap();
    let primary_id = primary["sessionId"].as_str().unwrap();
    let replayed_on_primary = runtime
        .invoke(
            "session.launch",
            json!({
                "sessionId":primary_id,"packageName":"com.android.settings"
            }),
        )
        .await;
    runtime
        .invoke("session.stop", json!({"sessionId":primary_id}))
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
    let stopped = runtime
        .invoke("session.stop", json!({"sessionId":sid}))
        .await
        .unwrap();
    assert_eq!(stopped["applicationStopped"], false);
    runtime
        .invoke("devices.forget", json!({"deviceId":device}))
        .await
        .unwrap();
}
