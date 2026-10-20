use super::*;
use interop_adb::{DeviceInfo, protocol};

fn connection() -> (Client, tokio::io::DuplexStream) {
    let (transport, peer) = tokio::io::duplex(4096);
    let client = Client::from_negotiated_transport(
        transport,
        DeviceInfo {
            version: protocol::VERSION,
            max_payload: 4096,
            banner: "device::features=shell_v2;\0".into(),
            features: ["shell_v2".into()].into(),
        },
    )
    .unwrap();
    (client, peer)
}

fn helper() -> (Arc<Companion>, mpsc::Receiver<Request>) {
    let (requests, receiver) = mpsc::channel(32);
    let (_, stopped) = watch::channel(false);
    (
        Arc::new(Companion {
            id: uuid::Uuid::new_v4(),
            cancellation: CancellationToken::new(),
            requests,
            state: Arc::new(RwLock::new(json!({}))),
            stopped,
        }),
        receiver,
    )
}

#[tokio::test]
async fn app_reads_reject_late_success_from_offline_replaced_or_cancelled_owners() {
    for command in ["apps.list", "apps.icon"] {
        for change in [
            "unchanged",
            "offline",
            "client_replaced",
            "client_closed",
            "helper_replaced",
            "helper_cancelled",
        ] {
            let directory = tempfile::tempdir().unwrap();
            let runtime = Runtime::initialize(directory.path()).await.unwrap();
            let device = runtime
                .add_device(&json!({"address":"127.0.0.1","port":9}))
                .await
                .unwrap();
            let id = device["deviceId"].as_str().unwrap().to_owned();
            {
                let mut store = runtime.store.write().await;
                store.devices[0].status = "connected".into();
                store.devices[0].observation_wanted = false;
            }
            let (client, _peer) = connection();
            runtime
                .connections
                .lock()
                .await
                .insert(id.clone(), client.clone());
            let (original, mut requests) = helper();
            runtime
                .companions
                .lock()
                .await
                .insert(id.clone(), original.clone());
            let owner = runtime.clone();
            let device = id.clone();
            let invocation = tokio::spawn(async move {
                owner.invoke(command, json!({"deviceId":device,"filter":"running","packageName":"com.android.settings","allowStart":false})).await
            });
            let request = requests.recv().await.unwrap();
            assert_eq!(request.payload["command"], command);
            let (replacement, _replacement_peer) = connection();
            let (new_helper, _new_requests) = helper();
            match change {
                "offline" => runtime.store.write().await.devices[0].status = "offline".into(),
                "client_replaced" => {
                    runtime
                        .connections
                        .lock()
                        .await
                        .insert(id.clone(), replacement);
                }
                "client_closed" => client.close(),
                "helper_replaced" => {
                    runtime
                        .companions
                        .lock()
                        .await
                        .insert(id.clone(), new_helper);
                }
                "helper_cancelled" => original.cancellation.cancel(),
                _ => {}
            }
            // Deliver a real successful RPC receipt after ownership changed. A
            // connected replacement must never endorse the original request.
            request
                .result
                .send(Ok(json!({"apps":[],"dataBase64":"old-icon","live":true})))
                .unwrap();
            let result = invocation.await.unwrap();
            if change == "unchanged" {
                assert_eq!(result.unwrap()["deviceId"], id);
            } else {
                assert_eq!(result.unwrap_err().code, "cancelled", "{command}/{change}");
            }
            client.close();
        }
    }
}
