//! Authenticated loopback delivery for the shared cross-platform media player.

use super::{
    MAX_CONFIGURATION_BYTES, MAX_PACKET_BYTES, MatroskaMuxer, Track, VideoCodec, VideoTrack,
};
use crate::{CoreError, CoreResult};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    net::Ipv4Addr,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{
        TcpListener, TcpStream,
        tcp::{OwnedReadHalf, OwnedWriteHalf},
    },
    sync::Mutex,
};
use tokio_util::sync::CancellationToken;

struct Entry {
    cancellation: CancellationToken,
    status: Arc<Mutex<Value>>,
    finished: Arc<AtomicBool>,
}

struct Completion(Arc<AtomicBool>);
impl Drop for Completion {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Release);
    }
}

/// Transport ownership is process-level. A URL is a single-use delivery handle,
/// never a persisted session identity or permission to create another session.
#[derive(Default)]
pub struct MediaStreams {
    entries: Mutex<HashMap<String, Entry>>,
}

impl MediaStreams {
    pub async fn command(&self, command: &str, params: &Value) -> CoreResult<Value> {
        match command {
            "media.open" => self.open(params).await,
            "media.status" => {
                let entries = self.entries.lock().await;
                let entry = entries
                    .get(required(params, "relayId")?)
                    .ok_or_else(|| CoreError::new("media_ended", "媒体输入已结束。"))?;
                Ok(entry.status.lock().await.clone())
            }
            "media.close" => {
                if let Some(entry) = self
                    .entries
                    .lock()
                    .await
                    .remove(required(params, "relayId")?)
                {
                    entry.cancellation.cancel();
                }
                Ok(json!({"closed": true}))
            }
            _ => Err(CoreError::new("unknown_command", "未知媒体传输操作。")),
        }
    }

    async fn open(&self, params: &Value) -> CoreResult<Value> {
        let port = params["port"]
            .as_u64()
            .filter(|p| (1..=65535).contains(p))
            .ok_or_else(|| CoreError::new("invalid_endpoint", "媒体端口无效。"))?
            as u16;
        let token = required(params, "token")?.to_owned();
        if token.len() != 64 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(CoreError::new("invalid_endpoint", "媒体授权标识无效。"));
        }
        let video = match required(params, "kind")? {
            "video" => Some(VideoCodec::from_name(required(params, "codec")?).map_err(mux_error)?),
            "audio" => None,
            _ => return Err(CoreError::new("invalid_endpoint", "媒体类型无效。")),
        };
        let generation = params["generation"].as_u64().unwrap_or(1);
        let endpoint = HttpEndpoint::bind().await?;
        let id = uuid::Uuid::new_v4().to_string();
        let initial = endpoint.view(&id, generation, video, None);
        let cancellation = CancellationToken::new();
        let finished = Arc::new(AtomicBool::new(false));
        let status = Arc::new(Mutex::new(
            json!({"relayId": id, "generation": generation, "endpoint":initial,"status": "waiting", "packets": 0, "bytes": 0}),
        ));
        if params["traceFrames"].as_bool() == Some(true) {
            status.lock().await["frameTrace"] = json!([]);
        }
        {
            let mut entries = self.entries.lock().await;
            entries.retain(|_, entry| !entry.finished.load(Ordering::Acquire));
            if entries.len() >= 32 {
                return Err(CoreError::new(
                    "resource_busy",
                    "媒体输入数量已达上限，请先结束其他活动。",
                ));
            }
            entries.insert(
                id.clone(),
                Entry {
                    cancellation: cancellation.clone(),
                    status: status.clone(),
                    finished: finished.clone(),
                },
            );
        }
        let completion = Completion(finished);
        tokio::spawn(async move {
            let _completion = completion;
            let work = relay(endpoint, port, &token, video, generation, status.clone());
            let result =
                tokio::select! { _ = cancellation.cancelled() => Ok(()), result = work => result };
            let mut state = status.lock().await;
            state["status"] = json!(if result.is_ok() { "closed" } else { "failed" });
            if let Err(error) = result {
                state["reason"] = json!(error.message);
                state["errorCode"] = json!(error.code);
            }
        });
        Ok(initial)
    }
}

