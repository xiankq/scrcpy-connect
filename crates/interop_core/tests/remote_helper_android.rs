//! Actual Android kernel operations, through the same deployment path as production.
pub use interop_core::{CoreError, CoreResult};
#[path = "../src/remote_helper.rs"]
mod remote_helper;
use interop_adb::{Client, ConnectOptions, OperationOptions, sync::RemotePath};

async fn put(client: &Client, path: &[u8], bytes: &[u8]) {
    client
        .sync(OperationOptions::default())
        .await
        .unwrap()
        .push(
            &RemotePath::new(path).unwrap(),
            &mut &bytes[..],
            0o600,
            0,
            bytes.len() as u64,
        )
        .await
        .unwrap();
}
async fn get(client: &Client, path: &[u8]) -> Option<Vec<u8>> {
    let mut bytes = Vec::new();
    let result = client
        .sync(OperationOptions::default())
        .await
        .unwrap()
        .pull(&RemotePath::new(path).unwrap(), &mut bytes, 4096)
        .await;
    result.ok().map(|_| bytes)
}
async fn shell(client: &Client, command: &str) -> Vec<u8> {
    let output = client
        .shell(command, 16 * 1024, OperationOptions::default())
        .await
        .unwrap();
    assert_eq!(
        output.exit_code,
        Some(0),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    output.stdout
}

#[tokio::test]
#[ignore = "requires actual Android shared storage and authorized adbd"]
async fn actual_android_shared_storage_rename_and_publish_are_kernel_atomic() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let client = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let root = format!(
        "/sdcard/interop-rename-test-{}",
        uuid::Uuid::new_v4().simple()
    );
    shell(&client, &format!("mkdir -- {root}")).await;
    let source = format!("{root}/source");
    let target = format!("{root}/target");
    put(&client, source.as_bytes(), b"source").await;
    put(&client, target.as_bytes(), b"existing").await;
    let conflict = remote_helper::remote_rename(&client, &source, &target, false)
        .await
        .unwrap_err();
    assert_eq!(conflict.code, "conflict", "{conflict:?}");
    assert_eq!(conflict.details["errno"], 17);
    assert_eq!(get(&client, source.as_bytes()).await.unwrap(), b"source");
    assert_eq!(get(&client, target.as_bytes()).await.unwrap(), b"existing");
    shell(&client, &format!("rm -- {target}")).await;
    assert_eq!(
        remote_helper::remote_rename(&client, &source, &target, false)
            .await
            .unwrap()["atomic"],
        true
    );
    assert!(get(&client, source.as_bytes()).await.is_none());
    assert_eq!(get(&client, target.as_bytes()).await.unwrap(), b"source");
    put(&client, source.as_bytes(), b"new publication").await;
    assert_eq!(
        remote_helper::remote_rename(&client, &source, &target, true)
            .await
            .unwrap()["atomic"],
        true
    );
    assert!(get(&client, source.as_bytes()).await.is_none());
    assert_eq!(
        get(&client, target.as_bytes()).await.unwrap(),
        b"new publication"
    );
    shell(&client, &format!("rm -rf -- {root}")).await;
    client.close();
}

