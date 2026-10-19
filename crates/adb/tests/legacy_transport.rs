//! Compatibility fixtures for the 1.0.0 wire protocol used by older adbd.
use interop_adb::{
    Client, ConnectOptions, Identity, OperationOptions,
    protocol::{self, Frame},
};
use std::time::Duration;
use tokio::io::DuplexStream;

fn options() -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(3),
        ..Default::default()
    }
}

async fn read(peer: &mut DuplexStream) -> Frame {
    // Legacy adbd verifies checksums and accepts only 4 KiB payloads.
    Frame::read(peer, 4096, false).await.unwrap()
}

async fn send(peer: &mut DuplexStream, command: u32, arg0: u32, arg1: u32, payload: &[u8]) {
    Frame::new(command, arg0, arg1, payload.to_vec())
        .write(peer)
        .await
        .unwrap();
}

async fn connect_banner(peer: &mut DuplexStream) {
    let connect = read(peer).await;
    assert_eq!(connect.command, protocol::CNXN);
    assert!(connect.arg0 >= protocol::LEGACY_VERSION);
    assert!(connect.payload.len() <= 4096);
    legacy_banner(peer).await;
}

async fn legacy_banner(peer: &mut DuplexStream) {
    send(
        peer,
        protocol::CNXN,
        protocol::LEGACY_VERSION,
        4096,
        b"device::ro.product.model=Legacy;\0",
    )
    .await;
}

#[tokio::test]
async fn legacy_zero_id_close_preserves_tail_and_other_streams() {
    let (transport, mut peer) = tokio::io::duplex(64 * 1024);
    let (finish, finished) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        connect_banner(&mut peer).await;
        let first = read(&mut peer).await;
        send(&mut peer, protocol::OKAY, 41, first.arg0, &[]).await;
        let second = read(&mut peer).await;
        send(&mut peer, protocol::OKAY, 42, second.arg0, &[]).await;
        send(&mut peer, protocol::WRTE, 41, first.arg0, b"tail").await;
        // Older adbd versions also used zero sender IDs for ordinary closes.
        send(&mut peer, protocol::CLSE, 0, first.arg0, &[]).await;
        send(&mut peer, protocol::WRTE, 42, second.arg0, b"alive").await;
        let mut closed = false;
        let mut acknowledged = false;
        while !closed || !acknowledged {
            let frame = read(&mut peer).await;
            if frame.command == protocol::CLSE && frame.arg0 == first.arg0 {
                assert_eq!(frame.arg1, 41);
                closed = true;
            }
            if frame.command == protocol::OKAY && frame.arg1 == 42 {
                acknowledged = true;
            }
        }
        finished.await.unwrap();
    });
    let client = Client::connect_transport(transport, ConnectOptions::default())
        .await
        .unwrap();
    assert_eq!(client.info().version, protocol::LEGACY_VERSION);
    assert_eq!(client.info().max_payload, 4096);
    let mut first = client.open("shell:first", options()).await.unwrap();
    let mut second = client.open("shell:second", options()).await.unwrap();
    let mut tail = [0; 4];
    first.read_exact(&mut tail).await.unwrap();
    assert_eq!(&tail, b"tail");
    assert_eq!(first.read(&mut [0; 1]).await.unwrap(), 0);
    let mut alive = [0; 5];
    second.read_exact(&mut alive).await.unwrap();
    assert_eq!(&alive, b"alive");
    assert!(!client.is_closed(), "{:?}", client.close_reason());
    finish.send(()).unwrap();
    server.await.unwrap();
    client.close();
}

