//! Read-only recovery projection. No connection, companion or media is started.
use crate::{CoreError, CoreResult, Runtime};
use serde_json::{Value, json};

impl Runtime {
    pub(crate) async fn state_snapshot(&self) -> CoreResult<Value> {
        // The event fence detects concurrent state publications. Frame-only
        // telemetry is deliberately excluded so active video cannot starve it.
        // This is not a transaction across remote Android services.
        for _ in 0..4 {
            let before = self.events.cursor();
            let (devices, settings) = {
                let store = self.store.read().await;
                (store.devices.clone(), store.settings.clone())
            };
            let projected_devices = {
                let clients = self.connections.lock().await;
                devices
                    .iter()
                    .map(|device| crate::device::project_device(device, &clients))
                    .collect::<Vec<_>>()
            };
            let sessions = self.session_command("session.list", &Value::Null).await?;
            let sources = self.audio_command("audio.sources", &Value::Null).await?;
            let transfers = self.list_transfers().await?;
            let activities = self.activities().await?;
            let observations = self.observation_list().await?;
            let adb_operations = self.setup_operations.snapshot().await;
            let shares = match self.sharing.lock().await.clone() {
                Some(manager) => {
                    manager.command("sharing.pending", &Value::Null)?["shares"].clone()
                }
                None => json!([]),
            };
            // Clone owners before awaiting individual capability caches.
            let cached = self.companions.lock().await.clone();
            let mut companions = Vec::new();
            for device in &devices {
                let state = match cached.get(&device.id) {
                    Some(companion) if companion.is_active() => {
                        let state = companion.capability_state().await;
                        companion.is_active().then_some(state)
                    }
                    _ => None,
                }
                .unwrap_or_else(|| json!({
                        "notifications":{"notifications":[],"status":"unknown","live":false,"reason":"尚未建立实时通知观察。"},
                        "calls":{"calls":[],"status":"unknown","live":false,"reason":"尚未建立通话观察。"},
                        "clipboard":{"status":"unknown","live":false}
                    }));
                companions.push(json!({"deviceId":device.id,"state":state}));
            }
            let after = self.events.cursor();
            if before.state_revision == after.state_revision {
                return Ok(json!({
                    "sequence":after.sequence,
                    "consistency":"event-fenced",
                    "devices":projected_devices,"settings":settings,
                    "sessions":sessions["sessions"],"sources":sources["sources"],
                    "transfers":transfers["transfers"],"activities":activities["activities"],
                    "shares":shares,"companions":companions,"observations":observations,
                    "adbOperations":adb_operations
                }));
            }
            tokio::task::yield_now().await;
        }
        Err(CoreError::new(
            "state_busy",
            "设备状态持续变化，尚未取得完整快照，请重试。",
        ))
    }
}
