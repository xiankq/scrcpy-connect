//! Desktop authentication uses official adb, with one isolated process per
//! selected RSA identity. No custom identity silently inherits the global key.
use crate::{
    CoreError, CoreResult, Runtime, connection_policy::AdbServerPolicy, host_identity::Material,
};
use interop_adb::{OperationOptions, server};
use std::{collections::HashMap, net::SocketAddr, path::Path, sync::Arc, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    process::{Child, Command},
    sync::Mutex,
};

#[derive(Default)]
pub(crate) struct ServerPool {
    children: Mutex<HashMap<String, (SocketAddr, Child)>>,
    usb_owners: Mutex<HashMap<String, SocketAddr>>,
}
impl ServerPool {
    pub async fn endpoint(
        &self,
        policy: &AdbServerPolicy,
        material: &Arc<Material>,
        options: &OperationOptions,
    ) -> CoreResult<SocketAddr> {
        self.endpoint_scoped(policy, material, None, options).await
    }
    pub async fn usb_endpoint(
        &self,
        policy: &AdbServerPolicy,
        material: &Arc<Material>,
        serial: &str,
        options: &OperationOptions,
    ) -> CoreResult<SocketAddr> {
        self.endpoint_scoped(policy, material, Some(serial), options)
            .await
    }
    async fn endpoint_scoped(
        &self,
        policy: &AdbServerPolicy,
        material: &Arc<Material>,
        usb_serial: Option<&str>,
        options: &OperationOptions,
    ) -> CoreResult<SocketAddr> {
        let global = Path::new(&policy.key_directory).join("global/adbkey");
        let pem = tokio::fs::read_to_string(global).await?;
        let global = interop_adb::Identity::from_pem(&pem)?;
        if crate::host_identity::fingerprint(&global)? == material.fingerprint {
            return Ok(SocketAddr::from(([127, 0, 0, 1], policy.port)));
        }
        let pool_key = match usb_serial {
            Some(serial) => format!("{}:usb:{serial}", material.fingerprint),
            None => material.fingerprint.clone(),
        };
        let mut children = self.children.lock().await;
        if let Some((address, child)) = children.get_mut(&pool_key)
            && child.try_wait()?.is_none()
        {
            return Ok(*address);
        }
        children.remove(&pool_key);
        if children.len() >= 32 {
            return Err(CoreError::new("resource_busy", "专用ADB授权服务已达上限。"));
        }
        let home = Path::new(&policy.key_directory).join(&material.fingerprint);
        tokio::fs::create_dir_all(&home).await?;
        let key = home.join("adbkey");
        Runtime::private_write(&key, material.identity.to_pkcs8_pem()?.as_bytes()).await?;
        let public = home.join("adbkey.pub");
        let mut public_key = material.identity.public_key("interop")?;
        public_key.pop();
        public_key.push(b'\n');
        Runtime::private_write(&public, &public_key).await?;
        let reservation = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
        let address = reservation.local_addr()?;
        drop(reservation);
        let mut child = Command::new(&policy.executable_path)
            .args([
                "--one-device",
                usb_serial.unwrap_or("interop-no-usb-selected"),
                "-L",
                &format!("tcp:{}", address.port()),
                "server",
                "nodaemon",
            ])
            .env("ANDROID_USER_HOME", &home)
            .env("ADB_VENDOR_KEYS", &key)
            .env("ADB_MDNS_AUTO_CONNECT", "0")
            .env("ADB_LIBUSB", "1")
            .env("ADB_LOCAL_TRANSPORT_MAX_PORT", "0")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn()?;
        let ready = async {
            loop {
                if child.try_wait()?.is_some() {
                    return Err(CoreError::new(
                        "adb_server_failed",
                        "专用官方ADB服务启动失败。",
                    ));
                }
                if server::query(
                    address,
                    "host:version",
                    &OperationOptions {
                        timeout: Duration::from_millis(300),
                        cancellation: options.cancellation.clone(),
                    },
                )
                .await
                .is_ok()
                {
                    return Ok(());
                }
                tokio::time::sleep(Duration::from_millis(30)).await;
            }
        };
        tokio::select! {
            _=options.cancellation.cancelled()=>return Err(CoreError::new("cancelled","ADB服务准备已取消。")),
            result=tokio::time::timeout(options.timeout,ready)=>result.map_err(|_|CoreError::new("timeout","ADB服务准备超时。"))??,
        }
        children.insert(pool_key, (address, child));
        Ok(address)
    }
    pub async fn stop_all(&self) {
        let children = std::mem::take(&mut *self.children.lock().await);
        for (_, (_, mut child)) in children {
            let _ = child.kill().await;
            let _ = child.wait().await;
        }
        self.usb_owners.lock().await.clear();
    }

