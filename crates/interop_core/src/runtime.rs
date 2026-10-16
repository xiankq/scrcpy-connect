use crate::{
    CoreError, CoreResult,
    model::{Device, Store, now, required},
};
use interop_adb::{Client, Identity};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Arc,
};
use tokio::{
    fs,
    sync::{Mutex, RwLock, broadcast},
};

pub struct Runtime {
    pub(crate) root: PathBuf,
    pub(crate) identity: Identity,
    pub(crate) store: RwLock<Store>,
    pub(crate) connections: Mutex<HashMap<String, Client>>,
    pub(crate) events: broadcast::Sender<Value>,
    pub(crate) persistence: Mutex<()>,
    pub(crate) sessions: Mutex<HashMap<String, crate::scrcpy::Session>>,
    pub(crate) resource_admission: crate::resource::ResourceAdmission,
    pub(crate) audio_sources: Mutex<HashMap<String, crate::audio::AudioSource>>,
    pub(crate) companions: Mutex<HashMap<String, Arc<crate::companion::Companion>>>,
    pub(crate) transfers: Mutex<HashMap<String, crate::files::Transfer>>,
    pub(crate) sharing: Mutex<Option<Arc<crate::sharing::ImportManager>>>,
    pub(crate) documents: crate::documents::CopyManager,
    pub(crate) media: crate::media::http::MediaStreams,
    pub(crate) qr_attempt: Mutex<Option<(String, tokio_util::sync::CancellationToken)>>,
    pub(crate) device_operations: Mutex<HashMap<String, tokio_util::sync::CancellationToken>>,
}

