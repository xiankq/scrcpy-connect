//! Run against an authorization-enforcing Android wireless connection listener.
//! The isolated Runtime always creates an identity that has never been paired.
use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
#[ignore = "requires secure Android TLS listener rejecting a fresh identity"]
async fn actual_unpaired_certificate_is_unauthorized_and_stops_reconnect() {
    let endpoint = std::env::var("ANDROID_TLS_ENDPOINT").expect("ANDROID_TLS_ENDPOINT");
    let (host, port) = endpoint.rsplit_once(':').expect("host:port fixture");
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let added = runtime
        .invoke(
            "devices.add",
            json!({"address":host,"port":port.parse::<u16>().unwrap(),"transport":"tls"}),
        )
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap();
    let failure = runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .expect_err("an unpaired identity must not establish a TLS transport");
    assert!(
        failure.message.contains("CertificateUnknown"),
        "this case requires the real Android client-certificate rejection, not a network failure"
    );
    let record = runtime
        .invoke("device.info", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(record["status"], "unauthorized");
    assert_eq!(record["autoReconnect"], false);
    assert!(record["guid"].is_null());
}
