use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};

async fn runtime() -> (tempfile::TempDir, Arc<Runtime>, String) {
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
    let id = device["deviceId"].as_str().unwrap().to_owned();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    (root, runtime, id)
}
fn adb(args: &[&str]) -> String {
    let binary = std::env::var("ANDROID_ADB").expect("ANDROID_ADB is a test harness only");
    let serial = std::env::var("ANDROID_TARGET_SERIAL").expect("ANDROID_TARGET_SERIAL");
    assert!(
        serial.starts_with("emulator-"),
        "this synthetic-notification/call harness is for an explicit AVD"
    );
    let result = std::process::Command::new(binary)
        .args(["-s", &serial])
        .args(args)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "official test harness command failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    String::from_utf8_lossy(&result.stdout).into_owned()
}
struct ModemCleanup;
impl Drop for ModemCleanup {
    fn drop(&mut self) {
        let (Ok(binary), Ok(serial)) = (
            std::env::var("ANDROID_ADB"),
            std::env::var("ANDROID_TARGET_SERIAL"),
        ) else {
            return;
        };
        for number in ["5550101234", "5550101235"] {
            let _ = std::process::Command::new(&binary)
                .args(["-s", &serial, "emu", "gsm", "cancel", number])
                .output();
        }
        let _ = std::process::Command::new(binary)
            .args([
                "-s",
                &serial,
                "shell",
                "input",
                "keyevent",
                "KEYCODE_ENDCALL",
            ])
            .output();
    }
}
async fn wait_modem_state(state: u8) {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let dump = adb(&["shell", "dumpsys", "telephony.registry"]);
            let modem_matches = dump
                .lines()
                .any(|line| line.trim() == format!("mCallState={state}"));
            let telecom_idle = state != 0
                || adb(&["shell", "dumpsys", "telecom"])
                    .split_once("  mCalls:")
                    .and_then(|(_, calls)| calls.split_once("  mCallAudioManager:"))
                    .is_some_and(|(calls, _)| calls.trim().is_empty());
            if modem_matches && telecom_idle {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .expect("official harness observes actual virtual modem state");
}
async fn wait_call(runtime: &Arc<Runtime>, id: &str, state: &str) -> Option<Value> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let result = runtime
                .invoke("calls.list", json!({"deviceId":id}))
                .await
                .unwrap();
            let calls = result["calls"].as_array().unwrap();
            if state == "idle" && calls.is_empty() {
                return None;
            }
            if let Some(call) = calls.first().filter(|call| call["state"] == state) {
                return Some(call.clone());
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .expect("actual modem call state")
}

#[tokio::test]
#[ignore = "requires an actual Android endpoint and explicit official-adb AVD test harness"]
async fn rust_runtime_receives_live_notifications_rejects_old_actions_and_clears_target() {
    let (_root, runtime, id) = runtime().await;
    let mut events = runtime.subscribe();
    let snapshot = runtime
        .invoke("notifications.list", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(snapshot["status"], "available", "{snapshot}");
    assert_eq!(snapshot["live"], true);
    let tag = format!("interop-notification-{}", uuid::Uuid::new_v4());
    adb(&[
        "shell",
        "cmd",
        "notification",
        "post",
        "-t",
        &tag,
        &tag,
        "first_fixture_body",
    ]);
    let first = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let event = events.recv().await.unwrap();
            if event["type"] == "notifications.changed"
                && let Some(item) = event["data"]["notifications"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|item| item["title"] == tag)
            {
                return item.clone();
            }
        }
    })
    .await
    .expect("real Binder event through Rust");
    assert_eq!(first["body"], "first_fixture_body");
    adb(&[
        "shell",
        "cmd",
        "notification",
        "post",
        "-t",
        &tag,
        &tag,
        "updated_fixture_body",
    ]);
    let current = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let snapshot = runtime
                .invoke("notifications.list", json!({"deviceId":id}))
                .await
                .unwrap();
            if let Some(item) = snapshot["notifications"]
                .as_array()
                .unwrap()
                .iter()
                .find(|item| item["title"] == tag && item["body"] == "updated_fixture_body")
            {
                return item.clone();
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap();
    assert_ne!(first["id"], current["id"]);
    assert_eq!(
        runtime
            .invoke(
                "notifications.dismiss",
                json!({"deviceId":id,"notificationId":first["id"]})
            )
            .await
            .unwrap_err()
            .code,
        "notification_expired"
    );
    let dismissed = runtime
        .invoke(
            "notifications.dismiss",
            json!({"deviceId":id,"notificationId":current["id"]}),
        )
        .await
        .unwrap();
    assert_eq!(dismissed["acceptedBySystem"], true);
    assert_eq!(dismissed["markedRead"], false);
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = runtime
                .invoke("notifications.list", json!({"deviceId":id}))
                .await
                .unwrap();
            if !snapshot["notifications"]
                .as_array()
                .unwrap()
                .iter()
                .any(|item| item["title"] == tag)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke("notifications.list", json!({"deviceId":id}))
            .await
            .unwrap_err()
            .code,
        "disconnected"
    );
}

