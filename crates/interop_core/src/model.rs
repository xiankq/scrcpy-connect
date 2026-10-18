use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};

pub type CoreResult<T> = Result<T, CoreError>;

#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub struct CoreError {
    pub code: String,
    pub message: String,
    pub details: Value,
}
impl CoreError {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            details: Value::Null,
        }
    }
    pub fn pending(feature: &str) -> Self {
        Self::new(
            "implementation_pending",
            format!("{feature}尚未提供，请稍后再试。"),
        )
    }
}
impl From<interop_adb::Error> for CoreError {
    fn from(e: interop_adb::Error) -> Self {
        let code = match &e {
            interop_adb::Error::AuthorizationRequired => "authorization_required",
            interop_adb::Error::Cancelled => "cancelled",
            interop_adb::Error::Timeout => "timeout",
            interop_adb::Error::Closed => "disconnected",
            _ => "device_error",
        };
        Self::new(code, e.to_string())
    }
}
impl From<std::io::Error> for CoreError {
    fn from(e: std::io::Error) -> Self {
        Self::new("io_error", e.to_string())
    }
}
impl From<serde_json::Error> for CoreError {
    fn from(e: serde_json::Error) -> Self {
        Self::new("invalid_data", e.to_string())
    }
}

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum TransportKind {
    Tcp,
    Wireless,
    Tls,
    Usb,
}

impl TransportKind {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "tcp" => Some(Self::Tcp),
            "wireless" => Some(Self::Wireless),
            "tls" => Some(Self::Tls),
            "usb" => Some(Self::Usb),
            _ => None,
        }
    }

    pub(crate) fn is_usb(&self) -> bool {
        matches!(self, Self::Usb)
    }

    pub(crate) fn requires_tls(&self, paired_guid: Option<&str>) -> bool {
        !self.is_usb() && (matches!(self, Self::Tls) || paired_guid.is_some())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub id: String,
    pub name: String,
    pub address: String,
    pub port: u16,
    #[serde(default)]
    pub guid: Option<String>,
    #[serde(default)]
    pub serial: Option<String>,
    pub transport: TransportKind,
    pub status: String,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub android_version: Option<String>,
    #[serde(default)]
    pub api_level: Option<u32>,
    #[serde(default)]
    pub battery: Option<u32>,
    #[serde(default)]
    pub last_seen: Option<u64>,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub auto_reconnect: bool,
    #[serde(default = "observation_default")]
    pub observation_wanted: bool,
}

fn observation_default() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Store {
    pub version: u32,
    pub identity_fingerprint: String,
    pub devices: Vec<Device>,
    pub settings: Value,
}

pub fn required<'a>(p: &'a Value, key: &str) -> CoreResult<&'a str> {
    p.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty() && !s.contains('\0'))
        .ok_or_else(|| CoreError::new("invalid_argument", format!("缺少或无效的字段：{key}")))
}

pub fn remote_path(value: &str) -> CoreResult<String> {
    if !value.starts_with('/') || value.contains('\0') || value.len() > 1000 {
        return Err(CoreError::new("invalid_path", "请选择有效的手机绝对路径。"));
    }
    let mut parts = Vec::new();
    for part in value.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            p => parts.push(p),
        }
    }
    Ok(format!("/{}", parts.join("/")))
}

pub fn quote(value: &str) -> CoreResult<String> {
    if value.contains('\0') {
        return Err(CoreError::new("invalid_argument", "内容不能包含空字符。"));
    }
    Ok(format!("'{}'", value.replace('\'', "'\"'\"'")))
}

pub fn mime(path: &str) -> &'static str {
    match path
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "webp" => "image/webp",
        "gif" => "image/gif",
        "heic" | "heif" => "image/heic",
        "mp4" | "m4v" => "video/mp4",
        "mkv" => "video/x-matroska",
        "webm" => "video/webm",
        "mov" => "video/quicktime",
        "pdf" => "application/pdf",
        "txt" | "md" => "text/plain",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    }
}