impl Drop for MediaStreams {
    fn drop(&mut self) {
        for entry in self.entries.get_mut().values() {
            entry.cancellation.cancel();
        }
    }
}

fn required<'a>(params: &'a Value, name: &str) -> CoreResult<&'a str> {
    params[name]
        .as_str()
        .ok_or_else(|| CoreError::new("invalid_endpoint", format!("缺少媒体参数：{name}。")))
}

fn mux_error(error: super::MuxError) -> CoreError {
    CoreError::new("media_mux", error.to_string())
}

struct HttpEndpoint {
    listener: TcpListener,
    secret: String,
    url: String,
}
impl HttpEndpoint {
    async fn bind() -> CoreResult<Self> {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
        let port = listener.local_addr()?.port();
        let secret = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        let url = format!("http://127.0.0.1:{port}/{secret}");
        Ok(Self {
            listener,
            secret,
            url,
        })
    }
    fn view(
        &self,
        id: &str,
        generation: u64,
        video: Option<VideoCodec>,
        format: Option<&MediaFormat>,
    ) -> Value {
        let codec = match video {
            Some(VideoCodec::H264) => "h264",
            Some(VideoCodec::H265) => "h265",
            Some(VideoCodec::Av1) => "av1",
            Some(VideoCodec::Vp8) => "vp8",
            Some(VideoCodec::Vp9) => "vp9",
            None => "pcm_s16le",
        };
        let mut view = json!({"relayId":id,"url":self.url,"generation":generation,"container":"matroska","singleUse":true,"kind":if video.is_some(){"video"}else{"audio"},"codec":codec});
        if let Some((width, height)) = format.and_then(|format| format.dimensions) {
            view["width"] = json!(width);
            view["height"] = json!(height);
        }
        view
    }
}

async fn authenticated_client(listener: &TcpListener, token: &str) -> CoreResult<TcpStream> {
    tokio::time::timeout(Duration::from_secs(20), async {
        for _ in 0..8 {
            let (mut stream, _) = listener.accept().await?;
            stream.set_nodelay(true)?;
            let mut request = Vec::new();
            let valid = tokio::time::timeout(Duration::from_secs(2), async {
                while request.len() < 4096 {
                    let byte = stream.read_u8().await?;
                    request.push(byte);
                    if request.ends_with(b"\r\n\r\n") {
                        break;
                    }
                }
                Ok::<_, std::io::Error>(
                    request.starts_with(format!("GET /{token} HTTP/1.").as_bytes())
                        && request.ends_with(b"\r\n\r\n"),
                )
            })
            .await;
            if matches!(valid, Ok(Ok(true))) {
                return Ok(stream);
            }
            let _ = stream
                .write_all(
                    b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                )
                .await;
        }
        Err(CoreError::new("media_auth", "媒体输入未通过授权。"))
    })
    .await
    .map_err(|_| CoreError::new("media_timeout", "播放器未及时读取媒体输入。"))?
}

enum Unit {
    Dimensions(u32, u32),
    Packet { flags: u64, bytes: Vec<u8> },
}

