use interop_adb::{Client, ConnectOptions, Identity, OperationOptions, sync::RemotePath};
use interop_core::Runtime;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};

async fn settled(runtime: &Arc<Runtime>, device: &str, search: &Value) -> Value {
    tokio::time::timeout(Duration::from_secs(35), async {
        loop {
            let snapshot = runtime
                .invoke(
                    "files.search.get",
                    json!({"deviceId":device,"searchId":search["searchId"]}),
                )
                .await
                .unwrap();
            if snapshot["status"] != "running" {
                return snapshot;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
#[ignore = "requires actual Android adbd whose root Sync listing needs the SELinux fallback"]
async fn filesystem_root_search_preserves_absolute_root_in_directory_fallback() {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .unwrap()
        .parse()
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let search = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":"/","query":"sdcard","filter":"all"}),
        )
        .await
        .unwrap();
    let observed = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let snapshot = runtime
                .invoke(
                    "files.search.get",
                    json!({"deviceId":id,"searchId":search["searchId"]}),
                )
                .await
                .unwrap();
            if snapshot["entries"]
                .as_array()
                .unwrap()
                .iter()
                .any(|entry| entry["path"] == "/sdcard")
                || snapshot["status"] != "running"
            {
                return snapshot;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    runtime
        .invoke(
            "files.search.cancel",
            json!({"deviceId":id,"searchId":search["searchId"]}),
        )
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(observed["path"], "/");
    assert!(
        observed["entries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|entry| entry["path"] == "/sdcard"),
        "{observed}"
    );
}

#[tokio::test]
#[ignore = "requires an actual Android raw ADB endpoint"]
async fn bounded_search_finds_distinct_paths_and_never_traverses_links() {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .unwrap()
        .parse()
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let device = runtime
        .invoke(
            "devices.add",
            json!({"address":endpoint.ip().to_string(),"port":endpoint.port()}),
        )
        .await
        .unwrap();
    let id = device["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let identity = Identity::from_pem(
        &tokio::fs::read_to_string(directory.path().join("host_identity.pem"))
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
    let root = format!("/data/local/tmp/interop-search-{}", uuid::Uuid::new_v4());
    let fixture = client.shell(&format!("mkdir -p '{root}/a' '{root}/b' '{root}/outside'; ln -s '{root}/outside' '{root}/a/link' && print -nr -- created"), 4096, OperationOptions::default()).await.unwrap();
    assert_eq!(fixture.stdout, b"created");
    let mut sync = client.sync(OperationOptions::default()).await.unwrap();
    for name in [
        "a/中文 ' REPORT.JPG",
        "b/中文 ' REPORT.JPG",
        "outside/hidden.txt",
        "a/note.txt",
        "a/line\n'break.txt",
        "a/Straße.txt",
    ] {
        sync.push(
            &RemotePath::new(format!("{root}/{name}")).unwrap(),
            &mut std::io::Cursor::new(b"fixture"),
            0o600,
            0,
            1024,
        )
        .await
        .unwrap();
    }
    let started = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":format!("{root}/a"),"query":"report","filter":"all"}),
        )
        .await
        .unwrap();
    assert_eq!(started["status"], "running");
    let done = settled(&runtime, id, &started).await;
    assert_eq!(done["status"], "completed", "{done}");
    assert_eq!(done["entries"].as_array().unwrap().len(), 1, "{done}");
    assert_eq!(done["visitedDirectories"], 1, "links must not be traversed");
    let started = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":root,"query":"中文 '","filter":"images"}),
        )
        .await
        .unwrap();
    let done = settled(&runtime, id, &started).await;
    assert_eq!(done["status"], "completed", "{done}");
    let entries = done["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 2, "{done}");
    assert_ne!(entries[0]["path"], entries[1]["path"]);
    for query in ["line\n'break", "STRASSE"] {
        let search = runtime.invoke("files.search.start", json!({"deviceId":id,"path":format!("{root}/a"),"query":query,"filter":"documents"})).await.unwrap();
        let done = settled(&runtime, id, &search).await;
        assert_eq!(done["status"], "completed", "{done}");
        assert_eq!(done["entries"].as_array().unwrap().len(), 1, "{done}");
    }
    let link = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":format!("{root}/a/link"),"query":"hidden","filter":"all"}),
        )
        .await
        .unwrap();
    let rejected = settled(&runtime, id, &link).await;
    assert_eq!(rejected["status"], "failed", "{rejected}");
    assert_eq!(rejected["complete"], false);
    assert_eq!(rejected["entries"].as_array().unwrap().len(), 0);
    let first = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":root,"query":"note","filter":"all"}),
        )
        .await
        .unwrap();
    let other = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":root,"query":"report","filter":"all"}),
        )
        .await
        .unwrap();
    let wrong = runtime
        .invoke(
            "files.search.cancel",
            json!({"deviceId":"different-device","searchId":first["searchId"]}),
        )
        .await
        .unwrap_err();
    assert_eq!(wrong.code, "search_device_mismatch");
    let cancelled = runtime
        .invoke(
            "files.search.cancel",
            json!({"deviceId":id,"searchId":first["searchId"]}),
        )
        .await
        .unwrap();
    assert_eq!(cancelled["status"], "cancelled");
    assert_eq!(settled(&runtime, id, &first).await["status"], "cancelled");
    assert_eq!(settled(&runtime, id, &other).await["status"], "completed");
    assert_eq!(
        runtime
            .invoke(
                "files.search.cancel",
                json!({"deviceId":id,"searchId":first["searchId"]})
            )
            .await
            .unwrap()["status"],
        "cancelled"
    );
    // Raw non-UTF8 names must never alias a valid replacement-character path.
    sync.push(
        &RemotePath::new([root.as_bytes(), b"/a/\xff.JPG"].concat()).unwrap(),
        &mut std::io::Cursor::new(b"raw"),
        0o600,
        0,
        1024,
    )
    .await
    .unwrap();
    let invalid = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":format!("{root}/a"),"query":"","filter":"images"}),
        )
        .await
        .unwrap();
    let partial = settled(&runtime, id, &invalid).await;
    assert_eq!(partial["status"], "partial", "{partial}");
    assert_eq!(partial["entries"].as_array().unwrap().len(), 1);
    assert!(
        partial["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "invalid_filename")
    );
    assert!(
        partial["entries"]
            .as_array()
            .unwrap()
            .iter()
            .all(|entry| !entry["path"].as_str().unwrap().contains('�'))
    );
    let setup = client.shell(&format!("mkdir '{root}/many'; n=0; while [ \"$n\" -le 500 ]; do : > '{root}/many'/match-$n.txt; n=$((n+1)); done; print -nr -- created"), 4096, OperationOptions::default()).await.unwrap();
    assert_eq!(setup.stdout, b"created");
    let limited = runtime.invoke("files.search.start", json!({"deviceId":id,"path":format!("{root}/many"),"query":"match","filter":"documents"})).await.unwrap();
    let partial = settled(&runtime, id, &limited).await;
    assert_eq!(partial["status"], "partial", "{partial}");
    assert_eq!(partial["entries"].as_array().unwrap().len(), 500);
    assert_eq!(partial["complete"], false);
    assert!(
        partial["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue["code"] == "result_limit")
    );
    let fixture = client
        .shell(
            &format!("mkdir '{root}/empty' '{root}/blocked'; chmod 000 '{root}/blocked'"),
            4096,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(fixture.stdout, b"created");
    let empty = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":format!("{root}/empty"),"query":"absent","filter":"all"}),
        )
        .await
        .unwrap();
    assert_eq!(settled(&runtime, id, &empty).await["status"], "completed");
    let blocked = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":format!("{root}/blocked"),"query":"absent","filter":"all"}),
        )
        .await
        .unwrap();
    let blocked = settled(&runtime, id, &blocked).await;
    assert_eq!(blocked["status"], "partial", "{blocked}");
    assert!(!blocked["issues"].as_array().unwrap().is_empty());
    let shared = format!("/sdcard/Download/interop-search-{}", uuid::Uuid::new_v4());
    runtime
        .invoke("files.mkdir", json!({"deviceId":id,"path":shared}))
        .await
        .unwrap();
    sync.push(
        &RemotePath::new(format!("{shared}/shared.txt")).unwrap(),
        &mut std::io::Cursor::new(b"shared"),
        0o600,
        0,
        1024,
    )
    .await
    .unwrap();
    let shared_search = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":shared,"query":"shared","filter":"documents"}),
        )
        .await
        .unwrap();
    let shared_done = settled(&runtime, id, &shared_search).await;
    assert_eq!(shared_done["status"], "completed", "{shared_done}");
    assert_eq!(shared_done["entries"].as_array().unwrap().len(), 1);
    runtime
        .invoke("files.delete", json!({"deviceId":id,"paths":[shared]}))
        .await
        .unwrap();
    client
        .shell(
            &format!("chmod 700 '{root}/blocked'"),
            4096,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    let stopping = runtime
        .invoke(
            "files.search.start",
            json!({"deviceId":id,"path":root,"query":"absent","filter":"all"}),
        )
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(
        settled(&runtime, id, &stopping).await["status"],
        "cancelled"
    );
    let cleanup = client
        .shell(
            &format!("rm -rf -- '{root}'"),
            4096,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(cleanup.exit_code, Some(0));
}
