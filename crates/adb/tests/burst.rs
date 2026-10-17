//! Byte-stream fixtures for AOSP delayed_ack at 9084198a2d4b0f6a0f174260fb42da33485b684d.
use interop_adb::{
    AdbStream, CancellationToken, Client, ConnectOptions, DeviceInfo, Error, OperationOptions,
    ReverseSocket,
    protocol::{self, Frame},
};
use std::time::Duration;
use tokio::io::DuplexStream;

async fn read<T: tokio::io::AsyncRead + Unpin>(peer: &mut T) -> Frame {
    tokio::time::timeout(
        Duration::from_secs(2),
        Frame::read(peer, protocol::MAX_PAYLOAD, true),
    )
    .await
    .unwrap()
    .unwrap()
}
async fn send<T: tokio::io::AsyncWrite + Unpin>(
    peer: &mut T,
    command: u32,
    local: u32,
    remote: u32,
    bytes: &[u8],
) {
    Frame::new(command, local, remote, bytes.to_vec())
        .write(peer)
        .await
        .unwrap();
}
fn options() -> OperationOptions {
    OperationOptions {
        timeout: Duration::from_secs(2),
        ..Default::default()
    }
}
fn enabled() -> ConnectOptions {
    ConnectOptions {
        burst_mode: true,
        ..Default::default()
    }
}

#[tokio::test]
async fn enabled_connection_advertises_delayed_ack_and_byte_window() {
    let (host, mut peer) = tokio::io::duplex(8192);
    let server = tokio::spawn(async move {
        let cnxn = read(&mut peer).await;
        assert!(String::from_utf8_lossy(&cnxn.payload).contains("delayed_ack"));
        send(
            &mut peer,
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=delayed_ack;\0",
        )
        .await;
        let open = read(&mut peer).await;
        assert_eq!(open.command, protocol::OPEN);
        assert!(open.arg1 > 0);
        send(
            &mut peer,
            protocol::OKAY,
            41,
            open.arg0,
            &8192i32.to_le_bytes(),
        )
        .await;
        let a = read(&mut peer).await;
        let b = read(&mut peer).await;
        assert_eq!((a.command, b.command), (protocol::WRTE, protocol::WRTE));
        assert_eq!((a.payload.len(), b.payload.len()), (4096, 4096));
        assert_eq!(read(&mut peer).await.command, protocol::CLSE);
    });
    let client = Client::connect_transport(host, enabled()).await.unwrap();
    let mut stream = client.open("shell:cat", options()).await.unwrap();
    stream.write_all(&vec![7; 8192]).await.unwrap();
    stream.close().await.unwrap();
    server.await.unwrap();
}

fn attached(burst: bool, peer_support: bool, max_payload: usize) -> (Client, DuplexStream) {
    let (host, peer) = tokio::io::duplex(2 * protocol::MAX_PAYLOAD);
    let info = DeviceInfo {
        version: protocol::VERSION,
        max_payload,
        banner: "device::".into(),
        features: if peer_support {
            ["delayed_ack".into()].into()
        } else {
            Default::default()
        },
    };
    (
        Client::from_negotiated_transport_with_burst(host, info, burst).unwrap(),
        peer,
    )
}
async fn open(
    client: &Client,
    peer: &mut DuplexStream,
    remote: u32,
    credit: i32,
) -> (AdbStream, Frame) {
    let opener = client.clone();
    let task = tokio::spawn(async move { opener.open("shell:cat", options()).await.unwrap() });
    let frame = read(peer).await;
    send(
        peer,
        protocol::OKAY,
        remote,
        frame.arg0,
        &credit.to_le_bytes(),
    )
    .await;
    (task.await.unwrap(), frame)
}
async fn quiet(peer: &mut DuplexStream) {
    assert!(
        tokio::time::timeout(
            Duration::from_millis(15),
            Frame::read(peer, protocol::MAX_PAYLOAD, true)
        )
        .await
        .is_err()
    );
}
fn delta(frame: &Frame) -> i32 {
    assert_eq!(frame.command, protocol::OKAY);
    i32::from_le_bytes(frame.payload.as_slice().try_into().unwrap())
}

