#[path = "support/gallery_adbd.rs"]
mod gallery_adbd;
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, HashSet},
    sync::{Arc, Mutex},
    time::Duration,
};

#[derive(Clone)]
struct Node {
    mode: u32,
    modified: u32,
    size: u64,
}
#[derive(Default)]
struct DeviceFiles {
    nodes: BTreeMap<String, Node>,
    denied: HashSet<String>,
    blocked: bool,
    changed_on_list: HashSet<String>,
    raw_root_names: Vec<Vec<u8>>,
    legacy_root_alias: bool,
    list_failures: HashSet<String>,
    fallback_metadata_failure: bool,
}
impl DeviceFiles {
    fn directory(&mut self, path: &str) {
        self.nodes.insert(
            path.into(),
            Node {
                mode: 0o40755,
                modified: 10,
                size: 123,
            },
        );
    }
    fn media(&mut self, path: &str, modified: u32) {
        self.nodes.insert(
            path.into(),
            Node {
                mode: 0o100644,
                modified,
                size: 123,
            },
        );
    }
}
struct Peer {
    files: Arc<Mutex<DeviceFiles>>,
    port: u16,
    task: tokio::task::JoinHandle<()>,
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
        let files = Arc::new(Mutex::new(DeviceFiles::default()));
        files.lock().unwrap().directory("/sdcard");
        let data = files.clone();
        let task = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let _ = gallery_adbd::serve(socket, data).await;
        });
        Self { files, port, task }
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
async fn finished(runtime: &Arc<Runtime>, device: &str, scan: &str, limit: u64) -> Value {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let page = runtime
                .invoke(
                    "media.list",
                    json!({"deviceId":device,"scanId":scan,"limit":limit}),
                )
                .await
                .unwrap();
            if page["status"] != "scanning" {
                return page;
            }
            assert_eq!(page["items"], json!([]));
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("bounded fixture scan")
}

#[tokio::test]
async fn gallery_validates_pages_and_reports_expired_scans_before_connecting() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for page in [
        json!({"limit":0}),
        json!({"limit":201}),
        json!({"offset":-1}),
        json!({"limit":"1"}),
    ] {
        let mut params = page;
        params["deviceId"] = json!("offline");
        assert_eq!(
            runtime.invoke("media.list", params).await.unwrap_err().code,
            "invalid_argument"
        );
    }
    for command in ["media.list", "media.scan.cancel"] {
        assert_eq!(
            runtime
                .invoke(command, json!({"deviceId":"offline","scanId":"expired"}))
                .await
                .unwrap_err()
                .code,
            "media_scan_not_found"
        );
    }
}

#[tokio::test]
async fn gallery_discovers_download_custom_root_and_android_media_with_stable_pages() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        for path in [
            "/sdcard/Download",
            "/sdcard/Custom",
            "/sdcard/Android",
            "/sdcard/Android/media",
            "/sdcard/Android/data",
            "/sdcard/Android/obb",
        ] {
            files.directory(path);
        }
        files.media("/sdcard/root.jpg", 30);
        files.media("/sdcard/Download/a.mp4", 20);
        files.media("/sdcard/Custom/z.png", 20);
        files.media("/sdcard/Android/media/chat.jpg", 20);
        files.media("/sdcard/Android/data/private.jpg", 99);
        files.media("/sdcard/Android/obb/private.mp4", 99);
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let receipt = runtime
        .invoke("media.list", json!({"deviceId":device,"limit":2}))
        .await
        .unwrap();
    assert_eq!(receipt["status"], "scanning");
    assert_eq!(receipt["items"], json!([]));
    let scan = receipt["scanId"].as_str().unwrap();
    let page = finished(&runtime, &device, scan, 2).await;
    assert_eq!(page["status"], "completed", "{page}");
    assert_eq!(page["complete"], true);
    assert_eq!(page["total"], 4);
    assert_eq!(page["nextOffset"], 2);
    assert_eq!(page["scope"]["roots"], json!(["/sdcard"]));
    assert_eq!(page["items"][0]["path"], "/sdcard/root.jpg");
    assert_eq!(page["items"][0]["size"], 123);
    assert_eq!(page["items"][0]["modified"], 30);
    assert_eq!(page["items"][1]["path"], "/sdcard/Android/media/chat.jpg");
    let last = runtime
        .invoke(
            "media.list",
            json!({"deviceId":device,"scanId":scan,"offset":2,"limit":2}),
        )
        .await
        .unwrap();
    assert_eq!(last["items"][0]["path"], "/sdcard/Custom/z.png");
    assert_eq!(last["items"][1]["path"], "/sdcard/Download/a.mp4");
    assert!(last["nextOffset"].is_null());
    {
        let mut files = peer.files.lock().unwrap();
        files.nodes.remove("/sdcard/root.jpg");
        files.media("/sdcard/new.jpg", 100);
    }
    let fresh = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_ne!(fresh["scanId"], receipt["scanId"]);
    let updated = finished(&runtime, &device, fresh["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(updated["items"][0]["path"], "/sdcard/new.jpg");
    assert_eq!(
        runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":scan,"limit":2})
            )
            .await
            .unwrap(),
        page
    );
    assert_eq!(
        runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":scan,"offset":2,"limit":2})
            )
            .await
            .unwrap(),
        last
    );
}

