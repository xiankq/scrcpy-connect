use super::*;
use interop_adb::{
    DeviceInfo,
    protocol::{self, Frame},
};

async fn request(runtime: &Arc<Runtime>, command: &str, params: Value) -> CoreResult<Value> {
    Box::pin(runtime.invoke(command, params)).await
}
async fn session(runtime: &Runtime, command: &str, params: &Value) -> CoreResult<Value> {
    Box::pin(runtime.session_command(command, params)).await
}

#[derive(Default)]
struct Evidence {
    launches: Vec<String>,
    closed_controls: usize,
    controls: Vec<u32>,
    fail_release_verification: bool,
    release_verifications: Vec<String>,
}
struct Fixture {
    _root: tempfile::TempDir,
    runtime: Arc<Runtime>,
    client: interop_adb::Client,
    device: String,
    evidence: Arc<std::sync::Mutex<Evidence>>,
    server: tokio::task::JoinHandle<()>,
}
impl Fixture {
    async fn new() -> Self {
        Box::pin(Self::configured(None, Some(0))).await
    }
    async fn configured(existing: Option<Arc<Runtime>>, dummy: Option<u8>) -> Self {
        let root = tempfile::tempdir().unwrap();
        let runtime = match existing {
            Some(runtime) => runtime,
            None => Box::pin(Runtime::initialize(root.path())).await.unwrap(),
        };
        let device = uuid::Uuid::new_v4().to_string();
        runtime.store.write().await.devices.push(serde_json::from_value(json!({"id":device,"name":"fixture","address":"fixture","port":5555,"transport":"tcp","status":"connected","apiLevel":35,"observationWanted":false})).unwrap());
        let (transport, mut peer) = tokio::io::duplex(256 * 1024);
        let client = interop_adb::Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 64 * 1024,
                banner: "device::keep-active-fixture".into(),
                features: HashSet::new(),
            },
        )
        .unwrap();
        runtime
            .connections
            .lock()
            .await
            .insert(device.clone(), client.clone());
        let evidence = Arc::new(std::sync::Mutex::new(Evidence::default()));
        let observed = evidence.clone();
        let server = tokio::spawn(async move {
            let mut syncs = HashMap::<u32, Vec<u8>>::new();
            while let Ok(frame) = Frame::read(&mut peer, 64 * 1024, true).await {
                let local = frame.arg0;
                let remote = local + 100;
                match frame.command {
                    protocol::OPEN => {
                        let service = String::from_utf8(frame.payload).unwrap();
                        Frame::new(protocol::OKAY, remote, local, vec![])
                            .write(&mut peer)
                            .await
                            .unwrap();
                        let reply = if service.starts_with("sync:") {
                            syncs.insert(local, vec![]);
                            None
                        } else if service.starts_with("localabstract:scrcpy_") {
                            observed.lock().unwrap().controls.push(local);
                            dummy.map(|dummy| (vec![dummy], false))
                        } else if service.contains("__INTEROP_PID__") {
                            observed.lock().unwrap().launches.push(service);
                            Some((b"__INTEROP_PID__321:456\n".to_vec(), false))
                        } else if service.contains("__KEEP_ACTIVE_RELEASED__") {
                            let mut evidence = observed.lock().unwrap();
                            evidence.release_verifications.push(service);
                            Some((
                                if evidence.fail_release_verification {
                                    b"still-running\n".to_vec()
                                } else {
                                    b"__KEEP_ACTIVE_RELEASED__\n".to_vec()
                                },
                                true,
                            ))
                        } else if service.contains("identity-mismatch") {
                            Some((b"verified:S\n".to_vec(), true))
                        } else if service.contains("rm -f --") {
                            Some((vec![], true))
                        } else {
                            panic!("unexpected service {service}")
                        };
                        if let Some((bytes, close)) = reply {
                            if !bytes.is_empty() {
                                Frame::new(protocol::WRTE, remote, local, bytes)
                                    .write(&mut peer)
                                    .await
                                    .unwrap();
                            }
                            if close {
                                Frame::new(protocol::CLSE, remote, local, vec![])
                                    .write(&mut peer)
                                    .await
                                    .unwrap();
                            }
                        }
                    }
                    protocol::WRTE => {
                        let local = frame.arg0;
                        let remote = local + 100;
                        Frame::new(protocol::OKAY, remote, local, vec![])
                            .write(&mut peer)
                            .await
                            .unwrap();
                        if let Some(bytes) = syncs.get_mut(&local) {
                            bytes.extend_from_slice(&frame.payload);
                            while bytes.len() >= 8 {
                                let word =
                                    u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
                                if &bytes[..4] == b"DONE" {
                                    bytes.drain(..8);
                                    Frame::new(
                                        protocol::WRTE,
                                        remote,
                                        local,
                                        b"OKAY\0\0\0\0".to_vec(),
                                    )
                                    .write(&mut peer)
                                    .await
                                    .unwrap();
                                } else {
                                    if bytes.len() < 8 + word {
                                        break;
                                    }
                                    bytes.drain(..8 + word);
                                }
                            }
                        }
                    }
                    protocol::CLSE => {
                        let local = frame.arg0;
                        if observed.lock().unwrap().controls.contains(&local) {
                            observed.lock().unwrap().closed_controls += 1;
                        }
                        syncs.remove(&local);
                        Frame::new(protocol::CLSE, local + 100, local, vec![])
                            .write(&mut peer)
                            .await
                            .unwrap();
                    }
                    protocol::OKAY => {}
                    _ => panic!("unexpected ADB command"),
                }
            }
        });
        Self {
            _root: root,
            runtime,
            client,
            device,
            evidence,
            server,
        }
    }
    async fn window(&self, id: &str, package: Option<&str>, paused: bool) {
        let (control, _requests) = mpsc::channel(1);
        self.runtime.activities.sessions.lock().await.insert(id.into(),Session {
            device_id:self.device.clone(),package:package.map(str::to_owned),cancellation:CancellationToken::new(),lifetime:CancellationToken::new(),control,
            state:Arc::new(RwLock::new(json!({"sessionId":id,"deviceId":self.device,"status":if paused {"paused"} else {"streaming"},"textureId":5,"captureGeneration":1,"taskId":79,"keepActive":false}))),process_closed:Arc::new(AtomicBool::new(true)),process:None,
        });
    }
    async fn setting(&self, enabled: bool) -> CoreResult<Value> {
        let mut settings = self.runtime.store.read().await.settings["deviceSettings"].clone();
        if !settings.is_object() {
            settings = json!({});
        }
        settings[&self.device] = json!({"stayAwake":enabled});
        request(
            &self.runtime,
            "settings.update",
            json!({"deviceSettings":settings}),
        )
        .await
    }
    async fn state(&self, id: &str) -> Value {
        self.runtime.activities.sessions.lock().await[id]
            .state
            .read()
            .await
            .clone()
    }
}

