use interop_core::{CoreError, CoreResult};
use serde_json::json;

#[path = "../src/transfer_store.rs"]
mod transfer_store;

#[tokio::test]
async fn durable_task_changes_survive_reopen_without_rewriting_untouched_tasks() {
    let root = tempfile::tempdir().unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    store
        .persist_one("first", &json!({"id":"first","status":"queued"}))
        .await
        .unwrap();
    store
        .persist_one("second", &json!({"id":"second","status":"running"}))
        .await
        .unwrap();
    store
        .persist_one("first", &json!({"id":"first","status":"finalizing"}))
        .await
        .unwrap();
    drop(store);
    let reopened = transfer_store::TransferStore::open(root.path()).unwrap();
    let tasks = reopened.snapshot();
    assert!(
        tasks
            .iter()
            .any(|task| task["id"] == "first" && task["status"] == "finalizing")
    );
    assert!(
        tasks
            .iter()
            .any(|task| task["id"] == "second" && task["status"] == "running")
    );
}

#[tokio::test]
async fn legacy_tasks_migrate_and_a_durable_finalizing_save_cannot_restart_after_crash() {
    let root = tempfile::tempdir().unwrap();
    let task = json!({"id":"save","deviceId":"offline","direction":"push","source":"/source",
        "destination":"/target","name":"source","status":"running","transferred":12,"total":12,
        "error":null,"policy":"ask","createdAt":1});
    std::fs::write(
        root.path().join("transfers.json"),
        serde_json::to_vec(&vec![task.clone()]).unwrap(),
    )
    .unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    let mut finalizing = task;
    finalizing["status"] = json!("finalizing");
    store.persist_one("save", &finalizing).await.unwrap();
    drop(store);
    let runtime = interop_core::Runtime::initialize(root.path())
        .await
        .unwrap();
    let restored = runtime
        .invoke("transfers.get", json!({"transferId":"save"}))
        .await
        .unwrap();
    assert_eq!(restored["errorCode"], "result_unknown");
    assert_eq!(restored["canRestart"], false);
}

#[tokio::test]
async fn repeated_or_missing_log_sequences_fail_closed() {
    for duplicate in [true, false] {
        let root = tempfile::tempdir().unwrap();
        let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
        store
            .persist_one("save", &json!({"id":"save","status":"running"}))
            .await
            .unwrap();
        store
            .persist_one("save", &json!({"id":"save","status":"finalizing"}))
            .await
            .unwrap();
        drop(store);
        let path = root.path().join("transfers.journal");
        let bytes = std::fs::read(&path).unwrap();
        let records: Vec<_> = bytes.split_inclusive(|byte| *byte == b'\n').collect();
        let damaged = if duplicate {
            [bytes.as_slice(), records[1]].concat()
        } else {
            records[1].to_vec()
        };
        std::fs::write(path, damaged).unwrap();
        assert!(
            transfer_store::TransferStore::open(root.path()).is_err(),
            "an ambiguous save must never restore as restartable"
        );
    }
}

#[tokio::test]
async fn frequent_changes_keep_the_journal_bounded_and_preserve_the_latest_save() {
    let root = tempfile::tempdir().unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    for revision in 0..300 {
        store
            .persist_one(
                "save",
                &json!({"id":"save","revision":revision,"source":"s".repeat(2048)}),
            )
            .await
            .unwrap();
    }
    drop(store);
    assert!(
        std::fs::metadata(root.path().join("transfers.journal"))
            .unwrap()
            .len()
            < 128 * 1024,
        "retained deltas must be compacted instead of growing with every save"
    );
    let reopened = transfer_store::TransferStore::open(root.path()).unwrap();
    assert_eq!(reopened.snapshot()[0]["revision"], 299);
}

