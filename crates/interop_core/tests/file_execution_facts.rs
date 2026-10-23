#[path = "support/gallery_adbd.rs"]
mod gallery_adbd;
use interop_core::Runtime;
use serde_json::json;
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

#[tokio::test]
async fn lists_raw_names_and_wide_metadata_and_does_not_follow_child_links() {
    let peer = Peer::start().await;
    {
        let mut data = peer.files.lock().unwrap();
        data.media("/sdcard/large.mp4", 19);
        data.nodes.get_mut("/sdcard/large.mp4").unwrap().size = (1u64 << 32) + 19;
        data.raw_root_names.push(b"bad\xff.jpg".to_vec());
        data.nodes.insert(
            "/sdcard/link".into(),
            Node {
                mode: 0o120777,
                modified: 1,
                size: 3,
            },
        );
    }
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    let facts = runtime
        .execute_file_list(&id, "/sdcard", false, 100, Default::default())
        .await
        .unwrap();
    assert!(facts.entries.iter().any(|e| e.name == b"bad\xff.jpg"));
    assert_eq!(
        facts
            .entries
            .iter()
            .find(|e| e.name == b"large.mp4")
            .unwrap()
            .stamp
            .as_ref()
            .unwrap()
            .size,
        (1u64 << 32) + 19
    );
    assert_eq!(
        facts
            .entries
            .iter()
            .find(|e| e.name == b"link")
            .unwrap()
            .stamp
            .as_ref()
            .unwrap()
            .mode
            & 0o170000,
        0o120000
    );
    assert_eq!(
        runtime
            .execute_file_list(&id, "/sdcard/link", false, 100, Default::default())
            .await
            .err()
            .unwrap()
            .code,
        "not_directory"
    );
}

#[tokio::test]
async fn directory_listing_distinguishes_masked_permission_denial_from_empty_and_detects_changes() {
    let peer = Peer::start().await;
    {
        let mut data = peer.files.lock().unwrap();
        data.directory("/sdcard/denied");
        data.denied.insert("/sdcard/denied".into());
        data.directory("/sdcard/empty");
    }
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    assert_eq!(
        runtime
            .execute_file_list(&id, "/sdcard/denied", false, 100, Default::default())
            .await
            .err()
            .unwrap()
            .code,
        "permission_denied"
    );
    assert!(
        runtime
            .execute_file_list(&id, "/sdcard/empty", false, 100, Default::default())
            .await
            .unwrap()
            .entries
            .is_empty()
    );
    peer.files
        .lock()
        .unwrap()
        .changed_on_list
        .insert("/sdcard".into());
    assert_eq!(
        runtime
            .execute_file_list(&id, "/sdcard", false, 100, Default::default())
            .await
            .err()
            .unwrap()
            .code,
        "source_changed"
    );
}

#[tokio::test]
async fn legacy_storage_alias_uses_verified_wide_metadata_and_bounded_listing() {
    let peer = Peer::start().await;
    {
        let mut data = peer.files.lock().unwrap();
        data.legacy_root_alias = true;
        for i in 0..12 {
            data.media(&format!("/sdcard/{i}.jpg"), 10);
        }
    }
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    assert_eq!(
        runtime
            .execute_file_stat(&id, "/sdcard", false, true, Default::default())
            .await
            .unwrap()
            .mode
            & 0o170000,
        0o040000
    );
    let facts = runtime
        .execute_file_list(&id, "/sdcard", false, 5, Default::default())
        .await
        .unwrap();
    assert_eq!(facts.entries.len(), 5);
    assert!(facts.truncated);

    let mutate = |action| {
        runtime.execute_file_mutation(
            &id,
            action,
            "/sdcard/created",
            "",
            false,
            false,
            Default::default(),
        )
    };
    mutate("mkdir").await.unwrap();
    assert!(
        peer.files
            .lock()
            .unwrap()
            .nodes
            .contains_key("/sdcard/created")
    );
    assert_eq!(mutate("mkdir").await.unwrap_err().code, "remote_failed");
    mutate("delete").await.unwrap();
    assert!(
        !peer
            .files
            .lock()
            .unwrap()
            .nodes
            .contains_key("/sdcard/created")
    );
}

#[tokio::test]
async fn cancelled_listing_never_waits_for_a_blocked_device_and_local_links_are_not_directories() {
    let peer = Peer::start().await;
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let id = peer.connect(&runtime).await;
    peer.files.lock().unwrap().blocked = true;
    let cancellation = interop_adb::CancellationToken::new();
    let token = cancellation.clone();
    let next = runtime.clone();
    let worker = tokio::spawn(async move {
        next.execute_file_list(&id, "/sdcard", false, 100, token)
            .await
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    cancellation.cancel();
    assert!(
        tokio::time::timeout(Duration::from_secs(2), worker)
            .await
            .unwrap()
            .unwrap()
            .is_err()
    );
    #[cfg(unix)]
    {
        let link = root.path().join("link");
        std::os::unix::fs::symlink(root.path(), &link).unwrap();
        assert_eq!(
            runtime
                .execute_file_list("", link.to_str().unwrap(), true, 100, Default::default())
                .await
                .err()
                .unwrap()
                .code,
            "not_directory"
        );
    }
}
