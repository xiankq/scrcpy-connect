use interop_adb::CancellationToken;
use interop_core::{AdbServerPolicy, ConnectionPolicy, Runtime};
use serde_json::json;
use std::sync::{Arc, atomic::AtomicU64};

#[tokio::test]
#[ignore = "requires isolated official adb server and an explicitly authorized test Android endpoint"]
async fn official_server_file_facts_copy_atomic_publish_and_cancellation() {
    let server: std::net::SocketAddr = std::env::var("INTEROP_ADB_SERVER")
        .unwrap()
        .parse()
        .unwrap();
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_ADBD_ENDPOINT")
        .unwrap()
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let key = std::env::var("INTEROP_ADB_KEY").unwrap();
    std::fs::copy(&key, root.path().join("host_identity.pem")).unwrap();
    let keys = root.path().join("keys");
    std::fs::create_dir_all(keys.join("global")).unwrap();
    std::fs::copy(key, keys.join("global/adbkey")).unwrap();
    let mut policy = ConnectionPolicy::standalone();
    policy.adb_server = Some(AdbServerPolicy {
        host: server.ip().to_string(),
        port: server.port(),
        executable_path: std::env::var("INTEROP_ADB_BINARY").unwrap(),
        key_directory: keys.to_string_lossy().into_owned(),
    });
    let runtime = Runtime::initialize_with_connection_policy(root.path(), policy)
        .await
        .unwrap();
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let token = CancellationToken::new();
    let remote = format!("/data/local/tmp/interop-file-{}", uuid::Uuid::new_v4());
    runtime
        .execute_file_mutation(id, "mkdir", &remote, "", false, false, token.clone())
        .await
        .unwrap();
    let result = async {
        let bytes = (0..4096).map(|i| (i % 251) as u8).collect::<Vec<_>>();
        let source = root.path().join("source.bin");
        std::fs::write(&source, &bytes).unwrap();
        let source = source.to_str().unwrap();
        let stamp = runtime
            .execute_file_stat(id, source, true, false, token.clone())
            .await
            .unwrap();
        let part = format!("{remote}/upload.part");
        let target = format!("{remote}/a.bin");
        let count = runtime
            .execute_file_copy(
                id,
                source,
                &part,
                true,
                stamp,
                token.clone(),
                Arc::new(AtomicU64::new(0)),
            )
            .await
            .unwrap();
        assert_eq!(count, 4096);
        runtime
            .execute_file_mutation(id, "commit", &part, &target, false, false, token.clone())
            .await
            .unwrap();
        let facts = runtime
            .execute_file_list(id, &remote, false, 16, token.clone())
            .await
            .unwrap();
        assert!(!facts.truncated);
        assert_eq!(facts.entries.len(), 1);
        assert_eq!(facts.entries[0].name, b"a.bin");
        let stamp = runtime
            .execute_file_stat(id, &target, false, false, token.clone())
            .await
            .unwrap();
        assert_eq!(stamp.size, 4096);
        let temporary = root.path().join("download.part");
        let destination = root.path().join("download.bin");
        runtime
            .execute_file_copy(
                id,
                &target,
                temporary.to_str().unwrap(),
                false,
                stamp,
                token.clone(),
                Arc::new(AtomicU64::new(0)),
            )
            .await
            .unwrap();
        runtime
            .execute_file_mutation(
                id,
                "commit",
                temporary.to_str().unwrap(),
                destination.to_str().unwrap(),
                true,
                false,
                token.clone(),
            )
            .await
            .unwrap();
        assert_eq!(std::fs::read(destination).unwrap(), bytes);
        let cancelled = CancellationToken::new();
        cancelled.cancel();
        assert_eq!(
            runtime
                .execute_file_list(id, &remote, false, 16, cancelled)
                .await
                .err()
                .unwrap()
                .code,
            "cancelled"
        );
        let missing = runtime
            .execute_file_stat(
                id,
                root.path().join("missing").to_str().unwrap(),
                true,
                false,
                token.clone(),
            )
            .await
            .unwrap_err();
        assert_eq!(missing.code, "not_found");
        println!(
            "actual official-server AVD: typed stat/list, 4096-byte binary push/pull, remote and local no-replace publication, pre-cancel and missing local metadata verified"
        );
    };
    // Test cleanup is restricted to this unique temporary fixture tree.
    result.await;
    runtime
        .execute_file_mutation(id, "delete", &remote, "", false, false, token)
        .await
        .unwrap();
    runtime.stop_all().await;
}
