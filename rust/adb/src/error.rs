use std::io;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("ADB I/O: {0}")]
    Io(#[source] io::Error),
    /// 尚未取得 TCP 传输；保留其失败阶段，不能与认证中的 I/O 混淆。
    #[error("ADB TCP connection failed: {0}")]
    Connect(#[source] Box<Error>),
    /// 本机身份可能已提交给配对服务，失败不能证明对端没有保存信任。
    #[error("ADB pairing result is unknown: {0}")]
    PairingResultUnknown(#[source] Box<Error>),
    #[error("invalid ADB protocol: {0}")]
    Protocol(String),
    #[error("invalid argument: {0}")]
    InvalidArgument(&'static str),
    #[error("ADB operation timed out")]
    Timeout,
    #[error("ADB operation cancelled")]
    Cancelled,
    #[error("ADB connection or stream closed")]
    Closed,
    #[error("device authorization is required")]
    AuthorizationRequired,
    #[error("ADB service failed: {0}")]
    Remote(String),
    #[error("ADB {operation} failed with errno {errno}")]
    RemoteErrno { operation: &'static str, errno: u32 },
    #[error("ADB feature is unavailable: {0}")]
    Unsupported(&'static str),
    #[error("RSA identity: {0}")]
    Identity(String),
    #[error(transparent)]
    Usb(#[from] crate::usb::UsbError),
    #[error("output exceeds the configured limit")]
    OutputLimit,
    #[error("ADB compression: {0}")]
    Compression(String),
}

pub type Result<T> = std::result::Result<T, Error>;

// rustls 在握手及首个加密 ADB 读取期间将对端 alert 放入 io::Error 的 source；此处保留其语义，避免消费者依赖提供者的人类可读错误文本。
impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        if matches!(
            error
                .get_ref()
                .and_then(|source| source.downcast_ref::<rustls::Error>()),
            Some(rustls::Error::AlertReceived(
                rustls::AlertDescription::CertificateRequired
                    | rustls::AlertDescription::BadCertificate
                    | rustls::AlertDescription::CertificateUnknown
                    | rustls::AlertDescription::UnknownCA
                    | rustls::AlertDescription::AccessDenied
            ))
        ) {
            Self::AuthorizationRequired
        } else {
            Self::Io(error)
        }
    }
}

pub(crate) async fn bounded<T>(
    timeout: std::time::Duration,
    cancellation: &tokio_util::sync::CancellationToken,
    operation: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    // 调用方把本 future 嵌入自身状态机，shell 等操作还携带大缓冲；此处只装箱一次，使深层会话启动调用链适配默认测试线程栈。
    let operation = Box::pin(operation);
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(Error::Cancelled),
        result = tokio::time::timeout(timeout, operation) => result.map_err(|_| Error::Timeout)?,
    }
}
