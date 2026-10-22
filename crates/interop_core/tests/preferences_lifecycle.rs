use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn caller_defaults_fill_missing_keys_and_preserve_explicit_choices() {
    let directory = tempfile::tempdir().unwrap();
    let empty = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        empty.invoke("settings.get", json!({})).await.unwrap(),
        json!({})
    );
    empty
        .invoke("settings.update", json!({"appearance":"dark","maxFps":24}))
        .await
        .unwrap();
    drop(empty);
    let configured = Runtime::initialize_with_settings(
        directory.path(),
        interop_core::ConnectionPolicy::standalone(),
        json!({"appearance":"light","maxFps":60,"notificationAlerts":false}),
    )
    .await
    .unwrap();
    let settings = configured.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(
        settings,
        json!({"appearance":"dark","maxFps":24,"notificationAlerts":false})
    );
    assert!(
        settings.get("qualityPreset").is_none(),
        "native must not invent product defaults"
    );
    configured.invoke("settings.import", json!({"metadata":{
        "format":"scrcpy-connect-metadata","version":1,"devices":[],"settings":{"appearance":"system"}
    }})).await.unwrap();
    let restored = configured.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(restored["appearance"], "system");
    assert_eq!(restored["maxFps"], 60);
    assert_eq!(restored["notificationAlerts"], false);
}

#[tokio::test]
async fn file_browser_preferences_survive_runtime_restart() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize_with_settings(
        directory.path(),
        interop_core::ConnectionPolicy::standalone(),
        json!({
            "fileViewMode":"grid",
            "fileSortKey":"name",
            "fileSortAscending":true
        }),
    )
    .await
    .unwrap();
    runtime
        .invoke(
            "settings.update",
            json!({
                "fileViewMode":"list",
                "fileSortKey":"modified",
                "fileSortAscending":false
            }),
        )
        .await
        .unwrap();
    drop(runtime);

    let reopened = Runtime::initialize_with_settings(
        directory.path(),
        interop_core::ConnectionPolicy::standalone(),
        json!({
            "fileViewMode":"grid",
            "fileSortKey":"name",
            "fileSortAscending":true
        }),
    )
    .await
    .unwrap();
    let settings = reopened
        .invoke("settings.get", json!({}))
        .await
        .unwrap();
    assert_eq!(settings["fileViewMode"], "list");
    assert_eq!(settings["fileSortKey"], "modified");
    assert_eq!(settings["fileSortAscending"], false);
}

#[tokio::test]
async fn version_one_store_migrates_only_the_old_network_default_signature() {
    let directory = tempfile::tempdir().unwrap();
    tokio::fs::write(
        directory.path().join("devices.json"),
        serde_json::to_vec(&json!({
            "version":1,
            "identityFingerprint":"old",
            "devices":[],
            "settings":{
                "appearance":"dark",
                "adbBurstMode":false,
                "qualityPreset":"balanced",
                "maxSize":1280,
                "maxFps":60,
                "videoBitRate":8000000,
                "videoCodec":"h264",
                "videoEncoder":null,
                "deviceQuality":{
                    "old":{"qualityPreset":"balanced","maxSize":1280,"maxFps":60,"videoBitRate":8000000},
                    "custom":{"qualityPreset":"balanced","maxSize":1920,"maxFps":60,"videoBitRate":8000000}
                }
            }
        }))
        .unwrap(),
    )
    .await
    .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let settings = runtime.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(settings["appearance"], "dark");
    assert_eq!(settings["adbBurstMode"], true);
    assert_eq!(settings["videoBitRate"], 4000000);
    assert_eq!(settings["deviceQuality"]["old"]["videoBitRate"], 4000000);
    assert_eq!(settings["deviceQuality"]["custom"]["videoBitRate"], 8000000);
}

