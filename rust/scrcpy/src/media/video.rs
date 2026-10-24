//! 将 scrcpy 视频单元交付到原生媒体 ABI。
use super::{MediaError, MediaResult};
use crate::capture::{MAX_PACKET, session_dimensions};

/// 独立 SDK 捕获复用同一原生包投递实现；renderer 不消费时按来源背压，不向 Dart 复制媒体。
pub async fn forward_video(
    source: std::sync::Arc<crate::media::native::MediaSource>,
    mut stream: interop_adb::AdbStream,
    preface: Vec<u8>,
    cancellation: interop_adb::CancellationToken,
) -> MediaResult<()> {
    let operation = async {
        source.wait_attached().await?;
        let mut packets = VideoPackets::default();
        packets.preface(&source, &preface).await?;
        loop {
            let unit = crate::capture::read_video_unit(&mut stream).await?;
            let (header, bytes) = match unit {
                crate::capture::VideoUnit::Dimensions { width, height } => {
                    let mut header = [0; 12];
                    header[..4].copy_from_slice(&0x8000_0000u32.to_be_bytes());
                    header[4..8].copy_from_slice(&width.to_be_bytes());
                    header[8..].copy_from_slice(&height.to_be_bytes());
                    (header, Vec::new())
                }
                crate::capture::VideoUnit::Packet { flags, bytes } => {
                    let mut header = [0; 12];
                    header[..8].copy_from_slice(&flags.to_be_bytes());
                    header[8..].copy_from_slice(&(bytes.len() as u32).to_be_bytes());
                    (header, bytes)
                }
            };
            packets.unit(&source, &header, bytes).await?;
        }
    };
    let result = tokio::select! {
        _=cancellation.cancelled()=>Ok(()),
        result=operation=>result,
    };
    source.finish();
    cancellation.cancel();
    result
}

#[derive(Default)]
pub struct VideoPackets {
    pub dimensions: Option<(u32, u32)>,
    pub configuration: Vec<u8>,
    pub pending_configuration: Vec<u8>,
    pub pending: bool,
    pub pending_units: usize,
}

impl VideoPackets {
    pub async fn unit(
        &mut self,
        output: &crate::media::native::MediaSource,
        header: &[u8; 12],
        bytes: Vec<u8>,
    ) -> MediaResult<()> {
        if let Some(dimensions) = session_dimensions(header)? {
            self.dimensions = Some(dimensions);
            // reset 可在旧 CSD 获帧前发出新 session；禁止跨会话拼接参数集。
            self.pending_configuration.clear();
            self.pending = true;
            self.pending_units = 0;
            return Ok(());
        }
        let flags = u64::from_be_bytes(header[..8].try_into().expect("fixed header"));
        if flags & (1 << 62) != 0 {
            if !self.pending {
                self.pending = true;
                self.pending_units = 0;
                self.pending_configuration.clear();
            }
            if self.pending_configuration.len() + bytes.len()
                > crate::media::MAX_CONFIGURATION_BYTES
            {
                return Err(MediaError::new("video_protocol", "视频配置超过限额。"));
            }
            self.pending_configuration.extend_from_slice(&bytes);
            self.pending_units += 1;
            if self.pending_units > 64 {
                return Err(MediaError::new(
                    "video_protocol",
                    "视频配置未在限额内跟随关键帧。",
                ));
            }
            return Ok(());
        }
        let keyframe = flags & (1 << 61) != 0;
        if self.pending {
            self.pending_units += 1;
            if self.pending_units > 64 {
                return Err(MediaError::new(
                    "video_protocol",
                    "视频配置未在限额内跟随关键帧。",
                ));
            }
            if !keyframe {
                return Ok(());
            }
            let (width, height) = self
                .dimensions
                .ok_or_else(|| MediaError::new("video_protocol", "视频流缺少会话尺寸。"))?;
            if !self.pending_configuration.is_empty() {
                self.configuration = std::mem::take(&mut self.pending_configuration);
            }
            output.configure(width, height, &self.configuration).await?;
            self.pending = false;
        }
        output
            .packet_owned(bytes, flags & ((1 << 61) - 1), keyframe)
            .await
    }
    pub async fn preface(
        &mut self,
        output: &crate::media::native::MediaSource,
        mut bytes: &[u8],
    ) -> MediaResult<()> {
        while !bytes.is_empty() {
            if bytes.len() < 12 {
                return Err(MediaError::new("video_protocol", "视频首帧前缀不完整。"));
            }
            let header: [u8; 12] = bytes[..12].try_into().expect("bounded header");
            bytes = &bytes[12..];
            let length = if session_dimensions(&header)?.is_some() {
                0
            } else {
                u32::from_be_bytes(header[8..].try_into().expect("header")) as usize
            };
            if length > bytes.len() || length > MAX_PACKET {
                return Err(MediaError::new("video_protocol", "视频首帧数据不完整。"));
            }
            self.unit(output, &header, bytes[..length].to_vec()).await?;
            bytes = &bytes[length..];
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::media::native::{MediaSource, testing::Reader};
    use interop_adb::CancellationToken;
    use tokio::io::AsyncReadExt;

    #[tokio::test]
    async fn protocol_dimensions_reach_a_sink_without_inheriting_decoder_limits() {
        let source = MediaSource::register(
            uuid::Uuid::new_v4().simple().to_string(),
            1,
            65536,
            16385,
            CancellationToken::new(),
        )
        .unwrap();
        let mut reader = Reader::attach(source.id(), 1);
        let mut preface = Vec::new();
        preface.extend_from_slice(&0x8000_0000u32.to_be_bytes());
        preface.extend_from_slice(&65536u32.to_be_bytes());
        preface.extend_from_slice(&16385u32.to_be_bytes());
        preface.extend_from_slice(&(1u64 << 61).to_be_bytes());
        preface.extend_from_slice(&1u32.to_be_bytes());
        preface.push(0x42);
        VideoPackets::default()
            .preface(&source, &preface)
            .await
            .unwrap();
        let mut forwarded = [0; 25];
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            reader.read_exact(&mut forwarded),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(forwarded.as_slice(), preface);
    }
}
