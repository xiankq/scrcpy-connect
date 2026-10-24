//! 接收诊断必须观察真实 ADB 缓冲，不能改变 ACK。
use interop_adb::{
    Client, DeviceInfo, OperationOptions,
    protocol::{self, Frame},
};
use std::{
    collections::HashSet,
    sync::{
        OnceLock,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};
use tokio::io::{AsyncWriteExt, DuplexStream};

static CALLS: AtomicUsize = AtomicUsize::new(0);
fn clock() -> u64 {
    CALLS.fetch_add(1, Ordering::Relaxed);
    static ORIGIN: OnceLock<Instant> = OnceLock::new();
    ORIGIN.get_or_init(Instant::now).elapsed().as_micros() as u64
}

async fn receive(peer: &mut DuplexStream) -> Frame {
    tokio::time::timeout(Duration::from_secs(2), Frame::read(peer, 4096, true))
        .await
        .unwrap()
        .unwrap()
}

#[tokio::test]
async fn stream_trace_observes_payload_receive_queue_and_partial_consumption() {
    CALLS.store(0, Ordering::Relaxed);
    let (transport, mut peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::\0".into(),
            features: HashSet::new(),
        },
    )
    .unwrap();
    let opener = client.clone();
    let task = tokio::spawn(async move {
        opener
            .open("localabstract:video", OperationOptions::default())
            .await
            .unwrap()
    });
    let open = receive(&mut peer).await;
    Frame::new(protocol::OKAY, 8, open.arg0, [])
        .write(&mut peer)
        .await
        .unwrap();
    let mut stream = task.await.unwrap();
    for traced in [false, true, false] {
        stream
            .set_read_trace_clock(traced.then_some(clock as fn() -> u64))
            .unwrap();
        let calls_before = CALLS.load(Ordering::Relaxed);
        let mut encoded = Vec::new();
        Frame::new(protocol::WRTE, 8, open.arg0, b"payload".to_vec())
            .write(&mut encoded)
            .await
            .unwrap();
        peer.write_all(&encoded[..25]).await.unwrap();
        // 头部及一个 payload 字节已到达，AdbStream 仍须等待完整 WRTE；不完整读取须可安全取消。
        let mut first = [0; 1];
        assert!(
            tokio::time::timeout(Duration::from_millis(30), stream.read(&mut first))
                .await
                .is_err()
        );
        peer.write_all(&encoded[25..]).await.unwrap();
        if traced {
            tokio::time::timeout(Duration::from_secs(1), async {
                while CALLS.load(Ordering::Relaxed) < calls_before + 3 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .unwrap();
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(stream.read(&mut first).await.unwrap(), 1);
        assert_eq!(&first, b"p");
        let receipt = stream.read_trace();
        if traced {
            let r = receipt.expect("enabled trace must observe the real payload read");
            assert_eq!(r.sequence, 1);
            assert_eq!(r.payload_bytes, 7);
            assert!(r.payload_read_us - r.payload_started_us >= 20_000);
            assert!(r.routed_us >= r.payload_read_us);
            assert!(r.first_consumed_us - r.routed_us >= 10_000);
        } else {
            assert!(receipt.is_none());
            assert_eq!(CALLS.load(Ordering::Relaxed), calls_before);
        }
        // 部分消费不能提前确认，也不能用下次读取的时钟值替换回执。
        assert!(
            tokio::time::timeout(Duration::from_millis(10), receive(&mut peer))
                .await
                .is_err()
        );
        let mut rest = [0; 6];
        stream.read_exact(&mut rest).await.unwrap();
        assert_eq!(&rest, b"ayload");
        if traced {
            assert_eq!(
                stream.read_trace().unwrap().first_consumed_us,
                receipt.unwrap().first_consumed_us
            );
        }
        assert_eq!(receive(&mut peer).await.command, protocol::OKAY);
    }
    stream.close().await.unwrap();
    client.close();
}

static OLD_CLOCK_CALLS: AtomicUsize = AtomicUsize::new(0);
static NEW_CLOCK_CALLS: AtomicUsize = AtomicUsize::new(0);
fn old_clock() -> u64 {
    1_000_000 + OLD_CLOCK_CALLS.fetch_add(1, Ordering::Relaxed) as u64
}
fn new_clock() -> u64 {
    2_000_000 + NEW_CLOCK_CALLS.fetch_add(1, Ordering::Relaxed) as u64
}

#[tokio::test]
async fn changing_trace_clock_discards_inflight_and_queued_receipts_but_keeps_bytes() {
    OLD_CLOCK_CALLS.store(0, Ordering::Relaxed);
    NEW_CLOCK_CALLS.store(0, Ordering::Relaxed);
    let (transport, mut peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::\0".into(),
            features: HashSet::new(),
        },
    )
    .unwrap();
    let opener = client.clone();
    let task = tokio::spawn(async move {
        opener
            .open("localabstract:video", OperationOptions::default())
            .await
            .unwrap()
    });
    let open = receive(&mut peer).await;
    Frame::new(protocol::OKAY, 8, open.arg0, [])
        .write(&mut peer)
        .await
        .unwrap();
    let mut stream = task.await.unwrap();
    stream.set_read_trace_clock(Some(old_clock)).unwrap();
    let mut packet = Vec::new();
    Frame::new(protocol::WRTE, 8, open.arg0, b"one".to_vec())
        .write(&mut packet)
        .await
        .unwrap();
    peer.write_all(&packet[..25]).await.unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while OLD_CLOCK_CALLS.load(Ordering::Relaxed) == 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    stream.set_read_trace_clock(Some(new_clock)).unwrap();
    peer.write_all(&packet[25..]).await.unwrap();
    let mut data = [0; 3];
    stream.read_exact(&mut data).await.unwrap();
    assert_eq!(&data, b"one");
    assert!(
        stream.read_trace().is_none(),
        "cannot re-label the previous clock's packet"
    );
    assert_eq!(NEW_CLOCK_CALLS.load(Ordering::Relaxed), 0);
    assert_eq!(receive(&mut peer).await.command, protocol::OKAY);

    Frame::new(protocol::WRTE, 8, open.arg0, b"two".to_vec())
        .write(&mut peer)
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while NEW_CLOCK_CALLS.load(Ordering::Relaxed) < 3 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    stream.set_read_trace_clock(None).unwrap();
    stream.read_exact(&mut data).await.unwrap();
    assert_eq!(&data, b"two");
    assert!(
        stream.read_trace().is_none(),
        "disabled traces cannot consume a queued receipt"
    );
    assert_eq!(NEW_CLOCK_CALLS.load(Ordering::Relaxed), 3);
    assert_eq!(receive(&mut peer).await.command, protocol::OKAY);
    stream.close().await.unwrap();
    client.close();
}
