//! Activity ownership, projection and targeted cancellation. Wire IDs are kept
//! here so listing an activity and stopping it always use the same identity.
use crate::{CoreError, CoreResult, Runtime, model::required};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};
use tokio::sync::Mutex;

#[derive(Default)]
pub(crate) struct ActivityOwner {
    pub(crate) sessions: Mutex<HashMap<String, crate::scrcpy::Session>>,
    pub(crate) audio_sources: Mutex<HashMap<String, crate::audio::AudioSource>>,
    pub(crate) transfers: Mutex<HashMap<String, crate::files::Transfer>>,
    pub(crate) admission: crate::resource::ResourceAdmission,
    pub(crate) keep_active: crate::scrcpy::KeepActiveOwner,
}

impl ActivityOwner {
    pub(crate) async fn cancel_device_transfers(&self, device: &str) {
        for transfer in self
            .transfers
            .lock()
            .await
            .values_mut()
            .filter(|task| task.device_id == device)
        {
            if matches!(
                transfer.status.as_str(),
                "queued" | "running" | "finalizing"
            ) {
                transfer.cancellation.cancel();
            }
        }
    }

    pub(crate) async fn session_snapshots(&self) -> Vec<Value> {
        let mut sessions = Vec::new();
        for session in self.sessions.lock().await.values() {
            if let Some(state) = session.activity_snapshot().await {
                sessions.push(state);
            }
        }
        sessions
    }

