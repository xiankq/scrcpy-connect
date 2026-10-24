//! 精确子进程和专用启动回执；不解析 ADB 命令或身份目录。
use std::{collections::HashMap, io, pin::Pin};
use tokio::io::{AsyncRead, AsyncWrite};
#[cfg(unix)]
#[path = "server_process/unix.rs"]
mod platform;
#[cfg(windows)]
#[path = "server_process/windows.rs"]
mod platform;
#[cfg(not(any(unix, windows)))]
compile_error!("当前宿主没有官方 ADB 子进程实现");
pub(super) use platform::Process;
pub(super) type Reader = Pin<Box<dyn AsyncRead + Send>>;
pub(super) type Writer = Pin<Box<dyn AsyncWrite + Send>>;
pub(super) struct Spawned {
    pub process: Process,
    pub input: Writer,
    pub output: Reader,
    pub error: Reader,
    pub ack: Option<Reader>,
}
pub(super) async fn spawn(
    executable: &str,
    arguments: &[String],
    environment: &HashMap<String, String>,
    ack: bool,
) -> io::Result<Spawned> {
    platform::spawn(executable, arguments, environment, ack).await
}
