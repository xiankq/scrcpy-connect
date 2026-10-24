//! 分阶段启动：控制通道在编码首帧前可用，调用方可先提交 START_APP。
pub use crate::process_identity::ProcessLaunchState;
use crate::{
    Error, Result,
    config::{Options, VideoCodec},
    process::{ManagedProcess, managed_launch_command},
};
use interop_adb::{
    AdbStream, CancellationToken, Client, OperationOptions, RemoteSocket,
    sync::{Compression, RemotePath},
};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::Instant;

pub struct Session {
    client: Client,
    scid: u32,
    options: Options,
    cancellation: CancellationToken,
    startup_timeout: Duration,
    launch_state: ProcessLaunchState,
}

pub struct Launched {
    pub session: Session,
    pub process: ManagedProcess,
    pub pid: u32,
    pub started: u64,
}

pub struct Connected {
    pub video: AdbStream,
    pub control: Option<AdbStream>,
    pub device_name: String,
    pub codec: VideoCodec,
    pub initial: [u8; 12],
}

/// 通道按上游 video → audio → control 次序接纳；元数据不等于编码首帧就绪。
pub struct ConnectedChannels {
    pub video: Option<AdbStream>,
    pub audio: Option<AdbStream>,
    pub control: Option<AdbStream>,
    pub device_name: String,
    pub video_initial: Option<[u8; 12]>,
}

impl Session {
    /// 仅拥有传入 token 的捕获；Client 的传输所有权始终属于调用方。
    pub fn new(
        client: Client,
        scid: u32,
        options: Options,
        cancellation: CancellationToken,
    ) -> Result<Self> {
        options.validate()?;
        if scid > 0x7fff_ffff {
            return Err(Error::new("invalid_argument", "SCID 无效。"));
        }
        Ok(Self {
            client,
            scid,
            options,
            cancellation,
            startup_timeout: Duration::from_secs(30),
            launch_state: ProcessLaunchState::default(),
        })
    }

    pub fn with_startup_timeout(mut self, timeout: Duration) -> Result<Self> {
        if timeout.is_zero() {
            return Err(Error::new("invalid_argument", "启动期限必须大于零。"));
        }
        self.startup_timeout = timeout;
        Ok(self)
    }

    pub fn cancellation(&self) -> &CancellationToken {
        &self.cancellation
    }

    /// 在 launch 之前保存；启动取消或失败后仍由它核验同一次远端责任。
    pub fn launch_state(&self) -> ProcessLaunchState {
        self.launch_state.clone()
    }

    /// 上传使用捕获自己的 token。释放本地 sync 流后才能进行后续清理；flush 不代表远端退出确认。
    pub async fn upload(&self, jar: &str, server: &[u8]) -> Result<()> {
        tokio::time::timeout(self.startup_timeout, self.upload_inner(jar, server))
            .await
            .map_err(|_| Error::new("timeout", "服务上传未在启动期限内完成。"))?
    }
    async fn upload_inner(&self, jar: &str, server: &[u8]) -> Result<()> {
        let mut sync = self.client.sync(self.operation_options()).await?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .min(u32::MAX as u64) as u32;
        sync.push_compressed(
            &RemotePath::new(jar)?,
            &mut &server[..],
            0o644,
            now,
            server.len() as u64,
            upload_compression(&self.client.info().features),
        )
        .await?;
        Ok(())
    }

    pub fn command(&self, jar: &str) -> Result<String> {
        self.options.command(jar, self.scid)
    }

    /// prepared_command 必须实现 managed_launch_command 的 START/RUN/STOP/DONE 契约。
    /// 启动失败后，调用方仍须通过预先保存的 launch_state 排空与核验。
    pub async fn launch_prepared(self, prepared_command: &str) -> Result<Launched> {
        let timeout = self.startup_timeout;
        let cancellation = self.cancellation.clone();
        tokio::select! {
            biased;
            _=cancellation.cancelled()=>Err(interop_adb::Error::Cancelled.into()),
            result=tokio::time::timeout(timeout, self.launch_prepared_inner(prepared_command))=>result.map_err(|_| Error::new("timeout", "服务进程未在启动期限内报告身份。"))?,
        }
    }
    async fn launch_prepared_inner(self, prepared_command: &str) -> Result<Launched> {
        let process = self
            .client
            .exec(
                prepared_command,
                OperationOptions {
                    timeout: Duration::from_secs(365 * 24 * 60 * 60),
                    // 捕获取消改走监督 STOP，不能让 ADB 读取先丢弃远端退出回执。
                    ..Default::default()
                },
            )
            .await?;
        let process = ManagedProcess::start(process, self.launch_state.clone(), &self.cancellation);
        let (pid, started) = self.launch_state.running().await?;
        Ok(Launched {
            session: self,
            process,
            pid,
            started,
        })
    }

