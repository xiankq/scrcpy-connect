//! Exercise public Client/Sync against a classic ADB peer, parsing the SYNC
//! byte stream independently of its WRTE boundaries.
use interop_adb::{
    CancellationToken, Client, DeviceInfo, Error, OperationOptions,
    protocol::{self, Frame},
    sync::{Compression, RemotePath},
};
use std::{
    collections::HashSet,
    io,
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    task::{Context, Poll},
    time::Duration,
};
use tokio::io::{AsyncRead, DuplexStream, ReadBuf};

fn options() -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(3),
        ..Default::default()
    }
}

fn connection(max_payload: usize, features: &[&str]) -> (Client, DuplexStream) {
    let (transport, peer) = tokio::io::duplex(2 * 1024 * 1024);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload,
            banner: "device::".into(),
            features: features
                .iter()
                .map(|s| (*s).to_owned())
                .collect::<HashSet<_>>(),
        },
    )
    .unwrap();
    (client, peer)
}

struct Peer {
    socket: DuplexStream,
    host: u32,
    bytes: Vec<u8>,
    writes: Vec<usize>,
    max_payload: usize,
}

impl Peer {
    async fn open(mut socket: DuplexStream, max_payload: usize) -> Self {
        let open = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        assert_eq!(open.command, protocol::OPEN);
        assert_eq!(open.payload, b"sync:\0");
        Frame::new(protocol::OKAY, 7, open.arg0, [])
            .write(&mut socket)
            .await
            .unwrap();
        Self {
            socket,
            host: open.arg0,
            bytes: vec![],
            writes: vec![],
            max_payload,
        }
    }

    async fn take(&mut self, count: usize) -> Vec<u8> {
        while self.bytes.len() < count {
            let frame = Frame::read(&mut self.socket, protocol::MAX_PAYLOAD, true)
                .await
                .unwrap();
            if frame.command == protocol::OKAY {
                continue;
            }
            assert_eq!(frame.command, protocol::WRTE);
            assert_eq!((frame.arg0, frame.arg1), (self.host, 7));
            assert!(frame.payload.len() <= self.max_payload);
            self.writes.push(frame.payload.len());
            self.bytes.extend(frame.payload);
            Frame::new(protocol::OKAY, 7, self.host, [])
                .write(&mut self.socket)
                .await
                .unwrap();
        }
        self.bytes.drain(..count).collect()
    }

    async fn request(&mut self, id: &[u8; 4]) -> Vec<u8> {
        let header = self.take(8).await;
        assert_eq!(&header[..4], id);
        self.take(u32::from_le_bytes(header[4..].try_into().unwrap()) as usize)
            .await
    }

    async fn pushed(&mut self, expected: &[u8]) {
        assert_eq!(self.request(b"SEND").await, b"/fixture,33152");
        let mut received = Vec::new();
        loop {
            let header = self.take(8).await;
            let value = u32::from_le_bytes(header[4..].try_into().unwrap());
            if &header[..4] == b"DONE" {
                assert_eq!(value, 42);
                break;
            }
            assert_eq!(&header[..4], b"DATA");
            assert!(
                value > 0 && value <= 64 * 1024,
                "SYNC DATA exceeds the protocol limit"
            );
            received.extend(self.take(value as usize).await);
        }
        assert_eq!(received, expected);
        assert!(self.bytes.is_empty());
        self.reply(b"OKAY\0\0\0\0").await;
    }

    async fn reply(&mut self, bytes: &[u8]) {
        Frame::new(protocol::WRTE, 7, self.host, bytes)
            .write(&mut self.socket)
            .await
            .unwrap();
    }

    async fn closed(&mut self) {
        loop {
            let frame = Frame::read(&mut self.socket, protocol::MAX_PAYLOAD, true)
                .await
                .unwrap();
            if frame.command == protocol::OKAY {
                continue;
            }
            assert_eq!(
                frame.command,
                protocol::CLSE,
                "unexpected data after operation ended"
            );
            assert_eq!(frame.arg0, self.host);
            break;
        }
    }
}

