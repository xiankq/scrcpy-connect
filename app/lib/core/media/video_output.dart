import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/control/video_session.dart';

import 'video_output_snapshot.dart';

part 'video_output.freezed.dart';

@freezed
abstract class VideoDecoderMetadata with _$VideoDecoderMetadata {
  const VideoDecoderMetadata._();
  const factory VideoDecoderMetadata({
    String? decoderName,
    bool? hardwareAccelerated,
    String? hardwareVerification,
    bool? backendHardwareFrames,
    bool? platformTexturePrepared,
    int? presentedSequence,
    String? presentationPath,
  }) = _VideoDecoderMetadata;

  Map<String, dynamic> toSnapshot() => {
    'decoderName': decoderName,
    'hardwareAccelerated': hardwareAccelerated,
    'hardwareVerification': hardwareVerification,
    'backendHardwareFrames': backendHardwareFrames,
    'platformTexturePrepared': platformTexturePrepared,
    'presentedSequence': presentedSequence,
    'presentationPath': presentationPath,
  };
}

/// 同一捕获与本机渲染代次的实际解码证据。
@freezed
abstract class VideoOutputReceipt with _$VideoOutputReceipt {
  const VideoOutputReceipt._();
  const factory VideoOutputReceipt({
    required String sessionId,
    required String deviceId,
    required String relayId,
    required int textureId,
    required int decodedWidth,
    required int decodedHeight,
    required String codec,
    required int generation,
    required int captureGeneration,
    required bool paused,
    int? frameCount,
    required int decodedReceipts,
    required int snapshotReceipts,
    @Default(VideoDecoderMetadata()) VideoDecoderMetadata decoder,
    @Default({}) Map<String, int> startupTimingMs,
  }) = _VideoOutputReceipt;

  VideoRendererReceipt get rendererReceipt => VideoRendererReceipt(
    sessionId: sessionId,
    deviceId: deviceId,
    captureGeneration: captureGeneration,
    generation: generation,
    textureId: textureId,
    decodedWidth: decodedWidth,
    decodedHeight: decodedHeight,
    frameCount: frameCount,
    hardwareAccelerated: decoder.hardwareAccelerated,
  );

  bool sameBinding(VideoOutputReceipt other) =>
      sessionId == other.sessionId &&
      deviceId == other.deviceId &&
      generation == other.generation &&
      captureGeneration == other.captureGeneration &&
      relayId == other.relayId &&
      textureId == other.textureId;

  Map<String, dynamic> toSnapshot() => {
    ...decoder.toSnapshot(),
    'sessionId': sessionId,
    'deviceId': deviceId,
    'relayId': relayId,
    'textureId': textureId,
    'decodedWidth': decodedWidth,
    'decodedHeight': decodedHeight,
    'codec': codec,
    'generation': generation,
    'captureGeneration': captureGeneration,
    'paused': paused,
    if (frameCount != null) 'frameCount': frameCount,
    'backend': 'media_codec',
    'firstFrameDecoded': true,
    'evidence': 'media_codec.decodedFrame',
    'decodedReceipts': decodedReceipts,
    'snapshotReceipts': snapshotReceipts,
    'presentedToWidget': false,
    'continuousFrameTelemetry': false,
    'outputStartupTimingMs': startupTimingMs,
  };
}

sealed class VideoOutputEvent {
  const VideoOutputEvent();
  Map<String, dynamic> toApplicationEvent() => switch (this) {
    VideoOutputReady(:final output) => _event('session.output.ready', output),
    VideoOutputChanged(:final output) => _event(
      'session.output.changed',
      output,
    ),
    VideoOutputFrame(:final output) => _event(
      'session.frame',
      output,
      metadataOnly: true,
    ),
    VideoOutputFailed(
      :final sessionId,
      :final deviceId,
      :final generation,
      :final reason,
    ) =>
      {
        'type': 'session.output.failed',
        'deviceId': deviceId,
        'data': {
          'sessionId': sessionId,
          'generation': generation,
          'reason': reason,
          'backend': 'media_codec',
        },
      },
  };
  static Map<String, dynamic> _event(
    String type,
    VideoOutputReceipt output, {
    bool metadataOnly = false,
  }) => {
    'type': type,
    'deviceId': output.deviceId,
    'data': {...output.toSnapshot(), if (metadataOnly) 'metadataOnly': true},
  };
}

final class VideoOutputReady extends VideoOutputEvent {
  const VideoOutputReady(this.output);
  final VideoOutputReceipt output;
}

final class VideoOutputChanged extends VideoOutputEvent {
  const VideoOutputChanged(this.output);
  final VideoOutputReceipt output;
}

final class VideoOutputFrame extends VideoOutputEvent {
  const VideoOutputFrame(this.output);
  final VideoOutputReceipt output;
}

final class VideoOutputFailed extends VideoOutputEvent {
  const VideoOutputFailed({
    required this.sessionId,
    required this.deviceId,
    required this.generation,
    required this.reason,
  });
  final String sessionId, deviceId, reason;
  final int generation;
}

@freezed
abstract class VideoPlaybackReceipt with _$VideoPlaybackReceipt {
  const VideoPlaybackReceipt._();
  const factory VideoPlaybackReceipt({
    required VideoSessionSnapshot session,
    required VideoOutputReceipt output,
  }) = _VideoPlaybackReceipt;

  Map<String, dynamic> toSnapshot() => {
    ...sessionWithVideoOutput(session.toSnapshot(), output.toSnapshot()),
    'paused': output.paused,
  };
}