#[tokio::test]
async fn last_close_reports_unconfirmed_keep_active_release_without_reviving_the_window() {
    let fixture = Fixture::new().await;
    fixture.window("A", None, true).await;
    fixture.setting(true).await.unwrap();
    let original = fixture.state("A").await;
    fixture.evidence.lock().unwrap().fail_release_verification = true;
    let mut events = fixture.runtime.events.subscribe();
    let closed = session(&fixture.runtime, "session.stop", &json!({"sessionId":"A"}))
        .await
        .unwrap();
    assert_eq!(
        closed["status"], "stopped",
        "the logical window really closed"
    );
    assert_eq!(
        closed["keepActiveCleanup"]["cleanupConfirmed"], false,
        "a failed target PID/start verification must not masquerade as released"
    );
    assert_eq!(
        closed["keepActiveCleanup"]["leaseId"],
        original["keepActiveLeaseId"]
    );
    assert_eq!(
        closed["keepActiveCleanup"]["pid"],
        original["keepActivePid"]
    );
    assert!(fixture.runtime.activities.sessions.lock().await.is_empty());
    let retained = fixture
        .runtime
        .activities
        .keep_active
        .device(&fixture.device)
        .await;
    assert_eq!(
        retained.lease.lock().await.as_ref().unwrap().id,
        original["keepActiveLeaseId"].as_str().unwrap()
    );
    let mut observed = Vec::new();
    while let Ok(event) = events.try_recv() {
        observed.push(event);
    }
    assert!(
        observed
            .iter()
            .any(|event| event["type"] == "device.keep_active.updated"
                && event["deviceId"] == fixture.device
                && event["data"]["cleanupConfirmed"] == false
                && event["data"]["leaseId"] == original["keepActiveLeaseId"])
    );
    {
        let evidence = fixture.evidence.lock().unwrap();
        assert_eq!(evidence.closed_controls, 1);
        assert_eq!(evidence.launches.len(), 1);
        assert!(
            evidence
                .release_verifications
                .iter()
                .all(|command| command.contains("p=321")
                    && command.contains("456")
                    && !command.contains("kill -"))
        );
    }
    fixture.evidence.lock().unwrap().fail_release_verification = false;
    let released = stop_unowned(
        &fixture.runtime.activities,
        &fixture.runtime.events,
        &fixture.device,
    )
    .await
    .unwrap();
    assert_eq!(released["cleanupConfirmed"], true);
    assert_eq!(released["leaseId"], original["keepActiveLeaseId"]);
    assert!(retained.lease.lock().await.is_none());
    assert!(fixture.runtime.activities.sessions.lock().await.is_empty());
    assert_eq!(
        fixture.evidence.lock().unwrap().launches.len(),
        1,
        "rechecking retained release must not create a new helper or window"
    );
}