#[tokio::test]
async fn a_checkpoint_installed_before_log_truncation_never_resurrects_removed_tasks() {
    let root = tempfile::tempdir().unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    store
        .persist_one("save", &json!({"id":"save","status":"finalizing"}))
        .await
        .unwrap();
    let finalizing_log = std::fs::read(root.path().join("transfers.journal")).unwrap();
    store
        .persist_all(&std::collections::HashMap::<String, serde_json::Value>::new())
        .await
        .unwrap();
    let deletion_log = std::fs::read(root.path().join("transfers.journal")).unwrap();
    drop(store);
    // Crash after installing the new checkpoint but before clearing the old
    // log: both old upserts and the durable removal remain in that old log.
    std::fs::write(
        root.path().join("transfers.json"),
        br#"{"version":1,"sequence":2,"transfers":[]}"#,
    )
    .unwrap();
    std::fs::write(root.path().join("transfers.journal"), deletion_log).unwrap();
    let mut reopened = transfer_store::TransferStore::open(root.path()).unwrap();
    assert!(reopened.snapshot().is_empty());
    reopened
        .persist_one("new", &json!({"id":"new","status":"queued"}))
        .await
        .unwrap();
    drop(reopened);
    assert_eq!(
        transfer_store::TransferStore::open(root.path())
            .unwrap()
            .snapshot()[0]["id"],
        "new"
    );
    // An even older, otherwise valid pre-checkpoint journal is harmless too.
    std::fs::write(root.path().join("transfers.journal"), finalizing_log).unwrap();
    let mut reopened = transfer_store::TransferStore::open(root.path()).unwrap();
    assert!(reopened.snapshot().is_empty());
    reopened
        .persist_one(
            "after-old-log",
            &json!({"id":"after-old-log","status":"queued"}),
        )
        .await
        .unwrap();
    drop(reopened);
    assert_eq!(
        transfer_store::TransferStore::open(root.path())
            .unwrap()
            .snapshot()[0]["id"],
        "after-old-log"
    );
}

#[tokio::test]
async fn a_torn_tail_never_silently_forgets_an_uncertain_commit() {
    for tail in [b"{".as_slice(), br#"{"version":1,"sequence":2}"#.as_slice()] {
        let root = tempfile::tempdir().unwrap();
        let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
        store
            .persist_one("save", &json!({"id":"save","status":"finalizing"}))
            .await
            .unwrap();
        drop(store);
        let path = root.path().join("transfers.journal");
        let mut bytes = std::fs::read(&path).unwrap();
        bytes.extend_from_slice(tail);
        std::fs::write(path, bytes).unwrap();
        assert!(transfer_store::TransferStore::open(root.path()).is_err());
    }
}

#[tokio::test]
async fn an_uncertain_append_cannot_be_reused_after_the_filesystem_is_repaired() {
    let root = tempfile::tempdir().unwrap();
    // The failure is introduced after loading, at the actual append boundary.
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    std::fs::create_dir(root.path().join("transfers.journal")).unwrap();
    assert!(
        store
            .persist_one("save", &json!({"id":"save","status":"finalizing"}))
            .await
            .is_err()
    );
    std::fs::remove_dir(root.path().join("transfers.journal")).unwrap();
    assert!(
        store
            .persist_one("save", &json!({"id":"save","status":"running"}))
            .await
            .is_err()
    );
    let mut reopened = transfer_store::TransferStore::open(root.path()).unwrap();
    reopened
        .persist_one("save", &json!({"id":"save","status":"running"}))
        .await
        .unwrap();
}

#[tokio::test]
async fn committing_one_task_adds_only_that_tasks_bytes_with_a_large_history() {
    let root = tempfile::tempdir().unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    let history: std::collections::HashMap<_, _> = (0..1000)
        .map(|index| (format!("task-{index}"), json!({"id":format!("task-{index}"),"status":"completed","source":"s".repeat(2048)})))
        .collect();
    store.persist_all(&history).await.unwrap();
    let checkpoint = std::fs::read(root.path().join("transfers.json")).unwrap();
    store
        .persist_one(
            "task-0",
            &json!({"id":"task-0","status":"finalizing","source":"s".repeat(2048)}),
        )
        .await
        .unwrap();
    assert!(
        std::fs::metadata(root.path().join("transfers.journal"))
            .unwrap()
            .len()
            < 8192
    );
    assert_eq!(
        std::fs::read(root.path().join("transfers.json")).unwrap(),
        checkpoint
    );
    drop(store);
    let tasks = transfer_store::TransferStore::open(root.path())
        .unwrap()
        .snapshot();
    assert_eq!(tasks.len(), 1000);
    assert_eq!(
        tasks.iter().find(|task| task["id"] == "task-0").unwrap()["status"],
        "finalizing"
    );
}

#[tokio::test]
async fn an_older_attempt_cannot_replace_the_new_attempts_commit_receipt() {
    let root = tempfile::tempdir().unwrap();
    let mut store = transfer_store::TransferStore::open(root.path()).unwrap();
    store
        .persist_one(
            "save",
            &json!({"id":"save","generation":2,"status":"finalizing"}),
        )
        .await
        .unwrap();
    assert!(
        store
            .persist_one(
                "save",
                &json!({"id":"save","generation":1,"status":"running"})
            )
            .await
            .is_err()
    );
    drop(store);
    let task = transfer_store::TransferStore::open(root.path())
        .unwrap()
        .snapshot()
        .remove(0);
    assert_eq!(task["generation"], 2);
    assert_eq!(task["status"], "finalizing");
}
