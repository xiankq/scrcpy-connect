//! Filesystem compatibility shared by tree transfers, search and gallery.
//! SYNC remains the fast path; its denied metadata is resolved by the same
//! descriptor-verified native helper, without depending on Android shell tools.
use crate::{CoreError, CoreResult, model::quote, remote_helper::remote_metadata};
use interop_adb::{
    Client, OperationOptions, ShellOutput,
    sync::{FileStat, RemotePath},
};
use serde_json::Value;

pub(crate) fn storage_alias(path: &str) -> bool {
    matches!(path, "/sdcard" | "/mnt/sdcard" | "/storage/self/primary")
}

/// Preserve real exit status for mutations even on the unframed exec protocol.
/// An absent receipt is unknown, never success and never an automatic retry.
pub(crate) async fn command(
    client: &Client,
    script: &str,
    max_output: usize,
    options: OperationOptions,
) -> CoreResult<ShellOutput> {
    let cancellation = options.cancellation.clone();
    let timeout = options.timeout;
    let execute = async {
        if client.info().features.contains("shell_v2") {
            return Ok(client.shell(script, max_output, options).await?);
        }
        let marker = format!("INTEROP_EXIT_{}:", uuid::Uuid::new_v4().simple());
        let script = format!(
            "(\n{script}\n); interop_status=$?; print -nr -- '{marker}'\"$interop_status\""
        );
        let mut stream = client.exec(&script, options).await?;
        let mut output = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let count = stream.read(&mut buffer).await?;
            if count == 0 {
                break;
            }
            if output.len() + count > max_output.saturating_add(marker.len() + 3) {
                return Err(CoreError::new(
                    "result_unknown",
                    "设备操作回执超过限制，请刷新核对结果。",
                ));
            }
            output.extend_from_slice(&buffer[..count]);
        }
        let index = output
            .windows(marker.len())
            .rposition(|part| part == marker.as_bytes())
            .ok_or_else(|| {
                CoreError::new("result_unknown", "未取得设备操作回执，请刷新核对结果。")
            })?;
        let code = std::str::from_utf8(&output[index + marker.len()..])
            .ok()
            .filter(|text| {
                !text.is_empty()
                    && text.len() <= 3
                    && text.bytes().all(|byte| byte.is_ascii_digit())
            })
            .and_then(|text| text.parse::<u8>().ok())
            .ok_or_else(|| {
                CoreError::new("result_unknown", "设备操作回执无效，请刷新核对结果。")
            })?;
        output.truncate(index);
        if output.len() > max_output {
            return Err(CoreError::new(
                "result_unknown",
                "设备操作回执超过限制，请刷新核对结果。",
            ));
        }
        Ok(ShellOutput {
            stdout: if code == 0 {
                output.clone()
            } else {
                Vec::new()
            },
            stderr: if code == 0 { Vec::new() } else { output },
            exit_code: Some(u32::from(code)),
        })
    };
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(CoreError::new("cancelled", "设备操作已取消。")),
        result = tokio::time::timeout(timeout, Box::pin(execute)) => result.map_err(|_| CoreError::new("timeout", "设备操作超时。"))?,
    }
}

pub(crate) async fn stat(
    client: &Client,
    path: &str,
    follow_alias: bool,
    options: OperationOptions,
) -> CoreResult<FileStat> {
    // Only the three explicit Android storage roots may be resolved. Appending
    // /. makes legacy STAT inspect the directory rather than the alias inode.
    let resolved = if follow_alias && storage_alias(path) {
        format!("{path}/.")
    } else {
        path.to_owned()
    };
    // Classic STAT truncates st_size to u32 and cannot describe errno. The
    // native service preserves both, including files larger than 4 GiB.
    if !client.info().features.contains("stat_v2") {
        return metadata(&remote_metadata(client, &resolved, "lstat", 1, options).await?);
    }
    let mut sync = client.sync(options.clone()).await?;
    match sync.lstat(&RemotePath::new(&resolved)?).await {
        Ok(stat) => Ok(stat),
        Err(
            interop_adb::Error::RemoteErrno {
                errno: 1 | 13 | 38 | 95,
                ..
            }
            | interop_adb::Error::Remote(_)
            | interop_adb::Error::Unsupported(_),
        ) => metadata(&remote_metadata(client, &resolved, "lstat", 1, options).await?),
        // SYNC v2 already returned an authoritative result for absence and
        // invalid paths. Transport errors cannot be repaired by deploying a
        // second service on that same connection either.
        Err(error) => Err(error.into()),
    }
}

