use interop_adb::{
    Client, ConnectOptions, DeviceInfo, OperationOptions,
    protocol::{self, Frame},
};
use tokio::io::{AsyncRead, AsyncReadExt};

async fn wire_frame(reader: &mut (impl AsyncRead + Unpin)) -> (Frame, u32) {
    let mut header = [0; 24];
    reader.read_exact(&mut header).await.unwrap();
    let word = |offset| u32::from_le_bytes(header[offset..offset + 4].try_into().unwrap());
    let mut payload = vec![0; word(12) as usize];
    reader.read_exact(&mut payload).await.unwrap();
    (Frame::new(word(0), word(4), word(8), payload), word(16))
}
fn checksum(payload: &[u8]) -> u32 {
    payload.iter().map(|byte| *byte as u32).sum()
}

async fn negotiated_open_checksum(version: u32) -> (u32, u32) {
    let (transport, mut peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version,
            max_payload: 4096,
            banner: "device::".into(),
            features: Default::default(),
        },
    )
    .unwrap();
    let opener = client.clone();
    let task =
        tokio::spawn(async move { opener.open("fixture:", OperationOptions::default()).await });
    let (open, wire_checksum) = wire_frame(&mut peer).await;
    client.close();
    task.abort();
    (wire_checksum, checksum(&open.payload))
}

#[tokio::test]
async fn legacy_transport_sends_payload_checksum() {
    let (actual, expected) = negotiated_open_checksum(protocol::LEGACY_VERSION).await;
    assert_eq!(actual, expected);
    assert_ne!(actual, 0);
}

#[tokio::test]
async fn modern_transport_omits_payload_checksum() {
    assert_eq!(negotiated_open_checksum(protocol::VERSION).await.0, 0);
}

#[tokio::test]
async fn handshake_has_checksum_before_modern_negotiation() {
    let (transport, mut peer) = tokio::io::duplex(4096);
    let connector = tokio::spawn(async move {
        Client::connect_transport(transport, ConnectOptions::default())
            .await
            .unwrap()
    });
    let (connect, actual) = wire_frame(&mut peer).await;
    assert_eq!(connect.command, protocol::CNXN);
    assert_eq!(actual, checksum(&connect.payload));
    assert_ne!(actual, 0);
    Frame::new(
        protocol::CNXN,
        protocol::VERSION,
        4096,
        b"device::features=;\0",
    )
    .write(&mut peer)
    .await
    .unwrap();
    let client = connector.await.unwrap();
    let opener = client.clone();
    let task =
        tokio::spawn(async move { opener.open("fixture:", OperationOptions::default()).await });
    let (_, actual) = wire_frame(&mut peer).await;
    client.close();
    task.abort();
    assert_eq!(actual, 0);
}

#[tokio::test]
async fn public_frame_write_keeps_checksum() {
    let frame = Frame::new(protocol::WRTE, 1, 2, b"payload");
    let mut bytes = Vec::new();
    frame.write(&mut bytes).await.unwrap();
    assert_eq!(
        wire_frame(&mut bytes.as_slice()).await.1,
        checksum(&frame.payload)
    );
}

#[tokio::test]
async fn negotiated_checksum_policy_covers_stream_data() {
    for version in [protocol::LEGACY_VERSION, protocol::VERSION] {
        let (transport, mut peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version,
                max_payload: 4096,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        let opener = client.clone();
        let opening = tokio::spawn(async move {
            opener
                .open("fixture:", OperationOptions::default())
                .await
                .unwrap()
        });
        let (open, _) = wire_frame(&mut peer).await;
        Frame::new(protocol::OKAY, 41, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let mut stream = opening.await.unwrap();
        let writing = tokio::spawn(async move { stream.write_all(b"nonempty data").await });
        let (data, actual) = wire_frame(&mut peer).await;
        assert_eq!(data.command, protocol::WRTE);
        assert_eq!(
            actual,
            if version >= protocol::VERSION {
                0
            } else {
                checksum(&data.payload)
            }
        );
        client.close();
        writing.abort();
    }
}

#[tokio::test]
async fn auth_signature_and_public_key_keep_checksums_until_cnxn() {
    let identity = interop_adb::Identity::generate().unwrap();
    let (transport, mut peer) = tokio::io::duplex(4096);
    let connector = tokio::spawn(async move {
        Client::connect_transport(
            transport,
            ConnectOptions {
                identity: Some(identity),
                request_authorization: true,
                ..Default::default()
            },
        )
        .await
        .unwrap()
    });
    let (connect, actual) = wire_frame(&mut peer).await;
    assert_eq!(actual, checksum(&connect.payload));
    for response_type in [2, 3] {
        Frame::new(protocol::AUTH, 1, 0, vec![7; 20])
            .write(&mut peer)
            .await
            .unwrap();
        let (auth, actual) = wire_frame(&mut peer).await;
        assert_eq!((auth.command, auth.arg0), (protocol::AUTH, response_type));
        assert_eq!(actual, checksum(&auth.payload));
        assert_ne!(actual, 0);
    }
    Frame::new(protocol::CNXN, protocol::VERSION, 4096, b"device::\0")
        .write(&mut peer)
        .await
        .unwrap();
    connector.await.unwrap().close();
}
