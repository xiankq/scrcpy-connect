//! Opt-in tests use the Rust ADB host and the pinned official scrcpy JAR.
//! Official adb is only used by the external harness to expose authorized adbd.
#[path = "support/native_media.rs"]
mod native_media;
mod support;
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{process::Stdio, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn video_socket(session: &Value) -> native_media::Reader {
    native_media::Reader::video(session)
}

async fn keyframe(socket: &mut native_media::Reader) -> Vec<Vec<u8>> {
    tokio::time::timeout(Duration::from_secs(12), async {
        let mut packets = Vec::new();
        let mut total = 0;
        loop {
            let mut header = [0; 12];
            socket.read_exact(&mut header).await.unwrap();
            if header[0] & 0x80 != 0 {
                continue;
            }
            let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
            let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
            assert!(length > 0 && length <= 16 * 1024 * 1024);
            total += length;
            assert!(total <= 32 * 1024 * 1024);
            let mut packet = vec![0; length];
            socket.read_exact(&mut packet).await.unwrap();
            packets.push(packet);
            if flags & (1 << 61) != 0 && flags & (1 << 62) == 0 {
                return packets;
            }
        }
    })
    .await
    .expect("actual video keyframe")
}

fn elementary_input(
    codec: &str,
    packets: &[Vec<u8>],
    width: u16,
    height: u16,
) -> (String, Vec<u8>) {
    if matches!(codec, "av1" | "vp8" | "vp9") {
        // Preserve AV1/VPx access-unit boundaries in IVF. This test-only mux preserves individual
        // scrcpy packet boundaries; it is not a product playback adapter.
        let mut bytes = b"DKIF".to_vec();
        bytes.extend_from_slice(&0u16.to_le_bytes());
        bytes.extend_from_slice(&32u16.to_le_bytes());
        bytes.extend_from_slice(match codec {
            "av1" => b"AV01",
            "vp8" => b"VP80",
            _ => b"VP90",
        });
        bytes.extend_from_slice(&width.to_le_bytes());
        bytes.extend_from_slice(&height.to_le_bytes());
        bytes.extend_from_slice(&30u32.to_le_bytes());
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&(packets.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());
        for (index, packet) in packets.iter().enumerate() {
            bytes.extend_from_slice(&(packet.len() as u32).to_le_bytes());
            bytes.extend_from_slice(&(index as u64).to_le_bytes());
            bytes.extend_from_slice(packet);
        }
        ("ivf".into(), bytes)
    } else {
        (
            (match codec {
                "h264" => "h264",
                "h265" => "hevc",
                _ => panic!("codec"),
            })
            .into(),
            packets.concat(),
        )
    }
}

async fn decode(codec: &str, packets: &[Vec<u8>], session: &Value) {
    let ffmpeg =
        std::env::var("INTEROP_FFMPEG").expect("set INTEROP_FFMPEG to the real decoder executable");
    let (format, bytes) = elementary_input(
        codec,
        packets,
        session["width"].as_u64().unwrap() as u16,
        session["height"].as_u64().unwrap() as u16,
    );
    let mut process = tokio::process::Command::new(ffmpeg)
        .args([
            "-v",
            "error",
            "-threads",
            "1",
            "-f",
            &format,
            "-i",
            "pipe:0",
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "png",
            "-threads",
            "1",
            "pipe:1",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let mut input = process.stdin.take().unwrap();
    let writer = tokio::spawn(async move { input.write_all(&bytes).await });
    let output = tokio::time::timeout(Duration::from_secs(30), process.wait_with_output())
        .await
        .expect("ffmpeg bounded decode")
        .unwrap();
    let _ = writer.await.unwrap();
    assert!(
        output.status.success(),
        "{codec}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.starts_with(b"\x89PNG\r\n\x1a\n"),
        "{codec} produced no actual decoded image"
    );
    assert_eq!(
        u32::from_be_bytes(output.stdout[16..20].try_into().unwrap()) as u64,
        session["width"].as_u64().unwrap()
    );
    assert_eq!(
        u32::from_be_bytes(output.stdout[20..24].try_into().unwrap()) as u64,
        session["height"].as_u64().unwrap()
    );
    eprintln!(
        "actual {codec} FFmpeg decoded PNG: {}x{}",
        session["width"], session["height"]
    );
}

#[tokio::test]
#[ignore = "requires an authorized awake real adbd and INTEROP_FFMPEG"]
async fn enumerate_actual_encoders_decode_multiple_codecs_and_preserve_old_session() {
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let device = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let options = runtime
        .invoke("session.quality.options", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(options["probe"]["status"], "enumerated");
    eprintln!(
        "actual pinned scrcpy list_encoders: {}",
        options["encoders"]
    );
    let available = options["codecs"].as_array().unwrap();
    let mut decoded = Vec::new();
    for codec in ["h264", "h265", "av1", "vp9", "vp8"] {
        let entry = available.iter().find(|entry| entry["id"] == codec).unwrap();
        if entry["available"] != true {
            eprintln!("actual {codec}: no target encoder enumerated");
            continue;
        }
        let encoder = entry["encoders"][0]["name"].as_str().unwrap();
        runtime.invoke("session.quality", support::media_params(json!({"deviceId":id,"videoCodec":codec,"videoEncoder":encoder,"maxSize":720,"maxFps":15,"videoBitRate":1_000_000}))).await.unwrap();
        let session = match runtime
            .invoke("session.start", support::media_params(json!({"deviceId":id,
                "videoCodec":codec,"videoEncoder":encoder,"maxSize":720,"maxFps":15,"videoBitRate":1_000_000})))
            .await
        {
            Ok(session) => session,
            Err(error) if codec != "h264" => {
                eprintln!("actual enumerated {codec} failed startup/configuration: {error:?}");
                continue;
            }
            Err(error) => panic!("H.264 startup failed: {error:?}"),
        };
        assert_eq!(session["codec"], codec);
        assert_eq!(session["mime"], entry["mime"]);
        assert_eq!(session["videoEncoder"], encoder);
        assert_eq!(session["encodedKeyFrameReady"], true);
        let mut socket = video_socket(&session).await;
        let packets = keyframe(&mut socket).await;
        if codec == "h264" {
            let bad = runtime.invoke("session.quality", support::media_params(json!({"deviceId":id,"sessionId":session["sessionId"],"videoCodec":"h265","videoEncoder":"interop.no.such.encoder"}))).await.unwrap_err();
            assert_eq!(bad.code, "encoder_unavailable");
            let still = runtime
                .invoke("session.list", json!({"deviceId":id}))
                .await
                .unwrap();
            assert_eq!(still["sessions"].as_array().unwrap().len(), 1);
            assert_eq!(still["sessions"][0]["sessionId"], session["sessionId"]);
            assert_eq!(still["sessions"][0]["codec"], "h264");
            // A real response over the existing scrcpy control socket proves
            // that the old process is still operational after rejection. A
            // static display need not emit another keyframe on a timer, and a
            // headless test must not fabricate a Native texture acknowledgement.
            let clipboard = runtime
                .invoke("clipboard.get", json!({"deviceId":id}))
                .await
                .unwrap();
            assert!(clipboard["text"].is_string());
            let same = runtime.invoke("session.quality", support::media_params(json!({"deviceId":id,"sessionId":session["sessionId"],"videoCodec":"h264","videoEncoder":encoder,"maxSize":1280}))).await.unwrap();
            assert_eq!(same["appliesNextSession"], true);
            assert_eq!(same["needsRestart"], true);
            let current = runtime
                .invoke("session.list", json!({"deviceId":id}))
                .await
                .unwrap();
            assert_eq!(current["sessions"][0]["quality"]["maxSize"], 720);
            assert_eq!(current["sessions"][0]["sessionId"], session["sessionId"]);
        }
        decode(codec, &packets, &session).await;
        runtime
            .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
            .await
            .unwrap();
        decoded.push(codec);
    }
    // Explicit start options affect only this new session, not whichever
    // per-device selection the actual device exposed in the loop above.
    let saved = runtime.invoke("settings.get", json!({})).await.unwrap();
    let h264 = available
        .iter()
        .find(|entry| entry["id"] == "h264")
        .unwrap();
    let override_session = runtime.invoke("session.start", support::media_params(json!({"deviceId":id,"videoCodec":"h264","videoEncoder":h264["encoders"][0]["name"],"maxSize":640}))).await.unwrap();
    assert_eq!(override_session["codec"], "h264");
    assert_eq!(override_session["quality"]["maxSize"], 640);
    let mut socket = video_socket(&override_session).await;
    let packets = keyframe(&mut socket).await;
    decode("h264", &packets, &override_session).await;
    let unchanged = runtime.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(unchanged["deviceQuality"][id], saved["deviceQuality"][id]);
    runtime
        .invoke(
            "session.stop",
            json!({"sessionId":override_session["sessionId"]}),
        )
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert!(decoded.contains(&"h264"));
    assert!(
        decoded.len() >= 2,
        "no second codec could configure and decode: {decoded:?}"
    );
    eprintln!("actual codecs with encoded headers, keyframes and decoded images: {decoded:?}");
}