#[tokio::test]
async fn successful_retry_explicitly_clears_the_previous_keep_active_error() {
    let fixture = Fixture::new().await;
    fixture.window("A", None, true).await;
    fixture.setting(true).await.unwrap();
    fixture.evidence.lock().unwrap().fail_release_verification = true;
    assert_eq!(
        fixture.setting(false).await.unwrap_err().code,
        "keep_active_partial"
    );
    assert_eq!(
        fixture.state("A").await["keepActiveError"]["code"],
        "keep_active_cleanup"
    );
    fixture.evidence.lock().unwrap().fail_release_verification = false;
    let mut events = fixture.runtime.events.subscribe();
    fixture.setting(true).await.unwrap();
    let state = fixture.state("A").await;
    assert_eq!(
        state.get("keepActiveError"),
        Some(&Value::Null),
        "merged UI state needs an explicit null to clear an old error"
    );
    assert_eq!(state["keepActiveApplied"], true);
    assert_eq!(state["captureGeneration"], 1);
    assert_eq!(state["textureId"], 5);
    let mut cleared = false;
    while let Ok(event) = events.try_recv() {
        if event["type"] == "session.updated"
            && event["data"]["sessionId"] == "A"
            && event["data"].get("keepActiveError") == Some(&Value::Null)
        {
            cleared = true;
        }
    }
    assert!(cleared);
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.client.close();
        self.server.abort();
    }
}

