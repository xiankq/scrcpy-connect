use interop_adb::{
    CancellationToken, Client, DeviceInfo, OperationOptions,
    protocol::{self, Frame},
};
use interop_scrcpy::{
    config::{DisplayOptions, Options},
    control::{self, Channel, DeviceMessage},
    session::Session,
};
use std::time::Duration;

fn client() -> (Client, tokio::io::DuplexStream) {
    let (transport, peer) = tokio::io::duplex(64 * 1024);
    (
        Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 64 * 1024,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap(),
        peer,
    )
}
async fn read(peer: &mut tokio::io::DuplexStream) -> Frame {
    tokio::time::timeout(Duration::from_secs(1), Frame::read(peer, 64 * 1024, true))
        .await
        .unwrap()
        .unwrap()
}
async fn accept(peer: &mut tokio::io::DuplexStream, remote: u32) -> u32 {
    let open = read(peer).await;
    assert_eq!(open.command, protocol::OPEN);
    Frame::new(protocol::OKAY, remote, open.arg0, [])
        .write(peer)
        .await
        .unwrap();
    open.arg0
}

#[test]
fn control_queries_and_display_power_use_upstream_wire_values() {
    assert_eq!(control::Message::GetClipboard.encode().unwrap(), [8, 0]);
    assert_eq!(
        control::Message::SetDisplayPower(false).encode().unwrap(),
        [10, 0]
    );
}

#[test]
fn display_resize_preserves_unsigned_wire_dimensions_without_product_limits() {
    for (width, height, expected) in [
        (1, 2, [21, 0, 1, 0, 2]),
        (0x1234, 0xabcd, [21, 0x12, 0x34, 0xab, 0xcd]),
        (u16::MAX, u16::MAX, [21, 255, 255, 255, 255]),
    ] {
        assert_eq!(
            control::Message::ResizeDisplay { width, height }
                .encode()
                .unwrap(),
            expected
        );
    }
    for (width, height) in [(0, 1), (1, 0), (0, 0)] {
        assert!(
            control::Message::ResizeDisplay { width, height }
                .encode()
                .is_err()
        );
    }
}

#[test]
fn new_display_size_does_not_inherit_decoder_limit() {
    for size in [(16385, 1), (1, 16385), (u16::MAX, u16::MAX)] {
        let options = Options {
            display: Some(DisplayOptions {
                size: Some(size),
                density: None,
            }),
            ..Options::default()
        };
        assert!(
            options
                .command("/data/local/tmp/test.jar", 1)
                .unwrap()
                .contains(&format!("new_display={}x{} ", size.0, size.1))
        );
    }
    for size in [(0, 1), (1, 0), (0, 0)] {
        let options = Options {
            display: Some(DisplayOptions {
                size: Some(size),
                density: None,
            }),
            ..Options::default()
        };
        assert!(options.validate().is_err());
    }
}

#[test]
fn session_dimensions_preserve_server_integers_without_decoder_limits() {
    use interop_scrcpy::capture::session_dimensions;
    let header = |flags: u32, width: u32, height: u32| {
        let mut bytes = [0; 12];
        bytes[..4].copy_from_slice(&flags.to_be_bytes());
        bytes[4..8].copy_from_slice(&width.to_be_bytes());
        bytes[8..].copy_from_slice(&height.to_be_bytes());
        bytes
    };
    for flags in [0x8000_0000, 0x8000_0001] {
        for size in [(16385, 1), (65535, 65536), (i32::MAX as u32, 1)] {
            assert_eq!(
                session_dimensions(&header(flags, size.0, size.1)).unwrap(),
                Some(size)
            );
        }
        for size in [(0, 1), (1, 0), (0x8000_0000, 1), (1, u32::MAX)] {
            assert!(session_dimensions(&header(flags, size.0, size.1)).is_err());
        }
    }
    assert!(session_dimensions(&header(0x8000_0002, 1, 1)).is_err());
    assert_eq!(session_dimensions(&header(0, 1, 1)).unwrap(), None);
}

