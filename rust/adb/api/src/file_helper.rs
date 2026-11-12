//! Android 原子路径操作；每次调用将显式注入的不可变助手部署到新建 0700 目录，不信任远端可执行缓存。
use crate::file_system::{FileError, FileResult, HelperResources};
use interop_adb::{Client, OperationOptions, sync::RemotePath};
use serde_json::{Value, json};
use std::{fmt::Write, time::Duration};

struct Deployment {
    lease: interop_adb::AdbStream,
    directory: String,
}
impl Deployment {
    async fn create(
        client: &Client,
        directory: String,
        options: OperationOptions,
    ) -> FileResult<Self> {
        // 创建者宣告成功前即拥有清理职责；保持原始 stdin 打开即租用目录。等待创建回执时调用方被丢弃，也通过 EOF 释放。仅 mkdir 成功后安装清理，冲突不授权删除。mkdir 前等待宿主输入，防止取消 OPEN 在宿主取得租约流前留下孤儿目录。
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
            return Err(FileError::new(
                "helper_deployment",
                "无法创建独占文件服务目录。",
            ));
        }
        Ok(Self { lease, directory })
    }

    async fn cleanup(mut self) {
        // 正常完成时短暂等待远端清理；错误或取消时丢弃同一流，以 EOF 触发清理。
        let _ = tokio::time::timeout(Duration::from_secs(2), async {
            self.lease.write_all(b"\n").await?;
            let mut byte = [0];
            self.lease.read(&mut byte).await
        })
        .await;
    }
}

fn artifact(abis: &str, helpers: &HelperResources) -> FileResult<std::sync::Arc<[u8]>> {
    for abi in abis.split(|c: char| c == ',' || c.is_ascii_whitespace()) {
        if let Some(bytes) = helpers.get(abi) {
            return Ok(bytes.clone());
        }
    }
    Err(FileError::new(
        "unsupported_abi",
        "未提供设备 ABI 对应的文件服务程序。",
    ))
}

pub(crate) fn path_assignment(name: &str, path: &[u8]) -> FileResult<String> {
    if path.is_empty() || path.len() > 4095 || path.contains(&0) {
        return Err(FileError::new(
            "invalid_path",
            "远端路径为空、过长或含有空字节。",
        ));
    }
    let mut octal = String::with_capacity(path.len() * 5);
    for byte in path {
        write!(&mut octal, "\\0{byte:03o}").expect("String writing");
    }
    // 命令替换会去掉尾随换行；哨兵保留全部路径字节，包括换行后缀与非 UTF-8 名称。
    Ok(format!(
        "{name}=$(print -n -- '{octal}.')\n{name}=${{{name}%.}}\n"
    ))
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
) -> FileResult<Vec<u8>> {
    // 旧服务可能使用 PTY；私有路径进入前先完成禁回显，PTY 无法切 raw 时拒绝继续。
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
        return Err(FileError::new(
            "helper_unavailable",
            "设备无法建立无回显的文件服务通道。",
        ));
    }
    // 长度分帧绕过规范行长限制，无需交互 shell。
    stream
        .write_all(format!("{}\n", script.len()).as_bytes())
        .await?;
    stream.write_all(script.as_bytes()).await?;
    // shell 返回已打开可执行描述符字节；增量比较，即使产物损坏且超大也受限。
    let mut artifact_buffer = [0; 4096];
    for expected in expected_artifact.chunks(artifact_buffer.len()) {
        let received = &mut artifact_buffer[..expected.len()];
        stream.read_exact(received).await?;
        if received != expected {
            return Err(FileError::new(
                "helper_integrity",
                "设备文件服务校验失败，未授权执行。",
            ));
        }
    }
    let marker = format!("{}\n", challenge.marker);
    let mut verified = vec![0; marker.len()];
    stream.read_exact(&mut verified).await?;
    if verified != marker.as_bytes() {
        return Err(FileError::new(
            "helper_integrity",
            "设备文件服务长度校验失败，未授权执行。",
        ));
    }
    // 全部产物字节及结束标记匹配前，不向远端 shell 发送授权字节；失败或取消读取丢弃流。
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
            return Err(FileError::new("helper_protocol", "文件服务响应过长。"));
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
    // fd3 保留宿主原始输入，fd0 固定已打开可执行文件；cat、read 和 exec 使用这些描述符，不重新打开路径。不可预测结束标记防止附加产物字节伪装成回读结束。
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

