//! 使用真实 ADB 流及显式采样时刻核验消费活动，不等待生产环境的 45 秒期限。
use super::*;
use crate::api::cleanup_tests::{connection, peer, raw};
use interop_adb::protocol::{self, Frame};
use std::{future::Future, task::Poll};

const IDLE: Duration = Duration::from_secs(45);

async fn frame(socket: &mut tokio::io::DuplexStream) -> Frame {
    tokio::time::timeout(
        Duration::from_secs(1),
        Frame::read(socket, protocol::MAX_PAYLOAD, true),
    )
    .await
    .unwrap()
    .unwrap()
}

#[tokio::test]
async fn recent_service_events_survive_idle_sampling_between_reads() {
    let (connection, client, mut socket, _) = connection();
    let (send_chunk, mut chunks) = mpsc::unbounded_channel::<Vec<u8>>();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(async move {
        let open = frame(&mut socket).await;
        assert_eq!(open.command, protocol::OPEN);
        Frame::new(protocol::OKAY, 7, open.arg0, [])
            .write(&mut socket)
            .await
            .unwrap();
        for _ in 0..2 {
            let bytes = chunks.recv().await.unwrap();
            Frame::new(protocol::WRTE, 7, open.arg0, bytes)
                .write(&mut socket)
                .await
                .unwrap();
            assert_eq!(frame(&mut socket).await.command, protocol::OKAY);
            notice.send(protocol::OKAY).unwrap();
        }
        assert_eq!(frame(&mut socket).await.command, protocol::CLSE);
        notice.send(protocol::CLSE).unwrap();
        while Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .is_ok()
        {}
    });
    let id = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    let op = registry().lock().unwrap().operations[&id].clone();
    for bytes in [b"first".to_vec(), b"second".to_vec()] {
        send_chunk.send(bytes.clone()).unwrap();
        let before_read = Instant::now();
        let event = adb_service_next(id.clone()).await.unwrap().unwrap();
        assert_eq!(event.bytes, bytes);
        assert_eq!(notices.recv().await, Some(protocol::OKAY));
        // reader 已释放，消费者在 Dart 处理当前事件；不到完整闲置期限不能撤销流。
        assert!(op.events.try_lock().is_ok());
        assert!(
            !reclaim_operation_if_idle(
                &id,
                &op,
                before_read + IDLE - Duration::from_nanos(1),
                IDLE,
                Duration::from_secs(1),
            )
            .await
        );
        assert!(!op.stop.is_cancelled());
    }
    adb_cancel(id).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn pending_service_reader_and_its_cancelled_wait_restart_idle_protection() {
    let (connection, client, socket, _) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let id = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    let op = registry().lock().unwrap().operations[&id].clone();
    let mut reading = Box::pin(adb_service_next(id.clone()));
    std::future::poll_fn(|context| {
        assert!(reading.as_mut().poll(context).is_pending());
        Poll::Ready(())
    })
    .await;
    assert!(
        !reclaim_operation_if_idle(
            &id,
            &op,
            Instant::now() + IDLE * 2,
            IDLE,
            Duration::from_secs(1),
        )
        .await
    );
    let before_drop = Instant::now();
    drop(reading);
    assert!(
        !reclaim_operation_if_idle(
            &id,
            &op,
            before_drop + IDLE - Duration::from_nanos(1),
            IDLE,
            Duration::from_secs(1),
        )
        .await
    );
    assert!(!op.stop.is_cancelled());
    adb_cancel(id).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn a_truly_idle_operation_closes_only_its_own_stream() {
    let (connection, client, socket, _) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let id = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    let other = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    let op = registry().lock().unwrap().operations[&id].clone();
    assert!(
        reclaim_operation_if_idle(
            &id,
            &op,
            Instant::now() + IDLE,
            IDLE,
            Duration::from_secs(1),
        )
        .await
    );
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    assert_eq!(
        adb_service_next(id).await.err().unwrap(),
        "adb_operation_closed"
    );
    adb_write(
        other.clone(),
        AdbInput {
            kind: AdbInputKind::Bytes,
            bytes: b"still-owned".to_vec(),
            rows: 0,
            columns: 0,
        },
    )
    .await
    .unwrap();
    assert_eq!(notices.recv().await, Some(protocol::WRTE));
    assert!(!client.is_closed());
    adb_cancel(other).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}

#[tokio::test]
async fn idle_cleanup_failure_retains_the_exact_operation_for_concurrent_retry() {
    let (connection, client, socket, writes) = connection();
    let (notice, mut notices) = mpsc::unbounded_channel();
    let serving = tokio::spawn(peer(socket, notice));
    let id = adb_service(connection.clone(), raw(), 5000).await.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::OPEN));
    let op = registry().lock().unwrap().operations[&id].clone();
    writes.pause();
    assert!(
        !reclaim_operation_if_idle(
            &id,
            &op,
            Instant::now() + IDLE,
            IDLE,
            Duration::from_millis(20),
        )
        .await
    );
    assert!(op.stop.is_cancelled());
    assert!(Arc::ptr_eq(
        &registry().lock().unwrap().operations[&id],
        &op,
    ));
    assert!(notices.try_recv().is_err(), "尚未写出的 CLSE 不能冒充完成");
    writes.resume();
    let (reclaimed, cancelled) = tokio::join!(
        reclaim_operation_if_idle(&id, &op, Instant::now(), IDLE, Duration::from_secs(1)),
        adb_cancel(id.clone()),
    );
    assert!(reclaimed);
    cancelled.unwrap();
    assert_eq!(notices.recv().await, Some(protocol::CLSE));
    assert!(!registry().lock().unwrap().operations.contains_key(&id));
    adb_disconnect(connection).await.unwrap();
    client.close();
    serving.await.unwrap();
}
