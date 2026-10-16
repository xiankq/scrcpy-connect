//! Independent ADB host: no adb executable or localhost adb server is used.
//! Transports are byte streams; platform USB permission and endpoint adapters stay outside the core.
mod client;
mod compression;
mod error;
mod identity;
pub mod protocol;
mod services;
pub mod sync;
pub mod usb;
pub mod wireless;

pub use client::{AdbStream, Client, ConnectOptions, DeviceInfo, OperationOptions, Transport};
pub use error::{Error, Result};
pub use identity::Identity;
pub use services::{RebootTarget, RemoteSocket, ShellEvent, ShellMode, ShellOutput, ShellSession};
pub use tokio_util::sync::CancellationToken;
