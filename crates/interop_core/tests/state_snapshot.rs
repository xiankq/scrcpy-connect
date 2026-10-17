use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn snapshot_recovers_current_state_with_an_event_fence_and_no_new_activities() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut events = runtime.subscribe();
    runtime
        .invoke("settings.update", json!({"appearance":"dark"}))
        .await
        .unwrap();
    let before = events.recv().await.unwrap();
    let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
    assert_eq!(snapshot["settings"]["appearance"], "dark");
    let watermark = snapshot["sequence"].as_u64().unwrap();
    assert!(watermark > 0);
    assert!(before["sequence"].as_u64().unwrap() <= watermark);
    for collection in [
        "devices",
        "sessions",
        "sources",
        "transfers",
        "activities",
        "shares",
        "companions",
    ] {
        assert_eq!(snapshot[collection], json!([]), "{collection}");
    }
    assert!(
        events.try_recv().is_err(),
        "Reading state must not start or publish an activity"
    );
    assert!(!snapshot.to_string().contains("PRIVATE KEY"));
    runtime
        .invoke("settings.update", json!({"appearance":"light"}))
        .await
        .unwrap();
    let after = events.recv().await.unwrap();
    assert!(after["sequence"].as_u64().unwrap() > watermark);
    assert_eq!(
        runtime.invoke("state.snapshot", json!({})).await.unwrap()["settings"]["appearance"],
        "light"
    );
}

#[tokio::test]
async fn a_consumed_share_waiting_in_the_forward_queue_is_not_published_as_new() {
    let directory = tempfile::tempdir().unwrap();
    let cache = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke(
            "sharing.configure",
            json!({"absoluteRoot":cache.path().join("incoming"),"allowedCacheRoot":cache.path()}),
        )
        .await
        .unwrap();
    let mut events = runtime.subscribe();
    let id = uuid::Uuid::new_v4().to_string();
    runtime
        .invoke(
            "sharing.reject",
            json!({"shareId":id,"reason":"fixture provider rejected"}),
        )
        .await
        .unwrap();
    runtime
        .invoke("sharing.consume", json!({"shareId":id}))
        .await
        .unwrap();
    let event = tokio::time::timeout(std::time::Duration::from_secs(2), events.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        event["type"], "state.resync",
        "Never resurrect the old visible share receipt after it was consumed"
    );
    assert_eq!(
        runtime.invoke("state.snapshot", json!({})).await.unwrap()["shares"],
        json!([])
    );
}
