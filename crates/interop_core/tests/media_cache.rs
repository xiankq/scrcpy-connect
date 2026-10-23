use interop_adb::protocol::{self, Frame};
use interop_core::Runtime;
use serde_json::json;
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

#[tokio::test]
#[ignore = "requires an actual Android raw ADB endpoint and the configured companion artifact"]
async fn android_thumbnail_preview_and_original_have_real_file_leases_through_clear() {
    use base64::Engine as _;
    use interop_adb::{Client, ConnectOptions, Identity, OperationOptions, sync::RemotePath};
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .unwrap()
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let outgoing = root.path().join("outgoing");
    runtime
        .invoke(
            "media.cache.configure",
            json!({"outgoingDirectory":outgoing}),
        )
        .await
        .unwrap();
    let id = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_owned();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let identity = Identity::from_pem(
        &tokio::fs::read_to_string(root.path().join("host_identity.pem"))
            .await
            .unwrap(),
    )
    .unwrap();
    let client = Client::connect_tcp(
        endpoint,
        ConnectOptions {
            identity: Some(identity),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let path = format!("/data/local/tmp/interop-cache-{}.png", uuid::Uuid::new_v4());
    let png = base64::engine::general_purpose::STANDARD.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=").unwrap();
    client
        .sync(OperationOptions::default())
        .await
        .unwrap()
        .push(
            &RemotePath::new(&path).unwrap(),
            &mut std::io::Cursor::new(&png),
            0o644,
            0,
            1024,
        )
        .await
        .unwrap();
    let thumbnail = runtime
        .invoke(
            "media.thumbnail",
            json!({"deviceId":id,"path":path,"maxSize":128}),
        )
        .await
        .unwrap();
    let preview = runtime
        .invoke("media.preview", json!({"deviceId":id,"path":path}))
        .await
        .unwrap();
    let original_path = outgoing.join("original.png");
    let original_lease = pull_leased(&runtime, &id, &path, &original_path).await;
    let original = json!({"localPath":original_path});
    assert_eq!(
        tokio::fs::read(preview["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        png
    );
    assert_eq!(
        tokio::fs::read(original["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        png
    );
    let jpeg = tokio::fs::read(thumbnail["localPath"].as_str().unwrap())
        .await
        .unwrap();
    assert!(jpeg.starts_with(&[0xff, 0xd8]) && jpeg.ends_with(&[0xff, 0xd9]));
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        0
    );
    for content in [&thumbnail, &preview, &original] {
        assert!(std::path::Path::new(content["localPath"].as_str().unwrap()).is_file());
    }
    for lease in [
        &thumbnail["cacheLeaseId"],
        &preview["cacheLeaseId"],
        &json!(original_lease),
    ] {
        runtime
            .invoke("media.cache.release", json!({"leaseId":lease}))
            .await
            .unwrap();
    }
    let cleared = runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert_eq!(cleared["usedBytes"], 0);
    for content in [&thumbnail, &preview, &original] {
        assert!(!std::path::Path::new(content["localPath"].as_str().unwrap()).exists());
    }
    runtime
        .execute_file_mutation(&id, "delete", &path, "", false, false, Default::default())
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
}

struct Peer {
    port: u16,
    bytes: Arc<Mutex<Vec<u8>>>,
    paused: Arc<AtomicBool>,
    entered: Arc<tokio::sync::Notify>,
    resume: tokio::sync::mpsc::UnboundedSender<()>,
    task: tokio::task::JoinHandle<()>,
}
struct AbortOnDrop(tokio::task::JoinHandle<()>);
impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}
impl Drop for Peer {
    fn drop(&mut self) {
        self.task.abort();
    }
}
impl Peer {
    async fn start() -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let bytes = Arc::new(Mutex::new(b"real device bytes".to_vec()));
        let paused = Arc::new(AtomicBool::new(false));
        let pause = paused.clone();
        let entered = Arc::new(tokio::sync::Notify::new());
        let notify = entered.clone();
        let (resume, mut resumed) = tokio::sync::mpsc::unbounded_channel();
        let data = bytes.clone();
        let task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket.set_nodelay(true).unwrap();
            Frame::read(&mut socket, 1024 * 1024, false).await.unwrap();
            Frame::new(
                protocol::CNXN,
                protocol::VERSION,
                1024 * 1024,
                b"device::features=shell_v2,stat_v2;\0".to_vec(),
            )
            .write(&mut socket)
            .await
            .unwrap();
            let (mut input, mut socket) = socket.into_split();
            let (frames, mut received) = tokio::sync::mpsc::unbounded_channel();
            let _reader = AbortOnDrop(tokio::spawn(async move {
                while let Ok(frame) = Frame::read(&mut input, 1024 * 1024, true).await {
                    if frames.send(frame).is_err() {
                        break;
                    }
                }
            }));
            let mut pending = Vec::new();
            let mut services = HashMap::new();
            let mut ending = HashSet::new();
            loop {
                let frame = tokio::select! {
                    frame = received.recv() => match frame {Some(frame)=>frame,None=>break},
                    signal = resumed.recv() => {
                        if signal.is_none() { break; }
                        for (id,reply) in pending.drain(..) { Frame::new(protocol::WRTE,id,id,reply).write(&mut socket).await.unwrap(); }
                        continue;
                    }
                };
                let id = frame.arg0;
                if frame.command == protocol::OPEN {
                    let service = String::from_utf8(frame.payload)
                        .unwrap()
                        .trim_end_matches('\0')
                        .to_owned();
                    services.insert(id, service.clone());
                    Frame::new(protocol::OKAY, id, id, vec![])
                        .write(&mut socket)
                        .await
                        .unwrap();
                    if service.starts_with("shell") {
                        Frame::new(protocol::WRTE, id, id, vec![3, 1, 0, 0, 0, 0])
                            .write(&mut socket)
                            .await
                            .unwrap();
                        ending.insert(id);
                    }
                } else if frame.command == protocol::OKAY && ending.remove(&frame.arg1) {
                    Frame::new(protocol::CLSE, frame.arg1, id, vec![])
                        .write(&mut socket)
                        .await
                        .unwrap();
                } else if frame.command == protocol::WRTE {
                    Frame::new(protocol::OKAY, frame.arg1, id, vec![])
                        .write(&mut socket)
                        .await
                        .unwrap();
                    assert_eq!(services.get(&id).map(String::as_str), Some("sync:"));
                    let content = data.lock().unwrap().clone();
                    let mut reply = Vec::new();
                    match &frame.payload[..4] {
                        b"STA2" | b"LST2" => {
                            // This peer exercises cache ownership with modern
                            // metadata, independently of legacy helper deployment.
                            reply.extend(&frame.payload[..4]);
                            reply.extend(0u32.to_le_bytes()); // errno
                            reply.extend(1u64.to_le_bytes()); // device
                            reply.extend(1u64.to_le_bytes()); // inode
                            reply.extend(0o100644u32.to_le_bytes());
                            reply.extend(1u32.to_le_bytes()); // link count
                            reply.extend(2000u32.to_le_bytes()); // uid
                            reply.extend(2000u32.to_le_bytes()); // gid
                            reply.extend((content.len() as u64).to_le_bytes());
                            for _ in 0..3 {
                                reply.extend(10i64.to_le_bytes()); // atime, mtime, ctime
                            }
                        }
                        b"STAT" => {
                            reply.extend(b"STAT");
                            reply.extend(0o100644u32.to_le_bytes());
                            reply.extend((content.len() as u32).to_le_bytes());
                            reply.extend(10u32.to_le_bytes());
                        }
                        b"RECV" => {
                            reply.extend(b"DATA");
                            reply.extend((content.len() as u32).to_le_bytes());
                            reply.extend(content);
                            reply.extend(b"DONE\0\0\0\0");
                        }
                        request => panic!("unexpected sync request {request:?}"),
                    }
                    if frame.payload.starts_with(b"RECV") && pause.load(Ordering::SeqCst) {
                        pending.push((id, reply));
                        notify.notify_one();
                    } else {
                        Frame::new(protocol::WRTE, id, id, reply)
                            .write(&mut socket)
                            .await
                            .unwrap();
                    }
                } else if frame.command == protocol::CLSE {
                    services.remove(&id);
                    Frame::new(protocol::CLSE, frame.arg1, id, vec![])
                        .write(&mut socket)
                        .await
                        .unwrap();
                }
            }
        });
        Self {
            port,
            bytes,
            paused,
            entered,
            resume,
            task,
        }
    }
    async fn connect(&self, runtime: &Arc<Runtime>) -> String {
        let added = runtime
            .invoke(
                "devices.add",
                json!({"address":"127.0.0.1","port":self.port}),
            )
            .await
            .unwrap();
        let id = added["deviceId"].as_str().unwrap().to_owned();
        runtime
            .invoke("observation.stop", json!({"deviceId":id}))
            .await
            .unwrap();
        runtime
            .invoke("devices.connect", json!({"deviceId":id}))
            .await
            .unwrap();
        id
    }
}

#[tokio::test]
async fn in_flight_preview_reserves_bytes_without_blocking_status_or_clear() {
    let peer = Peer::start().await;
    peer.paused.store(true, Ordering::SeqCst);
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    runtime
        .invoke("media.cache.configure", json!({"budgetBytes":5000}))
        .await
        .unwrap();
    let job_runtime = runtime.clone();
    let job_id = id.clone();
    let job = tokio::spawn(async move {
        job_runtime
            .invoke(
                "media.preview",
                json!({"deviceId":job_id,"path":"/sdcard/a.jpg"}),
            )
            .await
    });
    tokio::time::timeout(std::time::Duration::from_secs(2), peer.entered.notified())
        .await
        .unwrap();
    let status = tokio::time::timeout(
        std::time::Duration::from_secs(1),
        runtime.invoke("media.cache.status", json!({})),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(status["reservedBytes"], 4113);
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        0
    );
    assert_eq!(
        runtime
            .invoke(
                "media.preview",
                json!({"deviceId":id,"path":"/sdcard/b.jpg"})
            )
            .await
            .unwrap_err()
            .code,
        "cache_budget_exceeded"
    );
    peer.paused.store(false, Ordering::SeqCst);
    peer.resume.send(()).unwrap();
    let preview = job.await.unwrap().unwrap();
    assert_eq!(
        tokio::fs::read(preview["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        b"real device bytes"
    );
    assert_eq!(
        runtime
            .invoke("media.cache.status", json!({}))
            .await
            .unwrap()["reservedBytes"],
        0
    );
}

#[tokio::test]
async fn preview_returns_owned_real_file_and_budget_rejects_while_all_bytes_are_leased() {
    let peer = Peer::start().await;
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    let preview = runtime
        .invoke(
            "media.preview",
            json!({"deviceId":id,"path":"/sdcard/a.jpg"}),
        )
        .await
        .unwrap();
    let path = preview["localPath"].as_str().unwrap();
    assert_eq!(tokio::fs::read(path).await.unwrap(), b"real device bytes");
    assert!(uuid::Uuid::parse_str(preview["cacheLeaseId"].as_str().unwrap()).is_ok());
    let used = runtime
        .invoke("media.cache.status", json!({}))
        .await
        .unwrap()["usedBytes"]
        .as_u64()
        .unwrap();
    runtime
        .invoke("media.cache.configure", json!({"budgetBytes":used}))
        .await
        .unwrap();
    let clear = runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert!(std::path::Path::new(path).exists());
    assert!(clear["protectedBytes"].as_u64().unwrap() >= 17);
    assert_eq!(
        runtime
            .invoke(
                "media.preview",
                json!({"deviceId":id,"path":"/sdcard/b.jpg"})
            )
            .await
            .unwrap_err()
            .code,
        "cache_budget_exceeded"
    );
    runtime
        .invoke(
            "media.cache.release",
            json!({"leaseId":preview["cacheLeaseId"]}),
        )
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke(
                "media.cache.release",
                json!({"leaseId":preview["cacheLeaseId"]})
            )
            .await
            .unwrap()["released"],
        false
    );
    let clear = runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert!(clear["deletedBytes"].as_u64().unwrap() >= 17);
    assert!(!std::path::Path::new(path).exists());
    assert_eq!(
        runtime
            .invoke("media.cache.status", json!({}))
            .await
            .unwrap()["usedBytes"],
        0
    );
}

#[tokio::test]
async fn changed_preview_source_never_replaces_a_file_still_owned_by_a_consumer() {
    let peer = Peer::start().await;
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    let first = runtime
        .invoke(
            "media.preview",
            json!({"deviceId":id,"path":"/sdcard/a.jpg"}),
        )
        .await
        .unwrap();
    *peer.bytes.lock().unwrap() = b"updated device bytes with different size".to_vec();
    let next = runtime
        .invoke(
            "media.preview",
            json!({"deviceId":id,"path":"/sdcard/a.jpg"}),
        )
        .await
        .unwrap();
    assert_ne!(first["localPath"], next["localPath"]);
    assert_eq!(
        tokio::fs::read(first["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        b"real device bytes"
    );
    assert_eq!(
        tokio::fs::read(next["localPath"].as_str().unwrap())
            .await
            .unwrap(),
        b"updated device bytes with different size"
    );
    runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert!(std::path::Path::new(first["localPath"].as_str().unwrap()).exists());
    assert!(std::path::Path::new(next["localPath"].as_str().unwrap()).exists());
}

async fn pull_leased(
    runtime: &Arc<Runtime>,
    device: &str,
    source: &str,
    destination: &std::path::Path,
) -> String {
    let stamp = runtime
        .execute_file_stat(device, source, false, false, Default::default())
        .await
        .unwrap();
    let part = destination.with_extension("part");
    let paths = vec![
        destination.to_string_lossy().into_owned(),
        part.to_string_lossy().into_owned(),
    ];
    let lease = runtime
        .execute_file_cache_reserve(paths, vec![0, stamp.size])
        .await
        .unwrap();
    runtime
        .execute_file_copy(
            device,
            source,
            part.to_str().unwrap(),
            false,
            stamp,
            Default::default(),
            Arc::new(std::sync::atomic::AtomicU64::new(0)),
        )
        .await
        .unwrap();
    runtime
        .execute_file_mutation(
            device,
            "commit",
            part.to_str().unwrap(),
            destination.to_str().unwrap(),
            true,
            false,
            Default::default(),
        )
        .await
        .unwrap();
    lease
}

#[tokio::test]
async fn real_private_pull_lease_spans_publish_and_eviction_removes_export_capability() {
    let peer = Peer::start().await;
    let root = tempfile::tempdir().unwrap();
    let outgoing = root.path().join("outgoing");
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    runtime
        .invoke(
            "media.cache.configure",
            json!({"outgoingDirectory":outgoing}),
        )
        .await
        .unwrap();
    let id = peer.connect(&runtime).await;
    let destination = outgoing.join("first.bin");
    let lease = pull_leased(&runtime, &id, "/sdcard/a.jpg", &destination).await;
    assert_eq!(
        tokio::fs::read(&destination).await.unwrap(),
        b"real device bytes"
    );
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        0
    );
    runtime
        .invoke("media.cache.configure", json!({"budgetBytes":17}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .execute_file_cache_reserve(
                vec![outgoing.join("other.bin").to_string_lossy().into_owned()],
                vec![17]
            )
            .await
            .unwrap_err()
            .code,
        "cache_budget_exceeded"
    );
    runtime
        .invoke("media.cache.release", json!({"leaseId":lease}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        17
    );
    // Export capability is derived by Dart from the native filesystem fact.
    assert!(!destination.exists());
}

#[tokio::test]
async fn cache_budget_counts_only_managed_roots_and_clear_preserves_delivery_and_share_ownership() {
    let root = tempfile::tempdir().unwrap();
    let outgoing_parent = tempfile::tempdir().unwrap();
    let outgoing = outgoing_parent.path().join("outgoing");
    tokio::fs::create_dir_all(&outgoing).await.unwrap();
    tokio::fs::create_dir_all(root.path().join("media/thumbnails"))
        .await
        .unwrap();
    tokio::fs::write(root.path().join("media/reclaimable.bin"), b"12345")
        .await
        .unwrap();
    let shared = root.path().join("media/thumbnails/shared.jpg");
    tokio::fs::write(&shared, b"1234567").await.unwrap();
    let saving = outgoing.join("saving.bin");
    tokio::fs::write(&saving, b"12345678901").await.unwrap();
    tokio::fs::write(root.path().join("not-cache.bin"), b"do not delete")
        .await
        .unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let configured = runtime
        .invoke(
            "media.cache.configure",
            json!({"outgoingDirectory":outgoing,"budgetBytes":1024}),
        )
        .await
        .unwrap();
    assert_eq!(configured["usedBytes"], 23);
    runtime
        .invoke("media.cache.retain", json!({"localPath":shared}))
        .await
        .unwrap();
    runtime.invoke("delivery.begin", json!({"operationId":"save-1","sourceId":"source","kind":"file","name":"saving.bin","localPath":saving})).await.unwrap();
    let cleared = runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert_eq!(cleared["deletedBytes"], 5);
    assert_eq!(cleared["protectedBytes"], 18);
    assert_eq!(cleared["reclaimableBytes"], 0);
    assert_eq!(tokio::fs::read(&saving).await.unwrap(), b"12345678901");
    drop(runtime);
    let reopened = Runtime::initialize(root.path()).await.unwrap();
    let status = reopened
        .invoke("media.cache.status", json!({}))
        .await
        .unwrap();
    assert_eq!(status["budgetBytes"], 1024);
    assert_eq!(status["usedBytes"], 18);
    assert_eq!(status["protectedBytes"], 18);
    assert_eq!(status["retainedShareCount"], 1);
    assert!(root.path().join("not-cache.bin").exists());
}

#[tokio::test]
async fn batch_reservations_count_subtree_growth_and_reject_overlaps_atomically() {
    let root = tempfile::tempdir().unwrap();
    let media = root.path().join("media");
    let tree = media.join("tree");
    let nested = tree.join("nested");
    std::fs::create_dir_all(&nested).unwrap();
    std::fs::write(tree.join("existing"), b"1234").unwrap();
    let sibling = media.join("tree-copy");
    std::fs::write(&sibling, b"12").unwrap();
    std::fs::write(media.join("reclaimable"), b"12345").unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let part = media.join("new.part");
    let lease = runtime
        .execute_file_cache_reserve(
            [&tree, &nested, &part, &sibling]
                .map(|p| p.to_string_lossy().into_owned())
                .to_vec(),
            vec![10, 0, 8, 0],
        )
        .await
        .unwrap();
    let status = runtime
        .invoke("media.cache.status", json!({}))
        .await
        .unwrap();
    assert_eq!(status["usedBytes"], 11);
    assert_eq!(status["reservedBytes"], 18);
    assert_eq!(status["protectedBytes"], 6);
    std::fs::write(nested.join("growth"), b"123456").unwrap();
    std::fs::write(&part, b"123").unwrap();
    let status = runtime
        .invoke("media.cache.status", json!({}))
        .await
        .unwrap();
    assert_eq!(status["usedBytes"], 20);
    assert_eq!(status["reservedBytes"], 9);
    assert_eq!(status["protectedBytes"], 15);

    let free = media.join("free");
    assert_eq!(
        runtime
            .execute_file_cache_reserve(
                vec![
                    free.to_string_lossy().into_owned(),
                    nested.join("conflict").to_string_lossy().into_owned()
                ],
                vec![2, 0],
            )
            .await
            .unwrap_err()
            .code,
        "cache_in_use"
    );
    // The rejected batch must not leave its earlier, non-conflicting path owned.
    let free_lease = runtime
        .execute_file_cache_reserve(vec![free.to_string_lossy().into_owned()], vec![2])
        .await
        .unwrap();
    runtime
        .execute_file_cache_release(&free_lease)
        .await
        .unwrap();
    let cleared = runtime
        .invoke("media.cache.clear", json!({}))
        .await
        .unwrap();
    assert_eq!(cleared["deletedBytes"], 5);
    assert_eq!(cleared["usedBytes"], 15);
    assert_eq!(cleared["reservedBytes"], 9);
    runtime.execute_file_cache_release(&lease).await.unwrap();
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        15
    );
}

#[tokio::test]
async fn admission_evicts_oldest_files_and_never_treats_sibling_prefixes_as_protected() {
    let root = tempfile::tempdir().unwrap();
    let media = root.path().join("media");
    std::fs::create_dir(&media).unwrap();
    // Create in reverse age order so directory traversal cannot choose victims.
    let mut paths = Vec::new();
    for (name, age) in [("tree-copy", 30), ("middle", 20), ("oldest", 10)] {
        let path = media.join(name);
        std::fs::write(&path, b"12345").unwrap();
        std::fs::OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(
                std::fs::FileTimes::new()
                    .set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(age)),
            )
            .unwrap();
        paths.push(path);
    }
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    runtime
        .invoke("media.cache.configure", json!({"budgetBytes":15}))
        .await
        .unwrap();
    let lease = runtime
        .execute_file_cache_reserve(
            vec![media.join("tree").to_string_lossy().into_owned()],
            vec![6],
        )
        .await
        .unwrap();
    assert!(paths[0].exists());
    assert!(!paths[1].exists());
    assert!(!paths[2].exists());
    let status = runtime
        .invoke("media.cache.status", json!({}))
        .await
        .unwrap();
    assert_eq!(status["usedBytes"], 5);
    assert_eq!(status["reservedBytes"], 6);
    assert_eq!(status["protectedBytes"], 0);
    assert_eq!(
        runtime
            .invoke("media.cache.clear", json!({}))
            .await
            .unwrap()["deletedBytes"],
        5
    );
    runtime.execute_file_cache_release(&lease).await.unwrap();
}
