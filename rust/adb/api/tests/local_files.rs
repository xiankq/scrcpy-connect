#![cfg(any(target_os = "linux", target_os = "android"))]
use interop_adb_api::api::*;
use std::{
    fs,
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd},
        unix::ffi::OsStrExt,
    },
    path::Path,
};
fn path(path: &Path) -> Vec<u8> {
    path.as_os_str().as_bytes().to_vec()
}
async fn open_scope(root: &Path) -> String {
    adb_local_scope_open(vec![path(root)], uuid::Uuid::new_v4().to_string(), 2000)
        .await
        .unwrap()
}
async fn private_scope() -> (tempfile::TempDir, String) {
    let root = tempfile::tempdir().unwrap();
    let scope = open_scope(root.path()).await;
    (root, scope)
}
fn pipe(flags: i32) -> (OwnedFd, OwnedFd) {
    let mut descriptors = [-1; 2];
    assert_eq!(
        unsafe { libc::pipe2(descriptors.as_mut_ptr(), libc::O_CLOEXEC | flags) },
        0
    );
    unsafe {
        (
            OwnedFd::from_raw_fd(descriptors[0]),
            OwnedFd::from_raw_fd(descriptors[1]),
        )
    }
}
fn request(source: &Path, target: &Path) -> LocalFileCopyRequest {
    LocalFileCopyRequest {
        source_path: Some(path(source)),
        source_fd: None,
        target_path: Some(path(target)),
        target_fd: None,
        source_offset: 0,
        length: None,
        expected_source: None,
        max_bytes: 1_000_000,
        timeout_ms: 2000,
    }
}
#[tokio::test]
async fn authorized_root_under_search_only_ancestor_supports_durable_file_operations() {
    use std::os::unix::fs::PermissionsExt;
    let ancestor = tempfile::tempdir().unwrap();
    struct RestorePermissions<'a>(&'a Path);
    impl Drop for RestorePermissions<'_> {
        fn drop(&mut self) {
            fs::set_permissions(self.0, fs::Permissions::from_mode(0o700)).unwrap();
        }
    }
    let _restore = RestorePermissions(ancestor.path());
    let root = ancestor.path().join("private-cache");
    fs::create_dir(&root).unwrap();
    let source = root.join("source");
    fs::write(&source, b"private app data").unwrap();
    fs::set_permissions(ancestor.path(), fs::Permissions::from_mode(0o111)).unwrap();
    assert_eq!(
        fs::read_dir(ancestor.path()).unwrap_err().kind(),
        std::io::ErrorKind::PermissionDenied
    );
    let scope = open_scope(&root).await;
    adb_local_mkdir(scope.clone(), path(&root.join("output")), true)
        .await
        .unwrap();
    let part = root.join("output/part");
    let destination = root.join("output/saved");
    let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
        .await
        .unwrap();
    let result = adb_local_copy_run(copy.clone()).await.unwrap();
    adb_local_commit(
        scope.clone(),
        copy.clone(),
        path(&destination),
        result.identity,
    )
    .await
    .unwrap();
    adb_local_copy_close(copy, 2000).await.unwrap();
    assert_eq!(fs::read(&destination).unwrap(), b"private app data");
    let identity = adb_local_stat(scope.clone(), path(&destination))
        .await
        .unwrap()
        .identity;
    adb_local_remove(scope.clone(), path(&destination), identity)
        .await
        .unwrap();
    adb_local_scope_close(scope, 2000).await.unwrap();
}

