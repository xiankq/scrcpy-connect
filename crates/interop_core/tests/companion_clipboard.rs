use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};

async fn add(runtime: &Arc<Runtime>, endpoint: std::net::SocketAddr) -> String {
    runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned()
}
async fn connected() -> (tempfile::TempDir, Arc<Runtime>, String) {
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("INTEROP_CORE_TEST_ENDPOINT")
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = add(&runtime, endpoint).await;
    // Exercise clipboard's own helper startup independently of observation.
    runtime
        .invoke("observation.stop", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    (root, runtime, id)
}
async fn assert_no_sessions(runtime: &Arc<Runtime>) {
    assert!(
        runtime.invoke("session.list", json!({})).await.unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn clipboard_requires_connection_and_validates_text_before_starting_companion() {
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = add(&runtime, "127.0.0.1:5555".parse().unwrap()).await;
    let error = runtime
        .invoke("clipboard.get", json!({"deviceId":id}))
        .await
        .unwrap_err();
    assert_eq!(error.code, "disconnected");
    for text in [Value::Null, json!("a".repeat(1 << 18))] {
        let error = runtime
            .invoke("clipboard.set", json!({"deviceId":id,"text":text}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "invalid_argument");
    }
    assert_no_sessions(&runtime).await;
}

#[tokio::test]
#[ignore = "requires actual authorized Android; temporarily changes target clipboard, no video session"]
async fn no_session_clipboard_round_trips_and_receives_another_companion_change() {
    let (_root, runtime, id) = connected().await;
    let (_other_root, other, other_id) = connected().await;
    assert_no_sessions(&runtime).await;
    assert_no_sessions(&other).await;
    let mut events = runtime.subscribe();
    let original = runtime
        .invoke("clipboard.get", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(original["source"], "companion");
    assert_eq!(original["available"], true);
    assert_eq!(original["live"], true);
    let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
    assert_eq!(snapshot["observations"][0]["wanted"], false);
    for section in ["notifications", "calls"] {
        assert_eq!(
            snapshot["companions"][0]["state"][section]["status"],
            "stopped"
        );
        assert_eq!(snapshot["companions"][0]["state"][section]["live"], false);
    }
    let marker = format!("interop 无会话 clipboard \n\"\\ {}", uuid::Uuid::new_v4());
    assert_eq!(
        runtime
            .invoke("clipboard.set", json!({"deviceId":id,"text":marker}))
            .await
            .unwrap()["applied"],
        true
    );
    assert_eq!(
        runtime
            .invoke("clipboard.get", json!({"deviceId":id}))
            .await
            .unwrap()["text"],
        marker
    );
    // JSON escaping must not bypass the transport bound or mutate the target.
    let oversized_json = "\0".repeat(200_000);
    assert_eq!(
        runtime
            .invoke(
                "clipboard.set",
                json!({"deviceId":id,"text":oversized_json})
            )
            .await
            .unwrap_err()
            .code,
        "invalid_argument"
    );
    assert_eq!(
        runtime
            .invoke("clipboard.get", json!({"deviceId":id}))
            .await
            .unwrap()["text"],
        marker
    );
    let external = format!("external clipboard {}", uuid::Uuid::new_v4());
    assert_eq!(
        other
            .invoke(
                "clipboard.set",
                json!({"deviceId":other_id,"text":external})
            )
            .await
            .unwrap()["applied"],
        true
    );
    let changed = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let event = events.recv().await.unwrap();
            if event["type"] == "clipboard.changed"
                && event["deviceId"] == id
                && event["data"]["text"] == external
            {
                break event;
            }
        }
    })
    .await
    .expect("real target Binder callback, not an echo of our own set");
    assert_eq!(changed["data"]["source"], "companion");
    // Clipboard access neither starts a screen nor creates a control session.
    assert_no_sessions(&runtime).await;
    assert_no_sessions(&other).await;
    runtime
        .invoke(
            "clipboard.set",
            json!({"deviceId":id,"text":original["text"]}),
        )
        .await
        .unwrap();
    other
        .invoke("devices.disconnect", json!({"deviceId":other_id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke("clipboard.get", json!({"deviceId":id}))
            .await
            .unwrap_err()
            .code,
        "disconnected"
    );
}

#[tokio::test]
#[ignore = "requires actual authorized Android; disconnects only this test's ADB connection"]
async fn disconnect_cancels_clipboard_companion_startup() {
    let (_root, runtime, id) = connected().await;
    let mut events = runtime.subscribe();
    let owner = runtime.clone();
    let device = id.clone();
    let startup = tokio::spawn(async move {
        owner
            .invoke("clipboard.get", json!({"deviceId":device}))
            .await
    });
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if events.recv().await.unwrap()["type"] == "companion.starting" {
                break;
            }
        }
    })
    .await
    .unwrap();
    tokio::time::timeout(
        Duration::from_secs(7),
        runtime.invoke("devices.disconnect", json!({"deviceId":id})),
    )
    .await
    .unwrap()
    .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_secs(2), startup)
            .await
            .unwrap()
            .unwrap()
            .is_err()
    );
    assert_eq!(
        runtime
            .invoke("device.info", json!({"deviceId":id}))
            .await
            .unwrap()["status"],
        "offline"
    );
    assert_no_sessions(&runtime).await;
}
