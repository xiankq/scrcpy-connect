//! 有界原生媒体生产者；只传递进程内 ABI 端点，不经 Dart 复制压缩数据。
pub mod native;
pub mod video;
pub const MAX_PACKET_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_CONFIGURATION_BYTES: usize = 256 * 1024;
pub type MediaResult<T> = std::result::Result<T, MediaError>;
#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub struct MediaError {
    pub code: &'static str,
    pub message: String,
}
impl MediaError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}
impl From<crate::Error> for MediaError {
    fn from(error: crate::Error) -> Self {
        match error {
            crate::Error::Failure { code, message } => Self { code, message },
            crate::Error::Adb(error) => Self::new("adb_error", error.to_string()),
        }
    }
}
