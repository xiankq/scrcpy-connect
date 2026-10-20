//! Optional device information never holds transport admission open. Jobs are
//! bounded and may publish only to the exact connection that requested them.
use crate::Runtime;
use interop_adb::{Client, OperationOptions};
use serde_json::json;
use std::{
    sync::{Arc, Weak},
    time::Duration,
};
use tokio::{sync::mpsc, task::JoinSet};
use tokio_util::sync::CancellationToken;

pub(crate) struct Request {
    pub(crate) id: String,
    pub(crate) client: Client,
}

pub(crate) fn spawn(
    runtime: &Arc<Runtime>,
    mut requests: mpsc::Receiver<Request>,
    lifetime: CancellationToken,
) {
    let runtime = Arc::downgrade(runtime);
    tokio::spawn(async move {
        let mut jobs = JoinSet::new();
        loop {
            tokio::select! {
                biased;
                _ = lifetime.cancelled() => break,
                request = requests.recv(), if jobs.len() < 4 => {
                    let Some(request) = request else { break; };
                    let runtime = runtime.clone();
                    jobs.spawn(refresh(runtime, request));
                }
                _ = jobs.join_next(), if !jobs.is_empty() => {}
            }
        }
        // Runtime owns the only sender. Its release aborts any queued or
        // in-flight optional requests instead of keeping device owners alive.
    });
}

fn battery(bytes: &[u8]) -> Option<u32> {
    let text = std::str::from_utf8(bytes).ok()?;
    let number = |key: &str| {
        text.lines()
            .find_map(|line| line.trim().strip_prefix(key)?.trim().parse::<u32>().ok())
    };
    let level = number("level:")?;
    let scale = number("scale:").filter(|scale| *scale > 0)?;
    Some((u64::from(level) * 100 / u64::from(scale)).min(100) as u32)
}

async fn refresh(runtime: Weak<Runtime>, request: Request) {
    if runtime.strong_count() == 0 {
        return;
    }
    let Ok(output) = request
        .client
        .shell(
            "dumpsys battery",
            64 * 1024,
            OperationOptions {
                timeout: Duration::from_secs(3),
                ..Default::default()
            },
        )
        .await
    else {
        return;
    };
    if output.exit_code.is_some_and(|code| code != 0) {
        return;
    }
    let Some(battery) = battery(&output.stdout) else {
        return;
    };
    let Some(runtime) = runtime.upgrade() else {
        return;
    };
    {
        // Match connection publication's lock order. A delayed reply from a
        // disconnected or replaced transport cannot update its replacement.
        let mut store = runtime.store.write().await;
        let connections = runtime.connections.lock().await;
        if !connections
            .get(&request.id)
            .is_some_and(|client| !client.is_closed() && client.same_connection(&request.client))
        {
            return;
        }
        let Some(device) = store
            .devices
            .iter_mut()
            .find(|device| device.id == request.id && device.status == "connected")
        else {
            return;
        };
        if device.battery == Some(battery) {
            return;
        }
        device.battery = Some(battery);
        runtime.emit("device.changed", Some(&request.id), json!(device));
    }
    let _ = runtime.persist().await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    use tokio::{io::DuplexStream, sync::oneshot};

    fn connection() -> (Client, DuplexStream) {
        let (transport, peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::features=shell_v2;\0".into(),
                features: ["shell_v2".into()].into(),
            },
        )
        .unwrap();
        (client, peer)
    }

    #[tokio::test]
    async fn late_battery_cannot_update_a_replaced_or_offline_device() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let added = runtime
            .add_device(&json!({"address":"127.0.0.1", "port":5555, "transport":"tcp"}))
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        for replace in [true, false] {
            let (client, mut peer) = connection();
            runtime
                .connections
                .lock()
                .await
                .insert(id.clone(), client.clone());
            {
                let mut store = runtime.store.write().await;
                let device = store
                    .devices
                    .iter_mut()
                    .find(|device| device.id == id)
                    .unwrap();
                device.status = "connected".into();
                device.battery = Some(42);
                device.observation_wanted = false;
            }
            let (started, observed) = oneshot::channel();
            let (release, ready) = oneshot::channel();
            let server = tokio::spawn(async move {
                let frame = Frame::read(&mut peer, 4096, true).await.unwrap();
                assert_eq!(frame.command, protocol::OPEN);
                assert!(String::from_utf8_lossy(&frame.payload).contains("dumpsys battery"));
                Frame::new(protocol::OKAY, 100, frame.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
                started.send(()).unwrap();
                ready.await.unwrap();
                let text = b"level: 99\nscale: 100\n";
                let mut reply = vec![1];
                reply.extend_from_slice(&(text.len() as u32).to_le_bytes());
                reply.extend_from_slice(text);
                reply.extend_from_slice(&[3, 1, 0, 0, 0, 0]);
                Frame::new(protocol::WRTE, 100, frame.arg0, reply)
                    .write(&mut peer)
                    .await
                    .unwrap();
                // Keep this transport alive until refresh has checked ownership.
                while Frame::read(&mut peer, 4096, true).await.is_ok() {}
            });
            let refresh = tokio::spawn(super::refresh(
                Arc::downgrade(&runtime),
                Request {
                    id: id.clone(),
                    client,
                },
            ));
            observed.await.unwrap();
            let (_replacement, _replacement_peer) = if replace {
                let (replacement, peer) = connection();
                runtime
                    .connections
                    .lock()
                    .await
                    .insert(id.clone(), replacement.clone());
                (Some(replacement), Some(peer))
            } else {
                runtime
                    .store
                    .write()
                    .await
                    .devices
                    .iter_mut()
                    .find(|device| device.id == id)
                    .unwrap()
                    .status = "offline".into();
                (None, None)
            };
            release.send(()).unwrap();
            tokio::time::timeout(Duration::from_secs(1), refresh)
                .await
                .unwrap()
                .unwrap();
            assert_eq!(runtime.device(&id).await.unwrap().battery, Some(42));
            runtime.connections.lock().await.remove(&id);
            server.abort();
        }
        runtime.stop_all().await;
    }

    #[tokio::test]
    async fn runtime_release_aborts_running_and_queued_queries() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Runtime::initialize(directory.path()).await.unwrap();
        let mut peers = Vec::new();
        for _ in 0..5 {
            let (client, peer) = connection();
            assert!(
                runtime
                    .metadata_updates
                    .try_send(Request {
                        id: "device".into(),
                        client
                    })
                    .is_ok()
            );
            peers.push(peer);
        }
        // Saturate all four workers with peers that never finish the shell.
        for peer in &mut peers[..4] {
            let frame = tokio::time::timeout(Duration::from_secs(1), Frame::read(peer, 4096, true))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(frame.command, protocol::OPEN);
        }
        let weak = Arc::downgrade(&runtime);
        drop(runtime);
        tokio::time::timeout(Duration::from_secs(1), async {
            while weak.strong_count() != 0 {
                tokio::task::yield_now().await;
            }
            for peer in &mut peers {
                while let Ok(frame) = Frame::read(peer, 4096, true).await {
                    assert_eq!(
                        frame.command,
                        protocol::CLSE,
                        "no queued query may start after Runtime release"
                    );
                }
            }
        })
        .await
        .expect("Runtime release must abort optional work, including its queued clients");
    }
}