#[test]
fn incoming_clipboard_uses_its_own_wire_limit() {
    for length in [
        control::CLIPBOARD_MAX,
        control::CLIPBOARD_MAX + 1,
        control::DEVICE_CLIPBOARD_MAX,
    ] {
        let mut bytes = vec![0];
        bytes.extend_from_slice(&(length as u32).to_be_bytes());
        bytes.resize(5 + length, b'x');
        let (message, used) = control::decode_device_message(&bytes).unwrap().unwrap();
        assert!(matches!(message,DeviceMessage::Clipboard(text) if text.len()==length));
        assert_eq!(used, bytes.len());
    }
    let mut bytes = vec![0];
    bytes.extend_from_slice(&((control::DEVICE_CLIPBOARD_MAX + 1) as u32).to_be_bytes());
    assert!(control::decode_device_message(&bytes).is_err());
}

#[tokio::test]
async fn control_channel_receives_legal_clipboard_above_outgoing_limit_and_releases_before_flush() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let opener = client.clone();
    let opening = tokio::spawn(async move {
        opener
            .open("fixture:", OperationOptions::default())
            .await
            .unwrap()
    });
    let local = accept(&mut peer, 77).await;
    let channel = Channel::start(opening.await.unwrap(), cancellation).unwrap();
    let mut events = channel.subscribe();
    let length = control::DEVICE_CLIPBOARD_MAX;
    let mut bytes = vec![0];
    bytes.extend_from_slice(&(length as u32).to_be_bytes());
    bytes.resize(5 + length, b'x');
    for chunk in bytes.chunks(64 * 1024) {
        Frame::new(protocol::WRTE, 77, local, chunk)
            .write(&mut peer)
            .await
            .unwrap();
        assert_eq!(read(&mut peer).await.command, protocol::OKAY);
    }
    let message = tokio::time::timeout(Duration::from_secs(1), events.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(message,DeviceMessage::Clipboard(text) if text.len()==length));
    channel.close().await;
    client
        .flush_closed_streams(OperationOptions::default())
        .await
        .unwrap();
    let close = read(&mut peer).await;
    assert_eq!((close.command, close.arg0), (protocol::CLSE, local));
    client.close();
}

#[tokio::test]
async fn stalled_identity_has_a_local_startup_deadline() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session = Session::new(client.clone(), 1, Options::default(), cancellation)
        .unwrap()
        .with_startup_timeout(Duration::from_millis(25))
        .unwrap();
    let state = session.launch_state();
    let startup = tokio::spawn(async move { session.launch_prepared("exec fixture").await });
    let local = accept(&mut peer, 77).await;
    let start = read(&mut peer).await;
    assert_eq!(start.command, protocol::WRTE);
    let start = String::from_utf8(start.payload).unwrap();
    let nonce = start.strip_prefix("START:").unwrap().trim_end();
    Frame::new(protocol::OKAY, 77, local, [])
        .write(&mut peer)
        .await
        .unwrap();
    let result = tokio::time::timeout(Duration::from_millis(250), startup)
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        result,
        Err(interop_scrcpy::Error::Failure {
            code: "timeout",
            ..
        })
    ));
    assert!(!client.is_closed(), "单捕获启动超时不能关闭调用方 ADB 传输");
    let stop = read(&mut peer).await;
    assert_eq!(stop.payload, format!("STOP:{nonce}\n").as_bytes());
    Frame::new(protocol::OKAY, 77, local, [])
        .write(&mut peer)
        .await
        .unwrap();
    Frame::new(
        protocol::WRTE,
        77,
        local,
        format!("__INTEROP_DONE__{nonce}\n").as_bytes(),
    )
    .write(&mut peer)
    .await
    .unwrap();
    state.wait_exited(&client).await.unwrap();
    client.close();
}

