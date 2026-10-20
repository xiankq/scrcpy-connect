//! Real kernel loss on sockets owned by this test. No firewall/proxy or peer EOF.
#![cfg(any(target_os = "linux", target_os = "android"))]

use interop_adb::{
    Client, ConnectOptions, KeepaliveOptions, OperationOptions, TcpOptions,
    protocol::{self, Frame},
};
use socket2::{SockFilter, SockRef};
use std::time::Duration;
use tokio::{
    io::AsyncReadExt,
    net::{TcpListener, TcpStream},
};

async fn connected() -> (Client, TcpStream) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let peer = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let frame = Frame::read(&mut socket, protocol::MAX_PAYLOAD, false)
            .await
            .unwrap();
        assert_eq!(frame.command, protocol::CNXN);
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=;\0".to_vec(),
        )
        .write(&mut socket)
        .await
        .unwrap();
        socket
    });
    let client = Client::connect_tcp(
        address,
        ConnectOptions {
            tcp: TcpOptions {
                nodelay: true,
                keepalive: Some(KeepaliveOptions {
                    idle: Duration::from_secs(1),
                    interval: Duration::from_secs(1),
                    retries: 10,
                }),
                user_timeout: Some(Duration::from_secs(11)),
            },
            ..Default::default()
        },
    )
    .await
    .unwrap();
    (client, peer.await.unwrap())
}

fn drop_incoming(socket: &TcpStream) {
    // BPF_RET | BPF_K, return 0: discard before TCP can ACK data/keepalive.
    // The peer stays open throughout each deadline assertion.
    SockRef::from(socket)
        .attach_filter(&[SockFilter::new(0x06, 0, 0, 0)])
        .unwrap();
}

async fn closed(client: &Client) {
    while !client.is_closed() {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

#[tokio::test]
#[ignore = "requires SO_ATTACH_FILTER permission; run explicitly on a dedicated Linux/Android test environment"]
async fn tcp_liveness_detects_idle_blackhole_without_peer_eof() {
    let (client, peer) = connected().await;
    drop_incoming(&peer);
    let result = tokio::time::timeout(Duration::from_secs(16), closed(&client)).await;
    client.close();
    assert!(
        result.is_ok(),
        "lost idle transport stayed online for 16 seconds without EOF"
    );
    drop(peer);
}

#[tokio::test]
#[ignore = "requires SO_ATTACH_FILTER permission; run explicitly on a dedicated Linux/Android test environment"]
async fn tcp_liveness_ends_unacknowledged_open_without_operation_timeout() {
    let (client, peer) = connected().await;
    drop_incoming(&peer);
    let result = tokio::time::timeout(
        Duration::from_secs(16),
        client.open(
            "shell:echo unreachable",
            OperationOptions {
                timeout: Duration::from_secs(120),
                ..Default::default()
            },
        ),
    )
    .await;
    let detected = matches!(result, Ok(Err(_))) && client.is_closed();
    client.close();
    assert!(
        detected,
        "unacknowledged OPEN did not fail with transport loss within 16 seconds"
    );
    drop(peer);
}

#[tokio::test]
async fn tcp_liveness_keeps_healthy_idle_connection_and_allows_prompt_close() {
    let (client, mut peer) = connected().await;
    tokio::time::sleep(Duration::from_secs(17)).await;
    assert!(
        !client.is_closed(),
        "healthy idle TCP is allowed to have no ADB frames"
    );
    client.close();
    assert!(client.is_closed());
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), peer.read(&mut [0; 1]))
            .await
            .expect("explicit close must release the underlying TCP transport")
            .unwrap(),
        0,
    );
    drop(peer);
}