#[tokio::test]
async fn copy_capacity_is_reserved_before_open_and_released_only_after_confirmed_cleanup() {
    use std::os::unix::fs::PermissionsExt;
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    fs::write(&source, b"bounded ownership").unwrap();
    let extra = root.path().join("extra");
    // 打开失败必须归还名额，不能让失败请求耗尽后续正常复制。
    for _ in 0..40 {
        assert_eq!(
            adb_local_copy_create(scope.clone(), request(&root.path().join("missing"), &extra))
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::NotFound
        );
    }
    let mut copies = Vec::new();
    for index in 0..32 {
        copies.push(
            adb_local_copy_create(
                scope.clone(),
                request(&source, &root.path().join(format!("part-{index}"))),
            )
            .await
            .unwrap(),
        );
    }
    assert_eq!(
        adb_local_copy_create(scope.clone(), request(&source, &extra))
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::Busy
    );
    assert!(!extra.exists(), "超额请求不能先创建目标文件");
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o500)).unwrap();
    let failed_cleanup = adb_local_copy_close(copies[0].clone(), 2000).await;
    fs::set_permissions(root.path(), fs::Permissions::from_mode(0o700)).unwrap();
    assert!(failed_cleanup.is_err());
    assert_eq!(
        adb_local_copy_create(scope.clone(), request(&source, &extra))
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::Busy,
        "未确认清理仍然占有原句柄与容量"
    );
    adb_local_copy_close(copies[0].clone(), 2000).await.unwrap();
    let admitted = adb_local_copy_create(scope.clone(), request(&source, &extra))
        .await
        .unwrap();
    adb_local_copy_close(admitted, 2000).await.unwrap();
    adb_local_scope_close(scope, 2000).await.unwrap();
    assert!(!extra.exists());
}

#[tokio::test]
async fn scope_root_limit_rejects_before_opening_any_path() {
    let absent = vec![b"/not-an-existing-capability-root".to_vec(); 17];
    assert_eq!(
        adb_local_scope_open(absent, uuid::Uuid::new_v4().to_string(), 2000)
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::InvalidArgument
    );
}

