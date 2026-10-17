//! Device, connection, session and transfer lifecycle owned independently of UI.
mod audio;
mod companion;
mod device;
pub mod documents;
mod events;
mod file_tree;
mod files;
pub mod media;
mod model;
mod preferences;
mod remote_helper;
pub mod resource;
mod runtime;
mod scrcpy;
pub mod sharing;
mod snapshot;

pub use model::{CoreError, CoreResult};
pub use runtime::Runtime;