#[tokio::test]
async fn gallery_keeps_accessible_media_when_adbd_masks_permission_denial_as_empty_done() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        files.media("/sdcard/visible.jpg", 20);
        files.directory("/sdcard/Private");
        files.denied.insert("/sdcard/Private".into());
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let receipt = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, receipt["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "partial");
    assert_eq!(page["complete"], false);
    assert_eq!(page["total"], 1);
    assert_eq!(page["items"][0]["path"], "/sdcard/visible.jpg");
    assert_eq!(
        page["issues"],
        json!([{"path":"/sdcard/Private","code":"permission_denied","reason":"无权读取或遍历此目录，扫描结果不完整。"}])
    );
}

#[tokio::test]
async fn gallery_cancels_exact_scans_and_bounds_active_and_retained_snapshots() {
    let peer = Peer::start().await;
    peer.files.lock().unwrap().blocked = true;
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let first = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let second = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let id = first["scanId"].as_str().unwrap();
    assert_eq!(
        runtime
            .invoke("media.list", json!({"deviceId":device}))
            .await
            .unwrap_err()
            .code,
        "media_scan_busy"
    );
    for command in ["media.list", "media.scan.cancel"] {
        assert_eq!(
            runtime
                .invoke(command, json!({"deviceId":"another","scanId":id}))
                .await
                .unwrap_err()
                .code,
            "media_scan_device_mismatch"
        );
    }
    let cancelled = runtime
        .invoke("media.scan.cancel", json!({"deviceId":device,"scanId":id}))
        .await
        .unwrap();
    assert_eq!(cancelled["status"], "cancelled");
    assert_eq!(cancelled["complete"], false);
    assert_eq!(
        runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":second["scanId"]})
            )
            .await
            .unwrap()["status"],
        "scanning"
    );
    let third = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    runtime
        .invoke(
            "media.scan.cancel",
            json!({"deviceId":device,"scanId":second["scanId"]}),
        )
        .await
        .unwrap();
    runtime
        .invoke(
            "media.scan.cancel",
            json!({"deviceId":device,"scanId":third["scanId"]}),
        )
        .await
        .unwrap();
    // Completing further independent scans evicts the oldest terminal snapshots.
    peer.files.lock().unwrap().blocked = false;
    for _ in 0..8 {
        let scan = runtime
            .invoke("media.list", json!({"deviceId":device}))
            .await
            .unwrap();
        assert_eq!(
            finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await["status"],
            "completed"
        );
    }
    assert_eq!(
        runtime
            .invoke("media.list", json!({"deviceId":device,"scanId":id}))
            .await
            .unwrap_err()
            .code,
        "media_scan_not_found"
    );
    peer.files.lock().unwrap().blocked = true;
    let scanning = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":device}))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":scanning["scanId"]})
            )
            .await
            .unwrap()["status"],
        "cancelled"
    );
}

#[tokio::test]
async fn gallery_marks_source_changes_and_invalid_names_partial_without_unsafe_paths() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        files.media("/sdcard/visible.jpg", 20);
        files.raw_root_names.push(b"bad\xff.jpg".to_vec());
        files.changed_on_list.insert("/sdcard".into());
        files.nodes.insert(
            "/sdcard/link".into(),
            Node {
                mode: 0o120777,
                modified: 10,
                size: 123,
            },
        );
        files.media("/sdcard/link/hidden.jpg", 100);
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "partial");
    assert_eq!(page["items"].as_array().unwrap().len(), 1);
    assert_eq!(page["items"][0]["path"], "/sdcard/visible.jpg");
    assert_eq!(page["issueCount"], 2);
    assert!(
        page["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "invalid_filename")
    );
    assert!(
        page["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "source_changed")
    );
}

#[tokio::test]
async fn gallery_reports_directory_entry_limit_instead_of_complete_empty_gallery() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        for n in 0..4097 {
            files.media(&format!("/sdcard/{n:04}.jpg"), 10);
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "partial");
    assert_eq!(page["complete"], false);
    assert_eq!(page["truncated"], true);
    assert_eq!(
        page["total"], 4096,
        "overflow must retain the accessible bounded prefix"
    );
    assert_eq!(page["items"][0]["path"], "/sdcard/0000.jpg");
    assert!(
        page["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "entry_limit")
    );
}

#[tokio::test]
async fn gallery_counts_entries_from_overflowing_directories_against_the_global_budget() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        for directory in 0..13 {
            let path = format!("/sdcard/{directory:02}");
            files.directory(&path);
            for entry in 0..4097 {
                files.media(&format!("{path}/{entry:04}.txt"), 10);
            }
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "partial");
    assert_eq!(page["visitedEntries"], 50_000);
}

