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
    pub connection_policy: crate::ConnectionPolicy,
    pub settings_defaults: Value,
    pub(crate) root: PathBuf,
    pub(crate) identities: crate::host_identity::IdentityOwner,
    pub(crate) metadata_updates: tokio::sync::mpsc::Sender<crate::device_metadata::Request>,
    _metadata_owner: tokio_util::sync::DropGuard,
    pub(crate) store: RwLock<Store>,
    pub(crate) connections: crate::connections::ConnectionOwner,
    pub(crate) encoder_catalog: crate::encoder_catalog::EncoderCatalog,
    pub(crate) events: crate::events::EventBus,
    pub(crate) persistence: Mutex<()>,
    pub(crate) transfer_store: Mutex<crate::transfer_store::TransferStore>,
    pub(crate) activities: Arc<crate::activities::ActivityOwner>,
    pub(crate) companions: Mutex<HashMap<String, Arc<crate::companion::Companion>>>,
    pub(crate) observations: Mutex<HashMap<String, crate::observation::Observation>>,
    pub(crate) observation_wakeup: Arc<tokio::sync::Notify>,
    pub(crate) searches: crate::file_search::Searches,
    pub(crate) gallery_scans: crate::gallery_index::GalleryScans,
    pub(crate) sharing: Mutex<Option<Arc<crate::sharing::ImportManager>>>,
    pub(crate) documents: crate::documents::CopyManager,
    pub(crate) deliveries: crate::delivery::DeliveryJournal,
    pub(crate) app_opens: crate::app_open::AppOpens,
    pub(crate) quality_changes: Mutex<()>,
    pub(crate) media: crate::media::http::MediaStreams,
    pub(crate) media_cache: crate::media_cache::MediaCache,
    pub(crate) setup_operations: crate::connection_setup::SetupOperations,
    pub(crate) discovered_services: crate::device::DiscoveredServices,
    pub(crate) reconnect_owner: Mutex<Option<crate::connections::ReconnectLease>>,
    pub(crate) device_operations: Mutex<HashMap<String, tokio_util::sync::CancellationToken>>,
}

impl Runtime {
    pub async fn initialize(root: impl AsRef<Path>) -> CoreResult<Arc<Self>> {
        Self::initialize_with_connection_policy(root, crate::ConnectionPolicy::standalone()).await
    }

    pub async fn initialize_with_connection_policy(
        root: impl AsRef<Path>,
        connection_policy: crate::ConnectionPolicy,
    ) -> CoreResult<Arc<Self>> {
        Self::initialize_with_settings(root, connection_policy, json!({})).await
    }

