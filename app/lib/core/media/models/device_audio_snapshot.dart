import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/media/models/audio_focus.dart';

part 'device_audio_snapshot.freezed.dart';

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
}

/// 捕获所有者的唯一状态；原生输出的事实由精确回执提交，源包数不构成可闻证明。
@freezed
abstract class DeviceAudioSnapshot with _$DeviceAudioSnapshot {
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
    AudioFocusSignal? focusSignal,
    String? reason,
    AudioCleanupFailure? cleanupError,
  }) = _DeviceAudioSnapshot;
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
    required AudioFocusSignal focusSignal,
    @Default(false) bool audibleContentVerified,
    @Default(false) bool speakerSamplesVerified,
    @Default(false) bool volumeConfigured,
    @Default(false) bool volumeOutputVerified,
  }) = _AudioOutputReceipt;
}

typedef DeviceAudioPlayback = ({
  DeviceAudioSnapshot source,
  AudioOutputReceipt output,
});
