//! Exercise the monitor's real teardown against a concurrently published Client.
use super::*;
use interop_adb::{DeviceInfo, protocol};
use std::{future::Future, task::Poll};
use tokio::io::DuplexStream;

fn connection() -> (Client, DuplexStream) {
    let (transport, peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::\0".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    (client, peer)
}

#[tokio::test]
async fn old_connection_cleanup_cannot_cancel_a_replacement_video_start() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut device = blank_device("127.0.0.1".into(), 9, "tcp");
    device.status = "connected".into();
    device.observation_wanted = false;
    // Only this test publishes a replacement; do not let the automatic connector
    // race the controlled interleaving after the monitor finishes its cleanup.
    device.auto_reconnect = false;
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let (old, _old_peer) = connection();
    runtime
        .connections
        .lock()
        .await
        .insert(id.clone(), old.clone());
    let old_cancel = CancellationToken::new();
    let _old_reservation = runtime
        .resource_admission
        .reserve_session(
            "old-video".into(),
            id.clone(),
            "old".into(),
            old_cancel.clone(),
        )
        .unwrap();

    // Teardown first invalidates observation state. Holding its existing lock
    // pins the real monitor after removal but before session cancellation.
    let observation = runtime.observations.lock().await;
    old.close();
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if !runtime.connections.lock().await.contains_key(&id)
                && runtime.device(&id).await.unwrap().status == "offline"
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("the monitor must reach the observation cleanup barrier");

    let (replacement, _replacement_peer) = connection();
    let token = CancellationToken::new();
    let attaching = runtime.attach_client(
        &id,
        replacement.clone(),
        Metadata::default(),
        &token,
        None,
        None,
    );
    tokio::pin!(attaching);
    let polled = std::future::poll_fn(|cx| Poll::Ready(attaching.as_mut().poll(cx))).await;
    assert!(polled.is_pending());
    let new_cancel = CancellationToken::new();
    let mut new_reservation = None;
    if runtime.client(&id).await.is_ok() {
        // This is exactly the admission start_session performs after obtaining
        // the newly published Client. It must survive the old monitor cleanup.
        new_reservation = Some(
            runtime
                .resource_admission
                .reserve_session(
                    "new-video".into(),
                    id.clone(),
                    "new".into(),
                    new_cancel.clone(),
                )
                .unwrap(),
        );
    }
    drop(observation);
    tokio::time::timeout(Duration::from_secs(5), &mut attaching)
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(5), old_cancel.cancelled())
        .await
        .unwrap();
    if new_reservation.is_none() {
        new_reservation = Some(
            runtime
                .resource_admission
                .reserve_session(
                    "new-video".into(),
                    id.clone(),
                    "new".into(),
                    new_cancel.clone(),
                )
                .unwrap(),
        );
    }
    assert!(
        !new_cancel.is_cancelled(),
        "old teardown cancelled video admitted on the replacement Client"
    );
    assert!(!replacement.is_closed());
    assert_eq!(runtime.device(&id).await.unwrap().status, "connected");
    replacement.close();
    drop(new_reservation);
}

