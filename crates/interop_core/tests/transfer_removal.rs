use interop_core::Runtime;
use serde_json::{Value, json};

fn task(id: &str, batch: &str, status: &str, destination: &str) -> Value {
    json!({"id":id,"deviceId":"device","direction":"pull","source":"/source",
        "destination":destination,"name":id,"status":status,"transferred":4,"total":4,
        "error":null,"policy":"ask","createdAt":1,"batchId":batch})
}

async fn seeded(root: &std::path::Path, tasks: Vec<Value>) -> std::sync::Arc<Runtime> {
    tokio::fs::write(
        root.join("transfers.json"),
        serde_json::to_vec(&tasks).unwrap(),
    )
    .await
    .unwrap();
    Runtime::initialize(root).await.unwrap()
}

#[tokio::test]
async fn removing_history_is_durable_and_never_deletes_completed_files() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("saved.txt");
    tokio::fs::write(&path, b"saved").await.unwrap();
    let runtime = seeded(
        directory.path(),
        vec![
            task("one", "selected", "completed", path.to_str().unwrap()),
            task("two", "selected", "failed", path.to_str().unwrap()),
            task("other", "other", "completed", path.to_str().unwrap()),
        ],
    )
    .await;
    let removed = runtime
        .invoke("transfers.remove", json!({"batchId":"selected"}))
        .await
        .unwrap();
    assert_eq!(removed["filesRemoved"], false);
    assert_eq!(removed["removedIds"].as_array().unwrap().len(), 2);
    assert_eq!(tokio::fs::read(&path).await.unwrap(), b"saved");
    drop(runtime);
    let restored = Runtime::initialize(directory.path()).await.unwrap();
    let listed = restored.invoke("transfers.list", json!({})).await.unwrap();
    assert_eq!(listed["transfers"].as_array().unwrap().len(), 1);
    assert_eq!(listed["transfers"][0]["id"], "other");
}

#[tokio::test]
async fn active_batch_cannot_be_forgotten_until_cancellation_has_finished() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = seeded(
        directory.path(),
        vec![
            task("done", "batch", "completed", "/not-touched"),
            task("waiting", "batch", "conflict", "/not-touched"),
        ],
    )
    .await;
    assert_eq!(
        runtime
            .invoke("transfers.remove", json!({"transferId":"done"}))
            .await
            .unwrap_err()
            .code,
        "transfer_active"
    );
    runtime
        .invoke("transfers.cancel", json!({"batchId":"batch"}))
        .await
        .unwrap();
    runtime
        .invoke("transfers.remove", json!({"batchId":"batch"}))
        .await
        .unwrap();
    assert_eq!(
        runtime.invoke("transfers.list", json!({})).await.unwrap()["transfers"],
        json!([])
    );
}

#[tokio::test]
async fn removing_a_directory_includes_descendants_but_preserves_other_records() {
    let directory = tempfile::tempdir().unwrap();
    let mut parent = task("root", "batch", "completed", "/not-touched");
    parent["kind"] = json!("directory");
    parent["treeVerified"] = json!(true);
    let mut child = task("child", "batch", "completed", "/not-touched/child");
    child["parentId"] = json!("root");
    let runtime = seeded(
        directory.path(),
        vec![
            parent,
            child,
            task("other", "batch", "completed", "/elsewhere"),
        ],
    )
    .await;
    runtime
        .invoke("transfers.remove", json!({"transferId":"root"}))
        .await
        .unwrap();
    let listed = runtime.invoke("transfers.list", json!({})).await.unwrap();
    assert_eq!(listed["transfers"].as_array().unwrap().len(), 1);
    assert_eq!(listed["transfers"][0]["id"], "other");
}

#[tokio::test]
async fn persistence_failure_does_not_make_records_disappear_from_memory() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = seeded(
        directory.path(),
        vec![task("one", "batch", "completed", "/not-touched")],
    )
    .await;
    let checkpoint = directory.path().join("transfers.json");
    tokio::fs::remove_file(&checkpoint).await.unwrap();
    tokio::fs::create_dir(&checkpoint).await.unwrap();
    assert_eq!(
        runtime
            .invoke("transfers.remove", json!({"batchId":"batch"}))
            .await
            .unwrap_err()
            .code,
        "persistence_failed"
    );
    assert_eq!(
        runtime.invoke("transfers.list", json!({})).await.unwrap()["transfers"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn removal_rejects_ambiguous_or_missing_targets() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for params in [json!({}), json!({"transferId":"a","batchId":"b"})] {
        assert_eq!(
            runtime
                .invoke("transfers.remove", params)
                .await
                .unwrap_err()
                .code,
            "invalid_argument"
        );
    }
    assert_eq!(
        runtime
            .invoke("transfers.remove", json!({"batchId":"missing"}))
            .await
            .unwrap_err()
            .code,
        "not_found"
    );
}
