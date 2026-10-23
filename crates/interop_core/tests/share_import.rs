use interop_core::{
    CoreError,
    sharing::{ImportManager, Limits, Source},
};
use serde_json::{Value, json};
use std::{
    fs,
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use tempfile::TempDir;

fn id() -> String {
    uuid::Uuid::new_v4().to_string()
}
fn manager(cache: &TempDir, limits: Limits) -> Arc<ImportManager> {
    ImportManager::open(cache.path().join("incoming"), cache.path(), limits).unwrap()
}
fn command(manager: &ImportManager, command: &str, params: Value) -> Value {
    manager.command(command, &params).unwrap()
}
async fn finish(manager: &ImportManager, id: &str) -> Value {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let rows = command(manager, "sharing.pending", Value::Null);
            if let Some(batch) = rows["shares"]
                .as_array()
                .unwrap()
                .iter()
                .find(|b| b["shareId"] == id && b["status"] != "importing")
            {
                return batch.clone();
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("bounded import completion")
}
fn path_source(path: &Path) -> Source {
    Source {
        name: "中文 文件.bin".into(),
        fd: None,
        path: Some(path.into()),
        offset: 0,
        declared_length: None,
    }
}
async fn ready(manager: &Arc<ImportManager>, cache: &TempDir, bytes: &[u8]) -> (String, Value) {
    let share = id();
    let source = cache.path().join(format!("source-{share}"));
    fs::write(&source, bytes).unwrap();
    manager
        .import(
            &share,
            None,
            Some("application/octet-stream".into()),
            vec![path_source(&source)],
        )
        .unwrap();
    let result = finish(manager, &share).await;
    assert_eq!(result["status"], "ready", "{result}");
    (share, result)
}

#[tokio::test]
async fn real_path_import_is_bounded_async_and_preserves_unicode_and_bytes() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let bytes: Vec<_> = (0..200_000).map(|i| (i % 251) as u8).collect();
    let (_, batch) = ready(&manager, &cache, &bytes).await;
    assert_eq!(batch["files"][0]["name"], "中文 文件.bin");
    assert_eq!(
        fs::read(batch["files"][0]["localPath"].as_str().unwrap()).unwrap(),
        bytes
    );
}

#[tokio::test]
async fn consume_restart_unknown_and_failed_tasks_keep_exact_source_until_positive_completion() {
    let cache = TempDir::new().unwrap();
    let mut manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"durable source").await;
    let path = batch["files"][0]["localPath"].as_str().unwrap().to_string();
    let lease = command(&manager, "sharing.retain", json!({"shareId":share}));
    assert_eq!(
        command(&manager, "sharing.retain", json!({"shareId":share})),
        lease
    );
    command(&manager, "sharing.consume", json!({"shareId":share}));
    drop(manager);
    manager = ImportManager::open(
        cache.path().join("incoming"),
        cache.path(),
        Limits::default(),
    )
    .unwrap();
    let transfer = id();
    let refs = |status| json!({"transfers":[{"id":transfer,"status":status,"sources":[path]}],"complete":true});
    command(&manager, "sharing.reconcile", refs("failed"));
    command(
        &manager,
        "sharing.reconcile",
        json!({"transfers":[],"complete":true}),
    );
    command(&manager, "sharing.reconcile", refs("cancelled"));
    assert_eq!(fs::read(&path).unwrap(), b"durable source");
    command(&manager, "sharing.reconcile", refs("completed"));
    assert!(!Path::new(&path).exists());
}

#[tokio::test]
async fn history_overflow_and_unrelated_external_paths_never_authorize_cleanup() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"retained").await;
    let path = batch["files"][0]["localPath"].as_str().unwrap();
    command(&manager, "sharing.retain", json!({"shareId":share}));
    command(&manager, "sharing.consume", json!({"shareId":share}));
    let before = command(&manager, "sharing.sources", Value::Null);
    let mut refs = vec![json!({"id":id(),"status":"completed","sources":[path]})];
    refs.extend(
        (0..1024)
            .map(|i| json!({"id":id(),"status":"completed","sources":[format!("/unrelated/{i}")]})),
    );
    let result = command(
        &manager,
        "sharing.reconcile",
        json!({"transfers":refs,"complete":true}),
    );
    assert_eq!(result["reconciled"], false);
    assert_eq!(result["snapshotComplete"], false);
    assert_eq!(before, command(&manager, "sharing.sources", Value::Null));
    assert!(Path::new(path).exists());
    for input in [
        json!(null),
        json!([null]),
        json!([{"id":"a","status":"completed","sources":[42]}]),
        json!([{"id":"a","status":"completed","sources":vec!["x";2049]}]),
    ] {
        let result = command(
            &manager,
            "sharing.reconcile",
            json!({"transfers":input,"complete":true}),
        );
        assert_eq!(result["reconciled"], false);
        assert!(Path::new(path).exists());
    }
}

