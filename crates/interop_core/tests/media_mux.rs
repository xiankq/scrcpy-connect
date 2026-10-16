use interop_core::media::{
    MAX_PACKET_BYTES, MatroskaMuxer, MuxError, Track, VideoCodec, VideoTrack,
};
use webm_iterable::{WebmIterator, matroska_spec::MatroskaSpec as Tag};

fn pcm() -> MatroskaMuxer {
    MatroskaMuxer::new(
        7,
        Track::PcmS16le {
            sample_rate: 48_000,
            channels: 2,
        },
    )
    .unwrap()
}

#[test]
fn preserves_irregular_microseconds_and_gaps_without_i16_overflow() {
    let mut mux = pcm();
    let mut stream = mux.take_header();
    assert!(mux.take_header().is_empty());
    for pts in [9_000_000, 9_123_457, 99_000_000_000] {
        stream.extend(mux.push_packet(pts, true, &[1, 2, 3, 4]).unwrap());
    }
    let tags: Vec<_> = WebmIterator::new(stream.as_slice(), &[])
        .collect::<Result<_, _>>()
        .unwrap();
    assert!(tags.contains(&Tag::TimestampScale(1_000)));
    let times: Vec<_> = tags
        .iter()
        .filter_map(|tag| {
            if let Tag::Timestamp(pts) = tag {
                Some(*pts)
            } else {
                None
            }
        })
        .collect();
    assert_eq!(times, [0, 123_457, 98_991_000_000]);
    let blocks: Vec<_> = tags
        .iter()
        .filter_map(|tag| {
            if let Tag::SimpleBlock(bytes) = tag {
                Some(bytes)
            } else {
                None
            }
        })
        .collect();
    assert_eq!(blocks.len(), 3);
    assert!(
        blocks
            .iter()
            .all(|block| block.as_slice() == [0x81, 0, 0, 0x80, 1, 2, 3, 4])
    );
    assert_eq!(mux.source_origin_us(), Some(9_000_000));
    assert_eq!(mux.generation(), 7);
}

#[test]
fn invalid_packets_do_not_advance_origin_or_poison_the_stream() {
    let mut mux = pcm();
    assert!(mux.push_packet(10, true, &[]).is_err());
    assert!(mux.push_packet(10, true, &[0; 3]).is_err());
    assert!(matches!(
        mux.push_packet(10, true, &vec![0; MAX_PACKET_BYTES + 1]),
        Err(MuxError::SizeLimit)
    ));
    assert_eq!(mux.source_origin_us(), None);
    mux.push_packet(20, true, &[0; 4]).unwrap();
    assert!(matches!(
        mux.push_packet(19, true, &[0; 4]),
        Err(MuxError::TimestampBeforeOrigin)
    ));
    assert!(!mux.push_packet(21, true, &[0; 4]).unwrap().is_empty());
    assert!(
        MatroskaMuxer::new(
            0,
            Track::PcmS16le {
                sample_rate: 0,
                channels: 2
            }
        )
        .is_err()
    );
}

#[test]
fn bounded_output_is_drained_for_long_running_streams() {
    let mut mux = pcm();
    mux.take_header();
    let packet = [42; 4096];
    for index in 0..10_000 {
        let chunk = mux.push_packet(index * 21_333, true, &packet).unwrap();
        assert!(chunk.len() < packet.len() + 100);
        assert_eq!(mux.buffered_output_bytes(), 0);
    }
}

#[test]
fn rejects_bad_configuration_instead_of_guessing_codec_private() {
    for codec in [VideoCodec::H264, VideoCodec::H265, VideoCodec::Av1] {
        assert!(VideoTrack::from_scrcpy(codec, 640, 480, &[]).is_err());
        assert!(VideoTrack::from_scrcpy(codec, 640, 480, &[0, 0, 1, 0xff]).is_err());
    }
    assert!(VideoCodec::from_name("made-up").is_err());
    assert!(VideoTrack::from_scrcpy(VideoCodec::Vp8, 0, 480, &[]).is_err());
    assert!(VideoTrack::from_scrcpy(VideoCodec::Vp9, 640, 480, &[1]).is_err());
    assert!(VideoTrack::from_scrcpy(VideoCodec::Vp9, 640, 480, &[]).is_ok());
}

#[test]
fn accepts_android_av1c_and_vp9_metadata_without_inventing_unknown_level() {
    let av1 = VideoTrack::from_scrcpy(VideoCodec::Av1, 288, 640, &[0x81, 4, 12, 0]).unwrap();
    assert_eq!(av1.codec_private(), [0x81, 4, 12, 0]);
    let mut mux = MatroskaMuxer::new(2, Track::Video(av1)).unwrap();
    assert!(mux.push_packet(0, true, &[0x12, 0]).is_err()); // Temporal delimiter alone is not a frame.
    assert_eq!(mux.source_origin_us(), None);
    let vp9 =
        VideoTrack::from_scrcpy(VideoCodec::Vp9, 288, 640, &[1, 1, 0, 2, 1, 0, 3, 1, 8]).unwrap();
    assert_eq!(vp9.codec_private(), [1, 1, 0, 3, 1, 8]);
    assert!(VideoTrack::from_scrcpy(VideoCodec::Vp9, 288, 640, &[1, 1, 0, 1, 1, 1]).is_err());
}

#[test]
fn rejects_midstream_parameter_change_and_requires_new_generation() {
    // Actual Android AVC baseline SPS/PPS. No decoder is needed for this config-boundary test.
    let config = [
        0, 0, 0, 1, 0x67, 0x42, 0xc0, 0x29, 0x8d, 0x68, 0x12, 5, 0x1a, 0x42, 12, 2, 12, 15, 8,
        0x84, 0x6a, 0, 0, 0, 1, 0x68, 0xce, 1, 0xa8, 0x35, 0xc8,
    ];
    let track = VideoTrack::from_scrcpy(VideoCodec::H264, 288, 640, &config).unwrap();
    let mut mux = MatroskaMuxer::new(3, Track::Video(track)).unwrap();
    assert!(mux.push_packet(10, false, &[0, 0, 1, 0x41, 1]).is_err());
    mux.push_packet(20, true, &[0, 0, 1, 0x65, 1]).unwrap();
    let error = mux
        .push_packet(30, true, &[0, 0, 1, 0x68, 0xce, 1, 0xa8, 0x35, 0xc9])
        .unwrap_err();
    assert!(error.to_string().contains("new generation"));
    assert_eq!(mux.source_origin_us(), Some(20));
    assert!(
        !mux.push_packet(40, false, &[0, 0, 1, 0x41, 1])
            .unwrap()
            .is_empty()
    );
}
