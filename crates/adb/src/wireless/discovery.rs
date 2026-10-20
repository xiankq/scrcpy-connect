//! DNS-SD discovery. Platform code must obtain local-network/multicast permission.
//! Manual socket connections do not depend on discovery being available.
use crate::{Error, OperationOptions, Result};
use mdns_sd::{Receiver, ResolvedService, ScopedIp, ServiceDaemon, ServiceEvent};
use std::{
    collections::BTreeMap,
    net::{SocketAddr, SocketAddrV6},
    time::Duration,
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
    pub fn restart(&mut self) -> Result<()> {
        let fresh = Self::new()?;
        *self = fresh;
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
    pub fn verify(&self, fullname: &str, timeout: Duration) -> Result<()> {
        self.daemon
            .verify(fullname.to_owned(), timeout)
            .map_err(mdns_error)
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