fn parse_result(output: &[u8], _target: &[u8], replace: bool) -> FileResult<Value> {
    let reply: Value = serde_json::from_slice(output).map_err(|_| {
        FileError::new(
            "result_unknown",
            "未取得重命名回执，操作可能已完成；请刷新核对，不会自动重试。",
        )
    })?;
    if reply["protocol"] != 1 {
        return Err(FileError::new(
            "result_unknown",
            "重命名回执无效，请刷新核对结果，不会自动重试。",
        ));
    }
    if let Some(stage) = reply["bootstrap"].as_str() {
        return Err(FileError::new(
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
            FileError::new(
                "result_unknown",
                "未取得有效的重命名结果，请刷新核对，不会自动重试。",
            )
        })?;
    if reply["ok"] == true && errno == 0 {
        return Ok(
            json!({"status":"completed","atomic":true,"operation":if replace{"rename_replace"}else{"rename_noreplace"}}),
        );
    }
    if reply["ok"] != false || errno == 0 {
        return Err(FileError::new(
            "result_unknown",
            "重命名回执不一致，请刷新核对，不会自动重试。",
        ));
    }
    let (code, message) = match errno {
        116 => ("source_changed", "所选文件已被修改或替换，请重新选择。"),
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
    let mut error = FileError::new(code, message);
    error.details = json!({"errno":errno,"atomic":true,"operation":if replace{"publish-replace"}else{"rename-no-replace"}});
    if let Some(hex) = reply.get("recoveryPathHex") {
        let hex = hex
            .as_str()
            .filter(|hex| {
                !hex.is_empty()
                    && hex.len() <= 16384
                    && hex.len() % 2 == 0
                    && hex.bytes().all(|byte| byte.is_ascii_hexdigit())
            })
            .ok_or_else(|| {
                FileError::new(
                    "result_unknown",
                    "隔离对象的恢复回执无效，请刷新核对；不会自动重试。",
                )
            })?;
        let bytes = hex
            .as_bytes()
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| {
                u8::from_str_radix(std::str::from_utf8(pair).expect("ASCII hex"), 16)
                    .expect("validated hex")
            })
            .collect::<Vec<_>>();
        let location = match std::str::from_utf8(&bytes) {
            Ok(path) => format!("{path:?}"),
            Err(_) => format!("原始路径字节 hex:{hex}"),
        };
        error.message = format!(
            "{message} 无法安全恢复源名称；对象已保留在 {location}，请核对并手动恢复；不会自动重试。"
        );
        error.details["recoveryPathHex"] = json!(hex);
    }
    Err(error)
}

pub(crate) async fn rename_bytes_with_options(
    client: &Client,
    helpers: &HelperResources,
    source: &[u8],
    target: &[u8],
    replace: bool,
    options: OperationOptions,
) -> FileResult<Value> {
    let operation = if replace {
        "publish-replace"
    } else {
        "rename-no-replace"
    };
    execute_helper(
        client,
        helpers,
        source,
        target,
        operation,
        1024,
        options,
    )
    .await
    .and_then(|output| parse_result(&output, target, replace))
    .map_err(|error| {
        if matches!(
            error.code.as_str(),
            "disconnected" | "timeout" | "cancelled" | "device_error" | "helper_protocol"
        ) {
            FileError::new(
                "result_unknown",
                "连接在执行重命名时中断；操作可能已完成，请刷新核对。这个操作不会再次删除源路径。",
            )
        } else {
            error
        }
    })
}

pub(crate) async fn mutate_expected(
    client: &Client,
    helpers: &HelperResources,
    source: &[u8],
    target: &[u8],
    delete: bool,
    identity: &str,
    options: OperationOptions,
) -> FileResult<Value> {
    // This suffix becomes one trusted argv in the verified helper invocation.
    if identity.is_empty()
        || identity.len() > 128
        || !identity
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() || byte == b'-')
    {
        return Err(FileError::new(
            "source_changed",
            "缺少可核验的所选文件身份，请重新选择。",
        ));
    }
    let operation = format!(
        "{}:{identity}",
        if delete {
            "delete-expected"
        } else {
            "rename-expected"
        }
    );
    execute_helper(
        client,
        helpers,
        source,
        if delete { source } else { target },
        &operation,
        32 * 1024,
        options,
    )
    .await
    .and_then(|output| parse_result(&output, target, false))
    .map_err(|error| {
        if matches!(
            error.code.as_str(),
            "disconnected" | "timeout" | "cancelled" | "device_error" | "helper_protocol"
        ) {
            FileError::new(
                "result_unknown",
                "文件变更未取得完整回执，请刷新核对；不会自动重试。",
            )
        } else {
            error
        }
    })
}

