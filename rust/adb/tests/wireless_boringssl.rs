//! 跨实现测试。用固定官方 BoringSSL 源码构建相邻 C++ 夹具，并将 ADB_BORINGSSL_FIXTURE 设为其绝对路径；产品无原生密码库依赖，因此默认忽略。
use interop_adb::{
    Client, ConnectOptions, Identity, OperationOptions, TlsPolicy,
    wireless::{self, TlsConfig},
};
use std::{
    io::{BufRead, BufReader},
    process::{Child, Command, Stdio},
    time::Duration,
};

struct Peer(Child);
impl Drop for Peer {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
fn start(mode: &str) -> (Peer, u16) {
    let path = std::env::var("ADB_BORINGSSL_FIXTURE")
        .expect("set ADB_BORINGSSL_FIXTURE to compiled test fixture");
    let mut child = Command::new(path)
        .arg(mode)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.as_mut().unwrap())
        .read_line(&mut line)
        .unwrap();
    let port = line
        .trim()
        .parse()
        .expect("fixture should print listener port");
    (Peer(child), port)
}
#[tokio::test]
#[ignore = "requires test-only official BoringSSL fixture"]
async fn pairing_matches_official_boringssl_exporter_spake2_hkdf_gcm_and_rsa_identity() {
    let (mut peer, port) = start("pair");
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let stream = tokio::net::TcpStream::connect(("127.0.0.1", port))
        .await
        .unwrap();
    let result = wireless::pair(
        stream,
        "123456",
        &identity,
        &tls,
        "interop-test",
        &OperationOptions::default(),
    )
    .await
    .unwrap();
    assert_eq!(result.guid, "adb-boringssl-official-crypto");
    assert!(peer.0.wait().unwrap().success());
}
#[tokio::test]
#[ignore = "requires test-only official BoringSSL fixture"]
async fn wrong_code_is_rejected_by_official_boringssl_peer_info_authentication() {
    let (mut peer, port) = start("wrong");
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let stream = tokio::net::TcpStream::connect(("127.0.0.1", port))
        .await
        .unwrap();
    let error = wireless::pair(
        stream,
        "654321",
        &identity,
        &tls,
        "interop-test",
        &OperationOptions::default(),
    )
    .await
    .unwrap_err();
    assert!(
        error.to_string().contains("pairing authentication failed"),
        "{error}"
    );
    assert!(!peer.0.wait().unwrap().success());
}
#[tokio::test]
#[ignore = "requires test-only official BoringSSL fixture"]
async fn stls_upgrades_existing_adb_transport_to_tls13_and_waits_for_cnxn() {
    let (mut peer, port) = start("stls");
    let identity = Identity::generate().unwrap();
    let tls = TlsConfig::experimental_rustcrypto(&identity).unwrap();
    let client = Client::connect_tcp(
        ("127.0.0.1", port),
        ConnectOptions {
            identity: Some(identity),
            tls: Some(tls),
            tls_policy: TlsPolicy::Required,
            operations: OperationOptions {
                timeout: Duration::from_secs(10),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .await
    .unwrap();
    assert!(client.info().features.contains("shell_v2"));
    assert_eq!(client.info().version, 0x01000001);
    assert!(peer.0.wait().unwrap().success());
}