    pub async fn initialize_with_settings(
        root: impl AsRef<Path>,
        connection_policy: crate::ConnectionPolicy,
        settings_defaults: Value,
    ) -> CoreResult<Arc<Self>> {
        connection_policy.validate()?;
        let settings_defaults =
            crate::preferences::validated_settings(&json!({}), &settings_defaults)?;
        let root = root.as_ref().to_path_buf();
        fs::create_dir_all(&root).await?;
        let root = fs::canonicalize(&root).await?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).await?;
        }
        let artifact_directory = root.join("bundled_servers");
        tokio::task::spawn_blocking(move || crate::bundled_servers::prepare(&artifact_directory))
            .await
            .map_err(|error| CoreError::new("server_integrity", error.to_string()))??;
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
        let fingerprint = hex::encode(Sha256::digest(identity.public_key("interop")?));
        let mut store = match fs::read(root.join("devices.json")).await {
            Ok(bytes) => serde_json::from_slice::<Store>(&bytes)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Store {
                version: 2,
                identity_fingerprint: fingerprint.clone(),
                device_identity_fingerprints: HashMap::new(),
                devices: Vec::new(),
                settings: settings_defaults.clone(),
            },
            Err(e) => return Err(e.into()),
        };
        if !matches!(store.version, 1 | 2) {
            return Err(CoreError::new(
                "storage_version",
                "设备记录版本较新，请更新应用。",
            ));
        }
        if store.version == 1 {
            crate::preferences::migrate_network_first_defaults(&mut store.settings);
            store.version = 2;
        }
        crate::preferences::remove_retired_settings(&mut store.settings);
        let settings = store
            .settings
            .as_object_mut()
            .ok_or_else(|| CoreError::new("invalid_data", "本机设置记录损坏。"))?;
        for (key, value) in settings_defaults.as_object().unwrap() {
            settings.entry(key.clone()).or_insert_with(|| value.clone());
        }
        let identity_changed = store.identity_fingerprint != fingerprint;
        store.identity_fingerprint = fingerprint;
        let (identities, changed_custom) =
            crate::host_identity::IdentityOwner::load(&root, identity, &mut store).await?;
        for device in &mut store.devices {
            let identity_changed = (identity_changed
                && !store.device_identity_fingerprints.contains_key(&device.id))
                || changed_custom.contains(&device.id);
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
        let events = crate::events::EventBus::new(256);
        let deliveries = crate::delivery::DeliveryJournal::open(&root).await?;
        let app_opens = crate::app_open::AppOpens::open(&root).await?;
        let media_cache = crate::media_cache::MediaCache::open(&root).await?;
        let transfer_root = root.clone();
        let transfer_store = tokio::task::spawn_blocking(move || {
            crate::transfer_store::TransferStore::open(&transfer_root)
        })
        .await
        .map_err(|error| CoreError::new("storage_error", error.to_string()))??;
        let (metadata_updates, metadata_requests) = tokio::sync::mpsc::channel(64);
        let metadata_lifetime = tokio_util::sync::CancellationToken::new();
        let runtime = Arc::new(Self {
            connection_policy,
            settings_defaults,
            root,
            identities,
            metadata_updates,
            _metadata_owner: metadata_lifetime.clone().drop_guard(),
            store: RwLock::new(store),
            connections: crate::connections::ConnectionOwner::default(),
            encoder_catalog: crate::encoder_catalog::EncoderCatalog::default(),
            events,
            persistence: Mutex::new(()),
            transfer_store: Mutex::new(transfer_store),
            activities: Arc::new(crate::activities::ActivityOwner::default()),
            companions: Mutex::new(HashMap::new()),
            observations: Mutex::new(HashMap::new()),
            observation_wakeup: Arc::new(tokio::sync::Notify::new()),
            searches: crate::file_search::Searches::default(),
            gallery_scans: crate::gallery_index::GalleryScans::default(),
            sharing: Mutex::new(None),
            documents: crate::documents::CopyManager::default(),
            deliveries,
            app_opens,
            quality_changes: Mutex::new(()),
            media: crate::media::http::MediaStreams::default(),
            media_cache,
            setup_operations: Default::default(),
            discovered_services: Default::default(),
            reconnect_owner: Mutex::new(None),
            device_operations: Mutex::new(HashMap::new()),
        });
        runtime.restore_transfers().await?;
        runtime.persist().await?;
        crate::device_metadata::spawn(&runtime, metadata_requests, metadata_lifetime);
        runtime.spawn_connection_monitor();
        runtime.spawn_observation_supervisor();
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
            .client(id)
            .await
            .ok_or_else(|| CoreError::new("disconnected", "设备尚未连接，请先恢复连接。"))
    }

    /// Thin boundary: the dispatch state machine is large, so it is boxed once
    /// here. Callers keep small frames on default test and FFI thread stacks.
    pub async fn invoke(self: &Arc<Self>, command: &str, params: Value) -> CoreResult<Value> {
        Box::pin(self.invoke_inner(command, params)).await
    }

    async fn invoke_inner(self: &Arc<Self>, command: &str, params: Value) -> CoreResult<Value> {
        if command.starts_with("media.cache.") {
            return self.cache_command(command, &params).await;
        }
        if command.starts_with("delivery.") {
            let _cache_gate = self.media_cache.gate.lock().await;
            if command == "delivery.begin" {
                self.cache_validate_delivery_locked(&params).await?;
            }
            return self.deliveries.command(command, &params).await;
        }
        if matches!(
            command,
            "media.open" | "media.status" | "media.close" | "media.trace.seal" | "media.trace.read"
        ) {
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
                        let published =
                            self.activities.transfers.lock().await.values().any(|task| {
                                task.direction == "push" && sources.contains(&task.source.as_str())
                            });
                        Err((error, !published))
                    }
                }
            }))
            .await;
        }
        if command.starts_with("identity.") {
            return self.identity_command(command, &params).await;
        }
        match command {
            command if command.starts_with("adb.") => {
                Box::pin(self.adb_command(command, &params)).await
            }
            "observation.start" | "observation.stop" | "observation.status"
            | "observation.list" => self.observation_command(command, &params).await,
            "state.snapshot" => Box::pin(self.state_snapshot()).await,
            "devices.list" => Ok(json!({"devices":self.projected_devices().await})),
            "devices.add" => Box::pin(self.add_device(&params)).await,
            "devices.connect" => {
                Box::pin(self.connect_device_with_attempt(
                    required(&params, "deviceId")?,
                    params["attemptId"].as_str(),
                    params["automatic"] == true,
                    params["ownerId"].as_str(),
                    params["candidateSource"].as_str(),
                    params["parentOperationId"].as_str(),
                ))
                .await
            }
            "devices.reconnect.owner" => self.reconnect_owner_command(&params).await,
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
            "devices.wake" => {
                Box::pin(self.wake_device(
                    required(&params, "deviceId")?,
                    params["connectionId"].as_str(),
                ))
                .await
            }
            "device.network.get" => self.device_network(&params).await,
            "device.screen.state" => self.device_screen_state(&params).await,
            "device.data.get" => self.device_data(&params).await,
            "apps.foreground" => self.device_foreground(&params).await,
            "devices.configure" => self.configure_device(&params).await,
            "device.info" => Ok(serde_json::to_value(
                self.device(required(&params, "deviceId")?).await?,
            )?),
            "files.list" => Box::pin(self.list_files(&params)).await,
            "files.search.start" | "files.search.get" | "files.search.cancel" => {
                self.file_search_command(command, &params).await
            }
            "files.mkdir" | "files.rename" | "files.delete" => {
                Box::pin(self.mutate_files(command, &params)).await
            }
            "files.pull" | "files.push" => Box::pin(self.start_transfer(command, params)).await,
            "transfers.remove" => Box::pin(self.remove_transfer_record(&params)).await,
            "transfers.list" => Box::pin(self.list_transfers()).await,
            "transfers.get" | "transfers.cancel" | "transfers.resume" | "transfers.resolve" => {
                Box::pin(self.transfer_command(command, &params)).await
            }
            "media.list" => Box::pin(self.list_media(&params)).await,
            "media.scan.cancel" => self.gallery_command(command, &params).await,
            "media.preview" => Box::pin(self.preview_media(&params)).await,
            "media.thumbnail" => Box::pin(self.thumbnail_media(&params)).await,
            "media.thumbnail.cancel" => Box::pin(self.cancel_thumbnail_media(&params)).await,
            "apps.list" if params["filter"] == "running" => {
                Box::pin(self.companion_command(command, &params)).await
            }
            "apps.icon" => Box::pin(self.companion_command(command, &params)).await,
            "apps.list" => match params.get("filter").and_then(Value::as_str) {
                None if params.get("filter").is_none() => Box::pin(self.list_apps(&params)).await,
                Some("installed") => Box::pin(self.list_apps(&params)).await,
                _ => Err(CoreError::new(
                    "invalid_argument",
                    "应用列表 filter 必须为 running 或 installed。",
                )),
            },
            "apps.launch" => Box::pin(self.launch_app(&params)).await,
            "session.start" => Box::pin(self.start_session(&params)).await,
            "session.stop"
            | "session.touch"
            | "session.key"
            | "session.text"
            | "session.screen"
            | "session.display"
            | "session.quality"
            | "session.reconfigure"
            | "session.screenshot"
            | "session.ready"
            | "session.clock.probe"
            | "session.frame"
            | "session.list"
            | "session.rotate"
            | "session.launch"
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
            | "calls.open"
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