#[tokio::test]
#[ignore = "creates synthetic virtual-modem calls on the explicit target AVD; never use with an existing call"]
async fn rust_runtime_observes_rapid_replacement_and_refuses_unsafe_aggregate_actions() {
    let (_root, runtime, id) = runtime().await;
    let initial = runtime
        .invoke("calls.list", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(initial["live"], true);
    assert_eq!(initial["controlStatus"], "limited");
    assert_eq!(initial["audioStatus"], "unknown");
    assert!(
        initial["calls"].as_array().unwrap().is_empty(),
        "do not alter an existing call"
    );
    let _cleanup = ModemCleanup;
    adb(&["emu", "gsm", "call", "5550101234"]);
    let first = wait_call(&runtime, &id, "ringing").await.unwrap();
    assert_eq!(first["deviceId"], id);
    assert!(
        first["generation"]
            .as_u64()
            .is_some_and(|generation| generation > 0),
        "raw call-state callbacks are decoded"
    );
    for capability in ["canAnswer", "canReject", "canHangup"] {
        assert_eq!(first[capability], false);
    }
    for action in ["answer", "reject", "hangup"] {
        assert_eq!(
            runtime
                .invoke(
                    "calls.action",
                    json!({"deviceId":id,"callId":first["id"],"action":action})
                )
                .await
                .unwrap_err()
                .code,
            "call_targeting_unavailable"
        );
    }
    assert_eq!(
        wait_call(&runtime, &id, "ringing").await.unwrap()["id"],
        first["id"]
    );
    // Do not issue a Rust refresh in the gap. Wait only through the official
    // harness until the modem accepted cancellation: this AVD can otherwise
    // report OK for the new call while Telecom rejects its creation.
    adb(&["emu", "gsm", "cancel", "5550101234"]);
    wait_modem_state(0).await;
    adb(&["emu", "gsm", "call", "5550101235"]);
    wait_modem_state(1).await;
    wait_call(&runtime, &id, "ringing").await.unwrap();
    // The aggregate registry may itself omit the idle transition. An unchanged
    // observation ID is permitted; it must never authorize a global action.
    assert_eq!(
        runtime
            .invoke(
                "calls.action",
                json!({"deviceId":id,"callId":first["id"],"action":"reject"})
            )
            .await
            .unwrap_err()
            .code,
        "call_targeting_unavailable"
    );
    assert_eq!(
        wait_call(&runtime, &id, "ringing").await.unwrap()["state"],
        "ringing",
        "old action must not end the observed replacement call"
    );
    adb(&["emu", "gsm", "cancel", "5550101235"]);
    adb(&["emu", "gsm", "cancel", "5550101234"]);
    adb(&["shell", "input", "keyevent", "KEYCODE_ENDCALL"]);
    wait_call(&runtime, &id, "idle").await;
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

#[tokio::test]
#[ignore = "requires an actual Android endpoint"]
async fn disconnect_cancels_companion_startup_instead_of_reviving_it() {
    let (_root, runtime, id) = runtime().await;
    let mut events = runtime.subscribe();
    let owner = runtime.clone();
    let device = id.clone();
    let startup = tokio::spawn(async move {
        owner
            .invoke("notifications.list", json!({"deviceId":device}))
            .await
    });
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if events.recv().await.unwrap()["type"] == "companion.starting" {
                break;
            }
        }
    })
    .await
    .unwrap();
    tokio::time::timeout(
        Duration::from_secs(7),
        runtime.invoke("devices.disconnect", json!({"deviceId":id})),
    )
    .await
    .expect("stop cancels startup before waiting on its lock")
    .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_secs(2), startup)
            .await
            .unwrap()
            .unwrap()
            .is_err()
    );
    assert_eq!(
        runtime
            .invoke("device.info", json!({"deviceId":id}))
            .await
            .unwrap()["status"],
        "offline"
    );
}
