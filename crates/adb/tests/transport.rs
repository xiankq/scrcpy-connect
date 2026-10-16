//! Wire-level local adbd fixtures. Actual Android interoperability is a separate device test.
use interop_adb::{
    CancellationToken, Client, ConnectOptions, Error, Identity, OperationOptions,
    protocol::{self, Frame},
    sync::RemotePath,
};

#[tokio::test]
async fn interactive_shell_retains_partial_event_across_input_interruptions() {
    use interop_adb::{ShellEvent, ShellMode};
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "shell_v2").await;
        let open = read(&mut socket).await;
        assert_eq!(open.payload, b"shell,v2,raw:cat\0");
        send(&mut socket, protocol::OKAY, 88, open.arg0, &[]).await;
        send(&mut socket, protocol::WRTE, 88, open.arg0, &[1, 5]).await;
        let mut input = Vec::new();
        loop {
            let frame = read(&mut socket).await;
            if frame.command == protocol::WRTE {
                input.extend(frame.payload);
                send(&mut socket, protocol::OKAY, 88, open.arg0, &[]).await;
                break;
            }
        }
        assert_eq!(input, b"\0\x05\0\0\0hello");
        loop {
            let frame = read(&mut socket).await;
            if frame.command == protocol::WRTE {
                assert_eq!(frame.payload, [4, 0, 0, 0, 0]);
                send(&mut socket, protocol::OKAY, 88, open.arg0, &[]).await;
                break;
            }
        }
        send(
            &mut socket,
            protocol::WRTE,
            88,
            open.arg0,
            b"\0\0\0hello\x03\x01\0\0\0\0",
        )
        .await;
        loop {
            if read(&mut socket).await.command == protocol::CLSE {
                break;
            }
        }
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let mut session = client
        .shell_session("cat", ShellMode::Raw, 4096, options())
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(20), session.next_event())
            .await
            .is_err()
    );
    session.write_stdin(b"hello").await.unwrap();
    session.close_stdin().await.unwrap();
    assert_eq!(
        session.next_event().await.unwrap(),
        Some(ShellEvent::Stdout(b"hello".to_vec()))
    );
    assert_eq!(
        session.next_event().await.unwrap(),
        Some(ShellEvent::Exit(0))
    );
    assert_eq!(session.next_event().await.unwrap(), None);
    session.close().await.unwrap();
    server.await.unwrap();
}
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};

async fn read(socket: &mut TcpStream) -> Frame {
    Frame::read(socket, protocol::MAX_PAYLOAD, false)
        .await
        .unwrap()
}
async fn send(socket: &mut TcpStream, command: u32, local: u32, remote: u32, data: &[u8]) {
    Frame::new(command, local, remote, data.to_vec())
        .write(socket)
        .await
        .unwrap();
}
async fn handshake(socket: &mut TcpStream, features: &str) {
    socket.set_nodelay(true).unwrap();
    assert_eq!(read(socket).await.command, protocol::CNXN);
    send(
        socket,
        protocol::CNXN,
        protocol::VERSION,
        4096,
        format!("device::features={features};\0").as_bytes(),
    )
    .await;
}
fn options() -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(3),
        ..Default::default()
    }
}

