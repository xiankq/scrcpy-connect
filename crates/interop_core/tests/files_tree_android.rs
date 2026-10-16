use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};

async fn runtime() -> (tempfile::TempDir, Arc<Runtime>, String, String) {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("explicit actual endpoint")
        .parse()
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap().to_owned();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let remote = format!("/sdcard/Download/interop-tree-{}", uuid::Uuid::new_v4());
    runtime
        .invoke("files.mkdir", json!({"deviceId":id,"path":remote}))
        .await
        .unwrap();
    (directory, runtime, id, remote)
}
async fn batch(runtime: &Arc<Runtime>, id: &str) -> (Value, Vec<Value>) {
    tokio::time::timeout(Duration::from_secs(45), async {
        loop {
            let listed = runtime.invoke("transfers.list", json!({})).await.unwrap();
            let summary = listed["batches"]
                .as_array()
                .unwrap()
                .iter()
                .find(|batch| batch["batchId"] == id)
                .unwrap()
                .clone();
            let tasks = listed["transfers"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|task| task["batchId"] == id)
                .cloned()
                .collect::<Vec<_>>();
            if summary["status"] != "running" {
                return (summary, tasks);
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .expect("real directory batch completes")
}
async fn clean(runtime: &Arc<Runtime>, id: &str, remote: &str) {
    runtime
        .invoke("files.delete", json!({"deviceId":id,"paths":[remote]}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires actual Android adbd; uses only a unique target shared-storage fixture"]
async fn directory_push_pull_preserves_structure_empty_files_empty_directories_and_contents() {
    let (directory, runtime, id, remote) = runtime().await;
    let source = directory.path().join("source");
    tokio::fs::create_dir_all(source.join("nested/empty"))
        .await
        .unwrap();
    tokio::fs::write(source.join("zero"), []).await.unwrap();
    let contents = (0..300_000)
        .map(|index| (index % 251) as u8)
        .collect::<Vec<_>>();
    tokio::fs::write(source.join("nested/中文 payload.bin"), &contents)
        .await
        .unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(&source, source.join("cycle")).unwrap();
    let started = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":format!("{remote}/tree")}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, started["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["failed"], 0, "{tasks:?}");
    assert_eq!(summary["directoryCount"], 3);
    assert_eq!(summary["fileCount"], 2);
    assert!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "file")
            .all(|task| task["status"] == "completed" && task["saveMode"] == "atomicRename")
    );
    #[cfg(unix)]
    assert!(
        tasks
            .iter()
            .any(|task| task["kind"] == "symlink" && task["status"] == "skipped")
    );
    let destination = directory.path().join("received");
    let pulled = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":format!("{remote}/tree"),"destination":destination}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, pulled["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "completed", "{tasks:?}");
    assert!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "directory")
            .all(|task| task["canExport"] == true && task["treeComplete"] == true)
    );
    assert_eq!(
        tokio::fs::read(destination.join("nested/中文 payload.bin"))
            .await
            .unwrap(),
        contents
    );
    assert_eq!(
        tokio::fs::metadata(destination.join("zero"))
            .await
            .unwrap()
            .len(),
        0
    );
    assert!(destination.join("nested/empty").is_dir());
    assert!(!destination.join("cycle").exists());
    clean(&runtime, &id, &remote).await;
}

#[tokio::test]
#[ignore = "requires actual Android adbd; pauses a directory batch at a real file conflict"]
async fn directory_conflict_batch_cancel_source_changes_and_partial_failure_are_real() {
    let (directory, runtime, id, remote) = runtime().await;
    let source = directory.path().join("source");
    tokio::fs::create_dir(&source).await.unwrap();
    tokio::fs::write(source.join("a"), b"original a")
        .await
        .unwrap();
    tokio::fs::write(source.join("b"), b"original b")
        .await
        .unwrap();
    let destination = format!("{remote}/tree");
    let initial = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":destination}),
        )
        .await
        .unwrap();
    assert_eq!(
        batch(&runtime, initial["batchId"].as_str().unwrap())
            .await
            .0["status"],
        "completed"
    );
    let second = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":destination}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, second["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "conflict");
    let conflict = tasks
        .iter()
        .find(|task| task["status"] == "conflict")
        .unwrap();
    assert!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "directory")
            .all(|task| task["canExport"] == false && task["localPath"].is_null())
    );
    // Modify the other, still-queued file after the selection snapshot.
    let other = tasks
        .iter()
        .find(|task| task["kind"] == "file" && task["status"] == "queued")
        .unwrap();
    tokio::fs::write(
        other["source"].as_str().unwrap(),
        b"changed after selection, must not silently transfer",
    )
    .await
    .unwrap();
    tokio::fs::write(
        source.join("added-after-selection"),
        b"not part of the selected snapshot",
    )
    .await
    .unwrap();
    runtime
        .invoke(
            "transfers.resolve",
            json!({"transferId":conflict["id"],"policy":"skip","applyToAll":true}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, second["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "partialFailure", "{tasks:?}");
    assert!(
        tasks
            .iter()
            .any(|task| task["errorCode"] == "source_changed" && task["canRestart"] == false)
    );
    assert!(
        tasks
            .iter()
            .any(|task| task["kind"] == "directory" && task["errorCode"] == "source_changed"),
        "the changed directory snapshot must not report complete: {tasks:?}"
    );
    let cancelled = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":destination}),
        )
        .await
        .unwrap();
    assert_eq!(
        batch(&runtime, cancelled["batchId"].as_str().unwrap())
            .await
            .0["status"],
        "conflict"
    );
    runtime
        .invoke("transfers.cancel", json!({"batchId":cancelled["batchId"]}))
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, cancelled["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "cancelled");
    assert!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "file")
            .all(|task| task["status"] == "cancelled")
    );
    let output = directory.path().join("unchanged");
    let readback = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":destination,"destination":output}),
        )
        .await
        .unwrap();
    assert_eq!(
        batch(&runtime, readback["batchId"].as_str().unwrap())
            .await
            .0["status"],
        "completed"
    );
    assert_eq!(
        tokio::fs::read(output.join("a")).await.unwrap(),
        b"original a"
    );
    assert_eq!(
        tokio::fs::read(output.join("b")).await.unwrap(),
        b"original b"
    );
    let partial=runtime.invoke("files.push",json!({"deviceId":id,"items":[{"source":directory.path().join("missing"),"destination":format!("{remote}/missing")},{"source":source.join("a"),"destination":format!("{remote}/valid")}]})).await.unwrap();
    let (summary, tasks) = batch(&runtime, partial["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "partialFailure");
    assert_eq!(summary["completed"], 1, "{tasks:?}");
    assert_eq!(summary["failed"], 1);
    clean(&runtime, &id, &remote).await;
}

#[tokio::test]
#[ignore = "requires actual Android adbd; tests directory/file type conflict without destructive replacement"]
async fn directory_keep_both_remaps_descendants_without_overwriting_existing_file() {
    let (directory, runtime, id, remote) = runtime().await;
    let source = directory.path().join("source");
    tokio::fs::create_dir(&source).await.unwrap();
    tokio::fs::write(source.join("child"), b"child bytes")
        .await
        .unwrap();
    let existing = directory.path().join("existing");
    tokio::fs::write(&existing, b"preserve existing file")
        .await
        .unwrap();
    let target = format!("{remote}/occupied");
    let original = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":existing,"destination":target}),
        )
        .await
        .unwrap();
    assert_eq!(
        batch(&runtime, original["batchId"].as_str().unwrap())
            .await
            .0["status"],
        "completed"
    );
    let started = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":target}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, started["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "conflict");
    let root = tasks
        .iter()
        .find(|task| task["kind"] == "directory")
        .unwrap();
    runtime
        .invoke(
            "transfers.resolve",
            json!({"transferId":root["id"],"policy":"keepBoth"}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, started["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "completed", "{tasks:?}");
    let root = tasks
        .iter()
        .find(|task| task["kind"] == "directory")
        .unwrap();
    let child = tasks.iter().find(|task| task["kind"] == "file").unwrap();
    assert_ne!(root["destination"], target);
    assert_eq!(
        child["destination"],
        format!("{}/child", root["destination"].as_str().unwrap())
    );
    let saved = directory.path().join("original-readback");
    let readback = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":target,"destination":saved}),
        )
        .await
        .unwrap();
    assert_eq!(
        batch(&runtime, readback["batchId"].as_str().unwrap())
            .await
            .0["status"],
        "completed"
    );
    assert_eq!(
        tokio::fs::read(saved).await.unwrap(),
        b"preserve existing file"
    );
    clean(&runtime, &id, &remote).await;
}

#[tokio::test]
#[ignore = "requires actual Android adbd; private /data/local/tmp fixture supports real symlinks"]
async fn remote_directory_symlink_cycles_are_skipped_instead_of_downloaded() {
    use interop_adb::{Client, ConnectOptions, Identity, OperationOptions};
    let (directory, runtime, id, unused) = runtime().await;
    let endpoint = std::env::var("INTEROP_CORE_TEST_ENDPOINT").unwrap();
    let identity = Identity::from_pem(
        &tokio::fs::read_to_string(directory.path().join("host_identity.pem"))
            .await
            .unwrap(),
    )
    .unwrap();
    let client = Client::connect_tcp(
        endpoint,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let remote = format!("/data/local/tmp/interop-tree-link-{}", uuid::Uuid::new_v4());
    let fixture=client.shell(&format!("mkdir '{remote}' '{remote}/empty' && printf 'real remote contents' > '{remote}/payload' && ln -s . '{remote}/cycle'"),4096,OperationOptions::default()).await.unwrap();
    assert_eq!(fixture.exit_code, Some(0));
    let destination = directory.path().join("download");
    let started = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":remote,"destination":destination}),
        )
        .await
        .unwrap();
    let (summary, tasks) = batch(&runtime, started["batchId"].as_str().unwrap()).await;
    assert_eq!(summary["status"], "completedWithSkips", "{tasks:?}");
    assert!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "directory" && task["parentId"].is_null())
            .all(|task| task["canExport"] == false && task["canExportPartial"] == true)
    );
    assert_eq!(
        tasks
            .iter()
            .filter(|task| task["kind"] == "symlink" && task["status"] == "skipped")
            .count(),
        1
    );
    assert_eq!(
        tokio::fs::read(destination.join("payload")).await.unwrap(),
        b"real remote contents"
    );
    assert!(destination.join("empty").is_dir());
    assert!(!destination.join("cycle").exists());
    runtime
        .invoke("files.delete", json!({"deviceId":id,"paths":[remote]}))
        .await
        .unwrap();
    clean(&runtime, &id, &unused).await;
}
