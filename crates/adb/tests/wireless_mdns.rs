//! Uses real UDP multicast, so opt in on a network-enabled test machine.
use interop_adb::{
    OperationOptions,
    wireless::discovery::{CONNECT_SERVICE, Discovery, DiscoveryEvent, ServiceKind},
};
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::time::Duration;

#[tokio::test]
#[ignore = "requires multicast-capable local networking"]
async fn discovers_connect_metadata_and_goodbye_over_actual_mdns() {
    let browser = Discovery::new().unwrap();
    let publisher = ServiceDaemon::new().unwrap();
    let instance = format!("adb-interop-test-{}", std::process::id());
    let service = ServiceInfo::new(
        CONNECT_SERVICE,
        &instance,
        "adb-interop-test.local.",
        "",
        38765,
        [("v", "2"), ("test", "metadata")].as_slice(),
    )
    .unwrap()
    .enable_addr_auto();
    let fullname = service.get_fullname().to_owned();
    publisher.register(service).unwrap();
    let options = OperationOptions {
        timeout: Duration::from_secs(10),
        ..Default::default()
    };
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            if let DiscoveryEvent::Resolved(service) = browser.next(&options).await.unwrap()
                && service.instance == instance
            {
                assert_eq!(service.kind, ServiceKind::Connect);
                assert_eq!(service.hostname, "adb-interop-test.local.");
                assert_eq!(service.properties.get("v").unwrap(), "2");
                assert_eq!(service.properties.get("test").unwrap(), "metadata");
                assert!(!service.endpoints.is_empty());
                assert!(
                    service
                        .endpoints
                        .iter()
                        .all(|address| address.port() == 38765)
                );
                break;
            }
        }
    })
    .await
    .unwrap();
    publisher.unregister(&fullname).unwrap();
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            if let DiscoveryEvent::Removed { fullname: removed } =
                browser.next(&options).await.unwrap()
                && removed == fullname
            {
                break;
            }
        }
    })
    .await
    .unwrap();
    publisher.shutdown().unwrap();
}
