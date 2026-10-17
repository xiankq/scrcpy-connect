use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn file_search_rejects_an_unbounded_empty_query_before_connecting() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let error = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":"offline","path":"/sdcard","query":"","filter":"all"}),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "invalid_argument");
}

#[tokio::test]
async fn file_search_validates_unsafe_inputs_and_never_invents_unknown_snapshots() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for params in [
        json!({"deviceId":"offline","path":"relative","query":"report","filter":"all"}),
        json!({"deviceId":"offline","path":"/sdcard","query":"report\u{0}","filter":"all"}),
        json!({"deviceId":"offline","path":"/sdcard","query":"a".repeat(257),"filter":"all"}),
        json!({"deviceId":"offline","path":"/sdcard","query":"report","filter":"invalid"}),
    ] {
        let error = runtime
            .invoke("files.search.start", params)
            .await
            .unwrap_err();
        assert!(matches!(
            error.code.as_str(),
            "invalid_path" | "invalid_argument"
        ));
    }
    assert_eq!(
        runtime
            .invoke(
                "files.search.start",
                json!({"deviceId":"offline","path":"/sdcard","query":"","filter":"images"})
            )
            .await
            .unwrap_err()
            .code,
        "disconnected"
    );
    for command in ["files.search.get", "files.search.cancel"] {
        assert_eq!(
            runtime
                .invoke(command, json!({"deviceId":"offline","searchId":"missing"}))
                .await
                .unwrap_err()
                .code,
            "search_not_found"
        );
    }
}
