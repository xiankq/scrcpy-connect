//! Opt-in diagnostic clock brackets, never a claim of synchronized clocks.
use crate::{CoreError, CoreResult};
use interop_adb::{CancellationToken, Client, OperationOptions};
use serde_json::{Value, json};
use std::time::Duration;

pub(crate) async fn sample(client: &Client, cancellation: CancellationToken) -> CoreResult<Value> {
    let before = crate::media::monotonic_micros();
    let operation = async {
        let mut stream = client
            .exec(
                "cat /proc/uptime",
                OperationOptions {
                    timeout: Duration::from_secs(2),
                    cancellation: cancellation.clone(),
                },
            )
            .await?;
        let mut output = Vec::new();
        let mut bytes = [0; 128];
        loop {
            let count = stream.read(&mut bytes).await?;
            if count == 0 {
                break;
            }
            if output.len() + count > 128 {
                return Err(CoreError::new("clock_probe", "目标时钟响应过长。"));
            }
            output.extend_from_slice(&bytes[..count]);
        }
        Ok::<_, CoreError>(output)
    };
    let bytes = tokio::select! {
        _ = cancellation.cancelled() => return Err(CoreError::new("cancelled", "时钟诊断已取消。")),
        result = tokio::time::timeout(Duration::from_secs(2), operation) => result
            .map_err(|_| CoreError::new("clock_probe", "目标时钟响应超时。"))??,
    };
    let after = crate::media::monotonic_micros();
    let raw = std::str::from_utf8(&bytes)
        .map_err(|_| CoreError::new("clock_probe", "目标时钟响应不是有效文本。"))?;
    let (lower, upper) = uptime_bucket(raw)
        .ok_or_else(|| CoreError::new("clock_probe", "目标时钟响应格式无效。"))?;
    Ok(json!({
        "controllerBeforeUs": before, "controllerAfterUs": after,
        "targetBootLowerUs": lower, "targetBootUpperUs": upper,
        "quantumUs": 10000, "rawUptime": raw,
    }))
}

fn uptime_bucket(raw: &str) -> Option<(u64, u64)> {
    if !raw.ends_with('\n') {
        return None;
    }
    let mut fields = raw.split_ascii_whitespace();
    let lower = decimal_centiseconds(fields.next()?)?;
    decimal_centiseconds(fields.next()?)?;
    if fields.next().is_some() {
        return None;
    }
    Some((lower, lower.checked_add(10_000)?))
}

fn decimal_centiseconds(field: &str) -> Option<u64> {
    let (seconds, fraction) = field.split_once('.')?;
    if seconds.is_empty()
        || fraction.len() != 2
        || !seconds
            .bytes()
            .chain(fraction.bytes())
            .all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    seconds
        .parse::<u64>()
        .ok()?
        .checked_mul(1_000_000)?
        .checked_add(fraction.parse::<u64>().ok()? * 10_000)
}

#[cfg(test)]
mod tests {
    use super::*;
    use interop_adb::{
        DeviceInfo,
        protocol::{self, Frame},
    };
    use std::collections::HashSet;

    #[test]
    fn rejects_truncated_nondecimal_and_overflowing_clock_output() {
        for raw in [
            "",
            "1.2 3.00\n",
            "1.23 3.45",
            "1.23 3.45\nextra",
            "1e3.00 3.45\n",
            "18446744073709.55 0.00\n",
        ] {
            assert!(uptime_bucket(raw).is_none(), "{raw:?}");
        }
    }

    #[tokio::test]
    async fn brackets_the_entire_exec_response_and_rejects_error_output() {
        let (transport, mut peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::\0".into(),
                features: HashSet::new(),
            },
        )
        .unwrap();
        let server = tokio::spawn(async move {
            for output in ["123456.78 200000.12\n", "cat: permission denied\n"] {
                let open = loop {
                    let frame = Frame::read(&mut peer, 4096, true).await.unwrap();
                    if frame.command == protocol::OPEN {
                        break frame;
                    }
                };
                assert_eq!(open.payload, b"exec:cat /proc/uptime\0");
                Frame::new(protocol::OKAY, 7, open.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
                tokio::time::sleep(Duration::from_millis(20)).await;
                Frame::new(protocol::WRTE, 7, open.arg0, output.as_bytes())
                    .write(&mut peer)
                    .await
                    .unwrap();
                loop {
                    let ack = Frame::read(&mut peer, 4096, true).await.unwrap();
                    if ack.command == protocol::OKAY {
                        break;
                    }
                }
                Frame::new(protocol::CLSE, 7, open.arg0, [])
                    .write(&mut peer)
                    .await
                    .unwrap();
            }
            // Keep the shared transport open until the caller finishes.
            while Frame::read(&mut peer, 4096, true).await.is_ok() {}
        });
        let result = sample(&client, CancellationToken::new()).await.unwrap();
        assert_eq!(result["targetBootLowerUs"], 123_456_780_000u64);
        assert_eq!(result["targetBootUpperUs"], 123_456_790_000u64);
        assert_eq!(result["rawUptime"], "123456.78 200000.12\n");
        assert!(
            result["controllerAfterUs"].as_u64().unwrap()
                - result["controllerBeforeUs"].as_u64().unwrap()
                >= 15_000
        );
        assert!(sample(&client, CancellationToken::new()).await.is_err());
        assert!(!client.is_closed());
        client.close();
        server.await.unwrap();
    }
}
