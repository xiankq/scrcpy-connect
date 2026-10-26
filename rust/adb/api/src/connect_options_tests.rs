//! 沿实际 TCP/AUTH/CNXN 路径验证显式执行参数；不绕过 SDK 的选项转换。
use super::*;
use interop_adb::protocol::{self, Frame};

async fn handshake(requested: AdbConnectOptions, burst: bool, comment: &str) {
    let (_directory, path) = super::handshake_tests::identity_path().await;
    let identity = Identity::from_pem(&std::fs::read_to_string(&path).unwrap()).unwrap();
    let expected_key = identity.public_key(comment).unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (release, released) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut peer, _) = listener.accept().await.unwrap();
        let hello = Frame::read(&mut peer, 4096, false).await.unwrap();
        assert_eq!(hello.command, protocol::CNXN);
        let banner = std::str::from_utf8(&hello.payload).unwrap();
        assert_eq!(
            banner.contains(",delayed_ack"),
            burst,
            "必须真正通告调用方选择的流控能力"
        );
        // 拒绝首个签名后再次请求 token，使公钥注释真实进入 AUTH 提示。
        for kind in [2, 3] {
            Frame::new(protocol::AUTH, 1, 0, [0x5a; 20])
                .write(&mut peer)
                .await
                .unwrap();
            let reply = Frame::read(&mut peer, 4096, false).await.unwrap();
            assert_eq!((reply.command, reply.arg0), (protocol::AUTH, kind));
            if kind == 3 {
                assert_eq!(reply.payload, expected_key);
            }
        }
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=delayed_ack\0".to_vec(),
        )
        .write(&mut peer)
        .await
        .unwrap();
        released.await.unwrap();
    });
    // 生产公开函数的 mobile 栅栏仍保留；只在夹具调用与它共用的真实执行入口。
    let connected = connect_tcp(
        address.to_string(),
        path,
        false,
        true,
        2000,
        requested,
        None,
    )
    .await
    .unwrap();
    let facts = adb_connection_facts(connected.id.clone()).unwrap();
    assert_eq!(facts.burst_mode, Some(burst));
    assert_eq!(facts.handshake, AdbHandshakeKind::Auth);
    adb_disconnect(connected.id).await.unwrap();
    release.send(()).unwrap();
    server.await.unwrap();
}

#[tokio::test]
async fn explicit_burst_and_public_key_comment_reach_the_actual_handshake() {
    handshake(
        AdbConnectOptions {
            burst_mode: true,
            public_key_comment: "sdk 用户@host".into(),
            tcp: AdbTcpOptions {
                nodelay: false,
                keepalive: Some(AdbKeepaliveOptions {
                    idle_ms: 1000,
                    interval_ms: 2000,
                    retries: 3,
                }),
                #[cfg(any(target_os = "android", target_os = "linux"))]
                user_timeout_ms: Some(5000),
                #[cfg(not(any(target_os = "android", target_os = "linux")))]
                user_timeout_ms: None,
            },
        },
        true,
        "sdk 用户@host",
    )
    .await;
}

#[tokio::test]
async fn defaults_keep_classic_flow_control_and_the_mechanism_comment() {
    handshake(
        AdbConnectOptions::default(),
        false,
        &ConnectOptions::default().public_key_comment,
    )
    .await;
}

#[test]
fn socket_values_keep_their_units_and_explicit_defaults() {
    let defaults = connection_options(AdbConnectOptions::default(), false, 1000).unwrap();
    assert_eq!(defaults.tcp, interop_adb::TcpOptions::default());
    assert_eq!(defaults.burst_mode, ConnectOptions::default().burst_mode);
    assert_eq!(
        defaults.public_key_comment,
        ConnectOptions::default().public_key_comment
    );
    let converted = connection_options(
        AdbConnectOptions {
            tcp: AdbTcpOptions {
                nodelay: false,
                keepalive: Some(AdbKeepaliveOptions {
                    idle_ms: 1500,
                    interval_ms: 2345,
                    retries: 127,
                }),
                user_timeout_ms: None,
            },
            ..Default::default()
        },
        false,
        1000,
    )
    .unwrap();
    assert!(!converted.tcp.nodelay);
    let keepalive = converted.tcp.keepalive.unwrap();
    assert_eq!(keepalive.idle, Duration::from_millis(1500));
    assert_eq!(keepalive.interval, Duration::from_millis(2345));
    assert_eq!(keepalive.retries, 127);
}

