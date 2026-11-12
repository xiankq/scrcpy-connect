// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'video_quality.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_VideoQuality _$VideoQualityFromJson(Map<String, dynamic> json) =>
    _VideoQuality(
      preset: $enumDecodeNullable(
        _$VideoQualityPresetEnumMap,
        json['qualityPreset'],
      ),
      maxSize: (json['maxSize'] as num).toInt(),
      maxFps: (json['maxFps'] as num).toInt(),
      bitRate: (json['videoBitRate'] as num).toInt(),
      codec: $enumDecode(_$VideoCodecEnumMap, json['videoCodec']),
      encoder: json['videoEncoder'] as String?,
    );

Map<String, dynamic> _$VideoQualityToJson(_VideoQuality instance) =>
    <String, dynamic>{
      'qualityPreset': ?_$VideoQualityPresetEnumMap[instance.preset],
      'maxSize': instance.maxSize,
      'maxFps': instance.maxFps,
      'videoBitRate': instance.bitRate,
      'videoCodec': _$VideoCodecEnumMap[instance.codec]!,
      'videoEncoder': instance.encoder,
    };

const _$VideoQualityPresetEnumMap = {
  VideoQualityPreset.smooth: 'smooth',
  VideoQualityPreset.balanced: 'balanced',
  VideoQualityPreset.clear: 'clear',
};

const _$VideoCodecEnumMap = {
  VideoCodec.h264: 'h264',
  VideoCodec.h265: 'h265',
  VideoCodec.av1: 'av1',
  VideoCodec.vp8: 'vp8',
  VideoCodec.vp9: 'vp9',
};