#[tokio::test]
async fn sync_lstat_selects_nofollow_protocol_and_preserves_metadata_widths() {
    for modern in [false, true] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            handshake(&mut socket, if modern { "stat_v2" } else { "" }).await;
            let open = read(&mut socket).await;
            assert_eq!(open.payload, b"sync:\0");
            send(&mut socket, protocol::OKAY, 22, open.arg0, &[]).await;
            let request = read(&mut socket).await;
            let id = if modern { b"LST2" } else { b"STAT" };
            assert_eq!(&request.payload[..4], id);
            assert_eq!(&request.payload[8..], b"/one/link");
            send(&mut socket, protocol::OKAY, 22, open.arg0, &[]).await;
            let mut response = id.to_vec();
            if modern {
                let mut fields = [0; 68];
                fields[20..24].copy_from_slice(&0o120777u32.to_le_bytes());
                fields[36..44].copy_from_slice(&0x1_0000_0001u64.to_le_bytes());
                fields[52..60].copy_from_slice(&(-10i64).to_le_bytes());
                response.extend_from_slice(&fields);
            } else {
                response.extend_from_slice(&0o120777u32.to_le_bytes());
                response.extend_from_slice(&17u32.to_le_bytes());
                response.extend_from_slice(&42u32.to_le_bytes());
            }
            send(&mut socket, protocol::WRTE, 22, open.arg0, &response).await;
            while read(&mut socket).await.command != protocol::CLSE {}
        });
        let client = Client::connect_tcp(address, ConnectOptions::default())
            .await
            .unwrap();
        let mut sync = client.sync(options()).await.unwrap();
        let stat = sync
            .lstat(&RemotePath::new(b"/one/link").unwrap())
            .await
            .unwrap();
        assert_eq!(stat.mode & 0o170000, 0o120000);
        assert_eq!(stat.size, if modern { 0x1_0000_0001 } else { 17 });
        assert_eq!(stat.modified_seconds, if modern { -10 } else { 42 });
        drop(sync);
        server.await.unwrap();
        client.close();
    }
}

#[tokio::test]
async fn reverse_bridge_acknowledges_input_while_output_ack_is_withheld() {
    use interop_adb::ReverseSocket;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let host = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let destination = host.local_addr().unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let host_task = tokio::spawn(async move {
        let (mut socket, _) = host.accept().await.unwrap();
        socket.write_all(&[19; 4096]).await.unwrap();
        let mut input = [0; 11];
        socket.read_exact(&mut input).await.unwrap();
        assert_eq!(&input, b"from device");
    });
    let (finished, completion) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "").await;
        let open = read(&mut socket).await;
        let service = open.payload.strip_suffix(&[0]).unwrap();
        let token = service.split(|byte| *byte == b';').nth(1).unwrap();
        let mut incoming = token.to_vec();
        incoming.push(0);
        send(&mut socket, protocol::OKAY, 50, open.arg0, &[]).await;
        send(&mut socket, protocol::WRTE, 50, open.arg0, b"OKAY").await;
        assert_eq!(read(&mut socket).await.command, protocol::OKAY);
        send(&mut socket, protocol::CLSE, 50, open.arg0, &[]).await;
        // A device initiates the approved reverse service after registration.
        send(&mut socket, protocol::OPEN, 600, 0, &incoming).await;
        let accepted = loop {
            let frame = read(&mut socket).await;
            if frame.command == protocol::OKAY && frame.arg1 == 600 {
                break frame;
            }
        };
        let output = read(&mut socket).await;
        assert_eq!(output.command, protocol::WRTE);
        assert_eq!(output.payload, [19; 4096]);
        // Withhold output's ACK until the host consumes input. A sequential
        // read/write bridge deadlocks here even though the two directions differ.
        send(
            &mut socket,
            protocol::WRTE,
            600,
            accepted.arg0,
            b"from device",
        )
        .await;
        let input_ack = read(&mut socket).await;
        assert_eq!(input_ack.command, protocol::OKAY);
        assert_eq!(input_ack.arg1, 600);
        send(&mut socket, protocol::OKAY, 600, accepted.arg0, &[]).await;
        let _ = finished.send(());
        // Keep the transport alive until the host receives its input.
        let _ = read(&mut socket).await;
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    client
        .reverse_forward(&ReverseSocket::Tcp(12345), destination, true, options())
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), completion)
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(3), host_task)
        .await
        .unwrap()
        .unwrap();
    client.close();
    server.abort();
}