#[tokio::test]
async fn byte_failure_removes_partial_and_does_not_poison_other_imports() {
    let cache = TempDir::new().unwrap();
    let manager = manager(
        &cache,
        Limits {
            file_bytes: 16,
            batch_bytes: 20,
            total_bytes: 24,
            ..Limits::default()
        },
    );
    let share = id();
    let source = cache.path().join("large");
    fs::write(&source, [7; 25]).unwrap();
    manager
        .import(&share, None, None, vec![path_source(&source)])
        .unwrap();
    assert_eq!(finish(&manager, &share).await["status"], "error");
    assert_eq!(
        command(
            &manager,
            "sharing.reconcile",
            json!({"transfers":[],"complete":true})
        )["retainedBytes"],
        0
    );
    assert_eq!(
        fs::read_dir(cache.path().join("incoming").join(&share))
            .unwrap()
            .count(),
        1
    );
    let (_, next) = ready(&manager, &cache, b"ok").await;
    assert_eq!(next["files"][0]["size"], 2);
}

#[tokio::test]
async fn bound_source_and_ready_batch_survive_late_reject_and_failed_journal_deletion() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"safe").await;
    let path = batch["files"][0]["localPath"].as_str().unwrap();
    let lease = command(&manager, "sharing.retain", json!({"shareId":share}));
    let lease_id = lease["leaseId"].as_str().unwrap();
    command(
        &manager,
        "sharing.reject",
        json!({"shareId":share,"reason":"late open failure"}),
    );
    command(&manager, "sharing.consume", json!({"shareId":share}));
    let journal = cache.path().join("incoming/.leases").join(lease_id);
    fs::remove_file(&journal).unwrap();
    fs::create_dir(&journal).unwrap();
    fs::write(journal.join("nonempty"), b"error").unwrap();
    assert!(
        manager
            .command("sharing.release", &json!({"leaseId":lease_id}))
            .is_err()
    );
    assert!(Path::new(path).exists());
    assert_eq!(
        command(&manager, "sharing.retain", json!({"shareId":share}))["leaseId"],
        lease["leaseId"]
    );
}

#[tokio::test]
async fn legacy_java_properties_migrate_in_place_with_active_lease_and_unicode_surrogates() {
    let cache = TempDir::new().unwrap();
    let share = id();
    let lease = id();
    let transfer = id();
    let directory = cache.path().join("incoming").join(&share);
    fs::create_dir_all(&directory).unwrap();
    fs::create_dir_all(cache.path().join("incoming/.leases")).unwrap();
    let file = directory.join("0-original");
    fs::write(&file, b"legacy active source").unwrap();
    fs::write(directory.join(".share"),b"created=1700000000000\nvisible=false\nstatus=ready\ncount=1\nfile.0.disk=0-original\nfile.0.name=\\u4e2d\\u6587\\uD83D\\uDE00.txt\n").unwrap();
    fs::write(
        cache.path().join("incoming/.leases").join(&lease),
        format!("share={share}\ntransfer={transfer}\n"),
    )
    .unwrap();
    let manager = manager(&cache, Limits::default());
    let inventory = command(&manager, "sharing.sources", Value::Null);
    assert_eq!(inventory["leases"][0]["files"][0]["name"], "中文😀.txt");
    assert_eq!(inventory["leases"][0]["transferId"], transfer);
    assert_eq!(inventory["sourcePaths"][0], file.to_string_lossy().as_ref());
    assert_eq!(fs::read(&file).unwrap(), b"legacy active source");
    assert_eq!(fs::read(directory.join(".share")).unwrap()[0], b'{');
    drop(manager);
    let restored = ImportManager::open(
        cache.path().join("incoming"),
        cache.path(),
        Limits::default(),
    )
    .unwrap();
    assert_eq!(
        command(&restored, "sharing.sources", Value::Null),
        inventory
    );
}

