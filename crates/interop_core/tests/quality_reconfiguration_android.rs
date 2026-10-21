//! Actual API-level evidence, using the product executor and pinned server.
mod support;
use interop_core::Runtime;
use serde_json::{Value, json};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn adb(arguments: &[&str]) -> String {
    let binary = std::env::var("INTEROP_ADB").expect("INTEROP_ADB");
    let serial = std::env::var("INTEROP_TARGET_SERIAL").expect("INTEROP_TARGET_SERIAL");
    let output = tokio::process::Command::new(binary)
        .arg("-s")
        .arg(serial)
        .args(arguments)
        .output()
        .await
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}

async fn runtime() -> (tempfile::TempDir, std::sync::Arc<Runtime>, String) {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let added = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":port}))
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap().to_owned();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    (directory, runtime, id)
}

#[tokio::test]
#[ignore = "requires an awake authorized target and INTEROP_ADB/INTEROP_TARGET_SERIAL"]
async fn virtual_display_density_evidence() {
    let (_directory, runtime, id) = runtime().await;
    adb(&["shell", "am", "start", "-a", "android.settings.SETTINGS"]).await;
    let physical = adb(&["shell", "dumpsys", "activity", "activities"]).await;
    let opened = runtime
        .invoke(
            "session.start",
            support::media_params(json!({
                "deviceId":id, "packageName":"com.android.settings", "maxSize":1280,
                "displayWidth":720,"displayHeight":1280,
            })),
        )
        .await;
    if let Err(error) = &opened {
        runtime.stop_all().await;
        panic!("virtual startup: {error:?}");
    }
    let opened = opened.unwrap();
    tokio::time::sleep(Duration::from_millis(500)).await;
    let display = adb(&["shell", "dumpsys", "display"]).await;
    let stacks = adb(&["shell", "cmd", "activity", "stack", "list"]).await;
    let virtual_activities = adb(&["shell", "dumpsys", "activity", "activities"]).await;
    runtime.stop_all().await;
    assert_eq!(opened["displayDensity"], 280);
    assert!(
        stacks.contains("sw411dp"),
        "phone logical width missing: {stacks}"
    );
    for (label, text) in [("physical", &physical), ("virtual", &virtual_activities)] {
        eprintln!(
            "{label}: {}",
            text.lines()
                .filter(|line| line.contains("com.android.settings")
                    || line.contains("mCurrentConfig=")
                    || line.contains("displayId="))
                .collect::<Vec<_>>()
                .join("\n")
        );
    }
    eprintln!("displays: {}", display.lines().filter(|line| line.contains("DisplayDeviceInfo{") || line.contains("mBaseDisplayInfo=")).collect::<Vec<_>>().join("\n"));
    eprintln!(
        "session width={} height={}",
        opened["width"], opened["height"]
    );
    let root = std::env::temp_dir();
    tokio::fs::write(root.join("scrcpy-density-physical.txt"), physical)
        .await
        .unwrap();
    tokio::fs::write(root.join("scrcpy-density-virtual.txt"), virtual_activities)
        .await
        .unwrap();
    tokio::fs::write(root.join("scrcpy-density-displays.txt"), display)
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires an awake authorized real adbd"]
async fn quality_change_updates_existing_capture_in_place() {
    let (_directory, runtime, id) = runtime().await;
    let session = runtime
        .invoke(
            "session.start",
            support::media_params(json!({"deviceId":id,"maxSize":720})),
        )
        .await
        .unwrap();
    let result = runtime
        .invoke(
            "session.quality",
            support::media_params(json!({"deviceId":id,"maxSize":1280})),
        )
        .await
        .unwrap();
    let rebuilt = runtime
        .invoke(
            "session.reconfigure",
            support::media_params(
                json!({"deviceId":id,"sessionId":session["sessionId"],"maxSize":1280}),
            ),
        )
        .await;
    let sessions = runtime
        .invoke("session.list", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime.stop_all().await;
    let rebuilt = rebuilt.unwrap();
    assert_eq!(rebuilt["sessionId"], session["sessionId"]);
    assert_eq!(rebuilt["generation"], 2);
    let current = sessions["sessions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["sessionId"] == session["sessionId"])
        .unwrap();
    assert_eq!(
        current["quality"]["maxSize"], 1280,
        "saving must also reconfigure the existing window: {result}"
    );
}

#[tokio::test]
#[ignore = "requires awake target; migrates the existing Settings task without relaunch"]
async fn independent_quality_rebuild_retains_real_task() {
    let (_directory, runtime, id) = runtime().await;
    let session = runtime.invoke("session.start", support::media_params(json!({"deviceId":id,"packageName":"com.android.settings","displayWidth":720,"displayHeight":1280,"maxSize":1280}))).await.unwrap();
    let rebuilt = runtime
        .invoke(
            "session.reconfigure",
            support::media_params(
                json!({"deviceId":id,"sessionId":session["sessionId"],"maxSize":1920}),
            ),
        )
        .await;
    let stacks = adb(&["shell", "cmd", "activity", "stack", "list"]).await;
    runtime.stop_all().await;
    let rebuilt = rebuilt.unwrap();
    assert_eq!(rebuilt["sessionId"], session["sessionId"]);
    assert_eq!(rebuilt["taskId"], session["taskId"]);
    assert_eq!(rebuilt["generation"], 2);
    assert_eq!(
        stacks
            .lines()
            .filter(|line| line.trim_start().starts_with("taskId=")
                && line.contains(": com.android.settings/"))
            .count(),
        1
    );
    assert_eq!(rebuilt["displaySize"]["height"], 1920);
    assert_eq!(rebuilt["displayDensity"], 420);
    assert!(stacks.contains("sw411dp"));
    eprintln!(
        "task before={} display={} after={} display={} density={}\n{stacks}",
        session["taskId"],
        session["displayId"],
        rebuilt["taskId"],
        rebuilt["displayId"],
        rebuilt["displayDensity"]
    );
}

#[tokio::test]
#[ignore = "requires awake real target; explicit close races a capture rebuild"]
async fn explicit_close_during_rebuild_does_not_resurrect_window() {
    let (_directory, runtime, id) = runtime().await;
    let session = runtime
        .invoke(
            "session.start",
            support::media_params(json!({"deviceId":id,"maxSize":720})),
        )
        .await
        .unwrap();
    let (result, stopped) = tokio::join!(
        runtime.invoke(
            "session.reconfigure",
            support::media_params(
                json!({"deviceId":id,"sessionId":session["sessionId"],"maxSize":1280})
            )
        ),
        async {
            tokio::time::sleep(Duration::from_millis(80)).await;
            runtime
                .invoke(
                    "session.stop",
                    json!({"deviceId":id,"sessionId":session["sessionId"]}),
                )
                .await
        }
    );
    let listed = runtime
        .invoke("session.list", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime.stop_all().await;
    assert!(stopped.is_ok(), "{stopped:?}");
    assert!(result.is_err(), "closed session was rebuilt: {result:?}");
    assert!(
        listed["sessions"].as_array().unwrap().is_empty(),
        "{listed}"
    );
}

#[tokio::test]
#[ignore = "requires awake target; physical wm-size lease is restored on completion"]
async fn physical_ratio_survives_quality_rebuild() {
    let (_directory, runtime, id) = runtime().await;
    let baseline = adb(&["shell", "wm", "size"]).await;
    let session = runtime
        .invoke(
            "session.start",
            support::media_params(
                json!({"deviceId":id,"maxSize":720,"displayWidth":800,"displayHeight":1280}),
            ),
        )
        .await
        .unwrap();
    let result = runtime
        .invoke(
            "session.reconfigure",
            support::media_params(
                json!({"deviceId":id,"sessionId":session["sessionId"],"maxSize":1280}),
            ),
        )
        .await;
    let applied = adb(&["shell", "wm", "size"]).await;
    runtime.stop_all().await;
    let restored = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let current = adb(&["shell", "wm", "size"]).await;
            if current == baseline {
                break current;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("supervisor must restore the original physical override");
    assert!(result.is_ok(), "{result:?}");
    assert!(applied.contains("Override size: 800x1280"), "{applied}");
    assert_eq!(baseline, restored);
}

#[tokio::test]
#[ignore = "requires real target; resizes/rotates only the owned virtual display"]
async fn virtual_resize_and_rotation_keep_phone_logical_width() {
    let (_directory, runtime, id) = runtime().await;
    let session = runtime.invoke("session.start",support::media_params(json!({"deviceId":id,"packageName":"com.android.settings","displayWidth":720,"displayHeight":1280,"maxSize":1920}))).await.unwrap();
    let resized = runtime.invoke("session.display",json!({"deviceId":id,"sessionId":session["sessionId"],"displayWidth":1080,"displayHeight":1920})).await;
    let stacks = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let stacks = adb(&["shell", "cmd", "activity", "stack", "list"]).await;
            if stacks.contains("[1080,1920]") && stacks.contains("sw411dp") {
                break stacks;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await;
    let rotated = runtime
        .invoke(
            "session.rotate",
            json!({"deviceId":id,"sessionId":session["sessionId"]}),
        )
        .await;
    let landscape = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let stacks = adb(&["shell", "cmd", "activity", "stack", "list"]).await;
            if stacks.contains("[1920,1080]") && stacks.contains("sw411dp") {
                break stacks;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await;
    runtime.stop_all().await;
    assert!(resized.is_ok(), "{resized:?}");
    assert!(rotated.is_ok(), "{rotated:?}");
    assert!(
        stacks.is_ok(),
        "resize did not preserve phone dp: {stacks:?}"
    );
    assert!(
        landscape.is_ok(),
        "rotation did not preserve phone dp: {landscape:?}"
    );
}

async fn drain_endpoint(endpoint: &Value) -> tokio::task::JoinHandle<()> {
    let url = endpoint["url"]
        .as_str()
        .unwrap()
        .strip_prefix("http://")
        .unwrap();
    let (address, path) = url.split_once('/').unwrap();
    let mut socket = tokio::net::TcpStream::connect(address).await.unwrap();
    socket
        .write_all(format!("GET /{path} HTTP/1.1\r\nHost: localhost\r\n\r\n").as_bytes())
        .await
        .unwrap();
    tokio::spawn(async move {
        let mut buffer = [0; 16384];
        while matches!(socket.read(&mut buffer).await,Ok(count) if count>0) {}
    })
}
async fn renderer_endpoint(
    runtime: &std::sync::Arc<Runtime>,
    stream: &Value,
    generation: u64,
) -> Value {
    runtime.invoke("media.open",json!({"kind":"video","port":stream["videoPort"],"token":stream["videoToken"],"codec":stream["codec"],"generation":generation})).await.unwrap()
}
async fn next_endpoint(runtime: &std::sync::Arc<Runtime>, relay: &Value, previous: u64) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let status = runtime
                .invoke("media.status", json!({"relayId":relay["relayId"]}))
                .await
                .unwrap();
            if status["endpoint"]["generation"].as_u64().unwrap_or(0) > previous {
                break status["endpoint"].clone();
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("actual relay must publish resized codec configuration")
}
#[tokio::test]
#[ignore = "requires real target; exercises core/HTTP generations, renderer verified separately"]
async fn resize_quality_resize_separates_capture_from_renderer_generation() {
    let (_directory, runtime, id) = runtime().await;
    let session = runtime.invoke("session.start",support::media_params(json!({"deviceId":id,"packageName":"com.android.settings","displayWidth":720,"displayHeight":1280,"maxSize":1920}))).await.unwrap();
    let sid = session["sessionId"].clone();
    let first = renderer_endpoint(&runtime, &session, 1).await;
    let first_reader = drain_endpoint(&first).await;
    runtime
        .invoke(
            "session.ready",
            json!({"sessionId":sid,"textureId":1,"generation":1,"captureGeneration":1}),
        )
        .await
        .unwrap();
    runtime
        .invoke(
            "session.display",
            json!({"sessionId":sid,"displayWidth":1080,"displayHeight":1920}),
        )
        .await
        .unwrap();
    let resized = next_endpoint(&runtime, &first, 1).await;
    let resized_reader = drain_endpoint(&resized).await;
    let generation = resized["generation"].as_u64().unwrap();
    runtime
        .invoke(
            "session.ready",
            json!({"sessionId":sid,"textureId":2,"generation":generation,"captureGeneration":1}),
        )
        .await
        .unwrap();
    let rebuilt = runtime
        .invoke(
            "session.reconfigure",
            json!({"deviceId":id,"sessionId":sid,"maxSize":1280}),
        )
        .await
        .unwrap();
    assert_eq!(rebuilt["captureGeneration"], 2);
    let next = rebuilt["generation"].as_u64().unwrap();
    assert!(next > generation);
    let second = renderer_endpoint(&runtime, &rebuilt, next).await;
    let second_reader = drain_endpoint(&second).await;
    runtime
        .invoke(
            "session.ready",
            json!({"sessionId":sid,"textureId":3,"generation":next,"captureGeneration":2}),
        )
        .await
        .unwrap();
    let stale = runtime
        .invoke(
            "session.ready",
            json!({"sessionId":sid,"textureId":999,"generation":next+100,"captureGeneration":1}),
        )
        .await
        .unwrap_err();
    assert_eq!(stale.code, "stale_generation");
    runtime
        .invoke(
            "session.display",
            json!({"sessionId":sid,"displayWidth":640,"displayHeight":1138}),
        )
        .await
        .unwrap();
    let final_endpoint = next_endpoint(&runtime, &second, next).await;
    let final_reader = drain_endpoint(&final_endpoint).await;
    let ready = runtime.invoke("session.ready",json!({"sessionId":sid,"textureId":4,"generation":final_endpoint["generation"],"captureGeneration":2})).await.unwrap();
    runtime.stop_all().await;
    for reader in [first_reader, resized_reader, second_reader, final_reader] {
        reader.abort();
    }
    assert_eq!(ready["captureGeneration"], 2);
    assert_eq!(ready["textureId"], 4);
    assert_eq!(ready["qualityRebuilding"], false);
}

#[tokio::test]
#[ignore = "requires awake real target; owns and restores a physical display lease"]
async fn physical_resize_after_quality_uses_the_new_capture_owner() {
    let (_directory, runtime, id) = runtime().await;
    let baseline = adb(&["shell", "wm", "size"]).await;
    let session = runtime
        .invoke(
            "session.start",
            support::media_params(
                json!({"deviceId":id,"maxSize":720,"displayWidth":800,"displayHeight":1280}),
            ),
        )
        .await
        .unwrap();
    let rebuilt = runtime
        .invoke(
            "session.reconfigure",
            support::media_params(
                json!({"deviceId":id,"sessionId":session["sessionId"],"maxSize":1280}),
            ),
        )
        .await;
    // This is an executor/HTTP ownership test, not a local-decoder acceptance.
    // Consume the replacement stream before acknowledging the renderer boundary;
    // actual MDK verification remains in device_quality_test.dart.
    let mut reader = None;
    let ready = if let Ok(current) = &rebuilt {
        let endpoint =
            renderer_endpoint(&runtime, current, current["generation"].as_u64().unwrap()).await;
        reader = Some(drain_endpoint(&endpoint).await);
        runtime.invoke("session.ready", json!({
            "sessionId":session["sessionId"], "textureId":1,
            "generation":current["generation"], "captureGeneration":current["captureGeneration"],
        })).await
    } else {
        Err(interop_core::CoreError::new(
            "rebuild_failed",
            "capture not replaced",
        ))
    };
    let resized = runtime.invoke("session.display",json!({"deviceId":id,"sessionId":session["sessionId"],"displayWidth":640,"displayHeight":960})).await;
    runtime.stop_all().await;
    if let Some(reader) = reader {
        reader.abort();
    }
    let restored = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let size = adb(&["shell", "wm", "size"]).await;
            if size == baseline {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await;
    eprintln!(
        "baseline={baseline:?} capture_generation={:?} ready_ok={} resized={resized:?} restored={}",
        rebuilt
            .as_ref()
            .ok()
            .map(|value| &value["captureGeneration"]),
        ready.is_ok(),
        restored.is_ok()
    );
    assert!(rebuilt.is_ok(), "{rebuilt:?}");
    assert!(ready.is_ok(), "{ready:?}");
    assert!(
        resized.is_ok(),
        "resize did not own its replacement capture: {resized:?}"
    );
    assert!(
        restored.is_ok(),
        "replacement capture did not restore its own lease"
    );
}
