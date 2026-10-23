use crate::{
    CoreError, CoreResult, Runtime,
    model::{Device, TransportKind, required},
};
use serde_json::{Value, json};
use std::sync::Arc;

pub(crate) const QUALITY_KEYS: [&str; 6] = [
    "qualityPreset",
    "maxSize",
    "maxFps",
    "videoBitRate",
    "videoCodec",
    "videoEncoder",
];

pub(crate) fn valid_encoder(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

fn quality_value(key: &str, value: &Value) -> bool {
    match key {
        "qualityPreset" => {
            value.is_null()
                || value
                    .as_str()
                    .is_some_and(|v| !v.is_empty() && v.len() <= 64)
        }
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

/// Defensive validation at the native execution boundary. Product preference
/// defaults, retired fields, migration and persistence belong to Dart.
pub(crate) fn validated_execution_settings(current: &Value, changes: &Value) -> CoreResult<Value> {
    let values = changes
        .as_object()
        .ok_or_else(|| CoreError::new("invalid_argument", "执行配置必须是对象。"))?;
    let mut next = current.as_object().cloned().unwrap_or_default();
    for (key, value) in values {
        let valid = match key.as_str() {
            "adbBurstMode" => value.is_boolean(),
            "deviceQuality" => value.as_object().is_some_and(|map| {
                map.len() <= 256
                    && map.iter().all(|(id, quality)| {
                        uuid::Uuid::parse_str(id).is_ok() && validate_quality(quality).is_ok()
                    })
            }),
            "deviceSettings" => value.as_object().is_some_and(|map| {
                map.len() <= 256
                    && map.iter().all(|(id, settings)| {
                        uuid::Uuid::parse_str(id).is_ok()
                            && settings.as_object().is_some_and(|settings| {
                                settings
                                    .iter()
                                    .all(|(key, value)| key == "stayAwake" && value.is_boolean())
                            })
                    })
            }),
            _ => quality_value(key, value),
        };
        if !valid {
            return Err(CoreError::new(
                "invalid_argument",
                format!("执行配置无效：{key}"),
            ));
        }
        next.insert(key.clone(), value.clone());
    }
    Ok(Value::Object(next))
}

fn changed_keep_active_devices(previous: &Value, next: &Value) -> Vec<String> {
    let mut devices = std::collections::BTreeSet::new();
    for settings in [previous, next] {
        if let Some(map) = settings["deviceSettings"].as_object() {
            devices.extend(map.keys().cloned());
        }
    }
    devices
        .into_iter()
        .filter(|device| {
            previous["deviceSettings"][device]["stayAwake"]
                .as_bool()
                .unwrap_or(false)
                != next["deviceSettings"][device]["stayAwake"]
                    .as_bool()
                    .unwrap_or(false)
        })
        .collect()
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
                let previous = store.settings.clone();
                store.settings = validated_execution_settings(&store.settings, params)?;
                let affected = changed_keep_active_devices(&previous, &store.settings);
                drop(store);
                // This is an execution mirror, not the product preference store.
                // Dart commits preferences before projecting them here.
                // Read the current mirror again before emitting a receipt.
                let store = self.store.read().await;
                let result = store.settings.clone();
                self.emit("settings.changed", None, result.clone());
                drop(store);
                Box::pin(self.sync_changed_keep_active(affected)).await?;
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
                        charging: None,
                        battery_updated_at: None,
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
                drop(store);
                self.persist().await?;
                self.emit("devices.changed", None, json!({"restored":count}));
                Ok(json!({"restored":count,"authorizationRestored":false}))
            }
            "system.info" => Ok(
                json!({"version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,
                "architecture":std::env::consts::ARCH,"adbImplementation":if self.connection_policy.adb_server.is_some(){"official platform-tools"}else{"Rust mobile host"},
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
        self.setup_operations.release_alias(id).await;
        if let Some(token) = self.device_operations.lock().await.remove(id) {
            token.cancel();
        }
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
pub(crate) fn defaults() -> Value {
    json!({"adbBurstMode":true,"deviceSettings":{},"qualityPreset":"balanced",
        "maxSize":1280,"maxFps":60,"videoBitRate":4_000_000,"videoCodec":"h264",
        "videoEncoder":null,"deviceQuality":{}})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn product_values_and_secrets_cannot_enter_execution_mirror() {
        for value in [
            json!({"appearance":"dark"}),
            json!({"privateKeyPem":"secret"}),
            json!({"deviceSettings":{"f6c1fc23-3943-49ce-b5ca-b774be89b61a":{"clipboardSync":true}}}),
        ] {
            assert!(validated_execution_settings(&json!({}), &value).is_err());
        }
        assert!(validated_execution_settings(&json!({}), &json!({"maxFps":0})).is_err());
        assert_eq!(
            validated_execution_settings(&json!({}), &json!({"adbBurstMode":true})).unwrap(),
            json!({"adbBurstMode":true})
        );
    }
    #[tokio::test]
    async fn mirror_update_does_not_write_product_preferences_or_device_records() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let path = directory.path().join("devices.json");
        let before = tokio::fs::read(&path).await.unwrap();
        runtime
            .invoke("settings.update", json!({"adbBurstMode":true}))
            .await
            .unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), before);
        assert_eq!(
            runtime.invoke("settings.get", Value::Null).await.unwrap()["adbBurstMode"],
            true
        );
        runtime
            .invoke("devices.add", json!({"address":"127.0.0.1","port":9}))
            .await
            .unwrap();
        let persisted: Value =
            serde_json::from_slice(&tokio::fs::read(&path).await.unwrap()).unwrap();
        assert!(
            persisted.get("settings").is_none(),
            "unrelated device saves must not persist an execution mirror"
        );
    }
}