#[tokio::test]
async fn cross_client_submission_runs_one_operation_and_failure_or_cancellation_cannot_replay() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"send once").await;
    let params = json!({"shareId":share,"deviceId":"device","items":[{"source":batch["files"][0]["localPath"],"destination":"/sdcard/file"}]});
    let runs = Arc::new(AtomicUsize::new(0));
    let batch_id = id();
    let operation = || {
        let runs = runs.clone();
        let batch = batch_id.clone();
        async move {
            runs.fetch_add(1, Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(30)).await;
            Ok(json!({"batchId":batch,"status":"queued"}))
        }
    };
    let (first, second) = tokio::join!(
        manager.submit_once(&share, &params, operation),
        manager.submit_once(&share, &params, operation)
    );
    assert_eq!(first.unwrap()["batchId"], batch_id);
    assert_eq!(second.unwrap()["reusedTransfer"], true);
    assert_eq!(runs.load(Ordering::SeqCst), 1);
    let changed = json!({"shareId":share,"deviceId":"other","items":params["items"]});
    assert_eq!(
        manager
            .submit_once(&share, &changed, operation)
            .await
            .unwrap_err()
            .code,
        "share_submission_mismatch"
    );
    assert!(
        manager
            .submit_once(&share, &json!({"items":[]}), operation)
            .await
            .is_err()
    );
    let (other, other_batch) = ready(&manager, &cache, b"unknown").await;
    let p = json!({"items":[{"source":other_batch["files"][0]["localPath"]}]});
    let failed = manager
        .submit_once(&other, &p, || async {
            Err(CoreError::new("transport_error", "unknown"))
        })
        .await;
    assert!(failed.is_err());
    assert_eq!(
        manager
            .submit_once(&other, &p, operation)
            .await
            .unwrap_err()
            .code,
        "share_submission_unknown"
    );
    assert_eq!(runs.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn cancelled_publication_is_persistently_unknown_and_keeps_its_source() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"cancel does not prove no publication").await;
    let params = json!({"items":[{"source":batch["files"][0]["localPath"]}]});
    let (started, waiting) = tokio::sync::oneshot::channel();
    let clone = manager.clone();
    let share_id = share.clone();
    let request = params.clone();
    let task = tokio::spawn(async move {
        clone
            .submit_once(&share_id, &request, || async move {
                let _ = started.send(());
                std::future::pending::<Result<Value, CoreError>>().await
            })
            .await
    });
    waiting.await.unwrap();
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    command(&manager, "sharing.consume", json!({"shareId":share}));
    let path = batch["files"][0]["localPath"].as_str().unwrap();
    assert!(Path::new(path).exists());
    drop(manager);
    let restored = ImportManager::open(
        cache.path().join("incoming"),
        cache.path(),
        Limits::default(),
    )
    .unwrap();
    let error = restored
        .submit_once(&share, &params, || async {
            panic!("uncertain publication must never replay")
        })
        .await
        .unwrap_err();
    assert_eq!(error.code, "share_submission_unknown");
    let transfer = id();
    command(
        &restored,
        "sharing.reconcile",
        json!({"transfers":[{"id":transfer,"status":"retained","sources":[path]}],"complete":true}),
    );
    let reused = restored
        .submit_once(&share, &params, || async {
            panic!("positively recovered task must not replay")
        })
        .await
        .unwrap();
    assert_eq!(reused["batchId"], transfer);
    assert_eq!(reused["reusedTransfer"], true);
}

