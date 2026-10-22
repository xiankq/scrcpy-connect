//! Real output-capture test. The optional fixture produces a known 880Hz tone,
//! proving capture content independently of the controller's playback adapter.
#[path = "support/native_media.rs"]
mod native_media;
mod support;
use interop_adb::{Client, ConnectOptions, OperationOptions, sync::RemotePath};
use interop_core::Runtime;
use serde_json::json;
use std::time::Duration;
use tokio::io::AsyncReadExt;

#[tokio::test]
#[ignore = "requires Android 11+ authorized adbd; optional INTEROP_AUDIO_FIXTURE plays test tone"]
async fn real_audio_only_capture_and_known_tone() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let device = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    // Device audio belongs to an opened control session. This source-capture
    // test does not fabricate a renderer-ready receipt for that session.
    let session = runtime
        .invoke(
            "session.start",
            support::media_params(json!({"deviceId":id})),
        )
        .await
        .unwrap();
    let source = runtime
        .invoke("audio.start", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(source["status"], "starting");
    assert_eq!(source["sampleRate"], 48000);
    assert_eq!(source["channels"], 2);
    assert_eq!(source["audibleContentVerified"], false);
    let sources = runtime.invoke("audio.sources", json!({})).await.unwrap();
    assert!(sources["sources"][0]["audioToken"].is_null());
    assert!(sources["sources"][0]["audioPort"].is_null());
    let mut audio = native_media::Reader::audio(&source);
    let fixture = std::env::var("INTEROP_AUDIO_FIXTURE").ok();
    let fixture_client = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let fixture_path = format!(
        "/data/local/tmp/interop-audio-fixture-{}.jar",
        uuid::Uuid::new_v4()
    );
    let mut process = if let Some(path) = &fixture {
        let bytes = tokio::fs::read(path).await.unwrap();
        fixture_client
            .sync(OperationOptions::default())
            .await
            .unwrap()
            .push(
                &RemotePath::new(&fixture_path).unwrap(),
                &mut &bytes[..],
                0o600,
                0,
                bytes.len() as u64,
            )
            .await
            .unwrap();
        Some(
            fixture_client
                .exec(
                    &format!("CLASSPATH={fixture_path} app_process / InteropAudioFixture"),
                    OperationOptions {
                        timeout: Duration::from_secs(15),
                        ..Default::default()
                    },
                )
                .await
                .unwrap(),
        )
    } else {
        None
    };
    let mut samples = Vec::new();
    let mut packets = 0;
    let mut previous_pts = None;
    tokio::time::timeout(Duration::from_secs(12), async {
        while samples.len() < 48000 * 5 / 2 {
            let mut header = [0; 12];
            audio.read_exact(&mut header).await.unwrap();
            let pts = u64::from_be_bytes(header[..8].try_into().unwrap());
            let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
            assert_eq!(pts >> 61, 0);
            assert!(length <= 4096 && length.is_multiple_of(4));
            if let Some(previous) = previous_pts {
                assert!(pts >= previous);
            }
            previous_pts = Some(pts);
            let mut pcm = vec![0; length];
            audio.read_exact(&mut pcm).await.unwrap();
            samples.extend(
                pcm.as_chunks::<4>()
                    .0
                    .iter()
                    .map(|frame| i16::from_le_bytes([frame[0], frame[1]])),
            );
            packets += 1;
        }
    })
    .await
    .unwrap();
    assert!(packets > 100);
    // No audio.ready is fabricated: only the native AudioTrack can acknowledge
    // actual presentation. This test inspects captured source samples instead.
    assert_eq!(
        runtime.invoke("audio.sources", json!({})).await.unwrap()["sources"][0]["status"],
        "starting"
    );
    if let Some(process) = &mut process {
        let mut output = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let count = process.read(&mut buffer).await.unwrap_or_else(|error| {
                panic!(
                    "fixture ended with {error}; output: {}",
                    String::from_utf8_lossy(&output)
                )
            });
            if count == 0 {
                break;
            }
            output.extend_from_slice(&buffer[..count]);
        }
        assert!(
            String::from_utf8_lossy(&output).contains("144000 frames at 880Hz played"),
            "{}",
            String::from_utf8_lossy(&output)
        );
        // At least one 0.1s window must have strong 880Hz energy. Compare with
        // adjacent frequencies to reject silence, arbitrary noise and DC.
        let mut best = 0.0_f64;
        for window in samples.windows(4800).step_by(2400) {
            let energy = |frequency: f64| -> f64 {
                let (mut re, mut im) = (0.0, 0.0);
                for (index, sample) in window.iter().enumerate() {
                    let phase = 2.0 * std::f64::consts::PI * frequency * index as f64 / 48000.0;
                    re += f64::from(*sample) * phase.cos();
                    im += f64::from(*sample) * phase.sin();
                }
                (re * re + im * im) / (window.len() * window.len()) as f64
            };
            let tone = energy(880.0);
            let side = energy(760.0) + energy(1000.0);
            if tone > 100.0 {
                best = best.max(tone / (side + 1.0));
            }
        }
        eprintln!("captured {packets} PCM packets; best 880Hz/adjacent energy ratio {best:.1}");
        assert!(
            best > 20.0,
            "known fixture tone was not found in captured output"
        );
    }
    runtime
        .invoke(
            "audio.stop",
            json!({"deviceId":id,"sourceId":source["sourceId"]}),
        )
        .await
        .unwrap();
    assert!(
        runtime.invoke("audio.sources", json!({})).await.unwrap()["sources"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    runtime
        .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
        .await
        .unwrap();
    if fixture.is_some() {
        fixture_client
            .shell(
                &format!("rm -f -- {fixture_path}"),
                4096,
                OperationOptions::default(),
            )
            .await
            .unwrap();
    }
    fixture_client.close();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}
