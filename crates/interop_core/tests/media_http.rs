use interop_core::media::http::MediaStreams;
use serde_json::{Value, json};
use std::{net::Ipv4Addr, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};

const TOKEN: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const DEADLINE: Duration = Duration::from_secs(5);

async fn raw_listener() -> TcpListener {
    TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap()
}

async fn open(streams: &MediaStreams, raw: &TcpListener) -> Value {
    streams
        .command(
            "media.open",
            &json!({"kind":"audio","port":raw.local_addr().unwrap().port(),"token":TOKEN,"generation":1}),
        )
        .await
        .unwrap()
}

fn endpoint(relay: &Value) -> (&str, String) {
    let (address, secret) = relay["url"]
        .as_str()
        .unwrap()
        .strip_prefix("http://")
        .unwrap()
        .split_once('/')
        .unwrap();
    (address, format!("/{secret}"))
}

async fn client(relay: &Value, correct_nonce: bool) -> TcpStream {
    let (address, path) = endpoint(relay);
    let mut stream = TcpStream::connect(address).await.unwrap();
    let path = if correct_nonce { &path } else { "/wrong-nonce" };
    stream
        .write_all(format!("GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
        .await
        .unwrap();
    stream
}

async fn authorized_raw(raw: &TcpListener) -> TcpStream {
    let (mut source, _) = tokio::time::timeout(DEADLINE, raw.accept())
        .await
        .expect("authorized client connects raw source")
        .unwrap();
    let mut supplied = [0; 65];
    tokio::time::timeout(DEADLINE, source.read_exact(&mut supplied))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&supplied[..64], TOKEN.as_bytes());
    assert_eq!(supplied[64], b'\n');
    source
}

async fn closed_raw(source: &mut TcpStream) {
    assert_eq!(
        tokio::time::timeout(DEADLINE, source.read(&mut [0; 1]))
            .await
            .expect("dropping HTTP playback must release even a completely silent raw source")
            .unwrap(),
        0
    );
}

async fn status(streams: &MediaStreams, relay: &Value, expected: &str) -> Value {
    tokio::time::timeout(DEADLINE, async {
        loop {
            let value = streams
                .command("media.status", &json!({"relayId":relay["relayId"]}))
                .await
                .unwrap();
            if value["status"] == expected {
                return value;
            }
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .expect("relay reaches terminal or streaming state")
}

#[tokio::test]
async fn wrong_http_nonce_never_connects_or_reads_the_raw_source() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let relay = open(&streams, &raw).await;
    let mut rejected = client(&relay, false).await;
    let mut response = Vec::new();
    tokio::time::timeout(DEADLINE, rejected.read_to_end(&mut response))
        .await
        .unwrap()
        .unwrap();
    assert!(response.starts_with(b"HTTP/1.1 403 Forbidden\r\n"));
    assert!(
        tokio::time::timeout(Duration::from_millis(150), raw.accept())
            .await
            .is_err(),
        "a guessed HTTP URL must not consume the authenticated single-use raw source"
    );
    assert_eq!(status(&streams, &relay, "waiting").await["packets"], 0);
    let authorized = client(&relay, true).await;
    let mut source = authorized_raw(&raw).await;
    drop(authorized);
    closed_raw(&mut source).await;
}

#[tokio::test]
async fn dropping_http_client_releases_silent_source_before_first_packet_and_after_streaming() {
    let streams = MediaStreams::default();
    for send_first_packet in [false, true] {
        let raw = raw_listener().await;
        let relay = open(&streams, &raw).await;
        let mut playback = client(&relay, true).await;
        let mut source = authorized_raw(&raw).await;
        if send_first_packet {
            source.write_u64(123_456).await.unwrap();
            source.write_u32(4).await.unwrap();
            source.write_all(&[1, 2, 3, 4]).await.unwrap();
            let mut header = Vec::new();
            tokio::time::timeout(DEADLINE, async {
                while !header.ends_with(b"\r\n\r\n") {
                    assert!(header.len() < 4096);
                    header.push(playback.read_u8().await.unwrap());
                }
            })
            .await
            .unwrap();
            assert!(header.starts_with(b"HTTP/1.1 200 OK\r\n"));
            assert_eq!(status(&streams, &relay, "streaming").await["packets"], 1);
        }
        // No further upstream packet is supplied to trigger a write failure.
        drop(playback);
        closed_raw(&mut source).await;
        status(&streams, &relay, "closed").await;
    }
}

#[tokio::test]
async fn thirty_two_terminated_tcp_relays_do_not_exhaust_admission() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let mut first = None;
    for _ in 0..32 {
        let relay = open(&streams, &raw).await;
        if first.is_none() {
            first = Some(relay["relayId"].clone());
        }
        let _playback = client(&relay, true).await;
        let source = authorized_raw(&raw).await;
        drop(source); // Actual upstream EOF ends the relay with a protocol failure.
        status(&streams, &relay, "failed").await;
    }
    let last = open(&streams, &raw).await;
    let playback = client(&last, true).await;
    let mut source = authorized_raw(&raw).await;
    assert_eq!(
        streams
            .command("media.status", &json!({"relayId":first.unwrap()}))
            .await
            .unwrap_err()
            .code,
        "media_ended"
    );
    drop(playback);
    closed_raw(&mut source).await;
}

#[tokio::test]
async fn active_limit_is_preserved_and_close_is_idempotent_with_real_waiting_and_static_sockets() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let mut waiting = Vec::new();
    for _ in 0..32 {
        waiting.push(open(&streams, &raw).await);
    }
    assert_eq!(
        streams
            .command(
                "media.open",
                &json!({"kind":"audio","port":raw.local_addr().unwrap().port(),"token":TOKEN})
            )
            .await
            .unwrap_err()
            .code,
        "resource_busy"
    );
    for relay in waiting {
        for _ in 0..2 {
            assert_eq!(
                streams
                    .command("media.close", &json!({"relayId":relay["relayId"]}))
                    .await
                    .unwrap()["closed"],
                true
            );
        }
    }
    let relay = open(&streams, &raw).await;
    let _playback = client(&relay, true).await;
    let mut source = authorized_raw(&raw).await;
    for _ in 0..2 {
        assert_eq!(
            streams
                .command("media.close", &json!({"relayId":relay["relayId"]}))
                .await
                .unwrap()["closed"],
            true
        );
    }
    closed_raw(&mut source).await;
    assert_eq!(
        streams
            .command("media.status", &json!({"relayId":relay["relayId"]}))
            .await
            .unwrap_err()
            .code,
        "media_ended"
    );
}

const SPS: &[u8] = &[
    0, 0, 0, 1, 0x67, 0x42, 0xc0, 0x29, 0x8d, 0x68, 0x12, 5, 0x1a, 0x42, 12, 2, 12, 15, 8, 0x84,
    0x6a, 0,
];
const PPS: &[u8] = &[0, 0, 0, 1, 0x68, 0xce, 1, 0xa8, 0x35, 0xc8];

async fn open_video(streams: &MediaStreams, raw: &TcpListener, generation: u64) -> Value {
    streams.command("media.open",&json!({"kind":"video","codec":"h264","port":raw.local_addr().unwrap().port(),"token":TOKEN,"generation":generation})).await.unwrap()
}

async fn dimensions(source: &mut TcpStream, width: u32, height: u32) {
    source.write_u32(0x8000_0000).await.unwrap();
    source.write_u32(width).await.unwrap();
    source.write_u32(height).await.unwrap();
}

async fn packet(source: &mut TcpStream, flags: u64, bytes: &[u8]) {
    source.write_u64(flags).await.unwrap();
    source.write_u32(bytes.len() as u32).await.unwrap();
    source.write_all(bytes).await.unwrap();
}

async fn config(source: &mut TcpStream, changed: bool) {
    let mut sps = SPS.to_vec();
    if changed {
        sps[7] = 0x2a;
    }
    packet(source, 1 << 62, &sps).await;
    packet(source, 1 << 62, PPS).await;
}

async fn frame(source: &mut TcpStream, pts: u64, key: bool) {
    packet(
        source,
        pts | if key { 1 << 61 } else { 0 },
        &[0, 0, 0, 1, if key { 0x65 } else { 0x41 }, 1],
    )
    .await;
}

async fn response_header(client: &mut TcpStream) {
    let mut header = Vec::new();
    tokio::time::timeout(DEADLINE, async {
        while !header.ends_with(b"\r\n\r\n") {
            assert!(header.len() < 4096);
            header.push(client.read_u8().await.unwrap());
        }
    })
    .await
    .unwrap();
    assert!(header.starts_with(b"HTTP/1.1 200 OK\r\n"));
}

async fn http_chunk(client: &mut TcpStream) -> Option<Vec<u8>> {
    tokio::time::timeout(DEADLINE, async {
        let mut line = Vec::new();
        while !line.ends_with(b"\r\n") {
            assert!(line.len() < 32);
            line.push(client.read_u8().await.unwrap());
        }
        let len = usize::from_str_radix(std::str::from_utf8(&line[..line.len() - 2]).unwrap(), 16)
            .unwrap();
        assert!(len < 65536);
        let mut data = vec![0; len];
        client.read_exact(&mut data).await.unwrap();
        let mut crlf = [0; 2];
        client.read_exact(&mut crlf).await.unwrap();
        assert_eq!(crlf, *b"\r\n");
        (len != 0).then_some(data)
    })
    .await
    .expect("bounded complete HTTP chunk")
}

async fn first_matroska(client: &mut TcpStream) -> Vec<u8> {
    response_header(client).await;
    let mut data = http_chunk(client).await.unwrap();
    data.extend(http_chunk(client).await.unwrap());
    data
}

async fn graceful_end(client: &mut TcpStream) {
    assert!(
        http_chunk(client).await.is_none(),
        "generation must end with the HTTP terminal chunk"
    );
    assert_eq!(
        tokio::time::timeout(DEADLINE, client.read(&mut [0; 1]))
            .await
            .unwrap()
            .unwrap(),
        0
    );
}

async fn next_endpoint(streams: &MediaStreams, relay: &Value, generation: u64) -> Value {
    tokio::time::timeout(DEADLINE, async {
        loop {
            let state = streams
                .command("media.status", &json!({"relayId":relay["relayId"]}))
                .await
                .unwrap();
            assert!(
                state["status"] != "failed",
                "generation must remain live; code={}",
                state["errorCode"]
            );
            if state["endpoint"]["generation"] == generation {
                return state["endpoint"].clone();
            }
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .expect("bounded new generation endpoint")
}

fn matroska_has_first_keyframe_origin_and_size(
    data: &[u8],
    width: u64,
    height: u64,
    changed: bool,
) {
    use webm_iterable::{WebmIterator, matroska_spec::MatroskaSpec as Tag};
    let tags = WebmIterator::new(data, &[])
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert!(tags.contains(&Tag::PixelWidth(width)));
    assert!(tags.contains(&Tag::PixelHeight(height)));
    assert!(
        tags.contains(&Tag::Timestamp(0)),
        "each generation rebases the actual first source PTS"
    );
    let block = tags
        .iter()
        .find_map(|tag| {
            if let Tag::SimpleBlock(bytes) = tag {
                Some(bytes)
            } else {
                None
            }
        })
        .unwrap();
    assert_ne!(
        block[3] & 0x80,
        0,
        "interframes must be skipped until a real keyframe"
    );
    if changed {
        let avcc = tags
            .iter()
            .find_map(|tag| {
                if let Tag::CodecPrivate(bytes) = tag {
                    Some(bytes)
                } else {
                    None
                }
            })
            .unwrap();
        assert_eq!(avcc[3], 0x2a);
    }
}

#[tokio::test]
async fn two_rotations_and_config_only_change_reuse_one_raw_connection_and_issue_fresh_http_generations()
 {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let relay = open_video(&streams, &raw, 1).await;
    let mut playback = client(&relay, true).await;
    let mut source = authorized_raw(&raw).await;
    dimensions(&mut source, 288, 640).await;
    config(&mut source, false).await;
    frame(&mut source, 123_456, true).await;
    matroska_has_first_keyframe_origin_and_size(
        &first_matroska(&mut playback).await,
        288,
        640,
        false,
    );

    // Repeated multi-packet SPS/PPS is a single complete equal config burst.
    config(&mut source, false).await;
    frame(&mut source, 223_456, false).await;
    assert!(http_chunk(&mut playback).await.is_some());
    assert_eq!(
        streams
            .command("media.status", &json!({"relayId":relay["relayId"]}))
            .await
            .unwrap()["generation"],
        1
    );
    let mut previous = relay.clone();
    for (index, (width, height, changed)) in
        [(640, 288, false), (288, 640, false), (288, 640, true)]
            .into_iter()
            .enumerate()
    {
        dimensions(&mut source, width, height).await;
        config(&mut source, changed).await;
        frame(&mut source, 1_000_000 + index as u64 * 1_000_000, false).await;
        frame(&mut source, 1_123_456 + index as u64 * 1_000_000, true).await;
        graceful_end(&mut playback).await;
        let next = next_endpoint(&streams, &relay, index as u64 + 2).await;
        assert!(next["relayId"] == relay["relayId"]);
        assert!(
            next["url"] != previous["url"],
            "each generation requires a new authenticated delivery handle"
        );
        assert_eq!(next["width"], width);
        assert_eq!(next["height"], height);
        let (address, _) = endpoint(&next);
        let (_, old_path) = endpoint(&previous);
        let mut stale = TcpStream::connect(address).await.unwrap();
        stale
            .write_all(format!("GET {old_path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
            .await
            .unwrap();
        let mut rejected = Vec::new();
        tokio::time::timeout(DEADLINE, stale.read_to_end(&mut rejected))
            .await
            .unwrap()
            .unwrap();
        assert!(rejected.starts_with(b"HTTP/1.1 403 Forbidden\r\n"));
        drop(playback);
        playback = client(&next, true).await;
        matroska_has_first_keyframe_origin_and_size(
            &first_matroska(&mut playback).await,
            width as u64,
            height as u64,
            changed,
        );
        previous = next;
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(150), raw.accept())
            .await
            .is_err(),
        "three generation changes must not consume another raw source"
    );
    streams
        .command("media.close", &json!({"relayId":relay["relayId"]}))
        .await
        .unwrap();
    closed_raw(&mut source).await;
}

async fn running_video(
    streams: &MediaStreams,
    raw: &TcpListener,
    generation: u64,
) -> (Value, TcpStream, TcpStream) {
    let relay = open_video(streams, raw, generation).await;
    let mut playback = client(&relay, true).await;
    let mut source = authorized_raw(raw).await;
    dimensions(&mut source, 288, 640).await;
    config(&mut source, false).await;
    frame(&mut source, 0, true).await;
    first_matroska(&mut playback).await;
    (relay, playback, source)
}

#[tokio::test]
async fn consecutive_encoder_sessions_before_a_frame_keep_only_the_latest_configuration() {
    for changed in [false, true] {
        let streams = MediaStreams::default();
        let raw = raw_listener().await;
        let (relay, mut playback, mut source) = running_video(&streams, &raw, 1).await;
        // The first encoder is reset after CSD, before any frame. The second
        // encoder's SPS/PPS may be equal or different; neither may be appended
        // to the abandoned session's configuration.
        dimensions(&mut source, 288, 640).await;
        config(&mut source, false).await;
        dimensions(&mut source, 288, 640).await;
        config(&mut source, changed).await;
        frame(&mut source, 99_999, true).await;

        if changed {
            graceful_end(&mut playback).await;
            let next = next_endpoint(&streams, &relay, 2).await;
            drop(playback);
            playback = client(&next, true).await;
            matroska_has_first_keyframe_origin_and_size(
                &first_matroska(&mut playback).await,
                288,
                640,
                true,
            );
        } else {
            use webm_iterable::{WebmIterator, matroska_spec::MatroskaSpec as Tag};
            let chunk = http_chunk(&mut playback)
                .await
                .expect("equal replacement CSD must keep the original HTTP stream live");
            let tags = WebmIterator::new(chunk.as_slice(), &[])
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            assert!(tags.contains(&Tag::SimpleBlock(vec![
                0x81, 0, 0, 0x80, 0, 0, 0, 2, 0x65, 1
            ])));
            assert_eq!(status(&streams, &relay, "streaming").await["generation"], 1);
        }
        streams
            .command("media.close", &json!({"relayId":relay["relayId"]}))
            .await
            .unwrap();
        closed_raw(&mut source).await;
    }
}

#[tokio::test]
async fn absent_next_generation_consumer_times_out_and_releases_the_unique_raw_source() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let (relay, mut playback, mut source) = running_video(&streams, &raw, 1).await;
    dimensions(&mut source, 640, 288).await;
    frame(&mut source, 99_999, true).await;
    graceful_end(&mut playback).await;
    next_endpoint(&streams, &relay, 2).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(25), source.read(&mut [0; 1]))
            .await
            .expect("an unattached generation must not retain capture indefinitely")
            .unwrap(),
        0
    );
    assert_eq!(
        status(&streams, &relay, "failed").await["errorCode"],
        "media_timeout"
    );
}

#[tokio::test]
async fn malformed_replacement_config_ends_old_http_and_fails_without_reconnecting_raw() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let (relay, mut playback, mut source) = running_video(&streams, &raw, 1).await;
    packet(&mut source, 1 << 62, &[0, 0, 0, 1, 0x67]).await;
    frame(&mut source, 99_999, true).await;
    graceful_end(&mut playback).await;
    closed_raw(&mut source).await;
    assert_eq!(
        status(&streams, &relay, "failed").await["errorCode"],
        "media_mux"
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(100), raw.accept())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn non_keyframes_and_generation_integer_overflow_fail_bounded_without_renumbering() {
    for generation in [1, u64::MAX] {
        let streams = MediaStreams::default();
        let raw = raw_listener().await;
        let (relay, mut playback, mut source) = running_video(&streams, &raw, generation).await;
        dimensions(&mut source, 640, 288).await;
        for pts in 1..=if generation == 1 { 63 } else { 1 } {
            frame(&mut source, pts, false).await;
        }
        graceful_end(&mut playback).await;
        closed_raw(&mut source).await;
        let failed = status(&streams, &relay, "failed").await;
        assert_eq!(
            failed["errorCode"],
            if generation == 1 {
                "media_keyframe"
            } else {
                "media_generation_exhausted"
            }
        );
        assert_eq!(failed["generation"], generation);
    }
}

#[tokio::test]
async fn eight_wrong_nonces_for_the_next_generation_close_the_source_without_a_second_accept() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let (relay, mut playback, mut source) = running_video(&streams, &raw, 1).await;
    dimensions(&mut source, 640, 288).await;
    frame(&mut source, 99_999, true).await;
    graceful_end(&mut playback).await;
    let next = next_endpoint(&streams, &relay, 2).await;
    for _ in 0..8 {
        let mut denied = client(&next, false).await;
        let mut response = Vec::new();
        tokio::time::timeout(DEADLINE, denied.read_to_end(&mut response))
            .await
            .unwrap()
            .unwrap();
        assert!(response.starts_with(b"HTTP/1.1 403 Forbidden\r\n"));
    }
    closed_raw(&mut source).await;
    assert_eq!(
        status(&streams, &relay, "failed").await["errorCode"],
        "media_auth"
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(100), raw.accept())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn missing_initial_packet_releases_the_raw_source_after_the_real_protocol_deadline() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let relay = open_video(&streams, &raw, 1).await;
    let _playback = client(&relay, true).await;
    let mut source = authorized_raw(&raw).await;
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(15), source.read(&mut [0; 1]))
            .await
            .expect("initial input deadline must release capture")
            .unwrap(),
        0
    );
    assert_eq!(
        status(&streams, &relay, "failed").await["errorCode"],
        "media_timeout"
    );
}

