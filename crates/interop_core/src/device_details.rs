//! Bounded, read-only target facts. Replies belong to one live connection.
use crate::{
    CoreError, CoreResult, Runtime,
    model::{now, required},
};
use interop_adb::{Client, OperationOptions};
use serde_json::{Value, json};
use std::{collections::BTreeSet, net::IpAddr, time::Duration};

async fn read(client: &Client, command: &str) -> CoreResult<String> {
    let output = client
        .shell(
            command,
            256 * 1024,
            OperationOptions {
                timeout: Duration::from_secs(5),
                ..Default::default()
            },
        )
        .await?;
    if output.exit_code.is_some_and(|code| code != 0) {
        return Err(CoreError::new(
            "query_unavailable",
            "目标设备未能提供此项数据。",
        ));
    }
    String::from_utf8(output.stdout)
        .map_err(|_| CoreError::new("invalid_data", "设备数据格式无法识别。"))
}

pub(crate) fn network_addresses(text: &str) -> Vec<Value> {
    let mut seen = BTreeSet::new();
    text.lines()
        .filter_map(|line| {
            let fields = line.split_whitespace().collect::<Vec<_>>();
            let index = fields
                .iter()
                .position(|part| *part == "inet" || *part == "inet6")?;
            let interface = fields.get(1)?.split('@').next()?.trim_end_matches(':');
            let raw = fields.get(index + 1)?.split('/').next()?;
            let ip = raw.parse::<IpAddr>().ok()?;
            if ip.is_loopback() || ip.is_unspecified() || ip.is_multicast() {
                return None;
            }
            let address = match ip {
                IpAddr::V6(ip) if ip.is_unicast_link_local() => format!("{ip}%{interface}"),
                _ => ip.to_string(),
            };
            if !seen.insert((interface.to_owned(), address.clone())) {
                return None;
            }
            Some(json!({"address":address,"interface":interface}))
        })
        .collect()
}

fn boolean(text: &str, keys: &[&str]) -> Option<bool> {
    for line in text.lines() {
        for key in keys {
            if let Some((_, rest)) = line.split_once(key) {
                let word = rest
                    .trim_start()
                    .split(|ch: char| ch.is_whitespace() || ch == ',' || ch == '}')
                    .next()?;
                if word == "true" {
                    return Some(true);
                }
                if word == "false" {
                    return Some(false);
                }
            }
        }
    }
    None
}

pub(crate) fn screen_state(text: &str) -> (Option<bool>, Option<bool>) {
    let on = if text.contains("mWakefulness=Asleep") || text.contains("mWakefulness=Dozing") {
        Some(false)
    } else if text.contains("mWakefulness=Awake") || text.contains("mWakefulness=Dreaming") {
        Some(true)
    } else {
        boolean(text, &["mInteractive=", "mScreenOnFully="])
    };
    let locked = boolean(
        text,
        &[
            "mKeyguardShowing=",
            "mShowingLockscreen=",
            "isStatusBarKeyguard=",
        ],
    )
    .or_else(|| {
        let mut in_keyguard = false;
        for line in text.lines() {
            if line.contains("KeyguardServiceDelegate") || line.contains("KeyguardService:") {
                in_keyguard = true;
                continue;
            }
            if in_keyguard && line.trim_start().starts_with("showing=") {
                return boolean(line, &["showing="]);
            }
        }
        None
    });
    (on, locked)
}

pub(crate) fn battery_data(text: &str) -> Value {
    let num = |key: &str| -> Option<f64> {
        text.lines()
            .find_map(|line| line.trim().strip_prefix(key)?.trim().parse().ok())
    };
    let level = num("level:")
        .zip(num("scale:"))
        .filter(|(level, scale)| {
            level.is_finite()
                && scale.is_finite()
                && *scale > 0.0
                && *level >= 0.0
                && *level <= *scale
        })
        .map(|(level, scale)| (level * 100.0 / scale).clamp(0.0, 100.0).round() as u32);
    let status = num("status:").map(|n| n as u32);
    // Power attachment alone is not proof of charging (for example a charge
    // limit can leave USB attached while status is NOT_CHARGING).
    let charging = match status {
        Some(2) => Some(true),
        Some(3..=5) => Some(false),
        _ => None,
    };
    json!({"level":level,"charging":charging,"status":status,"health":num("health:").map(|n|n as u32),
        "temperatureC":num("temperature:").map(|n|n / 10.0),"voltageMv":num("voltage:")})
}