#[tokio::test]
async fn retained_identity_cannot_publish_a_replacement_or_remove_it() {
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    let part = root.path().join("part");
    let target = root.path().join("target");
    fs::write(&source, b"original").unwrap();
    let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
        .await
        .unwrap();
    let result = adb_local_copy_run(copy.clone()).await.unwrap();
    fs::rename(&part, root.path().join("held")).unwrap();
    fs::write(&part, b"replacement").unwrap();
    assert_eq!(
        adb_local_commit(scope.clone(), copy.clone(), path(&target), result.identity)
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::SourceChanged
    );
    adb_local_copy_close(copy, 2000).await.unwrap();
    assert_eq!(fs::read(&part).unwrap(), b"replacement");
    assert!(!target.exists());
    let identity = adb_local_stat(scope.clone(), path(&part))
        .await
        .unwrap()
        .identity;
    fs::rename(&part, root.path().join("replacement-held")).unwrap();
    fs::write(&part, b"next").unwrap();
    assert_eq!(
        adb_local_remove(scope.clone(), path(&part), identity)
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::TargetChanged
    );
    assert_eq!(fs::read(part).unwrap(), b"next");
    adb_local_scope_close(scope, 2000).await.unwrap();
}
#[tokio::test]
async fn source_fd_is_duplicated_before_return_and_respects_its_exact_range() {
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    let part = root.path().join("part");
    fs::write(&source, b"prefix-CONTENT-suffix").unwrap();
    let file = fs::File::open(&source).unwrap();
    let mut options = request(&source, &part);
    options.source_path = None;
    options.source_fd = Some(file.as_raw_fd());
    options.source_offset = 7;
    options.length = Some(7);
    let copy = adb_local_copy_create(scope.clone(), options).await.unwrap();
    drop(file);
    let result = adb_local_copy_run(copy.clone()).await.unwrap();
    assert_eq!(result.bytes, 7);
    assert_eq!(fs::read(&part).unwrap(), b"CONTENT");
    adb_local_copy_close(copy, 2000).await.unwrap();
    assert!(!part.exists());
    adb_local_scope_close(scope, 2000).await.unwrap();
}
#[tokio::test]
async fn independent_ranges_of_one_source_descriptor_do_not_share_or_change_its_cursor() {
    use std::io::{Seek, SeekFrom};
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    let first_part = root.path().join("first-part");
    let second_part = root.path().join("second-part");
    fs::write(&source, b"abcdef").unwrap();
    let mut file = fs::File::open(&source).unwrap();
    file.seek(SeekFrom::Start(1)).unwrap();
    let mut first = request(&source, &first_part);
    first.source_path = None;
    first.source_fd = Some(file.as_raw_fd());
    first.length = Some(3);
    let mut second = first.clone();
    second.target_path = Some(path(&second_part));
    second.source_offset = 3;
    let first_id = adb_local_copy_create(scope.clone(), first).await.unwrap();
    let second_id = adb_local_copy_create(scope.clone(), second).await.unwrap();
    let cursor_after_create = file.stream_position().unwrap();
    let first_result = adb_local_copy_run(first_id.clone()).await;
    let first_bytes = fs::read(&first_part).unwrap();
    let second_result = adb_local_copy_run(second_id.clone()).await;
    let second_bytes = fs::read(&second_part).unwrap();
    let cursor_after_copy = file.stream_position().unwrap();
    adb_local_copy_close(first_id, 2000).await.unwrap();
    adb_local_copy_close(second_id, 2000).await.unwrap();
    adb_local_scope_close(scope, 2000).await.unwrap();
    assert_eq!(first_bytes, b"abc", "后登记范围不得改变先登记复制的起点");
    assert_eq!(second_bytes, b"def");
    assert_eq!(first_result.unwrap().bytes, 3);
    assert_eq!(second_result.unwrap().bytes, 3);
    assert_eq!(cursor_after_create, 1, "登记不得移动借入 FD 的游标");
    assert_eq!(cursor_after_copy, 1, "复制不得移动借入 FD 的游标");
}
#[tokio::test]
async fn sparse_source_above_four_gib_retains_its_size_and_exact_high_offset_range() {
    use std::{
        io::{Seek, SeekFrom},
        os::unix::fs::{FileExt, MetadataExt},
    };
    let (root, scope) = private_scope().await;
    let directory = root.path().join("large");
    fs::create_dir(&directory).unwrap();
    let source = directory.join("source");
    let mut file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&source)
        .unwrap();
    let offset = 5 * 1024 * 1024 * 1024 + 123;
    let payload = b"exact high-offset range";
    let size = offset + payload.len() as u64 + 9;
    file.set_len(size).unwrap();
    file.write_all_at(b"wrong low-offset bytes", 123).unwrap();
    file.write_all_at(payload, offset).unwrap();
    file.sync_all().unwrap();
    file.seek(SeekFrom::Start(5)).unwrap();
    let metadata = file.metadata().unwrap();
    // 只写入两个很短的范围，不能让大文件边界回归实际消耗数 GiB 空间。
    assert!(metadata.blocks() * 512 < 1024 * 1024);
    let before = adb_local_stat(scope.clone(), path(&source)).await.unwrap();
    assert_eq!(before.identity.size, size);
    assert_eq!(before.identity.inode, metadata.ino());
    assert_eq!(before.identity.device, metadata.dev());
    assert_eq!(before.identity.modified_seconds, metadata.mtime());
    assert_eq!(before.identity.modified_nanos, metadata.mtime_nsec() as u32);
    let listed = adb_local_list(scope.clone(), path(&directory), 1)
        .await
        .unwrap();
    assert_eq!(listed.entries[0].identity, before.identity);
    for use_descriptor in [true, false] {
        let part = root.path().join(if use_descriptor {
            "fd-part"
        } else {
            "path-part"
        });
        let mut options = request(&source, &part);
        if use_descriptor {
            options.source_path = None;
            options.source_fd = Some(file.as_raw_fd());
        }
        options.source_offset = offset;
        options.length = Some(payload.len() as u64);
        options.max_bytes = payload.len() as u64;
        options.expected_source = Some(before.identity.clone());
        let copy = adb_local_copy_create(scope.clone(), options).await.unwrap();
        let result = adb_local_copy_run(copy.clone()).await.unwrap();
        let bytes = fs::read(&part).unwrap();
        adb_local_copy_close(copy, 2000).await.unwrap();
        assert_eq!(result.bytes, payload.len() as u64);
        assert_eq!(result.source_identity, before.identity);
        assert_eq!(bytes, payload);
        assert_eq!(file.stream_position().unwrap(), 5);
    }
    adb_local_scope_close(scope, 2000).await.unwrap();
}
#[tokio::test]
async fn provider_pipe_target_is_explicitly_unsupported_without_writing_or_closing_it() {
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    fs::write(&source, b"must not be written").unwrap();
    let (read, write) = pipe(libc::O_NONBLOCK);
    let mut options = request(&source, &root.path().join("unused"));
    options.target_path = None;
    options.target_fd = Some(write.as_raw_fd());
    let rejected = adb_local_copy_create(scope.clone(), options)
        .await
        .unwrap_err();
    let mut byte = 0u8;
    assert_eq!(
        unsafe { libc::read(read.as_raw_fd(), (&mut byte as *mut u8).cast(), 1) },
        -1
    );
    assert_eq!(
        std::io::Error::last_os_error().raw_os_error(),
        Some(libc::EAGAIN)
    );
    assert!(unsafe { libc::fcntl(write.as_raw_fd(), libc::F_GETFD) } >= 0);
    adb_local_scope_close(scope, 2000).await.unwrap();
    assert_eq!(rejected.code, LocalFileErrorCode::Unsupported);
}
#[tokio::test]
async fn cancellation_drains_a_real_pipe_without_closing_the_platform_descriptor() {
    let (root, scope) = private_scope().await;
    let (read, write) = pipe(0);
    let part = root.path().join("part");
    let mut options = request(&root.path().join("unused"), &part);
    options.source_path = None;
    options.source_fd = Some(read.as_raw_fd());
    let copy = adb_local_copy_create(scope.clone(), options).await.unwrap();
    let run = tokio::spawn(adb_local_copy_run(copy.clone()));
    tokio::task::yield_now().await;
    adb_local_copy_cancel(copy.clone()).await.unwrap();
    adb_local_copy_close(copy, 2000).await.unwrap();
    assert_eq!(
        run.await.unwrap().unwrap_err().code,
        LocalFileErrorCode::Cancelled
    );
    assert!(!part.exists());
    assert!(unsafe { libc::fcntl(read.as_raw_fd(), libc::F_GETFD) } >= 0);
    assert!(unsafe { libc::fcntl(write.as_raw_fd(), libc::F_GETFD) } >= 0);
    adb_local_scope_close(scope, 2000).await.unwrap();
}
#[test]
fn cleanup_timeout_retains_handles_and_scope_admission_until_actual_worker_release() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .max_blocking_threads(1)
        .build()
        .unwrap();
    runtime.block_on(async {
        let (root, scope) = private_scope().await;
        let source = root.path().join("source");
        let part = root.path().join("part");
        fs::write(&source, b"queued").unwrap();
        let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
            .await
            .unwrap();
        let (release, held) = std::sync::mpsc::channel();
        let (ready, entered) = std::sync::mpsc::channel();
        let blocker = tokio::task::spawn_blocking(move || {
            ready.send(()).unwrap();
            held.recv().unwrap();
        });
        entered.recv().unwrap();
        let run = tokio::spawn(adb_local_copy_run(copy.clone()));
        tokio::task::yield_now().await;
        assert_eq!(
            adb_local_scope_close(scope.clone(), 1)
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::CleanupUnconfirmed
        );
        assert_eq!(
            adb_local_copy_close(copy.clone(), 1)
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::CleanupUnconfirmed
        );
        assert_eq!(
            adb_local_stat(scope.clone(), path(&source))
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::ScopeClosed
        );
        release.send(()).unwrap();
        blocker.await.unwrap();
        assert_eq!(
            run.await.unwrap().unwrap_err().code,
            LocalFileErrorCode::Cancelled
        );
        adb_local_copy_close(copy, 2000).await.unwrap();
        adb_local_scope_close(scope, 2000).await.unwrap();
        assert!(!part.exists());
    });
}
#[tokio::test]
async fn raw_names_limits_and_directory_roots_remain_exact() {
    use std::os::unix::ffi::OsStringExt;
    let (root, scope) = private_scope().await;
    let directory = root.path().join("directory");
    fs::create_dir(&directory).unwrap();
    fs::write(
        directory.join(std::ffi::OsString::from_vec(vec![0xff])),
        b"raw",
    )
    .unwrap();
    fs::write(directory.join("\u{fffd}"), b"valid").unwrap();
    let list = adb_local_list(scope.clone(), path(&directory), 2)
        .await
        .unwrap();
    assert!(list.entries.iter().any(|e| e.name == [0xff]));
    assert!(list.entries.iter().any(|e| e.name == "\u{fffd}".as_bytes()));
    assert_eq!(
        adb_local_list(scope.clone(), path(&directory), 1)
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::EntryLimit
    );
    assert_eq!(
        adb_local_stat(scope.clone(), path(root.path()))
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::InvalidArgument
    );
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("alias")).unwrap();
    assert!(
        adb_local_mkdir(
            scope.clone(),
            path(&root.path().join("alias/outside")),
            true
        )
        .await
        .is_err()
    );
    assert!(!outside.path().join("outside").exists());
    adb_local_scope_close(scope, 2000).await.unwrap();
}
#[tokio::test]
async fn provider_is_never_truncated_and_scope_close_reclaims_only_its_own_parts() {
    let (root, scope) = private_scope().await;
    let other = open_scope(root.path()).await;
    let source = root.path().join("source");
    let provider = root.path().join("provider");
    fs::write(&source, b"data").unwrap();
    fs::write(&provider, b"KEEP").unwrap();
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&provider)
        .unwrap();
    let mut options = request(&source, &root.path().join("unused"));
    options.target_path = None;
    options.target_fd = Some(file.as_raw_fd());
    assert_eq!(
        adb_local_copy_create(scope.clone(), options)
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::TargetChanged
    );
    assert_eq!(fs::read(&provider).unwrap(), b"KEEP");
    let part = root.path().join("part");
    let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
        .await
        .unwrap();
    adb_local_copy_run(copy.clone()).await.unwrap();
    let other_part = root.path().join("other-part");
    let other_copy = adb_local_copy_create(other.clone(), request(&source, &other_part))
        .await
        .unwrap();
    adb_local_copy_run(other_copy.clone()).await.unwrap();
    adb_local_scope_close(scope.clone(), 2000).await.unwrap();
    assert!(!part.exists());
    assert!(other_part.exists());
    assert_eq!(
        adb_local_copy_create(scope, request(&source, &part))
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::NotFound
    );
    adb_local_scope_close(other, 2000).await.unwrap();
    assert!(!other_part.exists());
}
#[tokio::test]
async fn closed_reservations_cannot_run_or_publish_and_conflicts_remain_retryable() {
    let (root, scope) = private_scope().await;
    let source = root.path().join("source");
    let part = root.path().join("part");
    fs::write(&source, b"bytes").unwrap();
    let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
        .await
        .unwrap();
    adb_local_copy_close(copy.clone(), 2000).await.unwrap();
    assert!(!part.exists());
    assert_eq!(
        adb_local_copy_run(copy).await.unwrap_err().code,
        LocalFileErrorCode::NotFound
    );
    let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
        .await
        .unwrap();
    let result = adb_local_copy_run(copy.clone()).await.unwrap();
    let target = root.path().join("target");
    fs::write(&target, b"existing").unwrap();
    assert_eq!(
        adb_local_commit(
            scope.clone(),
            copy.clone(),
            path(&target),
            result.identity.clone()
        )
        .await
        .unwrap_err()
        .code,
        LocalFileErrorCode::Conflict
    );
    assert_eq!(fs::read(target).unwrap(), b"existing");
    let next = root.path().join("next");
    adb_local_commit(scope.clone(), copy.clone(), path(&next), result.identity)
        .await
        .unwrap();
    adb_local_copy_close(copy, 2000).await.unwrap();
    assert_eq!(fs::read(next).unwrap(), b"bytes");
    adb_local_scope_close(scope, 2000).await.unwrap();
}

