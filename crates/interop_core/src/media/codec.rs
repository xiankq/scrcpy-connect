use super::{MAX_CONFIGURATION_BYTES, MAX_PACKET_BYTES, MuxError, MuxResult};
use bytes::Bytes;
use std::io::Cursor;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VideoCodec {
    H264,
    H265,
    Av1,
    Vp8,
    Vp9,
}

impl VideoCodec {
    pub fn from_name(name: &str) -> MuxResult<Self> {
        match name {
            "h264" => Ok(Self::H264),
            "h265" => Ok(Self::H265),
            "av1" => Ok(Self::Av1),
            "vp8" => Ok(Self::Vp8),
            "vp9" => Ok(Self::Vp9),
            _ => Err(configuration("unknown video codec")),
        }
    }
    pub fn matroska_id(self) -> &'static str {
        match self {
            Self::H264 => "V_MPEG4/ISO/AVC",
            Self::H265 => "V_MPEGH/ISO/HEVC",
            Self::Av1 => "V_AV1",
            Self::Vp8 => "V_VP8",
            Self::Vp9 => "V_VP9",
        }
    }
}

/// Immutable track configuration. New dimensions/configuration require a new generation.
#[derive(Clone, Debug)]
pub struct VideoTrack {
    codec: VideoCodec,
    width: u32,
    height: u32,
    codec_private: Vec<u8>,
    parameter_sets: Vec<Vec<u8>>,
}

impl VideoTrack {
    /// `configuration` contains scrcpy config packets (Annex B AVC/HEVC, low-overhead AV1 OBU).
    /// VP8 uses no CodecPrivate. VP9 accepts WebM feature metadata or no configuration.
    pub fn from_scrcpy(
        codec: VideoCodec,
        width: u32,
        height: u32,
        configuration_bytes: &[u8],
    ) -> MuxResult<Self> {
        if !(1..=16_384).contains(&width) || !(1..=16_384).contains(&height) {
            return Err(configuration("invalid video dimensions"));
        }
        if configuration_bytes.len() > MAX_CONFIGURATION_BYTES {
            return Err(MuxError::SizeLimit);
        }
        let codec_private = match codec {
            VideoCodec::H264 => avcc(configuration_bytes)?,
            VideoCodec::H265 => hvcc(configuration_bytes)?,
            VideoCodec::Av1 => av1c(configuration_bytes)?,
            VideoCodec::Vp8 => {
                if !configuration_bytes.is_empty() {
                    return Err(configuration("unexpected VP8/VP9 configuration"));
                }
                Vec::new()
            }
            VideoCodec::Vp9 => vp9_private(configuration_bytes)?,
        };
        let parameter_sets = if matches!(codec, VideoCodec::H264 | VideoCodec::H265) {
            annex_b(configuration_bytes)?
                .into_iter()
                .filter(|nal| is_parameter_set(codec, nal))
                .map(<[u8]>::to_vec)
                .collect()
        } else {
            Vec::new()
        };
        Ok(Self {
            codec,
            width,
            height,
            codec_private,
            parameter_sets,
        })
    }
    pub fn codec(&self) -> VideoCodec {
        self.codec
    }
    pub fn width(&self) -> u32 {
        self.width
    }
    pub fn height(&self) -> u32 {
        self.height
    }
    pub fn codec_private(&self) -> &[u8] {
        &self.codec_private
    }

