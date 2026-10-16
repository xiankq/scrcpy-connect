use super::{MAX_PACKET_BYTES, MuxError, MuxResult, VideoTrack};
use webm_iterable::{
    WebmWriter, WriteOptions,
    matroska_spec::{Master, MatroskaSpec as Tag},
};

/// One endpoint owns one video control session or one deduplicated device audio source.
#[derive(Clone, Debug)]
pub enum Track {
    Video(VideoTrack),
    PcmS16le { sample_rate: u32, channels: u16 },
}

/// Forward-only Matroska, with microsecond timestamps and no retained packet queue.
pub struct MatroskaMuxer {
    generation: u64,
    track: Track,
    writer: WebmWriter<Vec<u8>>,
    header: Vec<u8>,
    source_origin_us: Option<u64>,
}

impl MatroskaMuxer {
    pub fn new(generation: u64, track: Track) -> MuxResult<Self> {
        let mut entry = vec![Tag::TrackNumber(1), Tag::TrackUID(1), Tag::FlagLacing(0)];
        match &track {
            Track::Video(video) => {
                entry.extend([
                    Tag::TrackType(1),
                    Tag::CodecID(video.codec().matroska_id().into()),
                    Tag::Video(Master::Full(vec![
                        Tag::PixelWidth(video.width().into()),
                        Tag::PixelHeight(video.height().into()),
                    ])),
                ]);
                if !video.codec_private().is_empty() {
                    entry.push(Tag::CodecPrivate(video.codec_private().to_vec()));
                }
            }
            Track::PcmS16le {
                sample_rate,
                channels,
            } => {
                if !(8_000..=192_000).contains(sample_rate) || !(1..=8).contains(channels) {
                    return Err(MuxError::Configuration(
                        "invalid PCM sample rate/channel count".into(),
                    ));
                }
                entry.extend([
                    Tag::TrackType(2),
                    Tag::CodecID("A_PCM/INT/LIT".into()),
                    Tag::Audio(Master::Full(vec![
                        Tag::SamplingFrequency(f64::from(*sample_rate)),
                        Tag::Channels(u64::from(*channels)),
                        Tag::BitDepth(16),
                    ])),
                ]);
            }
        }
        let mut mux = Self {
            generation,
            track,
            writer: WebmWriter::new(Vec::new()),
            header: Vec::new(),
            source_origin_us: None,
        };
        mux.write(&Tag::Ebml(Master::Full(vec![
            Tag::EbmlVersion(1),
            Tag::EbmlReadVersion(1),
            Tag::EbmlMaxIdLength(4),
            Tag::EbmlMaxSizeLength(8),
            Tag::DocType("matroska".into()),
            Tag::DocTypeVersion(4),
            Tag::DocTypeReadVersion(2),
        ])))?;
        mux.writer
            .write_advanced(
                &Tag::Segment(Master::Start),
                WriteOptions::is_unknown_sized_element(),
            )
            .map_err(|e| MuxError::Serialization(e.to_string()))?;
        mux.write(&Tag::Info(Master::Full(vec![
            // 1000ns ticks preserve scrcpy's integer microseconds exactly.
            Tag::TimestampScale(1_000),
            Tag::MuxingApp("scrcpy-connect".into()),
            Tag::WritingApp("scrcpy-connect".into()),
        ])))?;
        mux.write(&Tag::Tracks(Master::Full(vec![Tag::TrackEntry(
            Master::Full(entry),
        )])))?;
        mux.header = std::mem::take(mux.writer.get_mut());
        Ok(mux)
    }

    /// Consume the bounded initialization bytes once, before forwarding packet chunks.
    pub fn take_header(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.header)
    }
    pub fn generation(&self) -> u64 {
        self.generation
    }
    pub fn source_origin_us(&self) -> Option<u64> {
        self.source_origin_us
    }
    /// Output retained between calls; excludes the immutable bounded codec configuration.
    pub fn buffered_output_bytes(&self) -> usize {
        self.header.len() + self.writer.get_ref().len()
    }

    /// The payload is one complete access unit, never the scrcpy 12-byte framing header.
    /// Codec configuration packets belong in `VideoTrack::from_scrcpy`, not here.
    pub fn push_packet(
        &mut self,
        pts_us: u64,
        keyframe: bool,
        payload: &[u8],
    ) -> MuxResult<Vec<u8>> {
        if payload.is_empty() {
            return Err(MuxError::Packet("empty access unit".into()));
        }
        if payload.len() > MAX_PACKET_BYTES {
            return Err(MuxError::SizeLimit);
        }
        let origin = self.source_origin_us.unwrap_or(pts_us);
        let relative = pts_us
            .checked_sub(origin)
            .ok_or(MuxError::TimestampBeforeOrigin)?;
        let (data, keyframe) = match &self.track {
            Track::Video(video) => {
                if self.source_origin_us.is_none() && !keyframe {
                    return Err(MuxError::Packet(
                        "video stream must start at a keyframe".into(),
                    ));
                }
                (video.repack(payload, keyframe)?, keyframe)
            }
            Track::PcmS16le { channels, .. } => {
                if !payload.len().is_multiple_of(usize::from(*channels) * 2) {
                    return Err(MuxError::Packet(
                        "PCM chunk ends inside a sample frame".into(),
                    ));
                }
                (payload.to_vec(), true)
            }
        };
        // A cluster per packet has bounded overhead, does not buffer a duration, and
        // prevents i16 relative-block timestamp overflow even after long static gaps.
        self.writer
            .write_advanced(
                &Tag::Cluster(Master::Start),
                WriteOptions::is_unknown_sized_element(),
            )
            .map_err(|e| MuxError::Serialization(e.to_string()))?;
        self.write(&Tag::Timestamp(relative))?;
        let mut block = Vec::with_capacity(data.len() + 4);
        block.extend_from_slice(&[0x81, 0, 0, if keyframe { 0x80 } else { 0 }]);
        block.extend_from_slice(&data);
        self.write(&Tag::SimpleBlock(block))?;
        self.write(&Tag::Cluster(Master::End))?;
        self.source_origin_us = Some(origin);
        Ok(std::mem::take(self.writer.get_mut()))
    }

    fn write(&mut self, tag: &Tag) -> MuxResult<()> {
        self.writer
            .write(tag)
            .map_err(|e| MuxError::Serialization(e.to_string()))
    }
}
