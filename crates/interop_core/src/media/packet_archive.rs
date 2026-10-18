//! Opt-in, bounded capture of the exact Matroska prefix delivered over HTTP.

use crate::{CoreError, CoreResult};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use tokio::sync::{Semaphore, SemaphorePermit};

const MAX_BYTES: usize = 32 * 1024 * 1024;
const MAX_FRAMES: usize = 8192;
const MAX_READ_BYTES: usize = 65536;
static ARCHIVE_SLOT: Semaphore = Semaphore::const_new(1);

pub(crate) struct PacketArchive {
    // The slot stays occupied while sealed bytes remain available to readers.
    _permit: Option<SemaphorePermit<'static>>,
    generation: Option<u64>,
    bytes: Vec<u8>,
    frames: Vec<Value>,
    source_origin_us: Option<u64>,
    last_pts_us: Option<u64>,
    failure: Option<&'static str>,
    sealed: bool,
}

impl PacketArchive {
    pub(crate) fn try_new() -> CoreResult<Self> {
        let permit = ARCHIVE_SLOT.try_acquire().map_err(|_| {
            CoreError::new("resource_busy", "已有媒体诊断档案，请先关闭对应媒体输入。")
        })?;
        Ok(Self {
            _permit: Some(permit),
            generation: None,
            bytes: Vec::new(),
            frames: Vec::new(),
            source_origin_us: None,
            last_pts_us: None,
            failure: None,
            sealed: false,
        })
    }

    pub(crate) fn begin(&mut self, generation: u64, header: &[u8]) {
        if self.sealed || self.failure.is_some() {
            return;
        }
        if self.generation.is_some() {
            self.fail("诊断档案不能拼接多个媒体代次或重复媒体头。");
            return;
        }
        if header.is_empty() || header.len() > MAX_BYTES {
            self.fail("媒体诊断档案头为空或超过容量限制。");
            return;
        }
        self.generation = Some(generation);
        self.bytes.extend_from_slice(header);
    }

    pub(crate) fn append(&mut self, generation: u64, encoded: &[u8], frame: Value) {
        if self.sealed || self.failure.is_some() || self.generation.is_none() {
            return;
        }
        if self.generation != Some(generation) {
            self.fail("媒体诊断档案跨越了媒体代次。");
            return;
        }
        if encoded.is_empty()
            || encoded.len() > MAX_BYTES - self.bytes.len()
            || self.frames.len() == MAX_FRAMES
        {
            self.fail("媒体诊断档案为空或超过容量限制。");
            return;
        }
        let pts = frame["ptsUs"].as_u64();
        let source_pts = frame["sourcePtsUs"].as_u64();
        let origin = source_pts
            .zip(pts)
            .and_then(|(source, pts)| source.checked_sub(pts));
        if frame["generation"].as_u64() != Some(generation)
            || origin.is_none()
            || self
                .source_origin_us
                .is_some_and(|previous| Some(previous) != origin)
            || self
                .last_pts_us
                .is_some_and(|previous| pts.is_none_or(|pts| pts <= previous))
        {
            self.fail("媒体诊断档案的帧时间戳或媒体代次无效。");
            return;
        }
        self.source_origin_us = origin;
        self.last_pts_us = pts;
        self.bytes.extend_from_slice(encoded);
        self.frames.push(frame);
    }

    /// Freeze the complete delivered prefix without stopping playback.
    pub(crate) fn seal(&mut self) -> CoreResult<Value> {
        self.check_failure()?;
        if self.frames.is_empty() {
            return Err(CoreError::new(
                "media_archive_empty",
                "媒体诊断档案尚未包含完整帧。",
            ));
        }
        self.sealed = true;
        Ok(json!({
            "bytes": self.bytes.len(),
            "frames": self.frames,
            "generation": self.generation,
            "complete": true,
        }))
    }