#[tokio::test]
async fn unsolicited_device_open_cannot_dial_arbitrary_host_ports() {
    let host = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target = host.local_addr().unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (rejected, seen) = tokio::sync::oneshot::channel();
    let (finish, finished) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "").await;
        send(
            &mut socket,
            protocol::OPEN,
            444,
            0,
            format!("tcp:{}\0", target.port()).as_bytes(),
        )
        .await;
        let close = read(&mut socket).await;
        assert_eq!(close.command, protocol::CLSE);
        assert_eq!((close.arg0, close.arg1), (0, 444));
        assert!(
            tokio::time::timeout(Duration::from_millis(50), host.accept())
                .await
                .is_err()
        );
        rejected.send(()).unwrap();
        let open = read(&mut socket).await;
        assert_eq!(open.command, protocol::OPEN);
        send(&mut socket, protocol::OKAY, 99, open.arg0, &[]).await;
        send(&mut socket, protocol::WRTE, 99, open.arg0, b"safe").await;
        loop {
            if read(&mut socket).await.command == protocol::CLSE {
                break;
            }
        }
        finished.await.unwrap();
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    seen.await.unwrap();
    let mut stream = client.open("safe", options()).await.unwrap();
    let mut value = [0; 4];
    stream.read_exact(&mut value).await.unwrap();
    assert_eq!(&value, b"safe");
    stream.close().await.unwrap();
    assert!(!client.is_closed());
    finish.send(()).unwrap();
    server.await.unwrap();
    client.close();
}

#[tokio::test]
async fn jdwp_tracker_preserves_partial_header_when_read_future_is_dropped() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (resume, resumed) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "").await;
        let open = read(&mut socket).await;
        assert_eq!(open.payload, b"track-jdwp\0");
        send(&mut socket, protocol::OKAY, 7, open.arg0, &[]).await;
        send(&mut socket, protocol::WRTE, 7, open.arg0, b"00").await;
        resumed.await.unwrap();
        assert_eq!(read(&mut socket).await.command, protocol::OKAY);
        send(&mut socket, protocol::WRTE, 7, open.arg0, b"04123\n").await;
        loop {
            if read(&mut socket).await.command == protocol::CLSE {
                break;
            }
        }
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let mut tracker = client.track_jdwp(20, options()).await.unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(20), tracker.next_event())
            .await
            .is_err()
    );
    resume.send(()).unwrap();
    let ids = tracker.next_event().await.unwrap().unwrap();
    assert_eq!(ids.iter().map(|id| id.get()).collect::<Vec<_>>(), [123]);
    tracker.close().await.unwrap();
    server.await.unwrap();
}

#[tokio::test]
#[ignore = "requires a real reachable adbd endpoint"]
async fn real_adbd_shell_keeps_transport_online() {
    let address = std::env::var("INTEROP_ADBD_ENDPOINT").expect("set INTEROP_ADBD_ENDPOINT");
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    for _ in 0..3 {
        let result = client
            .shell("printf interop-protocol", 4096, options())
            .await;
        assert!(
            result.is_ok(),
            "shell error {result:?}; transport {:?}",
            client.close_reason()
        );
        assert_eq!(result.unwrap().stdout, b"interop-protocol");
    }
    assert!(!client.is_closed(), "{:?}", client.close_reason());
}