async fn push_case(size: usize, max_payload: usize, expected_writes: usize) {
    let (client, socket) = connection(max_payload, &[]);
    let contents: Vec<u8> = (0..size).map(|n| (n % 251) as u8).collect();
    let expected = contents.clone();
    let server = tokio::spawn(async move {
        let mut peer = Peer::open(socket, max_payload).await;
        peer.pushed(&expected).await;
        let writes = peer.writes.clone();
        peer.closed().await;
        writes
    });
    let mut sync = client.sync(options()).await.unwrap();
    assert_eq!(
        sync.push(
            &RemotePath::new("/fixture").unwrap(),
            &mut contents.as_slice(),
            0o600,
            42,
            size as u64
        )
        .await
        .unwrap(),
        size as u64
    );
    drop(sync);
    let writes = server.await.unwrap();
    assert_eq!(writes.len(), expected_writes, "WRTE lengths: {writes:?}");
    // All non-final WRTEs use the negotiated payload, even when a DATA
    // record straddles two transport frames.
    assert!(writes[..writes.len() - 1].iter().all(|n| *n == max_payload));
}

#[tokio::test]
async fn small_file_coalesces_send_data_done() {
    push_case(1024, 1024 * 1024, 1).await;
    push_case(1024, 4096, 1).await;
}

#[tokio::test]
async fn empty_file_coalesces_send_done() {
    push_case(0, 1024 * 1024, 1).await;
}

#[tokio::test]
async fn large_file_keeps_64k_data_and_uses_two_max_payload_writes() {
    push_case(1024 * 1024, 1024 * 1024, 2).await;
}

#[tokio::test]
async fn legacy_4k_payload_splits_records_without_changing_sync_data() {
    // SEND header/path + two DATA headers + file + DONE header.
    let wire_size: usize = 8 + 14 + 2 * 8 + 70_000 + 8;
    push_case(70_000, 4096, wire_size.div_ceil(4096)).await;
}

/// Produce a small buffered prefix, then stop or fail before EOF.
struct InterruptedInput {
    prefix: bool,
    fail: bool,
}
impl AsyncRead for InterruptedInput {
    fn poll_read(
        mut self: Pin<&mut Self>,
        _: &mut Context<'_>,
        out: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if !self.prefix {
            self.prefix = true;
            out.put_slice(b"unfinished input");
            return Poll::Ready(Ok(()));
        }
        if self.fail {
            Poll::Ready(Err(io::Error::other("fixture input failed")))
        } else {
            Poll::Pending
        }
    }
}

#[tokio::test]
async fn input_failure_cancellation_and_timeout_discard_buffered_tail() {
    for reason in ["failure", "cancel", "timeout"] {
        let (client, socket) = connection(1024 * 1024, &[]);
        let token = CancellationToken::new();
        let operation = OperationOptions {
            cancellation: token.clone(),
            timeout: if reason == "timeout" {
                Duration::from_millis(30)
            } else {
                Duration::from_secs(3)
            },
        };
        let (closed, closed_on_wire) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let mut peer = Peer::open(socket, 1024 * 1024).await;
            peer.closed().await;
            closed.send(()).unwrap();
            // The connection stays usable and closes only the failed sync.
            let open = Frame::read(&mut peer.socket, protocol::MAX_PAYLOAD, true)
                .await
                .unwrap();
            assert_eq!(open.command, protocol::OPEN);
            assert_eq!(open.payload, b"shell:echo alive\0");
            Frame::new(protocol::OKAY, 8, open.arg0, [])
                .write(&mut peer.socket)
                .await
                .unwrap();
            loop {
                let frame = Frame::read(&mut peer.socket, protocol::MAX_PAYLOAD, true)
                    .await
                    .unwrap();
                assert_ne!(
                    frame.command,
                    protocol::WRTE,
                    "discarded sync data must never be flushed"
                );
                if frame.command == protocol::CLSE {
                    break;
                }
            }
        });
        let mut sync = client.sync(operation).await.unwrap();
        if reason == "cancel" {
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_millis(30)).await;
                token.cancel();
            });
        }
        let error = sync
            .push(
                &RemotePath::new("/fixture").unwrap(),
                &mut InterruptedInput {
                    prefix: false,
                    fail: reason == "failure",
                },
                0o600,
                42,
                100,
            )
            .await
            .unwrap_err();
        match reason {
            "failure" => assert!(matches!(error, Error::Io(_))),
            "cancel" => assert!(matches!(error, Error::Cancelled)),
            "timeout" => assert!(matches!(error, Error::Timeout)),
            _ => unreachable!(),
        }
        assert!(matches!(
            sync.stat(&RemotePath::new("/fixture").unwrap()).await,
            Err(Error::Closed)
        ));
        drop(sync);
        closed_on_wire.await.unwrap();
        let stream = client.open("shell:echo alive", options()).await.unwrap();
        drop(stream);
        server.await.unwrap();
    }
}