    pub(crate) fn repack(&self, payload: &[u8], keyframe: bool) -> MuxResult<Vec<u8>> {
        match self.codec {
            VideoCodec::H264 | VideoCodec::H265 => {
                let nals = annex_b(payload).map_err(|e| MuxError::Packet(e.to_string()))?;
                let size = nals
                    .iter()
                    .try_fold(0usize, |total, nal| total.checked_add(nal.len() + 4))
                    .filter(|size| *size <= MAX_PACKET_BYTES)
                    .ok_or(MuxError::SizeLimit)?;
                let mut output = Vec::with_capacity(size);
                for nal in nals {
                    validate_nal(self.codec, nal).map_err(|e| MuxError::Packet(e.to_string()))?;
                    if is_parameter_set(self.codec, nal)
                        && !self.parameter_sets.iter().any(|set| set == nal)
                    {
                        return Err(configuration(
                            "parameter set changed; a new generation is required",
                        ));
                    }
                    output.extend_from_slice(&(nal.len() as u32).to_be_bytes());
                    output.extend_from_slice(nal);
                }
                Ok(output)
            }
            VideoCodec::Av1 => {
                let obus = av1_obus(payload)?;
                if keyframe
                    && !obus
                        .iter()
                        .any(|(header, _, _)| header.obu_type == scuffle_av1::ObuType::Frame)
                {
                    return Err(MuxError::Packet(
                        "AV1 SimpleBlock keyframe requires a Frame OBU".into(),
                    ));
                }
                let sequence = obus
                    .iter()
                    .find(|(header, _, _)| header.obu_type == scuffle_av1::ObuType::SequenceHeader);
                if let Some((header, payload, encoded)) = sequence {
                    let derived = av1c_obus(encoded)?;
                    let seq = scuffle_av1::seq::SequenceHeaderObu::parse(
                        *header,
                        &mut Cursor::new(*payload),
                    )
                    .map_err(codec_error)?;
                    if derived[..3] != self.codec_private[..3]
                        || seq.max_frame_width != u64::from(self.width)
                        || seq.max_frame_height != u64::from(self.height)
                        || (!self.codec_private[4..].is_empty()
                            && self.codec_private[4..] != **encoded)
                    {
                        return Err(configuration(
                            "AV1 sequence changed; a new generation is required",
                        ));
                    }
                }
                if keyframe && sequence.is_none() {
                    let sequence = &self.codec_private[4..];
                    if sequence.is_empty() {
                        return Err(MuxError::Packet(
                            "AV1 keyframe has no sequence header".into(),
                        ));
                    }
                    if sequence.len() + payload.len() > MAX_PACKET_BYTES {
                        return Err(MuxError::SizeLimit);
                    }
                    let mut output = Vec::with_capacity(sequence.len() + payload.len());
                    output.extend_from_slice(sequence);
                    output.extend_from_slice(payload);
                    Ok(output)
                } else {
                    Ok(payload.to_vec())
                }
            }
            VideoCodec::Vp8 | VideoCodec::Vp9 => Ok(payload.to_vec()),
        }
    }
}

fn configuration(message: impl Into<String>) -> MuxError {
    MuxError::Configuration(message.into())
}

fn vp9_private(data: &[u8]) -> MuxResult<Vec<u8>> {
    // WebM VP9 Codec Feature Metadata is a sequence of (id, length, value),
    // unlike ISO-BMFF vpcC. Preserve verified MediaCodec metadata unchanged.
    let mut at = 0;
    let mut seen = [false; 5];
    let mut output = Vec::new();
    while at < data.len() {
        if data.len() - at < 3 {
            return Err(configuration("truncated VP9 feature metadata"));
        }
        let id = usize::from(data[at]);
        let length = usize::from(data[at + 1]);
        if !(1..=4).contains(&id) || length != 1 || seen[id] {
            return Err(configuration("unsupported or repeated VP9 feature"));
        }
        let value = data[at + 2];
        // Some Android encoders report an unspecified level as zero. The WebM
        // mapping has no level-zero value; omit this optional feature instead.
        if id == 2 && value == 0 {
            seen[id] = true;
            at += 3;
            continue;
        }
        let valid = match id {
            1 => value <= 3,
            2 => matches!(
                value,
                10 | 11 | 20 | 21 | 30 | 31 | 40 | 41 | 50 | 51 | 52 | 60 | 61 | 62
            ),
            3 => matches!(value, 8 | 10 | 12),
            4 => value <= 3,
            _ => false,
        };
        if !valid {
            return Err(configuration("invalid VP9 feature value"));
        }
        output.extend_from_slice(&data[at..at + 3]);
        seen[id] = true;
        at += 3;
    }
    Ok(output)
}
fn codec_error(error: impl std::fmt::Display) -> MuxError {
    configuration(error.to_string())
}

/// Split only framing; syntax parsing and configuration serialization use Scuffle.
/// The bounded NAL count also prevents tiny start codes from amplifying allocations.
fn annex_b(data: &[u8]) -> MuxResult<Vec<&[u8]>> {
    fn start(data: &[u8], from: usize) -> Option<(usize, usize)> {
        (from..data.len().saturating_sub(2)).find_map(|i| {
            if data[i..].starts_with(&[0, 0, 0, 1]) {
                Some((i, 4))
            } else if data[i..].starts_with(&[0, 0, 1]) {
                Some((i, 3))
            } else {
                None
            }
        })
    }
    let (first, prefix) =
        start(data, 0).ok_or_else(|| configuration("missing Annex B start code"))?;
    if data[..first].iter().any(|byte| *byte != 0) {
        return Err(configuration("bytes before Annex B start code"));
    }
    let mut from = first + prefix;
    let mut nals = Vec::new();
    loop {
        let next = start(data, from);
        let mut end = next.map_or(data.len(), |(i, _)| i);
        while end > from && data[end - 1] == 0 {
            end -= 1;
        }
        if end == from {
            return Err(configuration("empty NAL unit"));
        }
        nals.push(&data[from..end]);
        if nals.len() > 1024 {
            return Err(MuxError::SizeLimit);
        }
        match next {
            Some((i, len)) => from = i + len,
            None => break,
        }
    }
    Ok(nals)
}