#[test]
fn invalid_connection_fields_are_rejected_before_socket_use() {
    let check = |requested: AdbConnectOptions, expected: &str| {
        let error = connection_options(requested, false, 1000).unwrap_err();
        assert_eq!(error.code, AdbConnectionErrorCode::InvalidArgument);
        assert_eq!(error.message, expected);
    };
    for comment in [
        "bad\0comment".into(),
        "bad\rcomment".into(),
        "bad\ncomment".into(),
        "界".repeat(342),
    ] {
        check(
            AdbConnectOptions {
                public_key_comment: comment,
                ..Default::default()
            },
            "adb_invalid_public_key_comment",
        );
    }
    for (idle_ms, interval_ms, retries) in [
        (0, 1000, 1),
        (999, 1000, 1),
        (32_767_001, 1000, 1),
        (1000, 0, 1),
        (1000, 999, 1),
        (1000, 32_767_001, 1),
        (1000, 1000, 0),
        (1000, 1000, 128),
    ] {
        check(
            AdbConnectOptions {
                tcp: AdbTcpOptions {
                    keepalive: Some(AdbKeepaliveOptions {
                        idle_ms,
                        interval_ms,
                        retries,
                    }),
                    ..Default::default()
                },
                ..Default::default()
            },
            "adb_invalid_tcp_keepalive",
        );
    }
    for timeout in [0, i32::MAX as u32 + 1] {
        check(
            AdbConnectOptions {
                tcp: AdbTcpOptions {
                    user_timeout_ms: Some(timeout),
                    ..Default::default()
                },
                ..Default::default()
            },
            "adb_invalid_tcp_user_timeout",
        );
    }
    #[cfg(not(any(target_os = "android", target_os = "linux")))]
    check(
        AdbConnectOptions {
            tcp: AdbTcpOptions {
                user_timeout_ms: Some(1000),
                ..Default::default()
            },
            ..Default::default()
        },
        "adb_tcp_user_timeout_unsupported",
    );
}

#[tokio::test]
async fn invalid_connect_options_never_prepare_identity_or_contact_the_endpoint() {
    let directory = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let cases = [
        (
            AdbConnectOptions {
                public_key_comment: "invalid\ncomment".into(),
                ..Default::default()
            },
            1000,
            "adb_invalid_public_key_comment",
        ),
        (
            AdbConnectOptions {
                tcp: AdbTcpOptions {
                    keepalive: Some(AdbKeepaliveOptions {
                        idle_ms: 0,
                        interval_ms: 1000,
                        retries: 1,
                    }),
                    ..Default::default()
                },
                ..Default::default()
            },
            1000,
            "adb_invalid_tcp_keepalive",
        ),
        (
            AdbConnectOptions {
                tcp: AdbTcpOptions {
                    user_timeout_ms: Some(0),
                    ..Default::default()
                },
                ..Default::default()
            },
            1000,
            "adb_invalid_tcp_user_timeout",
        ),
        (AdbConnectOptions::default(), 0, "invalid_adb_timeout"),
    ];
    for (index, (options, timeout, expected)) in cases.into_iter().enumerate() {
        // 缺失的父目录也必须保持缺失；参数拒绝不能先进入身份准备。
        let parent = directory.path().join(format!("not-created-{index}"));
        let path = parent.join("host.pem");
        let error = connect_tcp(
            address.clone(),
            path.to_string_lossy().into_owned(),
            false,
            true,
            timeout,
            options,
            None,
        )
        .await
        .err()
        .expect("非法参数必须失败");
        assert!(!path.exists(), "非法参数不得创建密钥");
        assert!(!parent.exists(), "非法参数不得创建父目录");
        assert_eq!(error.code, AdbConnectionErrorCode::InvalidArgument);
        assert_eq!(error.message, expected);
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(30), listener.accept())
            .await
            .is_err(),
        "非法参数不得连接端点"
    );
}
