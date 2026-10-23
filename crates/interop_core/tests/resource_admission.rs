use interop_core::resource::{APP_SESSION_LIMIT, BusyReason, ResourceAdmission, ResourceStatus};
use std::{num::NonZeroUsize, sync::Arc, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{Barrier, mpsc, oneshot},
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn simultaneous_network_startups_reserve_before_io_and_never_cross_the_app_guard() {
    tokio::time::timeout(Duration::from_secs(10), async {
        let admission = ResourceAdmission::default();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let (connected_tx, mut connected_rx) = mpsc::unbounded_channel();
        let (release_tx, release_rx) = oneshot::channel();
        let server = tokio::spawn(async move {
            let mut sockets = Vec::new();
            for _ in 0..APP_SESSION_LIMIT {
                sockets.push(listener.accept().await.unwrap().0);
                connected_tx.send(()).unwrap();
            }
            release_rx.await.unwrap();
            for mut socket in sockets {
                socket.write_all(&[1]).await.unwrap();
            }
            assert!(
                tokio::time::timeout(Duration::from_millis(50), listener.accept())
                    .await
                    .is_err()
            );
        });
        let barrier = Arc::new(Barrier::new(65));
        let (attempt_tx, mut attempt_rx) = mpsc::unbounded_channel();
        let mut workers = JoinSet::new();
        for index in 0..64 {
            let admission = admission.clone();
            let barrier = barrier.clone();
            let attempt_tx = attempt_tx.clone();
            workers.spawn(async move {
                barrier.wait().await;
                let id = format!("session:{index}");
                let reservation = admission.reserve_session(
                    id.clone(),
                    "device-a".into(),
                    format!("window {index}"),
                    CancellationToken::new(),
                );
                match reservation {
                    Ok(_reservation) => {
                        attempt_tx.send(Ok(id.clone())).unwrap();
                        let mut socket = TcpStream::connect(address).await.unwrap();
                        assert_eq!(socket.read_u8().await.unwrap(), 1);
                        admission.set_status(&id, ResourceStatus::Streaming);
                    }
                    Err(busy) => {
                        attempt_tx.send(Err(busy)).unwrap();
                    }
                }
            });
        }
        barrier.wait().await;
        let mut admitted = 0;
        let mut rejected = 0;
        for _ in 0..64 {
            match attempt_rx.recv().await.unwrap() {
                Ok(_) => admitted += 1,
                Err(busy) => {
                    rejected += 1;
                    assert_eq!(busy.reason, BusyReason::AppSessionGuard);
                    assert_eq!(busy.activities.len(), APP_SESSION_LIMIT);
                    assert!(
                        busy.activities
                            .iter()
                            .all(|activity| activity.reserved && activity.preserved)
                    );
                    assert!(!busy.hardware_capacity_known);
                    assert!(!busy.pause_releases_reservation);
                }
            }
        }
        for _ in 0..APP_SESSION_LIMIT {
            connected_rx.recv().await.unwrap();
        }
        assert_eq!((admitted, rejected), (16, 48));
        assert!(
            admission
                .activities()
                .iter()
                .all(|activity| activity.status == ResourceStatus::Starting && !activity.can_pause)
        );
        release_tx.send(()).unwrap();
        while let Some(result) = workers.join_next().await {
            result.unwrap();
        }
        server.await.unwrap();
        assert!(admission.activities().is_empty());
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn abort_while_waiting_for_real_network_input_drops_only_the_new_reservation() {
    let admission = ResourceAdmission::new(NonZeroUsize::new(2).unwrap());
    let important = CancellationToken::new();
    let _old = admission
        .reserve_session(
            "session:important".into(),
            "device-a".into(),
            "existing task".into(),
            important.clone(),
        )
        .unwrap();
    admission.set_status("session:important", ResourceStatus::Streaming);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let attempt_admission = admission.clone();
    let cancelled = CancellationToken::new();
    let attempt_cancelled = cancelled.clone();
    let worker = tokio::spawn(async move {
        let _reservation = attempt_admission
            .reserve_session(
                "session:new".into(),
                "device-b".into(),
                "new task".into(),
                attempt_cancelled,
            )
            .unwrap();
        let mut socket = TcpStream::connect(address).await.unwrap();
        socket.read_u8().await
    });
    let (_server_socket, _) = listener.accept().await.unwrap();
    assert_eq!(admission.activities().len(), 2);
    worker.abort();
    assert!(worker.await.unwrap_err().is_cancelled());
    assert!(cancelled.is_cancelled());
    assert!(!important.is_cancelled());
    let activities = admission.activities();
    assert_eq!(activities.len(), 1);
    assert_eq!(activities[0].id, "session:important");
    assert_eq!(activities[0].device_id, "device-a");
    assert_eq!(activities[0].status, ResourceStatus::Streaming);
}

#[tokio::test]
async fn failed_encoded_start_releases_capacity_without_replacing_the_existing_identity() {
    let admission = ResourceAdmission::new(NonZeroUsize::new(2).unwrap());
    let important = CancellationToken::new();
    let _old = admission
        .reserve_session(
            "session:important".into(),
            "device-a".into(),
            "existing task".into(),
            important.clone(),
        )
        .unwrap();
    admission.set_status("session:important", ResourceStatus::Paused);
    let original = admission.activities();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        drop(socket);
    });
    let failure = async {
        let _reservation = admission
            .reserve_session(
                "session:failing".into(),
                "device-b".into(),
                "failed request".into(),
                CancellationToken::new(),
            )
            .unwrap();
        let mut socket = TcpStream::connect(address).await?;
        socket.read_u8().await
    }
    .await
    .unwrap_err();
    assert_eq!(failure.kind(), std::io::ErrorKind::UnexpectedEof);
    server.await.unwrap();
    assert_eq!(admission.activities(), original);
    assert!(!important.is_cancelled());
    let _retry = admission
        .reserve_session(
            "session:next".into(),
            "device-b".into(),
            "next request".into(),
            CancellationToken::new(),
        )
        .unwrap();
}

#[test]
fn duplicate_identity_and_device_cancellation_cannot_replace_or_stop_other_activities() {
    let admission = ResourceAdmission::new(NonZeroUsize::new(2).unwrap());
    let important = CancellationToken::new();
    let _old = admission
        .reserve_session(
            "session:important".into(),
            "device-a".into(),
            "original".into(),
            important.clone(),
        )
        .unwrap();
    admission.set_status("session:important", ResourceStatus::Streaming);
    let replacement = CancellationToken::new();
    let error = admission
        .reserve_session(
            "session:important".into(),
            "device-b".into(),
            "replacement".into(),
            replacement.clone(),
        )
        .err()
        .unwrap();
    assert_eq!(error.reason, BusyReason::ActivityAlreadyReserved);
    assert_eq!(admission.activities()[0].name, "original");
    assert!(!important.is_cancelled());
    assert!(!replacement.is_cancelled());
    let cancelled = CancellationToken::new();
    let pending = admission
        .reserve_session(
            "session:pending".into(),
            "device-b".into(),
            "pending".into(),
            cancelled.clone(),
        )
        .unwrap();
    admission.cancel_device("device-b");
    assert!(cancelled.is_cancelled());
    assert!(!important.is_cancelled());
    assert_eq!(admission.activities().len(), 2, "teardown retains capacity");
    admission.set_status("session:pending", ResourceStatus::Streaming);
    assert_eq!(admission.activities()[1].status, ResourceStatus::Stopping);
    drop(pending);
    assert_eq!(admission.activities().len(), 1);
    assert!(admission.activities()[0].can_pause);
    assert!(!admission.cancel("session:unknown"));
}
