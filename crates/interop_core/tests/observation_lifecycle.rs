use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn observation_intent_survives_restart_and_queries_never_restart_a_stopped_observer() {
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
    let initial = runtime
        .invoke("observation.status", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(initial["wanted"], true);
    assert_eq!(initial["phase"], "waiting_connection");
    assert_eq!(initial["notifications"]["status"], "unknown");
    assert_eq!(initial["notifications"]["live"], false);
    assert!(
        initial["notifications"]["notifications"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let stopped = runtime
        .invoke("observation.stop", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(stopped["wanted"], false);
    assert_eq!(stopped["phase"], "stopped");
    for command in ["notifications.list", "calls.list"] {
        let result = runtime
            .invoke(command, json!({"deviceId":id,"allowStart":false}))
            .await
            .unwrap();
        assert_eq!(result["live"], false);
    }
    let restored = Runtime::initialize(directory.path()).await.unwrap();
    let status = restored
        .invoke("observation.status", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(status["wanted"], false);
    assert_eq!(status["phase"], "stopped");
    let list = restored
        .invoke("observation.list", json!({}))
        .await
        .unwrap();
    assert_eq!(list["observations"], json!([status.clone()]));
    assert_eq!(
        restored.invoke("state.snapshot", json!({})).await.unwrap()["observations"],
        list["observations"]
    );
    let started = restored
        .invoke("observation.start", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(started["wanted"], true);
    assert_eq!(started["phase"], "waiting_connection");
    let activities = restored.invoke("activities.list", json!({})).await.unwrap();
    assert!(
        activities["activities"]
            .as_array()
            .unwrap()
            .iter()
            .any(|activity| activity["id"] == format!("observation:{id}"))
    );
    restored
        .invoke(
            "activities.stop",
            json!({"activityId":format!("observation:{id}")}),
        )
        .await
        .unwrap();
    assert_eq!(
        restored
            .invoke("observation.status", json!({"deviceId":id}))
            .await
            .unwrap()["wanted"],
        false
    );
    while let Ok(event) = events.try_recv() {
        assert_ne!(event["type"], "companion.starting");
    }
}
