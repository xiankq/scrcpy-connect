use super::*;

// 在仅有 API21 时代工具的本地 shell 上验证真实原始 ADB 引导及生成脚本，无需 Android 设备。
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
        // CI 可提供真实 mksh；回退仅实现观察到的三种 Android print 形式，并刻意拒绝 printf。
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
                            // 宿主丢弃流时 adbd 关闭原始 exec socket，将 EOF 交给 stdin。
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
const FIXTURE_HELPER: &[u8] =
    b"#!/bin/sh\nprintf '%s' \"$3\" > \"$2\"\nprintf '{\"protocol\":1,\"ok\":true,\"errno\":0}'\n";

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
) -> (FileResult<Vec<u8>>, Option<Vec<u8>>) {
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
            std::fs::set_permissions(&replacement, std::fs::Permissions::from_mode(0o700)).unwrap();
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
async fn helper_authorization_and_receipts_follow_the_verified_artifact() {
    use LaunchFixture::*;
    let helper = FIXTURE_HELPER;
    let mut changed = helper.to_vec();
    let last = changed.len() - 2;
    changed[last] = b' ';
    let appended = [helper, b"extra"].concat();
    let forged_marker = [helper, b"__INTEROP_VERIFIED__\n"].concat();
    // These cases share a complete shell/ADB fixture; each retains its distinct
    // authorization, executable-inode, interruption or output-bound assertion.
    for (actual, variant, limit, expected) in [
        (helper, Normal, 1024, "completed"),
        (helper, ReplacePath, 1024, "completed"),
        (helper, WrongAuthorization, 1024, "withheld"),
        (helper, CancelVerification, 1024, "cancelled"),
        (helper, Normal, 8, "helper_protocol"),
        (&helper[..helper.len() - 2], Normal, 1024, "truncated"),
        (changed.as_slice(), Normal, 1024, "helper_integrity"),
        (appended.as_slice(), Normal, 1024, "helper_integrity"),
        (forged_marker.as_slice(), Normal, 1024, "helper_integrity"),
    ] {
        let (output, receipt) = fixture_execution(actual, helper, variant, limit).await;
        match expected {
            "completed" => {
                assert_eq!(output.unwrap(), br#"{"protocol":1,"ok":true,"errno":0}"#);
                assert_eq!(receipt.unwrap(), b"private-'$\n\xff");
            }
            "withheld" => {
                assert!(output.unwrap().is_empty());
                assert!(receipt.is_none());
            }
            "truncated" => {
                assert!(output.is_err());
                assert!(receipt.is_none());
            }
            code => {
                assert_eq!(output.unwrap_err().code, code);
                if code != "helper_protocol" {
                    assert!(receipt.is_none(), "an unauthorized helper cannot execute");
                }
            }
        }
    }
}

#[test]
fn metadata_errno_and_envelopes_are_checked_before_use() {
    let preserved = parse_result(
        br#"{"protocol":1,"ok":false,"errno":116,"recoveryPathHex":"2f7364636172642f6974656d"}"#,
        b"",
        false,
    )
    .unwrap_err();
    assert_eq!(preserved.code, "source_changed");
    assert!(preserved.message.contains("/sdcard/item"));
    assert_eq!(
        preserved.details["recoveryPathHex"],
        "2f7364636172642f6974656d"
    );
    assert_eq!(
        parse_result(
            br#"{"protocol":1,"ok":false,"errno":116,"recoveryPathHex":"z"}"#,
            b"",
            false
        )
        .unwrap_err()
        .code,
        "result_unknown"
    );
    assert_eq!(
        parse_metadata(
            br#"{"protocol":1,"ok":true,"errno":0,"mode":33188,"size":5,"modifiedSeconds":123}"#
        )
        .unwrap()["size"],
        5
    );
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