#[tokio::test]
async fn multiplexes_shell_and_preserves_tail_and_exit_status() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "shell_v2").await;
        let first = read(&mut socket).await;
        assert_eq!(first.command, protocol::OPEN);
        send(&mut socket, protocol::OKAY, 101, first.arg0, &[]).await;
        let second = read(&mut socket).await;
        assert_eq!(second.command, protocol::OPEN);
        send(&mut socket, protocol::OKAY, 102, second.arg0, &[]).await;
        let packet = |text: &[u8], code: u8| {
            let mut bytes = vec![1];
            bytes.extend_from_slice(&(text.len() as u32).to_le_bytes());
            bytes.extend_from_slice(text);
            bytes.extend_from_slice(&[2, 1, 0, 0, 0, b'!', 3, 1, 0, 0, 0, code]);
            bytes
        };
        let second_packet = packet(b"two", 7);
        send(
            &mut socket,
            protocol::WRTE,
            102,
            second.arg0,
            &second_packet[..second_packet.len() - 6],
        )
        .await;
        // AOSP's EOF path may flush the final shell exit WRTE before an ACK.
        send(
            &mut socket,
            protocol::WRTE,
            102,
            second.arg0,
            &second_packet[second_packet.len() - 6..],
        )
        .await;
        send(&mut socket, protocol::CLSE, 102, second.arg0, &[]).await;
        send(
            &mut socket,
            protocol::WRTE,
            101,
            first.arg0,
            &packet(b"one", 0),
        )
        .await;
        send(&mut socket, protocol::CLSE, 101, first.arg0, &[]).await;
        // Keep transport alive until both close acknowledgements arrive.
        let mut closed = 0;
        while closed < 2 {
            if read(&mut socket).await.command == protocol::CLSE {
                closed += 1;
            }
        }
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let (first, second) = tokio::join!(
        client.shell("echo one", 1024, options()),
        client.shell("echo two", 1024, options())
    );
    let first = first.unwrap();
    let second = second.unwrap();
    assert_eq!(first.stdout, b"one");
    assert_eq!(first.stderr, b"!");
    assert_eq!(first.exit_code, Some(0));
    assert_eq!(second.stdout, b"two");
    assert_eq!(second.exit_code, Some(7));
    server.await.unwrap();
}

#[tokio::test]
async fn authorization_is_explicit_and_signature_is_not_double_hashed() {
    use base64::Engine;
    use rsa::{BigUint, Pkcs1v15Sign, RsaPublicKey};
    let identity = Identity::generate().unwrap();
    let public = identity.public_key("test").unwrap();
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(public.split(|b| *b == b' ').next().unwrap())
        .unwrap();
    assert_eq!(decoded.len(), 524);
    assert_eq!(u32::from_le_bytes(decoded[..4].try_into().unwrap()), 64);
    let key = RsaPublicKey::new(
        BigUint::from_bytes_le(&decoded[8..264]),
        BigUint::from(65537u32),
    )
    .unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(read(&mut socket).await.command, protocol::CNXN);
        let token = [0x42; 20];
        send(&mut socket, protocol::AUTH, 1, 0, &token).await;
        let signed = read(&mut socket).await;
        assert_eq!((signed.command, signed.arg0), (protocol::AUTH, 2));
        key.verify(Pkcs1v15Sign::new::<sha1::Sha1>(), &token, &signed.payload)
            .unwrap();
        send(&mut socket, protocol::AUTH, 1, 0, &token).await;
        // A rejected signature must not automatically offer a public key.
        let mut byte = [0];
        use tokio::io::AsyncReadExt;
        assert_eq!(socket.read(&mut byte).await.unwrap(), 0);
    });
    let error = Client::connect_tcp(
        address,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .err()
    .unwrap();
    assert!(matches!(error, Error::AuthorizationRequired));
    server.await.unwrap();
}

#[tokio::test]
async fn cancellation_closes_only_the_opening_stream() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "").await;
        let open = read(&mut socket).await;
        assert_eq!(open.command, protocol::OPEN);
        let close = read(&mut socket).await;
        assert_eq!(close.command, protocol::CLSE);
        assert_eq!(close.arg0, open.arg0);
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let token = CancellationToken::new();
    let trigger = token.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(20)).await;
        trigger.cancel();
    });
    let result = client
        .open(
            "shell:never",
            OperationOptions {
                cancellation: token,
                ..options()
            },
        )
        .await;
    assert!(matches!(result, Err(Error::Cancelled)));
    server.await.unwrap();
}

