//! Opt-in real adbd/scrcpy/decoder coverage. The external harness installs its
//! own optional launchable INTEROP_DISPLAY_PACKAGE (MAIN/LAUNCHER intent) and
//! removes only that fixture afterward. The app branch verifies flex-display
//! resizing with actual decoded pixels, catching a missing flex_display option.
#[path = "support/native_media.rs"]
mod native_media;
mod support;
use interop_adb::{Client, ConnectOptions, OperationOptions};
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{process::Stdio, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn shell(client: &Client, command: &str) -> String {
    let result = client
        .shell(command, 2 * 1024 * 1024, OperationOptions::default())
        .await
        .unwrap();
    assert!(
        result.exit_code.is_none_or(|code| code == 0),
        "{command}: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    String::from_utf8(result.stdout).unwrap()
}

async fn socket(session: &Value) -> native_media::Reader {
    native_media::Reader::video(session)
}

/// Read a genuine keyframe after the requested geometry, then independently
/// decode it. Neither a control receipt nor fabricated session.ready is evidence.
async fn decoded_frame(stream: &mut native_media::Reader, target: (u32, u32), label: &str) {
    let (dimensions, bytes) = tokio::time::timeout(Duration::from_secs(20), async {
        let mut dimensions = (0, 0);
        let mut bytes = Vec::new();
        loop {
            let mut header = [0; 12];
            stream.read_exact(&mut header).await.unwrap();
            if header[0] & 0x80 != 0 {
                dimensions = (
                    u32::from_be_bytes(header[4..8].try_into().unwrap()),
                    u32::from_be_bytes(header[8..12].try_into().unwrap()),
                );
                bytes.clear();
                continue;
            }
            let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
            let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
            assert!((1..=16 * 1024 * 1024).contains(&length));
            let mut payload = vec![0; length];
            stream.read_exact(&mut payload).await.unwrap();
            if dimensions != target {
                continue;
            }
            bytes.extend(payload);
            assert!(bytes.len() < 32 * 1024 * 1024);
            if flags & (1 << 61) != 0 && flags & (1 << 62) == 0 {
                return (dimensions, bytes);
            }
        }
    })
    .await
    .expect("new encoded geometry and keyframe");
    let decoder =
        std::env::var("INTEROP_FFMPEG").expect("set INTEROP_FFMPEG to an independent real decoder");
    let mut child = tokio::process::Command::new(decoder)
        .args([
            "-v",
            "error",
            "-threads",
            "1",
            "-f",
            "h264",
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
    let mut input = child.stdin.take().unwrap();
    let write = tokio::spawn(async move {
        input.write_all(&bytes).await.unwrap();
    });
    let output = tokio::time::timeout(Duration::from_secs(20), child.wait_with_output())
        .await
        .unwrap()
        .unwrap();
    write.await.unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stdout.starts_with(b"\x89PNG\r\n\x1a\n"));
    let decoded = (
        u32::from_be_bytes(output.stdout[16..20].try_into().unwrap()),
        u32::from_be_bytes(output.stdout[20..24].try_into().unwrap()),
    );
    assert_eq!(decoded, dimensions);
    assert_eq!(decoded, target);
    if let Ok(directory) = std::env::var("INTEROP_DISPLAY_CAPTURE_DIR") {
        let directory = std::path::Path::new(&directory);
        std::fs::create_dir_all(directory).unwrap();
        std::fs::write(directory.join(format!("{label}.png")), &output.stdout).unwrap();
    }
    eprintln!(
        "actual scrcpy H.264 -> independent decoded PNG: {}x{}",
        decoded.0, decoded.1
    );
}

fn user_activity(power: &str) -> u64 {
    power
        .lines()
        .find_map(|line| {
            line.trim()
                .strip_prefix("lastUserActivityTime=")
                .or_else(|| line.trim().strip_prefix("mLastUserActivityTime="))
                .and_then(|value| value.split_whitespace().next())
                .and_then(|value| value.parse().ok())
        })
        .expect("actual PowerManager user activity timestamp")
}

fn rotation(input: &str) -> u8 {
    input
        .lines()
        .find_map(|line| {
            if line.contains("Viewport ") && line.contains("displayId=0,") {
                line.split_once("orientation=")
                    .and_then(|(_, value)| value.split(',').next())
                    .and_then(|value| value.parse().ok())
            } else {
                line.split_once("SurfaceOrientation: ")
                    .and_then(|(_, value)| value.parse().ok())
            }
        })
        .expect("primary display rotation must be observable")
}

#[test]
#[ignore = "requires isolated awake Android adbd, INTEROP_FFMPEG; temporarily changes display size and sleeps/wakes the screen"]
fn real_display_resize_keep_active_and_owned_restoration() {
    // Debug builds retain the native startup state across many awaits. Give
    // this opt-in integration driver its own bounded stack, like the host app.
    std::thread::Builder::new()
        .stack_size(16 * 1024 * 1024)
        .spawn(|| {
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap()
                .block_on(display_test());
        })
        .unwrap()
        .join()
        .unwrap();
}

async fn display_test() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let inspector = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let original_size = shell(&inspector, "wm size").await;
    let original_rotation = shell(
        &inspector,
        "settings get system accelerometer_rotation; settings get system user_rotation",
    )
    .await;
    let original_orientation = rotation(&shell(&inspector, "dumpsys input").await);
    let original_timeouts = shell(
        &inspector,
        "settings get system screen_off_timeout; settings get global stay_on_while_plugged_in",
    )
    .await;
    let original_power = shell(&inspector, "dumpsys power").await;
    assert!(
        original_power.contains("mWakefulness=Awake"),
        "explicitly provide an already awake test target"
    );
    assert_eq!(
        shell(
            &inspector,
            "if [ -d /data/local/tmp/interop-display-0 ]; then echo occupied; fi"
        )
        .await
        .trim(),
        "",
        "another display owner must never be disturbed"
    );
    eprintln!(
        "Android target: {}",
        shell(
            &inspector,
            "getprop ro.build.version.sdk; getprop ro.product.cpu.abi"
        )
        .await
        .trim()
    );
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let device = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let device_id = device["deviceId"].as_str().unwrap().to_owned();
    // This isolated Runtime owns only display capture; avoid starting unrelated
    // notification/call observation against the shared AVD.
    runtime
        .invoke("observation.stop", json!({"deviceId":device_id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":device_id}))
        .await
        .unwrap();
    let run = runtime.clone();
    let target = device_id.clone();
    let inspect = inspector.clone();
    // Keep cleanup outside the task so assertion panics also close every session
    // owned by this fresh Runtime; existing Flutter/ADB processes are untouched.
    let outcome = tokio::spawn(async move {
        let main = run.invoke("session.start",support::media_params(json!({"deviceId":target,"displayWidth":640,"displayHeight":960,"keepActive":true,"maxSize":960,"maxFps":15,"videoBitRate":1_000_000}))).await.unwrap();
        let mut video = socket(&main).await;
        decoded_frame(&mut video,(640,960),"physical-portrait").await;
        let before = user_activity(&shell(&inspect,"dumpsys power").await);
        tokio::time::sleep(Duration::from_millis(4500)).await;
        let after = user_activity(&shell(&inspect,"dumpsys power").await);
        assert!(after > before,"scrcpy keep_active must reach the real PowerManager");
        eprintln!("keep_active advanced real userActivity: {before} -> {after}");
        run.invoke("session.display",json!({"sessionId":main["sessionId"],"displayWidth":960,"displayHeight":640})).await.unwrap();
        decoded_frame(&mut video,(960,640),"physical-landscape").await;
        run.invoke("session.key",json!({"sessionId":main["sessionId"],"keyCode":223,"action":"press"})).await.unwrap();
        tokio::time::sleep(Duration::from_millis(4500)).await;
        let sleeping = shell(&inspect,"dumpsys power").await;
        assert!(sleeping.contains("mWakefulness=Asleep") || sleeping.contains("mWakefulness=Dozing"),"keep_active must not wake a screen explicitly put to sleep");
        run.invoke("devices.wake",json!({"deviceId":target})).await.unwrap();
        run.invoke("session.stop",json!({"sessionId":main["sessionId"]})).await.unwrap();
        drop(video);
        if let Ok(package) = std::env::var("INTEROP_DISPLAY_PACKAGE") {
            let app = run.invoke("session.start",support::media_params(json!({"deviceId":target,"packageName":package,"displayWidth":640,"displayHeight":960,"maxSize":960,"maxFps":15,"videoBitRate":1_000_000}))).await.unwrap();
            let mut video = socket(&app).await;
            decoded_frame(&mut video,(640,960),"application-portrait").await;
            run.invoke("session.display",json!({"sessionId":app["sessionId"],"displayWidth":960,"displayHeight":640})).await.unwrap();
            decoded_frame(&mut video,(960,640),"application-landscape").await;
            run.invoke("session.stop",json!({"sessionId":app["sessionId"]})).await.unwrap();
            eprintln!("real application virtual display start and TYPE_RESIZE_DISPLAY decoded successfully");
        } else {
            eprintln!("virtual display branch not run: provide a dedicated INTEROP_DISPLAY_PACKAGE fixture");
        }
    }).await;
    let sessions = runtime
        .invoke("session.list", json!({"deviceId":device_id}))
        .await
        .unwrap();
    let owned: Vec<_> = sessions["sessions"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|session| session["sessionId"].as_str().map(str::to_owned))
        .collect();
    for id in &owned {
        let _ = runtime
            .invoke("session.stop", json!({"sessionId":id}))
            .await;
    }
    let _ = runtime
        .invoke("devices.wake", json!({"deviceId":device_id}))
        .await;
    let _ = runtime
        .invoke("devices.disconnect", json!({"deviceId":device_id}))
        .await;
    let restored = tokio::time::timeout(Duration::from_secs(8), async {
        loop {
            let current = shell(&inspector, "wm size").await;
            if current == original_size {
                break current;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await;
    let rotation = shell(
        &inspector,
        "settings get system accelerometer_rotation; settings get system user_rotation",
    )
    .await;
    let orientation = self::rotation(&shell(&inspector, "dumpsys input").await);
    let timeouts = shell(
        &inspector,
        "settings get system screen_off_timeout; settings get global stay_on_while_plugged_in",
    )
    .await;
    let lease = shell(&inspector,"if [ -d /data/local/tmp/interop-display-0 ]; then cat /data/local/tmp/interop-display-0/owner; fi").await;
    eprintln!(
        "post-stop wm size: {}",
        shell(&inspector, "wm size").await.trim()
    );
    eprintln!(
        "post-stop display lease: {}",
        if lease.trim().is_empty() {
            "absent"
        } else {
            lease.trim()
        }
    );
    assert!(
        restored.is_ok(),
        "the owned override was not restored; original={original_size:?}"
    );
    assert_eq!(
        rotation, original_rotation,
        "rotation preferences must be preserved"
    );
    assert_eq!(
        orientation, original_orientation,
        "actual display rotation must be preserved"
    );
    assert_eq!(
        timeouts, original_timeouts,
        "keep_active must not change global timeout settings"
    );
    assert!(lease.trim().is_empty(), "owned lease remains after stop");
    inspector.close();
    outcome.expect("device assertions failed after owned cleanup");
}
