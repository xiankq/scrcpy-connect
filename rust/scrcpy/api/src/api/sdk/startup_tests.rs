//! 跨上传、进程、控制和媒体来源的协议夹具，验证调用者真正可用的分阶段接口。
use super::*;
use interop_adb::{
    DeviceInfo,
    protocol::{self, Frame},
};

async fn read(peer: &mut tokio::io::DuplexStream) -> Frame {
    tokio::time::timeout(Duration::from_secs(2), Frame::read(peer, 65536, true))
        .await
        .unwrap()
        .unwrap()
}
async fn next_open(peer: &mut tokio::io::DuplexStream) -> Frame {
    loop {
        let frame = read(peer).await;
        if frame.command == protocol::OPEN {
            return frame;
        }
    }
}
async fn accept(peer: &mut tokio::io::DuplexStream, remote: u32) -> u32 {
    let open = next_open(peer).await;
    Frame::new(protocol::OKAY, remote, open.arg0, [])
        .write(peer)
        .await
        .unwrap();
    open.arg0
}
async fn send(peer: &mut tokio::io::DuplexStream, remote: u32, local: u32, data: &[u8]) {
    Frame::new(protocol::WRTE, remote, local, data)
        .write(peer)
        .await
        .unwrap();
}
async fn fixture(
    options: Options,
) -> (
    String,
    Client,
    tokio::io::DuplexStream,
    tokio::task::JoinHandle<Result<ScrcpySessionInfo, String>>,
    u32,
) {
    let (id, client, mut peer, starting, process, _) = opening_fixture(options).await;
    send(
        &mut peer,
        72,
        process,
        b"__INTEROP_PID__456:789\ncreated display=12\n",
    )
    .await;
    let run = process_command(&mut peer, process).await;
    assert!(run.starts_with("RUN:"));
    (id, client, peer, starting, process)
}

async fn process_command(peer: &mut tokio::io::DuplexStream, local: u32) -> String {
    loop {
        let frame = read(peer).await;
        if frame.command == protocol::WRTE && frame.arg0 == local {
            Frame::new(protocol::OKAY, 72, local, [])
                .write(peer)
                .await
                .unwrap();
            return String::from_utf8(frame.payload).unwrap();
        }
    }
}

