//! DNS-SD discovery. Platform code must obtain local-network/multicast permission.
//! Manual socket connections do not depend on discovery being available.
use crate::{Client, ConnectOptions, Error, OperationOptions, Result};
use mdns_sd::{Receiver, ResolvedService, ScopedIp, ServiceDaemon, ServiceEvent};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    net::{SocketAddr, SocketAddrV6},
    time::{Duration, Instant},
};

pub const LEGACY_SERVICE: &str = "_adb._tcp.local.";
pub const PAIRING_SERVICE: &str = "_adb-tls-pairing._tcp.local.";
pub const CONNECT_SERVICE: &str = "_adb-tls-connect._tcp.local.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceKind {
    Legacy,
    Pairing,
    Connect,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Service {
    pub kind: ServiceKind,
    pub instance: String,
    pub fullname: String,
    /// Includes `.local.` metadata used by current ADB host implementations.
    pub hostname: String,
    /// IPv6 link-local endpoints retain the interface's scope identifier.
    pub endpoints: Vec<SocketAddr>,
    pub properties: BTreeMap<String, String>,
}
#[derive(Debug, Clone)]
pub enum DiscoveryEvent {
    Resolved(Service),
    Removed { fullname: String },
}

pub enum ReconnectEvent {
    Connected { service: Service, client: Client },
    AttemptFailed { service: Service, error: Error },
}

