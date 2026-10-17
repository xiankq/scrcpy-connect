use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};

#[tokio::test]
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn non_utf8_names_never_alias_an_operable_replacement_character_filename() {
    use interop_adb::{Client, ConnectOptions, Identity, OperationOptions, sync::RemotePath};
    let (directory, runtime, id, remote) = runtime().await;
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
    let mut sync = client.sync(OperationOptions::default()).await.unwrap();
    let invalid = [remote.as_bytes(), b"/\xff.txt"].concat();
    let valid = format!("{remote}/�.txt");
    for (path, contents) in [
        (&invalid[..], &b"invalid filename"[..]),
        (valid.as_bytes(), &b"preserve this file"[..]),
    ] {
        sync.push(
            &RemotePath::new(path).unwrap(),
            &mut std::io::Cursor::new(contents),
            0o600,
            0,
            1024,
        )
        .await
        .unwrap();
    }
    let listed = runtime
        .invoke("files.list", json!({"deviceId":id,"path":remote}))
        .await
        .unwrap();
    let entries = listed["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 2);
    let unsupported = entries.iter().find(|e| e["nameIsUtf8"] == false).unwrap();
    assert!(unsupported["path"].is_null());
    assert_eq!(unsupported["canManage"], false);
    assert!(
        runtime
            .invoke(
                "files.delete",
                json!({"deviceId":id,"paths":[unsupported["path"]]})
            )
            .await
            .is_err()
    );
    let mut pulled = Vec::new();
    sync.pull(&RemotePath::new(valid).unwrap(), &mut pulled, 1024)
        .await
        .unwrap();
    assert_eq!(pulled, b"preserve this file");
    runtime
        .invoke("files.delete", json!({"deviceId":id,"paths":[remote]}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

async fn runtime() -> (tempfile::TempDir, Arc<Runtime>, String, String) {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("INTEROP_CORE_TEST_ENDPOINT")
        .parse()
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(dir.path()).await.unwrap();
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
    let remote = format!("/data/local/tmp/interop-files-{}", uuid::Uuid::new_v4());
    runtime
        .invoke("files.mkdir", json!({"deviceId":id,"path":remote}))
        .await
        .unwrap();
    (dir, runtime, id, remote)
}

async fn settled(runtime: &Arc<Runtime>, id: &str) -> Value {
    tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            let task = runtime
                .invoke("transfers.get", json!({"transferId":id}))
                .await
                .unwrap();
            if !matches!(
                task["status"].as_str().unwrap(),
                "queued" | "running" | "finalizing" | "cancelling"
            ) {
                return task;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("transfer settled")
}

async fn status(runtime: &Arc<Runtime>, id: &str, wanted: &str) -> Value {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let task = runtime
                .invoke("transfers.get", json!({"transferId":id}))
                .await
                .unwrap();
            if task["status"] == wanted {
                return task;
            }
            assert!(
                matches!(
                    task["status"].as_str().unwrap(),
                    "queued" | "running" | "finalizing"
                ),
                "unexpected task {task}"
            );
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap()
}

async fn push(
    runtime: &Arc<Runtime>,
    id: &str,
    source: &std::path::Path,
    destination: &str,
) -> Value {
    let started = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":destination,"conflict":"replace"}),
        )
        .await
        .unwrap();
    let task = settled(runtime, started["transferId"].as_str().unwrap()).await;
    assert_eq!(task["status"], "completed", "{task}");
    task
}

#[tokio::test]
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn batch_conflict_policy_only_applies_to_later_items_in_the_same_transfer() {
    let (dir, runtime, id, remote) = runtime().await;
    let source = dir.path().join("source.bin");
    tokio::fs::write(&source, b"real Android batch contents")
        .await
        .unwrap();
    for name in ["a.bin", "b.bin"] {
        let result = runtime.invoke("files.push", json!({"deviceId":id,"source":source,"destination":format!("{remote}/{name}"),"conflict":"replace"})).await.unwrap();
        let task = settled(&runtime, result["transferId"].as_str().unwrap()).await;
        assert_eq!(task["status"], "completed", "{task}");
    }
    let batch = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"items":[
                {"source":source,"destination":format!("{remote}/a.bin")},
                {"source":source,"destination":format!("{remote}/b.bin")}
            ]}),
        )
        .await
        .unwrap();
    let ids = batch["transferIds"].as_array().unwrap();
    let first = settled(&runtime, ids[0].as_str().unwrap()).await;
    assert_eq!(first["status"], "conflict");
    assert_eq!(first["canResume"], false);
    assert_eq!(
        runtime
            .invoke("transfers.get", json!({"transferId":ids[1]}))
            .await
            .unwrap()["status"],
        "queued"
    );
    runtime
        .invoke(
            "transfers.resolve",
            json!({"transferId":ids[0],"policy":"skip","applyToAll":true}),
        )
        .await
        .unwrap();
    for transfer_id in ids {
        let task = settled(&runtime, transfer_id.as_str().unwrap()).await;
        assert_eq!(task["status"], "skipped");
        assert_eq!(task["batchId"], batch["batchId"]);
        assert_eq!(task["policy"], "skip");
    }
    let later = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":format!("{remote}/a.bin")}),
        )
        .await
        .unwrap();
    assert_eq!(
        settled(&runtime, later["transferId"].as_str().unwrap()).await["status"],
        "conflict"
    );
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
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn actual_push_pull_hash_atomic_conflict_rename_delete_and_preview_cache() {
    use sha2::{Digest, Sha256};
    let (dir, runtime, id, remote) = runtime().await;
    let bytes: Vec<u8> = (0..8 * 1024 * 1024).map(|n| (n % 251) as u8).collect();
    let source = dir.path().join("original.bin");
    tokio::fs::write(&source, &bytes).await.unwrap();
    let remote_file = format!("{remote}/payload.bin");
    push(&runtime, &id, &source, &remote_file).await;
    let destination = dir.path().join("received.bin");
    let pull = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":remote_file,"destination":destination}),
        )
        .await
        .unwrap();
    let pull_id = pull["transferId"].as_str().unwrap();
    status(&runtime, pull_id, "running").await;
    tokio::fs::write(&destination, b"concurrently created local contents")
        .await
        .unwrap();
    let conflict = settled(&runtime, pull_id).await;
    assert_eq!(conflict["status"], "conflict", "{conflict}");
    assert_eq!(
        tokio::fs::read(&destination).await.unwrap(),
        b"concurrently created local contents"
    );
    runtime
        .invoke(
            "transfers.resolve",
            json!({"transferId":pull_id,"policy":"keepBoth","applyToAll":false}),
        )
        .await
        .unwrap();
    let done = settled(&runtime, pull_id).await;
    assert_eq!(done["status"], "completed", "{done}");
    assert_eq!(
        done["saveMode"],
        if cfg!(any(target_os = "linux", target_os = "android")) {
            "atomicRenameNoReplace"
        } else {
            "atomicHardLink"
        }
    );
    let saved = tokio::fs::read(done["localPath"].as_str().unwrap())
        .await
        .unwrap();
    assert_eq!(Sha256::digest(&saved), Sha256::digest(&bytes));
    let (first, concurrent) = tokio::join!(
        runtime.invoke("media.preview", json!({"deviceId":id,"path":remote_file})),
        runtime.invoke("media.preview", json!({"deviceId":id,"path":remote_file}))
    );
    let first = first.unwrap();
    let concurrent = concurrent.unwrap();
    assert_ne!(
        first["cacheHit"], concurrent["cacheHit"],
        "one concurrent request downloads, the other reuses"
    );
    assert_eq!(first["localPath"], concurrent["localPath"]);
    let second = runtime
        .invoke("media.preview", json!({"deviceId":id,"path":remote_file}))
        .await
        .unwrap();
    assert_eq!(second["cacheHit"], true);
    assert_eq!(first["localPath"], second["localPath"]);
    tokio::fs::write(first["localPath"].as_str().unwrap(), vec![0u8; bytes.len()])
        .await
        .unwrap();
    let repaired = runtime
        .invoke("media.preview", json!({"deviceId":id,"path":remote_file}))
        .await
        .unwrap();
    assert_eq!(
        repaired["cacheHit"], false,
        "locally corrupted cache is not trusted"
    );
    assert_eq!(
        Sha256::digest(
            tokio::fs::read(repaired["localPath"].as_str().unwrap())
                .await
                .unwrap()
        ),
        Sha256::digest(&bytes)
    );
    tokio::fs::write(
        &source,
        b"different source size invalidates the cached original",
    )
    .await
    .unwrap();
    push(&runtime, &id, &source, &remote_file).await;
    let changed = runtime
        .invoke("media.preview", json!({"deviceId":id,"path":remote_file}))
        .await
        .unwrap();
    assert_eq!(changed["cacheHit"], false);
    assert_eq!(changed["localPath"], first["localPath"]);
    assert_eq!(
        tokio::fs::read(changed["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        b"different source size invalidates the cached original"
    );
    let conflicting = format!("{remote}/exists.bin");
    push(&runtime, &id, &source, &conflicting).await;
    let error = runtime
        .invoke(
            "files.rename",
            json!({"deviceId":id,"path":remote_file,"name":"exists.bin"}),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, "conflict");
    let renamed = runtime
        .invoke(
            "files.rename",
            json!({"deviceId":id,"path":remote_file,"name":"renamed.bin"}),
        )
        .await
        .unwrap();
    assert_eq!(renamed["status"], "completed");
    let entries = runtime
        .invoke("files.list", json!({"deviceId":id,"path":remote}))
        .await
        .unwrap();
    assert!(
        !entries["entries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["name"] == "payload.bin")
    );
    assert!(
        entries["entries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["name"] == "renamed.bin")
    );
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
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn cancellation_never_claims_completion_and_restart_is_explicit_and_from_zero() {
    let (dir, runtime, id, remote) = runtime().await;
    let source = dir.path().join("large.bin");
    let mut file = tokio::fs::File::create(&source).await.unwrap();
    tokio::io::AsyncWriteExt::write_all(&mut file, &vec![0x5a; 32 * 1024 * 1024])
        .await
        .unwrap();
    drop(file);
    let remote_file = format!("{remote}/large.bin");
    push(&runtime, &id, &source, &remote_file).await;
    let destination = dir.path().join("cancelled.bin");
    let started = runtime
        .invoke(
            "files.pull",
            json!({"deviceId":id,"path":remote_file,"destination":destination}),
        )
        .await
        .unwrap();
    let transfer_id = started["transferId"].as_str().unwrap();
    status(&runtime, transfer_id, "running").await;
    runtime
        .invoke("transfers.cancel", json!({"transferId":transfer_id}))
        .await
        .unwrap();
    let cancelled = settled(&runtime, transfer_id).await;
    assert_eq!(cancelled["status"], "cancelled", "{cancelled}");
    assert_eq!(cancelled["canResume"], false);
    assert_eq!(cancelled["canRestart"], true);
    assert!(!tokio::fs::try_exists(&destination).await.unwrap());
    assert_eq!(
        runtime
            .invoke("transfers.resume", json!({"transferId":transfer_id}))
            .await
            .unwrap_err()
            .code,
        "resume_unavailable"
    );
    runtime
        .invoke(
            "transfers.resume",
            json!({"transferId":transfer_id,"restart":true}),
        )
        .await
        .unwrap();
    let completed = settled(&runtime, transfer_id).await;
    assert_eq!(completed["status"], "completed", "{completed}");
    assert_eq!(completed["transferred"], 32 * 1024 * 1024);
    assert_eq!(completed["generation"], 1);
    assert_eq!(
        tokio::fs::metadata(&destination).await.unwrap().len(),
        32 * 1024 * 1024
    );
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
#[ignore = "requires an actual Android raw ADB endpoint with emulated shared storage"]
async fn shared_storage_publishes_atomically_without_hard_links() {
    let (dir, runtime, id, remote) = runtime().await;
    let shared = format!("/sdcard/Download/interop-files-{}", uuid::Uuid::new_v4());
    runtime
        .invoke("files.mkdir", json!({"deviceId":id,"path":shared}))
        .await
        .unwrap();
    let source = dir.path().join("shared.bin");
    tokio::fs::write(&source, b"exclusive shared storage contents")
        .await
        .unwrap();
    let destination = format!("{shared}/中文 ' 文件.bin");
    let started = runtime
        .invoke(
            "files.push",
            json!({"deviceId":id,"source":source,"destination":destination}),
        )
        .await
        .unwrap();
    let task = settled(&runtime, started["transferId"].as_str().unwrap()).await;
    assert_eq!(task["status"], "completed", "{task}");
    assert_eq!(task["saveMode"], "atomicRename", "target fixture is FUSE");
    let renamed = runtime
        .invoke(
            "files.rename",
            json!({"deviceId":id,"path":destination,"name":"renamed.bin"}),
        )
        .await
        .unwrap();
    assert_eq!(renamed["status"], "completed");
    assert_eq!(renamed["atomic"], true);
    let preview = runtime
        .invoke(
            "media.preview",
            json!({"deviceId":id,"path":format!("{shared}/renamed.bin")}),
        )
        .await
        .unwrap();
    assert_eq!(
        tokio::fs::read(preview["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        b"exclusive shared storage contents"
    );
    runtime
        .invoke(
            "files.delete",
            json!({"deviceId":id,"paths":[shared,remote]}),
        )
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}