#[test]
fn same_key_handoff_keeps_retry_rights_and_old_ids_cannot_close_the_successor() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .max_blocking_threads(2)
        .build()
        .unwrap();
    runtime.block_on(async {
        let root = tempfile::tempdir().unwrap();
        let key = uuid::Uuid::new_v4().to_string();
        let original = adb_local_scope_open(vec![path(root.path())], key.clone(), 2000)
            .await
            .unwrap();
        let source = root.path().join("source");
        let part = root.path().join("part");
        fs::write(&source, b"pending").unwrap();
        let copy = adb_local_copy_create(original.clone(), request(&source, &part))
            .await
            .unwrap();
        let (release, held) = std::sync::mpsc::channel();
        let held = std::sync::Arc::new(std::sync::Mutex::new(held));
        let (ready, entered) = std::sync::mpsc::channel();
        // 真实占住两个阻塞 worker，使已登记复制的完成不能被虚假确认。
        let mut blockers = Vec::new();
        for _ in 0..2 {
            let held = held.clone();
            let ready = ready.clone();
            blockers.push(tokio::task::spawn_blocking(move || {
                ready.send(()).unwrap();
                held.lock().unwrap().recv().unwrap();
            }));
        }
        entered.recv().unwrap();
        entered.recv().unwrap();
        let running = tokio::spawn(adb_local_copy_run(copy.clone()));
        tokio::task::yield_now().await;
        assert_eq!(
            adb_local_scope_close(original.clone(), 1)
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::CleanupUnconfirmed
        );
        assert_eq!(
            adb_local_stat(original.clone(), path(&source))
                .await
                .unwrap_err()
                .code,
            LocalFileErrorCode::ScopeClosed
        );
        // 同 key 恢复等待旧 worker 的实际退出；关闭另一个 scope 不依赖此资源的锁。
        release.send(()).unwrap();
        release.send(()).unwrap();
        for blocker in blockers {
            blocker.await.unwrap();
        }
        assert_eq!(
            running.await.unwrap().unwrap_err().code,
            LocalFileErrorCode::Cancelled
        );
        let successor = adb_local_scope_open(vec![path(root.path())], key, 2000)
            .await
            .unwrap();
        assert_ne!(original, successor);
        assert!(!part.exists());
        adb_local_scope_close(original, 2000).await.unwrap();
        assert!(
            adb_local_stat(successor.clone(), path(&source))
                .await
                .is_ok()
        );
        adb_local_scope_close(successor, 2000).await.unwrap();
    });
}

