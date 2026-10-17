//! Opt-in AVD acceptance through Runtime commands and real Binder events.
//! This does not exercise host background notification delivery.
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};
use tokio::sync::broadcast;

fn adb(args: &[&str]) {
    let binary = std::env::var("ANDROID_ADB").expect("ANDROID_ADB is a test harness only");
    let serial = std::env::var("ANDROID_TARGET_SERIAL").expect("ANDROID_TARGET_SERIAL");
    assert!(
        serial
            .strip_prefix("emulator-")
            .is_some_and(|port| port.parse::<u16>().is_ok()),
        "synthetic notifications require an explicitly selected AVD"
    );
    let result = std::process::Command::new(binary)
        .args(["-s", &serial])
        .args(args)
        .output()
        .expect("run official adb test harness");
    assert!(
        result.status.success(),
        "official adb fixture command failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
}

async fn wait_live(events: &mut broadcast::Receiver<Value>, device: &str) -> Value {
    tokio::time::timeout(Duration::from_secs(35), async {
        loop {
            let event = events.recv().await.expect("observation event stream");
            if event["deviceId"] == device
                && event["type"] == "observation.changed"
                && event["data"]["notifications"]["live"] == true
                && event["data"]["calls"]["live"] == true
            {
                return event["data"].clone();
            }
        }
    })
    .await
    .expect("connection/start must establish live observation without a page list query")
}

async fn assert_stopped(
    runtime: &Arc<Runtime>,
    device: &str,
    events: &mut broadcast::Receiver<Value>,
) {
    let until = tokio::time::Instant::now() + Duration::from_secs(2);
    while tokio::time::Instant::now() < until {
        for allow_start in [false, true] {
            for (command, collection) in [
                ("notifications.list", "notifications"),
                ("calls.list", "calls"),
            ] {
                let result = runtime
                    .invoke(command, json!({"deviceId":device,"allowStart":allow_start}))
                    .await
                    .unwrap();
                assert_eq!(
                    result["status"], "stopped",
                    "{command} cannot restart observation"
                );
                assert_eq!(result["live"], false);
                assert_eq!(result[collection], json!([]));
            }
        }
        let status = runtime
            .invoke("observation.status", json!({"deviceId":device}))
            .await
            .unwrap();
        assert_eq!(status["wanted"], false);
        assert_eq!(status["phase"], "stopped");
        loop {
            match events.try_recv() {
                Ok(event) if event["deviceId"] == device => assert!(
                    !matches!(
                        event["type"].as_str(),
                        Some(
                            "notifications.changed"
                                | "calls.changed"
                                | "calls.incoming"
                                | "companion.starting"
                        )
                    ),
                    "stopped observation cannot publish data or start a helper: {}",
                    event["type"]
                ),
                Ok(_) => {}
                Err(broadcast::error::TryRecvError::Empty) => break,
                Err(error) => panic!("observation event stream: {error}"),
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

struct TargetCleanup {
    runtime: Arc<Runtime>,
    device: String,
    tag: String,
    original_clipboard: Option<String>,
    posted: bool,
}
impl TargetCleanup {
    async fn restore_clipboard(&self, original: &str) -> Result<(), String> {
        let written = self
            .runtime
            .invoke(
                "clipboard.set",
                json!({"deviceId":self.device,"text":original}),
            )
            .await
            .map_err(|error| format!("restore clipboard: {}", error.code))?;
        if written["applied"] != true {
            return Err("original clipboard was not restored".into());
        }
        let restored = self
            .runtime
            .invoke(
                "clipboard.get",
                json!({"deviceId":self.device,"allowStart":false}),
            )
            .await
            .map_err(|error| format!("verify original clipboard: {}", error.code))?;
        if restored["hasText"] != true || restored["text"].as_str() != Some(original) {
            return Err("original clipboard verification failed".into());
        }
        Ok(())
    }
    async fn remove_notification(&self) -> Result<(), String> {
        // AOSP cmd notification has no cancel subcommand. Use only the
        // fixture's exact title/package through the public dismiss operation.
        self.runtime
            .invoke("observation.start", json!({"deviceId":self.device}))
            .await
            .map_err(|error| format!("start fixture cleanup observer: {}", error.code))?;
        tokio::time::timeout(Duration::from_secs(35), async {
            loop {
                let status = self
                    .runtime
                    .invoke("observation.status", json!({"deviceId":self.device}))
                    .await
                    .map_err(|error| format!("cleanup observation status: {}", error.code))?;
                if status["notifications"]["live"] == true {
                    return Ok::<(), String>(());
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .map_err(|_| "fixture cleanup observer did not become live".to_owned())??;
        let snapshot = self
            .runtime
            .invoke(
                "notifications.list",
                json!({"deviceId":self.device,"allowStart":false}),
            )
            .await
            .map_err(|error| format!("list fixture for cleanup: {}", error.code))?;
        let items = snapshot["notifications"]
            .as_array()
            .ok_or("cleanup notification collection missing")?;
        for item in items
            .iter()
            .filter(|item| item["title"] == self.tag && item["packageName"] == "com.android.shell")
        {
            self.runtime
                .invoke(
                    "notifications.dismiss",
                    json!({"deviceId":self.device,"notificationId":item["id"]}),
                )
                .await
                .map_err(|error| format!("dismiss fixture: {}", error.code))?;
        }
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = self
                    .runtime
                    .invoke(
                        "notifications.list",
                        json!({"deviceId":self.device,"allowStart":false}),
                    )
                    .await
                    .map_err(|error| format!("verify fixture cleanup: {}", error.code))?;
                if snapshot["notifications"].as_array().is_some_and(|items| {
                    !items.iter().any(|item| {
                        item["title"] == self.tag && item["packageName"] == "com.android.shell"
                    })
                }) {
                    return Ok::<(), String>(());
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .map_err(|_| "fixture notification remained on target".to_owned())?
    }
    async fn run(&self) -> Result<(), String> {
        let mut errors = Vec::new();
        if self.original_clipboard.is_some() || self.posted {
            let connected = self
                .runtime
                .invoke("device.info", json!({"deviceId":self.device}))
                .await
                .is_ok_and(|device| device["status"] == "connected");
            if !connected
                && let Err(error) = self
                    .runtime
                    .invoke("devices.connect", json!({"deviceId":self.device}))
                    .await
            {
                errors.push(format!("reconnect for cleanup: {}", error.code));
            }
        }
        if let Some(original) = &self.original_clipboard
            && let Err(error) = self.restore_clipboard(original).await
        {
            errors.push(error);
        }
        if self.posted
            && let Err(error) = self.remove_notification().await
        {
            errors.push(error);
        }
        if let Err(error) = self
            .runtime
            .invoke("devices.disconnect", json!({"deviceId":self.device}))
            .await
        {
            errors.push(format!("disconnect fixture: {}", error.code));
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.join("; "))
        }
    }
}

struct CleanupGuard(Option<TargetCleanup>);
impl CleanupGuard {
    async fn finish(&mut self) {
        self.0
            .as_ref()
            .unwrap()
            .run()
            .await
            .expect("restore target fixture before completing test");
        self.0 = None;
    }
}
impl Drop for CleanupGuard {
    fn drop(&mut self) {
        let Some(cleanup) = self.0.take() else {
            return;
        };
        // The test uses two Tokio workers: its existing socket actors remain
        // runnable while this thread waits for panic-path cleanup to finish.
        let result = std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|error| error.to_string())?;
            runtime.block_on(async {
                tokio::time::timeout(Duration::from_secs(90), cleanup.run())
                    .await
                    .map_err(|_| "target fixture cleanup timed out".to_owned())?
            })
        })
        .join();
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => eprintln!("observation fixture cleanup failed: {error}"),
            Err(_) => eprintln!("observation fixture cleanup thread failed"),
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires actual Android endpoint and explicit official-adb AVD; temporarily changes text clipboard and one unique notification"]
async fn connection_observes_without_page_queries_and_explicit_stop_survives_reconnect() {
    // Validate the AVD selection before any Runtime connection or mutation.
    adb(&["get-state"]);
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
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    let tag = format!("interop-observation-{}", uuid::Uuid::new_v4());
    let mut cleanup = CleanupGuard(Some(TargetCleanup {
        runtime: runtime.clone(),
        device: device.clone(),
        tag: tag.clone(),
        original_clipboard: None,
        posted: false,
    }));
    let mut events = runtime.subscribe();
    runtime
        .invoke("devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    let automatic = wait_live(&mut events, &device).await;
    assert_eq!(automatic["wanted"], true);

    let original = runtime
        .invoke(
            "clipboard.get",
            json!({"deviceId":device,"allowStart":false}),
        )
        .await
        .unwrap();
    assert_eq!(
        original["hasText"], true,
        "fixture requires an existing text ClipData so public get/set can restore it exactly"
    );
    let original = original["text"].as_str().unwrap().to_owned();
    let stopped = runtime
        .invoke("observation.stop", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(stopped["phase"], "stopped");
    assert_eq!(stopped["wanted"], false);
    let mut stopped_events = runtime.subscribe();
    let still_owned = runtime
        .invoke(
            "clipboard.get",
            json!({"deviceId":device,"allowStart":false}),
        )
        .await
        .unwrap();
    assert!(
        still_owned["text"].as_str() == Some(original.as_str()),
        "stop changed clipboard content"
    );
    let marker = format!("observation-stop clipboard {}", uuid::Uuid::new_v4());
    cleanup.0.as_mut().unwrap().original_clipboard = Some(original);
    assert_eq!(
        runtime
            .invoke(
                "clipboard.set",
                json!({"deviceId":device,"text":marker,"allowStart":false})
            )
            .await
            .unwrap()["applied"],
        true
    );
    let read = runtime
        .invoke(
            "clipboard.get",
            json!({"deviceId":device,"allowStart":false}),
        )
        .await
        .unwrap();
    assert!(
        read["text"].as_str() == Some(marker.as_str()),
        "shared helper clipboard round trip failed after observation stop"
    );
    cleanup.0.as_mut().unwrap().posted = true;
    adb(&[
        "shell",
        "cmd",
        "notification",
        "post",
        "-t",
        &tag,
        &tag,
        "posted_while_stopped",
    ]);
    assert_stopped(&runtime, &device, &mut stopped_events).await;

    runtime
        .invoke("devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke("device.info", json!({"deviceId":device}))
            .await
            .unwrap()["autoReconnect"],
        false
    );
    assert_stopped(&runtime, &device, &mut stopped_events).await;
    let mut reconnected_events = runtime.subscribe();
    runtime
        .invoke("devices.connect", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_stopped(&runtime, &device, &mut reconnected_events).await;

    let mut resumed_events = runtime.subscribe();
    runtime
        .invoke("observation.start", json!({"deviceId":device}))
        .await
        .unwrap();
    let resumed = wait_live(&mut resumed_events, &device).await;
    assert!(resumed["generation"].as_u64().unwrap() > stopped["generation"].as_u64().unwrap());
    let body = format!("after_explicit_start_{}", uuid::Uuid::new_v4());
    adb(&[
        "shell",
        "cmd",
        "notification",
        "post",
        "-t",
        &tag,
        &tag,
        &body,
    ]);
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            let event = resumed_events.recv().await.unwrap();
            if event["deviceId"] == device
                && event["type"] == "notifications.changed"
                && event["data"]["notifications"]
                    .as_array()
                    .is_some_and(|items| {
                        items.iter().any(|item| {
                            item["title"] == tag
                                && item["body"] == body
                                && item["packageName"] == "com.android.shell"
                        })
                    })
            {
                break;
            }
        }
    })
    .await
    .expect("explicit start re-registers a real listener delivering a newly posted notification");
    cleanup.finish().await;
}