async fn read_unit(source: &mut TcpStream, video: bool) -> CoreResult<Unit> {
    let mut header = [0; 12];
    // A static source may wait indefinitely between complete packets; a
    // partially delivered header/payload must not hold a generation forever.
    source.read_exact(&mut header[..1]).await?;
    let complete = async {
        source.read_exact(&mut header[1..]).await?;
        let high = u32::from_be_bytes(header[..4].try_into().expect("fixed header"));
        if video && high & 0x8000_0000 != 0 {
            let width = u32::from_be_bytes(header[4..8].try_into().expect("fixed header"));
            let height = u32::from_be_bytes(header[8..].try_into().expect("fixed header"));
            if high & 0x7fff_fffe != 0
                || !(1..=16384).contains(&width)
                || !(1..=16384).contains(&height)
            {
                return Err(CoreError::new("media_protocol", "媒体画面尺寸无效。"));
            }
            return Ok(Unit::Dimensions(width, height));
        }
        let flags = u64::from_be_bytes(header[..8].try_into().expect("fixed header"));
        let length = u32::from_be_bytes(header[8..].try_into().expect("fixed header")) as usize;
        if length == 0
            || length > MAX_PACKET_BYTES
            || (flags & (1 << 62) != 0 && length > MAX_CONFIGURATION_BYTES)
            || (!video && (flags >> 61 != 0 || length > 4096 || !length.is_multiple_of(4)))
        {
            return Err(CoreError::new("media_protocol", "媒体数据包无效。"));
        }
        let mut bytes = vec![0; length];
        source.read_exact(&mut bytes).await?;
        Ok(Unit::Packet { flags, bytes })
    };
    tokio::time::timeout(Duration::from_secs(10), complete)
        .await
        .map_err(|_| CoreError::new("media_timeout", "媒体数据包未及时发送完整。"))?
}

async fn chunk(output: &mut OwnedWriteHalf, bytes: &[u8]) -> CoreResult<()> {
    // Bound delivery only while actual bytes are pending, never the idle
    // interval between frames. Fail the relay rather than dropping compressed
    // packets whose references the decoder may still require.
    tokio::time::timeout(Duration::from_secs(10), async {
        output
            .write_all(format!("{:x}\r\n", bytes.len()).as_bytes())
            .await?;
        output.write_all(bytes).await?;
        output.write_all(b"\r\n").await?;
        Ok::<_, CoreError>(())
    })
    .await
    .map_err(|_| CoreError::new("media_timeout", "播放器未及时读取媒体输出。"))?
}

async fn relay(
    mut endpoint: HttpEndpoint,
    port: u16,
    token: &str,
    video: Option<VideoCodec>,
    mut generation: u64,
    status: Arc<Mutex<Value>>,
) -> CoreResult<()> {
    let client = authenticated_client(&endpoint.listener, &endpoint.secret).await?;
    let (mut incoming, mut output) = client.into_split();
    // Authenticate and connect the single-use raw source exactly once. The
    // source outlives normal generation EOFs, but never a lost HTTP consumer.
    let setup = async {
        let mut source = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).await?;
        source.set_nodelay(true)?;
        source.write_all(format!("{token}\n").as_bytes()).await?;
        let ready = prepare_generation(&mut source, video, MediaFormat::default(), None).await?;
        Ok::<_, CoreError>((source, ready))
    };
    let (mut source, mut ready) = tokio::select! {
        result = consumer_closed(&mut incoming) => return result,
        result = setup => result?,
    };
    loop {
        {
            let mut state = status.lock().await;
            let id = state["relayId"]
                .as_str()
                .expect("owned relay identity")
                .to_owned();
            state["endpoint"] = endpoint.view(&id, generation, video, Some(&ready.format));
            state["generation"] = json!(generation);
        }
        let transition = tokio::select! {
            result = consumer_closed(&mut incoming) => return result,
            result = forward_generation(output, &mut source, ready, video, generation, &status) => result?,
        };
        drop(incoming);
        drop(endpoint);
        // Stop observing the old read-half before sending its intentional EOF;
        // the player may close its socket in response without closing source.
        tokio::time::timeout(Duration::from_secs(2), async {
            let mut old = transition.output;
            old.write_all(b"0\r\n\r\n").await?;
            old.shutdown().await
        })
        .await
        .map_err(|_| CoreError::new("media_timeout", "旧媒体输入未能及时结束。"))??;
        generation = generation.checked_add(1).ok_or_else(|| {
            CoreError::new(
                "media_generation_exhausted",
                "媒体代次已达上限，请结束此活动。",
            )
        })?;
        status.lock().await["status"] = json!("reconfiguring");
        ready = prepare_generation(
            &mut source,
            video,
            transition.format,
            Some(transition.group),
        )
        .await?;
        endpoint = HttpEndpoint::bind().await?;
        {
            let mut state = status.lock().await;
            let id = state["relayId"]
                .as_str()
                .expect("owned relay identity")
                .to_owned();
            state["endpoint"] = endpoint.view(&id, generation, video, Some(&ready.format));
            state["generation"] = json!(generation);
            state["status"] = json!("waiting");
        }
        // Only one pending keyframe is retained. Do not read or queue any more
        // raw packets while the next authenticated HTTP consumer is absent.
        let client = authenticated_client(&endpoint.listener, &endpoint.secret).await?;
        (incoming, output) = client.into_split();
    }
}

