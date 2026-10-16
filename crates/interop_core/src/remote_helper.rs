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
    client: Client,
    directory: String,
}
impl Deployment {
    async fn cleanup(&self) {
        let _ = self
            .client
            .shell(
                &format!(
                    "rm -f -- {}/rename; rmdir -- {}",
                    self.directory, self.directory
                ),
                1024,
                OperationOptions {
                    timeout: Duration::from_secs(2),
                    ..Default::default()
                },
            )
            .await;
    }
}
impl Drop for Deployment {
    fn drop(&mut self) {
        // Also clean if the caller drops/cancels the operation future.
        if let Ok(runtime) = tokio::runtime::Handle::try_current() {
            let client = self.client.clone();
            let directory = self.directory.clone();
            runtime.spawn(async move {
                let _ = client
                    .shell(
                        &format!("rm -f -- {directory}/rename; rmdir -- {directory}"),
                        1024,
                        OperationOptions {
                            timeout: Duration::from_secs(2),
                            ..Default::default()
                        },
                    )
                    .await;
            });
        }
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
        "{name}=$(printf '%b.' '{octal}')\n{name}=${{{name}%.}}\n"
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

async fn run_script(
    client: &Client,
    script: &str,
    options: OperationOptions,
) -> CoreResult<Vec<u8>> {
    // The legacy service may use a PTY. Complete echo suppression before any
    // private path bytes arrive; fail closed if a PTY cannot be made raw.
    const BOOTSTRAP: &str = "if [ -t 0 ]; then stty raw -echo 2>/dev/null || exit 71; fi; printf '__INTEROP_READY__\\n'; IFS= read -r count; script=$(dd bs=1 count=\"$count\" 2>/dev/null); eval \"$script\"";
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
    let mut output = Vec::new();
    let mut buffer = [0; 256];
    loop {
        let count = stream.read(&mut buffer).await?;
        if count == 0 {
            break;
        }
        if output.len() + count > 1024 {
            return Err(CoreError::new("helper_protocol", "文件服务响应过长。"));
        }
        output.extend_from_slice(&buffer[..count]);
    }
    Ok(output)
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
    let source_arg = path_assignment("source", source)?;
    let target_arg = path_assignment("target", target)?;
    let options = OperationOptions::default();
    let abis = client
        .shell(
            "getprop ro.product.cpu.abilist; getprop ro.product.cpu.abi",
            2048,
            options.clone(),
        )
        .await?;
    let (bytes, hash) = artifact(&String::from_utf8_lossy(&abis.stdout))?;
    let directory = format!(
        "/data/local/tmp/interop-fs-{}",
        uuid::Uuid::new_v4().simple()
    );
    let created = client
        .shell(
            &format!("umask 077; if mkdir -- {directory}; then printf created; fi"),
            1024,
            options.clone(),
        )
        .await?;
    if created.stdout != b"created" {
        return Err(CoreError::new(
            "helper_deployment",
            "无法创建独占文件服务目录。",
        ));
    }
    let deployment = Deployment {
        client: client.clone(),
        directory,
    };
    let result=Box::pin(async {
        let path=format!("{}/rename",deployment.directory);
        let mut sync=client.sync(options.clone()).await?;
        sync.push(&RemotePath::new(&path)?,&mut &bytes[..],0o700,0,bytes.len() as u64).await?;
        drop(sync);
        let operation=if replace {"publish-replace"}else{"rename-no-replace"};
        // Pin the opened inode on stdin, hash that descriptor and exec the same
        // descriptor. Replacing the pathname after verification cannot switch
        // the executable. The directory also excludes other Android app UIDs.
        let script=format!(r#"{source_arg}{target_arg}exec 0<{path} || {{ printf '{{"protocol":1,"bootstrap":"open"}}'; exit; }}
hash=$(sha256sum /proc/$$/fd/0 2>/dev/null) || {{ printf '{{"protocol":1,"bootstrap":"hash"}}'; exit; }}
case "$hash" in {hash}' '*) ;; *) printf '{{"protocol":1,"bootstrap":"integrity"}}'; exit ;; esac
exec /proc/self/fd/0 {operation} "$source" "$target"
"#);
        let execution=Box::pin(run_script(client,&script,options)).await.and_then(|output|parse_result(&output,target,replace));
        execution.map_err(|error|if matches!(error.code.as_str(),"disconnected"|"timeout"|"cancelled"|"device_error"|"helper_protocol") {CoreError::new("result_unknown","连接在执行重命名时中断；操作可能已完成，请刷新核对。这个操作不会再次删除源路径。")}else{error})
    }).await;
    deployment.cleanup().await;
    result
}

#[cfg(test)]
mod tests {
    use super::*;
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