#[tokio::test]
async fn local_opt_in_and_peer_feature_are_both_required() {
    for local in [false, true] {
        for support in [false, true] {
            let (host, mut peer) = tokio::io::duplex(8192);
            let server = tokio::spawn(async move {
                let cnxn = read(&mut peer).await;
                assert_eq!(
                    String::from_utf8_lossy(&cnxn.payload).contains("delayed_ack"),
                    local
                );
                let banner = if support {
                    b"device::features=delayed_ack;\0".as_slice()
                } else {
                    b"device::features=;\0".as_slice()
                };
                send(&mut peer, protocol::CNXN, protocol::VERSION, 4096, banner).await;
                let open = read(&mut peer).await;
                assert_eq!(open.arg1 > 0, local && support);
                let credit = 1i32.to_le_bytes();
                send(
                    &mut peer,
                    protocol::OKAY,
                    77,
                    open.arg0,
                    if local && support { &credit } else { &[] },
                )
                .await;
                assert_eq!(read(&mut peer).await.command, protocol::CLSE);
            });
            let client = Client::connect_transport(
                host,
                ConnectOptions {
                    burst_mode: local,
                    ..Default::default()
                },
            )
            .await
            .unwrap();
            assert_eq!(client.burst_mode(), local && support);
            client
                .open("test", options())
                .await
                .unwrap()
                .close()
                .await
                .unwrap();
            server.await.unwrap();
        }
    }
}

#[tokio::test]
async fn legacy_external_connector_remains_classic_despite_peer_banner() {
    let (host, mut peer) = tokio::io::duplex(8192);
    let client = Client::from_negotiated_transport(
        host,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::features=delayed_ack;".into(),
            features: ["delayed_ack".into()].into(),
        },
    )
    .unwrap();
    assert!(!client.burst_mode());
    let opener = client.clone();
    let task = tokio::spawn(async move { opener.open("test", options()).await.unwrap() });
    let frame = read(&mut peer).await;
    assert_eq!(frame.arg1, 0);
    send(&mut peer, protocol::OKAY, 55, frame.arg0, &[]).await;
    task.await.unwrap().close().await.unwrap();
    assert_eq!(read(&mut peer).await.command, protocol::CLSE);
}

#[tokio::test]
async fn signed_credit_allows_one_whole_packet_overshoot_and_waits_until_positive() {
    let (client, mut peer) = attached(true, true, 4096);
    let (mut stream, opened) = open(&client, &mut peer, 41, 1).await;
    let task = tokio::spawn(async move {
        let result = stream.write_all(&vec![9; 8192]).await;
        (stream, result)
    });
    let first = read(&mut peer).await;
    assert_eq!(first.payload.len(), 4096); // 1 - 4096 = -4095, not -4096 or 0.
    quiet(&mut peer).await;
    for adjustment in [0i32, -5, 4100] {
        // credit ends at zero; still no second WRTE.
        send(
            &mut peer,
            protocol::OKAY,
            41,
            opened.arg0,
            &adjustment.to_le_bytes(),
        )
        .await;
        quiet(&mut peer).await;
    }
    send(
        &mut peer,
        protocol::OKAY,
        41,
        opened.arg0,
        &1i32.to_le_bytes(),
    )
    .await;
    assert_eq!(read(&mut peer).await.payload.len(), 4096);
    let (stream, result) = task.await.unwrap();
    result.unwrap();
    stream.close().await.unwrap();
}

#[tokio::test]
async fn repeated_okay_deltas_accumulate_above_signed_32_bits() {
    let (client, mut peer) = attached(true, true, 4096);
    let (mut stream, opened) = open(&client, &mut peer, 41, i32::MAX).await;
    send(
        &mut peer,
        protocol::OKAY,
        41,
        opened.arg0,
        &i32::MAX.to_le_bytes(),
    )
    .await;
    // These combine to +4294967294; wrapping a signed32 counter would stall.
    let task = tokio::spawn(async move {
        stream.write_all(&vec![7; 8192]).await.unwrap();
        stream
    });
    assert_eq!(read(&mut peer).await.payload.len(), 4096);
    assert_eq!(read(&mut peer).await.payload.len(), 4096);
    task.await.unwrap().close().await.unwrap();
}

