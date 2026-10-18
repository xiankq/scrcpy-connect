use crate::{
    CoreError, CoreResult, Runtime,
    model::{Device, TransportKind, required},
};
use serde_json::{Value, json};
use std::sync::Arc;

pub(crate) fn defaults() -> Value {
    json!({"appearance":"light",
        "backgroundConnection":true,"backgroundKeepAlive":true,
        "notificationAlerts":true,"callAlerts":true,"adbBurstMode":false,
        "deviceSettings":{},
        "qualityPreset":"balanced","maxSize":1280,"maxFps":60,"videoBitRate":8_000_000,"videoCodec":"h264","videoEncoder":null,"deviceQuality":{}})
}

const REMOVED_SETTINGS: [&str; 10] = [
    "backgroundAudio",
    "reduceTransparency",
    "reduceMotion",
    "audioMode",
    "audioDevices",
    "clipboardEnabled",
    "clipboardTarget",
    "clipboardSync",
    "clipboardMode",
    "clipboardDevice",
];

/// Retired global source choices must not survive restart or metadata restore.
pub(crate) fn remove_retired_settings(settings: &mut Value) {
    if let Some(settings) = settings.as_object_mut() {
        for key in REMOVED_SETTINGS {
            settings.remove(key);
        }
    }
}

pub(crate) const QUALITY_KEYS: [&str; 6] = [
    "qualityPreset",
    "maxSize",
    "maxFps",
    "videoBitRate",
    "videoCodec",
    "videoEncoder",
];

pub(crate) fn quality_settings(settings: &Value, device: Option<&str>) -> Value {
    let mut result = defaults();
    for key in QUALITY_KEYS {
        if let Some(value) = settings.get(key) {
            result[key] = value.clone();
        }
    }
    if let Some(overrides) = device
        .and_then(|id| settings["deviceQuality"].get(id))
        .and_then(Value::as_object)
    {
        for (key, value) in overrides {
            result[key] = value.clone();
        }
    }
    result
}