fn number_after(text: &str, prefix: &str) -> Option<u64> {
    text.lines().find_map(|line| {
        line.trim()
            .strip_prefix(prefix)?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    })
}

fn dimensions(text: &str) -> Option<(u32, u32)> {
    let line = text
        .lines()
        .rev()
        .find(|line| line.starts_with("Override size:") || line.starts_with("Physical size:"))?;
    let (w, h) = line.split_once(':')?.1.trim().split_once('x')?;
    Some((w.parse().ok()?, h.parse().ok()?))
}

fn refresh_rate(text: &str) -> Option<f64> {
    // Read the active default display, never the first virtual display or a
    // supported-mode maximum that may not be in use.
    for line in text.lines().rev().filter(|line| {
        line.contains("DisplayInfo{")
            && (line.contains("displayId 0,") || line.contains("displayId=0,"))
    }) {
        for prefix in ["renderFrameRate ", "refreshRate ", "refreshRate="] {
            if let Some((_, rest)) = line.split_once(prefix)
                && let Some(rate) = rest
                    .split(|ch: char| ch.is_whitespace() || ch == ',' || ch == '}')
                    .next()
                    .and_then(|value| value.parse::<f64>().ok())
                    .filter(|value| value.is_finite() && *value > 0.0)
            {
                return Some(rate);
            }
        }
    }
    None
}

fn foreground_package(text: &str) -> Option<String> {
    let mut packages = BTreeSet::new();
    let mut display = None;
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("Display #") {
            display = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.trim_end_matches(':').parse::<u32>().ok());
        }
        if display.is_some_and(|id| id != 0) {
            continue;
        }
        if !line.contains("mResumedActivity") && !line.contains("topResumedActivity") {
            continue;
        }
        for token in line.split_whitespace() {
            if let Some((package, _)) = token.split_once('/') {
                let package = package
                    .rsplit('=')
                    .next()
                    .unwrap_or(package)
                    .trim_start_matches('{');
                if package.contains('.')
                    && package
                        .chars()
                        .all(|ch| ch.is_ascii_alphanumeric() || ch == '.' || ch == '_')
                {
                    packages.insert(package.to_owned());
                }
            }
        }
    }
    (packages.len() == 1)
        .then(|| packages.into_iter().next())
        .flatten()
}

impl Runtime {
    async fn fact_client(&self, params: &Value) -> CoreResult<(String, Client)> {
        let id = required(params, "deviceId")?.to_owned();
        let client = self.client(&id).await?;
        if params["connectionId"]
            .as_str()
            .is_some_and(|expected| expected != client.connection_id().to_string())
        {
            return Err(CoreError::new(
                "stale_connection",
                "连接已替换，请重新读取设备状态。",
            ));
        }
        Ok((id, client))
    }

    async fn validate_fact_client(&self, id: &str, client: &Client) -> CoreResult<()> {
        if !self.client(id).await?.same_connection(client) || client.is_closed() {
            return Err(CoreError::new(
                "stale_connection",
                "连接已替换，已丢弃旧设备数据。",
            ));
        }
        Ok(())
    }

    pub(crate) async fn device_network(&self, params: &Value) -> CoreResult<Value> {
        let (id, client) = self.fact_client(params).await?;
        let text = read(&client, "ip -o addr show")
            .await
            .map_err(|_| CoreError::new("network_unavailable", "无法读取目标设备网络接口。"))?;
        self.validate_fact_client(&id, &client).await?;
        Ok(
            json!({"deviceId":id,"connectionId":client.connection_id().to_string(),"observedAt":now(),"addresses":network_addresses(&text)}),
        )
    }

    pub(crate) async fn device_screen_state(&self, params: &Value) -> CoreResult<Value> {
        let (id, client) = self.fact_client(params).await?;
        let text = read(&client, "dumpsys power; dumpsys window policy").await?;
        let (on, locked) = screen_state(&text);
        self.validate_fact_client(&id, &client).await?;
        Ok(
            json!({"deviceId":id,"connectionId":client.connection_id().to_string(),"screenOn":on,"locked":locked,"observedAt":now()}),
        )
    }

