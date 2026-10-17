//! Durable device observation intent, separate from shared helper lifetime.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{Device, required},
};
use serde_json::{Value, json};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::RwLock;
use uuid::Uuid;

pub(crate) struct Observation {
    generation: u64,
    phase: String,
    helper: Option<Uuid>,
    running: bool,
    failures: u32,
    retry_after: Instant,
    notifications: Value,
    calls: Value,
}
fn unknown(section: &str, phase: &str, reason: &str) -> Value {
    json!({section:[],"status":if phase=="stopped" {"stopped"} else {"unknown"},"live":false,"reason":reason})
}
impl Observation {
    fn new(wanted: bool) -> Self {
        let phase = if wanted {
            "waiting_connection"
        } else {
            "stopped"
        };
        Self {
            generation: 0,
            phase: phase.into(),
            helper: None,
            running: false,
            failures: 0,
            retry_after: Instant::now(),
            notifications: unknown("notifications", phase, "尚未建立当前连接的实时观察。"),
            calls: unknown("calls", phase, "尚未建立当前连接的实时观察。"),
        }
    }
    fn clear(&mut self, reason: &str) {
        self.notifications = unknown("notifications", &self.phase, reason);
        self.calls = unknown("calls", &self.phase, reason);
    }
    fn invalidate(&mut self, wanted: bool, reason: &str) {
        self.generation = self
            .generation
            .checked_add(1)
            .expect("observation generation exhausted");
        self.phase = if wanted {
            "waiting_connection"
        } else {
            "stopped"
        }
        .into();
        self.helper = None;
        self.running = false;
        self.failures = 0;
        self.retry_after = Instant::now();
        self.clear(reason);
    }
    fn view(&self, device: &Device) -> Value {
        json!({"deviceId":device.id,"wanted":device.observation_wanted,"phase":self.phase,"generation":self.generation,"notifications":self.notifications,"calls":self.calls})
    }
    fn current_view(&self, device: &Device, active_helper: bool) -> Value {
        let mut value = self.view(device);
        if device.observation_wanted
            && (device.status != "connected"
                || (matches!(self.phase.as_str(), "observing" | "limited") && !active_helper))
        {
            let phase = if device.status == "connected" {
                "failed"
            } else {
                "waiting_connection"
            };
            value["phase"] = json!(phase);
            value["notifications"] =
                unknown("notifications", phase, "实时观察连接已失效，等待重新核验。");
            value["calls"] = unknown("calls", phase, "实时观察连接已失效，等待重新核验。");
        }
        value
    }
}
impl Runtime {
    pub(crate) async fn observation_list(&self) -> CoreResult<Vec<Value>> {
        let observations = self.observations.lock().await;
        let store = self.store.read().await;
        let helpers = self.companions.lock().await;
        Ok(store
            .devices
            .iter()
            .map(|d| {
                observations
                    .get(&d.id)
                    .map(|o| {
                        o.current_view(
                            d,
                            helpers.get(&d.id).is_some_and(|helper| {
                                Some(helper.id) == o.helper && helper.is_active()
                            }),
                        )
                    })
                    .unwrap_or_else(|| Observation::new(d.observation_wanted).view(d))
            })
            .collect())
    }
    pub(crate) async fn observation_status(&self, id: &str) -> CoreResult<Value> {
        let observations = self.observations.lock().await;
        let device = self.device(id).await?;
        let helpers = self.companions.lock().await;
        Ok(observations
            .get(id)
            .map(|o| {
                o.current_view(
                    &device,
                    helpers
                        .get(id)
                        .is_some_and(|helper| Some(helper.id) == o.helper && helper.is_active()),
                )
            })
            .unwrap_or_else(|| Observation::new(device.observation_wanted).view(&device)))
    }
    pub(crate) async fn observation_command(
        self: &Arc<Self>,
        command: &str,
        params: &Value,
    ) -> CoreResult<Value> {
        if command == "observation.list" {
            return Ok(json!({"observations":self.observation_list().await?}));
        }
        let id = required(params, "deviceId")?;
        if command == "observation.status" {
            return self.observation_status(id).await;
        }
        if !matches!(command, "observation.start" | "observation.stop") {
            return Err(CoreError::new("unknown_command", "未知观察操作。"));
        }
        let wanted = command == "observation.start";
        let helper = self
            .companions
            .lock()
            .await
            .get(id)
            .filter(|h| h.is_active())
            .cloned();
        let generation;
        {
            let mut observations = self.observations.lock().await;
            let mut store = self.store.write().await;
            let device = store
                .devices
                .iter_mut()
                .find(|d| d.id == id)
                .ok_or_else(|| CoreError::new("not_found", "这台设备的本机记录已不存在。"))?;
            let observation = observations
                .entry(id.into())
                .or_insert_with(|| Observation::new(device.observation_wanted));
            if wanted
                && device.observation_wanted
                && matches!(observation.phase.as_str(), "observing" | "limited")
                && observation.notifications["live"] == true
                && observation.calls["live"] == true
                && helper
                    .as_ref()
                    .is_some_and(|h| Some(h.id) == observation.helper)
            {
                return Ok(observation.view(device));
            }
            device.observation_wanted = wanted;
            observation.invalidate(
                wanted,
                if wanted {
                    "正在等待建立实时观察。"
                } else {
                    "已主动停止通知与来电观察。"
                },
            );
            if wanted && device.status == "connected" {
                observation.phase = "starting".into();
            }
            if !wanted {
                observation.helper = helper.as_ref().map(|h| h.id);
            }
            generation = observation.generation;
            let mut cache = match helper.as_ref() {
                Some(helper) => Some(helper.state.write().await),
                None => None,
            };
            if let Some(cache) = cache.as_mut() {
                cache["notifications"] = observation.notifications.clone();
                cache["calls"] = observation.calls.clone();
            }
            self.emit("observation.changed", Some(id), observation.view(device));
        }
        // A durable false intent is acknowledged before any possible restart.
        self.persist().await?;
        if wanted {
            self.observation_wakeup.notify_one();
        } else if let Some(helper) = helper
            && let Err(error) = helper
                .request(
                    "observation.set",
                    &json!({"enabled":false,"epoch":generation}),
                )
                .await
        {
            self.observation_failed(id, generation, &error.message, false)
                .await;
        }
        self.observation_status(id).await
    }
    pub(crate) async fn observation_connection_changed(&self, id: &str) {
        let mut observations = self.observations.lock().await;
        let Ok(device) = self.device(id).await else {
            return;
        };
        let observation = observations
            .entry(id.into())
            .or_insert_with(|| Observation::new(device.observation_wanted));
        observation.invalidate(
            device.observation_wanted,
            "连接已变化，实时内容等待重新核验。",
        );
        let helper = self.companions.lock().await.get(id).cloned();
        let mut cache = match helper.as_ref() {
            Some(helper) => Some(helper.state.write().await),
            None => None,
        };
        if let Some(cache) = cache.as_mut() {
            cache["notifications"] = observation.notifications.clone();
            cache["calls"] = observation.calls.clone();
        }
        self.emit("observation.changed", Some(id), observation.view(&device));
        self.observation_wakeup.notify_one();
    }
    pub(crate) async fn forget_observation(&self, id: &str) {
        self.observations.lock().await.remove(id);
        self.events.note_state_change();
    }
    pub(crate) async fn bind_observation(&self, id: &str, generation: u64, helper: Uuid) -> bool {
        let mut observations = self.observations.lock().await;
        let Ok(device) = self.device(id).await else {
            return false;
        };
        let Some(observation) = observations.get_mut(id) else {
            return false;
        };
        if !device.observation_wanted
            || device.status != "connected"
            || observation.generation != generation
        {
            return false;
        }
        observation.helper = Some(helper);
        true
    }
    pub(crate) async fn observation_is_current(&self, id: &str, generation: u64) -> bool {
        let observations = self.observations.lock().await;
        self.device(id)
            .await
            .is_ok_and(|device| device.observation_wanted && device.status == "connected")
            && observations
                .get(id)
                .is_some_and(|value| value.generation == generation)
    }
    // The exact helper and wire epoch must still own the current intent. The
    // actor crosses this seam before returning RPC receipts or publishing data.
    pub(crate) async fn commit_observation(
        &self,
        id: &str,
        helper: Uuid,
        response: &Value,
        section: Option<&str>,
        kind: Option<&str>,
        state: &RwLock<Value>,
    ) -> bool {
        let data = if section.is_some() {
            &response["data"]
        } else {
            response
        };
        if !self
            .companions
            .lock()
            .await
            .get(id)
            .is_some_and(|current| current.id == helper && current.is_active())
        {
            return false;
        }
        let mut observations = self.observations.lock().await;
        let Ok(device) = self.device(id).await else {
            return false;
        };
        let Some(observation) = observations.get_mut(id) else {
            return false;
        };
        if device.status != "connected"
            || observation.helper != Some(helper)
            || data["observationEpoch"].as_u64() != Some(observation.generation)
        {
            return false;
        }
        if section.is_some() && (!device.observation_wanted || data["observationEnabled"] != true) {
            return false;
        }
        if section.is_none() && data["observationEnabled"] != device.observation_wanted {
            return false;
        }
        let mut cache = state.write().await;
        if let Some(section) = section {
            cache[section] = data.clone();
            if section == "notifications" {
                observation.notifications = data.clone();
            } else {
                observation.calls = data.clone();
            }
            if let Some(kind) = kind {
                self.emit(kind, Some(id), data.clone());
                self.emit("observation.changed", Some(id), observation.view(&device));
            } else {
                self.events.note_state_change();
            }
        } else {
            observation.notifications = data["notifications"].clone();
            observation.calls = data["calls"].clone();
            cache["notifications"] = observation.notifications.clone();
            cache["calls"] = observation.calls.clone();
            observation.phase = if !device.observation_wanted {
                if data["cleanupConfirmed"] == false {
                    "failed"
                } else {
                    "stopped"
                }
            } else if observation.notifications["status"] == "limited"
                || observation.calls["status"] == "limited"
            {
                "limited"
            } else {
                "observing"
            }
            .into();
            self.emit("observation.changed", Some(id), observation.view(&device));
        }
        true
    }
    async fn observation_failed(&self, id: &str, generation: u64, reason: &str, retry: bool) {
        let mut observations = self.observations.lock().await;
        let Ok(device) = self.device(id).await else {
            return;
        };
        let Some(observation) = observations
            .get_mut(id)
            .filter(|o| o.generation == generation)
        else {
            return;
        };
        observation.running = false;
        observation.phase = if device.observation_wanted && device.status != "connected" {
            "waiting_connection"
        } else {
            "failed"
        }
        .into();
        observation.clear(reason);
        observation.failures = observation.failures.saturating_add(1);
        observation.retry_after = Instant::now()
            + Duration::from_secs(if retry {
                1 << observation.failures.min(5)
            } else {
                32
            });
        self.emit("observation.changed", Some(id), observation.view(&device));
    }
    pub(crate) async fn observation_helper_stopped(&self, id: &str, helper: Uuid, reason: &str) {
        {
            let mut observations = self.observations.lock().await;
            let Ok(device) = self.device(id).await else {
                return;
            };
            if !device.observation_wanted {
                if let Some(observation) = observations
                    .get_mut(id)
                    .filter(|value| value.helper == Some(helper))
                {
                    observation.phase = "stopped".into();
                    observation.helper = None;
                    observation.clear("已主动停止通知与来电观察。");
                    self.emit("observation.changed", Some(id), observation.view(&device));
                }
                return;
            }
        }
        let generation = self
            .observations
            .lock()
            .await
            .get(id)
            .filter(|o| o.helper == Some(helper))
            .map(|o| o.generation);
        if let Some(generation) = generation {
            self.observation_failed(id, generation, reason, true).await;
            self.observation_wakeup.notify_one();
        }
    }
    pub(crate) fn spawn_observation_supervisor(self: &Arc<Self>) {
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(runtime) = weak.upgrade() else {
                    break;
                };
                let wake = runtime.observation_wakeup.clone();
                drop(runtime);
                tokio::select! {_=wake.notified()=>{},_=tokio::time::sleep(Duration::from_secs(1))=>{}}
                let Some(runtime) = weak.upgrade() else {
                    break;
                };
                let devices = runtime.store.read().await.devices.clone();
                for device in devices
                    .into_iter()
                    .filter(|d| d.observation_wanted && d.status == "connected")
                {
                    let generation = {
                        let mut observations = runtime.observations.lock().await;
                        let Ok(current) = runtime.device(&device.id).await else {
                            continue;
                        };
                        if !current.observation_wanted || current.status != "connected" {
                            continue;
                        }
                        let observation = observations
                            .entry(device.id.clone())
                            .or_insert_with(|| Observation::new(true));
                        if observation.running
                            || matches!(observation.phase.as_str(), "observing" | "limited")
                            || Instant::now() < observation.retry_after
                        {
                            continue;
                        }
                        observation.running = true;
                        observation.phase = "starting".into();
                        observation.generation = observation
                            .generation
                            .checked_add(1)
                            .expect("observation generation exhausted");
                        runtime.emit(
                            "observation.changed",
                            Some(&device.id),
                            observation.view(&device),
                        );
                        observation.generation
                    };
                    let owner = runtime.clone();
                    tokio::spawn(async move {
                        let has_helper = owner
                            .companions
                            .lock()
                            .await
                            .get(&device.id)
                            .is_some_and(|helper| helper.is_active());
                        let result=owner.companion_command("observation.set",&json!({"deviceId":device.id,"enabled":true,"epoch":generation,"allowStart":!has_helper})).await;
                        match result {
                            Ok(_) => {
                                if let Some(observation) = owner
                                    .observations
                                    .lock()
                                    .await
                                    .get_mut(&device.id)
                                    .filter(|o| o.generation == generation)
                                {
                                    observation.running = false;
                                    observation.failures = 0;
                                }
                            }
                            Err(error) => {
                                owner
                                    .observation_failed(
                                        &device.id,
                                        generation,
                                        &error.message,
                                        true,
                                    )
                                    .await
                            }
                        }
                    });
                }
            }
        });
    }
}
