use crate::{controls, ff, mc_set_paused, mc_set_volume, string};
use flutter_rust_bridge::frb;

pub struct MediaStatus {
    pub width: u32,
    pub height: u32,
    pub frame_count: u64,
    pub presented_frame_count: u64,
    pub presented_sequence: u64,
    pub presentation_path: String,
    pub presentation_error: String,
    pub audio_played_frames: u64,
    pub audio_queued_frames: u64,
    pub audio_dropped_frames: u64,
    pub bytes_written: u64,
    pub position_ms: i64,
    pub hardware_accelerated: bool,
    pub backend_hardware_frames: bool,
    pub hardware_verification: i32,
    pub native_ready: bool,
    pub first_frame: bool,
    pub paused: bool,
    pub ended: bool,
    pub error_code: i32,
    pub decoder_name: String,
    pub error: String,
}

#[frb(sync)]
pub fn media_status(control_id: u64) -> Result<MediaStatus, String> {
    controls::with_decoder(control_id, |value| {
        let status = value.shared.lock().unwrap().status;
        MediaStatus {
            width: status.width,
            height: status.height,
            frame_count: status.frame_count,
            presented_frame_count: status.presented_frame_count,
            presented_sequence: status.presented_sequence,
            presentation_path: unsafe { string(status.presentation_path.as_ptr()) },
            presentation_error: unsafe { string(status.presentation_error.as_ptr()) },
            audio_played_frames: status.audio_played_frames,
            audio_queued_frames: status.audio_queued_frames,
            audio_dropped_frames: status.audio_dropped_frames,
            bytes_written: status.bytes_written,
            position_ms: status.position_us / 1000,
            hardware_accelerated: status.hardware_accelerated != 0,
            backend_hardware_frames: status.backend_hardware_frames != 0,
            hardware_verification: status.hardware_verification,
            native_ready: status.native_ready != 0,
            first_frame: status.frame_count != 0,
            paused: status.paused != 0,
            ended: status.ended != 0,
            error_code: status.error_code,
            decoder_name: unsafe { string(status.decoder_name.as_ptr()) },
            error: unsafe { string(status.error.as_ptr()) },
        }
    })
}

#[frb(sync)]
pub fn media_set_paused(control_id: u64, paused: bool) -> Result<(), String> {
    controls::with_decoder(control_id, |value| unsafe {
        mc_set_paused(value as *const _ as *mut ff::mc_decoder, paused.into());
    })
}

#[frb(sync)]
pub fn media_set_volume(control_id: u64, volume: f64) -> Result<(), String> {
    if !volume.is_finite() || !(0.0..=1.0).contains(&volume) {
        return Err("media volume must be finite and between 0 and 1".into());
    }
    controls::with_decoder(control_id, |value| unsafe {
        mc_set_volume(value as *const _ as *mut ff::mc_decoder, volume);
    })
}