#[tokio::test]
async fn disconnect_revokes_admission_and_serializes_only_its_own_replacement() {
    use tokio::io::AsyncReadExt;

    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut device = blank_device("127.0.0.1".into(), 9, "tcp");
    device.observation_wanted = false;
    device.status = "connected".into();
    let id = device.id.clone();
    let mut other = device.clone();
    other.id = "other-device".into();
    runtime.store.write().await.devices.extend([device, other]);
    let (old, mut old_peer) = connection();
    runtime.connections.lock().await.insert(id.clone(), old);
    let observation = runtime.observations.lock().await;
    let disconnecting = runtime.disconnect_device(&id, false);
    tokio::pin!(disconnecting);
    assert!(
        std::future::poll_fn(|cx| Poll::Ready(disconnecting.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    assert!(
        runtime.client(&id).await.is_err(),
        "disconnect must revoke old-client admission before waiting for cleanup"
    );
    let mut byte = [0];
    assert!(
        tokio::time::timeout(Duration::from_millis(25), old_peer.read(&mut byte))
            .await
            .is_err(),
        "detached transport must stay alive for existing owners' shutdown and artifact cleanup"
    );

    let (replacement, _peer) = connection();
    let token = CancellationToken::new();
    let attaching = runtime.attach_client(
        &id,
        replacement.clone(),
        Metadata::default(),
        &token,
        None,
        None,
    );
    tokio::pin!(attaching);
    assert!(
        std::future::poll_fn(|cx| Poll::Ready(attaching.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    assert!(
        runtime.client(&id).await.is_err(),
        "same-device publication must wait for old cleanup"
    );

    let (other_client, _other_peer) = connection();
    let other_token = CancellationToken::new();
    let other_attaching = runtime.attach_client(
        "other-device",
        other_client.clone(),
        Metadata::default(),
        &other_token,
        None,
        None,
    );
    tokio::pin!(other_attaching);
    assert!(
        std::future::poll_fn(|cx| Poll::Ready(other_attaching.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    assert!(
        runtime.client("other-device").await.is_ok(),
        "a different device must still publish while the first device cleans up"
    );
    drop(observation);
    let (disconnected, attached, other_attached) =
        tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(disconnecting, attaching, other_attaching)
        })
        .await
        .unwrap();
    disconnected.unwrap();
    attached.unwrap();
    other_attached.unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), old_peer.read(&mut byte))
            .await
            .unwrap()
            .unwrap(),
        0,
        "old transport closes after cleanup before the replacement is admitted"
    );
    assert_eq!(runtime.device(&id).await.unwrap().status, "connected");
    assert!(!replacement.is_closed());
    replacement.close();
    other_client.close();
}

#[tokio::test]
async fn replacement_before_monitor_cleanup_retires_old_admission_and_ignores_stale_scan() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut device = blank_device("127.0.0.1".into(), 9, "tcp");
    device.status = "connected".into();
    device.observation_wanted = false;
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let (old, _old_peer) = connection();
    runtime
        .connections
        .lock()
        .await
        .insert(id.clone(), old.clone());
    let old_cancel = CancellationToken::new();
    let _old_reservation = runtime
        .resource_admission
        .reserve_session(
            "old-video".into(),
            id.clone(),
            "old".into(),
            old_cancel.clone(),
        )
        .unwrap();
    old.close();
    let (replacement, _peer) = connection();
    runtime
        .attach_client(
            &id,
            replacement.clone(),
            Metadata::default(),
            &CancellationToken::new(),
            None,
            None,
        )
        .await
        .unwrap();
    assert!(
        old_cancel.is_cancelled(),
        "manual replacement must finish old activity cleanup even before the monitor runs"
    );
    let new_cancel = CancellationToken::new();
    let _new_reservation = runtime
        .resource_admission
        .reserve_session(
            "new-video".into(),
            id.clone(),
            "new".into(),
            new_cancel.clone(),
        )
        .unwrap();
    runtime.retire_closed_connection(&id).await.unwrap();
    assert!(
        !new_cancel.is_cancelled(),
        "a stale monitor scan cannot clean up the healthy replacement"
    );
    assert!(
        runtime
            .client(&id)
            .await
            .unwrap()
            .same_connection(&replacement)
    );
    assert_eq!(runtime.device(&id).await.unwrap().status, "connected");
    replacement.close();
}

#[tokio::test]
async fn cancelled_cleanup_must_finish_before_a_later_client_is_published() {
    for recover_without_client in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let mut device = blank_device("127.0.0.1".into(), 9, "tcp");
        device.status = "connected".into();
        device.observation_wanted = false;
        device.auto_reconnect = false;
        let id = device.id.clone();
        runtime.store.write().await.devices.push(device);
        let (old, _old_peer) = connection();
        runtime
            .connections
            .lock()
            .await
            .insert(id.clone(), old.clone());
        let old_cancel = CancellationToken::new();
        let _old_reservation = runtime
            .resource_admission
            .reserve_session(
                "old-video".into(),
                id.clone(),
                "old".into(),
                old_cancel.clone(),
            )
            .unwrap();
        let observation = runtime.observations.lock().await;
        old.close();
        let (cancelled_client, _cancelled_peer) = connection();
        let cancelled_token = CancellationToken::new();
        let mut cancelled = Box::pin(runtime.attach_client(
            &id,
            cancelled_client.clone(),
            Metadata::default(),
            &cancelled_token,
            None,
            None,
        ));
        assert!(
            std::future::poll_fn(|cx| Poll::Ready(cancelled.as_mut().poll(cx)))
                .await
                .is_pending()
        );
        assert!(!runtime.connections.lock().await.contains_key(&id));
        assert!(
            !old_cancel.is_cancelled(),
            "cleanup is pinned before session cancellation"
        );
        drop(cancelled); // The public caller's timeout drops this future.
        cancelled_client.close();

        if recover_without_client {
            drop(observation);
            tokio::time::timeout(Duration::from_secs(5), old_cancel.cancelled())
            .await
            .expect("the real monitor must resume orphaned cleanup without another connection attempt");
            assert!(runtime.client(&id).await.is_err());
            continue;
        }

        let (replacement, _replacement_peer) = connection();
        let token = CancellationToken::new();
        let mut attaching = Box::pin(runtime.attach_client(
            &id,
            replacement.clone(),
            Metadata::default(),
            &token,
            None,
            None,
        ));
        assert!(
            std::future::poll_fn(|cx| Poll::Ready(attaching.as_mut().poll(cx)))
                .await
                .is_pending()
        );
        let published_early = runtime.client(&id).await.is_ok();
        drop(observation);
        tokio::time::timeout(Duration::from_secs(5), attaching)
            .await
            .unwrap()
            .unwrap();
        assert!(
            !published_early,
            "a cancelled cleanup cannot admit a new Client before finishing old activities"
        );
        assert!(
            old_cancel.is_cancelled(),
            "the interrupted cleanup must be retried, not forgotten after removal"
        );
        assert!(!replacement.is_closed());
        replacement.close();
    }
}

#[tokio::test]
async fn cancelled_disconnect_closes_detached_transport_and_preserves_cleanup() {
    use tokio::io::AsyncReadExt;

    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let mut device = blank_device("127.0.0.1".into(), 9, "tcp");
    device.status = "connected".into();
    device.observation_wanted = false;
    let id = device.id.clone();
    runtime.store.write().await.devices.push(device);
    let (old, mut peer) = connection();
    runtime
        .connections
        .lock()
        .await
        .insert(id.clone(), old.clone());
    let cancel = CancellationToken::new();
    let _reservation = runtime
        .resource_admission
        .reserve_session("old-video".into(), id.clone(), "old".into(), cancel.clone())
        .unwrap();
    let observation = runtime.observations.lock().await;
    let mut disconnecting = Box::pin(runtime.disconnect_device(&id, false));
    assert!(
        std::future::poll_fn(|cx| Poll::Ready(disconnecting.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    assert!(runtime.client(&id).await.is_err());
    assert!(!old.is_closed());
    drop(disconnecting);
    assert!(
        old.is_closed(),
        "dropping the caller must close the exact detached Client"
    );
    let mut byte = [0];
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), peer.read(&mut byte))
            .await
            .unwrap()
            .unwrap(),
        0
    );
    drop(observation);
    tokio::time::timeout(Duration::from_secs(5), cancel.cancelled())
        .await
        .unwrap();
    assert!(
        !runtime.device(&id).await.unwrap().auto_reconnect,
        "cancelled disconnect cannot restore automatic connection intent"
    );
}
