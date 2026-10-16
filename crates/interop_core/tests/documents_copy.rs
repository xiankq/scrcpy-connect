#![cfg(any(target_os = "linux", target_os = "android"))]
use interop_core::documents::CopyManager;
use serde_json::{Value, json};
use std::{
    fs,
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    sync::Arc,
    thread,
    time::Duration,
};

fn params(root: &std::path::Path) -> Value {
    json!({"allowedRoots":[root],"operationId":"copy-test"})
}

#[test]
fn copies_exact_bytes_and_publishes_without_replacing_an_existing_file() {
    let root = tempfile::tempdir().unwrap();
    let manager = CopyManager::default();
    let source = root.path().join("source");
    let part = root.path().join("part");
    let target = root.path().join("target");
    fs::write(&source, b"shared document bytes").unwrap();
    let mut p = params(root.path());
    p["sourcePath"] = json!(source);
    p["targetPath"] = json!(part);
    let result = manager.request("document.copy", p.clone()).unwrap();
    assert_eq!(result["bytes"], 21);
    let commit = json!({"allowedRoots":[root.path()],"partPath":part,"path":target,"identity":result["identity"]});
    manager.request("document.commit", commit.clone()).unwrap();
    assert!(!part.exists());
    assert_eq!(fs::read(&target).unwrap(), b"shared document bytes");
    fs::write(&part, b"replacement").unwrap();
    assert!(
        manager
            .request(
                "document.commit",
                json!({"allowedRoots":[root.path()],"partPath":part,"path":target})
            )
            .is_err()
    );
    assert_eq!(fs::read(&target).unwrap(), b"shared document bytes");
}
#[test]
fn refuses_nonempty_provider_descriptor_without_truncation() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source");
    let target = root.path().join("existing");
    fs::write(&source, b"new").unwrap();
    fs::write(&target, b"keep existing").unwrap();
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&target)
        .unwrap();
    let mut p = params(root.path());
    p["sourcePath"] = json!(source);
    p["targetFd"] = json!(file.as_raw_fd());
    let error = CopyManager::default()
        .request("document.copy", p)
        .unwrap_err();
    assert_eq!(error.code, "target_changed");
    assert_eq!(fs::read(&target).unwrap(), b"keep existing");
}
#[test]
fn quota_failure_removes_only_its_private_partial_and_never_publishes() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source");
    let part = root.path().join("part");
    fs::write(&source, vec![4; 100_000]).unwrap();
    let mut p = params(root.path());
    p["sourcePath"] = json!(source);
    p["targetPath"] = json!(part);
    p["maxBytes"] = json!(70000);
    let error = CopyManager::default()
        .request("document.copy", p)
        .unwrap_err();
    assert_eq!(error.code, "byte_limit");
    assert_eq!(error.details["bytesCopied"], 65536);
    assert!(!part.exists());
}
#[test]
fn rejects_symlink_ancestors_and_stale_source_identity() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("secret"), b"outside").unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("link")).unwrap();
    let manager = CopyManager::default();
    let mut p = params(root.path());
    p["path"] = json!(root.path().join("link/secret"));
    assert!(manager.request("document.localStat", p).is_err());
    let source = root.path().join("source");
    fs::write(&source, b"old").unwrap();
    let identity = manager
        .request(
            "document.localStat",
            json!({"allowedRoots":[root.path()],"path":source}),
        )
        .unwrap();
    fs::remove_file(&source).unwrap();
    fs::write(&source, b"different source").unwrap();
    let mut p = params(root.path());
    p["sourcePath"] = json!(source);
    p["targetPath"] = json!(root.path().join("part"));
    p["sourceIdentity"] = identity;
    assert_eq!(
        manager.request("document.copy", p).unwrap_err().code,
        "source_changed"
    );
    assert!(!root.path().join("part").exists());
}
#[test]
fn cancellation_interrupts_a_real_empty_pipe_and_keeps_one_io_slot() {
    let root = tempfile::tempdir().unwrap();
    let mut ends = [0; 2];
    assert_eq!(
        unsafe { libc::pipe2(ends.as_mut_ptr(), libc::O_CLOEXEC) },
        0
    );
    let read = unsafe { OwnedFd::from_raw_fd(ends[0]) };
    let _write = unsafe { OwnedFd::from_raw_fd(ends[1]) };
    let manager = Arc::new(CopyManager::default());
    let mut p = params(root.path());
    p["sourceFd"] = json!(read.as_raw_fd());
    p["targetPath"] = json!(root.path().join("part"));
    let worker = manager.clone();
    let job = thread::spawn(move || worker.request("document.copy", p));
    // Confirm the active slot instead of assuming the worker was scheduled.
    for attempt in 0..100 {
        let result = manager.request("document.copy", json!({"operationId":"probe"}));
        if result.is_err_and(|e| e.code == "documents_busy") {
            break;
        }
        assert!(attempt < 99);
        thread::sleep(Duration::from_millis(5));
    }
    manager
        .request("document.cancel", json!({"operationId":"copy-test"}))
        .unwrap();
    let error = job.join().unwrap().unwrap_err();
    assert_eq!(error.code, "cancelled");
    assert!(!root.path().join("part").exists());
}
#[test]
fn local_plan_preserves_empty_directories_and_cannot_remove_a_replacement() {
    let root = tempfile::tempdir().unwrap();
    let manager = CopyManager::default();
    let dir = root.path().join("empty");
    manager
        .request(
            "document.mkdir",
            json!({"allowedRoots":[root.path()],"path":dir}),
        )
        .unwrap();
    let listed = manager
        .request(
            "document.localChildren",
            json!({"allowedRoots":[root.path()],"path":dir}),
        )
        .unwrap();
    assert_eq!(listed["entries"], json!([]));
    let file = root.path().join("part");
    fs::write(&file, b"first").unwrap();
    let stamp = manager
        .request(
            "document.localStat",
            json!({"allowedRoots":[root.path()],"path":file}),
        )
        .unwrap();
    let replacement = root.path().join("replacement");
    fs::write(&replacement, b"keep").unwrap();
    fs::rename(&replacement, &file).unwrap();
    assert_eq!(
        manager
            .request(
                "document.remove",
                json!({"allowedRoots":[root.path()],"path":file,"identity":stamp})
            )
            .unwrap_err()
            .code,
        "target_changed"
    );
    assert_eq!(fs::read(file).unwrap(), b"keep");
}

#[test]
fn rejects_alias_prefixes_root_exposure_and_identity_paths() {
    let root = tempfile::tempdir().unwrap();
    let manager = CopyManager::default();
    for path in [
        root.path().to_path_buf(),
        root.path().with_extension("other").join("item"),
        root.path()
            .parent()
            .unwrap()
            .join("files/host_identity.pem"),
        root.path().join("../outside"),
    ] {
        let result = manager.request(
            "document.localStat",
            json!({"allowedRoots":[root.path()],"path":path}),
        );
        assert_eq!(result.unwrap_err().code, "invalid_path");
    }
}

#[test]
fn cancellation_before_descriptor_binding_still_rejects_the_late_copy() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source");
    let part = root.path().join("part");
    fs::write(&source, b"must not publish").unwrap();
    let manager = CopyManager::default();
    manager
        .request("document.cancel", json!({"operationId":"copy-test"}))
        .unwrap();
    let mut p = params(root.path());
    p["sourcePath"] = json!(source);
    p["targetPath"] = json!(part);
    assert_eq!(
        manager.request("document.copy", p).unwrap_err().code,
        "cancelled"
    );
    assert!(!part.exists());
}