#[tokio::test]
async fn legacy_authorization_reoffers_key_when_framework_becomes_ready() {
    let identity = Identity::generate().unwrap();
    let public_key = identity.public_key("legacy-test").unwrap();
    let (transport, mut peer) = tokio::io::duplex(64 * 1024);
    let (finish, finished) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        assert_eq!(read(&mut peer).await.command, protocol::CNXN);
        send(&mut peer, protocol::AUTH, 1, 0, &[1; 20]).await;
        let signature = read(&mut peer).await;
        assert_eq!((signature.command, signature.arg0), (protocol::AUTH, 2));
        assert_eq!(signature.payload.len(), 256);
        send(&mut peer, protocol::AUTH, 1, 0, &[2; 20]).await;
        let offered = read(&mut peer).await;
        assert_eq!((offered.command, offered.arg0), (protocol::AUTH, 3));
        assert_eq!(offered.payload, public_key);
        // Android 4.4's needs_retry path sends another token when framework
        // connects after the first public key arrived during boot.
        send(&mut peer, protocol::AUTH, 1, 0, &[3; 20]).await;
        let repeated = read(&mut peer).await;
        assert_eq!((repeated.command, repeated.arg0), (protocol::AUTH, 3));
        assert_eq!(repeated.payload, public_key);
        legacy_banner(&mut peer).await;
        finished.await.unwrap();
    });
    let client = Client::connect_transport(
        transport,
        ConnectOptions {
            identity: Some(identity),
            request_authorization: true,
            public_key_comment: "legacy-test".into(),
            operations: options(),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert_eq!(client.info().version, protocol::LEGACY_VERSION);
    assert!(!client.is_closed());
    finish.send(()).unwrap();
    server.await.unwrap();
    client.close();
}

#[tokio::test]
async fn classic_reverse_drains_tail_when_close_wakes_pending_writer() {
    use interop_adb::ReverseSocket;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let host = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let destination = host.local_addr().unwrap();
    let (resume, resumed) = tokio::sync::oneshot::channel();
    let host_task = tokio::spawn(async move {
        let (mut socket, _) = host.accept().await.unwrap();
        socket2::SockRef::from(&socket)
            .set_recv_buffer_size(4096)
            .unwrap();
        socket.write_all(b"withhold my ACK").await.unwrap();
        // Hold the host's read side until the bridge is blocked delivering
        // device data and the daemon has closed its stream.
        resumed.await.unwrap();
        socket2::SockRef::from(&socket)
            .set_recv_buffer_size(1024 * 1024)
            .unwrap();
        let mut received = Vec::new();
        let result = socket.read_to_end(&mut received).await;
        (received, result)
    });
    let (transport, mut peer) = tokio::io::duplex(64 * 1024);
    let (finish, finished) = tokio::sync::oneshot::channel();
    let (sent, sent_count) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        connect_banner(&mut peer).await;
        let registration = read(&mut peer).await;
        let token = registration
            .payload
            .strip_suffix(&[0])
            .unwrap()
            .split(|byte| *byte == b';')
            .nth(1)
            .unwrap()
            .to_vec();
        send(&mut peer, protocol::OKAY, 50, registration.arg0, &[]).await;
        send(&mut peer, protocol::WRTE, 50, registration.arg0, b"OKAY").await;
        send(&mut peer, protocol::CLSE, 50, registration.arg0, &[]).await;
        let mut incoming = token;
        incoming.push(0);
        send(&mut peer, protocol::OPEN, 600, 0, &incoming).await;
        let accepted = loop {
            let frame = read(&mut peer).await;
            if frame.command == protocol::OKAY && frame.arg1 == 600 {
                break frame.arg0;
            }
        };
        let output = read(&mut peer).await;
        assert_eq!(output.command, protocol::WRTE);
        assert_eq!(output.payload, b"withhold my ACK");
        // Leave that write awaiting ACK, then fill the bridge's TCP send
        // buffer. The first unacknowledged input packet proves that its read
        // task is stuck in TCP write_all, independently of select! ordering.
        let mut count = 0;
        loop {
            assert!(count < 16 * 1024 * 1024, "TCP backpressure did not engage");
            send(&mut peer, protocol::WRTE, 600, accepted, &[0x5a; 4096]).await;
            count += 4096;
            if tokio::time::timeout(Duration::from_millis(250), read(&mut peer))
                .await
                .is_err()
            {
                break;
            }
        }
        // AOSP may flush one final WRTE on EOF before receiving the previous
        // ACK. Both packets must survive removal of the route by CLSE.
        send(&mut peer, protocol::WRTE, 600, accepted, b"tail-end").await;
        send(&mut peer, protocol::CLSE, 600, accepted, &[]).await;
        loop {
            let frame = read(&mut peer).await;
            if frame.command == protocol::CLSE && frame.arg1 == 600 {
                break;
            }
        }
        tokio::task::yield_now().await;
        resume.send(()).unwrap();
        sent.send(count).unwrap();
        finished.await.unwrap();
    });
    let client = Client::connect_transport(transport, ConnectOptions::default())
        .await
        .unwrap();
    assert!(!client.burst_mode());
    client
        .reverse_forward(&ReverseSocket::Tcp(12345), destination, true, options())
        .await
        .unwrap();
    let (received, result) = tokio::time::timeout(Duration::from_secs(15), host_task)
        .await
        .unwrap()
        .unwrap();
    let count = sent_count.await.unwrap();
    assert!(result.is_ok(), "host read failed: {result:?}");
    assert_eq!(received.len(), count + 8, "reverse dropped device bytes");
    assert!(received[..count].iter().all(|byte| *byte == 0x5a));
    assert_eq!(&received[count..], b"tail-end");
    assert!(!client.is_closed(), "{:?}", client.close_reason());
    finish.send(()).unwrap();
    server.await.unwrap();
    client.close();
}

