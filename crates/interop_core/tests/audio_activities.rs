//! Runtime activity behavior against an ADB wire peer. The peer accepts the
//! real server upload and exposes scrcpy's raw-audio handshake; it does not
//! assert Android capture or native playback support.
use interop_adb::protocol::{self, Frame};
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::broadcast,
};

struct Peer {
    port: u16,
    task: tokio::task::JoinHandle<()>,
}
impl Drop for Peer {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn send(socket: &mut TcpStream, command: u32, id: u32, payload: Vec<u8>) -> bool {
    Frame::new(command, id, id, payload)
        .write(socket)
        .await
        .is_ok()
}
impl Peer {
    async fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket.set_nodelay(true).unwrap();
            Frame::read(&mut socket, 1024 * 1024, false).await.unwrap();
            Frame::new(
                protocol::CNXN,
                protocol::VERSION,
                1024 * 1024,
                b"device::features=shell_v2;\0".to_vec(),
            )
            .write(&mut socket)
            .await
            .unwrap();
            let mut sync = HashMap::<u32, Vec<u8>>::new();
            let mut ending = HashSet::new();
            let mut media = HashMap::<String, (bool, usize)>::new();
            while let Ok(frame) = Frame::read(&mut socket, 1024 * 1024, true).await {
                let id = frame.arg0;
                if frame.command == protocol::OPEN {
                    let service = String::from_utf8(frame.payload).unwrap();
                    if !send(&mut socket, protocol::OKAY, id, vec![]).await {
                        return;
                    }
                    if service.starts_with("sync:") {
                        sync.insert(id, Vec::new());
                    } else if service.starts_with("shell") {
                        let mut reply = Vec::new();
                        if service.contains("getprop ro.product.model") {
                            let text = format!(
                                "Audio fixture\n15\n35\nfixture-{port}\nlevel: 80\nscale: 100\n"
                            );
                            reply.push(1);
                            reply.extend((text.len() as u32).to_le_bytes());
                            reply.extend(text.as_bytes());
                        } else if service.contains("dumpsys power") || service.contains("verified:")
                        {
                            let text = if service.contains("verified:") {
                                "verified:12345\n"
                            } else {
                                "Awake\n"
                            };
                            reply.push(1);
                            reply.extend((text.len() as u32).to_le_bytes());
                            reply.extend(text.as_bytes());
                        }
                        reply.extend([3, 1, 0, 0, 0, 0]);
                        if !send(&mut socket, protocol::WRTE, id, reply).await {
                            return;
                        }
                        ending.insert(id);
                    } else if service.starts_with("localabstract:scrcpy_") {
                        let (audio_only, opens) = media
                            .get_mut(service.trim_end_matches('\0'))
                            .expect("launched capture socket");
                        *opens += 1;
                        if !*audio_only && *opens > 1 {
                            continue; // The second connection is the control channel.
                        }
                        let mut audio = vec![0; 65];
                        audio.extend(if *audio_only {
                            [0, b'r', b'a', b'w']
                        } else {
                            *b"h264"
                        });
                        if !*audio_only {
                            audio.extend(0x8000_0000u32.to_be_bytes());
                            audio.extend(720u32.to_be_bytes());
                            audio.extend(1280u32.to_be_bytes());
                            audio.extend((1u64 << 61).to_be_bytes());
                            audio.extend(4u32.to_be_bytes());
                            audio.extend([0, 0, 0, 1]);
                            if !send(&mut socket, protocol::WRTE, id, audio).await {
                                return;
                            }
                            continue;
                        }
                        // A bounded PCM packet stays available for an actual
                        // output adapter; activity tests never fake audio.ready.
                        audio.extend(0u64.to_be_bytes());
                        audio.extend(4096u32.to_be_bytes());
                        audio.extend([0; 4096]);
                        if !send(&mut socket, protocol::WRTE, id, audio).await {
                            return;
                        }
                    } else {
                        assert!(service.starts_with("exec:run_owned() {"), "{service}");
                        assert!(service.contains("exec app_process /"), "{service}");
                        let scid = &service.split_once("scid=").unwrap().1[..8];
                        let audio_only = service.contains("video=false");
                        media.insert(format!("localabstract:scrcpy_{scid}"), (audio_only, 0));
                        if !audio_only
                            && !send(
                                &mut socket,
                                protocol::WRTE,
                                id,
                                b"__INTEROP_PID__123:12345\n".to_vec(),
                            )
                            .await
                        {
                            return;
                        }
                    }
                } else if frame.command == protocol::WRTE {
                    if !send(&mut socket, protocol::OKAY, id, vec![]).await {
                        return;
                    }
                    let buffer = sync.get_mut(&id).expect("only SYNC accepts input");
                    buffer.extend(frame.payload);
                    loop {
                        if buffer.len() < 8 {
                            break;
                        }
                        let done = &buffer[..4] == b"DONE";
                        let length = if done {
                            0
                        } else {
                            u32::from_le_bytes(buffer[4..8].try_into().unwrap()) as usize
                        };
                        if buffer.len() < 8 + length {
                            break;
                        }
                        assert!(matches!(&buffer[..4], b"SEND" | b"DATA" | b"DONE"));
                        buffer.drain(..8 + length);
                        if done
                            && !send(&mut socket, protocol::WRTE, id, b"OKAY\0\0\0\0".to_vec())
                                .await
                        {
                            return;
                        }
                    }
                } else if frame.command == protocol::OKAY && ending.remove(&frame.arg1) {
                    if !send(&mut socket, protocol::CLSE, id, vec![]).await {
                        return;
                    }
                } else if frame.command == protocol::CLSE {
                    sync.remove(&id);
                    if !send(&mut socket, protocol::CLSE, id, vec![]).await {
                        return;
                    }
                }
            }
        });
        Self { port, task }
    }
    async fn connect(&self, runtime: &Arc<Runtime>) -> String {
        let added = runtime
            .invoke(
                "devices.add",
                json!({"address":"127.0.0.1","port":self.port}),
            )
            .await
            .unwrap();
        let device = added["deviceId"].as_str().unwrap().to_owned();
        runtime
            .invoke("observation.stop", json!({"deviceId":device}))
            .await
            .unwrap();
        runtime
            .invoke("devices.connect", json!({"deviceId":device}))
            .await
            .unwrap();
        // Audio ownership requires an opened control session. This wire peer
        // models its process/video/control handshake without claiming decoding.
        runtime
            .invoke("session.start", json!({"deviceId":device}))
            .await
            .unwrap();
        device
    }
}
async fn source_event(
    events: &mut broadcast::Receiver<Value>,
    source: &Value,
    status: &str,
) -> Value {
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let event = events.recv().await.unwrap();
            if event["type"] == "audio.updated"
                && event["data"]["sourceId"] == source["sourceId"]
                && event["data"]["status"] == status
            {
                return event;
            }
        }
    })
    .await
    .expect("source lifecycle must refresh activities")
}

