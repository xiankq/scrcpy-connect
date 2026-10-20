//! Execution settings supplied by the host application, separate from resource ownership.
use crate::{CoreError, CoreResult};
use interop_adb::{KeepaliveOptions, TcpOptions};
use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConnectionPolicy {
    pub request_authorization: bool,
    pub public_key_comment: String,
    pub connect_timeout_ms: u64,
    pub discovery_timeout_ms: u64,
    pub pairing_timeout_ms: u64,
    pub qr_pairing_timeout_ms: u64,
    pub endpoint_timeout_ms: u64,
    pub tcpip_restart_timeout_ms: u64,
    pub tcpip_attempt_timeout_ms: u64,
    pub tcp: TcpPolicy,
    pub health_enabled: bool,
    pub health_idle_ms: u64,
    pub health_probe_timeout_ms: u64,
    pub health_failure_limit: u32,
    pub monitor_interval_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TcpPolicy {
    pub nodelay: bool,
    pub keepalive: Option<KeepalivePolicy>,
    pub user_timeout_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct KeepalivePolicy {
    pub idle_ms: u64,
    pub interval_ms: u64,
    pub retries: u32,
}

impl TcpPolicy {
    pub(crate) fn options(&self) -> TcpOptions {
        TcpOptions {
            nodelay: self.nodelay,
            keepalive: self.keepalive.as_ref().map(|v| KeepaliveOptions {
                idle: Duration::from_millis(v.idle_ms),
                interval: Duration::from_millis(v.interval_ms),
                retries: v.retries,
            }),
            user_timeout: self.user_timeout_ms.map(Duration::from_millis),
        }
    }
}

impl ConnectionPolicy {
    /// Compatibility configuration for independent Rust hosts. Flutter supplies
    /// its complete configuration explicitly through initialize_with_connection_policy.
    pub fn standalone() -> Self {
        Self {
            request_authorization: true,
            public_key_comment: "interop-controller".into(),
            connect_timeout_ms: 60_000,
            discovery_timeout_ms: 3_000,
            pairing_timeout_ms: 60_000,
            qr_pairing_timeout_ms: 120_000,
            endpoint_timeout_ms: 5_000,
            tcpip_restart_timeout_ms: 10_000,
            tcpip_attempt_timeout_ms: 4_000,
            tcp: TcpPolicy {
                nodelay: true,
                keepalive: Some(KeepalivePolicy {
                    idle_ms: 1_000,
                    interval_ms: 1_000,
                    retries: 10,
                }),
                user_timeout_ms: Some(11_000),
            },
            health_enabled: true,
            health_idle_ms: 10_000,
            health_probe_timeout_ms: 3_000,
            health_failure_limit: 2,
            monitor_interval_ms: 2_000,
        }
    }

    pub fn validate(&self) -> CoreResult<()> {
        let durations = [
            self.connect_timeout_ms,
            self.discovery_timeout_ms,
            self.pairing_timeout_ms,
            self.qr_pairing_timeout_ms,
            self.endpoint_timeout_ms,
            self.tcpip_restart_timeout_ms,
            self.tcpip_attempt_timeout_ms,
            self.health_idle_ms,
            self.health_probe_timeout_ms,
            self.monitor_interval_ms,
        ];
        if durations.into_iter().any(|v| v == 0 || v > 86_400_000)
            || self.health_failure_limit == 0
            || self.health_failure_limit > 1_000
            || self.public_key_comment.len() > 1024
            || self.public_key_comment.contains('\0')
            || self
                .tcp
                .user_timeout_ms
                .is_some_and(|v| v == 0 || v > 86_400_000)
            || self.tcp.keepalive.as_ref().is_some_and(|v| {
                v.idle_ms < 1_000
                    || v.interval_ms < 1_000
                    || v.idle_ms > 86_400_000
                    || v.interval_ms > 86_400_000
                    || v.retries == 0
                    || v.retries > 1_000
            })
        {
            return Err(CoreError::new(
                "invalid_connection_policy",
                "连接策略包含无效的时限或 TCP 配置。",
            ));
        }
        Ok(())
    }
}
