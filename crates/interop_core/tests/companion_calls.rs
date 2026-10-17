use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn opening_current_system_call_requires_live_observation_without_starting_a_helper() {
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
    let error = runtime
        .invoke("calls.open", json!({"deviceId":id}))
        .await
        .unwrap_err();
    assert_eq!(error.code, "observation_required");
    assert!(
        events.try_recv().is_err(),
        "opening must not start observation"
    );
    let snapshot = runtime.invoke("state.snapshot", json!({})).await.unwrap();
    assert_eq!(snapshot["observations"][0]["calls"]["live"], false);
}