fn validate_nal(codec: VideoCodec, nal: &[u8]) -> MuxResult<()> {
    if nal[0] & 0x80 != 0
        || (codec == VideoCodec::H264 && (nal[0] & 31 == 0 || nal[0] & 31 >= 24))
        || (codec == VideoCodec::H265 && (nal.len() < 2 || nal[1] & 7 == 0))
    {
        return Err(configuration("invalid NAL header"));
    }
    Ok(())
}

fn is_parameter_set(codec: VideoCodec, nal: &[u8]) -> bool {
    match codec {
        VideoCodec::H264 => matches!(nal[0] & 31, 7 | 8),
        VideoCodec::H265 => matches!((nal[0] >> 1) & 63, 32..=34),
        _ => false,
    }
}

fn avcc(data: &[u8]) -> MuxResult<Vec<u8>> {
    use scuffle_h264::{AVCDecoderConfigurationRecord, AvccExtendedConfig, Sps};
    let nals = annex_b(data)?;
    for nal in &nals {
        validate_nal(VideoCodec::H264, nal)?;
    }
    let sps: Vec<_> = nals.iter().filter(|n| n[0] & 31 == 7).copied().collect();
    let pps: Vec<_> = nals.iter().filter(|n| n[0] & 31 == 8).copied().collect();
    // MediaCodec's ordinary one-active-SPS stream is supported. Multiple active
    // parameter-set IDs require an explicit selection rather than guessing a profile.
    if sps.len() != 1
        || pps.is_empty()
        || pps.len() > 255
        || sps.iter().chain(&pps).any(|n| n.len() > u16::MAX as usize)
    {
        return Err(configuration(
            "AVC requires one SPS and bounded PPS records",
        ));
    }
    let parsed = Sps::parse_with_emulation_prevention(sps[0]).map_err(codec_error)?;
    let extended_config = parsed.ext.map(|ext| AvccExtendedConfig {
        chroma_format_idc: ext.chroma_format_idc,
        bit_depth_luma_minus8: ext.bit_depth_luma_minus8,
        bit_depth_chroma_minus8: ext.bit_depth_chroma_minus8,
        sequence_parameter_set_ext: Vec::new(),
    });
    let record = AVCDecoderConfigurationRecord {
        configuration_version: 1,
        profile_indication: parsed.profile_idc,
        profile_compatibility: sps[0][2],
        level_indication: parsed.level_idc,
        length_size_minus_one: 3,
        sps: sps.into_iter().map(Bytes::copy_from_slice).collect(),
        pps: pps.into_iter().map(Bytes::copy_from_slice).collect(),
        extended_config,
    };
    let mut output = Vec::new();
    record.build(&mut output).map_err(codec_error)?;
    Ok(output)
}

fn hvcc(data: &[u8]) -> MuxResult<Vec<u8>> {
    use scuffle_h265::{
        ConstantFrameRate, HEVCDecoderConfigurationRecord, NALUnitType, NaluArray,
        NumTemporalLayers, ParallelismType, SpsNALUnit,
    };
    let nals = annex_b(data)?;
    for nal in &nals {
        validate_nal(VideoCodec::H265, nal)?;
    }
    let sets: Vec<Vec<&[u8]>> = [32, 33, 34]
        .into_iter()
        .map(|kind| {
            nals.iter()
                .filter(|n| (n[0] >> 1) & 63 == kind)
                .copied()
                .collect()
        })
        .collect();
    if sets.iter().any(|set| {
        set.is_empty() || set.len() > 255 || set.iter().any(|n| n.len() > u16::MAX as usize)
    }) || sets[1].len() != 1
    {
        return Err(configuration("HEVC requires VPS, one SPS, and PPS"));
    }
    let sps = SpsNALUnit::parse(sets[1][0]).map_err(codec_error)?.rbsp;
    let profile = sps.profile_tier_level.general_profile;
    // Preserve the six general_constraint_indicator_flags bytes. This is framing
    // extraction after the library validates SPS syntax, not a second SPS parser.
    let mut rbsp = Vec::new();
    let mut zeros = 0;
    for &byte in &sets[1][0][2..] {
        if zeros >= 2 && byte == 3 {
            zeros = 0;
            continue;
        }
        rbsp.push(byte);
        zeros = if byte == 0 { zeros + 1 } else { 0 };
    }
    if rbsp.len() < 13 {
        return Err(configuration("truncated HEVC profile"));
    }
    let constraints = rbsp[6..12]
        .iter()
        .fold(0u64, |value, byte| (value << 8) | u64::from(*byte));
    let arrays = sets
        .into_iter()
        .zip([
            NALUnitType::VpsNut,
            NALUnitType::SpsNut,
            NALUnitType::PpsNut,
        ])
        .map(|(set, kind)| NaluArray {
            array_completeness: false,
            nal_unit_type: kind,
            nalus: set.into_iter().map(Bytes::copy_from_slice).collect(),
        })
        .collect();
    let record = HEVCDecoderConfigurationRecord {
        general_profile_space: profile.profile_space,
        general_tier_flag: profile.tier_flag,
        general_profile_idc: profile.profile_idc,
        general_profile_compatibility_flags: profile.profile_compatibility_flag,
        general_constraint_indicator_flags: constraints,
        general_level_idc: profile
            .level_idc
            .ok_or_else(|| configuration("missing HEVC level"))?,
        min_spatial_segmentation_idc: 0,
        parallelism_type: ParallelismType::MixedOrUnknown,
        chroma_format_idc: sps.chroma_format_idc,
        bit_depth_luma_minus8: sps.bit_depth_luma_minus8,
        bit_depth_chroma_minus8: sps.bit_depth_chroma_minus8,
        avg_frame_rate: 0,
        constant_frame_rate: ConstantFrameRate::Unknown,
        num_temporal_layers: NumTemporalLayers::from(sps.sps_max_sub_layers_minus1 + 1),
        temporal_id_nested: sps.sps_temporal_id_nesting_flag,
        length_size_minus_one: 3,
        arrays,
    };
    let mut output = Vec::new();
    record.mux(&mut output).map_err(codec_error)?;
    Ok(output)
}

