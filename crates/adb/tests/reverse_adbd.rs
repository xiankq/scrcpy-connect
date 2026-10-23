use interop_adb::{Client, ConnectOptions, OperationOptions, RemoteSocket, ReverseSocket};
use std::{num::NonZeroU16, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
#[ignore = "requires actual authorized adbd; binds only a new ephemeral device reverse port"]
async fn actual_reverse_accepts_device_opens_bridges_bytes_rebinds_and_removes() {
    let address = std::env::var("INTEROP_ADBD_ADDRESS").unwrap_or_else(|_| "127.0.0.1".into());
    let port: u16 = std::env::var("INTEROP_ADBD_PORT")
        .expect("set INTEROP_ADBD_PORT")
        .parse()
        .unwrap();
    let client = Client::connect_tcp(
        (address.as_str(), port),
        ConnectOptions {
            adb_server: std::env::var("INTEROP_ADB_SERVER")
                .ok()
                .map(|s| s.parse().unwrap()),
            request_authorization: true,
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let destination = listener.local_addr().unwrap();
    let echo = tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            tokio::spawn(async move {
                let mut buffer = vec![0; 65536];
                loop {
                    let count = socket.read(&mut buffer).await.unwrap();
                    if count == 0 {
                        break;
                    }
                    socket.write_all(&buffer[..count]).await.unwrap();
                }
            });
        }
    });
    let binding = client
        .reverse_forward(
            &ReverseSocket::Tcp(0),
            destination,
            true,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    let ReverseSocket::Tcp(device_port) = binding.device else {
        panic!("expected allocated TCP port")
    };
    assert_ne!(device_port, 0);
    let endpoint = format!("tcp:{device_port}");
    assert!(
        client
            .reverse_list(OperationOptions::default())
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.device_service == endpoint)
    );
    assert!(
        client
            .reverse_forward(
                &binding.device,
                destination,
                true,
                OperationOptions::default()
            )
            .await
            .is_err(),
        "norebind must preserve the first listener"
    );
    let exchange = |byte: u8| {
        let client = client.clone();
        async move {
            let mut stream = client
                .connect_socket(
                    &RemoteSocket::Tcp(NonZeroU16::new(device_port).unwrap()),
                    OperationOptions::default(),
                )
                .await
                .unwrap();
            let bytes = vec![byte; 512 * 1024];
            // Alternating write/read also exercises multiple ADB packets without
            // requiring an unbounded full-duplex application output buffer.
            for chunk in bytes.chunks(8192) {
                stream.write_all(chunk).await.unwrap();
                let mut output = vec![0; chunk.len()];
                stream.read_exact(&mut output).await.unwrap();
                assert_eq!(&output, chunk);
            }
            stream.close().await.unwrap();
        }
    };
    tokio::time::timeout(Duration::from_secs(15), async {
        tokio::join!(exchange(17), exchange(29));
    })
    .await
    .unwrap();
    let replacement = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    client
        .reverse_forward(
            &binding.device,
            replacement.local_addr().unwrap(),
            false,
            OperationOptions::default(),
        )
        .await
        .unwrap();
    let responder = tokio::spawn(async move {
        let (mut socket, _) = replacement.accept().await.unwrap();
        socket.write_all(b"replacement").await.unwrap();
    });
    let mut stream = client
        .connect_socket(
            &RemoteSocket::Tcp(NonZeroU16::new(device_port).unwrap()),
            OperationOptions::default(),
        )
        .await
        .unwrap();
    let mut output = [0; 11];
    stream.read_exact(&mut output).await.unwrap();
    assert_eq!(&output, b"replacement");
    responder.await.unwrap();
    drop(stream);
    client
        .reverse_remove(&binding.device, OperationOptions::default())
        .await
        .unwrap();
    assert!(
        !client
            .reverse_list(OperationOptions::default())
            .await
            .unwrap()
            .iter()
            .any(|entry| entry.device_service == endpoint)
    );
    assert!(
        client
            .connect_socket(
                &RemoteSocket::Tcp(NonZeroU16::new(device_port).unwrap()),
                OperationOptions::default()
            )
            .await
            .is_err()
    );
    assert_eq!(
        client
            .shell(
                "printf reverse_transport_alive",
                4096,
                OperationOptions::default()
            )
            .await
            .unwrap()
            .stdout,
        b"reverse_transport_alive"
    );
    let local = ReverseSocket::LocalAbstract(format!(
        "interop-reverse-test-{:016x}",
        rand::random::<u64>()
    ));
    let binding = client
        .reverse_forward(&local, destination, true, OperationOptions::default())
        .await
        .unwrap();
    let ReverseSocket::LocalAbstract(name) = binding.device else {
        panic!("expected localabstract binding")
    };
    let mut stream = client
        .connect_socket(
            &RemoteSocket::LocalAbstract(name),
            OperationOptions::default(),
        )
        .await
        .unwrap();
    stream.write_all(b"unix reverse").await.unwrap();
    let mut result = [0; 12];
    stream.read_exact(&mut result).await.unwrap();
    assert_eq!(&result, b"unix reverse");
    stream.close().await.unwrap();
    client
        .reverse_remove(&local, OperationOptions::default())
        .await
        .unwrap();
    let snapshot = client
        .jdwp_processes(1024, OperationOptions::default())
        .await
        .unwrap();
    let mut tracker = client
        .track_jdwp(1024, OperationOptions::default())
        .await
        .unwrap();
    let initial = tracker.next_event().await.unwrap().unwrap();
    assert!(snapshot.iter().all(|pid| pid.get() > 0));
    assert!(initial.iter().all(|pid| pid.get() > 0));
    tracker.close().await.unwrap();
    if client.uses_server() {
        let binding = client
            .reverse_forward(
                &ReverseSocket::Tcp(0),
                destination,
                true,
                OperationOptions::default(),
            )
            .await
            .unwrap();
        let ReverseSocket::Tcp(port) = binding.device else {
            panic!("TCP binding expected")
        };
        let server = std::env::var("INTEROP_ADB_SERVER")
            .unwrap()
            .parse()
            .unwrap();
        let observer = Client::connect_server(
            server,
            &format!("{address}:{}", std::env::var("INTEROP_ADBD_PORT").unwrap()),
            OperationOptions::default(),
        )
        .await
        .unwrap();
        client.close();
        tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                if !observer
                    .reverse_list(OperationOptions::default())
                    .await
                    .unwrap()
                    .iter()
                    .any(|e| e.device_service == format!("tcp:{port}"))
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        observer.close();
    }
    echo.abort();
    client.close();
}
