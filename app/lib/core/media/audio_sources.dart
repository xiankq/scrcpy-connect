import 'package:freezed_annotation/freezed_annotation.dart';

part 'audio_sources.freezed.dart';
part 'audio_sources.g.dart';

enum DeviceAudioStatus { starting, playing, paused, error, stopped }

enum AudioPlayState { starting, playing, paused }

@freezed
abstract class DeviceAudioTarget with _$DeviceAudioTarget {
  const factory DeviceAudioTarget({
    required String deviceId,
    String? sourceId,
  }) = _DeviceAudioTarget;
}

@freezed
abstract class AudioCleanupFailure with _$AudioCleanupFailure {
  const factory AudioCleanupFailure({
    required String code,
    required String reason,
  }) = _AudioCleanupFailure;
  factory AudioCleanupFailure.fromJson(Map<String, Object?> json) =>
      _$AudioCleanupFailureFromJson(json);
}

/// 捕获所有者的唯一状态；原生输出的事实由精确回执提交，源包数不构成可闻证明。
@freezed
abstract class DeviceAudioSnapshot with _$DeviceAudioSnapshot {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true, includeIfNull: false)
  const factory DeviceAudioSnapshot({
    required String sourceId,
    required String deviceId,
    required int generation,
    required String name,
    required DeviceAudioStatus status,
    required int createdAt,
    @Default('pcm_s16le') String codec,
    @Default(48000) int sampleRate,
    @Default(2) int channels,
    @Default(2) int bytesPerSample,
    @Default(1) double volume,
    @Default(false) bool muted,
    @Default(false) bool nativeAttached,
    @Default(false) bool playbackVerified,
    @Default(false) bool speakerSamplesVerified,
    @Default(false) bool audibleContentVerified,
    @Default('output') String captureSource,
    @Default(false) bool callAudioSupported,
    @Default(false) bool remoteExitVerified,
    @Default(false) bool captureReady,
    @Default(false) bool mediaReady,
    @Default(false) bool localReleased,
    @Default(false) bool existing,
    String? audioSourceId,
    String? captureRef,
    int? nativeGeneration,
    int? processId,
    int? processStarted,
    String? backend,
    int? nativeRevision,
    int? bytesWritten,
    bool? presentationOnly,
    bool? manualPaused,
    bool? focusPaused,
    bool? backgroundPaused,
    bool? requiresUserResume,
    String? focusSignal,
    String? reason,
    AudioCleanupFailure? cleanupError,
  }) = _DeviceAudioSnapshot;
  factory DeviceAudioSnapshot.fromJson(Map<String, Object?> json) =>
      _$DeviceAudioSnapshotFromJson(json);
}

@freezed
abstract class AudioVolumeChange with _$AudioVolumeChange {
  const factory AudioVolumeChange({
    required DeviceAudioTarget target,
    required double volume,
    required bool muted,
  }) = _AudioVolumeChange;
}

/// 输出所有者提交的实际播放器证据，必须关联精确设备与源，不能代替系统可闻性证明。
@freezed
abstract class AudioOutputReceipt with _$AudioOutputReceipt {
  // ignore: invalid_annotation_target
  @JsonSerializable(includeIfNull: false)
  const factory AudioOutputReceipt({
    required String sourceId,
    required String deviceId,
    String? relayId,
    @Default('media_codec') String backend,
    required bool nativeReady,
    required int bytesWritten,
    required int revision,
    required bool applied,
    required AudioPlayState playState,
    required bool manualPaused,
    required bool focusPaused,
    required bool backgroundPaused,
    required bool requiresUserResume,
    required String reason,
    @Default(48000) int sampleRate,
    @Default(2) int channels,
    required bool mediaInfoReady,
    required bool playingConfirmed,
    required bool sourcePcmReceived,
    required int sourcePcmPackets,
    required bool playbackClockAdvanced,
    int? clockStartMs,
    int? clockEndMs,
    int? positionMs,
    required double volume,
    required bool muted,
    int? focusEpoch,
    required String focusSignal,
    @Default(false) bool audibleContentVerified,
    @Default(false) bool speakerSamplesVerified,
    @Default(false) bool volumeConfigured,
    @Default(false) bool volumeOutputVerified,
  }) = _AudioOutputReceipt;
  factory AudioOutputReceipt.fromJson(Map<String, Object?> json) =>
      _$AudioOutputReceiptFromJson(json);
}

typedef DeviceAudioPlayback = ({
  DeviceAudioSnapshot source,
  AudioOutputReceipt output,
});

abstract interface class RemoteAudio {
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId});
  Future<Set<String>> readAudioEligibleDevices();
  Future<DeviceAudioPlayback> startAudio(String deviceId);
  Future<void> stopAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  });
}

@freezed
abstract class AudioSourcesState with _$AudioSourcesState {
  const factory AudioSourcesState({
    @Default(true) bool loading,
    List<DeviceAudioSnapshot>? sources,
    Object? error,
    @Default(0) int revision,
  }) = _AudioSourcesState;
}
