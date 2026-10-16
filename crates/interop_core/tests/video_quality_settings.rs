use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
async fn unprobed_quality_is_unknown_and_invalid_settings_are_atomic() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let initial = runtime
        .invoke("session.quality.options", json!({}))
        .await
        .unwrap();
    assert_eq!(initial["probe"]["status"], "unknown");
    assert_eq!(initial["current"]["videoCodec"], "h264");
    let codecs = initial["codecs"].as_array().unwrap();
    assert_eq!(codecs.len(), 5);
    assert!(
        codecs
            .iter()
            .all(|codec| codec["status"] == "unknown" && codec["available"] == false)
    );
    for codec in ["h264", "h265", "av1", "vp8", "vp9"] {
        runtime
            .invoke(
                "settings.update",
                json!({"videoCodec":codec,"videoEncoder":null}),
            )
            .await
            .unwrap();
    }
    assert!(
        runtime
            .invoke(
                "settings.update",
                json!({"videoCodec":"h265","videoEncoder":"c2.x; id","maxFps":30})
            )
            .await
            .is_err()
    );
    let after = runtime
        .invoke("session.quality.options", json!({}))
        .await
        .unwrap();
    assert_eq!(after["current"]["videoCodec"], "vp9");
    assert_eq!(after["current"]["maxFps"], 60);
}

#[tokio::test]
async fn per_device_quality_is_isolated_and_not_restored_to_new_identities() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let a = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":15556}))
        .await
        .unwrap();
    let b = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":15558}))
        .await
        .unwrap();
    let a = a["deviceId"].as_str().unwrap();
    let b = b["deviceId"].as_str().unwrap();
    runtime.invoke("settings.update", json!({"deviceQuality":{a:{"videoCodec":"h265","maxSize":720},b:{"videoCodec":"av1","maxSize":1920}}})).await.unwrap();
    let qa = runtime
        .invoke("session.quality.options", json!({"deviceId":a}))
        .await
        .unwrap();
    let qb = runtime
        .invoke("session.quality.options", json!({"deviceId":b}))
        .await
        .unwrap();
    assert_eq!(qa["current"]["videoCodec"], "h265");
    assert_eq!(qb["current"]["videoCodec"], "av1");
    assert_eq!(qa["probe"]["status"], "unknown");
    assert_eq!(qb["probe"]["status"], "unknown");
    assert!(
        runtime
            .invoke(
                "settings.update",
                json!({"deviceQuality":{a:{"videoCodec":"h264","maxFps":0}}})
            )
            .await
            .is_err()
    );
    let metadata = runtime.invoke("settings.export", json!({})).await.unwrap();
    runtime.invoke("settings.import", metadata).await.unwrap();
    let exported = runtime.invoke("settings.export", json!({})).await.unwrap();
    assert_eq!(exported["metadata"]["settings"]["deviceQuality"], json!({}));
    assert_eq!(exported["metadata"]["settings"]["videoCodec"], "h264");
}