    pub async fn usb_devices(
        &self,
        policy: &AdbServerPolicy,
        options: &OperationOptions,
    ) -> CoreResult<Vec<server::ServerDevice>> {
        let global = SocketAddr::from(([127, 0, 0, 1], policy.port));
        let addresses = std::iter::once(global)
            .chain(
                self.children
                    .lock()
                    .await
                    .values()
                    .map(|(address, _)| *address)
                    .collect::<Vec<_>>(),
            )
            .collect::<Vec<_>>();
        let mut queries = tokio::task::JoinSet::new();
        for address in addresses {
            let options = options.clone();
            queries.spawn(async move { server::devices(address, &options).await });
        }
        let mut devices = std::collections::BTreeMap::new();
        while let Some(result) = queries.join_next().await {
            if let Ok(Ok(entries)) = result {
                for device in entries
                    .into_iter()
                    .filter(|d| d.description.contains("usb:"))
                {
                    devices.entry(device.serial.clone()).or_insert(device);
                }
            }
        }
        Ok(devices.into_values().collect())
    }

    /// Transfer only a USB device already owned by one of this app's servers.
    /// Other programs' adb servers and their USB handles are never touched.
    pub async fn attach_usb(
        &self,
        policy: &AdbServerPolicy,
        selected: SocketAddr,
        serial: &str,
        options: &OperationOptions,
    ) -> CoreResult<()> {
        let mut owners = self.usb_owners.lock().await;
        let global = SocketAddr::from(([127, 0, 0, 1], policy.port));
        if owners.get(serial).copied() == Some(selected) {
            return Ok(());
        }
        let selected_devices = server::devices(selected, options).await?;
        if selected_devices
            .iter()
            .any(|d| d.serial == serial && d.description.contains("usb:") && d.state != "detached")
        {
            owners.insert(serial.into(), selected);
            return Ok(());
        }
        let previous = owners.get(serial).copied().unwrap_or(global);
        if previous != selected {
            let old = server::devices(previous, options).await?;
            if !old
                .iter()
                .any(|d| d.serial == serial && d.description.contains("usb:"))
            {
                return Err(CoreError::new(
                    "usb_unavailable",
                    "目标USB不由当前应用的官方ADB服务持有。",
                ));
            }
            official_usb_command(policy, previous, serial, "detach", options).await?;
        }
        if let Err(error) = official_usb_command(policy, selected, serial, "attach", options).await
        {
            if previous != selected {
                let _ = official_usb_command(policy, previous, serial, "attach", options).await;
            }
            return Err(error);
        }
        owners.insert(serial.into(), selected);
        Ok(())
    }
}

async fn official_usb_command(
    policy: &AdbServerPolicy,
    address: SocketAddr,
    serial: &str,
    command: &str,
    options: &OperationOptions,
) -> CoreResult<()> {
    let mut child = Command::new(&policy.executable_path)
        .args([
            "-H",
            "127.0.0.1",
            "-P",
            &address.port().to_string(),
            "-s",
            serial,
            command,
        ])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()?;
    tokio::select! {
        _=options.cancellation.cancelled()=>Err(CoreError::new("cancelled","USB后端交接已取消。")),
        result=tokio::time::timeout(options.timeout,child.wait())=>{
            if result.map_err(|_|CoreError::new("timeout","USB后端交接超时。"))??.success(){Ok(())}
            else {Err(CoreError::new("usb_handoff_failed","官方ADB无法完成USB授权身份交接；请确认平台USB后端支持attach/detach。"))}
        }
    }
}

impl Runtime {
    pub(crate) async fn official_pair(
        &self,
        address: &str,
        password: &str,
        material: &Arc<Material>,
        options: &OperationOptions,
    ) -> CoreResult<interop_adb::wireless::PairingResult> {
        let policy = self
            .connection_policy
            .adb_server
            .as_ref()
            .ok_or_else(|| CoreError::new("invalid_backend", "未配置官方ADB。"))?;
        let server = self
            .official_adb
            .endpoint(policy, material, options)
            .await?;
        let mut command = Command::new(&policy.executable_path);
        command.args([
            "-H",
            "127.0.0.1",
            "-P",
            &server.port().to_string(),
            "pair",
            address,
        ]);
        let mut child = command
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn()?;
        let mut input = child.stdin.take().expect("piped stdin");
        input.write_all(password.as_bytes()).await?;
        input.write_all(b"\n").await?;
        drop(input);
        let mut output = child.stdout.take().expect("piped stdout").take(65537);
        let mut bytes = Vec::new();
        let work = async {
            output.read_to_end(&mut bytes).await?;
            let result = child.wait().await?;
            if !result.success() || bytes.len() > 65536 {
                return Err(CoreError::new("pairing_failed", "官方ADB未完成配对。"));
            }
            Ok::<_, CoreError>(())
        };
        tokio::select! {
            _=options.cancellation.cancelled()=>return Err(CoreError::new("cancelled","配对已取消。")),
            result=tokio::time::timeout(options.timeout,work)=>result.map_err(|_|CoreError::new("timeout","配对执行超时。"))??,
        }
        let text = std::str::from_utf8(&bytes)
            .map_err(|_| CoreError::new("pairing_failed", "官方ADB返回无效配对结果。"))?;
        let guid = text
            .split("[guid=")
            .nth(1)
            .and_then(|s| s.split(']').next())
            .filter(|s| !s.is_empty() && s.len() <= 256)
            .ok_or_else(|| CoreError::new("pairing_failed", "官方ADB未返回已配对设备身份。"))?;
        Ok(interop_adb::wireless::PairingResult {
            guid: guid.to_owned(),
        })
    }
}