static TRACE_CLOCK: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
fn clock() -> u64 {
    TRACE_CLOCK.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

#[tokio::test]
async fn partial_reads_return_only_consumed_bytes_and_keep_each_wrte_trace() {
    let (client, mut peer) = attached(true, true, 4096);
    let (mut stream, opened) = open(&client, &mut peer, 41, 1).await;
    stream.set_read_trace_clock(Some(clock)).unwrap();
    for bytes in [
        b"abc".as_slice(),
        b"defg".as_slice(),
        b"hi".as_slice(),
        b"j".as_slice(),
    ] {
        send(&mut peer, protocol::WRTE, 41, opened.arg0, bytes).await;
    }
    quiet(&mut peer).await; // enqueueing four packets is not consumption.
    let mut first = [0; 1];
    stream.read_exact(&mut first).await.unwrap();
    assert_eq!(&first, b"a");
    assert_eq!(delta(&read(&mut peer).await), 1);
    let receipt = stream.read_trace().unwrap();
    assert_eq!((receipt.sequence, receipt.payload_bytes), (1, 3));
    assert!(receipt.payload_started_us <= receipt.payload_read_us);
    assert!(
        receipt.payload_read_us <= receipt.routed_us
            && receipt.routed_us <= receipt.first_consumed_us
    );
    let mut rest = [0; 2];
    stream.read_exact(&mut rest).await.unwrap();
    assert_eq!(&rest, b"bc");
    assert_eq!(
        stream.read_trace().unwrap().first_consumed_us,
        receipt.first_consumed_us
    );
    assert_eq!(delta(&read(&mut peer).await), 2);
    for (sequence, bytes) in [
        (2, b"defg".as_slice()),
        (3, b"hi".as_slice()),
        (4, b"j".as_slice()),
    ] {
        let mut data = vec![0; bytes.len()];
        stream.read_exact(&mut data).await.unwrap();
        assert_eq!(data, bytes);
        assert_eq!(stream.read_trace().unwrap().sequence, sequence);
        assert_eq!(delta(&read(&mut peer).await), bytes.len() as i32);
    }
}

#[tokio::test]
async fn slow_stream_may_overshoot_once_and_invalid_excess_does_not_block_another_stream() {
    let (client, mut peer) = attached(true, true, 4096);
    let (mut slow, opened) = open(&client, &mut peer, 41, 1).await;
    let (mut fast, fast_open) = open(&client, &mut peer, 42, 1).await;
    // Leave one byte positive, then send an entire max_payload WRTE.
    let mut remaining = opened.arg1 as usize - 1;
    while remaining > 0 {
        let count = remaining.min(4096);
        send(&mut peer, protocol::WRTE, 41, opened.arg0, &vec![7; count]).await;
        remaining -= count;
    }
    send(&mut peer, protocol::WRTE, 41, opened.arg0, &vec![8; 4096]).await;
    send(&mut peer, protocol::WRTE, 42, fast_open.arg0, b"fast").await;
    let mut value = [0; 4];
    fast.read_exact(&mut value).await.unwrap();
    assert_eq!(&value, b"fast");
    assert_eq!(delta(&read(&mut peer).await), 4);
    assert!(!client.is_closed());
    // An additional byte exceeds the allowed one-packet overshoot.
    send(&mut peer, protocol::WRTE, 41, opened.arg0, b"x").await;
    let close = read(&mut peer).await;
    assert_eq!((close.command, close.arg1), (protocol::CLSE, 41));
    assert!(!client.is_closed());
    let mut count = 0;
    loop {
        let n = slow.read(&mut [0; 4096]).await.unwrap();
        if n == 0 {
            break;
        }
        count += n;
    }
    assert_eq!(count, opened.arg1 as usize - 1 + 4096);
    // A second service remains usable after the malformed slow stream closes.
    fast.write_all(b"fine").await.unwrap();
    let frame = read(&mut peer).await;
    assert_eq!(
        (frame.command, frame.arg1, frame.payload.as_slice()),
        (protocol::WRTE, 42, b"fine".as_slice())
    );
}

#[tokio::test]
async fn malformed_okay_lengths_and_remote_ids_close_only_the_target_stream() {
    for (remote, payload) in [
        (41, vec![]),
        (41, vec![1]),
        (41, vec![0; 3]),
        (41, vec![0; 5]),
        (0, vec![0; 4]),
        (99, vec![0; 4]),
    ] {
        let (client, mut peer) = attached(true, true, 4096);
        let (_target, opened) = open(&client, &mut peer, 41, 1).await;
        let (mut sibling, _) = open(&client, &mut peer, 42, 1).await;
        send(&mut peer, protocol::OKAY, remote, opened.arg0, &payload).await;
        let close = read(&mut peer).await;
        assert_eq!(
            (close.command, close.arg0, close.arg1),
            (protocol::CLSE, opened.arg0, 41)
        );
        sibling.write_all(b"ok").await.unwrap();
        assert_eq!(read(&mut peer).await.payload, b"ok");
        assert!(!client.is_closed());
    }
}

#[tokio::test]
async fn close_wakes_credit_waiters_and_tail_packets_remain_readable() {
    for zero_close in [false, true] {
        let (client, mut peer) = attached(true, true, 4096);
        let (mut stream, opened) = open(&client, &mut peer, 41, 0).await;
        let writer = tokio::spawn(async move { stream.write_all(b"blocked").await });
        quiet(&mut peer).await;
        send(
            &mut peer,
            protocol::CLSE,
            if zero_close { 0 } else { 41 },
            opened.arg0,
            &[],
        )
        .await;
        assert!(matches!(
            tokio::time::timeout(Duration::from_secs(1), writer)
                .await
                .unwrap()
                .unwrap(),
            Err(Error::Closed)
        ));
    }
    let (client, mut peer) = attached(true, true, 4096);
    let (mut stream, opened) = open(&client, &mut peer, 41, 1).await;
    for bytes in [b"one", b"two", b"end"] {
        send(&mut peer, protocol::WRTE, 41, opened.arg0, bytes).await;
    }
    send(&mut peer, protocol::CLSE, 41, opened.arg0, &[]).await;
    assert_eq!(read(&mut peer).await.command, protocol::CLSE);
    let mut tail = [0; 9];
    stream.read_exact(&mut tail).await.unwrap();
    assert_eq!(&tail, b"onetwoend");
    assert_eq!(stream.read(&mut [0; 1]).await.unwrap(), 0);
}

#[tokio::test]
async fn cancellation_and_transport_close_wake_credit_waiters() {
    for cancel_operation in [true, false] {
        let (client, mut peer) = attached(true, true, 4096);
        let cancellation = CancellationToken::new();
        let trigger = cancellation.clone();
        let opener = client.clone();
        let task = tokio::spawn(async move {
            opener
                .open(
                    "test",
                    OperationOptions {
                        cancellation,
                        ..options()
                    },
                )
                .await
                .unwrap()
        });
        let opened = read(&mut peer).await;
        send(
            &mut peer,
            protocol::OKAY,
            41,
            opened.arg0,
            &0i32.to_le_bytes(),
        )
        .await;
        let mut stream = task.await.unwrap();
        let writer = tokio::spawn(async move { stream.write_all(b"waiting").await });
        quiet(&mut peer).await;
        if cancel_operation {
            trigger.cancel();
        } else {
            client.close();
        }
        let error = tokio::time::timeout(Duration::from_secs(1), writer)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err();
        if cancel_operation {
            assert!(matches!(error, Error::Cancelled));
            assert_eq!(read(&mut peer).await.command, protocol::CLSE);
            assert!(!client.is_closed());
        } else {
            assert!(matches!(error, Error::Closed));
        }
    }
}

#[tokio::test]
async fn receive_budget_rejects_new_streams_and_is_reclaimed_after_dropping_closed_tails() {
    let (client, mut peer) = attached(true, true, 4096);
    let (events, mut received) = tokio::sync::mpsc::channel(128);
    let server = tokio::spawn(async move {
        let mut remote = 1;
        loop {
            let Ok(Ok(frame)) =
                tokio::time::timeout(Duration::from_secs(3), Frame::read(&mut peer, 4096, true))
                    .await
            else {
                break;
            };
            if frame.command == protocol::OPEN {
                send(
                    &mut peer,
                    protocol::OKAY,
                    remote,
                    frame.arg0,
                    &1i32.to_le_bytes(),
                )
                .await;
                send(&mut peer, protocol::WRTE, remote, frame.arg0, b"tail").await;
                send(&mut peer, protocol::CLSE, remote, frame.arg0, &[]).await;
                events.send(remote).await.unwrap();
                remote += 1;
            }
        }
    });
    let mut streams = Vec::new();
    loop {
        match client.open("test", options()).await {
            Ok(stream) => {
                streams.push(stream);
                received.recv().await.unwrap();
            }
            Err(Error::InvalidArgument(message)) => {
                assert!(message.contains("memory budget"));
                break;
            }
            Err(error) => panic!("unexpected {error:?}"),
        }
    }
    assert!(!streams.is_empty() && streams.len() < 128);
    assert!(!client.is_closed());
    // Routes have already closed. Unconsumed tail bytes still own the memory
    // reservation, until the consumer itself releases them.
    let mut first = streams.remove(0);
    let mut tail = [0; 4];
    first.read_exact(&mut tail).await.unwrap();
    assert_eq!(&tail, b"tail");
    drop(first);
    let replacement = client.open("test", options()).await.unwrap();
    received.recv().await.unwrap();
    drop(replacement);
    assert!(!client.is_closed());
    client.close();
    server.abort();
}

#[tokio::test]
async fn reverse_open_uses_peer_credit_and_reads_while_output_credit_is_exhausted() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let destination = listener.local_addr().unwrap();
    let (release, released) = tokio::sync::oneshot::channel();
    let host = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        socket.write_all(&vec![19; 8192]).await.unwrap();
        let mut input = [0; 11];
        socket.read_exact(&mut input).await.unwrap();
        assert_eq!(&input, b"from device");
        released.await.unwrap();
    });
    let (client, mut peer) = attached(true, true, 4096);
    let registrar = client.clone();
    let registration = tokio::spawn(async move {
        registrar
            .reverse_forward(&ReverseSocket::Tcp(12345), destination, true, options())
            .await
            .unwrap()
    });
    let request = read(&mut peer).await;
    assert_eq!(request.command, protocol::OPEN);
    assert!(request.arg1 > 0);
    let token = request
        .payload
        .strip_suffix(&[0])
        .unwrap()
        .split(|byte| *byte == b';')
        .nth(1)
        .unwrap()
        .to_vec();
    send(
        &mut peer,
        protocol::OKAY,
        50,
        request.arg0,
        &1i32.to_le_bytes(),
    )
    .await;
    send(&mut peer, protocol::WRTE, 50, request.arg0, b"OKAY").await;
    send(&mut peer, protocol::CLSE, 50, request.arg0, &[]).await;
    registration.await.unwrap();
    // An approved endpoint still must follow the negotiated OPEN wire shape.
    send(&mut peer, protocol::OPEN, 599, 0, &token).await;
    let rejected = loop {
        let f = read(&mut peer).await;
        if f.arg1 == 599 {
            break f;
        }
    };
    assert_eq!((rejected.command, rejected.arg0), (protocol::CLSE, 0));
    send(&mut peer, protocol::OPEN, 600, 1, &token).await;
    let accepted = loop {
        let f = read(&mut peer).await;
        if f.arg1 == 600 {
            break f;
        }
    };
    assert_eq!(delta(&accepted), request.arg1 as i32);
    let first = read(&mut peer).await;
    assert_eq!(
        (first.command, first.arg1, first.payload.len()),
        (protocol::WRTE, 600, 4096)
    );
    // The initial one-byte peer window permits this whole WRTE and becomes
    // negative. Reading in the other direction must remain independent.
    send(
        &mut peer,
        protocol::WRTE,
        600,
        accepted.arg0,
        b"from device",
    )
    .await;
    let ack = read(&mut peer).await;
    assert_eq!((ack.arg1, delta(&ack)), (600, 11));
    quiet(&mut peer).await;
    send(
        &mut peer,
        protocol::OKAY,
        600,
        accepted.arg0,
        &4096i32.to_le_bytes(),
    )
    .await;
    let second = read(&mut peer).await;
    assert_eq!(
        (second.command, second.payload.len()),
        (protocol::WRTE, 4096)
    );
    release.send(()).unwrap();
    host.await.unwrap();
    assert!(!client.is_closed());
    client.close();
}