// The server-side sync byte stream reassembles requests split across ADB WRTE frames.
struct SyncPeer {
    socket: TcpStream,
    local: u32,
    remote: u32,
    bytes: Vec<u8>,
}
impl SyncPeer {
    async fn take(&mut self, count: usize) -> Vec<u8> {
        while self.bytes.len() < count {
            let frame = read(&mut self.socket).await;
            match frame.command {
                protocol::WRTE => {
                    self.bytes.extend(frame.payload);
                    send(
                        &mut self.socket,
                        protocol::OKAY,
                        self.local,
                        self.remote,
                        &[],
                    )
                    .await;
                }
                protocol::OKAY => {}
                other => panic!("unexpected {other:x}"),
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
            send(
                &mut self.socket,
                protocol::WRTE,
                self.local,
                self.remote,
                chunk,
            )
            .await;
            // A packet is acknowledged when the application consumes it and requests more.
            // Single-packet replies may remain unacknowledged until the next sync operation.
            if chunk.len() == 4096 {
                let ack = read(&mut self.socket).await;
                assert_eq!(ack.command, protocol::OKAY);
            }
        }
    }
}

#[tokio::test]
async fn sync_streams_push_pull_and_reads_stat_and_directory() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let contents: Vec<u8> = (0..150_000).map(|i| (i % 251) as u8).collect();
    let expected = contents.clone();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "stat_v2").await;
        let open = read(&mut socket).await;
        assert_eq!(open.payload, b"sync:\0");
        send(&mut socket, protocol::OKAY, 41, open.arg0, &[]).await;
        let mut peer = SyncPeer {
            socket,
            local: 41,
            remote: open.arg0,
            bytes: vec![],
        };
        let (id, path) = peer.request().await;
        assert_eq!(&id, b"STA2");
        assert_eq!(path, b"/data/local/tmp/test");
        let mut stat = b"STA2".to_vec();
        let mut body = [0; 68];
        body[20..24].copy_from_slice(&0o100644u32.to_le_bytes());
        body[36..44].copy_from_slice(&(expected.len() as u64).to_le_bytes());
        body[52..60].copy_from_slice(&42u64.to_le_bytes());
        stat.extend_from_slice(&body);
        peer.reply(&stat).await;
        let (id, _) = peer.request().await;
        assert_eq!(&id, b"LIST");
        let mut listing = b"DENT".to_vec();
        for word in [0o100644u32, expected.len() as u32, 42, 4] {
            listing.extend_from_slice(&word.to_le_bytes());
        }
        listing.extend_from_slice(b"test");
        listing.extend_from_slice(b"DONE");
        listing.extend_from_slice(&[0; 16]);
        peer.reply(&listing).await;
        let (id, path) = peer.request().await;
        assert_eq!(&id, b"SEND");
        assert!(path.starts_with(b"/data/local/tmp/test,"));
        let mut pushed = Vec::new();
        loop {
            let header = peer.take(8).await;
            let value = u32::from_le_bytes(header[4..].try_into().unwrap());
            if &header[..4] == b"DONE" {
                assert_eq!(value, 42);
                break;
            }
            assert_eq!(&header[..4], b"DATA");
            assert!(value <= 65536);
            pushed.extend(peer.take(value as usize).await);
        }
        assert_eq!(pushed, expected);
        peer.reply(b"OKAY\0\0\0\0").await;
        let (id, _) = peer.request().await;
        assert_eq!(&id, b"RECV");
        // Small DATA records still cross ADB packet boundaries and exercise incremental reads.
        for chunk in expected.chunks(3000) {
            let mut data = b"DATA".to_vec();
            data.extend_from_slice(&(chunk.len() as u32).to_le_bytes());
            data.extend_from_slice(chunk);
            peer.reply(&data).await;
            loop {
                let frame = read(&mut peer.socket).await;
                if frame.command == protocol::OKAY {
                    break;
                }
            }
        }
        peer.reply(b"DONE\0\0\0\0").await;
        // Keep the fixture alive through stream drop.
        loop {
            if read(&mut peer.socket).await.command == protocol::CLSE {
                break;
            }
        }
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let path = RemotePath::new("/data/local/tmp/test").unwrap();
    let mut sync = client.sync(options()).await.unwrap();
    let stat = sync.stat(&path).await.unwrap();
    assert_eq!(stat.size, contents.len() as u64);
    assert_eq!(stat.modified_seconds, 42);
    let entries = sync
        .list(&RemotePath::new("/data/local/tmp").unwrap(), 32)
        .await
        .unwrap();
    assert_eq!(entries[0].name, b"test");
    assert_eq!(
        sync.push(&path, &mut &contents[..], 0o644, 42, 200_000)
            .await
            .unwrap(),
        contents.len() as u64
    );
    let mut received = Vec::new();
    assert_eq!(
        sync.pull(&path, &mut received, 200_000).await.unwrap(),
        contents.len() as u64
    );
    assert_eq!(received, contents);
    drop(sync);
    server.await.unwrap();
}

