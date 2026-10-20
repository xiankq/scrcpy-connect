//! Real adbd interoperability: Rust encoders feed the official device decoders;
//! official device encoders feed Rust decoders. No adb executable is involved.
use interop_adb::{
    CancellationToken, Client, ConnectOptions, Error, OperationOptions,
    sync::{Compression, RemotePath},
};
use rand::{RngCore, SeedableRng};
use std::time::Duration;

#[tokio::test]
#[ignore = "requires actual authorized adbd advertising all sync v2 compression features"]
async fn official_adbd_round_trips_all_compression_formats_and_bounds() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let client = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    for feature in [
        "sendrecv_v2",
        "sendrecv_v2_brotli",
        "sendrecv_v2_lz4",
        "sendrecv_v2_zstd",
    ] {
        assert!(
            client.info().features.contains(feature),
            "device must advertise {feature}"
        );
    }
    let root = format!(
        "/data/local/tmp/interop-sync-{:016x}{:016x}",
        rand::random::<u64>(),
        rand::random::<u64>()
    );
    assert_eq!(
        client
            .shell(
                &format!("umask 077; mkdir -- {root}"),
                4096,
                OperationOptions::default()
            )
            .await
            .unwrap()
            .exit_code,
        Some(0)
    );
    let mut random = vec![0; 350_000];
    rand::rngs::StdRng::seed_from_u64(0xADB2026).fill_bytes(&mut random);
    let data = [
        vec![],
        b"sync-v2-small\0\xff\n".to_vec(),
        (0..350_000).map(|i| (i % 31) as u8).collect(),
        random,
    ];
    for (codec_index, codec) in [Compression::Brotli, Compression::Lz4, Compression::Zstd]
        .into_iter()
        .enumerate()
    {
        let mut sync = client.sync(OperationOptions::default()).await.unwrap();
        for (index, bytes) in data.iter().enumerate() {
            let path = RemotePath::new(format!("{root}/codec-{codec_index}-{index}")).unwrap();
            assert_eq!(
                sync.push_compressed(
                    &path,
                    &mut &bytes[..],
                    0o600,
                    1_700_000_000,
                    bytes.len() as u64,
                    codec
                )
                .await
                .unwrap(),
                bytes.len() as u64,
                "push {codec:?}/{index}"
            );
            assert_eq!(sync.stat(&path).await.unwrap().size, bytes.len() as u64);
            let mut plain = Vec::new();
            sync.pull(&path, &mut plain, bytes.len() as u64)
                .await
                .unwrap();
            assert_eq!(&plain, bytes, "official decoder {codec:?}/{index}");
            let mut compressed = Vec::new();
            sync.pull_compressed(&path, &mut compressed, bytes.len() as u64, codec)
                .await
                .unwrap();
            assert_eq!(&compressed, bytes, "official encoder {codec:?}/{index}");
        }
        eprintln!(
            "official adbd {codec:?}: empty, small, compressible and incompressible push/pull verified"
        );
    }
    let limit_path = RemotePath::new(format!("{root}/codec-2-3")).unwrap();
    let mut limited = client.sync(OperationOptions::default()).await.unwrap();
    assert!(matches!(
        limited
            .pull_compressed(&limit_path, &mut Vec::new(), 100, Compression::Zstd)
            .await,
        Err(Error::OutputLimit)
    ));
    assert!(matches!(
        limited.stat(&limit_path).await,
        Err(Error::Closed)
    ));
    for cancelled in [false, true] {
        let token = CancellationToken::new();
        let options = OperationOptions {
            timeout: Duration::from_millis(100),
            cancellation: token.clone(),
        };
        let mut stalled = client.sync(options).await.unwrap();
        let (mut input, _keep_writer_open) = tokio::io::duplex(1);
        let path = RemotePath::new(format!("{root}/stalled-{cancelled}")).unwrap();
        if cancelled {
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_millis(20)).await;
                token.cancel();
            });
        }
        let error = stalled
            .push_compressed(&path, &mut input, 0o600, 0, 1024, Compression::Zstd)
            .await
            .unwrap_err();
        assert!(if cancelled {
            matches!(error, Error::Cancelled)
        } else {
            matches!(error, Error::Timeout)
        });
        assert!(matches!(stalled.stat(&path).await, Err(Error::Closed)));
    }
    assert_eq!(
        client
            .shell(
                "printf compression_transport_alive",
                4096,
                OperationOptions::default()
            )
            .await
            .unwrap()
            .stdout,
        b"compression_transport_alive"
    );
    client
        .shell(
            &format!("rm -rf -- {root}"),
            4096,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    client.close();
}