#[tokio::test]
#[ignore = "requires actual Android shell-authorized adbd; creates only unique temporary fixture paths"]
async fn actual_atomic_conflicts_directories_symlinks_bytes_and_source_replacement() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let client = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    let root = format!(
        "/data/local/tmp/interop-rename-test-{}",
        uuid::Uuid::new_v4().simple()
    );
    shell(&client, &format!("mkdir -- {root}")).await;
    let source = format!("{root}/source");
    let target = format!("{root}/target");
    put(&client, source.as_bytes(), b"source").await;
    put(&client, target.as_bytes(), b"existing").await;
    let conflict = remote_helper::remote_rename(&client, &source, &target, false)
        .await
        .unwrap_err();
    assert_eq!(conflict.code, "conflict", "{conflict:?}");
    assert_eq!(conflict.details["errno"], 17);
    assert_eq!(get(&client, source.as_bytes()).await.unwrap(), b"source");
    assert_eq!(get(&client, target.as_bytes()).await.unwrap(), b"existing");
    shell(&client, &format!("rm -- {target}")).await;
    assert_eq!(
        remote_helper::remote_rename(&client, &source, &target, false)
            .await
            .unwrap()["atomic"],
        true
    );
    assert!(get(&client, source.as_bytes()).await.is_none());
    assert_eq!(get(&client, target.as_bytes()).await.unwrap(), b"source");
    shell(
        &client,
        &format!(
            "mkdir -- {root}/kept-dir {root}/another-dir; ln -s missing-target {root}/existing-link"
        ),
    )
    .await;
    let directory_conflict = remote_helper::remote_rename(
        &client,
        &format!("{root}/another-dir"),
        &format!("{root}/kept-dir"),
        false,
    )
    .await
    .unwrap_err();
    assert_eq!(directory_conflict.code, "conflict");
    shell(
        &client,
        &format!("test -d {root}/another-dir && test -d {root}/kept-dir"),
    )
    .await;
    let candidate = format!("{root}/candidate");
    put(&client, candidate.as_bytes(), b"candidate").await;
    assert_eq!(
        remote_helper::remote_rename(&client, &candidate, &format!("{root}/existing-link"), false)
            .await
            .unwrap_err()
            .code,
        "conflict"
    );
    assert_eq!(
        shell(&client, &format!("readlink {root}/existing-link")).await,
        b"missing-target\n"
    );
    assert_eq!(
        get(&client, candidate.as_bytes()).await.unwrap(),
        b"candidate"
    );
    shell(&client,&format!("mkdir -p -- {root}/dir/sub; printf payload > {root}/dir/sub/file; ln -s target {root}/link")).await;
    remote_helper::remote_rename(
        &client,
        &format!("{root}/dir"),
        &format!("{root}/moved-dir"),
        false,
    )
    .await
    .unwrap();
    assert_eq!(
        get(&client, format!("{root}/moved-dir/sub/file").as_bytes())
            .await
            .unwrap(),
        b"payload"
    );
    remote_helper::remote_rename(
        &client,
        &format!("{root}/link"),
        &format!("{root}/moved-link"),
        false,
    )
    .await
    .unwrap();
    assert_eq!(
        shell(&client, &format!("readlink {root}/moved-link")).await,
        b"target\n"
    );
    assert_eq!(get(&client, target.as_bytes()).await.unwrap(), b"source");
    let mut raw_source = format!("{root}/raw-").into_bytes();
    raw_source.extend_from_slice(b"\xff'$\n");
    let mut raw_target = format!("{root}/moved-").into_bytes();
    raw_target.extend_from_slice(b"\xfe\n\n");
    put(&client, &raw_source, b"arbitrary path bytes").await;
    remote_helper::remote_rename_bytes(&client, &raw_source, &raw_target, false)
        .await
        .unwrap();
    assert_eq!(
        get(&client, &raw_target).await.unwrap(),
        b"arbitrary path bytes"
    );
    assert!(get(&client, &raw_source).await.is_none());

    for round in 0..8 {
        let first = format!("{root}/first-{round}");
        let second = format!("{root}/second-{round}");
        let destination = format!("{root}/winner-{round}");
        put(&client, first.as_bytes(), b"first").await;
        put(&client, second.as_bytes(), b"second").await;
        let (a, b) = tokio::join!(
            remote_helper::remote_rename(&client, &first, &destination, false),
            remote_helper::remote_rename(&client, &second, &destination, false)
        );
        assert_eq!(usize::from(a.is_ok()) + usize::from(b.is_ok()), 1);
        let loser = if a.is_ok() {
            assert_eq!(b.unwrap_err().code, "conflict");
            (&second, b"second".as_slice(), b"first".as_slice())
        } else {
            assert_eq!(a.unwrap_err().code, "conflict");
            (&first, b"first".as_slice(), b"second".as_slice())
        };
        assert_eq!(get(&client, loser.0.as_bytes()).await.unwrap(), loser.1);
        assert_eq!(get(&client, destination.as_bytes()).await.unwrap(), loser.2);
    }
    let mut before = 0;
    let mut after = 0;
    for round in 0..8 {
        let source = format!("{root}/race-source-{round}");
        let incoming = format!("{root}/incoming-{round}");
        let destination = format!("{root}/race-destination-{round}");
        put(&client, source.as_bytes(), b"old").await;
        put(&client, incoming.as_bytes(), b"new").await;
        let (moved, published) = tokio::join!(
            remote_helper::remote_rename(&client, &source, &destination, false),
            remote_helper::remote_rename(&client, &incoming, &source, true)
        );
        moved.unwrap();
        published.unwrap();
        let destination = get(&client, destination.as_bytes()).await.unwrap();
        let source = get(&client, source.as_bytes()).await;
        match destination.as_slice() {
            b"old" => {
                assert_eq!(source.unwrap(), b"new");
                before += 1
            }
            b"new" => {
                assert!(source.is_none());
                after += 1
            }
            _ => panic!("unexpected fixture content"),
        }
        assert!(get(&client, incoming.as_bytes()).await.is_none());
    }
    eprintln!(
        "8 competing destination renames retained all losers; source replacement serialization: rename-first={before}, replacement-first={after}"
    );
    shell(&client, &format!("rm -rf -- {root}")).await;
    client.close();
}
