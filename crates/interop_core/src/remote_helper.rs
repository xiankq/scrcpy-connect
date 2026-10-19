//! Atomic Android path operations. Each call deploys its own immutable embedded
//! helper into a new 0700 directory; no remote executable cache is trusted.
use crate::{CoreError, CoreResult};
use base64::Engine;
use interop_adb::{Client, OperationOptions, sync::RemotePath};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fmt::Write, time::Duration};

const MANIFEST: &str = include_str!("../../../servers/helpers/manifest.json");
const ARM64: &[u8] = include_bytes!("../../../servers/helpers/bin/arm64-v8a/interop-rename");
const ARM: &[u8] = include_bytes!("../../../servers/helpers/bin/armeabi-v7a/interop-rename");
const X64: &[u8] = include_bytes!("../../../servers/helpers/bin/x86_64/interop-rename");
const X86: &[u8] = include_bytes!("../../../servers/helpers/bin/x86/interop-rename");

struct Deployment {
    lease: interop_adb::AdbStream,
    directory: String,
}
impl Deployment {
    async fn create(
        client: &Client,
        directory: String,
        options: OperationOptions,
    ) -> CoreResult<Self> {
        // The creator owns cleanup before announcing success. Keeping its raw
        // stdin open leases the directory; EOF also releases it if the caller
        // is dropped while awaiting the creation receipt. Only successful
        // mkdir installs cleanup, so a collision never authorizes deletion.
        // Wait for host input before mkdir: cancelling OPEN cannot create an
        // orphan before the host has obtained the stream that owns its lease.
        let script = format!(
            "IFS= read -r create || exit; [ \"$create\" = create ] || exit; umask 077; if mkdir {directory}; then trap 'rm -f -- {directory}/rename; rmdir {directory}' EXIT; trap 'exit' HUP INT TERM PIPE; print -r -- '__INTEROP_DEPLOYED__'; IFS= read -r release; else print -r -- '__INTEROP_COLLISION__'; fi"
        );
        let mut lease = client.exec(&script, options).await?;
        lease.write_all(b"create\n").await?;
        let mut receipt = Vec::new();
        while receipt.len() < 64 {
            let mut byte = [0];
            if lease.read(&mut byte).await? == 0 {
                break;
            }
            receipt.push(byte[0]);
            if byte[0] == b'\n' {
                break;
            }
        }
        if receipt != b"__INTEROP_DEPLOYED__\n" && receipt != b"__INTEROP_DEPLOYED__\r\n" {
            return Err(CoreError::new(
                "helper_deployment",
                "无法创建独占文件服务目录。",
            ));
        }
        Ok(Self { lease, directory })
    }

    async fn cleanup(mut self) {
        // On normal completion wait briefly for remote cleanup. On any error
        // or cancellation, dropping this same stream delivers EOF instead.
        let _ = tokio::time::timeout(Duration::from_secs(2), async {
            self.lease.write_all(b"\n").await?;
            let mut byte = [0];
            self.lease.read(&mut byte).await
        })
        .await;
    }
}

fn artifact(abis: &str) -> CoreResult<(&'static [u8], String)> {
    let manifest: Value = serde_json::from_str(MANIFEST)?;
    for abi in abis.split(|c: char| c == ',' || c.is_ascii_whitespace()) {
        let bytes = match abi {
            "arm64-v8a" => ARM64,
            "armeabi-v7a" => ARM,
            "x86_64" => X64,
            "x86" => X86,
            _ => continue,
        };
        let hash = manifest["artifacts"]
            .as_array()
            .and_then(|entries| entries.iter().find(|entry| entry["abi"] == abi))
            .and_then(|entry| entry["sha256"].as_str())
            .ok_or_else(|| CoreError::new("helper_integrity", "内置文件服务清单无效。"))?;
        if format!("{:x}", Sha256::digest(bytes)) != hash {
            return Err(CoreError::new("helper_integrity", "内置文件服务校验失败。"));
        }
        return Ok((bytes, hash.to_owned()));
    }
    Err(CoreError::new(
        "unsupported_abi",
        "设备处理器尚无文件服务程序。",
    ))
}

