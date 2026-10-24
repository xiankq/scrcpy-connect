//! 使用真实流与受控本机完成栅栏核验操作句柄的认领、失败重试和迟到清理。
use super::*;
use interop_adb::protocol;

#[tokio::test]
async fn failed_claim_preserves_the_client_and_retry_drains_a_real_stream() {
    let (old, client, socket, writes) = cleanup_tests::connection_with_ownership(true);
    let physical = adb_connection_facts(old.clone()).unwrap().connection_id;
    let lifetime = admit_capture(&old, |_, lifetime, _| Ok(lifetime)).unwrap();
    let owner = admit_capture(&old, |_, _, owner| Ok(owner)).unwrap();
    with_connection_owner(&old, |actual| {
        assert_eq!(actual, owner);
        assert!(
            registry().try_lock().is_err(),
            "回收授权必须保持 exact key 锁至同步回调退出"
        );
    })
    .unwrap();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let peer = tokio::spawn(cleanup_tests::peer(socket, notice));
    let operation_id = adb_service(old.clone(), cleanup_tests::raw(), 5000)
        .await
        .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    writes.pause();
    assert!(
        connection_claim::claim(&old, Duration::from_millis(20))
            .await
            .is_err()
    );
    assert!(!client.is_closed());
    assert!(!lifetime.is_cancelled(), "认领不能取消捕获继承的 lifetime");
    assert!(registry().lock().unwrap().connections.contains_key(&old));
    assert!(device(&old).is_err());
    assert!(operation(old.clone()).is_err());
    assert!(admit_capture(&old, |_, _, _| Ok(())).is_err());
    assert_eq!(
        adb_connection_facts(old.clone()).unwrap().connection_id,
        physical
    );

    writes.resume();
    let next = adb_claim_connection(old.clone()).await.unwrap();
    assert_ne!(old, next.id);
    assert_eq!(
        adb_connection_facts(next.id.clone()).unwrap().connection_id,
        physical
    );
    assert_eq!(
        admit_capture(&next.id, |_, _, owner| Ok(owner)).unwrap(),
        owner
    );
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    assert!(
        !registry()
            .lock()
            .unwrap()
            .operations
            .contains_key(&operation_id)
    );
    assert!(device(&old).is_err());
    assert!(adb_connection_facts(old.clone()).is_err());
    assert!(with_connection_owner(&old, |_| panic!("旧句柄不得回收后继捕获")).is_none());
    assert!(adb_claim_connection(old.clone()).await.is_err());
    adb_disconnect(old).await.unwrap();
    assert!(!client.is_closed(), "旧句柄清理不能断开后继认领者");
    let operation = adb_service(next.id.clone(), cleanup_tests::raw(), 5000)
        .await
        .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    adb_cancel(operation).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    adb_disconnect(next.id).await.unwrap();
    assert!(client.is_closed());
    peer.await.unwrap();
}

#[tokio::test]
async fn queued_old_disconnect_and_second_claim_do_not_take_the_successor() {
    let (old, client, socket, _) = cleanup_tests::connection_with_ownership(true);
    let (notice, mut notices) = mpsc::unbounded_channel();
    let peer = tokio::spawn(cleanup_tests::peer(socket, notice));
    let (id, op, _events) = operation(old.clone()).unwrap();
    let stop = op.stop.clone();
    let release = CancellationToken::new();
    let held = release.clone();
    let worker = tokio::spawn(async move {
        let _finished = Completion(op.finished.clone());
        let stream = op
            .client
            .open("shell:held", OperationOptions::default())
            .await
            .unwrap();
        op.stop.cancelled().await;
        held.cancelled().await;
        drop(stream);
    });
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    let claiming = tokio::spawn(adb_claim_connection(old.clone()));
    stop.cancelled().await;
    assert!(admit_capture(&old, |_, _, _| Ok(())).is_err());
    assert!(admit_file(&old, |_, _| Ok(())).is_err());
    assert!(operation(old.clone()).is_err());
    let disconnecting = tokio::spawn(adb_disconnect(old.clone()));
    let competing = tokio::spawn(adb_claim_connection(old.clone()));
    tokio::task::yield_now().await;
    assert!(!claiming.is_finished());
    assert!(!disconnecting.is_finished());
    assert!(!competing.is_finished());
    release.cancel();
    let next = claiming.await.unwrap().unwrap();
    assert!(competing.await.unwrap().is_err());
    disconnecting.await.unwrap().unwrap();
    worker.await.unwrap();
    assert!(!client.is_closed());
    assert!(!registry().lock().unwrap().operations.contains_key(&id));
    assert!(device(&old).is_err());
    assert!(device(&next.id).unwrap().same_connection(&client));
    adb_disconnect(next.id).await.unwrap();
    peer.await.unwrap();
}

