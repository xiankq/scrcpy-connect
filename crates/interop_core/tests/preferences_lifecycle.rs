use interop_core::Runtime;
use serde_json::json;

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
    let target = tempfile::tempdir().unwrap();
    let restored = Runtime::initialize(target.path()).await.unwrap();
    let receipt = restored.invoke("settings.import", exported).await.unwrap();
    assert_eq!(receipt["authorizationRestored"], false);
    let list = restored.invoke("devices.list", json!({})).await.unwrap();
    let device = &list["devices"][0];
    assert_eq!(device["transport"], "tls");
    assert_eq!(device["status"], "unauthorized");
    assert_eq!(device["autoReconnect"], false);
    assert_ne!(device["id"], added["deviceId"]);
    drop(restored);
    let reopened = Runtime::initialize(target.path()).await.unwrap();
    assert_eq!(
        reopened.invoke("devices.list", json!({})).await.unwrap()["devices"][0]["transport"],
        "tls"
    );
}

#[tokio::test]
async fn export_contains_metadata_only_and_restore_never_transfers_trust() {
    let source = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(source.path()).await.unwrap();
    runtime
        .invoke(
            "devices.add",
            json!({"address":"192.0.2.10","port":5555,"name":"我的手机"}),
        )
        .await
        .unwrap();
    let exported = runtime.invoke("settings.export", json!({})).await.unwrap();
    let text = exported.to_string();
    assert!(!text.contains("PRIVATE KEY"));
    assert!(!text.contains("identityFingerprint"));
    assert!(!text.contains("autoReconnect"));
    let target = tempfile::tempdir().unwrap();
    let restored = Runtime::initialize(target.path()).await.unwrap();
    restored.invoke("settings.import", exported).await.unwrap();
    let list = restored.invoke("devices.list", json!({})).await.unwrap();
    assert_eq!(list["devices"].as_array().unwrap().len(), 1);
    assert_eq!(list["devices"][0]["status"], "unauthorized");
    assert_eq!(list["devices"][0]["autoReconnect"], false);
    assert!(list["devices"][0]["guid"].is_null());
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

#[tokio::test]
async fn system_alert_preferences_persist_separately_from_observation_and_background() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let initial = runtime.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(initial["notificationAlerts"], true);
    assert_eq!(initial["callAlerts"], true);
    let updated = runtime
        .invoke(
            "settings.update",
            json!({"notificationAlerts":false,"callAlerts":false}),
        )
        .await
        .unwrap();
    assert_eq!(
        updated["backgroundKeepAlive"],
        initial["backgroundKeepAlive"]
    );
    assert!(
        runtime
            .invoke(
                "settings.update",
                json!({"notificationAlerts":true,"callAlerts":"false"})
            )
            .await
            .is_err()
    );
    assert_eq!(
        runtime.invoke("settings.get", json!({})).await.unwrap(),
        updated
    );
    drop(runtime);
    let reopened = Runtime::initialize(directory.path()).await.unwrap();
    let persisted = reopened.invoke("settings.get", json!({})).await.unwrap();
    assert_eq!(persisted["notificationAlerts"], false);
    assert_eq!(persisted["callAlerts"], false);
}
