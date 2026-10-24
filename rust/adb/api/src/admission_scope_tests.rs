//! 稳定准入域通过公开接口接管，真实工作必须完成后才换发权限。
use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::io::AsyncReadExt;

#[tokio::test]
async fn takeover_failure_retains_the_revoked_scope_until_real_work_exits() {
    let name = format!("scope-{}", uuid::Uuid::new_v4());
    let first = adb_admission_scope_attach(name.clone(), None, 1000)
        .await
        .unwrap();
    let handshake = adb_scoped_handshake_create(first.scope_id.clone())
        .await
        .unwrap();
    let release = CancellationToken::new();
    let held = release.clone();
    let (started, ready) = tokio::sync::oneshot::channel();
    let worker = tokio::spawn(handshake::run(
        Some(handshake.clone()),
        move |stop| async move {
            started.send(()).unwrap();
            stop.cancelled().await;
            held.cancelled().await;
            Ok(())
        },
    ));
    ready.await.unwrap();
    assert_eq!(
        adb_admission_scope_attach(name.clone(), Some(first.scope_id.clone()), 20)
            .await
            .unwrap_err(),
        "adb_admission_scope_cleanup_unconfirmed"
    );
    let retained = adb_admission_scope_inspect(name.clone()).unwrap().unwrap();
    assert_eq!(retained.scope_id, first.scope_id);
    assert!(!retained.accepting);
    assert_eq!(
        adb_scoped_handshake_create(first.scope_id.clone())
            .await
            .unwrap_err()
            .message,
        "adb_admission_scope_stale"
    );
    release.cancel();
    worker.await.unwrap().unwrap();
    let next = adb_admission_scope_attach(name.clone(), Some(first.scope_id.clone()), 1000)
        .await
        .unwrap();
    assert_ne!(first.scope_id, next.scope_id);
    adb_admission_scope_close(first.scope_id.clone(), 1000)
        .await
        .unwrap();
    assert_eq!(
        adb_admission_scope_inspect(name.clone())
            .unwrap()
            .unwrap()
            .scope_id,
        next.scope_id
    );
    adb_admission_scope_close(next.scope_id, 1000)
        .await
        .unwrap();
    assert!(adb_admission_scope_inspect(name).unwrap().is_none());
}

async fn scope() -> AdbAdmissionScopeInfo {
    adb_admission_scope_attach(format!("scope-{}", uuid::Uuid::new_v4()), None, 1000)
        .await
        .unwrap()
}

async fn direct_connection(
    scope: &AdbAdmissionScopeInfo,
    stalled: bool,
) -> (
    String,
    tokio::task::JoinHandle<Result<AdbDeviceInfo, AdbConnectionError>>,
    tokio::net::TcpStream,
    tempfile::TempDir,
) {
    static PEM: OnceLock<String> = OnceLock::new();
    let pem = PEM.get_or_init(|| {
        Identity::generate()
            .unwrap()
            .to_pkcs8_pem()
            .unwrap()
            .to_string()
    });
    let directory = tempfile::tempdir().unwrap();
    let path = directory
        .path()
        .join("key.pem")
        .to_string_lossy()
        .into_owned();
    adb_replace_identity(path.clone(), pem.clone(), None)
        .await
        .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let id = adb_scoped_handshake_create(scope.scope_id.clone())
        .await
        .unwrap();
    let handshake = id.clone();
    let worker = tokio::spawn(connect_tcp(
        address,
        path,
        false,
        true,
        60_000,
        AdbConnectOptions::default(),
        Some(handshake),
    ));
    let (mut peer, _) = listener.accept().await.unwrap();
    assert_eq!(
        Frame::read(&mut peer, 4096, false).await.unwrap().command,
        protocol::CNXN
    );
    if !stalled {
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::\0".to_vec(),
        )
        .write(&mut peer)
        .await
        .unwrap();
    }
    (id, worker, peer, directory)
}