#[tokio::test]
async fn one_scope_blocked_on_a_pipe_does_not_lock_another_scope() {
    let root = tempfile::tempdir().unwrap();
    let first = open_scope(root.path()).await;
    let second = open_scope(root.path()).await;
    let (read, _write) = pipe(0);
    let mut options = request(&root.path().join("unused"), &root.path().join("part"));
    options.source_path = None;
    options.source_fd = Some(read.as_raw_fd());
    let copy = adb_local_copy_create(first.clone(), options).await.unwrap();
    let running = tokio::spawn(adb_local_copy_run(copy.clone()));
    tokio::task::yield_now().await;
    let independent = root.path().join("independent");
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        adb_local_mkdir(second.clone(), path(&independent), true),
    )
    .await
    .unwrap()
    .unwrap();
    adb_local_scope_close(first, 2000).await.unwrap();
    assert!(running.await.unwrap().is_err());
    assert!(independent.is_dir());
    adb_local_scope_close(second, 2000).await.unwrap();
}

#[cfg(target_os = "linux")]
fn isolate(name: &str, flag: &str) -> bool {
    if std::env::var_os(flag).is_some() {
        return false;
    }
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", name, "--nocapture"])
        .env(flag, "1")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    true
}
#[cfg(target_os = "linux")]
fn deny_syscall_except_fd(number: libc::c_long, allowed: Option<i32>) {
    let mut filter = vec![
        libc::sock_filter {
            code: (libc::BPF_LD | libc::BPF_W | libc::BPF_ABS) as u16,
            jt: 0,
            jf: 0,
            k: 0,
        },
        libc::sock_filter {
            code: (libc::BPF_JMP | libc::BPF_JEQ | libc::BPF_K) as u16,
            jt: 0,
            jf: if allowed.is_some() { 3 } else { 1 },
            k: number as u32,
        },
    ];
    if let Some(fd) = allowed {
        filter.extend([
            libc::sock_filter {
                code: (libc::BPF_LD | libc::BPF_W | libc::BPF_ABS) as u16,
                jt: 0,
                jf: 0,
                k: 16,
            },
            libc::sock_filter {
                code: (libc::BPF_JMP | libc::BPF_JEQ | libc::BPF_K) as u16,
                jt: 1,
                jf: 0,
                k: fd as u32,
            },
        ]);
    }
    filter.extend([
        libc::sock_filter {
            code: (libc::BPF_RET | libc::BPF_K) as u16,
            jt: 0,
            jf: 0,
            k: libc::SECCOMP_RET_ERRNO | libc::EIO as u32,
        },
        libc::sock_filter {
            code: (libc::BPF_RET | libc::BPF_K) as u16,
            jt: 0,
            jf: 0,
            k: libc::SECCOMP_RET_ALLOW,
        },
    ]);
    let program = libc::sock_fprog {
        len: filter.len() as u16,
        filter: filter.as_mut_ptr(),
    };
    assert_eq!(
        unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1usize, 0usize, 0usize, 0usize) },
        0
    );
    assert_eq!(
        unsafe {
            libc::syscall(
                libc::SYS_seccomp,
                libc::SECCOMP_SET_MODE_FILTER,
                libc::SECCOMP_FILTER_FLAG_TSYNC,
                &program,
            )
        },
        0
    );
}
#[cfg(target_os = "linux")]
#[test]
fn no_hardlink_permission_is_needed_for_no_replace_commit() {
    if isolate(
        "no_hardlink_permission_is_needed_for_no_replace_commit",
        "INTEROP_LOCAL_NO_HARDLINK",
    ) {
        return;
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let (root, scope) = private_scope().await;
        let source = root.path().join("source");
        let part = root.path().join("part");
        let target = root.path().join("target");
        fs::write(&source, b"no hardlink").unwrap();
        let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
            .await
            .unwrap();
        let result = adb_local_copy_run(copy.clone()).await.unwrap();
        deny_syscall_except_fd(libc::SYS_linkat, None);
        adb_local_commit(scope.clone(), copy.clone(), path(&target), result.identity)
            .await
            .unwrap();
        adb_local_copy_close(copy, 2000).await.unwrap();
        assert_eq!(fs::read(target).unwrap(), b"no hardlink");
        adb_local_scope_close(scope, 2000).await.unwrap();
    });
}
#[cfg(target_os = "linux")]
#[test]
fn post_rename_sync_failure_consumes_publication_right_and_close_preserves_both_paths() {
    if isolate(
        "post_rename_sync_failure_consumes_publication_right_and_close_preserves_both_paths",
        "INTEROP_LOCAL_UNKNOWN_COMMIT",
    ) {
        return;
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let (root, scope) = private_scope().await;
        let source = root.path().join("source");
        let part = root.path().join("part");
        let target = root.path().join("target");
        fs::write(&source, b"published").unwrap();
        let copy = adb_local_copy_create(scope.clone(), request(&source, &part))
            .await
            .unwrap();
        let result = adb_local_copy_run(copy.clone()).await.unwrap();
        let target_fd = fs::read_dir("/proc/self/fd")
            .unwrap()
            .filter_map(|entry| {
                let entry = entry.ok()?;
                (fs::read_link(entry.path()).ok()? == part)
                    .then(|| entry.file_name().to_string_lossy().parse::<i32>().unwrap())
            })
            .next()
            .unwrap();
        // 原目标文件的 fsync 成功，rename 后的目录 fsync 真正失败；不注入伪造回执。
        deny_syscall_except_fd(libc::SYS_fsync, Some(target_fd));
        assert_eq!(
            adb_local_commit(
                scope.clone(),
                copy.clone(),
                path(&target),
                result.identity.clone()
            )
            .await
            .unwrap_err()
            .code,
            LocalFileErrorCode::ResultUnknown
        );
        assert_eq!(fs::read(&target).unwrap(), b"published");
        fs::write(&part, b"replacement").unwrap();
        assert_eq!(
            adb_local_commit(
                scope.clone(),
                copy.clone(),
                path(&root.path().join("second")),
                result.identity
            )
            .await
            .unwrap_err()
            .code,
            LocalFileErrorCode::ResultUnknown
        );
        adb_local_copy_close(copy, 2000).await.unwrap();
        assert_eq!(fs::read(target).unwrap(), b"published");
        assert_eq!(fs::read(part).unwrap(), b"replacement");
        adb_local_scope_close(scope, 2000).await.unwrap();
    });
}