fn path_assignment(name: &str, path: &[u8]) -> CoreResult<String> {
    if path.is_empty() || path.len() > 4095 || path.contains(&0) {
        return Err(CoreError::new(
            "invalid_path",
            "远端路径为空、过长或含有空字节。",
        ));
    }
    let mut octal = String::with_capacity(path.len() * 5);
    for byte in path {
        write!(&mut octal, "\\0{byte:03o}").expect("String writing");
    }
    // Command substitution strips trailing newlines; a sentinel preserves every
    // path byte, including newline suffixes and non-UTF8 names.
    Ok(format!(
        "{name}=$(print -n -- '{octal}.')\n{name}=${{{name}%.}}\n"
    ))
}

pub(crate) async fn remote_rename(
    client: &Client,
    source: &str,
    target: &str,
    replace: bool,
) -> CoreResult<Value> {
    let mut result = Box::pin(remote_rename_bytes(
        client,
        source.as_bytes(),
        target.as_bytes(),
        replace,
    ))
    .await?;
    result["path"] = json!(target);
    Ok(result)
}

struct LaunchChallenge {
    authorization: String,
    marker: String,
}

impl LaunchChallenge {
    fn new() -> Self {
        Self {
            authorization: uuid::Uuid::new_v4().simple().to_string(),
            marker: format!("__INTEROP_VERIFIED_{}__", uuid::Uuid::new_v4().simple()),
        }
    }
}

async fn run_script(
    client: &Client,
    script: &str,
    expected_artifact: &[u8],
    challenge: &LaunchChallenge,
    response_limit: usize,
    options: OperationOptions,
) -> CoreResult<Vec<u8>> {
    // The legacy service may use a PTY. Complete echo suppression before any
    // private path bytes arrive; fail closed if a PTY cannot be made raw.
    const BOOTSTRAP: &str = "if [ -t 0 ]; then stty raw -echo 2>/dev/null || exit 71; fi; print -r -- '__INTEROP_READY__'; IFS= read -r count; script=$(dd bs=1 count=\"$count\" 2>/dev/null); eval \"$script\"";
    let mut stream = client.exec(BOOTSTRAP, options).await?;
    let mut ready = Vec::new();
    loop {
        let mut byte = [0];
        stream.read_exact(&mut byte).await?;
        ready.push(byte[0]);
        if byte[0] == b'\n' || ready.len() > 64 {
            break;
        }
    }
    if ready != b"__INTEROP_READY__\r\n" && ready != b"__INTEROP_READY__\n" {
        return Err(CoreError::new(
            "helper_unavailable",
            "设备无法建立无回显的文件服务通道。",
        ));
    }
    // Length framing avoids canonical line limits and any interactive shell.
    stream
        .write_all(format!("{}\n", script.len()).as_bytes())
        .await?;
    stream.write_all(script.as_bytes()).await?;
    // The shell returns the bytes of its already-open executable descriptor.
    // Compare incrementally so even a corrupt oversized artifact is bounded.
    let mut artifact_buffer = [0; 4096];
    for expected in expected_artifact.chunks(artifact_buffer.len()) {
        let received = &mut artifact_buffer[..expected.len()];
        stream.read_exact(received).await?;
        if received != expected {
            return Err(CoreError::new(
                "helper_integrity",
                "设备文件服务校验失败，未授权执行。",
            ));
        }
    }
    let marker = format!("{}\n", challenge.marker);
    let mut verified = vec![0; marker.len()];
    stream.read_exact(&mut verified).await?;
    if verified != marker.as_bytes() {
        return Err(CoreError::new(
            "helper_integrity",
            "设备文件服务长度校验失败，未授权执行。",
        ));
    }
    // No authorization bytes enter the remote shell until all artifact bytes
    // and its end marker agree. A failed or cancelled read drops this stream.
    stream
        .write_all(format!("{}\n", challenge.authorization).as_bytes())
        .await?;
    let mut output = Vec::new();
    let mut buffer = [0; 256];
    loop {
        let count = stream.read(&mut buffer).await?;
        if count == 0 {
            break;
        }
        if output.len() + count > response_limit {
            return Err(CoreError::new("helper_protocol", "文件服务响应过长。"));
        }
        output.extend_from_slice(&buffer[..count]);
    }
    Ok(output)
}

