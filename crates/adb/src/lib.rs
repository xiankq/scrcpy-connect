//! Independent ADB host: no adb executable or localhost adb server is used.
//! Transports are byte streams; platform USB permission and endpoint adapters stay outside the core.
mod client;
mod compression;
mod error;
mod identity;
mod processes;
pub mod protocol;
mod read_trace;
mod reverse;
mod services;
pub mod sync;
mod tcp;
pub mod usb;
pub mod wireless;

pub use client::{
    AdbStream, Client, ConnectOptions, DeviceInfo, OperationOptions, TlsPolicy, Transport,
};
pub use error::{Error, Result};
pub use identity::Identity;
pub use processes::JdwpTracker;
pub use read_trace::ReadTrace;
pub use reverse::{ReverseBinding, ReverseMapping, ReverseSocket};
pub use services::{RebootTarget, RemoteSocket, ShellEvent, ShellMode, ShellOutput, ShellSession};
pub use tokio_util::sync::CancellationToken;
