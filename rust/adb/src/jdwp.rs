//! 只读直连 adbd 的 JDWP 服务；PID 不是应用身份。
use crate::{AdbStream, Client, Error, OperationOptions, Result, error::bounded};
use std::num::NonZeroU32;

fn pids(bytes: &[u8], maximum: usize) -> Result<Vec<NonZeroU32>> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| Error::Protocol("JDWP process list is not ASCII".into()))?;
    let mut result = Vec::new();
    for line in text.lines() {
        if line.is_empty()
            || !line.bytes().all(|byte| byte.is_ascii_digit())
            || result.len() >= maximum
        {
            return Err(Error::Protocol(
                "invalid or oversized JDWP process list".into(),
            ));
        }
        let pid = line
            .parse::<u32>()
            .ok()
            .and_then(NonZeroU32::new)
            .ok_or_else(|| Error::Protocol("invalid JDWP PID".into()))?;
        result.push(pid);
    }
    Ok(result)
}

/// 四位十六进制长度分帧的 JDWP 更新。next_event 的 future 被丢弃后仍保留头部与正文进度，允许调用方与界面或控制输入并行等待。
pub struct JdwpTracker {
    stream: AdbStream,
    maximum: usize,
    header: [u8; 4],
    header_read: usize,
    body: Vec<u8>,
    body_read: usize,
    ended: bool,
}
impl JdwpTracker {
    pub async fn next_event(&mut self) -> Result<Option<Vec<NonZeroU32>>> {
        if self.ended {
            return Ok(None);
        }
        while self.header_read < 4 {
            let count = self
                .stream
                .read(&mut self.header[self.header_read..])
                .await?;
            if count == 0 {
                self.ended = true;
                if self.header_read == 0 {
                    return Ok(None);
                }
                return Err(Error::Protocol("truncated JDWP tracker header".into()));
            }
            self.header_read += count;
        }
        if !self.header.iter().all(u8::is_ascii_hexdigit) {
            self.stream.close_now();
            return Err(Error::Protocol("invalid JDWP tracker length".into()));
        }
        let length = usize::from_str_radix(std::str::from_utf8(&self.header).expect("ASCII"), 16)
            .expect("four hex digits");
        if length > self.maximum * 11 {
            self.stream.close_now();
            return Err(Error::OutputLimit);
        }
        self.body.resize(length, 0);
        while self.body_read < length {
            let count = self.stream.read(&mut self.body[self.body_read..]).await?;
            if count == 0 {
                self.stream.close_now();
                return Err(Error::Protocol("truncated JDWP tracker payload".into()));
            }
            self.body_read += count;
        }
        let result = pids(&self.body, self.maximum);
        self.body.clear();
        self.body_read = 0;
        self.header_read = 0;
        if result.is_err() {
            self.stream.close_now();
        }
        result.map(Some)
    }
    pub async fn close(self) -> Result<()> {
        self.stream.close().await
    }
}

fn check_maximum(maximum: usize) -> Result<()> {
    if !(1..=16384).contains(&maximum) {
        return Err(Error::InvalidArgument(
            "JDWP process limit must be between 1 and 16384",
        ));
    }
    Ok(())
}
impl Client {
    /// 从 track-jdwp 读取一份当前快照，包括显式空更新；旧版无分帧 jdwp 服务在 PID 列表为空时可能永不关闭。
    pub async fn jdwp_processes(
        &self,
        maximum: usize,
        options: OperationOptions,
    ) -> Result<Vec<NonZeroU32>> {
        check_maximum(maximum)?;
        bounded(options.timeout, &options.cancellation, async {
            let mut tracker = self.track_jdwp(maximum, options.clone()).await?;
            let current = tracker.next_event().await?.ok_or_else(|| {
                Error::Protocol("JDWP tracker closed before its first snapshot".into())
            })?;
            tracker.close().await?;
            Ok(current)
        })
        .await
    }
    pub async fn track_jdwp(
        &self,
        maximum: usize,
        options: OperationOptions,
    ) -> Result<JdwpTracker> {
        check_maximum(maximum)?;
        Ok(JdwpTracker {
            stream: self.open("track-jdwp", options).await?,
            maximum,
            header: [0; 4],
            header_read: 0,
            body: Vec::new(),
            body_read: 0,
            ended: false,
        })
    }
}
