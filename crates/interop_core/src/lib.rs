//! Device, connection, session and transfer lifecycle owned independently of UI.
mod activities;
mod app_open;
mod audio;
mod bundled_servers;
mod clock_probe;
mod companion;
mod connection_health;
mod connections;
mod delivery;
mod device;
mod device_metadata;
pub mod documents;
mod encoder_catalog;
mod events;
mod file_search;
mod file_tree;
mod files;
mod gallery_index;
#[cfg(any(target_os = "linux", target_os = "android"))]
mod local_publication;
pub mod media;
mod media_cache;
mod model;
mod observation;
mod preferences;
mod remote_fs;
mod remote_helper;
mod remote_process;
pub mod resource;
mod runtime;
mod scrcpy;
pub mod sharing;
mod snapshot;
mod transfer_store;

pub use model::{CoreError, CoreResult};
pub use runtime::Runtime;