/// 元数据与变更共享同一已核验可执行部署；助手仅接收 operation、path、limit 三个 argv。
pub(crate) async fn remote_metadata(
    client: &Client,
    helpers: &HelperResources,
    path: &[u8],
    operation: &str,
    limit: usize,
    options: OperationOptions,
) -> FileResult<Value> {
    if !matches!(operation, "stat" | "lstat" | "list") || !(1..=10_000).contains(&limit) {
        return Err(FileError::new(
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
        helpers,
        path,
        limit.to_string().as_bytes(),
        operation,
        response_limit,
        options,
    ))
    .await?;
    parse_metadata(&output)
}

fn parse_metadata(output: &[u8]) -> FileResult<Value> {
    let reply: Value = serde_json::from_slice(output)
        .map_err(|_| FileError::new("helper_protocol", "文件元数据回执无效。"))?;
    let errno = reply["errno"]
        .as_u64()
        .filter(|value| *value < 4096)
        .ok_or_else(|| FileError::new("helper_protocol", "文件元数据回执缺少有效结果。"))?;
    if reply["protocol"] != 1
        || (reply["ok"] != true && reply["ok"] != false)
        || (reply["ok"] == true) != (errno == 0)
    {
        return Err(FileError::new("helper_protocol", "文件元数据回执不一致。"));
    }
    if errno == 0 {
        return Ok(reply);
    }
    Err(interop_adb::Error::RemoteErrno {
        operation: "metadata",
        errno: errno as u32,
    }
    .into())
}

async fn execute_helper(
    client: &Client,
    helpers: &HelperResources,
    source: &[u8],
    target: &[u8],
    operation: &str,
    response_limit: usize,
    options: OperationOptions,
) -> FileResult<Vec<u8>> {
    let cancellation = options.cancellation.clone();
    let timeout = options.timeout;
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(FileError::new("cancelled", "文件服务操作已取消。")),
        result = tokio::time::timeout(timeout, Box::pin(execute_unbounded(client, helpers, source, target, operation, response_limit, options))) =>
            result.map_err(|_| FileError::new("timeout", "设备文件服务操作超时。"))?,
    }
}

async fn execute_unbounded(
    client: &Client,
    helpers: &HelperResources,
    source: &[u8],
    target: &[u8],
    operation: &str,
    response_limit: usize,
    options: OperationOptions,
) -> FileResult<Vec<u8>> {
    let source_arg = path_assignment("source", source)?;
    let target_arg = path_assignment("target", target)?;
    let abis = client
        .shell(
            "getprop ro.product.cpu.abilist; getprop ro.product.cpu.abi",
            2048,
            options.clone(),
        )
        .await?;
    let bytes = artifact(&String::from_utf8_lossy(&abis.stdout), helpers)?;
    let directory = format!("/data/local/tmp/adb-fs-{}", uuid::Uuid::new_v4().simple());
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
        // 宿主仅授权从已打开 inode 回读且与内嵌内容完全一致的字节；该 inode 固定至 exec。无需远端哈希工具，私有目录隔离其他 Android 应用 UID。
        let challenge = LaunchChallenge::new();
        let script = helper_script(&source_arg, &target_arg, &path, operation, &challenge);
        Box::pin(run_script(
            client,
            &script,
            &bytes,
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