#[tokio::test]
async fn takeover_drains_real_tcp_handshake_without_touching_another_scope() {
    let old = scope().await;
    let other = scope().await;
    let (handshake, worker, mut peer, _directory) = direct_connection(&old, true).await;
    let (other_handshake, other_worker, other_peer, _other_directory) =
        direct_connection(&other, true).await;
    let next = adb_admission_scope_attach(old.scope_key.clone(), Some(old.scope_id.clone()), 1000)
        .await
        .unwrap();
    assert!(worker.await.unwrap().is_err());
    let mut byte = [0];
    assert_eq!(
        peer.read(&mut byte).await.unwrap(),
        0,
        "交接返回时原握手 socket 已实际退出"
    );
    assert!(
        !registry()
            .lock()
            .unwrap()
            .handshakes
            .contains_key(&handshake)
    );
    assert!(!other_worker.is_finished());
    assert_eq!(
        adb_scoped_handshake_create(old.scope_id)
            .await
            .unwrap_err()
            .message,
        "adb_admission_scope_stale"
    );
    adb_admission_scope_close(other.scope_id, 1000)
        .await
        .unwrap();
    assert!(other_worker.await.unwrap().is_err());
    drop(other_peer);
    assert!(
        !registry()
            .lock()
            .unwrap()
            .handshakes
            .contains_key(&other_handshake)
    );
    adb_admission_scope_close(next.scope_id, 1000)
        .await
        .unwrap();
}

#[tokio::test]
async fn an_unconfirmed_real_connection_is_reclaimed_but_confirmed_clients_survive_takeover() {
    let old = scope().await;
    let (_handshake, worker, mut peer, _directory) = direct_connection(&old, false).await;
    let unconfirmed = worker.await.unwrap().unwrap();
    assert!(
        device(&unconfirmed.id).is_err(),
        "未确认结果不能先创建服务或捕获"
    );
    assert!(
        adb_claim_connection(unconfirmed.id.clone()).await.is_err(),
        "未确认结果不得绕过关闭责任被认领"
    );
    let next = adb_admission_scope_attach(old.scope_key.clone(), Some(old.scope_id), 1000)
        .await
        .unwrap();
    assert!(
        !registry()
            .lock()
            .unwrap()
            .connections
            .contains_key(&unconfirmed.id)
    );
    assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
    let (handshake, worker, _peer, _directory) = direct_connection(&next, false).await;
    let delivered = worker.await.unwrap().unwrap();
    adb_handshake_connection_confirm(handshake.clone(), delivered.id.clone())
        .await
        .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    let client = device(&delivered.id).unwrap();
    let last =
        adb_admission_scope_attach(next.scope_key.clone(), Some(next.scope_id.clone()), 1000)
            .await
            .unwrap();
    assert!(!client.is_closed());
    let claim = adb_scoped_handshake_create(last.scope_id.clone())
        .await
        .unwrap();
    let claimed = adb_scoped_connection_claim(delivered.id.clone(), claim.clone())
        .await
        .unwrap();
    assert_ne!(claimed.id, delivered.id);
    adb_handshake_connection_confirm(claim.clone(), claimed.id.clone())
        .await
        .unwrap();
    adb_handshake_close(claim).await.unwrap();
    adb_disconnect(delivered.id).await.unwrap();
    assert!(!client.is_closed(), "旧句柄的迟到清理不能关闭已认领的连接");
    adb_admission_scope_close(next.scope_id, 1000)
        .await
        .unwrap();
    assert!(!client.is_closed());
    adb_disconnect(claimed.id).await.unwrap();
    adb_admission_scope_close(last.scope_id, 1000)
        .await
        .unwrap();
}

#[tokio::test]
async fn concurrent_old_snapshots_have_one_successor_and_stale_close_is_harmless() {
    let old = scope().await;
    let (first, second) = tokio::join!(
        adb_admission_scope_attach(old.scope_key.clone(), Some(old.scope_id.clone()), 1000),
        adb_admission_scope_attach(old.scope_key.clone(), Some(old.scope_id.clone()), 1000),
    );
    let next = match (first, second) {
        (Ok(next), Err(error)) | (Err(error), Ok(next)) => {
            assert_eq!(error, "adb_admission_scope_stale");
            next
        }
        results => panic!("只能有一个旧快照成功认领：{results:?}"),
    };
    adb_admission_scope_close(old.scope_id, 1000).await.unwrap();
    assert_eq!(
        adb_admission_scope_inspect(old.scope_key)
            .unwrap()
            .unwrap()
            .scope_id,
        next.scope_id
    );
    adb_admission_scope_close(next.scope_id, 1000)
        .await
        .unwrap();
}

