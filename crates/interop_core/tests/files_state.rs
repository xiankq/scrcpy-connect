use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn interrupted_save_requires_target_verification_and_never_offers_byte_resume() {
    let directory = tempfile::tempdir().unwrap();
    let tasks: [serde_json::Value; 2] = std::array::from_fn(|index| {
        json!({
            "id":format!("transfer-{index}"),"deviceId":"device","direction":"pull",
            "source":"/sdcard/source.bin","destination":"/tmp/destination.bin","name":"source.bin",
            "status":if index==0 {"running"}else{"finalizing"},"transferred":12,"total":100,
            "error":null,"policy":"ask","createdAt":1
        })
    });
    tokio::fs::write(
        directory.path().join("transfers.json"),
        serde_json::to_vec(&tasks).unwrap(),
    )
    .await
    .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let running = runtime
        .invoke("transfers.get", json!({"transferId":"transfer-0"}))
        .await
        .unwrap();
    assert_eq!(running["status"], "interrupted");
    assert_eq!(running["canResume"], false);
    assert_eq!(running["canRestart"], true);
    assert_eq!(
        runtime
            .invoke("transfers.resume", json!({"transferId":"transfer-0"}))
            .await
            .unwrap_err()
            .code,
        "resume_unavailable"
    );
    let saving = runtime
        .invoke("transfers.get", json!({"transferId":"transfer-1"}))
        .await
        .unwrap();
    assert_eq!(saving["status"], "interrupted");
    assert_eq!(saving["canResume"], false);
    assert_eq!(saving["canRestart"], false);
    assert_eq!(saving["errorCode"], "result_unknown");
    assert_eq!(saving["partialDestinationPossible"], true);
    assert_eq!(
        runtime
            .invoke(
                "transfers.resume",
                json!({"transferId":"transfer-1","restart":true})
            )
            .await
            .unwrap_err()
            .code,
        "invalid_state"
    );
}

#[tokio::test]
async fn restored_directory_batches_keep_item_results_and_cancel_only_the_selected_batch() {
    let directory = tempfile::tempdir().unwrap();
    let tasks = vec![
        json!({"id":"root","deviceId":"device","direction":"pull","source":"/source","destination":"/target","name":"source","status":"completed","transferred":0,"total":0,"error":null,"policy":"ask","createdAt":1,"batchId":"tree","itemIndex":0,"kind":"directory","treeVerified":true}),
        json!({"id":"file","deviceId":"device","direction":"pull","source":"/source/file","destination":"/target/file","name":"file","status":"conflict","transferred":0,"total":9,"error":null,"policy":"ask","createdAt":1,"batchId":"tree","itemIndex":1,"kind":"file","parentId":"root"}),
        json!({"id":"link","deviceId":"device","direction":"pull","source":"/source/link","destination":"/target/link","name":"link","status":"skipped","transferred":0,"total":null,"error":"link skipped","policy":"ask","createdAt":1,"batchId":"tree","itemIndex":2,"kind":"symlink","parentId":"root"}),
        json!({"id":"unrelated","deviceId":"device","direction":"push","source":"/a","destination":"/b","name":"a","status":"conflict","transferred":0,"total":1,"error":null,"policy":"ask","createdAt":1,"batchId":"other","itemIndex":0}),
    ];
    tokio::fs::write(
        directory.path().join("transfers.json"),
        serde_json::to_vec(&tasks).unwrap(),
    )
    .await
    .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let before = runtime.invoke("transfers.list", json!({})).await.unwrap();
    let tree = before["batches"]
        .as_array()
        .unwrap()
        .iter()
        .find(|batch| batch["batchId"] == "tree")
        .unwrap();
    assert_eq!(tree["status"], "conflict");
    assert_eq!(tree["fileCount"], 1);
    assert_eq!(tree["directoryCount"], 1);
    assert_eq!(tree["skipped"], 1);
    assert_eq!(tree["canCancel"], true);
    runtime
        .invoke("transfers.cancel", json!({"batchId":"tree"}))
        .await
        .unwrap();
    let file = runtime
        .invoke("transfers.get", json!({"transferId":"file"}))
        .await
        .unwrap();
    assert_eq!(file["status"], "cancelled");
    assert_eq!(file["canResume"], false);
    assert_eq!(file["batch"]["batchId"], "tree");
    assert_eq!(file["batch"]["itemCount"], 3);
    assert_eq!(file["batch"]["cancelled"], 1);
    assert_eq!(file["batch"]["skipped"], 1);
    assert_eq!(file["batch"]["canCancel"], false);
    assert_eq!(file["batch"]["status"], "cancelled");
    assert_eq!(
        file["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|item| item["id"].as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["root", "file", "link"]
    );
    assert_eq!(
        runtime
            .invoke("transfers.get", json!({"transferId":"root"}))
            .await
            .unwrap()["status"],
        "completed"
    );
    assert_eq!(
        runtime
            .invoke("transfers.get", json!({"transferId":"link"}))
            .await
            .unwrap()["status"],
        "skipped"
    );
    assert_eq!(
        runtime
            .invoke("transfers.get", json!({"transferId":"unrelated"}))
            .await
            .unwrap()["status"],
        "conflict"
    );
}

#[tokio::test]
async fn unverified_directory_snapshots_restore_as_interrupted_private_cache() {
    let directory = tempfile::tempdir().unwrap();
    let task = json!({"id":"directory","deviceId":"device","direction":"pull","source":"/source","destination":"/private/cache/staging","name":"source","status":"completed","transferred":0,"total":0,"error":null,"policy":"ask","createdAt":1,"batchId":"batch","kind":"directory","treeVerified":false,"destinationScope":"privateCache"});
    tokio::fs::write(
        directory.path().join("transfers.json"),
        serde_json::to_vec(&vec![task]).unwrap(),
    )
    .await
    .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let task = runtime
        .invoke("transfers.get", json!({"transferId":"directory"}))
        .await
        .unwrap();
    assert_eq!(task["status"], "interrupted");
    assert_eq!(task["destinationScope"], "privateCache");
    assert_eq!(task["canResume"], false);
    let listed = runtime.invoke("transfers.list", json!({})).await.unwrap();
    assert_eq!(listed["batches"][0]["status"], "interrupted");
    assert_eq!(listed["batches"][0]["destinationScope"], "privateCache");
}