#[tokio::test]
async fn required_stls_negotiates_burst_and_exchanges_bytes_inside_tls() {
    use interop_adb::{Identity, TlsPolicy, wireless::TlsConfig};
    use rsa::{
        RsaPrivateKey,
        pkcs8::{DecodePrivateKey, EncodePrivateKey},
    };
    use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
    use std::sync::Arc;
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let key = RsaPrivateKey::from_pkcs8_pem(&identity.to_pkcs8_pem().unwrap())
        .unwrap()
        .to_pkcs8_der()
        .unwrap();
    let config =
        rustls::ServerConfig::builder_with_provider(Arc::new(rustls_rustcrypto::provider()))
            .with_protocol_versions(&[&rustls::version::TLS13])
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(
                vec![CertificateDer::from(tls.certificate_der().to_vec())],
                PrivatePkcs8KeyDer::from(key.as_bytes().to_vec()).into(),
            )
            .unwrap();
    let (host, mut peer) = tokio::io::duplex(64 * 1024);
    let server = tokio::spawn(async move {
        let cnxn = read(&mut peer).await;
        assert!(String::from_utf8_lossy(&cnxn.payload).contains("delayed_ack"));
        send(&mut peer, protocol::STLS, 0x0100_0000, 0, &[]).await;
        assert_eq!(read(&mut peer).await.command, protocol::STLS);
        let mut peer = tokio_rustls::TlsAcceptor::from(Arc::new(config))
            .accept(peer)
            .await
            .unwrap();
        send(
            &mut peer,
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=delayed_ack;\0",
        )
        .await;
        let opened = read(&mut peer).await;
        assert!(opened.arg1 > 0);
        send(
            &mut peer,
            protocol::OKAY,
            41,
            opened.arg0,
            &8192i32.to_le_bytes(),
        )
        .await;
        assert_eq!(read(&mut peer).await.payload.len(), 4096);
        assert_eq!(read(&mut peer).await.payload.len(), 4096);
        send(&mut peer, protocol::WRTE, 41, opened.arg0, b"tls").await;
        assert_eq!(delta(&read(&mut peer).await), 3);
        assert_eq!(read(&mut peer).await.command, protocol::CLSE);
    });
    let client = Client::connect_transport(
        host,
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            tls_policy: TlsPolicy::Required,
            burst_mode: true,
            operations: options(),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert!(client.burst_mode());
    let mut stream = client.open("shell:tls", options()).await.unwrap();
    stream.write_all(&vec![7; 8192]).await.unwrap();
    let mut reply = [0; 3];
    stream.read_exact(&mut reply).await.unwrap();
    assert_eq!(&reply, b"tls");
    stream.close().await.unwrap();
    server.await.unwrap();
}

#[tokio::test]
async fn duplicate_remote_ids_are_rejected_without_changing_sibling_routes() {
    let (client, mut peer) = attached(true, true, 4096);
    let (mut first, _) = open(&client, &mut peer, 41, 1).await;
    let opener = client.clone();
    let opening = tokio::spawn(async move { opener.open("second", options()).await });
    let second = read(&mut peer).await;
    send(
        &mut peer,
        protocol::OKAY,
        41,
        second.arg0,
        &1i32.to_le_bytes(),
    )
    .await;
    assert!(matches!(opening.await.unwrap(), Err(Error::Closed)));
    let close = read(&mut peer).await;
    assert_eq!((close.command, close.arg0), (protocol::CLSE, second.arg0));
    // The reused remote ID must not attach the second route to the first.
    first.write_all(b"a").await.unwrap();
    let sent = loop {
        let f = read(&mut peer).await;
        if f.command == protocol::WRTE {
            break f;
        }
    };
    assert_eq!(sent.payload, b"a");
    assert!(!client.is_closed());
}

#[tokio::test]
async fn reverse_close_drains_queued_input_even_when_outgoing_credit_wait_is_woken() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    for _ in 0..12 {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let destination = listener.local_addr().unwrap();
        let host = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket.write_all(&vec![9; 8192]).await.unwrap();
            let mut received = Vec::new();
            socket.read_to_end(&mut received).await.unwrap();
            received
        });
        let (client, mut peer) = attached(true, true, 4096);
        let registrar = client.clone();
        let registration = tokio::spawn(async move {
            registrar
                .reverse_forward(&ReverseSocket::Tcp(12345), destination, true, options())
                .await
                .unwrap()
        });
        let request = read(&mut peer).await;
        let token = request
            .payload
            .strip_suffix(&[0])
            .unwrap()
            .split(|byte| *byte == b';')
            .nth(1)
            .unwrap()
            .to_vec();
        send(
            &mut peer,
            protocol::OKAY,
            50,
            request.arg0,
            &1i32.to_le_bytes(),
        )
        .await;
        send(&mut peer, protocol::WRTE, 50, request.arg0, b"OKAY").await;
        send(&mut peer, protocol::CLSE, 50, request.arg0, &[]).await;
        registration.await.unwrap();
        send(&mut peer, protocol::OPEN, 600, 1, &token).await;
        let accepted = loop {
            let f = read(&mut peer).await;
            if f.arg1 == 600 {
                break f;
            }
        };
        assert_eq!(accepted.command, protocol::OKAY);
        assert_eq!(read(&mut peer).await.command, protocol::WRTE);
        // Both directions now become ready in the same scheduler turn: queued
        // input can be drained, while CLSE wakes the blocked output writer.
        for _ in 0..8 {
            send(
                &mut peer,
                protocol::WRTE,
                600,
                accepted.arg0,
                &vec![7; 4096],
            )
            .await;
        }
        send(&mut peer, protocol::CLSE, 600, accepted.arg0, &[]).await;
        let received = tokio::time::timeout(Duration::from_secs(2), host)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(received.len(), 8 * 4096);
        assert!(received.iter().all(|byte| *byte == 7));
        client.close();
    }
}

