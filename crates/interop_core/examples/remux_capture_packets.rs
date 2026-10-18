//! Offline lab adapter: remux a captured scrcpy packet ledger through the
//! production muxer. Does not connect to or change an Android device.
use interop_core::media::{MatroskaMuxer, Track, VideoCodec, VideoTrack};
use serde::Deserialize;
use std::{collections::HashSet, fs, io::Write, path::PathBuf};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Capture {
    width: u32,
    height: u32,
    packets: Vec<Packet>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Packet {
    offset: usize,
    size: usize,
    config: bool,
    keyframe: bool,
    source_pts_us: u64,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let directory = PathBuf::from(
        std::env::args_os()
            .nth(1)
            .ok_or("capture directory required")?,
    );
    let capture: Capture = serde_json::from_slice(&fs::read(directory.join("packets.json"))?)?;
    let path = directory.join("capture.h264");
    if fs::metadata(&path)?.len() > 128 * 1024 * 1024 {
        return Err("capture exceeds lab size bound".into());
    }
    let bytes = fs::read(path)?;
    let mut config = Vec::new();
    let mut mux = None;
    let mut expected = 0;
    let mut seen = HashSet::new();
    // Refuse replacing an earlier observation.
    let mut output = fs::File::create_new(directory.join("capture.mkv"))?;
    for packet in capture.packets {
        if packet.offset != expected || packet.size == 0 || packet.size > 16 * 1024 * 1024 {
            return Err("non-contiguous or invalid packet ledger".into());
        }
        let end = expected.checked_add(packet.size).ok_or("packet overflow")?;
        let data = bytes.get(expected..end).ok_or("packet outside capture")?;
        expected = end;
        if packet.config {
            if mux.is_some() {
                return Err("midstream configuration requires a new capture".into());
            }
            config.extend_from_slice(data);
            continue;
        }
        if !seen.insert(packet.source_pts_us) {
            return Err("duplicate media PTS".into());
        }
        if mux.is_none() {
            let track =
                VideoTrack::from_scrcpy(VideoCodec::H264, capture.width, capture.height, &config)?;
            let mut created = MatroskaMuxer::new(1, Track::Video(track))?;
            output.write_all(&created.take_header())?;
            mux = Some(created);
        }
        output.write_all(&mux.as_mut().unwrap().push_packet(
            packet.source_pts_us,
            packet.keyframe,
            data,
        )?)?;
    }
    if expected != bytes.len() || seen.is_empty() {
        return Err("unaccounted bytes or no media".into());
    }
    output.flush()?;
    println!("Remuxed {} exact-PTS packets", seen.len());
    Ok(())
}