#[tokio::test]
async fn a_truncated_configuration_payload_still_times_out_and_releases_capture() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let (relay, _playback, mut source) = running_video(&streams, &raw, 1).await;
    dimensions(&mut source, 640, 288).await;
    source.write_u64(1 << 62).await.unwrap();
    source.write_u32(100).await.unwrap();
    source.write_all(&[1, 2]).await.unwrap(); // Actual incomplete configuration payload.
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(15), source.read(&mut [0; 1]))
            .await
            .expect("truncated configuration deadline must release capture")
            .unwrap(),
        0
    );
    assert_eq!(
        status(&streams, &relay, "failed").await["errorCode"],
        "media_timeout"
    );
}

#[tokio::test]
async fn complete_video_configuration_can_remain_idle_until_capture_resumes() {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let (relay, mut playback, mut source) = running_video(&streams, &raw, 1).await;
    // RESET_VIDEO may finish its session/configuration just before capture is
    // cooperatively suspended. These are complete units, not a truncated packet.
    dimensions(&mut source, 288, 640).await;
    config(&mut source, false).await;
    tokio::time::sleep(Duration::from_millis(10_300)).await;
    let retained = streams
        .command("media.status", &json!({"relayId":relay["relayId"]}))
        .await
        .unwrap();
    assert_eq!(
        retained["status"], "streaming",
        "valid idle configuration must not end the retained window: {retained}"
    );
    frame(&mut source, 12_000_000, true).await;
    assert!(http_chunk(&mut playback).await.is_some());
    assert_eq!(
        streams
            .command("media.status", &json!({"relayId":relay["relayId"]}))
            .await
            .unwrap()["generation"],
        1
    );
    streams
        .command("media.close", &json!({"relayId":relay["relayId"]}))
        .await
        .unwrap();
    closed_raw(&mut source).await;
}