#[tokio::test]
async fn consumed_credit_coalesces_under_writer_pressure_and_survives_cancelled_read() {
    let (transport, mut peer) = tokio::io::duplex(64);
    let client = Client::from_negotiated_transport_with_burst(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: ["delayed_ack".into()].into(),
        },
        true,
    )
    .unwrap();
    let (mut stream, opened) = open(&client, &mut peer, 41, 1).await;
    send(&mut peer, protocol::WRTE, 41, opened.arg0, &vec![7; 4096]).await;
    let (ready, waiting) = tokio::sync::oneshot::channel();
    let consumer = tokio::spawn(async move {
        for _ in 0..4096 {
            stream.read_exact(&mut [0; 1]).await.unwrap();
        }
        // The writer cannot flush all individual OKAYs into this 64-byte wire.
        // Cancelling a read while it tries to return credit must retain it.
        assert!(
            tokio::time::timeout(Duration::from_millis(15), stream.read(&mut [0; 1]))
                .await
                .is_err()
        );
        ready.send(()).unwrap();
        let mut next = [0; 1];
        stream.read_exact(&mut next).await.unwrap();
        assert_eq!(&next, b"x");
        stream
    });
    waiting.await.unwrap();
    let mut credited = 0;
    let mut coalesced = false;
    while credited < 4096 {
        let ack = delta(&read(&mut peer).await);
        assert!(ack > 0);
        credited += ack;
        coalesced |= ack > 1;
    }
    assert_eq!(credited, 4096);
    assert!(coalesced);
    send(&mut peer, protocol::WRTE, 41, opened.arg0, b"x").await;
    let stream = consumer.await.unwrap();
    assert_eq!(delta(&read(&mut peer).await), 1);
    stream.close().await.unwrap();
}

