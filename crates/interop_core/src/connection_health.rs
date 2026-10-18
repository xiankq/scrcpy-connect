//! Idle connection health, independent of observation and control sessions.
//! Only silence across two bounded ADB OPENs can retire a transport. A busy
//! stream is stronger evidence of health than any individual service response.
use interop_adb::{Client, Error, OperationOptions};
use std::{collections::HashMap, time::Duration};
use tokio::{sync::oneshot, task::JoinHandle, time::Instant};
use tokio_util::sync::CancellationToken;

const IDLE: Duration = Duration::from_secs(10);
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Default)]
pub(crate) struct ConnectionHealth {
    connections: HashMap<String, Health>,
}

struct Health {
    client: Client,
    activity: usize,
    last_activity: Instant,
    timeouts: u8,
    probe: Option<Probe>,
}

struct Probe {
    result: oneshot::Receiver<bool>,
    cancellation: CancellationToken,
    task: JoinHandle<()>,
}

impl Probe {
    fn start(client: Client, timeout: Duration) -> Self {
        let cancellation = CancellationToken::new();
        let token = cancellation.clone();
        let (sender, result) = oneshot::channel();
        let task = tokio::spawn(async move {
            let result = client
                .open(
                    "sync:",
                    OperationOptions {
                        timeout,
                        cancellation: token,
                    },
                )
                .await;
            // Drop an accepted service immediately: no sync commands, file IO,
            // shell or process. CLSE rejection also advances inbound_activity.
            let timed_out = matches!(result, Err(Error::Timeout));
            drop(result);
            let _ = sender.send(timed_out);
        });
        Self {
            result,
            cancellation,
            task,
        }
    }
}

impl Drop for Probe {
    fn drop(&mut self) {
        self.cancellation.cancel();
        self.task.abort();
    }
}

impl ConnectionHealth {
    /// Called with the current connection map locked. Tasks only report their
    /// outcome; they can never close a replacement connection or retain Runtime.
    pub(crate) fn tick(&mut self, connections: &HashMap<String, Client>) {
        self.tick_at(connections, Instant::now(), IDLE, PROBE_TIMEOUT);
    }

