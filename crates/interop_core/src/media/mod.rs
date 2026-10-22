//! Bounded process-local scrcpy packet delivery to native decoders.

pub mod native;

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