#[tokio::test]
async fn device_setting_updates_all_existing_windows_and_last_close_releases_one_control_lease() {
    let fixture = Fixture::new().await;
    fixture.window("A", None, true).await;
    fixture.setting(true).await.unwrap();
    assert_eq!(
        fixture.evidence.lock().unwrap().launches.len(),
        1,
        "enabling on an existing paused window must start the actual control-only server"
    );
    let first = fixture.state("A").await;
    assert_eq!(first["keepActive"], true);
    assert_eq!(first["keepActiveLeaseActive"], true);
    let lease = first["keepActiveLeaseId"].clone();
    fixture
        .window("B", Some("com.android.settings"), false)
        .await;
    fixture
        .runtime
        .sync_keep_active(&fixture.device, Some(false))
        .await
        .unwrap();
    assert_eq!(fixture.evidence.lock().unwrap().launches.len(), 1);
    assert_eq!(fixture.state("B").await["keepActiveLeaseId"], lease);
    session(&fixture.runtime, "session.stop", &json!({"sessionId":"B"}))
        .await
        .unwrap();
    assert_eq!(
        fixture.evidence.lock().unwrap().closed_controls,
        0,
        "A still owns device keep-active after B closes"
    );
    assert_eq!(fixture.state("A").await["captureGeneration"], 1);
    fixture.setting(false).await.unwrap();
    assert_eq!(fixture.evidence.lock().unwrap().closed_controls, 1);
    assert_eq!(fixture.state("A").await["keepActive"], false);
    fixture.setting(true).await.unwrap();
    assert_eq!(fixture.evidence.lock().unwrap().launches.len(), 2);
    session(&fixture.runtime, "session.stop", &json!({"sessionId":"A"}))
        .await
        .unwrap();
    assert_eq!(fixture.evidence.lock().unwrap().closed_controls, 2);
    let commands = &fixture.evidence.lock().unwrap().launches;
    for command in commands {
        for option in [
            "video=false",
            "audio=false",
            "control=true",
            "display_id=0",
            "keep_active=true",
            "power_on=false",
            "power_off_on_close=false",
            "clipboard_autosync=false",
            "send_device_meta=false",
        ] {
            assert!(command.contains(option), "missing {option}");
        }
        for forbidden in [
            "video=true",
            "audio=true",
            "power_on=true",
            "power_off_on_close=true",
            "new_display=",
            "start_app=",
            "wm size",
            "input keyevent",
        ] {
            assert!(!command.contains(forbidden), "side effect {forbidden}");
        }
    }
}

#[tokio::test]
async fn malformed_control_handshake_reports_saved_failure_without_claiming_keep_active() {
    let fixture = Box::pin(Fixture::configured(None, Some(255))).await;
    fixture.window("A", None, false).await;
    let error = fixture.setting(true).await.unwrap_err();
    assert_eq!(error.code, "keep_active_partial");
    assert_eq!(error.details["failures"][0]["code"], "keep_active_protocol");
    assert_eq!(
        error.details["failures"][0]["details"]["keepActiveError"]["code"],
        "keep_active_protocol"
    );
    assert_eq!(error.details["saved"], true);
    let state = fixture.state("A").await;
    assert_eq!(state["keepActive"], true);
    assert_eq!(state["keepActiveApplied"], false);
    assert_eq!(state["keepActiveLeaseActive"], false);
    assert_eq!(
        state["textureId"], 5,
        "failed keep-active must preserve the real output"
    );
}