    fn tick_at(
        &mut self,
        connections: &HashMap<String, Client>,
        now: Instant,
        idle: Duration,
        timeout: Duration,
    ) {
        self.connections.retain(|id, health| {
            connections
                .get(id)
                .is_some_and(|client| !client.is_closed() && client.same_connection(&health.client))
        });
        for (id, client) in connections {
            if client.is_closed() {
                continue;
            }
            let health = self
                .connections
                .entry(id.clone())
                .or_insert_with(|| Health {
                    client: client.clone(),
                    activity: client.inbound_activity(),
                    last_activity: now,
                    timeouts: 0,
                    probe: None,
                });
            let activity = client.inbound_activity();
            if activity != health.activity {
                health.activity = activity;
                health.last_activity = now;
                health.timeouts = 0;
                health.probe = None;
            }
            if let Some(probe) = &mut health.probe {
                match probe.result.try_recv() {
                    Ok(timed_out) => {
                        health.probe = None;
                        if timed_out {
                            health.timeouts += 1;
                            if health.timeouts == 2 {
                                // Recheck after collecting the result, so traffic
                                // racing this tick also rescues the connection.
                                if client.inbound_activity() == health.activity {
                                    client.close();
                                    continue;
                                }
                                health.activity = client.inbound_activity();
                                health.last_activity = now;
                                health.timeouts = 0;
                            }
                        } else {
                            // Local limits/errors are inconclusive, never a dead
                            // daemon. Retry only after another idle interval.
                            health.timeouts = 0;
                            health.last_activity = now;
                        }
                    }
                    Err(oneshot::error::TryRecvError::Empty) => continue,
                    Err(oneshot::error::TryRecvError::Closed) => {
                        health.probe = None;
                        health.timeouts = 0;
                        health.last_activity = now;
                    }
                }
            }
            if now.duration_since(health.last_activity) >= idle {
                health.probe = Some(Probe::start(client.clone(), timeout));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    use tokio::io::{AsyncWriteExt, DuplexStream};

    const WAIT: Duration = Duration::from_secs(1);
    const TIMEOUT: Duration = Duration::from_millis(25);

    fn connection() -> (Client, DuplexStream) {
        connection_with_limit(4096)
    }

    fn connection_with_limit(max_payload: usize) -> (Client, DuplexStream) {
        let (transport, peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload,
                banner: "device::\0".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        (client, peer)
    }

    async fn receive(peer: &mut DuplexStream) -> Frame {
        tokio::time::timeout(WAIT, Frame::read(peer, 4096, true))
            .await
            .unwrap()
            .unwrap()
    }

    async fn inbound(client: &Client, before: usize) {
        tokio::time::timeout(WAIT, async {
            while client.inbound_activity() == before {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }

    async fn expired(peer: &mut DuplexStream, open: &Frame) {
        // The cancelled pending OPEN releases its route and sends CLSE.
        let close = receive(peer).await;
        assert_eq!(close.command, protocol::CLSE);
        assert_eq!(close.arg0, open.arg0);
        tokio::task::yield_now().await;
    }

    #[tokio::test]
    async fn two_silent_timeouts_close_only_the_unresponsive_connection() {
        let (client, mut peer) = connection();
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let start = Instant::now();
        health.tick_at(&connections, start, IDLE, TIMEOUT);
        health.tick_at(&connections, start + IDLE, IDLE, TIMEOUT);
        let first = receive(&mut peer).await;
        assert_eq!(first.command, protocol::OPEN);
        assert_eq!(first.payload, b"sync:\0");
        // Repeated ticks never create a second concurrent probe.
        health.tick_at(&connections, start + IDLE, IDLE, TIMEOUT);
        expired(&mut peer, &first).await;
        assert!(!client.is_closed());
        health.tick_at(&connections, start + IDLE + TIMEOUT, IDLE, TIMEOUT);
        let second = receive(&mut peer).await;
        assert_eq!(second.command, protocol::OPEN);
        expired(&mut peer, &second).await;
        health.tick_at(&connections, start + IDLE + 2 * TIMEOUT, IDLE, TIMEOUT);
        assert!(client.is_closed());
    }

    #[tokio::test]
    async fn healthy_responses_are_immediately_closed_and_never_disconnect() {
        let (client, mut peer) = connection();
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let mut now = Instant::now();
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        for command in [protocol::OKAY, protocol::CLSE, protocol::OKAY] {
            now += IDLE;
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            let mut open = receive(&mut peer).await;
            // Rejected pending OPENs can send both the protocol close response
            // and the existing AdbStream Drop cleanup.
            while open.command == protocol::CLSE {
                open = receive(&mut peer).await;
            }
            assert_eq!(open.command, protocol::OPEN);
            assert_eq!(open.payload, b"sync:\0");
            let before = client.inbound_activity();
            Frame::new(command, 7, open.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            inbound(&client, before).await;
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            let close = receive(&mut peer).await;
            assert_eq!(close.command, protocol::CLSE);
            assert_eq!(close.arg0, open.arg0);
            assert!(!client.is_closed());
        }
        client.close();
    }

    #[tokio::test]
    async fn stream_traffic_rescues_a_stalled_probe_and_suppresses_idle_probes() {
        let (client, mut peer) = connection();
        let opener = client.clone();
        let opening = tokio::spawn(async move {
            opener
                .open("localabstract:video", OperationOptions::default())
                .await
                .unwrap()
        });
        let video = receive(&mut peer).await;
        Frame::new(protocol::OKAY, 17, video.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let mut video_stream = opening.await.unwrap();
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let mut now = Instant::now();
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        now += IDLE;
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        let probe = receive(&mut peer).await;
        assert_eq!(probe.payload, b"sync:\0");
        for _ in 0..5 {
            let before = client.inbound_activity();
            Frame::new(protocol::WRTE, 17, video.arg0, b"video".to_vec())
                .write(&mut peer)
                .await
                .unwrap();
            inbound(&client, before).await;
            now += Duration::from_secs(2);
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            let mut bytes = [0; 5];
            video_stream.read_exact(&mut bytes).await.unwrap();
            assert_eq!(&bytes, b"video");
            // First iteration also cancels and closes the stalled probe.
            let mut acknowledgment = receive(&mut peer).await;
            if acknowledgment.command == protocol::CLSE {
                assert_eq!(acknowledgment.arg0, probe.arg0);
                acknowledgment = receive(&mut peer).await;
            }
            assert_eq!(acknowledgment.command, protocol::OKAY);
            assert_eq!(acknowledgment.arg0, video.arg0);
            assert!(!client.is_closed());
        }
        assert!(
            tokio::time::timeout(TIMEOUT, receive(&mut peer))
                .await
                .is_err()
        );
        client.close();
    }

    #[tokio::test]
    async fn completed_old_timeout_cannot_retire_a_replacement() {
        let (old, mut old_peer) = connection();
        let mut connections = HashMap::from([("device".into(), old.clone())]);
        let mut health = ConnectionHealth::default();
        let start = Instant::now();
        health.tick_at(&connections, start, IDLE, TIMEOUT);
        health.tick_at(&connections, start + IDLE, IDLE, TIMEOUT);
        let first = receive(&mut old_peer).await;
        expired(&mut old_peer, &first).await;
        health.tick_at(&connections, start + IDLE + TIMEOUT, IDLE, TIMEOUT);
        let second = receive(&mut old_peer).await;
        expired(&mut old_peer, &second).await;
        let (replacement, mut replacement_peer) = connection();
        connections.insert("device".into(), replacement.clone());
        health.tick_at(&connections, start + IDLE + 2 * TIMEOUT, IDLE, TIMEOUT);
        assert!(!replacement.is_closed());
        assert!(
            !old.is_closed(),
            "stale results must be discarded before applying them"
        );
        assert!(
            tokio::time::timeout(TIMEOUT, receive(&mut replacement_peer))
                .await
                .is_err()
        );
        old.close();
        replacement.close();
    }

    #[tokio::test]
    async fn removing_connection_or_dropping_manager_cancels_pending_open() {
        for drop_manager in [false, true] {
            let (client, mut peer) = connection();
            let mut connections = HashMap::from([("device".into(), client.clone())]);
            let mut health = ConnectionHealth::default();
            let start = Instant::now();
            health.tick_at(&connections, start, IDLE, WAIT);
            health.tick_at(&connections, start + IDLE, IDLE, WAIT);
            let probe = receive(&mut peer).await;
            if drop_manager {
                drop(health);
            } else {
                connections.clear();
                health.tick_at(&connections, start + IDLE, IDLE, WAIT);
            }
            // Observe real pending OPEN cleanup, before its one-second timeout.
            let close = tokio::time::timeout(Duration::from_millis(200), receive(&mut peer))
                .await
                .unwrap();
            assert_eq!(close.command, protocol::CLSE);
            assert_eq!(close.arg0, probe.arg0);
            assert!(!client.is_closed());
            assert!(
                tokio::time::timeout(TIMEOUT, receive(&mut peer))
                    .await
                    .is_err()
            );
            client.close();
        }
    }

    #[tokio::test]
    async fn local_stream_limit_does_not_count_as_a_silent_timeout() {
        let (client, mut peer) = connection();
        let mut busy = tokio::task::JoinSet::new();
        for _ in 0..128 {
            let owner = client.clone();
            busy.spawn(async move { owner.open("busy:", OperationOptions::default()).await });
            assert_eq!(receive(&mut peer).await.command, protocol::OPEN);
        }
        assert!(matches!(
            client.open("sync:", OperationOptions::default()).await,
            Err(Error::InvalidArgument(
                "maximum concurrent ADB streams reached"
            ))
        ));
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let mut now = Instant::now();
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        for _ in 0..3 {
            now += IDLE;
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            tokio::time::sleep(TIMEOUT * 2).await;
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            assert!(!client.is_closed());
        }
        // Even repeated probes under local resource pressure emit no new OPEN.
        assert!(
            tokio::time::timeout(TIMEOUT, receive(&mut peer))
                .await
                .is_err()
        );
        client.close();
    }

    #[tokio::test]
    async fn slow_partial_frame_payload_never_disconnects_a_receiving_connection() {
        let (client, mut peer) = connection_with_limit(protocol::MAX_PAYLOAD);
        let owner = client.clone();
        let opening = tokio::spawn(async move {
            owner
                .open("localabstract:video", OperationOptions::default())
                .await
                .unwrap()
        });
        let open = receive(&mut peer).await;
        Frame::new(protocol::OKAY, 17, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let mut stream = opening.await.unwrap();
        let payload = vec![7; protocol::MAX_PAYLOAD];
        let mut encoded = Vec::new();
        Frame::new(protocol::WRTE, 17, open.arg0, payload.clone())
            .write(&mut encoded)
            .await
            .unwrap();
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let mut now = Instant::now();
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        peer.write_all(&encoded[..24]).await.unwrap();
        // Model a legal 1 MiB WRTE received in 32 KiB increments across 64s.
        // The same serialized frame is still incomplete across both probe
        // deadlines; real duplex IO drives the actual Client reader.
        for chunk in encoded[24..].chunks(32 * 1024) {
            peer.write_all(chunk).await.unwrap();
            tokio::time::sleep(TIMEOUT * 2).await;
            now += Duration::from_secs(2);
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            assert!(
                !client.is_closed(),
                "continuous partial WRTE payload must keep the connection alive"
            );
        }
        let mut received = vec![0; payload.len()];
        stream.read_exact(&mut received).await.unwrap();
        assert_eq!(received, payload);
        assert_eq!(receive(&mut peer).await.command, protocol::OKAY);
        assert!(
            tokio::time::timeout(TIMEOUT, receive(&mut peer))
                .await
                .is_err()
        );
        client.close();
    }

    #[tokio::test]
    async fn slow_partial_frame_header_never_disconnects_a_receiving_connection() {
        let (client, mut peer) = connection();
        let owner = client.clone();
        let opening = tokio::spawn(async move {
            owner
                .open("localabstract:video", OperationOptions::default())
                .await
                .unwrap()
        });
        let open = receive(&mut peer).await;
        Frame::new(protocol::OKAY, 17, open.arg0, [])
            .write(&mut peer)
            .await
            .unwrap();
        let mut stream = opening.await.unwrap();
        let mut encoded = Vec::new();
        Frame::new(protocol::WRTE, 17, open.arg0, b"video".to_vec())
            .write(&mut encoded)
            .await
            .unwrap();
        let connections = HashMap::from([("device".into(), client.clone())]);
        let mut health = ConnectionHealth::default();
        let mut now = Instant::now();
        health.tick_at(&connections, now, IDLE, TIMEOUT);
        // The legal 24-byte header itself spans the idle interval and both
        // timeout windows; it must not require a complete frame to stay alive.
        for chunk in encoded[..24].chunks(2) {
            peer.write_all(chunk).await.unwrap();
            tokio::time::sleep(TIMEOUT * 2).await;
            now += Duration::from_secs(2);
            health.tick_at(&connections, now, IDLE, TIMEOUT);
            assert!(
                !client.is_closed(),
                "continuous partial ADB header must keep the connection alive"
            );
        }
        peer.write_all(&encoded[24..]).await.unwrap();
        let mut received = [0; 5];
        stream.read_exact(&mut received).await.unwrap();
        assert_eq!(&received, b"video");
        assert_eq!(receive(&mut peer).await.command, protocol::OKAY);
        assert!(
            tokio::time::timeout(TIMEOUT, receive(&mut peer))
                .await
                .is_err()
        );
        client.close();
    }
}
