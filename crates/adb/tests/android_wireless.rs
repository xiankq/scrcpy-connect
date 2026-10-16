//! Opt-in actual Android 11+ adbd interoperability. Test harness supplies fresh
//! endpoints and a private temporary code file; credentials are never logged.
//! Official adb may forward sockets for the harness, never for product code.
use interop_adb::{
    Client, ConnectOptions, Identity, OperationOptions,
    wireless::{self, TlsConfig},
};
use std::time::Duration;

#[tokio::test]
#[ignore = "requires Android pairing UI and current pairing/connect endpoints"]
async fn android_rejects_wrong_code_pairs_rust_identity_and_accepts_tls_reconnect() {
    let pairing = std::env::var("ANDROID_PAIR_ENDPOINT").expect("ANDROID_PAIR_ENDPOINT");
    let connect = std::env::var("ANDROID_TLS_ENDPOINT").expect("ANDROID_TLS_ENDPOINT");
    let path = std::env::var("ANDROID_PAIR_CODE_FILE").expect("ANDROID_PAIR_CODE_FILE");
    let code = std::fs::read_to_string(path).expect("read current pairing code");
    let code = code.trim();
    assert_eq!(code.len(), 6);
    assert!(code.bytes().all(|b| b.is_ascii_digit()));
    let identity = test_identity();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let options = OperationOptions {
        timeout: Duration::from_secs(20),
        ..Default::default()
    };
    let mut wrong = code.as_bytes().to_vec();
    wrong[0] = if wrong[0] == b'9' { b'0' } else { wrong[0] + 1 };
    let wrong = String::from_utf8(wrong).unwrap();
    let socket = tokio::net::TcpStream::connect(&pairing).await.unwrap();
    assert!(
        wireless::pair(
            socket,
            &wrong,
            &identity,
            &tls,
            "interop-android-test",
            &options
        )
        .await
        .is_err(),
        "a wrong code must not establish pairing"
    );
    let socket = tokio::net::TcpStream::connect(&pairing).await.unwrap();
    let paired = wireless::pair(
        socket,
        code,
        &identity,
        &tls,
        "interop-android-test",
        &options,
    )
    .await
    .unwrap();
    assert!(!paired.guid.is_empty());
    for _ in 0..2 {
        let client = Client::connect_tcp(
            &connect,
            ConnectOptions {
                identity: Some(identity.clone()),
                tls: Some(tls.clone()),
                request_authorization: false,
                operations: options.clone(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let output = client
            .shell("printf interop-wireless-verified", 1024, options.clone())
            .await
            .unwrap();
        assert_eq!(output.stdout, b"interop-wireless-verified");
        assert_eq!(output.exit_code, Some(0));
        client.close();
    }
}

fn test_identity() -> Identity {
    let Some(path) = std::env::var_os("ANDROID_TEST_IDENTITY_FILE") else {
        return Identity::generate().unwrap();
    };
    if let Ok(pem) = std::fs::read_to_string(&path) {
        return Identity::from_pem(&pem).unwrap();
    }
    let identity = Identity::generate().unwrap();
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    use std::io::Write;
    options
        .open(path)
        .unwrap()
        .write_all(identity.to_pkcs8_pem().unwrap().as_bytes())
        .unwrap();
    identity
}

#[tokio::test]
#[ignore = "requires a previously paired temporary test identity and Android TLS endpoint"]
async fn android_tls_reconnect_and_shell_with_persisted_rust_identity() {
    let endpoint = std::env::var("ANDROID_TLS_ENDPOINT").expect("ANDROID_TLS_ENDPOINT");
    assert!(
        std::env::var_os("ANDROID_TEST_IDENTITY_FILE").is_some(),
        "provide the identity previously paired by the other test"
    );
    let identity = test_identity();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    for _ in 0..2 {
        let options = OperationOptions {
            timeout: Duration::from_secs(20),
            ..Default::default()
        };
        let client = Client::connect_tcp(
            &endpoint,
            ConnectOptions {
                identity: Some(identity.clone()),
                tls: Some(tls.clone()),
                request_authorization: false,
                operations: options.clone(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let output = client
            .shell("printf interop-wireless-verified", 1024, options)
            .await
            .unwrap();
        assert_eq!(output.stdout, b"interop-wireless-verified");
        assert_eq!(output.exit_code, Some(0));
        client.close();
    }
}

#[tokio::test]
#[ignore = "requires an Android TLS endpoint with host authorization enforced"]
async fn android_unpaired_identity_cannot_open_tls_transport() {
    let endpoint = std::env::var("ANDROID_TLS_ENDPOINT").expect("ANDROID_TLS_ENDPOINT");
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let result = Client::connect_tcp(
        &endpoint,
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            request_authorization: false,
            operations: OperationOptions {
                timeout: Duration::from_secs(10),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .await;
    if let Ok(client) = result {
        client.close();
        panic!(
            "this device accepted an unpaired identity; its image cannot validate TLS host authorization"
        );
    }
}
