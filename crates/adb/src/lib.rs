//! Mobile direct ADB and official desktop adb-server service transports.
//! Transports are byte streams; platform USB permission and endpoint adapters stay outside the core.
mod burst;
mod client;
mod compression;
mod error;
mod identity;
mod processes;
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
    AdbReader, AdbStream, AdbWriter, Client, ConnectOptions, DeviceInfo, OperationOptions,
    TlsPolicy, Transport,
};
pub use error::{Error, Result};
pub use identity::Identity;
pub use processes::JdwpTracker;
pub use read_trace::ReadTrace;
pub use reverse::{ReverseBinding, ReverseMapping, ReverseSocket};
pub use services::{
    RebootTarget, RemoteSocket, ShellEvent, ShellMode, ShellOutput, ShellReader, ShellSession,
    ShellWriter,
};
pub use tcp::{KeepaliveOptions, TcpOptions};
pub use tokio_util::sync::CancellationToken;
