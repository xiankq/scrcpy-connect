//! 原始双声道 PCM 协议读取；通道接纳归 Session，播放与静音归宿主。
use crate::{Error, Result};
use interop_adb::AdbStream;
use std::time::Duration;

/// 已由首通道读过 dummy/name 后，只读取音频自身的格式标识。
pub async fn read_codec(stream: &mut AdbStream) -> Result<()> {
    let mut codec = [0; 4];
    stream.read_exact(&mut codec).await?;
    if codec == [0; 4] {
        return Err(Error::new("audio_unavailable", "设备禁用了本次音频采集。"));
    }
    if codec != [0, b'r', b'a', b'w'] {
        return Err(Error::new(
            "audio_protocol",
            "设备未返回请求的原始 PCM 音频流。",
        ));
    }
    Ok(())
}

pub fn pcm_packet_size(header: &[u8; 12]) -> Result<usize> {
    let flags = u64::from_be_bytes(header[..8].try_into().expect("固定音频头"));
    let length = u32::from_be_bytes(header[8..].try_into().expect("固定音频头")) as usize;
    if flags >> 61 != 0 || length > 4096 || !length.is_multiple_of(4) {
        return Err(Error::new("audio_protocol", "设备音频包的格式或大小无效。"));
    }
    Ok(length)
}

pub struct PcmPacket {
    pub pts_us: u64,
    pub bytes: Vec<u8>,
}
pub async fn read_pcm_packet(stream: &mut AdbStream) -> Result<PcmPacket> {
    let mut header = [0; 12];
    stream.read_exact(&mut header[..1]).await?;
    tokio::time::timeout(Duration::from_secs(10), async {
        stream.read_exact(&mut header[1..]).await?;
        let mut bytes = vec![0; pcm_packet_size(&header)?];
        stream.read_exact(&mut bytes).await?;
        Ok(PcmPacket {
            pts_us: u64::from_be_bytes(header[..8].try_into().expect("固定音频头")),
            bytes,
        })
    })
    .await
    .map_err(|_| Error::new("audio_timeout", "音频数据包未及时发送完整。"))?
}