#[tokio::test]
async fn control_is_connected_before_video_metadata_without_waiting_for_keyframe() {
    let (client, mut peer) = client();
    let cancellation = CancellationToken::new();
    let session =
        Session::new(client.clone(), 1, Options::default(), cancellation.clone()).unwrap();
    let connecting = tokio::spawn(async move { session.connect().await });
    let video = accept(&mut peer, 77).await;
    let control = accept(&mut peer, 78).await;
    let mut metadata = vec![0; 65];
    metadata.extend_from_slice(b"h264");
    metadata.extend_from_slice(&0x8000_0000u32.to_be_bytes());
    metadata.extend_from_slice(&640u32.to_be_bytes());
    metadata.extend_from_slice(&480u32.to_be_bytes());
    Frame::new(protocol::WRTE, 77, video, metadata)
        .write(&mut peer)
        .await
        .unwrap();
    assert_eq!(read(&mut peer).await.command, protocol::OKAY);
    let connected = tokio::time::timeout(Duration::from_millis(200), connecting)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(connected.control.is_some());
    assert_ne!(video, control);
    drop(connected);
    cancellation.cancel();
    client.close();
}

#[test]
fn channel_flags_are_explicit_and_all_disabled_is_rejected() {
    let options = Options {
        video: false,
        audio: true,
        control: false,
        display_id: 3,
        keep_active: true,
        power_off_on_close: true,
        stay_awake: true,
        cleanup: false,
        ..Options::default()
    };
    let command = options.command("/data/local/tmp/test.jar", 1).unwrap();
    for flag in [
        "video=false",
        "audio=true",
        "audio_codec=raw",
        "audio_source=output",
        "control=false",
        "display_id=3",
        "keep_active=true",
        "power_off_on_close=true",
        "stay_awake=true",
        "cleanup=false",
    ] {
        assert!(command.contains(flag), "{flag}");
    }
    let invalid = Options {
        video: false,
        audio: false,
        control: false,
        ..options
    };
    assert!(invalid.validate().is_err());
}

#[tokio::test]
async fn combined_capture_accepts_all_channels_before_reading_their_metadata() {
    let (client, mut peer) = client();
    let options = Options {
        audio: true,
        ..Options::default()
    };
    let session = Session::new(client.clone(), 1, options, CancellationToken::new()).unwrap();
    let connecting = tokio::spawn(async move { session.connect_channels().await });
    let video = accept(&mut peer, 77).await;
    let audio = accept(&mut peer, 78).await;
    let control = accept(&mut peer, 79).await;
    let mut metadata = vec![0; 65];
    metadata[1..8].copy_from_slice(b"fixture");
    metadata.extend_from_slice(b"h264");
    metadata.extend_from_slice(&0x8000_0000u32.to_be_bytes());
    metadata.extend_from_slice(&640u32.to_be_bytes());
    metadata.extend_from_slice(&480u32.to_be_bytes());
    Frame::new(protocol::WRTE, 77, video, metadata)
        .write(&mut peer)
        .await
        .unwrap();
    assert_eq!(read(&mut peer).await.command, protocol::OKAY);
    Frame::new(protocol::WRTE, 78, audio, b"\0raw")
        .write(&mut peer)
        .await
        .unwrap();
    assert_eq!(read(&mut peer).await.command, protocol::OKAY);
    let connected = tokio::time::timeout(Duration::from_millis(200), connecting)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(connected.device_name, "fixture");
    assert!(connected.video.is_some());
    assert!(connected.audio.is_some());
    assert!(connected.control.is_some());
    assert!(connected.video_initial.is_some());
    assert_ne!(video, audio);
    assert_ne!(audio, control);
    drop(connected);
    client.close();
}

#[tokio::test]
async fn control_only_reads_the_primary_preamble_without_waiting_for_media() {
    let (client, mut peer) = client();
    let options = Options {
        video: false,
        control: true,
        ..Options::default()
    };
    let session = Session::new(client.clone(), 1, options, CancellationToken::new()).unwrap();
    let connecting = tokio::spawn(async move { session.connect_channels().await });
    let control = accept(&mut peer, 77).await;
    let mut metadata = vec![0; 65];
    metadata[1..8].copy_from_slice(b"fixture");
    Frame::new(protocol::WRTE, 77, control, metadata)
        .write(&mut peer)
        .await
        .unwrap();
    assert_eq!(read(&mut peer).await.command, protocol::OKAY);
    let connected = tokio::time::timeout(Duration::from_millis(200), connecting)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(connected.device_name, "fixture");
    assert!(connected.video.is_none());
    assert!(connected.audio.is_none());
    assert!(connected.control.is_some());
    assert!(connected.video_initial.is_none());
    drop(connected);
    client.close();
}