// A connected consumer with a closed receive window is different from an idle
// captured screen: there are real compressed packets waiting to be delivered.
async fn stopped_http_consumer_releases_capture(explicit_close: bool) {
    let streams = MediaStreams::default();
    let raw = raw_listener().await;
    let relay = open_video(&streams, &raw, 1).await;
    let (address, path) = endpoint(&relay);
    let socket = tokio::net::TcpSocket::new_v4().unwrap();
    socket.set_recv_buffer_size(4096).unwrap();
    let mut playback = socket.connect(address.parse().unwrap()).await.unwrap();
    playback
        .write_all(format!("GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
        .await
        .unwrap();
    let mut source = authorized_raw(&raw).await;
    dimensions(&mut source, 288, 640).await;
    config(&mut source, false).await;
    frame(&mut source, 0, true).await;
    first_matroska(&mut playback).await;
    status(&streams, &relay, "streaming").await;
    // Keep playback alive without reading any more bytes. Enough valid H264
    // packets are supplied to fill actual TCP buffers, not a mocked write.
    let (mut source_reader, mut source_writer) = source.into_split();
    let sender = tokio::spawn(async move {
        let mut bytes = vec![0x55; 1024 * 1024];
        bytes[..5].copy_from_slice(&[0, 0, 0, 1, 0x41]);
        for index in 1..=64u64 {
            source_writer.write_u64(index * 1000).await?;
            source_writer.write_u32(bytes.len() as u32).await?;
            source_writer.write_all(&bytes).await?;
        }
        Ok::<_, std::io::Error>(())
    });
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(
        !sender.is_finished(),
        "real TCP backpressure must be reached before checking its deadline"
    );
    if explicit_close {
        streams
            .command("media.close", &json!({"relayId":relay["relayId"]}))
            .await
            .unwrap();
    }
    let released = tokio::time::timeout(
        Duration::from_secs(if explicit_close { 1 } else { 12 }),
        source_reader.read(&mut [0; 1]),
    )
    .await;
    let final_status = if !explicit_close {
        Some(
            streams
                .command("media.status", &json!({"relayId":relay["relayId"]}))
                .await
                .unwrap(),
        )
    } else {
        None
    };
    // Always cancel the blocked writer, including on the intentional red run.
    streams
        .command("media.close", &json!({"relayId":relay["relayId"]}))
        .await
        .unwrap();
    sender.abort();
    let _ = sender.await;
    drop(playback);
    assert!(
        matches!(released, Ok(Ok(0)) | Ok(Err(_))),
        "a non-reading live HTTP consumer must release raw capture within its delivery budget; status={final_status:?}",
    );
    if let Some(final_status) = final_status {
        assert_eq!(final_status["status"], "failed");
        assert_eq!(final_status["errorCode"], "media_timeout");
    }
}

#[tokio::test]
async fn video_transport_deadline_nonreading_http_consumer_releases_raw_capture() {
    stopped_http_consumer_releases_capture(false).await;
}

#[tokio::test]
async fn video_transport_deadline_cancel_releases_a_backpressured_http_consumer() {
    stopped_http_consumer_releases_capture(true).await;
}