#[tokio::test]
async fn stopping_an_audio_activity_is_device_and_generation_exact() {
    let first_peer = Peer::start().await;
    let second_peer = Peer::start().await;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let first_device = first_peer.connect(&runtime).await;
    let second_device = second_peer.connect(&runtime).await;
    let mut events = runtime.subscribe();
    let first = runtime
        .invoke("audio.start", json!({"deviceId":first_device}))
        .await
        .unwrap();
    let second = runtime
        .invoke("audio.start", json!({"deviceId":second_device}))
        .await
        .unwrap();
    let activity_id = format!("audio:{}", first["sourceId"].as_str().unwrap());
    let list = runtime.invoke("activities.list", json!({})).await.unwrap();
    let activity = list["activities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["id"] == activity_id)
        .expect("a real Runtime audio source must appear as an activity");
    assert_eq!(activity["deviceId"], first_device);
    assert_eq!(activity["sourceId"], first["sourceId"]);
    assert_eq!(activity["status"], "starting");
    assert_eq!(activity["canStop"], true);
    assert!(activity["stopImpact"].as_str().unwrap().contains("仅停止"));
    assert_eq!(
        source_event(&mut events, &first, "starting").await["deviceId"],
        first_device
    );
    let observations = runtime.invoke("observation.list", json!({})).await.unwrap();
    let sessions = runtime.invoke("session.list", json!({})).await.unwrap();
    let stopped = runtime
        .invoke("activities.stop", json!({"activityId":activity_id}))
        .await
        .unwrap();
    assert_eq!(
        stopped,
        json!({"deviceId":first_device,"sourceId":first["sourceId"],"status":"stopped"})
    );
    source_event(&mut events, &first, "stopped").await;
    let remaining = runtime.invoke("audio.sources", json!({})).await.unwrap();
    assert_eq!(remaining["sources"].as_array().unwrap().len(), 1);
    assert_eq!(remaining["sources"][0]["sourceId"], second["sourceId"]);
    for device in [&first_device, &second_device] {
        assert_eq!(
            runtime
                .invoke("device.info", json!({"deviceId":device}))
                .await
                .unwrap()["status"],
            "connected"
        );
    }
    assert_eq!(
        runtime.invoke("observation.list", json!({})).await.unwrap(),
        observations
    );
    assert_eq!(
        runtime.invoke("session.list", json!({})).await.unwrap(),
        sessions
    );
    let replacement = runtime
        .invoke("audio.start", json!({"deviceId":first_device}))
        .await
        .unwrap();
    assert_ne!(replacement["sourceId"], first["sourceId"]);
    assert_eq!(
        runtime
            .invoke("activities.stop", json!({"activityId":activity_id}))
            .await
            .unwrap_err()
            .code,
        "not_found"
    );
    assert_eq!(
        runtime
            .invoke(
                "audio.stop",
                json!({"deviceId":first_device,"sourceId":first["sourceId"]})
            )
            .await
            .unwrap_err()
            .code,
        "source_changed"
    );
    let current = runtime.invoke("audio.sources", json!({})).await.unwrap();
    assert!(
        current["sources"]
            .as_array()
            .unwrap()
            .iter()
            .any(|source| source["sourceId"] == replacement["sourceId"])
    );
    assert!(
        current["sources"]
            .as_array()
            .unwrap()
            .iter()
            .any(|source| source["sourceId"] == second["sourceId"])
    );
    let replacement_id = format!("audio:{}", replacement["sourceId"].as_str().unwrap());
    assert_eq!(
        runtime
            .invoke("activities.stop", json!({"activityId":replacement_id}))
            .await
            .unwrap()["sourceId"],
        replacement["sourceId"]
    );
    assert_eq!(
        runtime
            .invoke(
                "audio.stop",
                json!({"deviceId":second_device,"sourceId":second["sourceId"]})
            )
            .await
            .unwrap()["sourceId"],
        second["sourceId"]
    );
}
