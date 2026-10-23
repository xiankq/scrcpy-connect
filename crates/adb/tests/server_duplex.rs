//! Official smart-socket fixtures: no direct-adbd protocol or authentication.
use interop_adb::{Client, OperationOptions};
use std::time::Duration;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};

async fn service(socket: &mut TcpStream) -> String {
    let mut length = [0; 4];
    socket.read_exact(&mut length).await.unwrap();
    let count = usize::from_str_radix(std::str::from_utf8(&length).unwrap(), 16).unwrap();
    let mut bytes = vec![0; count];
    socket.read_exact(&mut bytes).await.unwrap();
    String::from_utf8(bytes).unwrap()
}
async fn negotiate(listener: &TcpListener) {
    let (mut socket, _) = listener.accept().await.unwrap();
    assert_eq!(service(&mut socket).await, "host:tport:serial:fixture");
    socket.write_all(b"OKAY").await.unwrap();
    socket.write_all(&42u64.to_le_bytes()).await.unwrap();
    let (mut features, _) = listener.accept().await.unwrap();
    assert_eq!(
        service(&mut features).await,
        "host-transport-id:42:features"
    );
    features.write_all(b"OKAY0008shell_v2").await.unwrap();
}

#[tokio::test]
async fn official_duplex_input_unblocks_read_and_dropped_writer_closes_only_service() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let fixture = tokio::spawn(async move {
        negotiate(&listener).await;
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(service(&mut socket).await, "host:transport-id:42");
        socket.write_all(b"OKAY").await.unwrap();
        assert_eq!(service(&mut socket).await, "exec:cat");
        socket.write_all(b"OKAY").await.unwrap();
        let mut input = [0; 3];
        socket.read_exact(&mut input).await.unwrap();
        assert_eq!(&input, &[0, 255, 7]);
        socket.write_all(&input).await.unwrap();
        assert_eq!(socket.read(&mut [0; 1]).await.unwrap(), 0);
        let (mut next, _) = listener.accept().await.unwrap();
        assert_eq!(service(&mut next).await, "host:transport-id:42");
        next.write_all(b"OKAY").await.unwrap();
        assert_eq!(service(&mut next).await, "exec:alive");
        next.write_all(b"OKAYalive").await.unwrap();
    });
    let client = Client::connect_server(address, "fixture", OperationOptions::default())
        .await
        .unwrap();
    assert_eq!(client.server_transport_id(), Some(42));
    let (mut reader, mut writer) = client
        .open("exec:cat", OperationOptions::default())
        .await
        .unwrap()
        .into_split();
    tokio::time::timeout(Duration::from_secs(1), async {
        tokio::join!(
            async {
                let mut output = [0; 3];
                assert_eq!(reader.read(&mut output).await.unwrap(), 3);
                assert_eq!(&output, &[0, 255, 7]);
            },
            async {
                writer.write_all(&[0, 255, 7]).await.unwrap();
            }
        );
    })
    .await
    .unwrap();
    drop(writer);
    tokio::time::timeout(Duration::from_secs(1), reader.read(&mut [0; 1]))
        .await
        .unwrap()
        .unwrap();
    assert!(!client.is_closed());
    let mut next = client
        .open("exec:alive", OperationOptions::default())
        .await
        .unwrap();
    let mut output = [0; 5];
    next.read_exact(&mut output).await.unwrap();
    assert_eq!(&output, b"alive");
    client.close();
    fixture.await.unwrap();
}

#[tokio::test]
async fn stale_official_transport_never_reselects_by_serial_or_connects_to_adbd() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let fixture = tokio::spawn(async move {
        negotiate(&listener).await;
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(service(&mut socket).await, "host:transport-id:42");
        socket.write_all(b"FAIL0010device not found").await.unwrap();
        assert!(
            tokio::time::timeout(Duration::from_millis(100), listener.accept())
                .await
                .is_err()
        );
    });
    let client = Client::connect_server(address, "fixture", OperationOptions::default())
        .await
        .unwrap();
    assert!(
        client
            .open("exec:alive", OperationOptions::default())
            .await
            .is_err()
    );
    client.close();
    fixture.await.unwrap();
}