#[tokio::test]
#[ignore = "requires actual authorized adbd; creates only an isolated temporary directory"]
async fn actual_lstat_is_single_path_nofollow_and_preserves_permission_errors() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let client = Client::connect_tcp((address.as_str(), port), ConnectOptions::default())
        .await
        .unwrap();
    assert!(client.info().features.contains("stat_v2"));
    let root = format!(
        "/data/local/tmp/interop-lstat-{:016x}{:016x}",
        rand::random::<u64>(),
        rand::random::<u64>()
    );
    let setup = client.shell(
        &format!("umask 077; mkdir -- {root} && printf content > {root}/target && ln -s target {root}/link && ln -s missing {root}/dangling && mkdir {root}/blocked && printf secret > {root}/blocked/file && chmod 000 {root}/blocked"),
        4096, OperationOptions::default(),
    ).await.unwrap();
    assert_eq!(setup.exit_code, Some(0), "{:?}", setup.stderr);
    // SELinux may deny adbd getattr on shell-created symlinks independently of
    // the shell subprocess. Preserve that denial rather than follow the target.
    for name in ["link", "dangling"] {
        let mut sync = client.sync(OperationOptions::default()).await.unwrap();
        match sync
            .lstat(&RemotePath::new(format!("{root}/{name}")).unwrap())
            .await
        {
            Ok(metadata) => assert_eq!(metadata.mode & 0o170000, 0o120000),
            Err(Error::RemoteErrno {
                operation: "stat",
                errno: 13,
            }) => {
                eprintln!("official adbd SELinux denies lstat of shell-created {name}: errno 13");
            }
            result => panic!("unexpected lstat result for {name}: {result:?}"),
        }
    }
    // An inaccessible sibling does not affect single-path metadata.
    let mut sync = client.sync(OperationOptions::default()).await.unwrap();
    let regular = sync
        .lstat(&RemotePath::new(format!("{root}/target")).unwrap())
        .await
        .unwrap();
    assert_eq!(regular.mode & 0o170000, 0o100000);
    assert_eq!(regular.size, 7);
    // Verify no-follow against an existing, readable Android system symlink,
    // without modifying any system file or relying on shell traversal rights.
    let mut verified_symlink = false;
    for path in ["/system/bin/sh", "/system/bin/ls", "/system/bin/cat"] {
        let mut sync = client.sync(OperationOptions::default()).await.unwrap();
        if let Ok(link) = sync.lstat(&RemotePath::new(path).unwrap()).await
            && link.mode & 0o170000 == 0o120000
        {
            let target = sync.stat(&RemotePath::new(path).unwrap()).await.unwrap();
            assert_ne!(target.mode & 0o170000, 0o120000);
            verified_symlink = true;
            eprintln!("official adbd LST2 preserves symlink while STA2 follows: {path}");
            break;
        }
    }
    assert!(
        verified_symlink,
        "target must expose a readable system symlink for this test"
    );
    let mut denied = client.sync(OperationOptions::default()).await.unwrap();
    let permission = denied
        .lstat(&RemotePath::new(format!("{root}/blocked/file")).unwrap())
        .await;
    assert!(
        matches!(
            permission,
            Err(Error::RemoteErrno {
                operation: "stat",
                errno: 13
            })
        ),
        "expected permission denial: {permission:?}"
    );
    let mut missing = client.sync(OperationOptions::default()).await.unwrap();
    let absence = missing
        .lstat(&RemotePath::new(format!("{root}/absent")).unwrap())
        .await;
    assert!(matches!(
        absence,
        Err(Error::RemoteErrno {
            operation: "stat",
            errno: 2
        })
    ));
    let cleanup = client
        .shell(
            &format!("chmod 700 {root}/blocked; rm -rf -- {root}"),
            4096,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(cleanup.exit_code, Some(0));
    client.close();
}
