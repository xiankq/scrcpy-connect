//! Device-side reverse listeners plus an allowlisted host TCP bridge. This is
//! the adbd `reverse:` protocol, not adb server's host:forward protocol.
use crate::{Client, Error, OperationOptions, Result, error::bounded};
use rand::RngCore;
use std::{collections::HashMap, net::SocketAddr, sync::Mutex, time::Duration};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReverseSocket {
    /// Zero requests an ephemeral device port; the returned binding has its actual port.
    Tcp(u16),
    LocalAbstract(String),
    LocalFilesystem(String),
}
impl ReverseSocket {
    fn service(&self) -> Result<String> {
        match self {
            Self::Tcp(port) => Ok(format!("tcp:{port}")),
            Self::LocalAbstract(name) | Self::LocalFilesystem(name) => {
                if name.is_empty()
                    || name.len() > 107
                    || name
                        .bytes()
                        .any(|byte| byte == 0 || byte == b';' || byte.is_ascii_whitespace())
                {
                    return Err(Error::InvalidArgument(
                        "reverse socket name is empty, too long, or contains a protocol delimiter",
                    ));
                }
                Ok(format!(
                    "{}:{name}",
                    if matches!(self, Self::LocalAbstract(_)) {
                        "localabstract"
                    } else {
                        "localfilesystem"
                    }
                ))
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReverseBinding {
    pub device: ReverseSocket,
    pub destination: SocketAddr,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReverseMapping {
    pub serial: String,
    pub device_service: String,
    pub host_service: String,
}

#[derive(Clone, Copy)]
pub(crate) struct Destination {
    pub address: SocketAddr,
    pub connect_timeout: Duration,
}
#[derive(Default)]
struct RegistryState {
    destinations: HashMap<String, Destination>,
    bindings: HashMap<String, String>,
}
#[derive(Default)]
pub(crate) struct Registry(Mutex<RegistryState>, tokio::sync::Mutex<()>);
impl Registry {
    pub fn destination(&self, service: &[u8]) -> Option<Destination> {
        let service = std::str::from_utf8(service).ok()?;
        self.0
            .lock()
            .expect("reverse registry mutex")
            .destinations
            .get(service)
            .copied()
    }
    fn remove(&self, device: &str) {
        let mut state = self.0.lock().expect("reverse registry mutex");
        if let Some(service) = state.bindings.remove(device) {
            state.destinations.remove(&service);
        }
    }
}

struct Registration {
    client: Client,
    token: String,
    committed: bool,
}
impl Drop for Registration {
    fn drop(&mut self) {
        if self.committed {
            return;
        }
        self.client
            .reverse_registry()
            .0
            .lock()
            .expect("reverse registry mutex")
            .destinations
            .remove(&self.token);
        // OPEN may have installed an ephemeral listener before timeout/cancellation.
        // Remove only listeners carrying this exact, random operation token.
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            let client = self.client.clone();
            let token = self.token.clone();
            runtime.spawn(async move {
                let _transaction = client.reverse_registry().1.lock().await;
                let options = OperationOptions {
                    timeout: Duration::from_secs(3),
                    ..Default::default()
                };
                if let Ok(entries) = client.reverse_list(options.clone()).await {
                    for entry in entries
                        .into_iter()
                        .filter(|entry| entry.host_service == token)
                    {
                        let _ = client
                            .reverse_request(
                                &format!("killforward:{}", entry.device_service),
                                options.clone(),
                            )
                            .await;
                    }
                }
            });
        }
    }
}

fn hex_length(bytes: &[u8]) -> Result<usize> {
    if bytes.len() != 4 || !bytes.iter().all(u8::is_ascii_hexdigit) {
        return Err(Error::Protocol("invalid reverse protocol length".into()));
    }
    usize::from_str_radix(std::str::from_utf8(bytes).expect("ASCII"), 16)
        .map_err(|_| Error::Protocol("invalid reverse protocol length".into()))
}
fn protocol_string(bytes: &[u8]) -> Result<&[u8]> {
    if bytes.len() < 4 {
        return Err(Error::Protocol("truncated reverse protocol string".into()));
    }
    let length = hex_length(&bytes[..4])?;
    if length != bytes.len() - 4 {
        return Err(Error::Protocol(
            "reverse protocol string length mismatch".into(),
        ));
    }
    Ok(&bytes[4..])
}
fn status(bytes: &[u8]) -> Result<&[u8]> {
    match bytes.get(..4) {
        Some(b"OKAY") => Ok(&bytes[4..]),
        Some(b"FAIL") => Err(Error::Remote(
            String::from_utf8_lossy(protocol_string(&bytes[4..])?).into_owned(),
        )),
        _ => Err(Error::Protocol("invalid reverse service status".into())),
    }
}

impl Client {
    async fn reverse_request(&self, command: &str, options: OperationOptions) -> Result<Vec<u8>> {
        bounded(options.timeout, &options.cancellation, async {
            let mut stream = self
                .open(&format!("reverse:{command}"), options.clone())
                .await?;
            let mut bytes = Vec::new();
            let mut buffer = [0; 4096];
            loop {
                let count = stream.read(&mut buffer).await?;
                if count == 0 {
                    break;
                }
                if bytes.len() + count > 65543 {
                    return Err(Error::OutputLimit);
                }
                bytes.extend_from_slice(&buffer[..count]);
            }
            Ok(bytes)
        })
        .await
    }

    /// Register a device listener and bridge its connections to this explicitly
    /// authorized host TCP address. The listener persists until removal or
    /// transport disconnect; dropping the returned metadata does not remove it.
    /// Only opaque endpoints installed here accept device-initiated OPENs.
    pub async fn reverse_forward(
        &self,
        device: &ReverseSocket,
        destination: SocketAddr,
        no_rebind: bool,
        options: OperationOptions,
    ) -> Result<ReverseBinding> {
        if destination.port() == 0 {
            return Err(Error::InvalidArgument(
                "reverse destination requires a nonzero port",
            ));
        }
        let device_service = device.service()?;
        // Serialize mutations so concurrent rebind/remove completions cannot
        // overwrite the local allowlist in a different order from adbd.
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let mut random = [0; 16];
        rand::rngs::OsRng.fill_bytes(&mut random);
        let token = format!(
            "localabstract:interop-reverse-{}",
            random
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>()
        );
        let mut guard = Registration {
            client: self.clone(),
            token: token.clone(),
            committed: false,
        };
        {
            let mut state = self
                .reverse_registry()
                .0
                .lock()
                .expect("reverse registry mutex");
            if state.destinations.len() >= 128 {
                return Err(Error::InvalidArgument("maximum reverse listeners reached"));
            }
            state.destinations.insert(
                token.clone(),
                Destination {
                    address: destination,
                    connect_timeout: options.timeout,
                },
            );
        }
        let bytes = self
            .reverse_request(
                &format!(
                    "forward:{}{device_service};{token}",
                    if no_rebind { "norebind:" } else { "" }
                ),
                options,
            )
            .await?;
        let extra = status(&bytes)?;
        let actual = if !extra.is_empty() {
            let port = std::str::from_utf8(protocol_string(extra)?)
                .ok()
                .and_then(|port| port.parse::<u16>().ok())
                .filter(|port| *port != 0)
                .ok_or_else(|| Error::Protocol("invalid resolved reverse TCP port".into()))?;
            if !matches!(device, ReverseSocket::Tcp(_)) {
                return Err(Error::Protocol(
                    "unexpected reverse TCP port for Unix listener".into(),
                ));
            }
            ReverseSocket::Tcp(port)
        } else {
            if matches!(device, ReverseSocket::Tcp(0)) {
                return Err(Error::Protocol(
                    "adbd did not return the allocated reverse port".into(),
                ));
            }
            device.clone()
        };
        let mut state = self
            .reverse_registry()
            .0
            .lock()
            .expect("reverse registry mutex");
        if let Some(previous) = state.bindings.insert(actual.service()?, token) {
            state.destinations.remove(&previous);
        }
        guard.committed = true;
        Ok(ReverseBinding {
            device: actual,
            destination,
        })
    }

    /// Device listener table, which adbd may share across connected hosts.
    pub async fn reverse_list(&self, options: OperationOptions) -> Result<Vec<ReverseMapping>> {
        let bytes = self.reverse_request("list-forward", options).await?;
        if bytes.starts_with(b"FAIL") {
            status(&bytes)?;
        }
        let text = std::str::from_utf8(protocol_string(&bytes)?)
            .map_err(|_| Error::Protocol("reverse listener table is not UTF-8".into()))?;
        let mut result = Vec::new();
        for line in text.lines() {
            let fields = line.split_ascii_whitespace().collect::<Vec<_>>();
            if fields.len() != 3 || result.len() >= 1024 {
                return Err(Error::Protocol(
                    "invalid or oversized reverse listener table".into(),
                ));
            }
            result.push(ReverseMapping {
                serial: fields[0].to_owned(),
                device_service: fields[1].to_owned(),
                host_service: fields[2].to_owned(),
            });
        }
        Ok(result)
    }

    pub async fn reverse_remove(
        &self,
        device: &ReverseSocket,
        options: OperationOptions,
    ) -> Result<()> {
        let service = device.service()?;
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let bytes = self
            .reverse_request(&format!("killforward:{service}"), options)
            .await?;
        if !status(&bytes)?.is_empty() {
            return Err(Error::Protocol(
                "unexpected reverse removal response".into(),
            ));
        }
        self.reverse_registry().remove(&service);
        Ok(())
    }

    /// Removes adbd's complete reverse listener table, including listeners from
    /// other hosts. Prefer `reverse_remove` for a single owned binding.
    pub async fn reverse_remove_all(&self, options: OperationOptions) -> Result<()> {
        let _transaction = bounded(options.timeout, &options.cancellation, async {
            Ok(self.reverse_registry().1.lock().await)
        })
        .await?;
        let bytes = self.reverse_request("killforward-all", options).await?;
        if !status(&bytes)?.is_empty() {
            return Err(Error::Protocol(
                "unexpected reverse removal response".into(),
            ));
        }
        *self
            .reverse_registry()
            .0
            .lock()
            .expect("reverse registry mutex") = RegistryState::default();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reverse_commands_reject_delimiters_and_status_lengths_are_exact() {
        for name in ["", "bad;tcp:1", "a b", "x\0y"] {
            assert!(ReverseSocket::LocalAbstract(name.into()).service().is_err());
        }
        assert_eq!(status(b"OKAY").unwrap(), b"");
        assert!(matches!(status(b"FAIL0004busy"),Err(Error::Remote(message))if message=="busy"));
        for bytes in [b"0004abc".as_slice(), b"gggg", b"0000extra"] {
            assert!(protocol_string(bytes).is_err());
        }
    }
}