#[tokio::test]
async fn closing_the_last_window_cancels_a_pending_control_handshake() {
    let fixture = Box::pin(Fixture::configured(None, None)).await;
    fixture.window("A", None, false).await;
    let runtime = fixture.runtime.clone();
    let device = fixture.device.clone();
    let changing = tokio::spawn(async move {
        request(
            &runtime,
            "settings.update",
            json!({"deviceSettings":{device:{"stayAwake":true}}}),
        )
        .await
    });
    tokio::time::timeout(Duration::from_secs(3), async {
        while fixture.evidence.lock().unwrap().controls.is_empty() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    // The real control socket was accepted but no dummy byte was supplied.
    // Explicit close must cancel startup rather than waiting its 12s timeout.
    tokio::time::timeout(
        Duration::from_secs(1),
        session(&fixture.runtime, "session.stop", &json!({"sessionId":"A"})),
    )
    .await
    .unwrap()
    .unwrap();
    let error = tokio::time::timeout(Duration::from_secs(1), changing)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    assert_eq!(error.code, "keep_active_partial");
    assert_eq!(error.details["failures"][0]["code"], "cancelled");
    assert!(fixture.runtime.activities.sessions.lock().await.is_empty());
    assert_eq!(fixture.evidence.lock().unwrap().closed_controls, 1);
}

#[tokio::test]
async fn unrelated_settings_and_capture_replacement_preserve_the_lease_and_other_devices() {
    let a = Fixture::new().await;
    let b = Box::pin(Fixture::configured(Some(a.runtime.clone()), Some(0))).await;
    a.window("A", None, true).await;
    b.window("B", Some("com.android.settings"), false).await;
    a.setting(true).await.unwrap();
    b.setting(true).await.unwrap();
    let lease_a = a.state("A").await["keepActiveLeaseId"].clone();
    let lease_b = b.state("B").await["keepActiveLeaseId"].clone();
    request(&a.runtime, "settings.update", json!({"maxFps":30}))
        .await
        .unwrap();
    {
        let sessions = a.runtime.activities.sessions.lock().await;
        let session = &sessions["A"];
        let mut state = session.state.write().await;
        state["qualityRebuilding"] = json!(true);
        state["qualityRetryable"] = json!(true);
        session.cancellation.cancel();
    }
    // A quality capture gap retains the existing logical window lifetime.
    stop_unowned(&a.runtime.activities, &a.runtime.events, &a.device)
        .await
        .unwrap();
    assert_eq!(a.evidence.lock().unwrap().closed_controls, 0);
    a.runtime.sync_keep_active(&a.device, None).await.unwrap();
    assert_eq!(a.state("A").await["keepActiveLeaseId"], lease_a);
    assert_eq!(a.evidence.lock().unwrap().launches.len(), 1);
    a.setting(false).await.unwrap();
    assert_eq!(a.evidence.lock().unwrap().closed_controls, 1);
    assert_eq!(b.evidence.lock().unwrap().closed_controls, 0);
    assert_eq!(b.state("B").await["keepActiveLeaseId"], lease_b);
    session(&a.runtime, "session.stop", &json!({"sessionId":"A"}))
        .await
        .unwrap();
    session(&a.runtime, "session.stop", &json!({"sessionId":"B"}))
        .await
        .unwrap();
    assert_eq!(b.evidence.lock().unwrap().closed_controls, 1);
}

#[tokio::test]
async fn retired_connection_cleanup_cannot_cancel_the_replacement_connection_lease() {
    let a = Fixture::new().await;
    a.window("A", None, false).await;
    a.setting(true).await.unwrap();
    let old = a.state("A").await["keepActiveLeaseId"].clone();
    let mut replacement = Box::pin(Fixture::configured(Some(a.runtime.clone()), Some(0))).await;
    replacement.device = a.device.clone();
    a.runtime
        .connections
        .lock()
        .await
        .insert(a.device.clone(), replacement.client.clone());
    // The old raw/control streams end while the per-device replacement obtains
    // its new lease. Its delayed monitor must match leaseId, not just deviceId.
    a.client.close();
    let receipt = a.runtime.sync_keep_active(&a.device, None).await.unwrap();
    assert_ne!(receipt["keepActiveLeaseId"], old);
    assert_eq!(
        receipt["keepActiveConnectionId"],
        replacement.client.connection_id().to_string()
    );
    for _ in 0..10 {
        tokio::task::yield_now().await;
    }
    assert_eq!(a.state("A").await["keepActiveLeaseActive"], true);
    assert_eq!(a.state("A").await["keepActiveApplied"], true);
    assert_eq!(replacement.evidence.lock().unwrap().closed_controls, 0);
    session(&a.runtime, "session.stop", &json!({"sessionId":"A"}))
        .await
        .unwrap();
    assert_eq!(replacement.evidence.lock().unwrap().closed_controls, 1);
}

#[tokio::test]
async fn disabling_the_setting_cancels_a_pending_control_handshake() {
    let fixture = Box::pin(Fixture::configured(None, None)).await;
    fixture.window("A", None, true).await;
    let runtime = fixture.runtime.clone();
    let device = fixture.device.clone();
    let enabling = tokio::spawn(async move {
        request(
            &runtime,
            "settings.update",
            json!({"deviceSettings":{device:{"stayAwake":true}}}),
        )
        .await
    });
    tokio::time::timeout(Duration::from_secs(3), async {
        while fixture.evidence.lock().unwrap().controls.is_empty() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    tokio::time::timeout(Duration::from_secs(1), fixture.setting(false))
        .await
        .unwrap()
        .unwrap();
    let error = tokio::time::timeout(Duration::from_secs(1), enabling)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    assert_eq!(error.details["failures"][0]["code"], "cancelled");
    assert_eq!(fixture.state("A").await["keepActive"], false);
    assert_eq!(fixture.state("A").await["keepActiveLeaseActive"], false);
    assert_eq!(fixture.evidence.lock().unwrap().closed_controls, 1);
}
