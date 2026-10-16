use std::io;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("ADB I/O: {0}")]
    Io(#[from] io::Error),
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
