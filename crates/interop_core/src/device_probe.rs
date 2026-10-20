//! Bounded protocol observations. Product capability labels belong to Dart.
use crate::{CoreError, CoreResult, Runtime, device::endpoint, model::required};
use interop_adb::{OperationOptions, sync::RemotePath};
use serde_json::{Value, json};
use std::time::Duration;
use tokio_util::sync::CancellationToken;

impl Runtime {
    pub(crate) async fn device_probe(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let device = self.device(id).await?;
        let client = self.client(id).await.ok();
        let connection_id = client
            .as_ref()
            .map(|client| client.connection_id().to_string());
        if params["connectionId"]
            .as_str()
            .is_some_and(|expected| Some(expected) != connection_id.as_deref())
        {
            return Err(CoreError::new("stale_connection", "探测指定的连接已替换。"));
        }
        let timeout = Duration::from_millis(
            params["timeoutMs"]
                .as_u64()
                .filter(|ms| (1..=60_000).contains(ms))
                .ok_or_else(|| {
                    CoreError::new("invalid_argument", "探测超时必须介于1毫秒和60秒。")
                })?,
        );
        let probes = params["probes"]
            .as_array()
            .filter(|items| items.len() <= 5)
            .ok_or_else(|| CoreError::new("invalid_argument", "探测项目无效。"))?;
        let mut observations = serde_json::Map::new();
        for probe in probes {
            let name = probe
                .as_str()
                .ok_or_else(|| CoreError::new("invalid_argument", "探测项目无效。"))?;
            if !matches!(
                name,
                "tcp" | "shell" | "sync" | "packages" | "wirelessProperties"
            ) {
                return Err(CoreError::new("invalid_argument", "未知协议探测项目。"));
            }
            let result: CoreResult<Value> = tokio::time::timeout(timeout,async {
                if name=="tcp" {
                    if device.transport.is_usb() || device.port==0 { return Ok(json!({"status":"not_applicable"})); }
                    return match tokio::net::TcpStream::connect(endpoint(&device.address,device.port)).await {
                        Ok(_) => Ok(json!({"status":"ok"})),
                        Err(error) => Ok(json!({"status":"error","code":if error.kind()==std::io::ErrorKind::PermissionDenied {"permission_denied"} else {"unreachable"}})),
                    };
                }
                let client=client.as_ref().ok_or_else(||CoreError::new("disconnected","当前没有设备连接。"))?;
                let options=OperationOptions {timeout,cancellation:CancellationToken::new()};
                if name=="sync" {
                    let mut sync=client.sync(options).await?;
                    let stat=sync.stat(&RemotePath::new(b"/")?).await?;
                    return Ok(json!({"status":"ok","mode":stat.mode}));
                }
                let (command,limit)=match name {
                    "shell"=>("printf interop-capability-check",1024),
                    "packages"=>("pm list packages",512*1024),
                    _=>("getprop service.adb.tls.port; getprop persist.adb.tls_server.enable; getprop mdns_service_version",8192),
                };
                let output=client.shell(command,limit,options).await?;
                Ok(json!({"status":"ok","stdout":String::from_utf8_lossy(&output.stdout),"exitCode":output.exit_code}))
            }).await.unwrap_or_else(|_|Err(CoreError::new("timeout","协议探测超时。")));
            observations.insert(
                name.into(),
                match result {
                    Ok(value) => value,
                    Err(error) => json!({"status":"error","code":error.code}),
                },
            );
        }
        let current = self.client(id).await.ok();
        if current.as_ref().map(|c| c.connection_id().to_string()) != connection_id {
            return Err(CoreError::new(
                "stale_connection",
                "探测期间设备连接已改变。",
            ));
        }
        let latest = self.device(id).await?;
        if (
            latest.address.as_str(),
            latest.port,
            json!(&latest.transport),
            &latest.guid,
        ) != (
            device.address.as_str(),
            device.port,
            json!(&device.transport),
            &device.guid,
        ) {
            return Err(CoreError::new(
                "stale_device",
                "探测期间设备地址或身份已改变。",
            ));
        }
        let identity = match self.identities.selected(Some(id)).await {
            Ok(material) => json!({"status":"ok","fingerprint":material.fingerprint}),
            Err(error) => json!({"status":"error","code":error.code}),
        };
        let companion = match self.companions.lock().await.get(id).cloned() {
            Some(companion) if companion.is_active() => companion.capability_state().await,
            _ => Value::Null,
        };
        Ok(
            json!({"deviceId":id,"device":latest,"connectionId":connection_id,"connected":current.is_some(),
            "observations":observations,"identity":identity,"usbBackendAvailable":interop_adb::usb::supported(),
            "adbBurstActive":current.as_ref().map(|c|c.burst_mode()),
            "features":current.map(|c|c.info().features.iter().cloned().collect::<Vec<_>>()).unwrap_or_default(),
            "activities":self.activities().await?,"audio":self.audio_command("audio.sources",&json!({})).await?,"companion":companion}),
        )
    }
}