impl Runtime {
    pub async fn initialize(root: impl AsRef<Path>) -> CoreResult<Arc<Self>> {
        let root = root.as_ref().to_path_buf();
        fs::create_dir_all(&root).await?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).await?;
        }
        let identity_path = root.join("host_identity.pem");
        let identity = match fs::read_to_string(&identity_path).await {
            Ok(pem) => Identity::from_pem(&pem)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let id = tokio::task::spawn_blocking(Identity::generate)
                    .await
                    .map_err(|e| CoreError::new("identity_error", e.to_string()))??;
                Self::private_write(&identity_path, id.to_pkcs8_pem()?.as_bytes()).await?;
                id
            }
            Err(e) => return Err(e.into()),
        };
        let fingerprint = format!("{:x}", Sha256::digest(identity.public_key("interop")?));
        let mut store = match fs::read(root.join("devices.json")).await {
            Ok(bytes) => serde_json::from_slice::<Store>(&bytes)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Store {
                version: 1,
                identity_fingerprint: fingerprint.clone(),
                devices: Vec::new(),
                settings: crate::preferences::defaults(),
            },
            Err(e) => return Err(e.into()),
        };
        if store.version != 1 {
            return Err(CoreError::new(
                "storage_version",
                "设备记录版本较新，请更新应用。",
            ));
        }
        let defaults = crate::preferences::defaults();
        let settings = store
            .settings
            .as_object_mut()
            .ok_or_else(|| CoreError::new("invalid_data", "本机设置记录损坏。"))?;
        for (key, value) in defaults.as_object().unwrap() {
            settings.entry(key.clone()).or_insert_with(|| value.clone());
        }
        let identity_changed = store.identity_fingerprint != fingerprint;
        store.identity_fingerprint = fingerprint;
        for device in &mut store.devices {
            device.status = if identity_changed {
                "unauthorized"
            } else {
                "offline"
            }
            .into();
            device.reason = identity_changed.then(|| "本机授权身份已改变，需要重新授权。".into());
            if identity_changed {
                device.auto_reconnect = false;
            }
        }
        let (events, _) = broadcast::channel(256);
        let runtime = Arc::new(Self {
            root,
            identity,
            store: RwLock::new(store),
            connections: Mutex::new(HashMap::new()),
            events,
            persistence: Mutex::new(()),
            sessions: Mutex::new(HashMap::new()),
            resource_admission: crate::resource::ResourceAdmission::default(),
            audio_sources: Mutex::new(HashMap::new()),
            companions: Mutex::new(HashMap::new()),
            transfers: Mutex::new(HashMap::new()),
            sharing: Mutex::new(None),
            documents: crate::documents::CopyManager::default(),
            media: crate::media::http::MediaStreams::default(),
            qr_attempt: Mutex::new(None),
            device_operations: Mutex::new(HashMap::new()),
        });
        runtime.restore_transfers().await?;
        runtime.persist().await?;
        runtime.spawn_connection_monitor();
        Ok(runtime)
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Value> {
        self.events.subscribe()
    }
    pub(crate) fn emit(&self, kind: &str, device: Option<&str>, data: Value) {
        let _ = self
            .events
            .send(json!({"type":kind,"deviceId":device,"data":data,"timestamp":now()}));
    }
    pub(crate) async fn private_write(path: &Path, bytes: &[u8]) -> CoreResult<()> {
        use tokio::io::AsyncWriteExt;
        let mut options = fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        {
            options.mode(0o600);
        }
        let temporary = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
        let mut output = options.open(&temporary).await?;
        output.write_all(bytes).await?;
        output.sync_all().await?;
        drop(output);
        if let Err(e) = fs::rename(&temporary, path).await {
            let _ = fs::remove_file(&temporary).await;
            return Err(e.into());
        }
        Ok(())
    }
    pub(crate) async fn persist(&self) -> CoreResult<()> {
        let _guard = self.persistence.lock().await;
        let bytes = serde_json::to_vec_pretty(&*self.store.read().await)?;
        Self::private_write(&self.root.join("devices.json"), &bytes).await
    }
    pub(crate) async fn device(&self, id: &str) -> CoreResult<Device> {
        self.store
            .read()
            .await
            .devices
            .iter()
            .find(|d| d.id == id)
            .cloned()
            .ok_or_else(|| CoreError::new("not_found", "这台设备的本机记录已不存在。"))
    }
    pub(crate) async fn client(&self, id: &str) -> CoreResult<Client> {
        self.connections
            .lock()
            .await
            .get(id)
            .filter(|c| !c.is_closed())
            .cloned()
            .ok_or_else(|| CoreError::new("disconnected", "设备尚未连接，请先恢复连接。"))
    }

    pub(crate) async fn stop_device_activities(&self, id: &str) -> CoreResult<()> {
        for transfer in self
            .transfers
            .lock()
            .await
            .values_mut()
            .filter(|t| t.device_id == id)
        {
            if matches!(
                transfer.status.as_str(),
                "queued" | "running" | "finalizing"
            ) {
                transfer.cancellation.cancel();
            }
        }
        self.stop_device_sessions(id).await;
        self.stop_device_audio(id).await;
        self.stop_device_companion(id).await;
        Ok(())
    }

    pub async fn invoke(self: &Arc<Self>, command: &str, params: Value) -> CoreResult<Value> {
        if matches!(command, "media.open" | "media.status" | "media.close") {
            return self.media.command(command, &params).await;
        }
        if command.starts_with("document.") {
            let result = if matches!(command, "document.cancel" | "document.limits") {
                self.documents.request(command, params)
            } else {
                let manager = self.documents.clone();
                let command = command.to_owned();
                tokio::task::spawn_blocking(move || manager.request(&command, params))
                    .await
                    .map_err(|_| {
                        CoreError::new("document_worker_failed", "本机文件任务意外结束。")
                    })?
            };
            return result.map_err(|error| CoreError {
                code: error.code.into(),
                message: error.message,
                details: error.details,
            });
        }
        if command.starts_with("sharing.") {
            return self.sharing_command(command, &params).await;
        }
        if command == "files.push"
            && let Some(share) = params["shareId"].as_str()
        {
            let manager = self.sharing_manager().await?;
            return Box::pin(manager.submit_checked(share, &params, || async {
                match Box::pin(self.start_transfer(command, params.clone())).await {
                    Ok(receipt) => Ok(receipt),
                    Err(error) => {
                        let sources: Vec<_> = params["items"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|item| item["source"].as_str())
                            .collect();
                        let published = self.transfers.lock().await.values().any(|task| {
                            task.direction == "push" && sources.contains(&task.source.as_str())
                        });
                        Err((error, !published))
                    }
                }
            }))
            .await;
        }
        match command {
            "devices.list" => Ok(json!({"devices":self.store.read().await.devices})),
            "devices.add" => Box::pin(self.add_device(&params)).await,
            "devices.connect" => {
                Box::pin(self.connect_device_with_attempt(
                    required(&params, "deviceId")?,
                    params["attemptId"].as_str(),
                ))
                .await
            }
            "devices.disconnect" | "devices.forget" => {
                Box::pin(
                    self.disconnect_device(
                        required(&params, "deviceId")?,
                        command.ends_with("forget"),
                    ),
                )
                .await
            }
            "devices.rename" => Box::pin(self.rename_device(&params)).await,
            "devices.discover" => Box::pin(self.discover_devices()).await,
            "devices.pair" => Box::pin(self.pair_device(&params)).await,
            "devices.pair.qr" => Box::pin(self.qr_pairing()).await,
            "devices.usb" => Box::pin(self.usb_devices(&params)).await,
            "devices.wireless" => Box::pin(self.enable_wireless(&params)).await,
            "devices.wake" => Box::pin(self.wake_device(required(&params, "deviceId")?)).await,
            "device.info" => Ok(serde_json::to_value(
                self.device(required(&params, "deviceId")?).await?,
            )?),
            "device.capabilities" => {
                Box::pin(self.capabilities(required(&params, "deviceId")?)).await
            }
            "device.diagnose" => Box::pin(self.diagnose(required(&params, "deviceId")?)).await,
            "files.list" => Box::pin(self.list_files(&params)).await,
            "files.mkdir" | "files.rename" | "files.delete" => {
                Box::pin(self.mutate_files(command, &params)).await
            }
            "files.pull" | "files.push" => Box::pin(self.start_transfer(command, params)).await,
            "transfers.list" => Box::pin(self.list_transfers()).await,
            "transfers.get" | "transfers.cancel" | "transfers.resume" | "transfers.resolve" => {
                Box::pin(self.transfer_command(command, &params)).await
            }
            "media.list" => Box::pin(self.list_media(&params)).await,
            "media.preview" => Box::pin(self.preview_media(&params)).await,
            "media.thumbnail" => Box::pin(self.thumbnail_media(&params)).await,
            "media.thumbnail.cancel" => Box::pin(self.cancel_thumbnail_media(&params)).await,
            "apps.list" => Box::pin(self.list_apps(&params)).await,
            "apps.launch" => Box::pin(self.launch_app(&params)).await,
            "session.start" => Box::pin(self.start_session(&params)).await,
            "session.stop"
            | "session.touch"
            | "session.key"
            | "session.text"
            | "session.screen"
            | "session.quality"
            | "session.screenshot"
            | "session.ready"
            | "session.frame"
            | "session.list"
            | "session.rotate"
            | "session.refresh"
            | "session.pause"
            | "session.resume"
            | "session.quality.options" => Box::pin(self.session_command(command, &params)).await,
            "settings.get" => Ok(self.store.read().await.settings.clone()),
            "audio.start" | "audio.stop" | "audio.ready" | "audio.sources" | "audio.volume"
            | "audio.pause" | "audio.resume" | "audio.presentation" => {
                Box::pin(self.audio_command(command, &params)).await
            }
            "settings.update" | "settings.export" | "settings.import" | "system.info" => {
                Box::pin(self.preferences(command, &params)).await
            }
            "devices.cancel" => Box::pin(self.cancel_device_operation(&params)).await,
            "activities.list" => Box::pin(self.activities()).await,
            "activities.stop" => Box::pin(self.stop_activity(&params)).await,
            "notifications.list"
            | "notifications.open"
            | "notifications.reply"
            | "notifications.dismiss"
            | "calls.list"
            | "calls.action" => Box::pin(self.companion_command(command, &params)).await,
            "clipboard.get" | "clipboard.set" => {
                Box::pin(self.clipboard_command(command, &params)).await
            }
            _ => Err(CoreError::new(
                "unknown_command",
                format!("未知操作：{command}"),
            )),
        }
    }
}