    pub(crate) async fn device_foreground(&self, params: &Value) -> CoreResult<Value> {
        let (id, client) = self.fact_client(params).await?;
        let text = read(&client, "dumpsys activity activities").await?;
        let package = foreground_package(&text).ok_or_else(|| {
            CoreError::new("foreground_unavailable", "无法确定当前手机画面中的应用。")
        })?;
        self.validate_fact_client(&id, &client).await?;
        Ok(
            json!({"deviceId":id,"connectionId":client.connection_id().to_string(),"packageName":package,"source":"resumedActivity"}),
        )
    }

    pub(crate) async fn device_data(&self, params: &Value) -> CoreResult<Value> {
        let id = required(params, "deviceId")?;
        let device = self.device(id).await?;
        if device.status != "connected" {
            return Ok(
                json!({"deviceId":id,"stale":true,"observedAt":device.last_seen,
                "system":{"model":device.model,"androidVersion":device.android_version,"apiLevel":device.api_level}}),
            );
        }
        let (_, client) = self.fact_client(params).await?;
        let mut failures = serde_json::Map::new();
        let mut query = |key: &'static str, result: CoreResult<String>| -> String {
            match result {
                Ok(text) => text,
                Err(error) => {
                    failures.insert(
                        key.into(),
                        json!({"code":error.code,"message":error.message}),
                    );
                    String::new()
                }
            }
        };
        let properties = query("system", read(&client, "getprop").await);
        let battery = query("battery", read(&client, "dumpsys battery").await);
        let display = query(
            "display",
            read(&client, "wm size; wm density; dumpsys display").await,
        );
        let power = query(
            "power",
            read(&client, "dumpsys power; dumpsys window policy").await,
        );
        let network = query("network", read(&client, "ip -o addr show").await);
        let memory = query(
            "memory",
            read(
                &client,
                "cat /proc/meminfo; cat /sys/devices/system/cpu/present",
            )
            .await,
        );
        let storage = query("storage", read(&client, "df -k /data").await);
        self.validate_fact_client(id, &client).await?;
        let prop = |key: &str| -> Option<String> {
            properties.lines().find_map(|line| {
                let (name, value) = line.strip_prefix('[')?.split_once("]: [")?;
                (name == key)
                    .then(|| value.trim_end_matches(']').to_owned())
                    .filter(|s| !s.is_empty())
            })
        };
        let size = dimensions(&display);
        let density = display.lines().rev().find_map(|line| {
            line.strip_prefix("Override density:")
                .or_else(|| line.strip_prefix("Physical density:"))?
                .trim()
                .parse::<u32>()
                .ok()
        });
        let refresh = refresh_rate(&display);
        let (screen_on, locked) = screen_state(&power);
        let storage_numbers = storage.lines().rev().find_map(|line| {
            let parts = line.split_whitespace().collect::<Vec<_>>();
            if parts.len() < 6 || !line.contains("/data") {
                return None;
            }
            Some((
                parts[1].parse::<u64>().ok()?.checked_mul(1024)?,
                parts[3].parse::<u64>().ok()?.checked_mul(1024)?,
            ))
        });
        let cores = memory.lines().find_map(|line| {
            line.trim()
                .strip_prefix("0-")?
                .parse::<u32>()
                .ok()
                .map(|n| n + 1)
        });
        Ok(
            json!({"deviceId":id,"connectionId":client.connection_id().to_string(),"observedAt":now(),"stale":false,"failures":failures,
            "system":{"model":prop("ro.product.model"),"brand":prop("ro.product.brand"),"product":prop("ro.product.name"),"hardware":prop("ro.hardware"),"androidVersion":prop("ro.build.version.release"),"apiLevel":prop("ro.build.version.sdk"),"securityPatch":prop("ro.build.version.security_patch"),"abi":prop("ro.product.cpu.abilist").or_else(||prop("ro.product.cpu.abi")),"build":prop("ro.build.display.id"),"serial":prop("ro.serialno")},
            "battery":battery_data(&battery),"display":{"width":size.map(|s|s.0),"height":size.map(|s|s.1),"densityDpi":density,"refreshRate":refresh,"screenOn":screen_on,"locked":locked},
            "network":{"addresses":network_addresses(&network),"transport":device.transport,"address":device.address,"port":device.port},
            "memory":{"totalBytes":number_after(&memory,"MemTotal:").and_then(|n|n.checked_mul(1024)),"availableBytes":number_after(&memory,"MemAvailable:").and_then(|n|n.checked_mul(1024))},
            "storage":{"totalBytes":storage_numbers.map(|n|n.0),"availableBytes":storage_numbers.map(|n|n.1)},"processor":{"cores":cores}}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn refresh_rate_uses_the_active_default_display_not_supported_modes() {
        assert_eq!(
            refresh_rate(
                "mBaseDisplayInfo=DisplayInfo{Built-in, displayId 0, renderFrameRate 60.000004, supportedModes [{fps=120}]}\nmBaseDisplayInfo=DisplayInfo{Virtual, displayId 3, renderFrameRate 90.0,}"
            ),
            Some(60.000004)
        );
        assert_eq!(
            refresh_rate("DisplayInfo{Built-in, displayId=0, refreshRate=59.94,}"),
            Some(59.94)
        );
        assert_eq!(refresh_rate("mSupportedModes=[fps=120]"), None);
    }
    #[test]
    fn interface_addresses_are_target_owned_scoped_and_deduplicated() {
        let entries = network_addresses(
            "1: lo inet 127.0.0.1/8 scope host lo\n2: wlan0 inet 192.168.1.8/24 scope global wlan0\n2: wlan0 inet6 fe80::1/64 scope link\n3: tun0 inet 10.0.0.2/24 scope global\n2: wlan0 inet 192.168.1.8/24 scope global",
        );
        assert_eq!(
            entries,
            vec![
                json!({"address":"192.168.1.8","interface":"wlan0"}),
                json!({"address":"fe80::1%wlan0","interface":"wlan0"}),
                json!({"address":"10.0.0.2","interface":"tun0"})
            ]
        );
    }
    #[test]
    fn unknown_power_and_keyguard_are_not_reported_as_locked() {
        assert_eq!(screen_state("unknown OEM dump\nshowing=true"), (None, None));
        assert_eq!(
            screen_state("mWakefulness=Awake\nKeyguardServiceDelegate\n showing=false"),
            (Some(true), Some(false))
        );
        assert_eq!(
            screen_state("mWakefulness=Asleep\nmKeyguardShowing=true"),
            (Some(false), Some(true))
        );
    }
    #[test]
    fn battery_distinguishes_unknown_from_discharging_and_reports_real_scale() {
        assert_eq!(battery_data("")["charging"], Value::Null);
        let value = battery_data(
            "level: 39\nscale: 50\nUSB powered: true\nstatus: 2\ntemperature: 321\nvoltage: 4120",
        );
        assert_eq!(value["level"], 78);
        assert_eq!(value["charging"], true);
        assert_eq!(value["temperatureC"], 32.1);
        assert_eq!(battery_data("level: -1\nscale: 100")["level"], Value::Null);
        assert_eq!(battery_data("level: 101\nscale: 100")["level"], Value::Null);
        assert_eq!(
            battery_data("USB powered: true\nstatus: 1")["charging"],
            Value::Null
        );
        assert_eq!(
            battery_data("USB powered: true\nstatus: 5")["charging"],
            false
        );
        assert_eq!(
            battery_data("level: 80\nscale: 100\nUSB powered: true\nstatus: 4")["charging"],
            false,
            "connected power cannot override an explicit NOT_CHARGING status"
        );
    }
    #[test]
    fn foreground_is_not_guessed_from_multiple_displays_or_ambiguous_tasks() {
        assert_eq!(
            foreground_package(
                "Display #0:\n mResumedActivity: ActivityRecord{a u0 com.example.app/.Main t42}\nDisplay #2:\n mResumedActivity: ActivityRecord{b u0 com.other.app/.Main t43}"
            ),
            Some("com.example.app".into())
        );
        assert_eq!(
            foreground_package(
                "mResumedActivity: com.one.app/.A\ntopResumedActivity=com.two.app/.B"
            ),
            None
        );
    }
}
