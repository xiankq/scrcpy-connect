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
    // One frame is blocked on the 256-byte transport and 64 fill the writer.
    tokio::time::sleep(Duration::from_millis(30)).await;
    (client, peer, consumer, tasks)
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
    // The second stream has a queued WRTE behind the currently blocked first.
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
    // With one frame in flight plus 64 queued, stream 66 is waiting for capacity.
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
    // The existing streams consumed IDs 1..=67. The next OPEN is waiting for
    // writer capacity, and its route must still obey a close for that local ID.
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
