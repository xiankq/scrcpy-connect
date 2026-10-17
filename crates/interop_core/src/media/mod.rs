//! Platform-independent, bounded packet-to-Matroska adapters.
//!
//! The caller owns transport, authentication, playback, and cancellation. A muxer has one
//! immutable track and generation; configuration changes require a new media resource.

mod codec;
pub mod http;
mod matroska;

pub use codec::{VideoCodec, VideoTrack};
pub use matroska::{MatroskaMuxer, Track};

/// Process-local monotonic media clock. Native decoder observers use the same
/// origin as relay diagnostics; remote media PTS are never treated as clocks.
pub fn monotonic_micros() -> u64 {
    static ORIGIN: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    ORIGIN
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_micros()
        .min(u64::MAX as u128) as u64
}

/// Maximum admitted compressed packet or PCM chunk, before copying it.
pub const MAX_PACKET_BYTES: usize = 16 * 1024 * 1024;
/// Codec configuration is independently bounded, including all parameter sets.
pub const MAX_CONFIGURATION_BYTES: usize = 256 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum MuxError {
    #[error("invalid media configuration: {0}")]
    Configuration(String),
    #[error("invalid media packet: {0}")]
    Packet(String),
    #[error("media timestamp predates this generation's origin")]
    TimestampBeforeOrigin,
    #[error("media input exceeds its byte limit")]
    SizeLimit,
    #[error("Matroska serialization failed: {0}")]
    Serialization(String),
}

pub type MuxResult<T> = Result<T, MuxError>;
