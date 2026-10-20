use std::io;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("ADB I/O: {0}")]
    Io(#[source] io::Error),
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

// rustls exposes peer alerts as the source of an io::Error, both during the
// TLS handshake and on the first encrypted ADB read. Preserve their meaning
// here so consumers never depend on a provider's human-readable error text.
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
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(Error::Cancelled),
        result = tokio::time::timeout(timeout, operation) => result.map_err(|_| Error::Timeout)?,
    }
}
