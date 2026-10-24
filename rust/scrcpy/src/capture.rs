//! 上游视频分段和编码首帧读取；不依赖呈现器或应用状态。
use crate::{Error, Result};
use interop_adb::AdbStream;
use std::time::Duration;
pub const MAX_PACKET: usize = 16 * 1024 * 1024;

#[derive(Debug)]
pub enum VideoUnit {
    Dimensions { width: u32, height: u32 },
    Packet { flags: u64, bytes: Vec<u8> },
}

/// 静态画面可无限等待下一包首字节；一旦开始，完整单元必须有界完成。
pub async fn read_video_unit(video: &mut AdbStream) -> Result<VideoUnit> {
    let mut header = [0; 12];
    video.read_exact(&mut header[..1]).await?;
    tokio::time::timeout(Duration::from_secs(10), async {
        video.read_exact(&mut header[1..]).await?;
        if let Some((width, height)) = session_dimensions(&header)? {
            return Ok(VideoUnit::Dimensions { width, height });
        }
        let length = u32::from_be_bytes(header[8..].try_into().expect("固定头长度")) as usize;
        if length == 0 || length > MAX_PACKET {
            return Err(Error::new("video_protocol", "视频数据包长度无效。"));
        }
        let mut bytes = vec![0; length];
        video.read_exact(&mut bytes).await?;
        Ok(VideoUnit::Packet {
            flags: u64::from_be_bytes(header[..8].try_into().expect("固定头长度")),
            bytes,
        })
    })
    .await
    .map_err(|_| Error::new("timeout", "视频数据包读取超时。"))?
}

pub fn session_dimensions(header: &[u8; 12]) -> Result<Option<(u32, u32)>> {
    let flags = u32::from_be_bytes(header[..4].try_into().expect("header"));
    if flags & 0x8000_0000 == 0 {
        return Ok(None);
    }
    // 服务端以 Java 正整数报告尺寸；本机解码器的分配限制由消费方核验。
    let width = i32::from_be_bytes(header[4..8].try_into().expect("header"));
    let height = i32::from_be_bytes(header[8..].try_into().expect("header"));
    if flags & 0x7fff_fffe != 0 || width <= 0 || height <= 0 {
        return Err(Error::new("video_protocol", "视频会话尺寸无效。"));
    }
    Ok(Some((width as u32, height as u32)))
}

pub async fn read_video_preface(
    video: &mut AdbStream,
    initial: [u8; 12],
) -> Result<(Vec<u8>, u32, u32)> {
    tokio::time::timeout(Duration::from_secs(8), async {
        let mut bytes = initial.to_vec();
        let (mut width, mut height) = session_dimensions(&initial)?
            .ok_or_else(|| Error::new("video_protocol", "视频流缺少会话尺寸。"))?;
        for _ in 0..64 {
            let mut header = [0; 12];
            video.read_exact(&mut header).await?;
            if let Some((updated_width, updated_height)) = session_dimensions(&header)? {
                width = updated_width;
                height = updated_height;
                bytes.extend_from_slice(&header);
                continue;
            }
            let length = u32::from_be_bytes(header[8..].try_into().expect("header")) as usize;
            if length == 0 || length > MAX_PACKET || bytes.len() + length + 12 > 2 * MAX_PACKET {
                return Err(Error::new("video_protocol", "首帧数据超出大小限制。"));
            }
            bytes.extend_from_slice(&header);
            let start = bytes.len();
            bytes.resize(start + length, 0);
            video.read_exact(&mut bytes[start..]).await?;
            let flags = u64::from_be_bytes(header[..8].try_into().expect("header"));
            if flags & (1 << 61) != 0 && flags & (1 << 62) == 0 {
                return Ok((bytes, width, height));
            }
        }
        Err(Error::new("video_protocol", "设备未提供有界的编码首帧。"))
    })
    .await
    .map_err(|_| Error::new("encoder_start_failed", "编码首帧未在期限内就绪。"))?
}