#[tokio::test]
async fn authorized_root_alias_is_resolved_once_and_cannot_redirect_the_anchor() {
    let parent = tempfile::tempdir().unwrap();
    let first = parent.path().join("first");
    let second = parent.path().join("second");
    fs::create_dir(&first).unwrap();
    fs::create_dir(&second).unwrap();
    fs::write(first.join("item"), b"first").unwrap();
    fs::write(second.join("item"), b"second").unwrap();
    let alias = parent.path().join("authorized");
    std::os::unix::fs::symlink(&first, &alias).unwrap();
    let scope = open_scope(&alias).await;
    assert_eq!(
        adb_local_stat(scope.clone(), path(&alias))
            .await
            .unwrap_err()
            .code,
        LocalFileErrorCode::InvalidArgument
    );
    adb_local_storage_free_bytes(alias.to_str().unwrap().into())
        .await
        .unwrap();
    let identity = adb_local_stat(scope.clone(), path(&alias.join("item")))
        .await
        .unwrap()
        .identity;
    fs::remove_file(&alias).unwrap();
    std::os::unix::fs::symlink(&second, &alias).unwrap();
    assert_eq!(
        adb_local_stat(scope.clone(), path(&alias.join("item")))
            .await
            .unwrap()
            .identity,
        identity
    );
    std::os::unix::fs::symlink(&second, first.join("inside")).unwrap();
    assert!(
        adb_local_stat(scope.clone(), path(&alias.join("inside/item")))
            .await
            .is_err()
    );
    adb_local_mkdir(scope.clone(), path(&alias.join("owned")), true)
        .await
        .unwrap();
    assert!(first.join("owned").exists());
    assert!(!second.join("owned").exists());
    adb_local_scope_close(scope, 2000).await.unwrap();
    let root_alias = parent.path().join("filesystem-root");
    std::os::unix::fs::symlink("/", &root_alias).unwrap();
    adb_local_storage_free_bytes(root_alias.to_str().unwrap().into())
        .await
        .unwrap();
    assert_eq!(
        adb_local_scope_open(
            vec![path(&root_alias)],
            uuid::Uuid::new_v4().to_string(),
            2000
        )
        .await
        .unwrap_err()
        .code,
        LocalFileErrorCode::InvalidArgument
    );
}