pub struct Discovery {
    daemon: ServiceDaemon,
    legacy: Receiver<ServiceEvent>,
    pairing: Receiver<ServiceEvent>,
    connect: Receiver<ServiceEvent>,
}
impl Discovery {
    pub fn new() -> Result<Self> {
        let daemon = ServiceDaemon::new().map_err(mdns_error)?;
        let result = (|| {
            Ok(Self {
                legacy: daemon.browse(LEGACY_SERVICE).map_err(mdns_error)?,
                pairing: daemon.browse(PAIRING_SERVICE).map_err(mdns_error)?,
                connect: daemon.browse(CONNECT_SERVICE).map_err(mdns_error)?,
                daemon: daemon.clone(),
            })
        })();
        if result.is_err() {
            let _ = daemon.shutdown();
        }
        result
    }
    /// Recreate multicast sockets and resolver state after a platform network change.
    /// Existing transports must be closed by the connection owner.
    pub fn network_changed(&mut self, tracker: &mut ReconnectTracker) -> Result<()> {
        let fresh = Self::new()?;
        *self = fresh;
        tracker.network_changed();
        Ok(())
    }
    /// Long-lived browsing re-resolves changed IPs/ports and emits goodbye/expiry removals.
    pub async fn next(&self, options: &OperationOptions) -> Result<DiscoveryEvent> {
        crate::error::bounded(options.timeout, &options.cancellation, async {
            loop {
                let (kind, event) = tokio::select! {
                    event = self.legacy.recv_async() => (ServiceKind::Legacy, event),
                    event = self.pairing.recv_async() => (ServiceKind::Pairing, event),
                    event = self.connect.recv_async() => (ServiceKind::Connect, event),
                };
                match event.map_err(|_| Error::Closed)? {
                    ServiceEvent::ServiceResolved(info) => {
                        return Ok(DiscoveryEvent::Resolved(from_resolved(kind, &info)));
                    }
                    ServiceEvent::ServiceRemoved(_, fullname) => {
                        return Ok(DiscoveryEvent::Removed { fullname });
                    }
                    _ => {}
                }
            }
        })
        .await
    }
    /// Ask the resolver to evict stale records after a failed connection.
    pub fn verify(&self, fullname: &str) -> Result<()> {
        self.daemon
            .verify(fullname.to_owned(), Duration::from_secs(3))
            .map_err(mdns_error)
    }
    /// Resolve and reconnect a known device using the current endpoint records.
    /// Repeated calls also retry failures with bounded exponential backoff. Call
    /// `tracker.failed` when a returned client disconnects, or `network_changed`
    /// when platform networking changes. A successful result has completed CNXN.
    pub async fn reconnect_next(
        &self,
        tracker: &mut ReconnectTracker,
        options: &ConnectOptions,
    ) -> Result<ReconnectEvent> {
        if options.tls.is_none() {
            return Err(Error::InvalidArgument(
                "wireless reconnect requires explicit TLS configuration",
            ));
        }
        crate::error::bounded(
            options.operations.timeout,
            &options.operations.cancellation,
            async {
                loop {
                    // Drain queued discoveries before selecting cached endpoints.
                    for (kind, receiver) in [
                        (ServiceKind::Legacy, &self.legacy),
                        (ServiceKind::Pairing, &self.pairing),
                        (ServiceKind::Connect, &self.connect),
                    ] {
                        while let Ok(event) = receiver.try_recv() {
                            match event {
                                ServiceEvent::ServiceResolved(info) => tracker
                                    .observe(DiscoveryEvent::Resolved(from_resolved(kind, &info))),
                                ServiceEvent::ServiceRemoved(_, fullname) => {
                                    tracker.observe(DiscoveryEvent::Removed { fullname })
                                }
                                _ => {}
                            }
                        }
                    }
                    let service = tracker
                        .due(Instant::now())
                        .first()
                        .map(|service| (*service).clone());
                    if let Some(service) = service {
                        // Reserve the attempt before awaiting network I/O. Dropping the
                        // future on cancellation/timeout must not bypass retry backoff.
                        tracker.failed(&service.fullname, Instant::now());
                        let mut last_error = Error::Closed;
                        for address in &service.endpoints {
                            match Client::connect_tcp(*address, options.clone()).await {
                                Ok(client) => {
                                    tracker.connected(&service.fullname);
                                    return Ok(ReconnectEvent::Connected { service, client });
                                }
                                Err(error @ (Error::Cancelled | Error::Timeout)) => {
                                    return Err(error);
                                }
                                Err(error) => last_error = error,
                            }
                        }
                        let _ = self.verify(&service.fullname);
                        return Ok(ReconnectEvent::AttemptFailed {
                            service,
                            error: last_error,
                        });
                    }
                    tokio::select! {
                        result = self.next(&options.operations) => tracker.observe(result?),
                        _ = tokio::time::sleep(Duration::from_millis(250)) => {},
                    }
                }
            },
        )
        .await
    }
}
impl Drop for Discovery {
    fn drop(&mut self) {
        for service in [LEGACY_SERVICE, PAIRING_SERVICE, CONNECT_SERVICE] {
            let _ = self.daemon.stop_browse(service);
        }
        let _ = self.daemon.shutdown();
    }
}
fn mdns_error(error: mdns_sd::Error) -> Error {
    Error::Protocol(format!("mDNS: {error}"))
}
fn from_resolved(kind: ServiceKind, info: &ResolvedService) -> Service {
    let suffix = match kind {
        ServiceKind::Legacy => LEGACY_SERVICE,
        ServiceKind::Pairing => PAIRING_SERVICE,
        ServiceKind::Connect => CONNECT_SERVICE,
    };
    let instance = info
        .get_fullname()
        .strip_suffix(suffix)
        .unwrap_or(info.get_fullname())
        .trim_end_matches('.')
        .to_owned();
    let mut endpoints = info
        .get_addresses()
        .iter()
        .filter_map(|address| match address {
            ScopedIp::V4(ip) => Some(SocketAddr::new((*ip.addr()).into(), info.get_port())),
            ScopedIp::V6(ip) => Some(SocketAddr::V6(SocketAddrV6::new(
                *ip.addr(),
                info.get_port(),
                0,
                ip.scope_id().index,
            ))),
            _ => None,
        })
        .collect::<Vec<_>>();
    endpoints.sort();
    let properties = info
        .get_properties()
        .iter()
        .map(|p| (p.key().to_owned(), p.val_str().to_owned()))
        .collect();
    Service {
        kind,
        instance,
        fullname: info.get_fullname().into(),
        hostname: info.get_hostname().into(),
        endpoints,
        properties,
    }
}