/// 返回实际已接纳 START、尚未交付 PID 的远端边界，用于验证等待者退出不丢失监督责任。
async fn opening_fixture(
    options: Options,
) -> (
    String,
    Client,
    tokio::io::DuplexStream,
    tokio::task::JoinHandle<Result<ScrcpySessionInfo, String>>,
    u32,
    String,
) {
    initialize_sdk(vec![1, 2, 3]).unwrap();
    let (transport, mut peer) = tokio::io::duplex(64 * 1024);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 65536,
            banner: "device::".into(),
            features: ["shell_v2".into()].into(),
        },
    )
    .unwrap();
    let connection =
        interop_adb_api::api::insert_connection(client.clone(), "startup-fixture".into(), false)
            .unwrap();
    let id = create(&connection.id, options).await.unwrap();
    let starting = tokio::spawn({
        let id = id.clone();
        async move { start_control(&id).await }
    });
    let local = accept(&mut peer, 71).await;
    let mut received = Vec::new();
    loop {
        let frame = read(&mut peer).await;
        assert_eq!(frame.command, protocol::WRTE);
        received.extend_from_slice(&frame.payload);
        Frame::new(protocol::OKAY, 71, local, [])
            .write(&mut peer)
            .await
            .unwrap();
        if received.windows(4).any(|value| value == b"DONE") {
            break;
        }
    }
    send(&mut peer, 71, local, b"OKAY\0\0\0\0").await;
    let process = next_open(&mut peer).await;
    assert!(String::from_utf8_lossy(&process.payload).contains("app_process"));
    Frame::new(protocol::OKAY, 72, process.arg0, [])
        .write(&mut peer)
        .await
        .unwrap();
    let start = process_command(&mut peer, process.arg0).await;
    let nonce = start.strip_prefix("START:").unwrap().trim_end().to_owned();
    assert_eq!(nonce.len(), 32);
    (id, client, peer, starting, process.arg0, nonce)
}
async fn stop_and_check_streams(
    id: String,
    client: Client,
    mut peer: tokio::io::DuplexStream,
    locals: &[u32],
) {
    let stopping = tokio::spawn(async move { stop(&id).await });
    let mut released = std::collections::HashSet::new();
    loop {
        let frame = read(&mut peer).await;
        if frame.command == protocol::WRTE && frame.payload.starts_with(b"STOP:") {
            Frame::new(protocol::OKAY, 72, frame.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            let nonce = std::str::from_utf8(&frame.payload[5..]).unwrap().trim_end();
            let done = format!("\n__INTEROP_DONE__{nonce}\n");
            send(&mut peer, 72, frame.arg0, done.as_bytes()).await;
        }
        if frame.command == protocol::CLSE {
            released.insert(frame.arg0);
        }
        if frame.command == protocol::OPEN {
            assert!(String::from_utf8_lossy(&frame.payload).contains("rm -f --"));
            for local in locals {
                assert!(released.contains(local), "删除前必须释放通道 {local}");
            }
            Frame::new(protocol::OKAY, 99, frame.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            send(&mut peer, 99, frame.arg0, &[3, 1, 0, 0, 0, 0]).await;
            break;
        }
    }
    stopping.await.unwrap().unwrap();
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
}

#[tokio::test]
async fn abandoning_start_before_identity_keeps_the_supervisor_until_its_exact_done() {
    let (id, client, peer, starting, process, _) = opening_fixture(Options::default()).await;
    starting.abort();
    assert!(matches!(starting.await, Err(error) if error.is_cancelled()));
    // 实际 START 已被对端接纳；取消调用者不能丢失 PID 之前的远端启动责任。
    stop_and_check_streams(id.clone(), client, peer, &[process]).await;
    assert!(lookup(&id).is_err());
}

#[tokio::test]
async fn missing_identity_and_done_retains_the_capture_without_removing_its_jar() {
    let (id, client, mut peer, starting, process, _) = opening_fixture(Options::default()).await;
    let stopping = tokio::spawn({
        let id = id.clone();
        async move { stop(&id).await }
    });
    assert!(
        process_command(&mut peer, process)
            .await
            .starts_with("STOP:")
    );
    // 对端在 START 之后丢失两种回执，CLSE 本身不能作为进程已退出的证明。
    Frame::new(protocol::CLSE, 72, process, [])
        .write(&mut peer)
        .await
        .unwrap();
    assert!(starting.await.unwrap().is_err());
    assert!(stopping.await.unwrap().is_err());
    assert!(lookup(&id).is_ok(), "未知启动必须保留同一捕获供后续核验");
    assert!(
        tokio::time::timeout(Duration::from_millis(20), next_open(&mut peer))
            .await
            .is_err(),
        "没有退出证明不得发出外部 rm 或按名称猜测其他进程"
    );
    assert!(stop(&id).await.is_err(), "重复停止不得把未知结果改写为成功");
    // 夹具没有真实子进程；只撤本用例私有登记，生产路径没有强制忘记未知资源的入口。
    registry().lock().unwrap().remove(&id);
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
}

async fn reply_shell(peer: &mut tokio::io::DuplexStream, open: Frame, stdout: &[u8], status: u8) {
    Frame::new(protocol::OKAY, 99, open.arg0, [])
        .write(peer)
        .await
        .unwrap();
    let mut reply = vec![1];
    reply.extend_from_slice(&(stdout.len() as u32).to_le_bytes());
    reply.extend_from_slice(stdout);
    reply.extend_from_slice(&[3, 1, 0, 0, 0, status]);
    send(peer, 99, open.arg0, &reply).await;
}

#[tokio::test]
async fn legacy_jar_cleanup_requires_its_complete_receipt_before_releasing_responsibility() {
    initialize_sdk(vec![1, 2, 3]).unwrap();
    let (transport, mut peer) = tokio::io::duplex(65536);
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
    let connection =
        interop_adb_api::api::insert_connection(client.clone(), "legacy-cleanup".into(), true)
            .unwrap();
    let id = create(&connection.id, Options::default()).await.unwrap();
    let capture = lookup(&id).unwrap();
    for attempt in 0..4 {
        let cleaning = tokio::spawn({
            let capture = capture.clone();
            async move { cleanup_remote(&capture).await }
        });
        let open = next_open(&mut peer).await;
        let command = String::from_utf8(open.payload).unwrap();
        assert!(command.starts_with("shell:"));
        assert!(command.contains("rm -f --"));
        let receipt = command
            .split_once("&& print -r -- ")
            .unwrap()
            .1
            .trim_end_matches('\0');
        let output = match attempt {
            0 => "rm: permission denied\n".to_owned(),
            1 => "__INTEROP_REMOVED__another-operation\n".to_owned(),
            2 => format!("{receipt}\ntrailing output\n"),
            _ => format!("{receipt}\n"),
        };
        Frame::new(protocol::OKAY, 73, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        send(&mut peer, 73, open.arg0, output.as_bytes()).await;
        Frame::new(protocol::CLSE, 73, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        assert_eq!(cleaning.await.unwrap().is_ok(), attempt == 3);
    }
    registry().lock().unwrap().remove(&id);
    client.close();
}

#[tokio::test]
async fn lost_done_uses_exact_kernel_identity_before_rm_and_retries_a_failed_verification() {
    let (id, client, mut peer, starting, process) = fixture(Options {
        video: false,
        audio: false,
        control: true,
        ..Default::default()
    })
    .await;
    let control = accept(&mut peer, 74).await;
    send(&mut peer, 74, control, &[0; 65]).await;
    starting.await.unwrap().unwrap();
    let stopping = tokio::spawn({
        let id = id.clone();
        async move { stop(&id).await }
    });
    assert!(
        process_command(&mut peer, process)
            .await
            .starts_with("STOP:")
    );
    send(&mut peer, 72, process, b"\n__INTEROP_DONE__foreign-nonce\n").await;
    Frame::new(protocol::CLSE, 72, process, [])
        .write(&mut peer)
        .await
        .unwrap();
    let verify = next_open(&mut peer).await;
    let command = String::from_utf8_lossy(&verify.payload);
    assert!(command.contains("p=456") && command.contains("expected=789"));
    assert!(!command.contains("rm -f"));
    reply_shell(&mut peer, verify, b"released:unknown\n", 0).await;
    assert!(stopping.await.unwrap().is_err());
    assert!(lookup(&id).is_ok());

    let retry = tokio::spawn({
        let id = id.clone();
        async move { stop(&id).await }
    });
    let verify = next_open(&mut peer).await;
    let command = String::from_utf8_lossy(&verify.payload);
    assert!(command.contains("p=456") && command.contains("expected=789"));
    reply_shell(&mut peer, verify, b"released:replaced\n", 0).await;
    let remove = next_open(&mut peer).await;
    assert!(String::from_utf8_lossy(&remove.payload).contains("rm -f --"));
    reply_shell(&mut peer, remove, b"", 0).await;
    retry.await.unwrap().unwrap();
    assert!(lookup(&id).is_err());
    assert!(!client.is_closed(), "核验和回收只能作用于本次捕获");
    client
        .close_and_wait(OperationOptions::default())
        .await
        .unwrap();
}

#[tokio::test]
async fn control_ready_allows_start_app_before_the_first_video_keyframe() {
    let (id, client, mut peer, starting, process) = fixture(Options::default()).await;
    let video = accept(&mut peer, 73).await;
    let control = accept(&mut peer, 74).await;
    let mut metadata = vec![0; 65];
    metadata.extend_from_slice(b"h264");
    metadata.extend_from_slice(&0x8000_0000u32.to_be_bytes());
    metadata.extend_from_slice(&640u32.to_be_bytes());
    metadata.extend_from_slice(&480u32.to_be_bytes());
    send(&mut peer, 73, video, &metadata).await;
    let info = tokio::time::timeout(Duration::from_millis(200), starting)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(info.control_ready);
    assert!(!info.media_ready);
    assert!(info.source.is_none());
    assert_eq!(
        (info.process_id, info.process_started),
        (Some(456), Some(789))
    );
    let logs = process_info(&id).unwrap();
    assert_eq!(logs.log_tail, b"created display=12\n");
    let waiting = tokio::spawn({
        let id = id.clone();
        async move { await_media(&id, 17).await }
    });
    tokio::task::yield_now().await;
    assert!(!waiting.is_finished());
    let command = tokio::spawn({
        let id = id.clone();
        async move { super::send(&id, Message::StartApp("org.example.test".into())).await }
    });
    loop {
        let frame = read(&mut peer).await;
        if frame.command == protocol::WRTE && frame.arg0 == control {
            assert_eq!(frame.payload[0], 16);
            Frame::new(protocol::OKAY, 74, control, [])
                .write(&mut peer)
                .await
                .unwrap();
            break;
        }
    }
    assert!(matches!(
        command.await.unwrap().unwrap(),
        ControlCompletion::Written
    ));
    let mut packet = (1u64 << 61).to_be_bytes().to_vec();
    packet.extend_from_slice(&3u32.to_be_bytes());
    packet.extend_from_slice(&[1, 2, 3]);
    send(&mut peer, 73, video, &packet).await;
    let ready = waiting.await.unwrap().unwrap();
    assert!(ready.media_ready);
    assert_eq!(ready.source.unwrap().generation, 17);
    assert!(start(&id).await.is_err(), "重复完整启动不得重新启动进程");
    assert!(
        !lookup(&id).unwrap().cancellation.is_cancelled(),
        "拒绝重复启动不能取消原捕获"
    );
    stop_and_check_streams(id, client, peer, &[process, video, control]).await;
}

#[tokio::test]
async fn typed_display_controls_are_written_without_claiming_the_remote_change_applied() {
    for (video_enabled, display, flex_display, can_resize) in [
        (true, None, false, false),
        (true, Some(Default::default()), false, false),
        (false, Some(Default::default()), true, false),
        (true, Some(Default::default()), true, true),
    ] {
        let (id, client, mut peer, starting, process) = fixture(Options {
            video: video_enabled,
            display,
            flex_display,
            ..Default::default()
        })
        .await;
        let video = if video_enabled {
            Some(accept(&mut peer, 73).await)
        } else {
            None
        };
        let control = accept(&mut peer, 74).await;
        let mut metadata = vec![0; 65];
        if let Some(video) = video {
            metadata.extend_from_slice(b"h264");
            metadata.extend_from_slice(&0x8000_0000u32.to_be_bytes());
            metadata.extend_from_slice(&640u32.to_be_bytes());
            metadata.extend_from_slice(&480u32.to_be_bytes());
            send(&mut peer, 73, video, &metadata).await;
        } else {
            send(&mut peer, 74, control, &metadata).await;
        }
        assert!(starting.await.unwrap().unwrap().control_ready);

        if !can_resize {
            let error = crate::api::scrcpy_resize_display(id.clone(), 800, 600)
                .await
                .err()
                .unwrap();
            assert!(error.starts_with("resize_unavailable:"));
        } else {
            assert!(
                crate::api::scrcpy_resize_display(id.clone(), 0, 600)
                    .await
                    .is_err()
            );
        }
        let requests = if can_resize {
            vec![vec![10, 0], vec![10, 1], vec![21, 0x12, 0x34, 0xab, 0xcd]]
        } else {
            vec![vec![10, 1]]
        };
        for expected in requests {
            let request = tokio::spawn({
                let id = id.clone();
                let expected = expected.clone();
                async move {
                    if expected[0] == 10 {
                        crate::api::scrcpy_set_display_power(id, expected[1] != 0).await
                    } else {
                        crate::api::scrcpy_resize_display(id, 0x1234, 0xabcd).await
                    }
                }
            });
            loop {
                let frame = read(&mut peer).await;
                if frame.command != protocol::WRTE || frame.arg0 != control {
                    continue;
                }
                assert_eq!(frame.payload, expected);
                // 未收到 ADB OKAY 前，不能把请求准入当作写入完成。
                assert!(!request.is_finished());
                Frame::new(protocol::OKAY, 74, control, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
                break;
            }
            assert!(matches!(
                request.await.unwrap().unwrap().completion,
                crate::api::ScrcpyControlCompletion::Written
            ));
        }
        assert!(!lookup(&id).unwrap().cancellation.is_cancelled());
        let mut locals = vec![process, control];
        locals.extend(video);
        stop_and_check_streams(id, client, peer, &locals).await;
    }
}

#[derive(Default)]
struct AudioReceiver {
    packet: Mutex<Vec<u8>>,
    codec: std::sync::atomic::AtomicU32,
    pts: std::sync::atomic::AtomicI64,
    received: tokio::sync::Notify,
}
unsafe extern "C" fn audio_event(
    context: *mut std::ffi::c_void,
    kind: u32,
    _: u64,
    codec: u32,
    _: u32,
    _: u32,
    bytes: *const u8,
    length: usize,
    pts: i64,
    _: u32,
) -> i32 {
    let receiver = unsafe { &*(context as *const AudioReceiver) };
    if kind == interop_scrcpy::media::native::EVENT_PACKET {
        *receiver.packet.lock().unwrap() =
            unsafe { std::slice::from_raw_parts(bytes, length) }.to_vec();
        receiver.codec.store(codec, Ordering::Relaxed);
        receiver.pts.store(pts, Ordering::Relaxed);
        receiver.received.notify_one();
    }
    0
}

#[tokio::test]
async fn raw_audio_only_has_an_independent_native_source_and_drains_before_cleanup() {
    let (id, client, mut peer, starting, process) = fixture(Options {
        video: false,
        audio: true,
        control: false,
        power_on: false,
        ..Default::default()
    })
    .await;
    let audio = accept(&mut peer, 73).await;
    let mut metadata = vec![0; 65];
    metadata.extend_from_slice(&[0, b'r', b'a', b'w']);
    send(&mut peer, 73, audio, &metadata).await;
    let info = starting.await.unwrap().unwrap();
    assert!(!info.video_enabled);
    assert!(info.audio_enabled);
    assert!(!info.control_ready);
    assert!(info.media_ready);
    assert!(info.source.is_none());
    let source = info.audio_source.unwrap();
    assert_eq!(source.codec, "pcm_s16le");
    assert_ne!(source.attach_address, 0);
    assert_eq!(source.source_id.len(), 64);
    let mut receiver = Box::new(AudioReceiver::default());
    let sink = interop_scrcpy::media::native::MediaSinkV1 {
        abi_version: 1,
        struct_size: std::mem::size_of::<interop_scrcpy::media::native::MediaSinkV1>() as u32,
        context: (&mut *receiver as *mut AudioReceiver).cast(),
        event: Some(audio_event),
    };
    assert_eq!(
        unsafe {
            interop_scrcpy::media::native::interop_media_attach(
                source.source_id.as_ptr(),
                source.source_id.len(),
                1,
                &sink,
            )
        },
        0
    );
    let pcm = [0, 1, 2, 3, 4, 5, 6, 7];
    let mut packet = 123456u64.to_be_bytes().to_vec();
    packet.extend_from_slice(&(pcm.len() as u32).to_be_bytes());
    packet.extend_from_slice(&pcm);
    send(&mut peer, 73, audio, &packet).await;
    tokio::time::timeout(Duration::from_secs(1), receiver.received.notified())
        .await
        .unwrap();
    assert_eq!(*receiver.packet.lock().unwrap(), pcm);
    assert_eq!(
        receiver.codec.load(Ordering::Relaxed),
        interop_scrcpy::media::native::CODEC_PCM_S16LE
    );
    assert_eq!(receiver.pts.load(Ordering::Relaxed), 123456);
    assert!(await_media(&id, 3).await.unwrap().audio_source.is_some());
    stop_and_check_streams(id, client, peer, &[process, audio]).await;
}

#[tokio::test]
async fn stopping_before_first_frame_releases_the_wait_and_all_started_streams() {
    let (id, client, mut peer, starting, process) = fixture(Options::default()).await;
    let video = accept(&mut peer, 73).await;
    let control = accept(&mut peer, 74).await;
    let mut metadata = vec![0; 65];
    metadata.extend_from_slice(b"h264");
    metadata.extend_from_slice(&0x8000_0000u32.to_be_bytes());
    metadata.extend_from_slice(&640u32.to_be_bytes());
    metadata.extend_from_slice(&480u32.to_be_bytes());
    send(&mut peer, 73, video, &metadata).await;
    starting.await.unwrap().unwrap();
    let waiting = tokio::spawn({
        let id = id.clone();
        async move { await_media(&id, 1).await }
    });
    stop_and_check_streams(id, client, peer, &[process, video, control]).await;
    assert!(waiting.await.unwrap().is_err());
}
