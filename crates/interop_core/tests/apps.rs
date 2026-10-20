use interop_core::Runtime;
use serde_json::{Value, json};

#[tokio::test]
async fn app_queries_require_real_connection_and_reject_invalid_arguments() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for filter in [json!("recent"), json!(true), Value::Null] {
        let error = runtime
            .invoke("apps.list", json!({"deviceId":"absent","filter":filter}))
            .await
            .unwrap_err();
        assert_eq!(error.code, "invalid_argument");
    }
    for package in [
        "",
        "bad/name",
        "com..app",
        "com.example;id",
        &"a".repeat(256),
    ] {
        let error = runtime
            .invoke(
                "apps.icon",
                json!({"deviceId":"absent","packageName":package}),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "invalid_argument");
    }
    for (command, params) in [
        ("apps.list", json!({"deviceId":"absent","filter":"running"})),
        (
            "apps.icon",
            json!({"deviceId":"absent","packageName":"com.android.settings"}),
        ),
    ] {
        let error = runtime.invoke(command, params).await.unwrap_err();
        assert_eq!(error.code, "disconnected");
    }
    assert!(
        runtime.invoke("session.list", json!({})).await.unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}