struct LegacySyncPeer {
    peer: DuplexStream,
    remote: u32,
    bytes: Vec<u8>,
}

impl LegacySyncPeer {
    async fn take(&mut self, count: usize) -> Vec<u8> {
        while self.bytes.len() < count {
            let frame = read(&mut self.peer).await;
            if frame.command == protocol::WRTE {
                assert_eq!((frame.arg0, frame.arg1), (self.remote, 42));
                self.bytes.extend(frame.payload);
                send(&mut self.peer, protocol::OKAY, 42, self.remote, &[]).await;
            } else {
                assert_eq!(frame.command, protocol::OKAY);
            }
        }
        self.bytes.drain(..count).collect()
    }

    async fn request(&mut self) -> ([u8; 4], Vec<u8>) {
        let header = self.take(8).await;
        let length = u32::from_le_bytes(header[4..].try_into().unwrap()) as usize;
        (header[..4].try_into().unwrap(), self.take(length).await)
    }

    async fn reply(&mut self, bytes: &[u8]) {
        for chunk in bytes.chunks(4096) {
            send(&mut self.peer, protocol::WRTE, 42, self.remote, chunk).await;
            let ack = read(&mut self.peer).await;
            assert_eq!(
                (ack.command, ack.arg0, ack.arg1),
                (protocol::OKAY, self.remote, 42)
            );
        }
    }
}

