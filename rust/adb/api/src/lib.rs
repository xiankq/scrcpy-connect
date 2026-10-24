//! ADB 类型化能力与宿主注入接缝；不包含任何导出桥接符号。
pub mod api;
mod consumer_activity;
mod file_helper;
mod file_metadata;
#[cfg(any(target_os = "linux", target_os = "android"))]
mod file_publication;
mod file_system;
mod identity;