    /// 独立调用者的标准启动入口；应用专有的逻辑窗口和任务策略不进入本库。
    pub async fn launch(self, jar: &str, server: &[u8]) -> Result<Launched> {
        self.upload(jar, server).await?;
        let command = managed_launch_command(jar, &self.command(jar)?)?;
        self.launch_prepared(&command).await
    }

    /// 兼容仅视频的调用者；组合捕获使用 connect_channels，不能静默丢掉音频通道。
    pub async fn connect(&self) -> Result<Connected> {
        if !self.options.video || self.options.audio {
            return Err(Error::new(
                "invalid_argument",
                "组合通道应使用 connect_channels。",
            ));
        }
        let connected = self.connect_channels().await?;
        Ok(Connected {
            video: connected.video.expect("已启用视频"),
            control: connected.control,
            device_name: connected.device_name,
            codec: self.options.codec,
            initial: connected.video_initial.expect("已接收视频尺寸"),
        })
    }

    pub async fn connect_channels(&self) -> Result<ConnectedChannels> {
        tokio::time::timeout(self.startup_timeout, self.connect_channels_inner())
            .await
            .map_err(|_| Error::new("timeout", "服务通道未在启动期限内就绪。"))?
    }
    async fn connect_channels_inner(&self) -> Result<ConnectedChannels> {
        let socket = RemoteSocket::LocalAbstract(format!("scrcpy_{:08x}", self.scid));
        let deadline = Instant::now() + self.startup_timeout;
        let first = loop {
            if self.cancellation.is_cancelled() {
                return Err(interop_adb::Error::Cancelled.into());
            }
            match tokio::time::timeout(
                Duration::from_millis(600),
                self.client
                    .connect_socket(&socket, self.operation_options()),
            )
            .await
            {
                Ok(Ok(stream)) => break stream,
                Ok(Err(error)) if Instant::now() >= deadline => return Err(error.into()),
                Err(_) if Instant::now() >= deadline => {
                    return Err(Error::new("timeout", "服务套接字未就绪。"));
                }
                _ => tokio::select! {
                    _=self.cancellation.cancelled()=>return Err(interop_adb::Error::Cancelled.into()),
                    _=tokio::time::sleep(Duration::from_millis(40))=>{},
                },
            }
        };
        let mut first = Some(first);
        let mut video = None;
        let mut audio = None;
        let mut control = None;
        // 必须先接纳所有通道再读取任何元数据，上游在 accept 全部完成后才启动发送。
        for (enabled, target) in [
            (self.options.video, &mut video),
            (self.options.audio, &mut audio),
            (self.options.control, &mut control),
        ] {
            if enabled {
                *target = Some(match first.take() {
                    Some(stream) => stream,
                    None => {
                        self.client
                            .connect_socket(&socket, self.operation_options())
                            .await?
                    }
                });
            }
        }
        let primary = video
            .as_mut()
            .or(audio.as_mut())
            .or(control.as_mut())
            .expect("配置至少启用一个通道");
        let mut dummy = [0];
        primary.read_exact(&mut dummy).await?;
        if dummy != [0] {
            return Err(Error::new("stream_protocol", "服务连接标识无效。"));
        }
        let mut name = [0; 64];
        primary.read_exact(&mut name).await?;
        let video_initial = if let Some(video) = &mut video {
            let mut codec = [0; 4];
            video.read_exact(&mut codec).await?;
            if codec != self.options.codec.wire() {
                return Err(Error::new(
                    "video_codec",
                    "设备实际视频编码与请求格式不一致。",
                ));
            }
            let mut initial = [0; 12];
            video.read_exact(&mut initial).await?;
            crate::capture::session_dimensions(&initial)?
                .ok_or_else(|| Error::new("video_protocol", "视频流缺少会话尺寸。"))?;
            Some(initial)
        } else {
            None
        };
        if let Some(audio) = &mut audio {
            crate::audio::read_codec(audio).await?;
        }
        Ok(ConnectedChannels {
            video,
            audio,
            control,
            video_initial,
            device_name: String::from_utf8_lossy(
                &name[..name.iter().position(|b| *b == 0).unwrap_or(64)],
            )
            .into_owned(),
        })
    }

    fn operation_options(&self) -> OperationOptions {
        OperationOptions {
            timeout: Duration::from_secs(365 * 24 * 60 * 60),
            cancellation: self.cancellation.clone(),
        }
    }
}

pub fn upload_compression(features: &std::collections::HashSet<String>) -> Compression {
    if !features.contains("sendrecv_v2") {
        return Compression::None;
    }
    for (feature, compression) in [
        ("sendrecv_v2_zstd", Compression::Zstd),
        ("sendrecv_v2_lz4", Compression::Lz4),
        ("sendrecv_v2_brotli", Compression::Brotli),
    ] {
        if features.iter().any(|value| value == feature) {
            return compression;
        }
    }
    Compression::None
}