struct GeneratedInput(Arc<AtomicUsize>);
impl AsyncRead for GeneratedInput {
    fn poll_read(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        out: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let count = out.remaining();
        out.initialize_unfilled().fill(42);
        out.advance(count);
        self.0.fetch_add(count, Ordering::SeqCst);
        Poll::Ready(Ok(()))
    }
}

#[tokio::test]
async fn streaming_input_is_bounded_by_one_payload_and_one_data_record() {
    let max_payload = 1024 * 1024;
    let (client, mut socket) = connection(max_payload, &[]);
    let consumed = Arc::new(AtomicUsize::new(0));
    let observed = consumed.clone();
    let token = CancellationToken::new();
    let cancel = token.clone();
    let server = tokio::spawn(async move {
        let open = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        Frame::new(protocol::OKAY, 7, open.arg0, [])
            .write(&mut socket)
            .await
            .unwrap();
        let frame = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        assert_eq!(frame.command, protocol::WRTE);
        assert_eq!(frame.payload.len(), max_payload);
        assert!(observed.load(Ordering::SeqCst) <= max_payload + 64 * 1024);
        // Withhold classic ACK: reading the source must stop at this bounded
        // buffer, and cancellation must abandon the partial DATA record.
        cancel.cancel();
        let close = Frame::read(&mut socket, protocol::MAX_PAYLOAD, true)
            .await
            .unwrap();
        assert_eq!(close.command, protocol::CLSE);
        assert_eq!(close.arg0, open.arg0);
    });
    let mut sync = client
        .sync(OperationOptions {
            cancellation: token,
            ..options()
        })
        .await
        .unwrap();
    assert!(matches!(
        sync.push(
            &RemotePath::new("/fixture").unwrap(),
            &mut GeneratedInput(consumed),
            0o600,
            42,
            u64::MAX
        )
        .await,
        Err(Error::Cancelled)
    ));
    drop(sync);
    server.await.unwrap();
}

#[tokio::test]
async fn dropping_a_push_future_and_sync_does_not_send_buffered_data() {
    let (client, socket) = connection(1024 * 1024, &[]);
    let server = tokio::spawn(async move {
        let mut peer = Peer::open(socket, 1024 * 1024).await;
        peer.closed().await;
    });
    let mut sync = client.sync(options()).await.unwrap();
    let path = RemotePath::new("/fixture").unwrap();
    let mut input = InterruptedInput {
        prefix: false,
        fail: false,
    };
    assert!(
        tokio::time::timeout(
            Duration::from_millis(30),
            sync.push(&path, &mut input, 0o600, 42, 100)
        )
        .await
        .is_err()
    );
    assert!(matches!(sync.stat(&path).await, Err(Error::Closed)));
    drop(sync);
    server.await.unwrap();
}