    /// Reads do not consume data, so a failed caller can retry the same range.
    pub(crate) fn read(&self, offset: usize, limit: usize) -> CoreResult<Value> {
        self.check_failure()?;
        if !self.sealed {
            return Err(CoreError::new(
                "media_archive_unsealed",
                "请先封存媒体诊断档案。",
            ));
        }
        if !(1..=MAX_READ_BYTES).contains(&limit) || offset > self.bytes.len() {
            return Err(CoreError::new(
                "invalid_argument",
                "媒体诊断档案读取范围无效。",
            ));
        }
        let length = limit.min(self.bytes.len() - offset);
        let next = offset + length;
        Ok(json!({
            "offset": offset,
            "bytesBase64": STANDARD.encode(&self.bytes[offset..next]),
            "bytes": length,
            "nextOffset": next,
            "eof": next == self.bytes.len(),
        }))
    }

    fn check_failure(&self) -> CoreResult<()> {
        match self.failure {
            Some(reason) => Err(CoreError::new("media_archive_failed", reason)),
            None => Ok(()),
        }
    }

    fn fail(&mut self, reason: &'static str) {
        self.failure = Some(reason);
        self.bytes = Vec::new();
        self.frames = Vec::new();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(generation: u64, pts: u64) -> Value {
        json!({
            "generation": generation,
            "ptsUs": pts,
            "sourcePtsUs": pts + 1000,
            "muxStartedUs": 10,
            "writeStartedUs": 11,
            "writtenUs": 12,
        })
    }

    fn archive() -> PacketArchive {
        // Only tests bypass global ownership; production always acquires it.
        PacketArchive {
            _permit: None,
            generation: None,
            bytes: Vec::new(),
            frames: Vec::new(),
            source_origin_us: None,
            last_pts_us: None,
            failure: None,
            sealed: false,
        }
    }

    #[test]
    fn global_slot_is_exclusive_and_released_on_drop() {
        let mut first = PacketArchive::try_new().unwrap();
        assert_eq!(
            PacketArchive::try_new().err().unwrap().code,
            "resource_busy"
        );
        first.begin(7, b"header");
        first.append(7, b"frame", frame(7, 0));
        first.seal().unwrap();
        assert!(PacketArchive::try_new().is_err());
        drop(first);
        let mut failed = PacketArchive::try_new().unwrap();
        failed.begin(1, b"");
        assert!(PacketArchive::try_new().is_err());
        drop(failed);
        assert!(PacketArchive::try_new().is_ok());
    }

    #[test]
    fn seal_preserves_exact_prefix_metadata_and_is_idempotent() {
        let mut capture = archive();
        assert_eq!(capture.seal().unwrap_err().code, "media_archive_empty");
        assert_eq!(
            capture.read(0, 1).unwrap_err().code,
            "media_archive_unsealed"
        );
        capture.append(7, b"ignored", frame(7, 0));
        capture.begin(7, b"header");
        assert!(capture.seal().is_err());
        capture.append(7, b"one", frame(7, 0));
        capture.append(7, b"two", frame(7, 10));
        let metadata = capture.seal().unwrap();
        assert_eq!(
            metadata,
            json!({
                "bytes": 12, "frames": [frame(7, 0), frame(7, 10)],
                "generation": 7, "complete": true,
            })
        );
        capture.append(8, b"ignored", frame(8, 0));
        capture.begin(8, b"ignored");
        assert_eq!(capture.seal().unwrap(), metadata);
        assert_eq!(capture.bytes, b"headeronetwo");
    }

    #[test]
    fn reads_are_bounded_repeatable_and_allow_exact_eof() {
        let mut capture = archive();
        capture.begin(1, b"head");
        capture.append(1, b"body", frame(1, 0));
        capture.seal().unwrap();
        let first = capture.read(0, 3).unwrap();
        assert_eq!(
            first,
            json!({
                "offset": 0, "bytesBase64": STANDARD.encode(b"hea"),
                "bytes": 3, "nextOffset": 3, "eof": false,
            })
        );
        assert_eq!(capture.read(0, 3).unwrap(), first);
        let last = capture.read(3, MAX_READ_BYTES).unwrap();
        assert_eq!(
            STANDARD
                .decode(last["bytesBase64"].as_str().unwrap())
                .unwrap(),
            b"dbody"
        );
        assert_eq!(last["nextOffset"], 8);
        assert_eq!(last["eof"], true);
        assert_eq!(
            capture.read(8, 1).unwrap(),
            json!({
                "offset": 8, "bytesBase64": "", "bytes": 0,
                "nextOffset": 8, "eof": true,
            })
        );
        for (offset, limit) in [(9, 1), (0, 0), (0, MAX_READ_BYTES + 1), (usize::MAX, 1)] {
            assert_eq!(
                capture.read(offset, limit).unwrap_err().code,
                "invalid_argument"
            );
        }
    }

    #[test]
    fn byte_and_frame_limits_fail_closed_without_retaining_payloads() {
        let mut capture = archive();
        capture.begin(1, b"h");
        capture.append(1, &vec![0; MAX_BYTES - 1], frame(1, 0));
        assert_eq!(capture.bytes.len(), MAX_BYTES);
        capture.append(1, b"x", frame(1, 1));
        assert_failed_and_cleared(&mut capture);

        let mut capture = archive();
        capture.begin(1, b"h");
        for pts in 0..MAX_FRAMES {
            capture.append(1, b"x", frame(1, pts as u64));
        }
        assert_eq!(capture.frames.len(), MAX_FRAMES);
        capture.append(1, b"x", frame(1, MAX_FRAMES as u64));
        assert_failed_and_cleared(&mut capture);
    }

    #[test]
    fn empty_and_oversized_headers_and_empty_packets_are_rejected() {
        for header in [Vec::new(), vec![0; MAX_BYTES + 1]] {
            let mut capture = archive();
            capture.begin(1, &header);
            assert_failed_and_cleared(&mut capture);
        }
        let mut capture = archive();
        capture.begin(1, b"header");
        capture.append(1, b"", frame(1, 0));
        assert_failed_and_cleared(&mut capture);
    }

    fn assert_failed_and_cleared(capture: &mut PacketArchive) {
        assert!(capture.bytes.is_empty());
        assert!(capture.frames.is_empty());
        assert_eq!(capture.bytes.capacity(), 0);
        assert_eq!(capture.frames.capacity(), 0);
        assert_eq!(capture.seal().unwrap_err().code, "media_archive_failed");
        assert_eq!(capture.read(0, 1).unwrap_err().code, "media_archive_failed");
        capture.begin(1, b"ignored");
        capture.append(1, b"ignored", frame(1, 10));
        assert!(capture.bytes.is_empty());
    }

    #[test]
    fn generation_changes_and_duplicate_headers_invalidate_unsealed_capture() {
        for next_generation in [1, 2] {
            let mut capture = archive();
            capture.begin(1, b"header");
            capture.append(1, b"frame", frame(1, 0));
            capture.begin(next_generation, b"header");
            assert_failed_and_cleared(&mut capture);
        }
        let mut capture = archive();
        capture.begin(1, b"header");
        capture.append(2, b"frame", frame(2, 0));
        assert_failed_and_cleared(&mut capture);
    }

    #[test]
    fn frame_timestamps_must_be_unique_increasing_and_share_source_origin() {
        let invalid = [
            frame(1, 0), // duplicate
            json!({"generation": 1, "ptsUs": 0, "sourcePtsUs": 999}),
            json!({"generation": 1, "ptsUs": 1, "sourcePtsUs": 1002}),
            json!({"generation": 1, "ptsUs": 2, "sourcePtsUs": 1}),
            json!({"generation": 1, "sourcePtsUs": 1001}),
            json!({"generation": 1, "ptsUs": 1}),
            frame(2, 1),
        ];
        for invalid_frame in invalid {
            let mut capture = archive();
            capture.begin(1, b"header");
            capture.append(1, b"first", frame(1, 0));
            capture.append(1, b"invalid", invalid_frame);
            assert_failed_and_cleared(&mut capture);
        }
        let mut capture = archive();
        capture.begin(1, b"header");
        capture.append(1, b"first", frame(1, 10));
        capture.append(1, b"backwards", frame(1, 9));
        assert_failed_and_cleared(&mut capture);
    }
}