#[tokio::test]
async fn legacy_shell_and_sync_round_trip_with_and_without_auth() {
    use interop_adb::sync::RemotePath;
    let identity = Identity::generate().unwrap();
    let content: Vec<u8> = (0..70_000).map(|index| (index % 251) as u8).collect();
    for authentication in [false, true] {
        let (transport, mut peer) = tokio::io::duplex(64 * 1024);
        let expected = content.clone();
        let (finish, finished) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            assert_eq!(read(&mut peer).await.command, protocol::CNXN);
            if authentication {
                send(&mut peer, protocol::AUTH, 1, 0, &[7; 20]).await;
                let response = read(&mut peer).await;
                assert_eq!((response.command, response.arg0), (protocol::AUTH, 2));
                assert_eq!(response.payload.len(), 256);
            }
            legacy_banner(&mut peer).await;
            let shell = read(&mut peer).await;
            assert_eq!(shell.payload, b"shell:printf legacy\0");
            send(&mut peer, protocol::OKAY, 41, shell.arg0, &[]).await;
            send(&mut peer, protocol::WRTE, 41, shell.arg0, b"legacy\0\xff").await;
            send(&mut peer, protocol::CLSE, 41, shell.arg0, &[]).await;
            let sync = loop {
                let frame = read(&mut peer).await;
                if frame.command == protocol::OPEN {
                    break frame;
                }
            };
            assert_eq!(sync.payload, b"sync:\0");
            send(&mut peer, protocol::OKAY, 42, sync.arg0, &[]).await;
            let mut sync = LegacySyncPeer {
                peer,
                remote: sync.arg0,
                bytes: Vec::new(),
            };
            let (id, path) = sync.request().await;
            assert_eq!(&id, b"STAT");
            assert_eq!(path, b"/data/local/tmp/legacy-\xff");
            let mut stat = b"STAT".to_vec();
            for word in [0o100640u32, 70_000, 42] {
                stat.extend_from_slice(&word.to_le_bytes());
            }
            sync.reply(&stat).await;
            assert_eq!(&sync.request().await.0, b"LIST");
            let mut listing = b"DENT".to_vec();
            for word in [0o100640u32, 70_000, 42, 4] {
                listing.extend_from_slice(&word.to_le_bytes());
            }
            listing.extend_from_slice(b"file");
            listing.extend_from_slice(b"DONE");
            listing.extend_from_slice(&[0; 16]);
            sync.reply(&listing).await;
            let (id, destination) = sync.request().await;
            assert_eq!(&id, b"SEND");
            assert_eq!(destination, b"/data/local/tmp/legacy-\xff,33184");
            let mut pushed = Vec::new();
            loop {
                let header = sync.take(8).await;
                let value = u32::from_le_bytes(header[4..].try_into().unwrap());
                if &header[..4] == b"DONE" {
                    assert_eq!(value, 42);
                    break;
                }
                assert_eq!(&header[..4], b"DATA");
                assert!(value <= 65536);
                pushed.extend(sync.take(value as usize).await);
            }
            assert_eq!(pushed, expected);
            sync.reply(b"OKAY\0\0\0\0").await;
            let (id, path) = sync.request().await;
            assert_eq!(&id, b"RECV");
            assert_eq!(path, b"/data/local/tmp/legacy-\xff");
            for chunk in expected.chunks(65536) {
                let mut data = b"DATA".to_vec();
                data.extend_from_slice(&(chunk.len() as u32).to_le_bytes());
                data.extend_from_slice(chunk);
                sync.reply(&data).await;
            }
            sync.reply(b"DONE\0\0\0\0").await;
            finished.await.unwrap();
        });
        let client = Client::connect_transport(
            transport,
            ConnectOptions {
                identity: authentication.then(|| identity.clone()),
                operations: options(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        assert_eq!(client.info().version, protocol::LEGACY_VERSION);
        assert_eq!(client.info().max_payload, 4096);
        assert!(client.info().features.is_empty());
        let output = client
            .shell("printf legacy", 1024, options())
            .await
            .unwrap();
        assert_eq!(output.stdout, b"legacy\0\xff");
        assert!(output.stderr.is_empty());
        assert_eq!(output.exit_code, None);
        let path = RemotePath::new(b"/data/local/tmp/legacy-\xff").unwrap();
        let mut sync = client.sync(options()).await.unwrap();
        let stat = sync.stat(&path).await.unwrap();
        assert_eq!(
            (stat.mode, stat.size, stat.modified_seconds),
            (0o100640, 70_000, 42)
        );
        let entries = sync
            .list(&RemotePath::new(b"/data/local/tmp").unwrap(), 1)
            .await
            .unwrap();
        assert_eq!(entries[0].name, b"file");
        assert_eq!(entries[0].stat, stat);
        assert_eq!(
            sync.push(&path, &mut &content[..], 0o640, 42, 70_000)
                .await
                .unwrap(),
            70_000
        );
        let mut received = Vec::new();
        assert_eq!(
            sync.pull(&path, &mut received, 70_000).await.unwrap(),
            70_000
        );
        assert_eq!(received, content);
        assert!(!client.is_closed(), "{:?}", client.close_reason());
        finish.send(()).unwrap();
        server.await.unwrap();
        client.close();
    }
}

#[tokio::test]
async fn checksum_validation_follows_the_negotiated_wire_version() {
    use tokio::io::AsyncWriteExt;
    for version in [protocol::LEGACY_VERSION, protocol::VERSION] {
        let (transport, mut peer) = tokio::io::duplex(64 * 1024);
        let (finish, finished) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            assert_eq!(read(&mut peer).await.command, protocol::CNXN);
            send(&mut peer, protocol::CNXN, version, 4096, b"device::\0").await;
            let open = read(&mut peer).await;
            send(&mut peer, protocol::OKAY, 41, open.arg0, &[]).await;
            let mut corrupted = Vec::new();
            Frame::new(protocol::WRTE, 41, open.arg0, b"checksum".to_vec())
                .write(&mut corrupted)
                .await
                .unwrap();
            // The byte sum of "checksum" is nonzero. Version 1.0.0 must reject
            // this frame; 1.0.1 explicitly permits an omitted checksum.
            corrupted[16..20].copy_from_slice(&0u32.to_le_bytes());
            peer.write_all(&corrupted).await.unwrap();
            finished.await.unwrap();
        });
        let client = Client::connect_transport(transport, ConnectOptions::default())
            .await
            .unwrap();
        let mut stream = client.open("shell:checksum", options()).await.unwrap();
        let mut payload = [0; 8];
        let result = stream.read_exact(&mut payload).await;
        if version == protocol::LEGACY_VERSION {
            assert!(matches!(result, Err(interop_adb::Error::Closed)));
            assert!(client.is_closed());
            assert!(
                client
                    .close_reason()
                    .unwrap()
                    .contains("invalid frame checksum")
            );
        } else {
            result.unwrap();
            assert_eq!(&payload, b"checksum");
            assert!(!client.is_closed());
        }
        finish.send(()).unwrap();
        server.await.unwrap();
        client.close();
    }
}
