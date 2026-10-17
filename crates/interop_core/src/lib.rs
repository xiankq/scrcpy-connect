//! Device, connection, session and transfer lifecycle owned independently of UI.
mod app_open;
mod audio;
mod companion;
mod delivery;
mod device;
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
mod remote_helper;
pub mod resource;
mod runtime;
mod scrcpy;
pub mod sharing;
mod snapshot;

pub use model::{CoreError, CoreResult};
pub use runtime::Runtime;