#[tokio::test]
async fn runtime_definite_validation_failure_can_retry_without_abandoning_lease() {
    let root = TempDir::new().unwrap();
    let cache = TempDir::new().unwrap();
    let runtime = interop_core::Runtime::initialize(root.path())
        .await
        .unwrap();
    runtime
        .invoke(
            "sharing.configure",
            json!({"absoluteRoot":cache.path().join("incoming"),"allowedCacheRoot":cache.path()}),
        )
        .await
        .unwrap();
    let share = id();
    let original = cache.path().join("source");
    fs::write(&original, b"offline retry").unwrap();
    runtime.invoke("sharing.import",json!({"shareId":share,"sources":[{"name":"source","path":original,"offset":0,"declaredLength":null}]})).await.unwrap();
    let path = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let pending = runtime.invoke("sharing.pending", json!({})).await.unwrap();
            if let Some(path) = pending["shares"][0]["files"][0]["localPath"].as_str() {
                break path.to_owned();
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let params = json!({"shareId":share,"deviceId":"offline","items":[{"source":path,"destination":"/sdcard/retry"}]});
    for _ in 0..2 {
        runtime
            .execute_file_publication("begin", &share, params.clone())
            .await
            .unwrap();
        runtime
            .execute_file_publication("abort", &share, json!({}))
            .await
            .unwrap();
    }
    let inventory = runtime.invoke("sharing.sources", json!({})).await.unwrap();
    assert_eq!(inventory["leases"].as_array().unwrap().len(), 1);
    assert!(Path::new(&path).exists());
}

#[cfg(any(target_os = "android", target_os = "linux"))]
#[tokio::test]
async fn fd_borrow_is_duplicated_and_asset_offset_length_are_exact() {
    use std::os::fd::AsRawFd;
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let source = cache.path().join("asset");
    fs::write(&source, b"prefixACTUALsuffix").unwrap();
    let input = fs::File::open(&source).unwrap();
    let share = id();
    manager
        .import(
            &share,
            None,
            None,
            vec![Source {
                name: "asset.bin".into(),
                fd: Some(input.as_raw_fd()),
                path: None,
                offset: 6,
                declared_length: Some(6),
            }],
        )
        .unwrap();
    drop(input);
    let batch = finish(&manager, &share).await;
    assert_eq!(batch["status"], "ready");
    assert_eq!(
        fs::read(batch["files"][0]["localPath"].as_str().unwrap()).unwrap(),
        b"ACTUAL"
    );
}

#[cfg(any(target_os = "android", target_os = "linux"))]
#[tokio::test]
async fn stream_cancel_timeout_queue_overflow_and_nonseekable_offsets_are_real() {
    use std::os::{fd::AsRawFd, unix::net::UnixStream};
    let cache = TempDir::new().unwrap();
    let manager = manager(
        &cache,
        Limits {
            pending: 2,
            timeout: Duration::from_millis(150),
            ..Limits::default()
        },
    );
    let (reader, _writer) = UnixStream::pair().unwrap();
    let make = |offset| Source {
        name: "pipe.bin".into(),
        fd: Some(reader.as_raw_fd()),
        path: None,
        offset,
        declared_length: None,
    };
    let invalid = id();
    assert_eq!(
        manager
            .import(&invalid, None, None, vec![make(1)])
            .unwrap_err()
            .code,
        "unsupported_source_offset"
    );
    command(&manager, "sharing.consume", json!({"shareId":invalid}));
    let first = id();
    let second = id();
    manager.import(&first, None, None, vec![make(0)]).unwrap();
    manager.import(&second, None, None, vec![make(0)]).unwrap();
    let overflow = id();
    assert_eq!(
        manager
            .import(&overflow, None, None, vec![make(0)])
            .unwrap_err()
            .code,
        "share_cache_busy"
    );
    assert!(!cache.path().join("incoming").join(overflow).exists());
    command(&manager, "sharing.cancel", json!({"shareId":first}));
    assert_eq!(finish(&manager, &first).await["status"], "error");
    assert_eq!(finish(&manager, &second).await["status"], "error");
    assert_eq!(
        fs::read_dir(cache.path().join("incoming").join(second))
            .unwrap()
            .count(),
        1
    );
}

#[test]
fn root_escape_symlinks_and_unknown_journals_preserve_data_and_deny_new_admission() {
    let cache = TempDir::new().unwrap();
    let outside = TempDir::new().unwrap();
    assert!(
        ImportManager::open(
            outside.path().join("incoming"),
            cache.path(),
            Limits::default()
        )
        .is_err()
    );
    let unknown = cache.path().join("incoming").join(id());
    fs::create_dir_all(&unknown).unwrap();
    let sentinel = unknown.join("unknown");
    fs::write(&sentinel, b"do not delete").unwrap();
    let manager = manager(&cache, Limits::default());
    assert_eq!(
        command(
            &manager,
            "sharing.reconcile",
            json!({"transfers":[],"complete":true})
        )["needsReview"],
        true
    );
    assert_eq!(
        manager
            .command("sharing.reject", &json!({"shareId":id(),"reason":"new"}))
            .unwrap_err()
            .code,
        "share_cache_busy"
    );
    assert!(sentinel.exists());
}

#[tokio::test]
async fn duplicate_engine_import_and_late_platform_reject_cannot_replace_the_owner() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let share = id();
    let original = cache.path().join("original");
    fs::write(&original, b"first authorized owner").unwrap();
    assert_eq!(
        manager
            .import(&share, None, None, vec![path_source(&original)])
            .unwrap()["status"],
        "starting"
    );
    // The second caller's revoked descriptor must never be inspected/adopted.
    let duplicate = manager
        .import(
            &share,
            None,
            None,
            vec![Source {
                name: "revoked".into(),
                fd: Some(-1),
                path: None,
                offset: 0,
                declared_length: None,
            }],
        )
        .unwrap();
    assert_eq!(duplicate["reusedImport"], true);
    command(
        &manager,
        "sharing.reject",
        json!({"shareId":share,"reason":"late revoked grant"}),
    );
    let batch = finish(&manager, &share).await;
    assert_eq!(batch["status"], "ready");
    let path = batch["files"][0]["localPath"].as_str().unwrap();
    assert_eq!(fs::read(path).unwrap(), b"first authorized owner");
    assert_eq!(
        manager.import(&share, None, None, vec![]).unwrap()["files"],
        batch["files"]
    );
    assert_eq!(
        fs::read_dir(cache.path().join("incoming").join(&share))
            .unwrap()
            .count(),
        2
    );
}