#[tokio::test]
async fn version_two_store_preserves_explicit_burst_and_bitrate_choices() {
    let directory = tempfile::tempdir().unwrap();
    tokio::fs::write(
        directory.path().join("devices.json"),
        serde_json::to_vec(&json!({
            "version":2,
            "identityFingerprint":"old",
            "devices":[],
            "settings":{
                "adbBurstMode":false,
                "qualityPreset":"balanced",
                "maxSize":1280,
                "maxFps":60,
                "videoBitRate":8000000
            }
        }))
        .unwrap(),
    )
    .await
    .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let settings = runtime.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(settings["adbBurstMode"], false);
    assert_eq!(settings["videoBitRate"], 8000000);
}

#[tokio::test]
async fn own_tls_export_restores_transport_without_restoring_authorization() {
    let source = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(source.path()).await.unwrap();
    let added = runtime
        .invoke(
            "devices.add",
            json!({"address":"192.0.2.10","port":37123,"transport":"tls","name":"TLS 手机"}),
        )
        .await
        .unwrap();
    let exported = runtime.invoke("settings.export", json!({})).await.unwrap();
    assert_eq!(exported["metadata"]["devices"][0]["transport"], "tls");
    let text = exported.to_string();
    assert!(!text.contains("PRIVATE KEY"));
    assert!(!text.contains("identityFingerprint"));
    assert!(!text.contains("autoReconnect"));
    let target = tempfile::tempdir().unwrap();
    let restored = Runtime::initialize(target.path()).await.unwrap();
    let receipt = restored.invoke("settings.import", exported).await.unwrap();
    assert_eq!(receipt["authorizationRestored"], false);
    let list = restored.invoke("devices.list", json!({})).await.unwrap();
    assert_eq!(list["devices"].as_array().unwrap().len(), 1);
    let device = &list["devices"][0];
    assert_eq!(device["transport"], "tls");
    assert_eq!(device["status"], "unauthorized");
    assert_eq!(device["autoReconnect"], false);
    assert!(device["guid"].is_null());
    assert_ne!(device["id"], added["deviceId"]);
    drop(restored);
    let reopened = Runtime::initialize(target.path()).await.unwrap();
    assert_eq!(
        reopened.invoke("devices.list", json!({})).await.unwrap()["devices"][0]["transport"],
        "tls"
    );
}

#[tokio::test]
async fn malformed_import_or_settings_patch_has_no_partial_effect() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let settings = runtime.invoke("settings.get", json!({})).await.unwrap();
    assert!(
        runtime
            .invoke(
                "settings.update",
                json!({"appearance":"dark","backgroundKeepAlive":"true"})
            )
            .await
            .is_err()
    );
    assert_eq!(
        runtime.invoke("settings.get", json!({})).await.unwrap(),
        settings
    );
    assert!(runtime.invoke("settings.import",json!({"metadata":{"format":"scrcpy-connect-metadata","version":1,
        "settings":settings,"devices":[{"name":"a","address":"192.0.2.1","port":5555,"transport":"tcp"},{"name":"b","address":"invalid path","port":5555,"transport":"tcp"}]}})).await.is_err());
    assert_eq!(
        runtime.invoke("devices.list", json!({})).await.unwrap()["devices"],
        json!([])
    );
}

#[tokio::test]
async fn usb_and_pending_wireless_metadata_restore_without_network_endpoints_or_trust() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke(
            "settings.import",
            json!({"metadata":{"format":"scrcpy-connect-metadata","version":1,
        "settings":{},"devices":[{"name":"USB 手机","address":"","port":0,"transport":"usb"},
        {"name":"待连接手机","address":"192.0.2.8","port":0,"transport":"wireless"}]}}),
        )
        .await
        .unwrap();
    let list = runtime.invoke("devices.list", json!({})).await.unwrap();
    assert_eq!(list["devices"].as_array().unwrap().len(), 2);
    for device in list["devices"].as_array().unwrap() {
        assert_eq!(device["status"], "unauthorized");
        assert_eq!(device["autoReconnect"], false);
    }
}