pub(crate) async fn accessible(
    client: &Client,
    path: &str,
    options: OperationOptions,
) -> CoreResult<bool> {
    let path = quote(path)?;
    // Legacy shell has neither a separate stderr nor an exit code. An exact
    // positive receipt avoids mistaking an empty/error response for permission.
    let mut stream = client
        .exec(
            &format!("if [ -r {path} ] && [ -x {path} ]; then print -nr -- INTEROP_ACCESSIBLE; fi"),
            options,
        )
        .await?;
    let mut output = Vec::new();
    let mut buffer = [0; 64];
    loop {
        let count = stream.read(&mut buffer).await?;
        if count == 0 {
            break;
        }
        if output.len() + count > 64 {
            return Ok(false);
        }
        output.extend_from_slice(&buffer[..count]);
    }
    Ok(output == b"INTEROP_ACCESSIBLE")
}

pub(crate) struct Listing {
    pub(crate) entries: Vec<(Vec<u8>, CoreResult<FileStat>)>,
    pub(crate) truncated: bool,
}

pub(crate) async fn fallback_children(
    client: &Client,
    path: &str,
    limit: usize,
    options: OperationOptions,
) -> CoreResult<Listing> {
    let limit = limit.clamp(1, 10_000);
    let path = if storage_alias(path) {
        format!("{path}/.")
    } else {
        path.to_owned()
    };
    let reply = remote_metadata(client, &path, "list", limit, options).await?;
    listing(&reply, limit)
}

fn invalid() -> CoreError {
    CoreError::new("invalid_metadata", "设备文件元数据格式无效。")
}

fn metadata(value: &Value) -> CoreResult<FileStat> {
    Ok(FileStat {
        mode: value["mode"]
            .as_u64()
            .and_then(|mode| mode.try_into().ok())
            .ok_or_else(invalid)?,
        size: value["size"].as_u64().ok_or_else(invalid)?,
        modified_seconds: value["modifiedSeconds"].as_i64().ok_or_else(invalid)?,
    })
}

fn name(value: &Value) -> CoreResult<Vec<u8>> {
    let text = value.as_str().ok_or_else(invalid)?;
    if text.is_empty() || text.len() > 510 || text.len() % 2 != 0 {
        return Err(invalid());
    }
    let bytes = text
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            let digit = |b| match b {
                b'0'..=b'9' => Some(b - b'0'),
                b'a'..=b'f' => Some(b - b'a' + 10),
                _ => None,
            };
            Some(digit(pair[0])? * 16 + digit(pair[1])?)
        })
        .collect::<Option<Vec<_>>>()
        .ok_or_else(invalid)?;
    if matches!(bytes.as_slice(), b"." | b"..") || bytes.contains(&b'/') || bytes.contains(&0) {
        return Err(invalid());
    }
    Ok(bytes)
}