#[tokio::test]
async fn completed_memory_snapshot_cannot_reclaim_until_the_same_snapshot_is_durable() {
    let root = TempDir::new().unwrap();
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"must survive persistence failure").await;
    let path = batch["files"][0]["localPath"].as_str().unwrap().to_owned();
    let lease = command(&manager, "sharing.retain", json!({"shareId":share}));
    let transfer = id();
    command(
        &manager,
        "sharing.bind",
        json!({"leaseId":lease["leaseId"],"transferId":transfer}),
    );
    command(&manager, "sharing.consume", json!({"shareId":share}));
    drop(manager);
    let runtime = interop_core::Runtime::initialize(root.path())
        .await
        .unwrap();
    runtime
        .invoke(
            "sharing.configure",
            json!({"absoluteRoot":cache.path().join("incoming"),"allowedCacheRoot":cache.path()}),
        )
        .await
        .unwrap();
    let blocked = runtime
        .invoke("sharing.reconcile", json!({}))
        .await
        .unwrap();
    assert_eq!(blocked["reason"], "dart_transfer_snapshot_required");
    assert_eq!(
        fs::read(&path).unwrap(),
        b"must survive persistence failure"
    );
    assert_eq!(
        runtime.invoke("sharing.sources", json!({})).await.unwrap()["leases"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    // Only a complete snapshot supplied after the Dart journal flush permits release.
    runtime.execute_file_publication("reconcile","",json!({"transfers":[{"id":transfer,"status":"completed","sources":[path]}],"complete":true})).await.unwrap();
    assert!(!Path::new(&path).exists());
}

#[tokio::test]
async fn large_publication_metadata_restarts_from_compact_identity_receipts_without_replay() {
    let cache = TempDir::new().unwrap();
    let manager = manager(&cache, Limits::default());
    let (share, batch) = ready(&manager, &cache, b"durable publication").await;
    let params = json!({"shareId":share,"items":[{"source":batch["files"][0]["localPath"],"destination":"/sdcard/destination"}],"metadata":"x".repeat(100_000)});
    let batch_id = id();
    let receipt =
        json!({"batchId":batch_id,"status":"queued","transfers":[{"details":"y".repeat(100_000)}]});
    assert_eq!(
        manager
            .submit_once(&share, &params, || async { Ok(receipt.clone()) })
            .await
            .unwrap(),
        receipt
    );
    drop(manager);
    let journals: Vec<_> = fs::read_dir(cache.path().join("incoming/.leases"))
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert_eq!(journals.len(), 1);
    assert!(journals[0].metadata().unwrap().len() < 4096);
    let restored = ImportManager::open(
        cache.path().join("incoming"),
        cache.path(),
        Limits::default(),
    )
    .unwrap();
    let replay = restored
        .submit_once(&share, &params, || async {
            panic!("durable publication must not replay")
        })
        .await
        .unwrap();
    assert_eq!(replay["batchId"], batch_id);
    assert_eq!(replay["reusedTransfer"], true);
    assert!(replay.get("transfers").is_none());
}