pub(crate) fn valid_encoder(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

fn quality_value(key: &str, value: &Value) -> bool {
    match key {
        "qualityPreset" => matches!(value.as_str(), Some("smooth" | "balanced" | "clear")),
        "videoCodec" => matches!(
            value.as_str(),
            Some("h264" | "h265" | "av1" | "vp8" | "vp9")
        ),
        "videoEncoder" => value.is_null() || value.as_str().is_some_and(valid_encoder),
        "maxSize" => value.as_u64().is_some_and(|n| (320..=4096).contains(&n)),
        "maxFps" => value.as_u64().is_some_and(|n| (1..=120).contains(&n)),
        "videoBitRate" => value
            .as_u64()
            .is_some_and(|n| (500_000..=50_000_000).contains(&n)),
        _ => false,
    }
}

pub(crate) fn validate_quality(values: &Value) -> CoreResult<()> {
    let object = values
        .as_object()
        .ok_or_else(|| CoreError::new("invalid_argument", "画质设置必须是对象。"))?;
    if object.iter().any(|(key, value)| !quality_value(key, value)) {
        return Err(CoreError::new("invalid_argument", "画质设置包含无效值。"));
    }
    Ok(())
}

fn validated_settings(current: &Value, changes: &Value) -> CoreResult<Value> {
    let values = changes
        .as_object()
        .ok_or_else(|| CoreError::new("invalid_argument", "设置必须是对象。"))?;
    let mut next = current.clone();
    for (key, value) in values {
        let valid = match key.as_str() {
            "appearance" => matches!(value.as_str(), Some("light" | "dark" | "system")),
            "backgroundConnection"
            | "backgroundKeepAlive"
            | "notificationAlerts"
            | "callAlerts"
            | "adbBurstMode" => value.is_boolean(),
            "deviceSettings" => value.as_object().is_some_and(|map| {
                map.len() <= 256
                    && map.iter().all(|(id, settings)| {
                        uuid::Uuid::parse_str(id).is_ok()
                            && settings.as_object().is_some_and(|settings| {
                                settings.iter().all(|(key, value)| {
                                    matches!(key.as_str(), "clipboardSync" | "showNavigationBar")
                                        && value.is_boolean()
                                })
                            })
                    })
            }),
            "qualityPreset" | "videoCodec" | "videoEncoder" | "maxSize" | "maxFps"
            | "videoBitRate" => quality_value(key, value),
            "deviceQuality" => value.as_object().is_some_and(|map| {
                map.len() <= 256
                    && map.iter().all(|(id, quality)| {
                        uuid::Uuid::parse_str(id).is_ok() && validate_quality(quality).is_ok()
                    })
            }),
            _ => false,
        };
        if !valid {
            return Err(CoreError::new(
                "invalid_argument",
                format!("设置值无效：{key}"),
            ));
        }
        next[key] = value.clone();
    }
    Ok(next)
}

impl Runtime {
    pub(crate) async fn preferences(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        match command {
            "settings.update" => {
                let mut store = self.store.write().await;
                store.settings = validated_settings(&store.settings, params)?;
                drop(store);
                self.persist().await?;
                // Persistence may wait behind another writer. Publish while
                // holding a fresh read guard so a late receipt cannot regress
                // a newer in-memory state already observed by a snapshot.
                let store = self.store.read().await;
                let result = store.settings.clone();
                self.emit("settings.changed", None, result.clone());
                Ok(result)
            }
            "settings.export" => {
                let store = self.store.read().await;
                let devices: Vec<Value> = store.devices.iter().map(|d| json!({
                    "name":d.name,"address":d.address,"port":d.port,"transport":d.transport,
                    "guid":d.guid,"serial":d.serial,"model":d.model,"androidVersion":d.android_version,"apiLevel":d.api_level
                })).collect();
                Ok(
                    json!({"metadata":{"format":"scrcpy-connect-metadata","version":1,"devices":devices,"settings":store.settings}}),
                )
            }
            "settings.import" => {
                let metadata = &params["metadata"];
                if metadata["format"] != "scrcpy-connect-metadata" || metadata["version"] != 1 {
                    return Err(CoreError::new(
                        "invalid_data",
                        "设备记录格式或版本不受支持。",
                    ));
                }
                let entries = metadata["devices"]
                    .as_array()
                    .filter(|a| a.len() <= 256)
                    .ok_or_else(|| CoreError::new("invalid_data", "设备列表无效或过长。"))?;
                let mut imported_settings = metadata["settings"].clone();
                remove_retired_settings(&mut imported_settings);
                let mut settings = validated_settings(&defaults(), &imported_settings)?;
                // Restored devices receive new identities; old per-device quality keys
                // must not silently attach to a different authorization record.
                settings["deviceQuality"] = json!({});
                settings["deviceSettings"] = json!({});
                let mut restored = Vec::new();
                for entry in entries {
                    let transport = TransportKind::parse(required(entry, "transport")?)
                        .ok_or_else(|| {
                            CoreError::new("invalid_data", "设备记录中的连接方式无效。")
                        })?;
                    let name = required(entry, "name")?;
                    let address = entry["address"].as_str().unwrap_or("");
                    let port = entry["port"]
                        .as_u64()
                        .and_then(|n| u16::try_from(n).ok())
                        .ok_or_else(|| CoreError::new("invalid_port", "记录的连接端口无效。"))?;
                    if name.chars().count() > 80
                        || address.len() > 253
                        || address.contains('\0')
                        || address.chars().any(char::is_whitespace)
                        || address.contains('/')
                        || address.contains('\\')
                        || (matches!(transport, TransportKind::Tcp)
                            && (address.is_empty() || port == 0))
                    {
                        return Err(CoreError::new("invalid_data", "设备名称或地址无效。"));
                    }
                    restored.push(Device {
                        id: uuid::Uuid::new_v4().to_string(),
                        name: name.into(),
                        address: address.into(),
                        port,
                        guid: None,
                        serial: None,
                        transport,
                        status: "unauthorized".into(),
                        model: None,
                        android_version: None,
                        api_level: None,
                        battery: None,
                        last_seen: None,
                        reason: Some("此记录来自恢复，请在被控手机重新核验授权。".into()),
                        auto_reconnect: false,
                        observation_wanted: true,
                    });
                }
                let count = restored.len();
                let mut store = self.store.write().await;
                // A restored endpoint never merges into or overwrites an authenticated live identity.
                store.devices.extend(restored);
                store.settings = settings;
                drop(store);
                self.persist().await?;
                self.emit("devices.changed", None, json!({"restored":count}));
                Ok(json!({"restored":count,"authorizationRestored":false}))
            }
            "system.info" => Ok(
                json!({"version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,
                "architecture":std::env::consts::ARCH,"adbImplementation":"Rust independent host",
                "scrcpyVersion":"5.0.1","identityMigration":false,"wirelessCryptoStatus":"experimental-rustcrypto"}),
            ),
            _ => Err(CoreError::new("unknown_command", "未知设置操作。")),
        }
    }

    pub(crate) async fn cancel_device_operation(&self, params: &Value) -> CoreResult<Value> {
        let id = params["attemptId"]
            .as_str()
            .or_else(|| params["deviceId"].as_str())
            .ok_or_else(|| CoreError::new("invalid_argument", "缺少连接或配对标识。"))?;
        if let Some(token) = self.device_operations.lock().await.remove(id) {
            token.cancel();
        }
        let mut qr = self.qr_attempt.lock().await;
        if qr.as_ref().is_some_and(|(attempt, _)| attempt == id)
            && let Some((_, token)) = qr.take()
        {
            token.cancel();
        }
        drop(qr);
        if let Some(device) = self
            .store
            .write()
            .await
            .devices
            .iter_mut()
            .find(|d| d.id == id)
        {
            if matches!(device.status.as_str(), "connecting" | "authorizing") {
                device.status = "offline".into();
            }
            device.auto_reconnect = false;
        }
        self.persist().await?;
        Ok(json!({"cancelled":true}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn device_preferences_accept_only_boolean_device_scoped_controls() {
        let id = uuid::Uuid::new_v4().to_string();
        let settings = validated_settings(
            &defaults(),
            &json!({"deviceSettings":{
                id.clone(): {"clipboardSync":true,"showNavigationBar":false}
            }}),
        )
        .unwrap();
        assert_eq!(settings["deviceSettings"][&id]["clipboardSync"], true);
        assert_eq!(settings["deviceSettings"][&id]["showNavigationBar"], false);
        for invalid in [
            json!({"deviceSettings":{"not-an-identity":{"clipboardSync":true}}}),
            json!({"deviceSettings":{id.clone():{"clipboardSync":"yes"}}}),
            json!({"deviceSettings":{id.clone():{"audioMode":"fixed"}}}),
            json!({"clipboardSync":true}),
            json!({"audioDevices":[]}),
            json!({"backgroundAudio":true}),
        ] {
            assert!(validated_settings(&defaults(), &invalid).is_err());
        }
    }

    #[test]
    fn retiring_global_choices_preserves_explicit_device_settings() {
        let mut settings = json!({
            "audioMode":"fixed", "audioDevices":["a"], "backgroundAudio":true,
            "clipboardSync":true, "clipboardMode":"fixed", "clipboardDevice":"a",
            "reduceMotion":true, "reduceTransparency":true,
            "deviceSettings":{"a":{"clipboardSync":false,"showNavigationBar":true}},
            "appearance":"dark"
        });
        remove_retired_settings(&mut settings);
        assert_eq!(
            settings,
            json!({
                "deviceSettings":{"a":{"clipboardSync":false,"showNavigationBar":true}},
                "appearance":"dark"
            })
        );
    }

    #[tokio::test]
    async fn restored_device_identities_do_not_inherit_clipboard_or_navigation_preferences() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        let result = runtime.invoke("settings.import", json!({"metadata":{
            "format":"scrcpy-connect-metadata","version":1,
            "devices":[{"name":"Phone","address":"phone.local","port":5555,"transport":"tcp"}],
            "settings":{"deviceSettings":{id:{"clipboardSync":true,"showNavigationBar":false}},
                "audioMode":"fixed","audioDevices":[],"clipboardMode":"fixed","clipboardSync":true}
        }})).await.unwrap();
        assert_eq!(result["restored"], 1);
        let settings = runtime.invoke("settings.get", Value::Null).await.unwrap();
        assert_eq!(settings["deviceSettings"], json!({}));
        assert!(settings.get("clipboardSync").is_none());
        assert!(settings.get("audioDevices").is_none());
    }
    #[test]
    fn invalid_patch_never_partially_changes_settings() {
        let original = defaults();
        assert!(validated_settings(&original, &json!({"appearance":"dark","maxFps":0})).is_err());
        assert_eq!(original["appearance"], "light");
        assert!(validated_settings(&original, &json!({"backgroundKeepAlive":"yes"})).is_err());
    }

    #[tokio::test]
    async fn a_delayed_persistence_receipt_cannot_publish_old_settings_after_a_snapshot() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let mut events = runtime.subscribe();
        let barrier = runtime.persistence.lock().await;
        let update = |appearance: &'static str| {
            let runtime = runtime.clone();
            tokio::spawn(async move {
                runtime
                    .invoke("settings.update", json!({"appearance":appearance}))
                    .await
                    .unwrap()
            })
        };
        let first = update("dark");
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            while runtime.invoke("settings.get", Value::Null).await.unwrap()["appearance"] != "dark"
            {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        let second = update("system");
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            while runtime.invoke("settings.get", Value::Null).await.unwrap()["appearance"]
                != "system"
            {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        let snapshot = runtime.invoke("state.snapshot", Value::Null).await.unwrap();
        assert_eq!(snapshot["settings"]["appearance"], "system");
        drop(barrier);
        first.await.unwrap();
        second.await.unwrap();
        for _ in 0..2 {
            let event = events.recv().await.unwrap();
            assert!(event["sequence"].as_u64().unwrap() > snapshot["sequence"].as_u64().unwrap());
            assert_eq!(
                event["data"]["appearance"], "system",
                "A late event must project the current committed in-memory state"
            );
        }
    }
}