fn helper_script(
    source_arg: &str,
    target_arg: &str,
    path: &str,
    operation: &str,
    challenge: &LaunchChallenge,
) -> String {
    // fd3 retains the raw host input before fd0 pins the opened executable.
    // cat, read and exec all use those descriptors, never a reopened pathname.
    // The unpredictable end marker prevents appended artifact bytes from
    // impersonating the end of the read-back transcript.
    let LaunchChallenge {
        authorization,
        marker,
    } = challenge;
    format!(
        r#"{source_arg}{target_arg}exec 3<&0
exec 0<{path} || {{ print -nr -- '{{"protocol":1,"bootstrap":"open"}}'; exit; }}
cat <&0 || exit
print -r -- '{marker}'
IFS= read -r authorization <&3 || exit
[ "$authorization" = '{authorization}' ] || exit
exec 3<&-
exec /proc/self/fd/0 {operation} "$source" "$target"
"#
    )
}

fn parse_result(output: &[u8], target: &[u8], replace: bool) -> CoreResult<Value> {
    let reply: Value = serde_json::from_slice(output).map_err(|_| {
        CoreError::new(
            "result_unknown",
            "未取得重命名回执，操作可能已完成；请刷新核对，不会自动重试。",
        )
    })?;
    if reply["protocol"] != 1 {
        return Err(CoreError::new(
            "result_unknown",
            "重命名回执无效，请刷新核对结果，不会自动重试。",
        ));
    }
    if let Some(stage) = reply["bootstrap"].as_str() {
        return Err(CoreError::new(
            if stage == "integrity" {
                "helper_integrity"
            } else {
                "helper_unavailable"
            },
            "设备文件服务的安全启动未完成。",
        ));
    }
    let errno = reply["errno"]
        .as_i64()
        .filter(|value| (0..4096).contains(value))
        .ok_or_else(|| {
            CoreError::new(
                "result_unknown",
                "未取得有效的重命名结果，请刷新核对，不会自动重试。",
            )
        })?;
    if reply["ok"] == true && errno == 0 {
        return Ok(
            json!({"status":"completed","atomic":true,"operation":if replace{"rename_replace"}else{"rename_noreplace"},"pathBytes":base64::engine::general_purpose::STANDARD.encode(target)}),
        );
    }
    if reply["ok"] != false || errno == 0 {
        return Err(CoreError::new(
            "result_unknown",
            "重命名回执不一致，请刷新核对，不会自动重试。",
        ));
    }
    let (code, message) = match errno {
        17 => ("conflict", "目标名称已存在，未覆盖。"),
        38 | 22 | 95 => (
            "atomic_rename_unavailable",
            "设备内核或文件系统不支持所需的原子重命名。",
        ),
        2 => ("not_found", "源路径或目标父目录不存在。"),
        13 | 1 => ("permission_denied", "设备系统拒绝重命名。"),
        18 => ("cross_device", "源与目标位于不同文件系统，无法原子重命名。"),
        28 => ("no_space", "设备空间不足。"),
        20 | 21 | 39 => (
            "invalid_destination",
            "目标路径的类型或目录内容不允许本次重命名。",
        ),
        _ => ("remote_error", "设备系统未完成重命名。"),
    };
    let mut error = CoreError::new(code, message);
    error.details = json!({"errno":errno,"atomic":true,"operation":if replace{"publish-replace"}else{"rename-no-replace"}});
    Err(error)
}

pub(crate) async fn remote_rename_bytes(
    client: &Client,
    source: &[u8],
    target: &[u8],
    replace: bool,
) -> CoreResult<Value> {
    let operation = if replace {
        "publish-replace"
    } else {
        "rename-no-replace"
    };
    execute_helper(
        client,
        source,
        target,
        operation,
        1024,
        OperationOptions::default(),
    )
    .await
    .and_then(|output| parse_result(&output, target, replace))
    .map_err(|error| {
        if matches!(
            error.code.as_str(),
            "disconnected" | "timeout" | "cancelled" | "device_error" | "helper_protocol"
        ) {
            CoreError::new(
                "result_unknown",
                "连接在执行重命名时中断；操作可能已完成，请刷新核对。这个操作不会再次删除源路径。",
            )
        } else {
            error
        }
    })
}

