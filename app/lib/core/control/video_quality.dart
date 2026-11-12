import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/settings/preferences.dart';

import 'session_activity.dart';

export 'package:scrcpy_connect/core/settings/preferences.dart' show VideoCodec;

part 'video_quality.freezed.dart';
part 'video_quality.g.dart';

enum VideoQualityPreset { smooth, balanced, clear }

/// 可空记录区分保持现有编码器与明确恢复自动选择。
@freezed
abstract class VideoQualityPatch with _$VideoQualityPatch {
  const factory VideoQualityPatch({
    VideoQualityPreset? preset,
    int? maxSize,
    int? maxFps,
    int? bitRate,
    VideoCodec? codec,
    ({String? name})? encoder,
  }) = _VideoQualityPatch;
}

@freezed
abstract class VideoQuality with _$VideoQuality {
  const VideoQuality._();
  // ignore: invalid_annotation_target
  @JsonSerializable(includeIfNull: false)
  const factory VideoQuality({
    @JsonKey(name: 'qualityPreset') VideoQualityPreset? preset,
    required int maxSize,
    required int maxFps,
    @JsonKey(name: 'videoBitRate') required int bitRate,
    @JsonKey(name: 'videoCodec') required VideoCodec codec,
    @JsonKey(name: 'videoEncoder', includeIfNull: true) String? encoder,
  }) = _VideoQuality;

  factory VideoQuality.fromJson(Map<String, dynamic> json) =>
      _$VideoQualityFromJson(json);

  VideoQualityPreferences get preferences => VideoQualityPreferences(
    qualityPreset: (name: preset?.name),
    maxSize: maxSize,
    maxFps: maxFps,
    videoBitRate: bitRate,
    videoCodec: codec,
    videoEncoder: (name: encoder),
  );
}

/// 从受控服务端清单解析出的编码器事实。
@freezed
abstract class VideoEncoder with _$VideoEncoder {
  const factory VideoEncoder({
    required VideoCodec codec,
    required String name,
    bool? hardware,
  }) = _VideoEncoder;
}

enum VideoDecoderEvidence { unknown, verified, unavailable }

@freezed
abstract class VideoDecoderCapability with _$VideoDecoderCapability {
  const factory VideoDecoderCapability({
    required VideoCodec codec,
    required VideoDecoderEvidence evidence,
    required bool canAttempt,
    required String reason,
  }) = _VideoDecoderCapability;
}

@freezed
abstract class VideoCodecOption with _$VideoCodecOption {
  const VideoCodecOption._();
  const factory VideoCodecOption({
    required VideoCodec codec,
    required List<VideoEncoder> encoders,
    required VideoDecoderCapability decoder,
  }) = _VideoCodecOption;

  bool get available =>
      encoders.isNotEmpty &&
      decoder.evidence != VideoDecoderEvidence.unavailable &&
      (decoder.evidence == VideoDecoderEvidence.verified || decoder.canAttempt);
}

@freezed
abstract class VideoQualityOptions with _$VideoQualityOptions {
  const factory VideoQualityOptions({
    required VideoQuality current,
    required List<VideoCodecOption> codecs,
    required List<SessionActivity> activeSessions,
    @Default([
      VideoQualityPreset.smooth,
      VideoQualityPreset.balanced,
      VideoQualityPreset.clear,
    ])
    List<VideoQualityPreset> presets,
    @Default([720, 1080, 1280, 1920]) List<int> maxSizes,
    @Default([30, 60]) List<int> frameRates,
    @Default([2000000, 4000000, 8000000, 12000000]) List<int> bitRates,
  }) = _VideoQualityOptions;
}

@freezed
abstract class VideoQualityFailure with _$VideoQualityFailure {
  const factory VideoQualityFailure({
    String? sessionId,
    required String name,
    required String reason,
    String? code,
  }) = _VideoQualityFailure;
}

@freezed
abstract class VideoQualityApplication with _$VideoQualityApplication {
  const factory VideoQualityApplication({
    required VideoQuality current,
    required bool appliedToAll,
    required List<SessionActivity> appliedSessions,
    required List<VideoQualityFailure> failures,
    required List<String> skippedSessions,
    required String reason,
  }) = _VideoQualityApplication;
}

@freezed
abstract class VideoQualityState with _$VideoQualityState {
  const factory VideoQualityState({
    @Default(true) bool loading,
    VideoQualityOptions? data,
    Object? error,
    @Default(0) int revision,
  }) = _VideoQualityState;
}

abstract interface class VideoQualityControl {
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId);
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  );
}
