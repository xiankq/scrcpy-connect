//! 通过调用方拥有的 ADB 连接运行 scrcpy；不登记设备、窗口或应用偏好。
pub mod audio;
pub mod capture;
pub mod config;
pub mod control;
pub mod media;
pub mod process;
pub mod process_identity;
pub mod session;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Adb(#[from] interop_adb::Error),
    #[error("{message}")]
    Failure { code: &'static str, message: String },
}

impl Error {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self::Failure {
            code,
            message: message.into(),
        }
    }
}

/// 仅引用一个 shell 参数；可信命令源码须由调用方自行构造。
pub fn shell_quote(value: &str) -> Result<String> {
    if value.contains('\0') {
        return Err(Error::new("invalid_argument", "内容不能包含空字符。"));
    }
    Ok(format!("'{}'", value.replace('\'', "'\"'\"'")))
}