#[tokio::test]
async fn gallery_follows_only_the_standard_sdcard_alias_on_legacy_adbd() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        files.legacy_root_alias = true;
        files.media("/sdcard/root.jpg", 10);
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "completed");
    assert_eq!(page["items"][0]["path"], "/sdcard/root.jpg");
}

#[tokio::test]
async fn gallery_uses_native_wide_metadata_instead_of_truncated_legacy_sync_sizes() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        files.legacy_root_alias = true;
        files.media("/sdcard/large.mp4", 10);
        files.nodes.get_mut("/sdcard/large.mp4").unwrap().size = (1u64 << 32) + 19;
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "completed", "{page}");
    assert_eq!(page["items"][0]["path"], "/sdcard/large.mp4");
    // The legacy STAT/DENT fixture truncates this to 19 on the wire. Only the
    // verified native helper can recover the actual size on this connection.
    assert_eq!(page["items"][0]["size"], 4_294_967_315u64);
}

#[tokio::test]
async fn gallery_counts_failed_fallback_metadata_toward_the_global_entry_limit() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        files.fallback_metadata_failure = true;
        for directory in 0..13 {
            let path = format!("/sdcard/{directory:02}");
            files.directory(&path);
            files.list_failures.insert(path.clone());
            for entry in 0..4097 {
                files.media(&format!("{path}/{entry:04}.txt"), 10);
            }
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let page = finished(&runtime, &device, scan["scanId"].as_str().unwrap(), 100).await;
    assert_eq!(page["status"], "partial");
    assert_eq!(page["visitedEntries"], 50_000);
    assert!(page["issueCount"].as_u64().unwrap() > 128);
    assert!(page["issues"].as_array().unwrap().len() <= 128);
}

#[tokio::test]
async fn gallery_bounds_retained_snapshot_bytes_including_long_media_and_issue_paths() {
    let peer = Peer::start().await;
    {
        let mut files = peer.files.lock().unwrap();
        let mut root = "/sdcard".to_owned();
        for component in ['a', 'b', 'c'] {
            root.push('/');
            root.push_str(&component.to_string().repeat(220));
            files.directory(&root);
        }
        // Exactly 64 retained issues makes the budget marker grow the issue
        // allocation from 64 slots to 128 slots at the byte limit.
        for n in 0..64 {
            let path = format!("{root}/z-denied-{n:03}-{}", "d".repeat(200));
            files.directory(&path);
            files.denied.insert(path);
        }
        for directory in 0..8 {
            let path = format!("{root}/photos-{directory:02}");
            files.directory(&path);
            for entry in 0..1500 {
                files.media(
                    &format!("{path}/image-{entry:04}-{}.jpg", "x".repeat(220)),
                    10,
                );
            }
        }
    }
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = peer.connect(&runtime).await;
    let scan = runtime
        .invoke("media.list", json!({"deviceId":device}))
        .await
        .unwrap();
    let id = scan["scanId"].as_str().unwrap();
    let page = finished(&runtime, &device, id, 200).await;
    assert_eq!(page["snapshotByteLimit"], 8_388_608);
    assert_eq!(page["status"], "partial");
    assert_eq!(page["truncated"], true);
    assert!(page["snapshotBytes"].as_u64().unwrap() <= 8_388_608);
    let total = page["total"].as_u64().unwrap();
    assert!((1000..12000).contains(&total));
    assert!(
        page["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "snapshot_byte_limit")
    );
    assert_eq!(page["issueCount"], 65);
    assert_eq!(page["issues"].as_array().unwrap().len(), 65);
    assert!(
        page["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "permission_denied")
    );
    let mut string_bytes = 0usize;
    for issue in page["issues"].as_array().unwrap() {
        for key in ["path", "code", "reason"] {
            string_bytes += issue[key].as_str().unwrap().len();
        }
    }
    let mut offset = 0;
    loop {
        let part = runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":id,"offset":offset,"limit":200}),
            )
            .await
            .unwrap();
        assert_eq!(part["snapshotBytes"], page["snapshotBytes"]);
        for item in part["items"].as_array().unwrap() {
            string_bytes +=
                item["path"].as_str().unwrap().len() + item["name"].as_str().unwrap().len();
        }
        match part["nextOffset"].as_u64() {
            Some(next) => offset = next,
            None => break,
        }
    }
    assert!(page["snapshotBytes"].as_u64().unwrap() >= string_bytes as u64);
    assert_eq!(
        runtime
            .invoke(
                "media.list",
                json!({"deviceId":device,"scanId":id,"limit":200})
            )
            .await
            .unwrap(),
        page
    );
}
