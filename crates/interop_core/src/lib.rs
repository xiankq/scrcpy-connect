//! Device, connection, session and transfer lifecycle owned independently of UI.
mod audio;
mod companion;
mod device;
mod file_tree;
mod files;
mod model;
mod preferences;
mod remote_helper;
pub mod resource;
mod runtime;
mod scrcpy;

pub use model::{CoreError, CoreResult};
pub use runtime::Runtime;