#[tokio::test]
async fn close_discards_pending_return_credit_before_draining_tail_with_a_full_writer() {
    let (transport, mut peer) = tokio::io::duplex(64);
    let client = Client::from_negotiated_transport_with_burst(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: ["delayed_ack".into()].into(),
        },
        true,
    )
    .unwrap();
    let (mut stream, opened) = open(&client, &mut peer, 41, 1).await;
    for _ in 0..3 {
        send(&mut peer, protocol::WRTE, 41, opened.arg0, b"a").await;
        stream.read_exact(&mut [0; 1]).await.unwrap();
        tokio::time::sleep(Duration::from_millis(1)).await;
    }
    send(&mut peer, protocol::WRTE, 41, opened.arg0, &vec![7; 4096]).await;
    for _ in 0..4096 {
        stream.read_exact(&mut [0; 1]).await.unwrap();
    }
    // Individual OKAYs have filled the outgoing wire and writer queue. The
    // unread inbound tail must remain accessible without flushing stale credit.
    send(&mut peer, protocol::WRTE, 41, opened.arg0, b"tail").await;
    send(&mut peer, protocol::CLSE, 41, opened.arg0, &[]).await;
    let mut tail = [0; 4];
    tokio::time::timeout(Duration::from_millis(100), stream.read_exact(&mut tail))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&tail, b"tail");
    client.close();
}