async fn consumer_closed(incoming: &mut OwnedReadHalf) -> CoreResult<()> {
    match incoming.read(&mut [0u8; 1]).await {
        Ok(0) | Err(_) => Ok(()),
        Ok(_) => Err(CoreError::new(
            "media_protocol",
            "媒体输入不接受额外的 HTTP 请求数据。",
        )),
    }
}

#[derive(Default)]
struct MediaFormat {
    dimensions: Option<(u32, u32)>,
    configuration: Vec<u8>,
}
struct PacketGroup {
    dimensions: Option<(u32, u32)>,
    configuration: Option<Vec<u8>>,
    packet: (u64, Vec<u8>),
    units: usize,
}
struct Ready {
    format: MediaFormat,
    packet: (u64, Vec<u8>),
    track: Track,
}
struct Transition {
    output: OwnedWriteHalf,
    format: MediaFormat,
    group: PacketGroup,
}

async fn packet_group(
    source: &mut TcpStream,
    video: bool,
    limit: usize,
) -> CoreResult<PacketGroup> {
    if limit == 0 {
        return Err(CoreError::new(
            "media_keyframe",
            "媒体输入在限额内未提供关键帧。",
        ));
    }
    let first = read_unit(source, video).await?;
    let gather = async {
        let mut dimensions = None;
        let mut configuration = None;
        let mut unit = first;
        for units in 1..=limit {
            match unit {
                Unit::Dimensions(width, height) => {
                    dimensions = Some((width, height));
                    // A reset may replace an encoder after CSD but before its
                    // first frame. Only config packets from the newest session
                    // belong to the frame we will eventually forward.
                    configuration = None;
                }
                Unit::Packet { flags, bytes } if flags & (1 << 62) != 0 => {
                    let configuration = configuration.get_or_insert_with(Vec::new);
                    if configuration.len() + bytes.len() > MAX_CONFIGURATION_BYTES {
                        return Err(CoreError::new("media_protocol", "媒体配置超过限额。"));
                    }
                    configuration.extend_from_slice(&bytes);
                }
                Unit::Packet { flags, bytes } => {
                    return Ok(PacketGroup {
                        dimensions,
                        configuration,
                        packet: (flags, bytes),
                        units,
                    });
                }
            }
            if units < limit {
                unit = read_unit(source, video).await?;
            } else {
                return Err(CoreError::new(
                    "media_protocol",
                    "媒体配置在限额内未跟随数据包。",
                ));
            }
        }
        unreachable!("nonzero bounded packet group")
    };
    // A complete session/configuration may be followed by a deliberate capture
    // pause. Only an incomplete individual unit has a delivery deadline.
    // Initial generation startup still has its own bounded prepare deadline.
    gather.await
}