fn listing(reply: &Value, limit: usize) -> CoreResult<Listing> {
    let values = reply["entries"]
        .as_array()
        .filter(|entries| entries.len() <= limit)
        .ok_or_else(invalid)?;
    let truncated = reply["truncated"].as_bool().ok_or_else(invalid)?;
    let mut entries = Vec::with_capacity(values.len());
    for value in values {
        let name = name(&value["nameHex"])?;
        let errno = value["errno"]
            .as_u64()
            .filter(|errno| *errno < 4096)
            .ok_or_else(invalid)?;
        let stat = if errno == 0 {
            metadata(value)
        } else {
            let (code, message) = match errno {
                1 | 13 => ("permission_denied", "设备拒绝读取目录项元数据。"),
                2 => ("source_changed", "目录项已消失。"),
                _ => ("remote_stat_failed", "无法读取目录项元数据。"),
            };
            Err(CoreError::new(code, message))
        };
        entries.push((name, stat));
    }
    Ok(Listing { entries, truncated })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    async fn stat_fixture(
        errno: Option<u32>,
    ) -> (
        Client,
        std::sync::Arc<std::sync::atomic::AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        use interop_adb::{
            DeviceInfo,
            protocol::{self, Frame},
        };
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        let (transport, mut peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::features=stat_v2;\0".into(),
                features: ["stat_v2".into()].into(),
            },
        )
        .unwrap();
        let opens = Arc::new(AtomicUsize::new(0));
        let seen = opens.clone();
        let server = tokio::spawn(async move {
            while let Ok(frame) = Frame::read(&mut peer, 4096, true).await {
                match frame.command {
                    protocol::OPEN => {
                        seen.fetch_add(1, Ordering::SeqCst);
                        let accepted = frame.payload == b"sync:\0";
                        Frame::new(
                            if accepted {
                                protocol::OKAY
                            } else {
                                protocol::CLSE
                            },
                            frame.arg0 + 100,
                            frame.arg0,
                            [],
                        )
                        .write(&mut peer)
                        .await
                        .unwrap();
                    }
                    protocol::WRTE => {
                        assert_eq!(&frame.payload[..4], b"LST2");
                        Frame::new(protocol::OKAY, frame.arg1, frame.arg0, [])
                            .write(&mut peer)
                            .await
                            .unwrap();
                        if let Some(errno) = errno {
                            let mut reply = b"LST2".to_vec();
                            reply.extend_from_slice(&errno.to_le_bytes());
                            reply.extend_from_slice(&[0; 64]);
                            Frame::new(protocol::WRTE, frame.arg1, frame.arg0, reply)
                                .write(&mut peer)
                                .await
                                .unwrap();
                        }
                    }
                    _ => {}
                }
            }
        });
        (client, opens, server)
    }

    #[tokio::test]
    async fn authoritative_sync_errno_does_not_deploy_a_metadata_helper() {
        use std::sync::atomic::Ordering;
        for (errno, expected) in [
            (2, "not_found"),
            (20, "not_directory"),
            (36, "invalid_path"),
        ] {
            let (client, opens, server) = stat_fixture(Some(errno)).await;
            let error = stat(
                &client,
                "/sdcard/missing",
                false,
                OperationOptions::default(),
            )
            .await
            .unwrap_err();
            assert_eq!(error.code, expected, "errno {errno}");
            assert_eq!(error.details["errno"], errno);
            assert_eq!(
                opens.load(Ordering::SeqCst),
                1,
                "an authoritative errno needs only SYNC"
            );
            client.close();
            server.abort();
        }
    }

    #[tokio::test]
    async fn denied_sync_metadata_still_uses_the_verified_helper_path() {
        use std::sync::atomic::Ordering;
        for errno in [1, 13, 38, 95] {
            let (client, opens, server) = stat_fixture(Some(errno)).await;
            let result = stat(
                &client,
                "/sdcard/denied",
                false,
                OperationOptions::default(),
            )
            .await;
            // This peer refuses the ABI shell OPEN; observing it proves the
            // helper path is retained without executing a remote program.
            assert!(result.is_err());
            assert_eq!(
                opens.load(Ordering::SeqCst),
                2,
                "errno {errno} must retain fallback"
            );
            client.close();
            server.abort();
        }
    }

    #[tokio::test]
    async fn silent_sync_metadata_timeout_does_not_start_another_service() {
        use std::{sync::atomic::Ordering, time::Duration};
        let (client, opens, server) = stat_fixture(None).await;
        let options = OperationOptions {
            timeout: Duration::from_millis(25),
            ..Default::default()
        };
        let error = stat(&client, "/sdcard/stalled", false, options)
            .await
            .unwrap_err();
        assert_eq!(error.code, "timeout");
        assert_eq!(opens.load(Ordering::SeqCst), 1);
        client.close();
        server.abort();
    }

    #[test]
    fn metadata_preserves_wide_sizes_and_signed_times() {
        let stat =
            metadata(&json!({"mode":33152,"size":5_000_000_000u64,"modifiedSeconds":-1})).unwrap();
        assert_eq!(stat.size, 5_000_000_000);
        assert_eq!(stat.modified_seconds, -1);
        for bad in [
            json!({"mode":33152,"size":-1,"modifiedSeconds":0}),
            json!({"mode":u64::MAX,"size":0,"modifiedSeconds":0}),
        ] {
            assert!(metadata(&bad).is_err());
        }
    }

    #[test]
    fn listing_preserves_raw_names_and_failed_entries_without_following_them() {
        let value = json!({"truncated":true,"entries":[
            {"nameHex":"270aff","mode":41471,"size":4,"modifiedSeconds":0,"errno":0},
            {"nameHex":"676f6e65","errno":2}
        ]});
        let listing = listing(&value, 2).unwrap();
        assert!(listing.truncated);
        assert_eq!(listing.entries[0].0, b"'\n\xff");
        assert_eq!(
            listing.entries[0].1.as_ref().unwrap().mode & 0o170000,
            0o120000
        );
        assert_eq!(
            listing.entries[1].1.as_ref().unwrap_err().code,
            "source_changed"
        );
    }

    #[test]
    fn malformed_or_unbounded_directory_records_are_rejected() {
        for value in [
            json!("2e2e"),
            json!("00"),
            json!("2f"),
            json!("gg"),
            json!("1"),
            json!(""),
            json!("a".repeat(512)),
        ] {
            assert!(name(&value).is_err());
        }
        assert!(listing(&json!({"entries":[],"truncated":"false"}), 1).is_err());
        assert!(listing(&json!({"entries":[{},{}],"truncated":false}), 1).is_err());
    }
}