#[tokio::test]
async fn directory_v2_retains_large_sizes_and_signed_times() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "ls_v2").await;
        let open = read(&mut socket).await;
        send(&mut socket, protocol::OKAY, 99, open.arg0, &[]).await;
        let mut peer = SyncPeer {
            socket,
            local: 99,
            remote: open.arg0,
            bytes: vec![],
        };
        let (id, _) = peer.request().await;
        assert_eq!(&id, b"LIS2");
        let mut response = b"DNT2".to_vec();
        let mut body = [0; 72];
        body[20..24].copy_from_slice(&0o100644u32.to_le_bytes());
        body[36..44].copy_from_slice(&(1u64 << 40).to_le_bytes());
        body[52..60].copy_from_slice(&(-42i64).to_le_bytes());
        body[68..72].copy_from_slice(&3u32.to_le_bytes());
        response.extend_from_slice(&body);
        response.extend_from_slice(&[b'a', 0xff, b'b']);
        response.extend_from_slice(b"DONE");
        response.extend_from_slice(&[0; 72]);
        peer.reply(&response).await;
        loop {
            if read(&mut peer.socket).await.command == protocol::CLSE {
                break;
            }
        }
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let mut sync = client.sync(options()).await.unwrap();
    let entries = sync.list(&RemotePath::new("/").unwrap(), 1).await.unwrap();
    assert_eq!(entries[0].name, [b'a', 0xff, b'b']);
    assert_eq!(entries[0].stat.size, 1u64 << 40);
    assert_eq!(entries[0].stat.modified_seconds, -42);
    drop(sync);
    server.await.unwrap();
}

#[tokio::test]
async fn excess_unacknowledged_data_is_a_protocol_failure() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        handshake(&mut socket, "").await;
        let open = read(&mut socket).await;
        send(&mut socket, protocol::OKAY, 77, open.arg0, &[]).await;
        send(&mut socket, protocol::WRTE, 77, open.arg0, b"first").await;
        send(&mut socket, protocol::WRTE, 77, open.arg0, b"tail").await;
        send(&mut socket, protocol::WRTE, 77, open.arg0, b"excess").await;
        tokio::time::sleep(Duration::from_millis(50)).await;
    });
    let client = Client::connect_tcp(address, ConnectOptions::default())
        .await
        .unwrap();
    let mut stream = client.open("shell:bad", options()).await.unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while !client.is_closed() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(client.is_closed());
    let mut data = [0; 32];
    // Already queued bytes remain readable, but fabricated extra packets are discarded.
    assert_eq!(stream.read(&mut data).await.unwrap(), 5);
    assert_eq!(stream.read(&mut data).await.unwrap(), 4);
    assert!(matches!(stream.read(&mut data).await, Err(Error::Closed)));
    server.await.unwrap();
}
