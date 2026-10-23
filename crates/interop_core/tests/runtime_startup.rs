use interop_core::Runtime;
use serde_json::json;

/// The normal application bootstraps the runtime and then registers a
/// canonical system temporary directory. DeviceRuntime-only tests omit this
/// second half of startup, including the cache component validation.
#[tokio::test]
async fn normal_startup_registers_canonical_cache_and_reopens_ownership() {
    let directory = tempfile::tempdir().unwrap();
    let support = directory.path().join("support");
    let outgoing = directory.path().join("temporary").join("outgoing");
    tokio::fs::create_dir_all(&outgoing).await.unwrap();
    let outgoing = tokio::fs::canonicalize(outgoing).await.unwrap();
    let runtime = Runtime::initialize(&support)
        .await
        .expect("native runtime initialization must succeed");
    runtime
        .invoke(
            "media.cache.configure",
            json!({"outgoingDirectory": outgoing}),
        )
        .await
        .expect("normal bootstrap must register its canonical outgoing cache");
    let reopened = Runtime::initialize(&support)
        .await
        .expect("startup must reopen the persisted canonical cache registration");
    reopened
        .invoke("media.cache.status", json!({}))
        .await
        .expect("startup cache status must validate its canonical managed roots");
}

#[cfg(any(unix, windows))]
#[tokio::test]
async fn normal_startup_rejects_linked_cache_components() {
    let directory = tempfile::tempdir().unwrap();
    let target = directory.path().join("external");
    tokio::fs::create_dir_all(&target).await.unwrap();
    let link = directory.path().join("alias");
    #[cfg(unix)]
    std::os::unix::fs::symlink(&target, &link).unwrap();
    #[cfg(windows)]
    {
        // Directory junctions require no elevated/developer-mode privilege.
        let result = std::process::Command::new("cmd.exe")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&target)
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "junction creation failed: {result:?}"
        );
    }
    let runtime = Runtime::initialize(directory.path().join("support"))
        .await
        .unwrap();
    let error = runtime
        .invoke(
            "media.cache.configure",
            json!({"outgoingDirectory": link.join("outgoing")}),
        )
        .await
        .expect_err("prefix handling must retain directory-link rejection");
    assert_eq!(error.code, "invalid_argument");
    assert!(error.message.contains("符号链接"));
}