/// Reconnect selection keeps authorization, discovery and connection separate.
/// The caller persists paired GUIDs, invokes `connected` after CNXN, and retries
/// `due` endpoints after `failed`. Every new DNS answer replaces stale endpoints.
#[derive(Default)]
pub struct ReconnectTracker {
    trusted: HashSet<String>,
    discovered: HashMap<String, Service>,
    attempts: HashMap<String, (u32, Instant)>,
    online: HashSet<String>,
}
impl ReconnectTracker {
    pub fn trust(&mut self, guid: impl Into<String>) {
        self.trusted.insert(guid.into());
    }
    pub fn revoke(&mut self, guid: &str) {
        self.trusted.remove(guid);
        for service in self
            .discovered
            .values()
            .filter(|service| known_instance(&service.instance, guid))
        {
            self.online.remove(&service.fullname);
            self.attempts.remove(&service.fullname);
        }
    }
    pub fn observe(&mut self, event: DiscoveryEvent) {
        match event {
            DiscoveryEvent::Resolved(service) if service.kind == ServiceKind::Connect => {
                let changed = self.discovered.get(&service.fullname) != Some(&service);
                if changed {
                    self.attempts.remove(&service.fullname);
                    self.online.remove(&service.fullname);
                }
                self.discovered.insert(service.fullname.clone(), service);
            }
            DiscoveryEvent::Removed { fullname } => {
                self.discovered.remove(&fullname);
                self.online.remove(&fullname);
                self.attempts.remove(&fullname);
            }
            _ => {}
        }
    }
    /// Network changes invalidate live connections. DNS browsing supplies fresh endpoints.
    pub fn network_changed(&mut self) {
        self.discovered.clear();
        self.online.clear();
        self.attempts.clear();
    }
    pub fn connected(&mut self, fullname: &str) {
        self.online.insert(fullname.into());
        self.attempts.remove(fullname);
    }
    pub fn failed(&mut self, fullname: &str, now: Instant) {
        self.online.remove(fullname);
        let count = self
            .attempts
            .get(fullname)
            .map_or(1, |(n, _)| n.saturating_add(1));
        let delay = Duration::from_secs(1u64 << count.min(6));
        self.attempts.insert(fullname.into(), (count, now + delay));
    }
    pub fn due(&self, now: Instant) -> Vec<&Service> {
        self.discovered
            .values()
            .filter(|service| {
                self.trusted
                    .iter()
                    .any(|guid| known_instance(&service.instance, guid))
                    && !self.online.contains(&service.fullname)
                    && self
                        .attempts
                        .get(&service.fullname)
                        .is_none_or(|(_, when)| now >= *when)
            })
            .collect()
    }
}
// AOSP's 2026 host tolerates mDNS conflict suffixes on an otherwise known GUID.
fn known_instance(instance: &str, guid: &str) -> bool {
    if guid.is_empty() {
        return false;
    }
    if instance == guid {
        return true;
    }
    instance
        .strip_prefix(guid)
        .and_then(|tail| tail.strip_prefix(" ("))
        .and_then(|tail| tail.strip_suffix(')'))
        .is_some_and(|digits| !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_trusted_connect_services_reconnect_and_changed_ports_reset_backoff() {
        let now = Instant::now();
        let service = Service {
            kind: ServiceKind::Connect,
            instance: "adb-guid (2)".into(),
            fullname: "test".into(),
            hostname: "device.local.".into(),
            endpoints: vec!["127.0.0.1:1234".parse().unwrap()],
            properties: BTreeMap::new(),
        };
        let mut tracker = ReconnectTracker::default();
        tracker.observe(DiscoveryEvent::Resolved(service.clone()));
        assert!(tracker.due(now).is_empty());
        tracker.trust("adb-guid");
        assert_eq!(tracker.due(now).len(), 1);
        tracker.failed("test", now);
        assert!(tracker.due(now).is_empty());
        let mut changed = service;
        changed.endpoints[0] = "127.0.0.1:4321".parse().unwrap();
        tracker.observe(DiscoveryEvent::Resolved(changed));
        assert_eq!(tracker.due(now).len(), 1);
        tracker.connected("test");
        assert!(tracker.due(now).is_empty());
        tracker.observe(DiscoveryEvent::Removed {
            fullname: "test".into(),
        });
        assert!(tracker.due(now).is_empty());
        assert!(!known_instance("adb-guid-attacker", "adb-guid"));
    }
}
