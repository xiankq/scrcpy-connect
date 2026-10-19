//! Real scrcpy JAR/device tests. No adb executable is used by this test or runtime.
//! Run with INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 and a reachable authorized adbd.
use interop_core::Runtime;
use serde_json::json;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
#[ignore = "requires a real authorized adbd and optional ffmpeg decoder"]
async fn jar_video_authentication_framing_and_h264_decode() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    eprintln!("scrcpy E2E: initialize");
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    eprintln!("scrcpy E2E: add device");
    let device = runtime
        .invoke("devices.add", json!({"address":address,"port":port}))
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    eprintln!("scrcpy E2E: connect");
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    eprintln!("scrcpy E2E: start session");
    let started = runtime
        .invoke("session.start", json!({"deviceId":id}))
        .await;
    if started.is_err() {
        eprintln!(
            "session startup state: {}",
            runtime.invoke("state.snapshot", json!({})).await.unwrap()
        );
    }
    let session = started.unwrap();
    assert_eq!(session["status"], "starting");
    assert!(session["textureId"].is_null());
    let video_port = session["videoPort"].as_u64().unwrap() as u16;
    let mut unauthorized = tokio::net::TcpStream::connect(("127.0.0.1", video_port))
        .await
        .unwrap();
    unauthorized.write_all(&[b'x'; 64]).await.unwrap();
    unauthorized.write_all(b"\n").await.unwrap();
    let mut byte = [0];
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), unauthorized.read(&mut byte))
            .await
            .unwrap()
            .unwrap(),
        0
    );
    let mut video = tokio::net::TcpStream::connect(("127.0.0.1", video_port))
        .await
        .unwrap();
    video
        .write_all(session["videoToken"].as_str().unwrap().as_bytes())
        .await
        .unwrap();
    video.write_all(b"\n").await.unwrap();
    let mut initial = [0; 12];
    video.read_exact(&mut initial).await.unwrap();
    assert_eq!(
        u32::from_be_bytes(initial[..4].try_into().unwrap()) & 0x8000_0000,
        0x8000_0000
    );
    assert_eq!(
        u32::from_be_bytes(initial[4..8].try_into().unwrap()) as u64,
        session["width"].as_u64().unwrap()
    );
    assert_eq!(
        u32::from_be_bytes(initial[8..].try_into().unwrap()) as u64,
        session["height"].as_u64().unwrap()
    );
    let mut h264 = Vec::new();
    let mut key_frame = false;
    tokio::time::timeout(Duration::from_secs(15), async {
        while !key_frame {
            let mut header = [0; 12];
            video.read_exact(&mut header).await.unwrap();
            if header[0] & 0x80 != 0 {
                continue;
            }
            let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
            let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
            assert!(length > 0 && length <= 16 * 1024 * 1024);
            let mut payload = vec![0; length];
            video.read_exact(&mut payload).await.unwrap();
            h264.extend(payload);
            key_frame = flags & (1u64 << 61) != 0;
        }
    })
    .await
    .unwrap();
    assert!(h264.windows(4).any(|bytes| bytes == [0, 0, 0, 1]));
    if let Ok(ffmpeg) = std::env::var("INTEROP_FFMPEG") {
        use std::process::Stdio;
        let mut decoder = tokio::process::Command::new(ffmpeg)
            .args([
                "-v",
                "error",
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
                "pipe:1",
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let mut input = decoder.stdin.take().unwrap();
        tokio::spawn(async move {
            input.write_all(&h264).await.unwrap();
            input.shutdown().await.unwrap();
        });
        let output = tokio::time::timeout(Duration::from_secs(20), decoder.wait_with_output())
            .await
            .unwrap()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(output.stdout.starts_with(b"\x89PNG\r\n\x1a\n"));
    }
    runtime
        .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires a real Android 10+ device and changes its test clipboard/application focus"]
async fn real_application_display_clipboard_and_task_survive_session_stop() {
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
    let apps = runtime
        .invoke("apps.list", json!({"deviceId":id}))
        .await
        .unwrap();
    assert!(
        apps["apps"]
            .as_array()
            .unwrap()
            .iter()
            .any(|app| app["packageName"] == "com.android.settings")
    );
    let session = runtime
        .invoke(
            "session.start",
            json!({"deviceId":id,"packageName":"com.android.settings"}),
        )
        .await
        .unwrap();
    let mut video = tokio::net::TcpStream::connect((
        "127.0.0.1",
        session["videoPort"].as_u64().unwrap() as u16,
    ))
    .await
    .unwrap();
    video
        .write_all(session["videoToken"].as_str().unwrap().as_bytes())
        .await
        .unwrap();
    video.write_all(b"\n").await.unwrap();
    let mut initial = [0; 12];
    video.read_exact(&mut initial).await.unwrap();
    let video_task = tokio::spawn(async move {
        let mut buffer = vec![0; 64 * 1024];
        loop {
            if video.read(&mut buffer).await.unwrap_or(0) == 0 {
                break;
            }
        }
    });
    let marker = format!("interop clipboard {}", std::process::id());
    let applied = runtime
        .invoke("clipboard.set", json!({"deviceId":id,"text":marker}))
        .await
        .unwrap();
    assert_eq!(applied["applied"], true);
    let clipboard = runtime
        .invoke("clipboard.get", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(clipboard["text"], marker);
    let inspector = interop_adb::Client::connect_tcp(
        (address.as_str(), port),
        interop_adb::ConnectOptions::default(),
    )
    .await
    .unwrap();
    let before = inspector
        .shell(
            "dumpsys activity activities",
            2 * 1024 * 1024,
            interop_adb::OperationOptions::default(),
        )
        .await
        .unwrap();
    let before = String::from_utf8_lossy(&before.stdout);
    assert!(before.contains("com.android.settings"));
    runtime
        .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(500)).await;
    let after = inspector
        .shell(
            "dumpsys activity activities",
            2 * 1024 * 1024,
            interop_adb::OperationOptions::default(),
        )
        .await
        .unwrap();
    let after = String::from_utf8_lossy(&after.stdout);
    assert!(
        after
            .lines()
            .any(|line| line.contains("ActivityRecord") && line.contains("com.android.settings")),
        "the existing task must survive closing the display"
    );
    video_task.abort();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires a real Android 7+ test device and changes its Settings search field"]
async fn real_scrcpy_touch_and_ascii_unicode_text_reach_android_edit_text() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let inspector = interop_adb::Client::connect_tcp(
        (address.as_str(), port),
        interop_adb::ConnectOptions::default(),
    )
    .await
    .unwrap();
    let shell = |command: &'static str| {
        let client = inspector.clone();
        async move {
            client
                .shell(
                    command,
                    2 * 1024 * 1024,
                    interop_adb::OperationOptions::default(),
                )
                .await
                .unwrap()
        }
    };
    let launched = shell("am start -a android.settings.APP_SEARCH_SETTINGS").await;
    assert!(
        !String::from_utf8_lossy(&launched.stdout).contains("Error"),
        "target must provide a Settings search activity"
    );
    tokio::time::sleep(Duration::from_millis(700)).await;
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
    let session = runtime
        .invoke("session.start", json!({"deviceId":id}))
        .await
        .unwrap();
    let mut video = tokio::net::TcpStream::connect((
        "127.0.0.1",
        session["videoPort"].as_u64().unwrap() as u16,
    ))
    .await
    .unwrap();
    video
        .write_all(session["videoToken"].as_str().unwrap().as_bytes())
        .await
        .unwrap();
    video.write_all(b"\n").await.unwrap();
    let video_task = tokio::spawn(async move {
        let mut buffer = vec![0; 64 * 1024];
        loop {
            if video.read(&mut buffer).await.unwrap_or(0) == 0 {
                break;
            }
        }
    });
    let dump_command = "uiautomator dump /data/local/tmp/interop-input-ui.xml >/dev/null && cat /data/local/tmp/interop-input-ui.xml; rm -f /data/local/tmp/interop-input-ui.xml";
    let ui = shell(dump_command).await;
    let ui = String::from_utf8_lossy(&ui.stdout);
    let edit = ui
        .find("class=\"android.widget.EditText\"")
        .expect("Settings search must expose an EditText");
    let begin = ui[..edit].rfind("<node").unwrap();
    let end = ui[edit..].find("/>").unwrap() + edit;
    let node = &ui[begin..end];
    let bounds = node
        .split("bounds=\"")
        .nth(1)
        .unwrap()
        .split('"')
        .next()
        .unwrap();
    let numbers: Vec<u32> = bounds
        .split(|c: char| !c.is_ascii_digit())
        .filter(|s| !s.is_empty())
        .map(|s| s.parse().unwrap())
        .collect();
    assert_eq!(numbers.len(), 4);
    let physical = shell("wm size").await;
    let physical = String::from_utf8_lossy(&physical.stdout);
    let dimensions = physical
        .lines()
        .rev()
        .find_map(|line| line.split_once(": ").map(|(_, s)| s))
        .unwrap();
    let (physical_width, physical_height) = dimensions.split_once('x').unwrap();
    let physical_width: u64 = physical_width.parse().unwrap();
    let physical_height: u64 = physical_height.parse().unwrap();
    let width = session["width"].as_u64().unwrap();
    let height = session["height"].as_u64().unwrap();
    let x = ((numbers[0] + numbers[2]) as u64 * width / (2 * physical_width)).min(width - 1);
    let y = ((numbers[1] + numbers[3]) as u64 * height / (2 * physical_height)).min(height - 1);
    for action in ["down", "up"] {
        runtime.invoke("session.touch",json!({"sessionId":session["sessionId"],"action":action,"pointerId":1,"x":x,"y":y,"screenWidth":width,"screenHeight":height,"pressure":if action=="up" {0.0} else {1.0}})).await.unwrap();
    }
    // Settings preserves its previous query across launches and across virtual
    // display teardown. Clear it through the same real control channel so this
    // test is repeatable without resetting/force-stopping the application.
    let focused = shell(dump_command).await;
    assert!(String::from_utf8_lossy(&focused.stdout).contains("focused=\"true\""));
    runtime.invoke("session.key",json!({"sessionId":session["sessionId"],"keyCode":29,"metaState":4096,"action":"press"})).await.unwrap();
    runtime
        .invoke(
            "session.key",
            json!({"sessionId":session["sessionId"],"keyCode":67,"action":"press"}),
        )
        .await
        .unwrap();
    runtime
        .invoke(
            "session.text",
            json!({"sessionId":session["sessionId"],"text":"interop_input_fixture"}),
        )
        .await
        .unwrap();
    let ui = shell(dump_command).await;
    assert!(
        String::from_utf8_lossy(&ui.stdout).contains("text=\"interop_input_fixture\""),
        "scrcpy key injection must reach the actual Android field"
    );
    runtime.invoke("session.key",json!({"sessionId":session["sessionId"],"keyCode":29,"metaState":4096,"action":"press"})).await.unwrap();
    runtime
        .invoke(
            "session.text",
            json!({"sessionId":session["sessionId"],"text":"跨设备输入验证"}),
        )
        .await
        .unwrap();
    let ui = shell(dump_command).await;
    assert!(
        String::from_utf8_lossy(&ui.stdout).contains("text=\"跨设备输入验证\""),
        "Unicode paste must reach the actual Android field"
    );
    runtime
        .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
        .await
        .unwrap();
    video_task.abort();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

/// Protocol lifecycle fixture only. Flutter's real renderer is tested separately.
#[tokio::test]
#[ignore = "requires isolated real Android 10+ adbd; starts Settings and pauses its own main capture"]
async fn paused_main_keeps_application_start_independent() {
    main_and_application_start(true).await;
}

#[tokio::test]
#[ignore = "requires isolated real Android 10+ adbd; starts main capture and Settings concurrently"]
async fn streaming_main_keeps_application_start_independent() {
    main_and_application_start(false).await;
}

async fn main_and_application_start(paused: bool) {
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
    runtime
        .invoke("devices.wake", json!({"deviceId":id}))
        .await
        .unwrap();
    let main = runtime
        .invoke("session.start", json!({"deviceId":id,"maxSize":720}))
        .await
        .unwrap();
    let mut socket =
        tokio::net::TcpStream::connect(("127.0.0.1", main["videoPort"].as_u64().unwrap() as u16))
            .await
            .unwrap();
    socket
        .write_all(main["videoToken"].as_str().unwrap().as_bytes())
        .await
        .unwrap();
    socket.write_all(b"\n").await.unwrap();
    let reader = tokio::spawn(async move {
        let mut buffer = [0; 65536];
        while socket.read(&mut buffer).await.unwrap_or(0) != 0 {}
    });
    // Headless acknowledgement enables the protocol pause command. It is not
    // evidence of a real renderer or a decoded frame.
    runtime
        .invoke(
            "session.ready",
            json!({"sessionId":main["sessionId"],"textureId":0}),
        )
        .await
        .unwrap();
    if paused {
        runtime
            .invoke("session.pause", json!({"sessionId":main["sessionId"]}))
            .await
            .unwrap();
    }
    let app = runtime
        .invoke(
            "session.start",
            json!({"deviceId":id,"packageName":"com.android.settings","maxSize":720}),
        )
        .await;
    runtime
        .invoke("session.stop", json!({"sessionId":main["sessionId"]}))
        .await
        .unwrap();
    if let Ok(session) = &app {
        runtime
            .invoke("session.stop", json!({"sessionId":session["sessionId"]}))
            .await
            .unwrap();
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    reader.abort();
    let app = app.expect("a retained main capture must not prevent another real application from producing its first keyframe");
    assert_ne!(app["sessionId"], main["sessionId"]);
    assert_eq!(app["encodedKeyFrameReady"], true);
}
