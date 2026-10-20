//! Real UDP DNS-SD and independent BoringSSL PAKE regression for QR pairing.
use super::*;
use interop_adb::wireless::discovery::PAIRING_SERVICE;
use std::{
    io::{BufRead, BufReader, Write},
    net::{IpAddr, Ipv4Addr, UdpSocket},
    process::{Child, Command, Stdio},
};

struct Peer(Child);
impl Drop for Peer {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

struct Task(tokio::task::JoinHandle<()>);
impl Drop for Task {
    fn drop(&mut self) {
        self.0.abort();
    }
}

struct Advertisement {
    task: Task,
    socket: UdpSocket,
    goodbye: Vec<u8>,
}
impl Drop for Advertisement {
    fn drop(&mut self) {
        self.task.0.abort();
        let _ = self.socket.send_to(&self.goodbye, "224.0.0.251:5353");
    }
}

fn local_address() -> Ipv4Addr {
    let socket = UdpSocket::bind("0.0.0.0:0").unwrap();
    socket.connect("224.0.0.251:5353").unwrap();
    let IpAddr::V4(address) = socket.local_addr().unwrap().ip() else {
        panic!("multicast-capable IPv4 interface required")
    };
    address
}

fn start_peer(address: Ipv4Addr, payload: &str) -> (Peer, u16) {
    let password = payload
        .split(';')
        .find_map(|field| field.strip_prefix("P:"))
        .expect("QR password field");
    let mut child = Command::new(
        std::env::var("ADB_BORINGSSL_FIXTURE")
            .expect("set ADB_BORINGSSL_FIXTURE to the compiled adjacent C++ fixture"),
    )
    .args(["qr", &address.to_string()])
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::inherit())
    .spawn()
    .unwrap();
    writeln!(child.stdin.take().unwrap(), "{password}").unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.as_mut().unwrap())
        .read_line(&mut line)
        .unwrap();
    let port = line.trim().parse().expect("fixture listener port");
    (Peer(child), port)
}

fn name(output: &mut Vec<u8>, value: &str) {
    for label in value.trim_end_matches('.').split('.') {
        output.push(label.len().try_into().unwrap());
        output.extend_from_slice(label.as_bytes());
    }
    output.push(0);
}

fn record(output: &mut Vec<u8>, owner: &str, kind: u16, ttl: u32, data: &[u8]) {
    name(output, owner);
    output.extend_from_slice(&kind.to_be_bytes());
    output.extend_from_slice(&1u16.to_be_bytes());
    output.extend_from_slice(&ttl.to_be_bytes());
    output.extend_from_slice(&(data.len() as u16).to_be_bytes());
    output.extend_from_slice(data);
}

// One DNS response carries both A records, so the resolver observes the exact
// candidate set together. A raw response also allows a deterministic loopback
// stall, instead of depending on a remote machine or a firewall black hole.
fn announcement(service: &str, address: Ipv4Addr, port: u16, ttl: u32) -> Vec<u8> {
    let fullname = format!("{service}.{PAIRING_SERVICE}");
    let hostname = format!("{service}.local.");
    let mut packet = vec![0, 0, 0x84, 0, 0, 0, 0, 5, 0, 0, 0, 0];
    let mut target = vec![];
    name(&mut target, &fullname);
    record(&mut packet, PAIRING_SERVICE, 12, ttl, &target);
    let mut srv = vec![0, 0, 0, 0];
    srv.extend_from_slice(&port.to_be_bytes());
    name(&mut srv, &hostname);
    record(&mut packet, &fullname, 33, ttl, &srv);
    record(&mut packet, &fullname, 16, ttl, &[0]);
    record(
        &mut packet,
        &hostname,
        1,
        ttl,
        &Ipv4Addr::LOCALHOST.octets(),
    );
    record(&mut packet, &hostname, 1, ttl, &address.octets());
    packet
}

fn advertise(service: &str, address: Ipv4Addr, port: u16) -> Advertisement {
    let packet = announcement(service, address, port, 120);
    let socket = socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    )
    .unwrap();
    socket.set_reuse_address(true).unwrap();
    socket
        .bind(&SocketAddr::from((address, 5353)).into())
        .unwrap();
    socket.set_multicast_if_v4(&address).unwrap();
    let socket: UdpSocket = socket.into();
    let sending = socket.try_clone().unwrap();
    let task = Task(tokio::spawn(async move {
        loop {
            sending.send_to(&packet, "224.0.0.251:5353").unwrap();
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }));
    Advertisement {
        task,
        socket,
        goodbye: announcement(service, address, port, 0),
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires IPv4 multicast and ADB_BORINGSSL_FIXTURE built with official BoringSSL"]
async fn qr_pairing_tries_a_working_address_after_a_stalled_tls_endpoint() {
    let address = local_address();
    let directory = tempfile::tempdir().unwrap();
    let mut policy = crate::ConnectionPolicy::standalone();
    policy.endpoint_timeout_ms = 2_000;
    policy.qr_pairing_timeout_ms = 12_000;
    let runtime = Runtime::initialize_with_connection_policy(directory.path(), policy)
        .await
        .unwrap();
    let receipt = runtime
        .invoke(
            "adb.pair.qr",
            json!({"attemptId":"qr-endpoints","leaseMs":30000}),
        )
        .await
        .unwrap();
    let (mut peer, port) = start_peer(address, receipt["payload"].as_str().unwrap());
    let stalled = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, port))
        .await
        .unwrap();
    let (accepted, observed_stall) = tokio::sync::oneshot::channel();
    let _stall = Task(tokio::spawn(async move {
        let (_socket, _) = stalled.accept().await.unwrap();
        let _ = accepted.send(());
        std::future::pending::<()>().await;
    }));
    let _advertisement = advertise(receipt["serviceName"].as_str().unwrap(), address, port);
    tokio::time::timeout(Duration::from_secs(5), observed_stall)
        .await
        .expect("QR discovery must actually attempt the first advertised socket")
        .unwrap();
    let outcome = tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            let state = runtime
                .invoke(
                    "adb.operation.get",
                    json!({"operationId":receipt["operationId"]}),
                )
                .await
                .unwrap();
            if matches!(
                state["outcome"]["status"].as_str(),
                Some("completed" | "failed")
            ) {
                break state["outcome"].clone();
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("QR operation must settle within its overall deadline");
    assert_eq!(outcome["status"], "completed", "{outcome}");
    assert_eq!(outcome["result"]["paired"], true);
    assert_eq!(
        outcome["result"]["device"]["guid"],
        "adb-boringssl-official-crypto"
    );
    assert!(peer.0.wait().unwrap().success());
    runtime
        .invoke(
            "adb.operation.release",
            json!({"operationId":receipt["operationId"]}),
        )
        .await
        .unwrap();
}