async fn register_reverse(
    client: &Client,
    peer: &mut DuplexStream,
    destination: std::net::SocketAddr,
) -> Vec<u8> {
    let registrar = client.clone();
    let registration = tokio::spawn(async move {
        registrar
            .reverse_forward(&ReverseSocket::Tcp(12345), destination, true, options())
            .await
            .unwrap()
    });
    let request = read(peer).await;
    let token = request
        .payload
        .strip_suffix(&[0])
        .unwrap()
        .split(|byte| *byte == b';')
        .nth(1)
        .unwrap()
        .to_vec();
    send(peer, protocol::OKAY, 50, request.arg0, &1i32.to_le_bytes()).await;
    send(peer, protocol::WRTE, 50, request.arg0, b"OKAY").await;
    send(peer, protocol::CLSE, 50, request.arg0, &[]).await;
    registration.await.unwrap();
    loop {
        if read(peer).await.command == protocol::CLSE {
            break;
        }
    }
    token
}

#[tokio::test]
async fn reverse_budget_rejection_with_a_full_writer_preserves_existing_streams() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let (transport, mut peer) = tokio::io::duplex(128);
    let client = Client::from_negotiated_transport_with_burst(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::".into(),
            features: ["delayed_ack".into()].into(),
        },
        true,
    )
    .unwrap();
    let token = register_reverse(&client, &mut peer, listener.local_addr().unwrap()).await;
    let mut streams = Vec::new();
    let mut remote = 100;
    loop {
        let opener = client.clone();
        let mut opening = tokio::spawn(async move { opener.open("held", options()).await });
        tokio::select! {
            result=&mut opening => { assert!(matches!(result.unwrap(),Err(Error::InvalidArgument(message)) if message.contains("memory budget"))); break; },
            frame=read(&mut peer) => {
                send(&mut peer,protocol::OKAY,remote,frame.arg0,&i32::MAX.to_le_bytes()).await;
                streams.push((opening.await.unwrap().unwrap(),frame));remote+=1;
            },
        }
    }
    let (mut flooding, _) = streams.remove(0);
    let writer = tokio::spawn(async move { flooding.write_all(&vec![7; 4096 * 128]).await });
    tokio::time::sleep(Duration::from_millis(15)).await;
    assert!(
        !writer.is_finished(),
        "writer queue must be full, with credit still available"
    );
    send(&mut peer, protocol::OPEN, 600, 1, &token).await;
    let (mut sibling, sibling_open) = streams.remove(0);
    // Reader routing continues even though the normal writer has no capacity.
    send(&mut peer, protocol::WRTE, 101, sibling_open.arg0, b"live").await;
    if client.is_closed() {
        panic!("budget rejection disconnected existing streams");
    }
    let mut received = [0; 4];
    let result = tokio::time::timeout(
        Duration::from_millis(100),
        sibling.read_exact(&mut received),
    )
    .await;
    assert!(
        result.is_ok(),
        "receive routing stalled after reverse budget rejection"
    );
    result.unwrap().unwrap();
    assert_eq!(&received, b"live");
    assert!(!client.is_closed());
    writer.abort();
    let _ = writer.await;
    let first = read(&mut peer).await;
    assert_eq!(first.command, protocol::WRTE);
    let rejection = read(&mut peer).await;
    assert_eq!(
        (rejection.command, rejection.arg0, rejection.arg1),
        (protocol::CLSE, 0, 600)
    );
    assert!(!client.is_closed());
    client.close();
}

