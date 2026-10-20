use super::*;
use interop_adb::protocol::{self, Frame};
use tokio::{net::TcpListener, sync::oneshot};

fn shell_reply(text: &[u8]) -> Vec<u8> {
    let mut bytes = vec![1];
    bytes.extend_from_slice(&(text.len() as u32).to_le_bytes());
    bytes.extend_from_slice(text);
    bytes.extend_from_slice(&[3, 1, 0, 0, 0, 0]);
    bytes
}

#[tokio::test]
async fn connection_is_usable_before_optional_battery_response() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let (battery_started, started) = oneshot::channel();
    let (release_battery, release) = oneshot::channel();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        socket.set_nodelay(true).unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0",
        )
        .write(&mut socket)
        .await
        .unwrap();
        let mut started = Some(battery_started);
        let mut release = Some(release);
        while let Ok(frame) = Frame::read(&mut socket, 4096, true).await {
            if frame.command != protocol::OPEN {
                continue;
            }
            Frame::new(protocol::OKAY, frame.arg0 + 100, frame.arg0, [])
                .write(&mut socket)
                .await
                .unwrap();
            let service = String::from_utf8_lossy(&frame.payload);
            let text = if service.contains("dumpsys battery") {
                let _ = started.take().unwrap().send(());
                let _ = release.take().unwrap().await;
                b"level: 81\nscale: 100\n".as_slice()
            } else {
                assert!(service.contains("getprop ro.serialno"));
                b"Fixture\n16\n36\nfixture-serial\n".as_slice()
            };
            if Frame::new(
                protocol::WRTE,
                frame.arg0 + 100,
                frame.arg0,
                shell_reply(text),
            )
            .write(&mut socket)
            .await
            .is_err()
            {
                break;
            }
        }
    });
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = runtime
        .add_device(
            &json!({"address":address.ip().to_string(), "port":address.port(), "transport":"tcp"}),
        )
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap();
    runtime
        .store
        .write()
        .await
        .devices
        .iter_mut()
        .find(|device| device.id == id)
        .unwrap()
        .observation_wanted = false;
    let connecting = {
        let runtime = runtime.clone();
        let id = id.to_owned();
        tokio::spawn(async move {
            runtime
                .connect_device_with_attempt(&id, None, false, None, None, None)
                .await
        })
    };
    // First witness the withheld query. RSA/TLS setup and parallel test load
    // must not be mistaken for a dependency on the optional battery response.
    tokio::time::timeout(Duration::from_secs(30), started)
        .await
        .unwrap()
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), connecting)
        .await
        .expect("optional battery must not hold the connection in connecting")
        .unwrap()
        .unwrap();
    assert_eq!(runtime.device(id).await.unwrap().status, "connected");
    assert!(runtime.client(id).await.is_ok());
    assert_eq!(runtime.device(id).await.unwrap().battery, None);
    let _ = release_battery.send(());
    tokio::time::timeout(Duration::from_secs(1), async {
        while runtime.device(id).await.unwrap().battery != Some(81) {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    runtime.stop_all().await;
    server.abort();
}