/// Metadata shares the exact same verified executable deployment as mutation.
/// The native helper receives only `operation`, `path`, `limit` as argv.
pub(crate) async fn remote_metadata(
    client: &Client,
    path: &str,
    operation: &str,
    limit: usize,
    options: OperationOptions,
) -> CoreResult<Value> {
    if !matches!(operation, "stat" | "lstat" | "list") || !(1..=10_000).contains(&limit) {
        return Err(CoreError::new(
            "invalid_params",
            "文件元数据操作或结果上限无效。",
        ));
    }
    let response_limit = if operation == "list" {
        8 * 1024 * 1024
    } else {
        4096
    };
    let output = Box::pin(execute_helper(
        client,
        path.as_bytes(),
        limit.to_string().as_bytes(),
        operation,
        response_limit,
        options,
    ))
    .await?;
    parse_metadata(&output)
}

fn parse_metadata(output: &[u8]) -> CoreResult<Value> {
    let reply: Value = serde_json::from_slice(output)
        .map_err(|_| CoreError::new("helper_protocol", "文件元数据回执无效。"))?;
    let errno = reply["errno"]
        .as_u64()
        .filter(|value| *value < 4096)
        .ok_or_else(|| CoreError::new("helper_protocol", "文件元数据回执缺少有效结果。"))?;
    if reply["protocol"] != 1
        || (reply["ok"] != true && reply["ok"] != false)
        || (reply["ok"] == true) != (errno == 0)
    {
        return Err(CoreError::new("helper_protocol", "文件元数据回执不一致。"));
    }
    if errno == 0 {
        return Ok(reply);
    }
    let (code, message) = match errno {
        1 | 13 => ("permission_denied", "设备系统拒绝读取文件元数据。"),
        2 => ("not_found", "设备文件路径不存在。"),
        20 => ("not_directory", "设备路径不是目录。"),
        36 => ("invalid_path", "设备文件路径过长。"),
        38 | 95 => ("unsupported", "设备不支持读取所需文件元数据。"),
        _ => ("remote_error", "设备系统未返回文件元数据。"),
    };
    let mut error = CoreError::new(code, message);
    error.details = json!({"errno":errno});
    Err(error)
}

async fn execute_helper(
    client: &Client,
    source: &[u8],
    target: &[u8],
    operation: &str,
    response_limit: usize,
    options: OperationOptions,
) -> CoreResult<Vec<u8>> {
    let cancellation = options.cancellation.clone();
    let timeout = options.timeout;
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(CoreError::new("cancelled", "文件服务操作已取消。")),
        result = tokio::time::timeout(timeout, Box::pin(execute_unbounded(client, source, target, operation, response_limit, options))) =>
            result.map_err(|_| CoreError::new("timeout", "设备文件服务操作超时。"))?,
    }
}

