use interop_adb::{Client, ConnectOptions, Identity, OperationOptions, sync::RemotePath};
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{path::Path, process::Command, sync::Arc, time::Duration};

fn ffmpeg(args: &[&str]) -> Vec<u8> {
    let exe = std::env::var("INTEROP_TEST_FFMPEG")
        .expect("INTEROP_TEST_FFMPEG required: actual JPEG/video decoder");
    let output = Command::new(exe)
        .args(["-hide_banner", "-loglevel", "error", "-threads", "1"])
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "ffmpeg: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output.stdout
}
async fn connected() -> (tempfile::TempDir, Arc<Runtime>, String, Client, String) {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .unwrap()
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let identity = Identity::from_pem(
        &tokio::fs::read_to_string(root.path().join("host_identity.pem"))
            .await
            .unwrap(),
    )
    .unwrap();
    let client = Client::connect_tcp(
        endpoint,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let remote = format!("/data/local/tmp/interop-thumbnail-{}", uuid::Uuid::new_v4());
    let out = client
        .shell(
            &format!("mkdir -m 700 {remote}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(out.exit_code, Some(0));
    (root, runtime, id, client, remote)
}
async fn push(client: &Client, path: &str, bytes: &[u8], mode: u32) {
    client
        .sync(OperationOptions::default())
        .await
        .unwrap()
        .push(
            &RemotePath::new(path).unwrap(),
            &mut std::io::Cursor::new(bytes),
            mode,
            0,
            64 * 1024 * 1024,
        )
        .await
        .unwrap();
}
async fn thumb(runtime: &Arc<Runtime>, id: &str, path: &str) -> Value {
    runtime
        .invoke(
            "media.thumbnail",
            json!({"deviceId":id,"path":path,"maxSize":128}),
        )
        .await
        .unwrap_or_else(|error| panic!("thumbnail {path}: {error:?}"))
}
fn rgb(path: &Path) -> Vec<u8> {
    ffmpeg(&[
        "-i",
        path.to_str().unwrap(),
        "-frames:v",
        "1",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "pipe:1",
    ])
}
fn corners(value: &Value) -> Vec<usize> {
    let bytes = rgb(Path::new(value["localPath"].as_str().unwrap()));
    let w = value["width"].as_u64().unwrap() as usize;
    let h = value["height"].as_u64().unwrap() as usize;
    [
        (w / 4, h / 4),
        (3 * w / 4, h / 4),
        (w / 4, 3 * h / 4),
        (3 * w / 4, 3 * h / 4),
    ]
    .iter()
    .map(|(x, y)| {
        let i = (y * w + x) * 3;
        let p = &bytes[i..i + 3];
        // red, green, blue, yellow; JPEG chroma loss is allowed.
        if p[0] > 150 && p[1] > 150 {
            3
        } else if p[0] > p[1] && p[0] > p[2] {
            0
        } else if p[1] > p[2] {
            1
        } else {
            2
        }
    })
    .collect()
}
fn exif(jpeg: &[u8], orientation: u8) -> Vec<u8> {
    let data = [
        69,
        120,
        105,
        102,
        0,
        0,
        73,
        73,
        42,
        0,
        8,
        0,
        0,
        0,
        1,
        0,
        0x12,
        1,
        3,
        0,
        1,
        0,
        0,
        0,
        orientation,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ];
    let mut output = vec![0xff, 0xd8, 0xff, 0xe1, 0, 34];
    output.extend(data);
    output.extend(&jpeg[2..]);
    output
}

#[tokio::test]
async fn validates_bounds_and_cancel_before_start_without_connecting() {
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":5555}))
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    for max in [json!(0), json!(63), json!(513), json!("128")] {
        assert_eq!(
            runtime
                .invoke(
                    "media.thumbnail",
                    json!({"deviceId":id,"path":"/a.jpg","maxSize":max})
                )
                .await
                .unwrap_err()
                .code,
            "invalid_argument"
        );
    }
    let operation = uuid::Uuid::new_v4().to_string();
    assert_eq!(
        runtime
            .invoke(
                "media.thumbnail.cancel",
                json!({"deviceId":id,"operationId":operation})
            )
            .await
            .unwrap()["status"],
        "cancelledBeforeStart"
    );
    assert_eq!(
        runtime
            .invoke(
                "media.thumbnail",
                json!({"deviceId":id,"path":"/a.jpg","operationId":operation})
            )
            .await
            .unwrap_err()
            .code,
        "cancelled"
    );
    assert!(
        runtime.invoke("session.list", json!({})).await.unwrap()["sessions"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
#[ignore = "requires authorized actual Android endpoint and ffmpeg; only UUID media fixtures, no UI changes"]
async fn real_images_video_orientation_cache_errors_and_cancel_use_only_small_jpeg_rpc() {
    Box::pin(real_thumbnail_fixture()).await;
}
async fn real_thumbnail_fixture() {
    eprintln!("thumbnail fixture setup");
    let (root, runtime, id, client, remote) = Box::pin(connected()).await;
    eprintln!("thumbnail fixture connected");
    let jpeg = ffmpeg(&[
        "-f",
        "lavfi",
        "-i",
        "color=red:s=320x160,drawbox=x=160:y=0:w=160:h=80:c=green:t=fill,drawbox=x=0:y=80:w=160:h=80:c=blue:t=fill,drawbox=x=160:y=80:w=160:h=80:c=yellow:t=fill",
        "-frames:v",
        "1",
        "-f",
        "image2pipe",
        "-c:v",
        "mjpeg",
        "pipe:1",
    ]);
    let expected = [
        [0, 1, 2, 3],
        [1, 0, 3, 2],
        [3, 2, 1, 0],
        [2, 3, 0, 1],
        [0, 2, 1, 3],
        [2, 0, 3, 1],
        [3, 1, 2, 0],
        [1, 3, 0, 2],
    ];
    for orientation in 1..=8 {
        eprintln!("thumbnail EXIF {orientation}");
        let path = format!("{remote}/exif-{orientation}.jpg");
        let source = exif(&jpeg, orientation);
        push(&client, &path, &source, 0o600).await;
        let result = thumb(&runtime, &id, &path).await;
        assert_eq!(result["orientation"], orientation);
        assert_eq!(result["originalSize"], source.len());
        assert_eq!(
            corners(&result),
            expected[orientation as usize - 1],
            "EXIF {orientation}: {result}"
        );
        assert!(
            result["width"].as_u64().unwrap() <= 128 && result["height"].as_u64().unwrap() <= 128
        );
        assert!(result["bytesTransferred"].as_u64().unwrap() < 32 * 1024);
        assert_eq!(result["originalBytesTransferred"], 0);
        if orientation == 1 {
            let hit = thumb(&runtime, &id, &path).await;
            assert_eq!(hit["cacheHit"], true);
            assert_eq!(hit["jpegBytesTransferred"], 0);
            assert!(hit["bytesTransferred"].as_u64().unwrap() < 2048);
            assert_eq!(hit["localPath"], result["localPath"]);
            let cache_path = result["localPath"].as_str().unwrap();
            let mut damaged = tokio::fs::read(cache_path).await.unwrap();
            let middle = damaged.len() / 2;
            damaged[middle] ^= 1;
            tokio::fs::write(cache_path, &damaged).await.unwrap();
            assert_eq!(thumb(&runtime, &id, &path).await["cacheHit"], false);
            // Same size and the same caller-supplied mtime: source ctime/identity
            // validation must invalidate the earlier thumbnail too.
            let changed = exif(&jpeg, 3);
            assert_eq!(changed.len(), source.len());
            push(&client, &path, &changed, 0o600).await;
            let updated = thumb(&runtime, &id, &path).await;
            assert_eq!(updated["cacheHit"], false);
            assert_ne!(updated["localPath"], result["localPath"]);
            assert_eq!(
                updated["sourceStamp"]["modifiedSeconds"],
                result["sourceStamp"]["modifiedSeconds"]
            );
            assert_eq!(corners(&updated), expected[2]);
        }
    }
    let base = root.path().join("video.mp4");
    let rotated = root.path().join("rotated.mp4");
    ffmpeg(&[
        "-f",
        "lavfi",
        "-i",
        "color=red:s=320x160,drawbox=x=160:y=0:w=160:h=80:c=green:t=fill,drawbox=x=0:y=80:w=160:h=80:c=blue:t=fill,drawbox=x=160:y=80:w=160:h=80:c=yellow:t=fill",
        "-t",
        "1",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        base.to_str().unwrap(),
    ]);
    ffmpeg(&[
        "-display_rotation",
        "-90",
        "-i",
        base.to_str().unwrap(),
        "-c",
        "copy",
        rotated.to_str().unwrap(),
    ]);
    // Valid MP4 plus bounded padding proves transport size is independent of the original size.
    let mut video = tokio::fs::read(rotated).await.unwrap();
    video.resize(8 * 1024 * 1024, 0);
    let path = format!("{remote}/rotated.mp4");
    push(&client, &path, &video, 0o600).await;
    let result = thumb(&runtime, &id, &path).await;
    assert_eq!(result["videoRotation"], 90);
    assert!(result["height"].as_u64().unwrap() > result["width"].as_u64().unwrap());
    assert_eq!(corners(&result), vec![2, 0, 3, 1]);
    assert_eq!(result["originalSize"], video.len());
    eprintln!(
        "video original={} JPEG={} RPC={} validation={}",
        video.len(),
        result["jpegBytes"],
        result["bytesTransferred"],
        result["sourceValidation"]
    );
    assert!(result["bytesTransferred"].as_u64().unwrap() < 32 * 1024);
    assert_eq!(result["originalBytesTransferred"], 0);
    assert!(
        !root
            .path()
            .join("media")
            .read_dir()
            .unwrap()
            .any(|entry| entry.unwrap().path().is_file()),
        "thumbnail must not download an original through preview"
    );
    let broken = format!("{remote}/broken.jpg");
    push(&client, &broken, b"not an image", 0o600).await;
    assert_eq!(
        runtime
            .invoke("media.thumbnail", json!({"deviceId":id,"path":broken}))
            .await
            .unwrap_err()
            .code,
        "media_decode_failed"
    );
    assert_eq!(
        runtime
            .invoke(
                "media.thumbnail",
                json!({"deviceId":id,"path":format!("{remote}/missing.jpg")})
            )
            .await
            .unwrap_err()
            .code,
        "not_found"
    );
    eprintln!("thumbnail PNG/limits");
    let png = ffmpeg(&[
        "-f",
        "lavfi",
        "-i",
        "color=blue:s=1024x512",
        "-frames:v",
        "1",
        "-f",
        "image2pipe",
        "-c:v",
        "png",
        "pipe:1",
    ]);
    let png_path = format!("{remote}/large.png");
    push(&client, &png_path, &png, 0o600).await;
    let png_thumb = thumb(&runtime, &id, &png_path).await;
    assert_eq!(
        (png_thumb["width"].as_u64(), png_thumb["height"].as_u64()),
        (Some(128), Some(64))
    );
    let mut giant = jpeg.clone();
    let sof = giant
        .windows(2)
        .position(|pair| pair == [255, 192])
        .expect("baseline JPEG SOF");
    giant[sof + 5..sof + 7].copy_from_slice(&20000u16.to_be_bytes());
    giant[sof + 7..sof + 9].copy_from_slice(&20000u16.to_be_bytes());
    let giant_path = format!("{remote}/giant.jpg");
    push(&client, &giant_path, &giant, 0o600).await;
    assert_eq!(
        runtime
            .invoke("media.thumbnail", json!({"deviceId":id,"path":giant_path}))
            .await
            .unwrap_err()
            .code,
        "media_pixel_limit"
    );
    let link = format!("{remote}/link.jpg");
    client
        .shell(
            &format!("ln -s {remote}/exif-1.jpg {link}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert!(
        runtime
            .invoke("media.thumbnail", json!({"deviceId":id,"path":link}))
            .await
            .is_err(),
        "never follow a final symlink, even if ROM denies lstat"
    );
    let audio = root.path().join("audio-only.mp4");
    ffmpeg(&[
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:duration=0.2",
        "-c:a",
        "aac",
        audio.to_str().unwrap(),
    ]);
    let audio_path = format!("{remote}/no-frame.mp4");
    push(
        &client,
        &audio_path,
        &tokio::fs::read(audio).await.unwrap(),
        0o600,
    )
    .await;
    assert_eq!(
        runtime
            .invoke("media.thumbnail", json!({"deviceId":id,"path":audio_path}))
            .await
            .unwrap_err()
            .code,
        "media_no_frame"
    );
    let denied = format!("{remote}/denied.jpg");
    push(&client, &denied, &jpeg, 0o000).await;
    assert_eq!(
        runtime
            .invoke("media.thumbnail", json!({"deviceId":id,"path":denied}))
            .await
            .unwrap_err()
            .code,
        "permission_denied"
    );
    let op = uuid::Uuid::new_v4().to_string();
    let mut events = runtime.subscribe();
    let task = {
        let runtime = runtime.clone();
        let id = id.clone();
        let path = path.clone();
        let op = op.clone();
        tokio::spawn(async move {
            runtime
                .invoke(
                    "media.thumbnail",
                    json!({"deviceId":id,"path":path,"maxSize":512,"operationId":op}),
                )
                .await
        })
    };
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let event = events.recv().await.unwrap();
            if event["type"] == "media.thumbnail.started" {
                break;
            }
        }
    })
    .await
    .unwrap();
    eprintln!("thumbnail actual child cancellation");
    let child = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let ps =
                Box::pin(client.shell("ps -A -o PID,ARGS", 64 * 1024, OperationOptions::default()))
                    .await
                    .unwrap();
            let text = String::from_utf8(ps.stdout).unwrap();
            if let Some(line) = text
                .lines()
                .find(|line| line.contains(&format!("interop-thumb-{op}")))
            {
                break line
                    .split_whitespace()
                    .next()
                    .unwrap()
                    .parse::<u32>()
                    .unwrap();
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("an actual isolated thumbnail child was running before cancellation");
    assert_eq!(
        runtime
            .invoke(
                "media.thumbnail.cancel",
                json!({"deviceId":id,"operationId":op})
            )
            .await
            .unwrap()["cancelRequested"],
        true
    );
    assert_eq!(task.await.unwrap().unwrap_err().code, "cancelled");
    let gone = client
        .shell(
            &format!("test ! -d /proc/{child}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(
        gone.exit_code,
        Some(0),
        "cancel must wait for the observed owned child to exit"
    );
    let mut listing = runtime
        .invoke("media.list", json!({"deviceId":id}))
        .await
        .unwrap();
    let scan = listing["scanId"].as_str().unwrap().to_owned();
    tokio::time::timeout(Duration::from_secs(40), async {
        while listing["status"] == "scanning" {
            tokio::time::sleep(Duration::from_millis(100)).await;
            listing = runtime
                .invoke("media.list", json!({"deviceId":id,"scanId":scan}))
                .await
                .unwrap();
        }
    })
    .await
    .expect("the bounded read-only gallery scan must settle after thumbnail cancellation");
    assert!(matches!(
        listing["status"].as_str(),
        Some("completed" | "partial")
    ));
    assert_eq!(listing["scope"]["roots"], json!(["/sdcard"]));
    // A separate service remains responsive after media cancellation.
    runtime
        .invoke("clipboard.get", json!({"deviceId":id}))
        .await
        .unwrap();
    client
        .shell(
            &format!("rm -rf {remote}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    eprintln!(
        "real thumbnails: EXIF 1..8, rotated padded 8MiB MP4, ffmpeg JPEG decode, cache/digest/source change, negative cases and cancellation passed"
    );
}

#[tokio::test]
#[ignore = "requires actual Android endpoint and ffmpeg; disconnects only this test-owned media operation"]
async fn real_disconnect_reaps_media_child_without_reviving_companion() {
    let (_root, runtime, id, client, remote) = connected().await;
    let jpeg = ffmpeg(&[
        "-f",
        "lavfi",
        "-i",
        "color=red:s=320x160",
        "-frames:v",
        "1",
        "-f",
        "image2pipe",
        "-c:v",
        "mjpeg",
        "pipe:1",
    ]);
    let path = format!("{remote}/disconnect.jpg");
    push(&client, &path, &jpeg, 0o600).await;
    let op = uuid::Uuid::new_v4().to_string();
    let task = {
        let runtime = runtime.clone();
        let id = id.clone();
        let op = op.clone();
        tokio::spawn(async move {
            runtime
                .invoke(
                    "media.thumbnail",
                    json!({"deviceId":id,"path":path,"operationId":op}),
                )
                .await
        })
    };
    let child = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let ps =
                Box::pin(client.shell("ps -A -o PID,ARGS", 64 * 1024, OperationOptions::default()))
                    .await
                    .unwrap();
            let text = String::from_utf8(ps.stdout).unwrap();
            if let Some(line) = text.lines().find(|line| {
                line.contains(&format!("interop-thumb-{op}"))
                    || line.contains(&format!("interop-stat-{op}"))
            }) {
                break line
                    .split_whitespace()
                    .next()
                    .unwrap()
                    .parse::<u32>()
                    .unwrap();
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("observed an actual media child before disconnect");
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    let result = task.await.unwrap();
    assert!(
        result.is_err(),
        "disconnected operation cannot publish cached success"
    );
    let gone = client
        .shell(
            &format!("test ! -d /proc/{child}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(gone.exit_code, Some(0));
    assert_eq!(
        runtime
            .invoke(
                "media.thumbnail",
                json!({"deviceId":id,"path":format!("{remote}/disconnect.jpg")})
            )
            .await
            .unwrap_err()
            .code,
        "disconnected"
    );
    client
        .shell(
            &format!("rm -rf {remote}"),
            1024,
            OperationOptions::default(),
        )
        .await
        .unwrap();
}
