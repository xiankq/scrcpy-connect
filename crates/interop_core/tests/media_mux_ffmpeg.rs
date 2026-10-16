//! Independent decoder tests. INTEROP_FFMPEG is mandatory, never an optional silent skip.
use interop_core::media::{MatroskaMuxer, Track, VideoCodec, VideoTrack};
use std::{
    process::{Output, Stdio},
    time::Duration,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn ffmpeg(args: &[&str], input: Vec<u8>) -> Output {
    let exe =
        std::env::var("INTEROP_FFMPEG").expect("set INTEROP_FFMPEG to a real decoder executable");
    let mut child = tokio::process::Command::new(exe)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let writer = tokio::spawn(async move { stdin.write_all(&input).await });
    let output = tokio::time::timeout(Duration::from_secs(30), child.wait_with_output())
        .await
        .expect("bounded ffmpeg")
        .unwrap();
    let _ = writer.await.unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

#[tokio::test]
#[ignore = "requires INTEROP_FFMPEG; generates a real H264 frame and independently decodes Matroska"]
async fn real_avcc_length_prefixed_frames_decode_and_preserve_variable_pts() {
    let encoded = ffmpeg(
        &[
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "color=c=red:s=64x48:r=1",
            "-frames:v",
            "1",
            "-c:v",
            "libx264",
            "-threads",
            "1",
            "-f",
            "h264",
            "pipe:1",
        ],
        Vec::new(),
    )
    .await
    .stdout;
    let track = VideoTrack::from_scrcpy(VideoCodec::H264, 64, 48, &encoded).unwrap();
    assert_eq!(track.codec_private()[0], 1);
    assert_eq!(track.codec_private()[4] & 3, 3);
    let mut mux = MatroskaMuxer::new(1, Track::Video(track)).unwrap();
    let mut input = mux.take_header();
    for pts in [5_000_000, 5_123_457, 6_234_567] {
        input.extend(mux.push_packet(pts, true, &encoded).unwrap());
    }
    let decoded = ffmpeg(
        &[
            "-v",
            "info",
            "-copyts",
            "-i",
            "pipe:0",
            "-vf",
            "showinfo",
            "-fps_mode",
            "passthrough",
            "-frames:v",
            "3",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-threads",
            "1",
            "pipe:1",
        ],
        input,
    )
    .await;
    assert_eq!(decoded.stdout.len(), 64 * 48 * 3 * 3);
    assert!(
        decoded
            .stdout
            .as_chunks::<3>()
            .0
            .iter()
            .all(|rgb| rgb[0] > 240 && rgb[1] < 10 && rgb[2] < 10)
    );
    let log = String::from_utf8_lossy(&decoded.stderr);
    assert!(log.contains("pts: 123457"), "{log}");
    assert!(log.contains("pts:1234567"), "{log}");
    eprintln!("FFmpeg decoded 3 AVC frames with exact relative PTS 0,123457,1234567us");
}

#[tokio::test]
#[ignore = "requires INTEROP_FFMPEG; independently decodes and verifies exact stereo PCM samples"]
async fn pcm_samples_survive_matroska_without_loss_or_channel_swap() {
    let samples: Vec<u8> = (0..4800i16)
        .flat_map(|i| [i, -i])
        .flat_map(i16::to_le_bytes)
        .collect();
    let mut mux = MatroskaMuxer::new(
        1,
        Track::PcmS16le {
            sample_rate: 48_000,
            channels: 2,
        },
    )
    .unwrap();
    let mut input = mux.take_header();
    for (index, chunk) in samples.chunks(1920).enumerate() {
        input.extend(
            mux.push_packet(8_000_000 + index as u64 * 10_000, true, chunk)
                .unwrap(),
        );
    }
    let decoded = ffmpeg(
        &[
            "-v",
            "error",
            "-i",
            "pipe:0",
            "-map",
            "0:a:0",
            "-c:a",
            "pcm_s16le",
            "-f",
            "s16le",
            "pipe:1",
        ],
        input,
    )
    .await;
    assert_eq!(decoded.stdout, samples);
    eprintln!("FFmpeg recovered all 4800 stereo PCM sample frames byte-exactly");
}

#[tokio::test]
#[ignore = "requires authorized target INTEROP_ADBD_PORT and INTEROP_FFMPEG; owns isolated scrcpy sessions"]
async fn real_scrcpy_five_codec_packets_decode_through_matroska() {
    use interop_core::Runtime;
    use serde_json::json;
    let store = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(store.path()).await.unwrap();
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("target adbd port")
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
    let mut decoded = Vec::new();
    for name in ["h264", "h265", "av1", "vp8", "vp9"] {
        let option = options["codecs"]
            .as_array()
            .unwrap()
            .iter()
            .find(|option| option["id"] == name)
            .unwrap();
        if option["available"] != true {
            eprintln!("actual {name} target encoder not available: {option}");
            continue;
        }
        let session = runtime.invoke("session.start",json!({"deviceId":id,"videoCodec":name,"maxSize":640,"maxFps":15,"videoBitRate":1_000_000})).await.unwrap();
        let mut socket = tokio::net::TcpStream::connect((
            "127.0.0.1",
            session["videoPort"].as_u64().unwrap() as u16,
        ))
        .await
        .unwrap();
        socket
            .write_all(session["videoToken"].as_str().unwrap().as_bytes())
            .await
            .unwrap();
        socket.write_all(b"\n").await.unwrap();
        let (configuration, pts, packet) = tokio::time::timeout(Duration::from_secs(12), async {
            let mut config = Vec::new();
            loop {
                let mut header = [0; 12];
                socket.read_exact(&mut header).await.unwrap();
                if header[0] & 0x80 != 0 {
                    continue;
                }
                let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
                let len = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
                assert!(len > 0 && len <= 16 * 1024 * 1024);
                let mut bytes = vec![0; len];
                socket.read_exact(&mut bytes).await.unwrap();
                if flags & (1 << 62) != 0 {
                    config.extend(bytes);
                    assert!(config.len() <= 256 * 1024);
                } else if flags & (1 << 61) != 0 {
                    break (config, flags & ((1 << 61) - 1), bytes);
                }
            }
        })
        .await
        .unwrap();
        eprintln!(
            "actual {name} config prefix: {:02x?}",
            &configuration[..configuration.len().min(32)]
        );
        let track = VideoTrack::from_scrcpy(
            VideoCodec::from_name(name).unwrap(),
            session["width"].as_u64().unwrap() as u32,
            session["height"].as_u64().unwrap() as u32,
            &configuration,
        )
        .unwrap();
        let private_bytes = track.codec_private().len();
        let mut mux = MatroskaMuxer::new(1, Track::Video(track)).unwrap();
        let mut stream = mux.take_header();
        stream.extend(mux.push_packet(pts, true, &packet).unwrap());
        let output = ffmpeg(
            &[
                "-v",
                "error",
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
            ],
            stream,
        )
        .await;
        assert!(output.stdout.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert_eq!(
            u32::from_be_bytes(output.stdout[16..20].try_into().unwrap()) as u64,
            session["width"].as_u64().unwrap()
        );
        assert_eq!(
            u32::from_be_bytes(output.stdout[20..24].try_into().unwrap()) as u64,
            session["height"].as_u64().unwrap()
        );
        eprintln!(
            "actual {name}: config={} private={private_bytes}, inputPTS={pts}us, Matroska FFmpeg PNG={}x{}",
            configuration.len(),
            session["width"],
            session["height"]
        );
        runtime
            .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
            .await
            .unwrap();
        decoded.push(name);
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert!(decoded.contains(&"h264"));
    eprintln!("actual target Matroska codecs decoded: {decoded:?}");
}
