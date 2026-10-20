use base64::Engine;
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{path::PathBuf, process::Command, sync::Arc, time::Duration};

fn adb(arguments: &[&str]) {
    let result = Command::new(std::env::var("ANDROID_ADB").expect("ANDROID_ADB"))
        .args([
            "-s",
            &std::env::var("ANDROID_TARGET_SERIAL").expect("ANDROID_TARGET_SERIAL"),
        ])
        .args(arguments)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
}

async fn running(runtime: &Arc<Runtime>, id: &str) -> Value {
    runtime
        .invoke("apps.list", json!({"deviceId":id,"filter":"running"}))
        .await
        .unwrap()
}

fn settings_present(value: &Value) -> bool {
    value["apps"]
        .as_array()
        .unwrap()
        .iter()
        .any(|app| app["packageName"] == "com.android.settings")
}

#[tokio::test]
#[ignore = "requires isolated authorized Android 10+ target without an existing Settings task; changes Settings focus/task"]
async fn target_tasks_and_real_icons_follow_started_and_removed_application() {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("INTEROP_CORE_TEST_ENDPOINT")
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("observation.stop", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let initial = running(&runtime, id).await;
    assert_eq!(initial["deviceId"], id);
    assert_eq!(initial["source"], "runningTasks");
    assert_eq!(initial["live"], true);
    assert!(
        !settings_present(&initial),
        "Use an isolated target without an existing Settings task"
    );
    assert!(
        initial["apps"]
            .as_array()
            .unwrap()
            .iter()
            .all(|app| app["packageName"] != "com.google.android.apps.nexuslauncher")
    );

    let check_runtime = runtime.clone();
    let check_id = id.to_owned();
    let check = async move {
        let runtime = check_runtime;
        let id = check_id.as_str();
        let icon = runtime
            .invoke(
                "apps.icon",
                json!({"deviceId":id,"packageName":"com.android.settings"}),
            )
            .await
            .unwrap();
        assert_eq!(icon["deviceId"], id);
        assert_eq!(icon["packageName"], "com.android.settings");
        assert_eq!(icon["mimeType"], "image/png");
        assert_eq!(icon["width"], 96);
        assert_eq!(icon["height"], 96);
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(icon["dataBase64"].as_str().unwrap())
            .unwrap();
        assert!(bytes.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert!(bytes.len() > 100 && bytes.len() <= 128 * 1024);
        if let Ok(directory) = std::env::var("INTEROP_APP_ICON_DIRECTORY") {
            let directory = PathBuf::from(directory);
            std::fs::create_dir_all(&directory).unwrap();
            std::fs::write(directory.join("com.android.settings.png"), bytes).unwrap();
            std::fs::write(
                directory.join("running-before.json"),
                serde_json::to_vec_pretty(&initial).unwrap(),
            )
            .unwrap();
            if let Ok(packages) = std::env::var("INTEROP_APP_ICON_PACKAGES") {
                for package in packages.split(',').filter(|name| !name.is_empty()) {
                    let icon = runtime
                        .invoke("apps.icon", json!({"deviceId":id,"packageName":package}))
                        .await
                        .unwrap();
                    let bytes = base64::engine::general_purpose::STANDARD
                        .decode(icon["dataBase64"].as_str().unwrap())
                        .unwrap();
                    assert!(bytes.starts_with(b"\x89PNG\r\n\x1a\n"));
                    std::fs::write(directory.join(format!("{package}.png")), bytes).unwrap();
                }
            }
        }
        let error = runtime
            .invoke(
                "apps.icon",
                json!({"deviceId":id,"packageName":"org.interop.missing_package_0123456789"}),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "app_not_found");
        adb(&[
            "shell",
            "am",
            "start",
            "-W",
            "-a",
            "android.settings.SETTINGS",
        ]);
        adb(&["shell", "input", "keyevent", "KEYCODE_HOME"]);
        let started = running(&runtime, id).await;
        assert!(
            settings_present(&started),
            "Started background Settings task is missing: {started}"
        );
        let app = started["apps"]
            .as_array()
            .unwrap()
            .iter()
            .find(|app| app["packageName"] == "com.android.settings")
            .unwrap();
        assert!(app["taskId"].as_i64().unwrap() > 0);
        assert_eq!(app["userId"], started["userId"]);
        if let Ok(directory) = std::env::var("INTEROP_APP_ICON_DIRECTORY") {
            std::fs::write(
                PathBuf::from(directory).join("running-started.json"),
                serde_json::to_vec_pretty(&started).unwrap(),
            )
            .unwrap();
        }
    };
    // Clean the one app task created by this test even if an assertion fails.
    let result = tokio::spawn(check).await;
    adb(&["shell", "am", "force-stop", "com.android.settings"]);
    let mut removed = false;
    for _ in 0..20 {
        if !settings_present(&running(&runtime, id).await) {
            removed = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert!(
        removed,
        "Removed Settings task remains in the background app list"
    );
    result.unwrap();
}
