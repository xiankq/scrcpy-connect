//! Restored records must retain their transport security requirement.
use interop_adb::protocol::{self, Frame};
use interop_core::{CoreResult, Runtime};
use serde_json::{Value, json};
use std::time::Duration;
use tokio::net::TcpListener;

async fn connect_record(transport: &str, paired: bool) -> (CoreResult<Value>, Value, usize) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        assert_eq!(
            Frame::read(&mut socket, 4096, false).await.unwrap().command,
            protocol::CNXN
        );
        Frame::new(
            protocol::CNXN,
            protocol::VERSION,
            4096,
            b"device::features=shell_v2;\0".to_vec(),
        )
        .write(&mut socket)
        .await
        .unwrap();
        let mut services = 0;
        while let Ok(frame) = Frame::read(&mut socket, 4096, false).await {
            if frame.command == protocol::OPEN {
                services += 1;
                // Metadata absence is not proof of a matching device identity.
                Frame::new(protocol::CLSE, 0, frame.arg0, Vec::new())
                    .write(&mut socket)
                    .await
                    .unwrap();
            }
        }
        services
    });
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = runtime
        .invoke("devices.add", json!({"address":"127.0.0.1","port":port}))
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap().to_owned();
    drop(runtime);
    // Input fixture represents a previously paired/restored device record.
    let path = directory.path().join("devices.json");
    let mut store: Value = serde_json::from_slice(&tokio::fs::read(&path).await.unwrap()).unwrap();
    let record = &mut store["devices"][0];
    record["transport"] = json!(transport);
    record["guid"] = if paired {
        json!("paired-fixture")
    } else {
        Value::Null
    };
    record["serial"] = json!("known-device-serial");
    record["observationWanted"] = json!(false);
    tokio::fs::write(&path, serde_json::to_vec(&store).unwrap())
        .await
        .unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let result = tokio::time::timeout(
        Duration::from_secs(20),
        runtime.invoke("devices.connect", json!({"deviceId":id})),
    )
    .await
    .unwrap();
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    let services = tokio::time::timeout(Duration::from_secs(2), server)
        .await
        .unwrap()
        .unwrap();
    (result, record, services)
}

#[tokio::test]
async fn paired_records_refuse_plaintext_even_when_metadata_has_no_serial() {
    for transport in ["tls", "tcp"] {
        let (result, record, services) = connect_record(transport, true).await;
        let error = result.expect_err("a paired modern endpoint must require TLS");
        assert!(error.message.contains("TLS is required"), "{error:?}");
        assert_ne!(record["status"], "connected");
        assert_eq!(
            services, 0,
            "must reject before querying any device service"
        );
    }
}

#[tokio::test]
async fn legacy_tcp_records_still_accept_a_plaintext_daemon() {
    let (result, record, services) = connect_record("tcp", false).await;
    assert_eq!(result.unwrap()["connected"], true);
    assert_eq!(record["status"], "connected");
    assert_eq!(services, 1, "the legacy connection proceeds to metadata");
}
