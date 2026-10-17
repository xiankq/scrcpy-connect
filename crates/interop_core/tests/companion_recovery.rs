use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn recovery_queries_do_not_start_an_observer_or_require_a_connection() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let id = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":9}))
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    let mut events = runtime.subscribe();

    for (command, collection) in [
        ("notifications.list", "notifications"),
        ("calls.list", "calls"),
    ] {
        let result = runtime
            .invoke(command, json!({"deviceId":id,"allowStart":false}))
            .await
            .unwrap();
        assert_eq!(result["deviceId"], id);
        assert_eq!(result["status"], "unknown");
        assert_eq!(result["live"], false);
        assert_eq!(result[collection], json!([]));
    }
    for command in ["clipboard.get", "notifications.dismiss"] {
        let error = runtime
            .invoke(command, json!({"deviceId":id,"allowStart":false}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "observation_required");
    }
    assert!(
        events.try_recv().is_err(),
        "recovery must not start a helper"
    );
    let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
    assert_eq!(
        snapshot["companions"][0]["state"]["notifications"]["live"],
        false
    );
    // An explicit user request preserves the existing connection requirement.
    assert_eq!(
        runtime
            .invoke(
                "notifications.list",
                json!({"deviceId":id,"allowStart":true})
            )
            .await
            .unwrap_err()
            .code,
        "disconnected"
    );
}