#[tokio::test]
async fn v2_metadata_errors_retain_errno_and_close_the_failed_sync_stream() {
    for operation in ["stat", "list"] {
        let (client, socket) = connection(4096, &["stat_v2", "ls_v2"]);
        let server = tokio::spawn(async move {
            let mut peer = Peer::open(socket, 4096).await;
            let (request, response, body_len) = if operation == "stat" {
                (b"STA2", b"STA2", 68)
            } else {
                (b"LIS2", b"DNT2", 72)
            };
            assert_eq!(peer.request(request).await, b"/fixture");
            let mut bytes = response.to_vec();
            bytes.extend(2u32.to_le_bytes());
            bytes.resize(4 + body_len, 0);
            peer.reply(&bytes).await;
            peer.closed().await;
        });
        let mut sync = client.sync(options()).await.unwrap();
        let path = RemotePath::new("/fixture").unwrap();
        let error = if operation == "stat" {
            sync.stat(&path).await.unwrap_err()
        } else {
            sync.list(&path, 1).await.unwrap_err()
        };
        assert!(
            matches!(error, Error::RemoteErrno { operation: actual, errno: 2 } if actual == operation)
        );
        assert!(matches!(sync.stat(&path).await, Err(Error::Closed)));
        drop(sync);
        server.await.unwrap();
    }
}

#[tokio::test]
async fn compressed_setup_and_read_requests_flush_and_allow_sync_reuse() {
    let (client, socket) = connection(1024 * 1024, &["sendrecv_v2", "sendrecv_v2_lz4"]);
    let server = tokio::spawn(async move {
        let mut peer = Peer::open(socket, 1024 * 1024).await;
        assert_eq!(peer.request(b"SND2").await, b"/fixture");
        let setup = peer.take(12).await;
        assert_eq!(&setup[..4], b"SND2");
        assert_eq!(
            u32::from_le_bytes(setup[4..8].try_into().unwrap()),
            0o100600
        );
        assert_eq!(u32::from_le_bytes(setup[8..].try_into().unwrap()), 2);
        let mut compressed = vec![];
        loop {
            let header = peer.take(8).await;
            let value = u32::from_le_bytes(header[4..].try_into().unwrap());
            if &header[..4] == b"DONE" {
                assert_eq!(value, 42);
                break;
            }
            assert_eq!(&header[..4], b"DATA");
            assert!(value <= 64 * 1024);
            compressed.extend(peer.take(value as usize).await);
        }
        let decoded =
            io::read_to_string(lz4_flex::frame::FrameDecoder::new(compressed.as_slice())).unwrap();
        assert_eq!(decoded, "compressed fixture");
        peer.reply(b"OKAY\0\0\0\0").await;
        // A read request must reach the peer immediately; waiting for more
        // writes here would deadlock the host on the stat response.
        assert_eq!(peer.request(b"STAT").await, b"/fixture");
        let mut stat = b"STAT".to_vec();
        for word in [0o100600u32, 18, 42] {
            stat.extend(word.to_le_bytes());
        }
        peer.reply(&stat).await;
        assert_eq!(peer.request(b"LIST").await, b"/fixture");
        let mut listing = b"DONE".to_vec();
        listing.extend([0; 16]);
        peer.reply(&listing).await;
        assert_eq!(peer.request(b"RCV2").await, b"/fixture");
        let setup = peer.take(8).await;
        assert_eq!(&setup[..4], b"RCV2");
        assert_eq!(u32::from_le_bytes(setup[4..].try_into().unwrap()), 2);
        let mut data = b"DATA".to_vec();
        data.extend((compressed.len() as u32).to_le_bytes());
        data.extend(compressed);
        data.extend(b"DONE\0\0\0\0");
        peer.reply(&data).await;
        peer.closed().await;
    });
    let mut sync = client.sync(options()).await.unwrap();
    let path = RemotePath::new("/fixture").unwrap();
    assert_eq!(
        sync.push_compressed(
            &path,
            &mut b"compressed fixture".as_slice(),
            0o600,
            42,
            100,
            Compression::Lz4
        )
        .await
        .unwrap(),
        18
    );
    assert_eq!(sync.stat(&path).await.unwrap().size, 18);
    assert!(sync.list(&path, 1).await.unwrap().is_empty());
    let mut output = vec![];
    assert_eq!(
        sync.pull_compressed(&path, &mut output, 100, Compression::Lz4)
            .await
            .unwrap(),
        18
    );
    assert_eq!(output, b"compressed fixture");
    drop(sync);
    server.await.unwrap();
}
