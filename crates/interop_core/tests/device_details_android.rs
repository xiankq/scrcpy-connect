use interop_core::Runtime;
use serde_json::json;

#[tokio::test]
#[ignore = "requires an explicit authorized Android ADB endpoint; read-only target facts"]
async fn target_facts_are_current_readable_and_fenced_to_one_connection() {
    let endpoint: std::net::SocketAddr = std::env::var("INTEROP_CORE_TEST_ENDPOINT")
        .expect("explicit INTEROP_CORE_TEST_ENDPOINT")
        .parse()
        .unwrap();
    let root = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(root.path()).await.unwrap();
    let added = runtime
        .invoke(
            "devices.add",
            json!({
                "address":endpoint.ip().to_string(), "port":endpoint.port()
            }),
        )
        .await
        .unwrap();
    let id = added["deviceId"].as_str().unwrap();
    runtime
        .invoke("devices.connect", json!({"deviceId":id}))
        .await
        .unwrap();
    let data = runtime
        .invoke("device.data.get", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(data["deviceId"], id);
    assert_eq!(data["stale"], false);
    assert!(
        data["system"]["model"]
            .as_str()
            .is_some_and(|s| !s.is_empty()),
        "{data}"
    );
    assert!(
        data["display"]["width"].as_u64().is_some_and(|n| n > 0),
        "{data}"
    );
    assert!(
        data["display"]["height"].as_u64().is_some_and(|n| n > 0),
        "{data}"
    );
    assert!(
        data["display"]["densityDpi"]
            .as_u64()
            .is_some_and(|n| n > 0),
        "{data}"
    );
    assert!(
        data["memory"]["totalBytes"].as_u64().is_some_and(|n| n > 0),
        "{data}"
    );
    assert!(
        data["display"]["refreshRate"]
            .as_f64()
            .is_some_and(|n| n > 0.0),
        "{data}"
    );
    assert!(
        data["storage"]["totalBytes"]
            .as_u64()
            .is_some_and(|n| n > 0),
        "{data}"
    );
    assert!(
        data["battery"]["level"].as_u64().is_some_and(|n| n <= 100),
        "{data}"
    );
    let connection = data["connectionId"].as_str().unwrap();
    let network = runtime
        .invoke(
            "device.network.get",
            json!({"deviceId":id,"connectionId":connection}),
        )
        .await
        .unwrap();
    assert_eq!(network["connectionId"], connection);
    assert!(
        !network["addresses"].as_array().unwrap().is_empty(),
        "{network}"
    );
    let screen = runtime
        .invoke(
            "device.screen.state",
            json!({"deviceId":id,"connectionId":connection}),
        )
        .await
        .unwrap();
    assert!(screen["screenOn"].is_boolean(), "{screen}");
    assert!(screen["locked"].is_boolean(), "{screen}");
    for command in [
        "device.data.get",
        "device.network.get",
        "device.screen.state",
    ] {
        assert_eq!(
            runtime
                .invoke(
                    command,
                    json!({"deviceId":id,"connectionId":"another-connection"})
                )
                .await
                .unwrap_err()
                .code,
            "stale_connection"
        );
    }
    println!(
        "actual facts: model={} display={} battery={} addresses={} failures={}",
        data["system"]["model"],
        data["display"],
        data["battery"],
        network["addresses"],
        data["failures"]
    );
    runtime
        .invoke("devices.disconnect", json!({"deviceId":id}))
        .await
        .unwrap();
    let offline = runtime
        .invoke("device.data.get", json!({"deviceId":id}))
        .await
        .unwrap();
    assert_eq!(offline["stale"], true);
    assert!(offline["battery"].is_null());
    assert!(offline["display"].is_null());
}