async fn execute_unbounded(
    client: &Client,
    source: &[u8],
    target: &[u8],
    operation: &str,
    response_limit: usize,
    options: OperationOptions,
) -> CoreResult<Vec<u8>> {
    let source_arg = path_assignment("source", source)?;
    let target_arg = path_assignment("target", target)?;
    let abis = client
        .shell(
            "getprop ro.product.cpu.abilist; getprop ro.product.cpu.abi",
            2048,
            options.clone(),
        )
        .await?;
    let (bytes, _hash) = artifact(&String::from_utf8_lossy(&abis.stdout))?;
    let directory = format!(
        "/data/local/tmp/interop-fs-{}",
        uuid::Uuid::new_v4().simple()
    );
    let deployment = Deployment::create(client, directory, options.clone()).await?;
    let result = Box::pin(async {
        let path = format!("{}/rename", deployment.directory);
        let mut sync = client.sync(options.clone()).await?;
        sync.push(
            &RemotePath::new(&path)?,
            &mut &bytes[..],
            0o700,
            0,
            bytes.len() as u64,
        )
        .await?;
        drop(sync);
        // The host authorizes only the exact embedded bytes returned from the
        // opened inode, which remains pinned for exec. No remote hash tool is
        // needed; the private directory excludes other Android app UIDs.
        let challenge = LaunchChallenge::new();
        let script = helper_script(&source_arg, &target_arg, &path, operation, &challenge);
        Box::pin(run_script(
            client,
            &script,
            bytes,
            &challenge,
            response_limit,
            options,
        ))
        .await
    })
    .await;
    deployment.cleanup().await;
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    // Exercise the real raw ADB bootstrap and generated shell script against a
    // local shell with only API21-era tools, without an Android device.
    #[cfg(unix)]
    async fn local_shell() -> (Client, tokio::task::JoinHandle<()>, tempfile::TempDir) {
        let (client, task, tools, _) = local_shell_with_output(false).await;
        (client, task, tools)
    }

    #[cfg(unix)]
    async fn local_shell_with_output(
        withhold_output: bool,
    ) -> (
        Client,
        tokio::task::JoinHandle<()>,
        tempfile::TempDir,
        tokio::sync::oneshot::Receiver<()>,
    ) {
        use interop_adb::{
            DeviceInfo,
            protocol::{self, Frame},
        };
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let tools = tempfile::tempdir().unwrap();
        for tool in ["cat", "dd", "mkdir", "rm", "rmdir"] {
            std::os::unix::fs::symlink(format!("/bin/{tool}"), tools.path().join(tool)).unwrap();
        }
        let (transport, mut peer) = tokio::io::duplex(8192);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: 0x0100_0000,
                max_payload: 4096,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        let path = tools.path().to_owned();
        let (output_started, output_received) = tokio::sync::oneshot::channel();
        let task = tokio::spawn(async move {
            let open = Frame::read(&mut peer, 4096, true).await.unwrap();
            assert_eq!(open.command, protocol::OPEN);
            let service = std::str::from_utf8(&open.payload)
                .unwrap()
                .trim_end_matches('\0');
            let command = service
                .strip_prefix("exec:")
                .expect("private paths require a raw service");
            // CI may supply real mksh. The fallback exposes only the three
            // observed Android print forms and deliberately rejects printf.
            let shell = std::env::var("INTEROP_TEST_MKSH").ok();
            let command = if shell.is_some() {
                command.to_owned()
            } else {
                format!(
                    r#"print() {{
    case "$1" in
        -r) shift; shift; /bin/printf '%s\n' "$*" ;;
        -nr) shift; shift; /bin/printf '%s' "$*" ;;
        -n) shift; shift; /bin/printf '%b' "$*" ;;
        *) return 127 ;;
    esac
}}
printf() {{ return 127; }}
{command}"#
                )
            };
            let mut child = tokio::process::Command::new(shell.as_deref().unwrap_or("/bin/sh"))
                .arg("-c")
                .arg(command)
                .env("PATH", path)
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::null())
                .kill_on_drop(true)
                .spawn()
                .unwrap();
            let mut input = child.stdin.take();
            let mut output = child.stdout.take().unwrap();
            let remote_id = 42;
            Frame::new(protocol::OKAY, remote_id, open.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            let mut outstanding = false;
            let mut finished = false;
            let mut buffer = [0; 1024];
            let mut output_started = Some(output_started);
            loop {
                tokio::select! {
                    frame = Frame::read(&mut peer, 4096, true) => {
                        let Ok(frame) = frame else { break };
                        match frame.command {
                            protocol::WRTE => {
                                if input.as_mut().unwrap().write_all(&frame.payload).await.is_err() { break; }
                                Frame::new(protocol::OKAY, remote_id, open.arg0, []).write(&mut peer).await.unwrap();
                            }
                            protocol::OKAY => outstanding = false,
                            protocol::CLSE => {
                                // adbd closes the raw exec socket when the host
                                // drops its stream, delivering EOF to stdin.
                                input.take();
                                outstanding = false;
                            },
                            _ => panic!("unexpected fixture frame"),
                        }
                    }
                    count = output.read(&mut buffer), if !outstanding && !finished => {
                        let count = count.unwrap();
                        if count == 0 {
                            Frame::new(protocol::CLSE, remote_id, open.arg0, []).write(&mut peer).await.unwrap();
                            finished = true;
                            continue;
                        }
                        if let Some(started) = output_started.take() {
                            let _ = started.send(());
                        }
                        if !withhold_output {
                            Frame::new(protocol::WRTE, remote_id, open.arg0, buffer[..count].to_vec()).write(&mut peer).await.unwrap();
                        }
                        outstanding = true;
                    }
                }
            }
            let _ = child.kill().await;
            let _ = child.wait().await;
        });
        (client, task, tools, output_received)
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn deployment_cleans_creation_when_receipt_is_lost() {
        for interruption in ["cancel", "timeout", "drop"] {
            let root = tempfile::tempdir().unwrap();
            let directory = root.path().join("deployment");
            let (client, peer, _tools, output) = local_shell_with_output(true).await;
            let options = OperationOptions {
                timeout: Duration::from_secs(1),
                ..Default::default()
            };
            let cancellation = options.cancellation.clone();
            let task_client = client.clone();
            let path = directory.to_str().unwrap().to_owned();
            let task =
                tokio::spawn(async move { Deployment::create(&task_client, path, options).await });
            tokio::time::timeout(Duration::from_secs(2), output)
                .await
                .unwrap()
                .unwrap();
            assert!(
                directory.is_dir(),
                "mkdir must precede the withheld receipt"
            );
            match interruption {
                "cancel" => {
                    cancellation.cancel();
                    assert_eq!(task.await.unwrap().err().unwrap().code, "cancelled");
                }
                "timeout" => assert_eq!(task.await.unwrap().err().unwrap().code, "timeout"),
                "drop" => {
                    task.abort();
                    assert!(task.await.err().unwrap().is_cancelled());
                }
                _ => unreachable!(),
            }
            let cleaned = tokio::time::timeout(Duration::from_secs(1), async {
                while directory.exists() {
                    tokio::task::yield_now().await;
                }
            })
            .await;
            client.close();
            peer.await.unwrap();
            assert!(
                cleaned.is_ok(),
                "{interruption} must clean a directory even before its creation receipt arrives"
            );
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn deployment_release_removes_only_its_exclusive_directory() {
        let root = tempfile::tempdir().unwrap();
        let directory = root.path().join("deployment");
        let (client, peer, _tools) = local_shell().await;
        let deployment = Deployment::create(
            &client,
            directory.to_str().unwrap().to_owned(),
            OperationOptions::default(),
        )
        .await
        .unwrap();
        assert!(
            directory.is_dir(),
            "the lease must keep the directory alive"
        );
        std::fs::write(directory.join("rename"), b"uploaded helper").unwrap();
        deployment.cleanup().await;
        assert!(!directory.exists(), "release must await remote cleanup");
        client.close();
        peer.await.unwrap();

        std::fs::create_dir(&directory).unwrap();
        std::fs::write(directory.join("rename"), b"pre-existing executable").unwrap();
        let (client, peer, _tools) = local_shell().await;
        let result = Deployment::create(
            &client,
            directory.to_str().unwrap().to_owned(),
            OperationOptions::default(),
        )
        .await;
        assert_eq!(result.err().unwrap().code, "helper_deployment");
        client.close();
        peer.await.unwrap();
        assert_eq!(
            std::fs::read(directory.join("rename")).unwrap(),
            b"pre-existing executable"
        );
    }

    #[cfg(unix)]
    const FIXTURE_HELPER: &[u8] = b"#!/bin/sh\nprintf '%s' \"$3\" > \"$2\"\nprintf '{\"protocol\":1,\"ok\":true,\"errno\":0}'\n";

    #[cfg(unix)]
    #[derive(Clone, Copy)]
    enum LaunchFixture {
        Normal,
        WrongAuthorization,
        ReplacePath,
        CancelVerification,
    }

    #[cfg(unix)]
    async fn fixture_execution(
        actual: &[u8],
        expected: &[u8],
        variant: LaunchFixture,
        response_limit: usize,
    ) -> (CoreResult<Vec<u8>>, Option<Vec<u8>>) {
        use std::os::unix::fs::PermissionsExt;
        let root = tempfile::tempdir().unwrap();
        let executable = root.path().join("rename");
        let receipt = root.path().join("receipt");
        std::fs::write(&executable, actual).unwrap();
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
        let source = path_assignment("source", receipt.as_os_str().as_encoded_bytes()).unwrap();
        let target = path_assignment("target", b"private-'$\n\xff").unwrap();
        let challenge = LaunchChallenge::new();
        let shell_challenge = LaunchChallenge {
            authorization: if matches!(variant, LaunchFixture::WrongAuthorization) {
                "wrong-token".to_owned()
            } else {
                challenge.authorization.clone()
            },
            marker: challenge.marker.clone(),
        };
        let script = helper_script(
            &source,
            &target,
            executable.to_str().unwrap(),
            "rename-no-replace",
            &shell_challenge,
        );
        let (client, task, tools) = local_shell().await;
        let verified = root.path().join("verified");
        let mut options = OperationOptions::default();
        let cancellation = options.cancellation.clone();
        let cancellation_task = if matches!(variant, LaunchFixture::CancelVerification) {
            let marker = verified.clone();
            Some(tokio::spawn(async move {
                while !marker.exists() {
                    tokio::task::yield_now().await;
                }
                cancellation.cancel();
            }))
        } else {
            None
        };
        let hook = match variant {
            LaunchFixture::ReplacePath => {
                let replacement = root.path().join("replacement");
                std::fs::write(&replacement, b"#!/bin/sh\nprintf replaced\n").unwrap();
                std::fs::set_permissions(&replacement, std::fs::Permissions::from_mode(0o700))
                    .unwrap();
                Some(format!(
                    "/bin/mv '{}' '{}'",
                    replacement.display(),
                    executable.display()
                ))
            }
            LaunchFixture::CancelVerification => Some(format!(
                ": > '{}'; IFS= read -r withheld <&3",
                verified.display()
            )),
            _ => None,
        };
        if let Some(hook) = hook {
            let cat = tools.path().join("cat");
            std::fs::remove_file(&cat).unwrap();
            std::fs::write(&cat, format!("#!/bin/sh\n/bin/cat\n{hook}\n")).unwrap();
            std::fs::set_permissions(cat, std::fs::Permissions::from_mode(0o700)).unwrap();
        }
        options.timeout = Duration::from_secs(2);
        let output = tokio::time::timeout(
            Duration::from_secs(3),
            run_script(
                &client,
                &script,
                expected,
                &challenge,
                response_limit,
                options,
            ),
        )
        .await
        .unwrap();
        client.close();
        task.await.unwrap();
        if let Some(task) = cancellation_task {
            task.await.unwrap();
        }
        (output, std::fs::read(receipt).ok())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn verified_helper_runs_without_remote_hash_utilities() {
        let (output, receipt) =
            fixture_execution(FIXTURE_HELPER, FIXTURE_HELPER, LaunchFixture::Normal, 1024).await;
        assert_eq!(output.unwrap(), br#"{"protocol":1,"ok":true,"errno":0}"#);
        assert_eq!(receipt.unwrap(), b"private-'$\n\xff");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn changed_or_oversized_artifacts_are_never_authorized() {
        let mut changed = FIXTURE_HELPER.to_vec();
        let last = changed.len() - 2;
        changed[last] = b' ';
        for actual in [
            changed,
            [FIXTURE_HELPER, b"extra"].concat(),
            [FIXTURE_HELPER, b"__INTEROP_VERIFIED__\n"].concat(),
        ] {
            let (output, receipt) =
                fixture_execution(&actual, FIXTURE_HELPER, LaunchFixture::Normal, 1024).await;
            assert_eq!(output.unwrap_err().code, "helper_integrity");
            assert!(
                receipt.is_none(),
                "verification failure cannot execute the helper"
            );
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn truncated_artifact_cannot_execute_helper() {
        let (output, receipt) = fixture_execution(
            &FIXTURE_HELPER[..FIXTURE_HELPER.len() / 2],
            FIXTURE_HELPER,
            LaunchFixture::Normal,
            1024,
        )
        .await;
        assert!(output.is_err());
        assert!(receipt.is_none());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn wrong_authorization_cannot_execute_the_verified_helper() {
        let (output, receipt) = fixture_execution(
            FIXTURE_HELPER,
            FIXTURE_HELPER,
            LaunchFixture::WrongAuthorization,
            1024,
        )
        .await;
        assert!(output.unwrap().is_empty());
        assert!(receipt.is_none());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn exec_uses_the_verified_inode_after_pathname_replacement() {
        let (output, receipt) = fixture_execution(
            FIXTURE_HELPER,
            FIXTURE_HELPER,
            LaunchFixture::ReplacePath,
            1024,
        )
        .await;
        assert_eq!(output.unwrap(), br#"{"protocol":1,"ok":true,"errno":0}"#);
        assert_eq!(receipt.unwrap(), b"private-'$\n\xff");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn cancellation_before_authorization_cannot_execute_helper() {
        let (output, receipt) = fixture_execution(
            FIXTURE_HELPER,
            FIXTURE_HELPER,
            LaunchFixture::CancelVerification,
            1024,
        )
        .await;
        assert_eq!(output.unwrap_err().code, "cancelled");
        assert!(receipt.is_none());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn verified_helper_response_remains_bounded() {
        let (output, _) =
            fixture_execution(FIXTURE_HELPER, FIXTURE_HELPER, LaunchFixture::Normal, 8).await;
        assert_eq!(output.unwrap_err().code, "helper_protocol");
    }

    #[tokio::test]
    async fn metadata_rejects_unsupported_operations_and_limits_before_device_access() {
        let (transport, _peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            interop_adb::DeviceInfo {
                version: interop_adb::protocol::VERSION,
                max_payload: 4096,
                banner: "device::".into(),
                features: Default::default(),
            },
        )
        .unwrap();
        for (operation, limit) in [("list;reboot", 1), ("list", 0), ("list", 10_001)] {
            assert_eq!(
                remote_metadata(
                    &client,
                    "/path",
                    operation,
                    limit,
                    OperationOptions::default()
                )
                .await
                .unwrap_err()
                .code,
                "invalid_params"
            );
        }
        client.close();
    }

    #[test]
    fn metadata_errno_and_envelopes_are_checked_before_use() {
        assert_eq!(parse_metadata(br#"{"protocol":1,"ok":true,"errno":0,"mode":33188,"size":5,"modifiedSeconds":123}"#).unwrap()["size"], 5);
        assert_eq!(
            parse_metadata(br#"{"protocol":1,"ok":false,"errno":13}"#)
                .unwrap_err()
                .code,
            "permission_denied"
        );
        for response in [
            b"".as_slice(),
            br#"{"protocol":1,"ok":true}"#,
            br#"{"protocol":1,"ok":true,"errno":13}"#,
            br#"{"protocol":2,"ok":true,"errno":0}"#,
        ] {
            assert_eq!(
                parse_metadata(response).unwrap_err().code,
                "helper_protocol"
            );
        }
    }

    #[test]
    fn embedded_artifacts_match_their_build_manifest() {
        for abi in ["arm64-v8a", "armeabi-v7a", "x86_64", "x86"] {
            assert!(artifact(abi).is_ok());
        }
        assert!(artifact("unknown").is_err());
        let manifest: Value = serde_json::from_str(MANIFEST).unwrap();
        let sources: [(&str, &[u8]); 4] = [
            (
                "crates/android_helper/src/main.rs",
                include_bytes!("../../android_helper/src/main.rs"),
            ),
            (
                "crates/android_helper/Cargo.toml",
                include_bytes!("../../android_helper/Cargo.toml"),
            ),
            (
                "crates/android_helper/Cargo.lock",
                include_bytes!("../../android_helper/Cargo.lock"),
            ),
            (
                "servers/helpers/build.py",
                include_bytes!("../../../servers/helpers/build.py"),
            ),
        ];
        for (path, bytes) in sources {
            assert_eq!(
                manifest["sources"][path],
                format!("{:x}", Sha256::digest(bytes)),
                "rebuild helper after editing {path}"
            );
        }
    }
    #[test]
    fn byte_paths_never_become_shell_syntax() {
        let value = path_assignment("source", b"/x/'$()\xff\n").unwrap();
        assert!(!value.contains("$()"));
        assert!(value.contains("\\0377\\0012"));
        assert!(path_assignment("source", b"x\0").is_err());
    }

    #[test]
    fn errno_is_typed_and_inconsistent_or_missing_results_fail_closed() {
        let conflict = parse_result(
            br#"{"protocol":1,"ok":false,"errno":17}"#,
            b"/target",
            false,
        )
        .unwrap_err();
        assert_eq!(conflict.code, "conflict");
        assert_eq!(conflict.details["errno"], 17);
        assert_eq!(
            parse_result(
                br#"{"protocol":1,"ok":false,"errno":38}"#,
                b"/target",
                false
            )
            .unwrap_err()
            .code,
            "atomic_rename_unavailable"
        );
        for response in [
            b"".as_slice(),
            br#"{"protocol":1,"ok":true"#,
            br#"{"protocol":1,"ok":true,"errno":17}"#,
            br#"{"protocol":1,"ok":false,"errno":0}"#,
            br#"{"protocol":1,"ok":true}"#,
            br#"{"protocol":1,"ok":false,"errno":-1}"#,
            br#"{"protocol":2,"ok":true,"errno":0}"#,
        ] {
            assert_eq!(
                parse_result(response, b"/target", false).unwrap_err().code,
                "result_unknown",
                "an absent or malformed receipt cannot prove that nothing happened"
            );
        }
    }
}
