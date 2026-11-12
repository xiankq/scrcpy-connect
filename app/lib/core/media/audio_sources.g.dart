// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: unnecessary_cast

part of 'audio_sources.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AudioCleanupFailure _$AudioCleanupFailureFromJson(Map<String, dynamic> json) =>
    _AudioCleanupFailure(
      code: json['code'] as String,
      reason: json['reason'] as String,
    );

Map<String, dynamic> _$AudioCleanupFailureToJson(
  _AudioCleanupFailure instance,
) => <String, dynamic>{'code': instance.code, 'reason': instance.reason};

_DeviceAudioSnapshot _$DeviceAudioSnapshotFromJson(Map<String, dynamic> json) =>
    _DeviceAudioSnapshot(
      sourceId: json['sourceId'] as String,
      deviceId: json['deviceId'] as String,
      generation: (json['generation'] as num).toInt(),
      name: json['name'] as String,
      status: $enumDecode(_$DeviceAudioStatusEnumMap, json['status']),
      createdAt: (json['createdAt'] as num).toInt(),
      codec: json['codec'] as String? ?? 'pcm_s16le',
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 48000,
      channels: (json['channels'] as num?)?.toInt() ?? 2,
      bytesPerSample: (json['bytesPerSample'] as num?)?.toInt() ?? 2,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      muted: json['muted'] as bool? ?? false,
      nativeAttached: json['nativeAttached'] as bool? ?? false,
      playbackVerified: json['playbackVerified'] as bool? ?? false,
      speakerSamplesVerified: json['speakerSamplesVerified'] as bool? ?? false,
      audibleContentVerified: json['audibleContentVerified'] as bool? ?? false,
      captureSource: json['captureSource'] as String? ?? 'output',
      callAudioSupported: json['callAudioSupported'] as bool? ?? false,
      remoteExitVerified: json['remoteExitVerified'] as bool? ?? false,
      captureReady: json['captureReady'] as bool? ?? false,
      mediaReady: json['mediaReady'] as bool? ?? false,
      localReleased: json['localReleased'] as bool? ?? false,
      existing: json['existing'] as bool? ?? false,
      audioSourceId: json['audioSourceId'] as String?,
      captureRef: json['captureRef'] as String?,
      nativeGeneration: (json['nativeGeneration'] as num?)?.toInt(),
      processId: (json['processId'] as num?)?.toInt(),
      processStarted: (json['processStarted'] as num?)?.toInt(),
      backend: json['backend'] as String?,
      nativeRevision: (json['nativeRevision'] as num?)?.toInt(),
      bytesWritten: (json['bytesWritten'] as num?)?.toInt(),
      presentationOnly: json['presentationOnly'] as bool?,
      manualPaused: json['manualPaused'] as bool?,
      focusPaused: json['focusPaused'] as bool?,
      backgroundPaused: json['backgroundPaused'] as bool?,
      requiresUserResume: json['requiresUserResume'] as bool?,
      focusSignal: json['focusSignal'] as String?,
      reason: json['reason'] as String?,
      cleanupError: json['cleanupError'] == null
          ? null
          : AudioCleanupFailure.fromJson(
              json['cleanupError'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$DeviceAudioSnapshotToJson(
  _DeviceAudioSnapshot instance,
) => <String, dynamic>{
  'sourceId': instance.sourceId,
  'deviceId': instance.deviceId,
  'generation': instance.generation,
  'name': instance.name,
  'status': _$DeviceAudioStatusEnumMap[instance.status]!,
  'createdAt': instance.createdAt,
  'codec': instance.codec,
  'sampleRate': instance.sampleRate,
  'channels': instance.channels,
  'bytesPerSample': instance.bytesPerSample,
  'volume': instance.volume,
  'muted': instance.muted,
  'nativeAttached': instance.nativeAttached,
  'playbackVerified': instance.playbackVerified,
  'speakerSamplesVerified': instance.speakerSamplesVerified,
  'audibleContentVerified': instance.audibleContentVerified,
  'captureSource': instance.captureSource,
  'callAudioSupported': instance.callAudioSupported,
  'remoteExitVerified': instance.remoteExitVerified,
  'captureReady': instance.captureReady,
  'mediaReady': instance.mediaReady,
  'localReleased': instance.localReleased,
  'existing': instance.existing,
  'audioSourceId': ?instance.audioSourceId,
  'captureRef': ?instance.captureRef,
  'nativeGeneration': ?instance.nativeGeneration,
  'processId': ?instance.processId,
  'processStarted': ?instance.processStarted,
  'backend': ?instance.backend,
  'nativeRevision': ?instance.nativeRevision,
  'bytesWritten': ?instance.bytesWritten,
  'presentationOnly': ?instance.presentationOnly,
  'manualPaused': ?instance.manualPaused,
  'focusPaused': ?instance.focusPaused,
  'backgroundPaused': ?instance.backgroundPaused,
  'requiresUserResume': ?instance.requiresUserResume,
  'focusSignal': ?instance.focusSignal,
  'reason': ?instance.reason,
  'cleanupError': ?instance.cleanupError?.toJson(),
};

const _$DeviceAudioStatusEnumMap = {
  DeviceAudioStatus.starting: 'starting',
  DeviceAudioStatus.playing: 'playing',
  DeviceAudioStatus.paused: 'paused',
  DeviceAudioStatus.error: 'error',
  DeviceAudioStatus.stopped: 'stopped',
};

_AudioOutputReceipt _$AudioOutputReceiptFromJson(Map<String, dynamic> json) =>
    _AudioOutputReceipt(
      sourceId: json['sourceId'] as String,
      deviceId: json['deviceId'] as String,
      relayId: json['relayId'] as String?,
      backend: json['backend'] as String? ?? 'media_codec',
      nativeReady: json['nativeReady'] as bool,
      bytesWritten: (json['bytesWritten'] as num).toInt(),
      revision: (json['revision'] as num).toInt(),
      applied: json['applied'] as bool,
      playState: $enumDecode(_$AudioPlayStateEnumMap, json['playState']),
      manualPaused: json['manualPaused'] as bool,
      focusPaused: json['focusPaused'] as bool,
      backgroundPaused: json['backgroundPaused'] as bool,
      requiresUserResume: json['requiresUserResume'] as bool,
      reason: json['reason'] as String,
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 48000,
      channels: (json['channels'] as num?)?.toInt() ?? 2,
      mediaInfoReady: json['mediaInfoReady'] as bool,
      playingConfirmed: json['playingConfirmed'] as bool,
      sourcePcmReceived: json['sourcePcmReceived'] as bool,
      sourcePcmPackets: (json['sourcePcmPackets'] as num).toInt(),
      playbackClockAdvanced: json['playbackClockAdvanced'] as bool,
      clockStartMs: (json['clockStartMs'] as num?)?.toInt(),
      clockEndMs: (json['clockEndMs'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt(),
      volume: (json['volume'] as num).toDouble(),
      muted: json['muted'] as bool,
      focusEpoch: (json['focusEpoch'] as num?)?.toInt(),
      focusSignal: json['focusSignal'] as String,
      audibleContentVerified: json['audibleContentVerified'] as bool? ?? false,
      speakerSamplesVerified: json['speakerSamplesVerified'] as bool? ?? false,
      volumeConfigured: json['volumeConfigured'] as bool? ?? false,
      volumeOutputVerified: json['volumeOutputVerified'] as bool? ?? false,
    );

Map<String, dynamic> _$AudioOutputReceiptToJson(_AudioOutputReceipt instance) =>
    <String, dynamic>{
      'sourceId': instance.sourceId,
      'deviceId': instance.deviceId,
      'relayId': ?instance.relayId,
      'backend': instance.backend,
      'nativeReady': instance.nativeReady,
      'bytesWritten': instance.bytesWritten,
      'revision': instance.revision,
      'applied': instance.applied,
      'playState': _$AudioPlayStateEnumMap[instance.playState]!,
      'manualPaused': instance.manualPaused,
      'focusPaused': instance.focusPaused,
      'backgroundPaused': instance.backgroundPaused,
      'requiresUserResume': instance.requiresUserResume,
      'reason': instance.reason,
      'sampleRate': instance.sampleRate,
      'channels': instance.channels,
      'mediaInfoReady': instance.mediaInfoReady,
      'playingConfirmed': instance.playingConfirmed,
      'sourcePcmReceived': instance.sourcePcmReceived,
      'sourcePcmPackets': instance.sourcePcmPackets,
      'playbackClockAdvanced': instance.playbackClockAdvanced,
      'clockStartMs': ?instance.clockStartMs,
      'clockEndMs': ?instance.clockEndMs,
      'positionMs': ?instance.positionMs,
      'volume': instance.volume,
      'muted': instance.muted,
      'focusEpoch': ?instance.focusEpoch,
      'focusSignal': instance.focusSignal,
      'audibleContentVerified': instance.audibleContentVerified,
      'speakerSamplesVerified': instance.speakerSamplesVerified,
      'volumeConfigured': instance.volumeConfigured,
      'volumeOutputVerified': instance.volumeOutputVerified,
    };

const _$AudioPlayStateEnumMap = {
  AudioPlayState.starting: 'starting',
  AudioPlayState.playing: 'playing',
  AudioPlayState.paused: 'paused',
};