#[tokio::test]
async fn a_borrowed_entry_cannot_be_claimed_or_revoke_another_entry_on_the_same_client() {
    let (borrowed, client, peer, _) = cleanup_tests::connection();
    let other = insert_connection(client.clone(), "independent".into(), false).unwrap();
    let first_lifetime = admit_capture(&borrowed, |_, lifetime, _| Ok(lifetime)).unwrap();
    let other_lifetime = admit_capture(&other.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    assert_eq!(
        adb_claim_connection(borrowed.clone()).await.err().unwrap(),
        "adb_connection_borrowed"
    );
    assert!(!first_lifetime.is_cancelled());
    assert!(device(&borrowed).is_ok());
    assert_ne!(
        admit_capture(&borrowed, |_, _, owner| Ok(owner)).unwrap(),
        admit_capture(&other.id, |_, _, owner| Ok(owner)).unwrap()
    );
    adb_disconnect(borrowed).await.unwrap();
    assert!(!other_lifetime.is_cancelled());
    assert!(device(&other.id).is_ok());
    adb_disconnect(other.id).await.unwrap();
    client.close();
    drop(peer);
}

#[test]
fn global_close_cannot_be_escaped_by_an_inflight_claim() {
    const CHILD: &str = "INTEROP_ADB_CLAIM_CLOSE_CHILD";
    if std::env::var_os(CHILD).is_none() {
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "api::connection_claim_tests::global_close_cannot_be_escaped_by_an_inflight_claim",
                "--nocapture",
            ])
            .env(CHILD, "1")
            .status()
            .unwrap();
        assert!(status.success());
        return;
    }
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let (old, client, socket, _) = cleanup_tests::connection_with_ownership(true);
        let (notice, mut notices) = mpsc::unbounded_channel();
        let peer = tokio::spawn(cleanup_tests::peer(socket, notice));
        let (_, op, _events) = operation(old.clone()).unwrap();
        let stop = op.stop.clone();
        let release = CancellationToken::new();
        let held = release.clone();
        let worker = tokio::spawn(async move {
            let _finished = Completion(op.finished.clone());
            let stream = op
                .client
                .open("shell:held", OperationOptions::default())
                .await
                .unwrap();
            op.stop.cancelled().await;
            held.cancelled().await;
            drop(stream);
        });
        assert_eq!(notices.recv().await, Some(protocol::OPEN));
        let claiming = tokio::spawn(adb_claim_connection(old.clone()));
        stop.cancelled().await;
        assert!(
            close_all_with_timeout(Duration::from_millis(20))
                .await
                .is_err()
        );
        assert!(registry().lock().unwrap().closing);
        release.cancel();
        assert!(claiming.await.unwrap().is_err());
        worker.await.unwrap();
        assert!(registry().lock().unwrap().connections.contains_key(&old));
        adb_close_all().await.unwrap();
        assert!(registry().lock().unwrap().connections.is_empty());
        assert!(client.is_closed());
        peer.await.unwrap();
    });
}

#[tokio::test]
async fn a_naturally_closed_registration_still_reports_its_exact_facts() {
    let (id, client, peer, _) = cleanup_tests::connection();
    let physical = client.connection_id().to_string();
    drop(peer);
    tokio::time::timeout(Duration::from_secs(1), async {
        while !client.is_closed() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(device(&id).is_err());
    let facts = adb_connection_facts(id.clone()).unwrap();
    assert!(facts.closed);
    assert_eq!(facts.connection_id, physical);
    assert!(facts.server_address.is_none());
    adb_disconnect(id.clone()).await.unwrap();
    assert!(adb_connection_facts(id).is_err());
}

#[test]
fn capture_retirement_holds_the_exact_handle_until_its_callback_finishes() {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let (old, client, peer, _) =
        runtime.block_on(async { cleanup_tests::connection_with_ownership(true) });
    let (resolved, resolved_rx) = std::sync::mpsc::channel();
    let (release, release_rx) = std::sync::mpsc::channel();
    let retired = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let retiring = std::thread::spawn({
        let old = old.clone();
        let retired = retired.clone();
        move || {
            with_connection_owner(&old, |_| {
                resolved.send(()).unwrap();
                release_rx.recv().unwrap();
                retired.store(true, std::sync::atomic::Ordering::Release);
            })
            .unwrap()
        }
    });
    resolved_rx.recv().unwrap();
    assert!(
        registry().try_lock().is_err(),
        "精确查表后暂停回收仍必须阻挡认领提交"
    );
    let (attempted, attempted_rx) = std::sync::mpsc::channel();
    let claiming = runtime.spawn({
        let old = old.clone();
        async move {
            attempted.send(()).unwrap();
            adb_claim_connection(old).await
        }
    });
    attempted_rx.recv().unwrap();
    assert!(!claiming.is_finished());
    release.send(()).unwrap();
    retiring.join().unwrap();
    let next = runtime.block_on(claiming).unwrap().unwrap();
    assert!(retired.load(std::sync::atomic::Ordering::Acquire));
    let lifetime = admit_capture(&next.id, |_, lifetime, _| Ok(lifetime)).unwrap();
    assert!(with_connection_owner(&old, |_| lifetime.cancel()).is_none());
    assert!(!lifetime.is_cancelled(), "旧句柄不能在交接后补做回收");
    runtime.block_on(adb_disconnect(next.id)).unwrap();
    assert!(client.is_closed());
    drop(peer);
}