#[tokio::test]
async fn a_late_client_from_an_abandoned_waiter_remains_owned_until_driver_cleanup() {
    let old = scope().await;
    let handshake = adb_scoped_handshake_create(old.scope_id.clone())
        .await
        .unwrap();
    let (stream, mut peer) = tokio::io::duplex(1024);
    let client = Client::from_negotiated_transport(
        stream,
        interop_adb::DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let late = client.clone();
    let release = CancellationToken::new();
    let held = release.clone();
    let (started, ready) = tokio::sync::oneshot::channel();
    let result_id = handshake.clone();
    let waiter = tokio::spawn(handshake::run_connection(
        Some(handshake.clone()),
        move |_| async move {
            started.send(()).unwrap();
            held.cancelled().await;
            handshake::publish_connection(Some(&result_id), late, "late".into())
        },
    ));
    ready.await.unwrap();
    waiter.abort();
    assert!(matches!(waiter.await, Err(error) if error.is_cancelled()));
    assert!(
        adb_admission_scope_attach(old.scope_key.clone(), Some(old.scope_id.clone()), 20)
            .await
            .is_err()
    );
    release.cancel();
    let next = adb_admission_scope_attach(old.scope_key, Some(old.scope_id), 1000)
        .await
        .unwrap();
    assert!(client.is_closed());
    assert_eq!(peer.read(&mut [0]).await.unwrap(), 0);
    assert!(
        !registry()
            .lock()
            .unwrap()
            .handshakes
            .contains_key(&handshake)
    );
    adb_admission_scope_close(next.scope_id, 1000)
        .await
        .unwrap();
}

#[tokio::test]
async fn scope_provenance_follows_confirmed_delivery_not_physical_client_or_pending_claim() {
    let first = scope().await;
    let (handshake, worker, _peer, _directory) = direct_connection(&first, false).await;
    let original = worker.await.unwrap().unwrap();
    assert!(
        adb_connection_facts(original.id.clone())
            .unwrap()
            .admission_scope_key
            .is_none()
    );
    adb_handshake_connection_confirm(handshake.clone(), original.id.clone())
        .await
        .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    assert_eq!(
        adb_connection_facts(original.id.clone())
            .unwrap()
            .admission_scope_key,
        Some(first.scope_key.clone())
    );
    let client = device(&original.id).unwrap();
    let borrowed = insert_connection(client.clone(), "borrowed".into(), false).unwrap();
    assert!(
        adb_connection_facts(borrowed.id.clone())
            .unwrap()
            .admission_scope_key
            .is_none()
    );
    adb_disconnect(borrowed.id).await.unwrap();
    assert!(!client.is_closed());

    let second = scope().await;
    let handshake = adb_scoped_handshake_create(second.scope_id.clone())
        .await
        .unwrap();
    let claimed = adb_scoped_connection_claim(original.id.clone(), handshake.clone())
        .await
        .unwrap();
    assert_eq!(
        adb_connection_facts(claimed.id.clone())
            .unwrap()
            .admission_scope_key,
        Some(first.scope_key.clone()),
        "尚未确认的接管不提前变更归属事实"
    );
    adb_handshake_connection_confirm(handshake.clone(), claimed.id.clone())
        .await
        .unwrap();
    adb_handshake_close(handshake).await.unwrap();
    assert_eq!(
        adb_connection_facts(claimed.id.clone())
            .unwrap()
            .admission_scope_key,
        Some(second.scope_key.clone())
    );
    assert_eq!(
        adb_connection_facts(claimed.id.clone())
            .unwrap()
            .connection_id,
        client.connection_id().to_string()
    );
    adb_disconnect(original.id).await.unwrap();
    assert!(!client.is_closed());
    adb_disconnect(claimed.id).await.unwrap();
    adb_admission_scope_close(first.scope_id, 1000)
        .await
        .unwrap();
    adb_admission_scope_close(second.scope_id, 1000)
        .await
        .unwrap();
}