#[tokio::test]
async fn reverse_tail_drain_survives_a_consumer_paused_for_more_than_five_seconds() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let destination = listener.local_addr().unwrap();
    let (resume, pause) = tokio::sync::oneshot::channel();
    let host = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        socket2::SockRef::from(&socket)
            .set_recv_buffer_size(64 * 1024)
            .unwrap();
        socket.write_all(&vec![9; 128 * 1024]).await.unwrap();
        pause.await.unwrap();
        tokio::time::sleep(Duration::from_millis(5500)).await;
        let mut received = Vec::new();
        socket.read_to_end(&mut received).await.unwrap();
        received
    });
    let (client, mut peer) = attached(true, true, 64 * 1024);
    let token = register_reverse(&client, &mut peer, destination).await;
    send(&mut peer, protocol::OPEN, 600, 1, &token).await;
    let accepted = read(&mut peer).await;
    assert_eq!(accepted.command, protocol::OKAY);
    assert_eq!(read(&mut peer).await.command, protocol::WRTE);
    let mut sent = 0;
    loop {
        send(
            &mut peer,
            protocol::WRTE,
            600,
            accepted.arg0,
            &vec![7; 64 * 1024],
        )
        .await;
        sent += 64 * 1024;
        if tokio::time::timeout(
            Duration::from_millis(30),
            Frame::read(&mut peer, protocol::MAX_PAYLOAD, true),
        )
        .await
        .is_err()
        {
            break;
        }
        assert!(
            sent < 16 * 1024 * 1024,
            "fixture did not reach destination TCP backpressure"
        );
    }
    send(&mut peer, protocol::CLSE, 600, accepted.arg0, &[]).await;
    loop {
        let frame = read(&mut peer).await;
        if frame.command == protocol::CLSE && frame.arg1 == 600 {
            break;
        }
    }
    resume.send(()).unwrap();
    let received = tokio::time::timeout(Duration::from_secs(15), host)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(received.len(), sent);
    assert!(received.iter().all(|byte| *byte == 7));
    assert!(!client.is_closed());
    client.close();
}
