//! 移动端直连 ADB 与桌面官方 adb-server 服务传输。传输是字节流，平台 USB 权限和端点 adapter 不归核心所有。
mod burst;
mod client;
mod compression;
mod error;
mod identity;
mod jdwp;
pub mod protocol;
mod read_trace;
mod reverse;
pub mod server;
mod services;
pub mod sync;
mod tcp;
pub mod usb;
pub mod wireless;

pub use client::{
    AdbReader, AdbStream, AdbWriter, Client, ConnectOptions, ConnectionSecurity, DeviceInfo,
    HandshakeKind, OpenProbeFacts, OpenProbeLayer, OpenProbeOutcome, OperationOptions, TlsPolicy,
    Transport,
};
pub use error::{Error, Result};
pub use identity::Identity;
pub use jdwp::JdwpTracker;
pub use read_trace::ReadTrace;
pub use reverse::{ReverseBinding, ReverseMapping, ReverseSocket};
pub use services::{
    RebootTarget, RemoteSocket, ShellEvent, ShellMode, ShellOutput, ShellReader, ShellSession,
    ShellWriter,
};
pub use tcp::{KeepaliveOptions, TcpOptions};
pub use tokio_util::sync::CancellationToken;
