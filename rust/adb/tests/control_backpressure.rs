use interop_adb::{
    AdbStream, Client, DeviceInfo, OperationOptions,
    protocol::{self, Frame},
};
use std::time::Duration;
use tokio::io::DuplexStream;

async fn saturated_writer() -> (
    Client,
    DuplexStream,
    AdbStream,
    Vec<tokio::task::JoinHandle<()>>,
) {
    let (transport, mut peer) = tokio::io::duplex(256);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 65536,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let mut streams = Vec::new();
    for _ in 0..67 {
        let opener = client.clone();
        let task = tokio::spawn(async move {
            opener
                .open("fixture:", OperationOptions::default())
                .await
                .unwrap()
        });
        let open = Frame::read(&mut peer, 65536, true).await.unwrap();
        Frame::new(protocol::OKAY, open.arg0 + 1000, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        streams.push(task.await.unwrap());
    }
    let consumer = streams.pop().unwrap();
    let tasks = streams
        .into_iter()
        .map(|mut stream| {
            tokio::spawn(async move {
                let _ = stream.write_all(&vec![42; 65536]).await;
            })
        })
        .collect();
    // 一个帧阻塞于 256 字节传输，另 64 个填满写队列。
    tokio::time::sleep(Duration::from_millis(30)).await;
    (client, peer, consumer, tasks)
}

#[tokio::test]
async fn priority_write_preempts_queued_normal_frames() {
    let (client, mut peer, mut consumer, tasks) = saturated_writer().await;
    consumer.set_write_priority(true).unwrap();
    let writing = tokio::spawn(async move { consumer.write_all(b"urgent").await.unwrap() });
    // 第一个大帧已开始写入有界传输；该传输完成后，小控制 WRTE 须先于主 FIFO 已等待的 64 个普通帧发送。
    let first = Frame::read(&mut peer, 65536, true).await.unwrap();
    assert_eq!(
        (first.command, first.payload.len()),
        (protocol::WRTE, 65536)
    );
    let second = Frame::read(&mut peer, 65536, true).await.unwrap();
    assert_eq!(second.command, protocol::WRTE);
    assert_eq!(second.payload, b"urgent");
    Frame::new(protocol::OKAY, second.arg0 + 1000, second.arg0, [])
        .write(&mut peer)
        .await
        .unwrap();
    writing.await.unwrap();
    client.close();
    for task in tasks {
        task.abort();
    }
}

#[tokio::test]
async fn ordered_close_follows_a_queued_priority_write_on_the_same_stream() {
    let (client, mut peer, mut consumer, tasks) = saturated_writer().await;
    consumer.set_write_priority(true).unwrap();
    // 优先 WRTE 排在阻塞的首帧之后，随后关闭同一流；CLSE 响应不能越过该 WRTE。
    let writing = tokio::spawn(async move {
        let _ = consumer.write_all(b"priority-tail").await;
        drop(consumer);
    });
    let result = tokio::time::timeout(Duration::from_secs(2), async {
        let mut saw_priority = false;
        loop {
            let frame = Frame::read(&mut peer, 65536, true).await.unwrap();
            if frame.command == protocol::CLSE {
                assert!(
                    saw_priority,
                    "ordered close overtook its same-stream priority WRTE"
                );
                break;
            }
            if frame.command == protocol::WRTE && frame.payload == b"priority-tail" {
                saw_priority = true;
                Frame::new(protocol::OKAY, frame.arg0 + 1000, frame.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
            }
        }
    })
    .await;
    client.close();
    for task in tasks {
        task.abort();
    }
    writing.abort();
    result.unwrap();
}

#[tokio::test]
async fn close_response_does_not_block_unrelated_inbound_data() {
    let (client, mut peer, mut consumer, tasks) = saturated_writer().await;
    Frame::new(protocol::CLSE, 1001, 1, [])
        .write(&mut peer)
        .await
        .unwrap();
    Frame::new(protocol::WRTE, 1067, 67, b"hello")
        .write(&mut peer)
        .await
        .unwrap();
    let mut buffer = [0; 5];
    let result =
        tokio::time::timeout(Duration::from_millis(300), consumer.read_exact(&mut buffer)).await;
    client.close();
    for task in tasks {
        task.abort();
    }
    result
        .expect("a saturated writer must not stall unrelated inbound routing")
        .unwrap();
    assert_eq!(&buffer, b"hello");
}

#[tokio::test]
async fn control_response_flood_is_bounded_and_closes_transport() {
    let (client, mut peer, _consumer, tasks) = saturated_writer().await;
    let flood = tokio::spawn(async move {
        for local in 1000..1400 {
            if Frame::new(protocol::OKAY, local + 1000, local, [])
                .write(&mut peer)
                .await
                .is_err()
            {
                break;
            }
        }
        peer
    });
    let result = tokio::time::timeout(Duration::from_millis(500), async {
        while !client.is_closed() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    let reason = client.close_reason();
    client.close();
    flood.abort();
    for task in tasks {
        task.abort();
    }
    result.expect("excess control responses must fail within a bounded queue");
    assert!(
        reason
            .unwrap_or_default()
            .contains("control response queue")
    );
}

#[tokio::test]
async fn remote_close_drains_classic_tail_while_writer_is_full() {
    let (client, mut peer, mut consumer, tasks) = saturated_writer().await;
    Frame::new(protocol::WRTE, 1067, 67, b"first")
        .write(&mut peer)
        .await
        .unwrap();
    Frame::new(protocol::WRTE, 1067, 67, b"tail")
        .write(&mut peer)
        .await
        .unwrap();
    Frame::new(protocol::CLSE, 1067, 67, [])
        .write(&mut peer)
        .await
        .unwrap();
    let result = tokio::time::timeout(Duration::from_millis(300), async {
        let mut bytes = [0; 9];
        consumer.read_exact(&mut bytes).await.unwrap();
        assert_eq!(&bytes, b"firsttail");
        assert_eq!(consumer.read(&mut [0; 1]).await.unwrap(), 0);
    })
    .await;
    client.close();
    for task in tasks {
        task.abort();
    }
    result.expect(
        "remote close must release pending ACK capacity waits while preserving queued tails",
    );
}

#[tokio::test]
async fn close_response_follows_already_queued_stream_write() {
    let (client, mut peer, _consumer, tasks) = saturated_writer().await;
    // 第二个流的 WRTE 排在当前阻塞的首帧之后。
    Frame::new(protocol::CLSE, 1002, 2, [])
        .write(&mut peer)
        .await
        .unwrap();
    let result = tokio::time::timeout(Duration::from_secs(2), async {
        let mut saw_write = false;
        loop {
            let frame = Frame::read(&mut peer, 65536, true).await.unwrap();
            if frame.arg0 == 2 {
                match frame.command {
                    protocol::WRTE => saw_write = true,
                    protocol::CLSE => {
                        assert!(saw_write, "CLSE overtook a queued WRTE on the same stream");
                        break;
                    }
                    _ => {}
                }
            }
        }
    })
    .await;
    client.close();
    for task in tasks {
        task.abort();
    }
    result.unwrap();
}

#[tokio::test]
async fn rejected_reverse_open_flood_is_bounded() {
    let (client, mut peer, _consumer, tasks) = saturated_writer().await;
    let flood = tokio::spawn(async move {
        for remote in 1000..1400 {
            if Frame::new(protocol::OPEN, remote, 0, b"unregistered;\0")
                .write(&mut peer)
                .await
                .is_err()
            {
                break;
            }
        }
        peer
    });
    let result = tokio::time::timeout(Duration::from_millis(500), async {
        while !client.is_closed() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    let reason = client.close_reason();
    client.close();
    flood.abort();
    for task in tasks {
        task.abort();
    }
    result.expect("unadmitted OPEN flood must fail within a bounded queue");
    assert!(
        reason
            .unwrap_or_default()
            .contains("control response queue")
    );
}

#[tokio::test]
async fn remote_close_wakes_writer_waiting_for_queue_capacity() {
    let (client, mut peer, _consumer, mut tasks) = saturated_writer().await;
    // 一个帧在途、64 个排队，流 66 正等待容量。
    Frame::new(protocol::CLSE, 1066, 66, [])
        .write(&mut peer)
        .await
        .unwrap();
    let mut pending_writer = tasks.pop().unwrap();
    let result = tokio::time::timeout(Duration::from_millis(300), &mut pending_writer).await;
    client.close();
    pending_writer.abort();
    for task in tasks {
        task.abort();
    }
    result
        .expect("CLSE must wake a stream writer even while the data queue is full")
        .unwrap();
}

#[tokio::test]
async fn remote_close_wakes_pending_open_without_sending_it_after_close() {
    let (client, mut peer, _consumer, tasks) = saturated_writer().await;
    let opener = client.clone();
    let mut pending_open =
        tokio::spawn(async move { opener.open("pending:", OperationOptions::default()).await });
    tokio::time::sleep(Duration::from_millis(30)).await;
    // 现有流已消耗 1..=67 的 ID；下一个 OPEN 正等待写队列容量，其路由仍须遵从针对该 local ID 的关闭。
    Frame::new(protocol::CLSE, 0, 68, [])
        .write(&mut peer)
        .await
        .unwrap();
    let result = tokio::time::timeout(Duration::from_millis(300), &mut pending_open).await;
    if result.is_err() {
        client.close();
        pending_open.abort();
        for task in tasks {
            task.abort();
        }
        panic!("CLSE must wake an OPEN waiting for data queue capacity");
    }
    assert!(matches!(
        result.unwrap().unwrap(),
        Err(interop_adb::Error::Closed)
    ));
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let frame = Frame::read(&mut peer, 65536, true).await.unwrap();
            assert!(
                !(frame.command == protocol::OPEN && frame.arg0 == 68),
                "closed OPEN was sent late"
            );
            if frame.command == protocol::CLSE && frame.arg0 == 68 {
                break;
            }
        }
        while let Ok(Ok(frame)) = tokio::time::timeout(
            Duration::from_millis(50),
            Frame::read(&mut peer, 65536, true),
        )
        .await
        {
            assert!(
                !(frame.command == protocol::OPEN && frame.arg0 == 68),
                "OPEN followed its CLSE response"
            );
        }
    })
    .await
    .unwrap();
    client.close();
    for task in tasks {
        task.abort();
    }
}

#[tokio::test]
async fn flush_closed_streams_waits_for_the_close_frame_before_cleanup_can_start() {
    let (client, mut peer, consumer, tasks) = saturated_writer().await;
    drop(consumer);
    let bounded = client
        .flush_closed_streams(OperationOptions {
            timeout: Duration::from_millis(20),
            ..Default::default()
        })
        .await;
    assert!(
        matches!(bounded, Err(interop_adb::Error::Timeout)),
        "写出关闭帧的等待必须有界"
    );
    let flushing = tokio::spawn({
        let client = client.clone();
        async move {
            client
                .flush_closed_streams(OperationOptions::default())
                .await
        }
    });
    tokio::task::yield_now().await;
    assert!(!flushing.is_finished(), "关闭帧尚未写出时不能开始清理");
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let frame = Frame::read(&mut peer, 65536, true).await.unwrap();
            if frame.command == protocol::CLSE && frame.arg0 == 67 {
                break;
            }
        }
        flushing.await.unwrap().unwrap();
    })
    .await
    .unwrap();
    client.close();
    for task in tasks {
        task.abort();
    }
}