type EncodedObu<'a> = (scuffle_av1::ObuHeader, &'a [u8], &'a [u8]);

fn av1_obus(data: &[u8]) -> MuxResult<Vec<EncodedObu<'_>>> {
    let mut cursor = Cursor::new(data);
    let mut obus = Vec::new();
    while (cursor.position() as usize) < data.len() {
        let start = cursor.position() as usize;
        let header = scuffle_av1::ObuHeader::parse(&mut cursor).map_err(codec_error)?;
        let from = cursor.position() as usize;
        let len = header.size.unwrap_or((data.len() - from) as u64);
        let end = from
            .checked_add(usize::try_from(len).map_err(codec_error)?)
            .filter(|end| *end <= data.len())
            .ok_or_else(|| configuration("truncated AV1 OBU"))?;
        obus.push((header, &data[from..end], &data[start..end]));
        if obus.len() > 1024 {
            return Err(MuxError::SizeLimit);
        }
        cursor.set_position(end as u64);
    }
    Ok(obus)
}

fn av1c(data: &[u8]) -> MuxResult<Vec<u8>> {
    use scuffle_av1::AV1CodecConfigurationRecord;
    if data.first() == Some(&0x81) {
        let record =
            AV1CodecConfigurationRecord::demux(&mut Cursor::new(Bytes::copy_from_slice(data)))
                .map_err(codec_error)?;
        // Android MediaCodec may already expose av1C, rather than bare sequence OBU.
        // Validate its sequence instead of treating the marker as an OBU header.
        if !record.config_obu.is_empty() {
            let derived = av1c_obus(&record.config_obu)?;
            if derived[..3] != data[..3] {
                return Err(configuration(
                    "AV1 configuration disagrees with its sequence header",
                ));
            }
        }
        return Ok(data.to_vec());
    }
    av1c_obus(data)
}

fn av1c_obus(data: &[u8]) -> MuxResult<Vec<u8>> {
    use scuffle_av1::{AV1CodecConfigurationRecord, ObuType, seq::SequenceHeaderObu};
    let obus = av1_obus(data)?;
    let sequences: Vec<_> = obus
        .iter()
        .filter(|(header, _, _)| header.obu_type == ObuType::SequenceHeader)
        .collect();
    if sequences.len() != 1 || sequences[0].0.size.is_none() {
        return Err(configuration("AV1 requires one sized sequence-header OBU"));
    }
    let (header, payload, encoded) = sequences[0];
    let seq = SequenceHeaderObu::parse(*header, &mut Cursor::new(*payload)).map_err(codec_error)?;
    let op = seq
        .operating_points
        .first()
        .ok_or_else(|| configuration("missing AV1 operating point"))?;
    let color = seq.color_config;
    let record = AV1CodecConfigurationRecord {
        seq_profile: seq.seq_profile,
        seq_level_idx_0: op.seq_level_idx,
        seq_tier_0: op.seq_tier,
        high_bitdepth: color.bit_depth > 8,
        twelve_bit: color.bit_depth == 12,
        monochrome: color.mono_chrome,
        chroma_subsampling_x: color.subsampling_x,
        chroma_subsampling_y: color.subsampling_y,
        chroma_sample_position: color.chroma_sample_position,
        hdr_wcg_idc: 0,
        initial_presentation_delay_minus_one: None,
        config_obu: Bytes::copy_from_slice(encoded),
    };
    let mut output = Vec::new();
    record.mux(&mut output).map_err(codec_error)?;
    Ok(output)
}