    pub(crate) async fn audio_snapshots(&self, active_only: bool) -> Vec<Value> {
        let mut sources = Vec::new();
        for source in self.audio_sources.lock().await.values() {
            if let Some(state) = source.snapshot(active_only).await {
                sources.push(state);
            }
        }
        sources
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ActivityRef<'a> {
    Connection(&'a str),
    Session(&'a str),
    Transfer(&'a str),
    Observation(&'a str),
    Audio(&'a str),
}

impl<'a> ActivityRef<'a> {
    fn parse(value: &'a str) -> Option<Self> {
        let (kind, id) = value.split_once(':')?;
        if id.is_empty() {
            return None;
        }
        match kind {
            "connection" => Some(Self::Connection(id)),
            "session" => Some(Self::Session(id)),
            "transfer" => Some(Self::Transfer(id)),
            "observation" => Some(Self::Observation(id)),
            "audio" => Some(Self::Audio(id)),
            _ => None,
        }
    }
}

impl std::fmt::Display for ActivityRef<'_> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (kind, id) = match self {
            Self::Connection(id) => ("connection", id),
            Self::Session(id) => ("session", id),
            Self::Transfer(id) => ("transfer", id),
            Self::Observation(id) => ("observation", id),
            Self::Audio(id) => ("audio", id),
        };
        write!(formatter, "{kind}:{id}")
    }
}

impl Runtime {
    pub(crate) async fn stop_device_activities(&self, id: &str) -> CoreResult<()> {
        self.searches.cancel_device(id);
        self.gallery_scans.cancel_device(id);
        self.observation_connection_changed(id).await;
        self.activities.cancel_device_transfers(id).await;
        self.stop_device_sessions(id).await;
        self.stop_device_audio(id).await;
        self.stop_device_companion(id).await;
        Ok(())
    }

    pub async fn stop_all(self: &Arc<Self>) {
        self.setup_operations.release_all().await;
        let tokens: Vec<_> = self
            .device_operations
            .lock()
            .await
            .drain()
            .map(|(_, t)| t)
            .collect();
        for token in tokens {
            token.cancel();
        }
        let ids: Vec<_> = self
            .store
            .read()
            .await
            .devices
            .iter()
            .map(|d| d.id.clone())
            .collect();
        for id in ids {
            let _ = self.disconnect_device(&id, false).await;
        }
    }
}

impl Runtime {
    pub(crate) async fn activities(&self) -> CoreResult<Value> {
        let mut sessions = self.activities.session_snapshots().await;
        for record in self.app_opens.unresolved(None).await {
            if !sessions
                .iter()
                .any(|session| session["sessionId"] == record["sessionId"])
            {
                sessions.push(record);
            }
        }
        let transfers = self.list_transfers().await?;
        let devices = self.store.read().await.devices.clone();
        let device_name = |id: &str| {
            devices
                .iter()
                .find(|device| device.id == id)
                .map(|device| device.name.clone())
                .unwrap_or_else(|| "Android 设备".into())
        };
        let mut activities = Vec::new();
        for (device, client) in self.connections.lock().await.iter() {
            if !client.is_closed() {
                activities.push(json!({"id":ActivityRef::Connection(device).to_string(),"deviceId":device,"deviceName":device_name(device),"name":"设备连接","status":"connected","canStop":true,"stopImpact":"断开这台设备，并停止它的控制会话和传输任务；其他设备不受影响。"}));
            }
        }
        for session in &sessions {
            activities.push(json!({"id":ActivityRef::Session(session["sessionId"].as_str().unwrap_or_default()).to_string(),"deviceId":session["deviceId"],"deviceName":device_name(session["deviceId"].as_str().unwrap_or_default()),"name":session["name"],"status":session["status"],"canStop":true,"stopImpact":"仅关闭这个控制会话，手机应用任务交回设备，不会强停应用。"}));
        }
        let known = activities
            .iter()
            .filter_map(|activity| activity["id"].as_str().map(str::to_owned))
            .collect::<HashSet<_>>();
        for reserved in self
            .activities
            .admission
            .activities()
            .into_iter()
            .filter(|reserved| !known.contains(&reserved.id))
        {
            activities.push(json!({"id":reserved.id,"deviceId":reserved.device_id,"deviceName":device_name(&reserved.device_id),
                "name":reserved.name,"status":reserved.status,"canStop":true,"canPause":reserved.can_pause,
                "reserved":true,"stopImpact":"仅取消这个正在启动或清理的控制会话；已有其他活动保持不变。"}));
        }
        if let Some(transfers) = transfers["transfers"].as_array() {
            for transfer in transfers.iter().filter(|transfer| {
                matches!(
                    transfer["status"].as_str(),
                    Some("queued" | "running" | "finalizing" | "conflict")
                )
            }) {
                activities.push(json!({"id":ActivityRef::Transfer(transfer["id"].as_str().unwrap_or_default()).to_string(),"deviceId":transfer["deviceId"],"deviceName":device_name(transfer["deviceId"].as_str().unwrap_or_default()),"name":transfer["name"],"status":transfer["status"],"canStop":true,"stopImpact":"仅取消这一项传输；已完成的文件不回滚，未完成内容保留为实际中断状态。"}));
            }
        }
        for observation in self.observation_list().await? {
            if observation["wanted"] == true {
                let id = observation["deviceId"].as_str().unwrap_or_default();
                activities.push(json!({"id":ActivityRef::Observation(id).to_string(),"deviceId":id,"deviceName":device_name(id),"name":"通知与来电观察","status":observation["phase"],"canStop":true,"stopImpact":"仅停止这台设备的通知与来电观察；剪贴板和媒体处理保持运行。"}));
            }
        }
        for source in self.audio_activity_sources().await {
            let device = source["deviceId"].as_str().unwrap_or_default();
            let source_id = source["sourceId"].as_str().unwrap_or_default();
            activities.push(json!({"id":ActivityRef::Audio(source_id).to_string(),"deviceId":device,"sourceId":source_id,
                "deviceName":device_name(device),"name":"设备声音","status":source["status"],"canStop":true,
                "stopImpact":"仅停止这台设备的这一代音源；设备连接、控制会话、通知与来电观察及其他设备音源保持运行。"}));
        }
        Ok(json!({"activities":activities,"sessions":sessions,"transfers":transfers["transfers"]}))
    }

    pub(crate) async fn stop_activity(self: &Arc<Self>, params: &Value) -> CoreResult<Value> {
        let id = required(params, "activityId")?;
        match ActivityRef::parse(id) {
            Some(ActivityRef::Audio(source_id)) => {
                let source = self
                    .audio_activity_sources()
                    .await
                    .into_iter()
                    .find(|source| source["sourceId"] == source_id)
                    .ok_or_else(|| {
                        CoreError::new("not_found", "此音源活动已结束或已被新一代音源替换。")
                    })?;
                // Bind to the observed device, then atomically recheck the source
                // generation inside audio.stop before removing its current owner.
                return self
                    .audio_command(
                        "audio.stop",
                        &json!({"deviceId":source["deviceId"],"sourceId":source_id}),
                    )
                    .await;
            }
            Some(ActivityRef::Observation(id)) => {
                self.observation_command("observation.stop", &json!({"deviceId":id}))
                    .await
            }
            Some(ActivityRef::Connection(id)) => self.disconnect_device(id, false).await,
            Some(ActivityRef::Session(id)) => {
                self.session_command("session.stop", &json!({"sessionId":id}))
                    .await
            }
            Some(ActivityRef::Transfer(id)) => {
                self.transfer_command("transfers.cancel", &json!({"transferId":id}))
                    .await
            }
            None => Err(CoreError::new("not_found", "此活动已结束或标识无效。")),
        }
    }
}