async fn prepare_generation(
    source: &mut TcpStream,
    video: Option<VideoCodec>,
    mut format: MediaFormat,
    mut pending: Option<PacketGroup>,
) -> CoreResult<Ready> {
    let prepare = async {
        let mut remaining = 64usize;
        loop {
            let group = match pending.take() {
                Some(group) => group,
                None => packet_group(source, video.is_some(), remaining).await?,
            };
            remaining = remaining.checked_sub(group.units).ok_or_else(|| {
                CoreError::new("media_keyframe", "媒体输入在限额内未提供关键帧。")
            })?;
            if let Some(dimensions) = group.dimensions {
                format.dimensions = Some(dimensions);
            }
            if let Some(configuration) = group.configuration {
                format.configuration = configuration;
            }
            let track = if let Some(codec) = video {
                let (width, height) = format
                    .dimensions
                    .ok_or_else(|| CoreError::new("media_protocol", "媒体输入缺少画面尺寸。"))?;
                Track::Video(
                    VideoTrack::from_scrcpy(codec, width, height, &format.configuration)
                        .map_err(mux_error)?,
                )
            } else {
                Track::PcmS16le {
                    sample_rate: 48000,
                    channels: 2,
                }
            };
            if video.is_none() || group.packet.0 & (1 << 61) != 0 {
                return Ok(Ready {
                    format,
                    packet: group.packet,
                    track,
                });
            }
            if remaining == 0 {
                return Err(CoreError::new(
                    "media_keyframe",
                    "媒体输入在限额内未提供关键帧。",
                ));
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(10), prepare)
        .await
        .map_err(|_| CoreError::new("media_timeout", "媒体输入首个关键帧超时。"))?
}

async fn forward_generation(
    mut output: OwnedWriteHalf,
    source: &mut TcpStream,
    ready: Ready,
    video: Option<VideoCodec>,
    generation: u64,
    status: &Mutex<Value>,
) -> CoreResult<Transition> {
    let Ready {
        format,
        mut packet,
        track,
    } = ready;
    let mut mux = MatroskaMuxer::new(generation, track).map_err(mux_error)?;
    let tracing = status.lock().await["frameTrace"].is_array();
    tokio::time::timeout(
        Duration::from_secs(10),
        output.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: video/x-matroska\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"),
    )
    .await
    .map_err(|_| CoreError::new("media_timeout", "播放器未及时读取媒体输出。"))??;
    chunk(&mut output, &mux.take_header()).await?;
    loop {
        let (flags, bytes) = packet;
        let mux_started_us = tracing.then(super::monotonic_micros);
        let encoded = mux
            .push_packet(
                flags & ((1 << 61) - 1),
                flags & (1 << 61) != 0 || video.is_none(),
                &bytes,
            )
            .map_err(mux_error)?;
        let write_started_us = tracing.then(super::monotonic_micros);
        chunk(&mut output, &encoded).await?;
        let written_us = tracing.then(super::monotonic_micros);
        {
            let mut state = status.lock().await;
            state["status"] = json!("streaming");
            state["packets"] = json!(state["packets"].as_u64().unwrap_or(0) + 1);
            state["bytes"] = json!(state["bytes"].as_u64().unwrap_or(0) + encoded.len() as u64);
            if let Some(frames) = state.get_mut("frameTrace").and_then(Value::as_array_mut) {
                if frames.len() == 256 {
                    frames.remove(0);
                }
                frames.push(json!({
                    "generation": generation,
                    "ptsUs": (flags & ((1 << 61) - 1)) - mux.source_origin_us().unwrap(),
                    "muxStartedUs": mux_started_us,
                    "writeStartedUs": write_started_us,
                    "writtenUs": written_us,
                }));
            }
        }
        let group = packet_group(source, video.is_some(), 64).await?;
        if video.is_some()
            && (group
                .dimensions
                .is_some_and(|dimensions| Some(dimensions) != format.dimensions)
                || group
                    .configuration
                    .as_ref()
                    .is_some_and(|configuration| configuration != &format.configuration))
        {
            return Ok(Transition {
                output,
                format,
                group,
            });
        }
        packet = group.packet;
    }
}
