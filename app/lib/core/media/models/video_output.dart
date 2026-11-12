import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';

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
}

sealed class VideoOutputEvent extends AppEvent {
  const VideoOutputEvent();
  String get sessionId;
  @override
  String get deviceId;

  @override
  String get type => switch (this) {
    VideoOutputReady() => 'session.output.ready',
    VideoOutputChanged() => 'session.output.changed',
    VideoOutputFrame() => 'session.frame',
    VideoOutputFailed() => 'session.output.failed',
  };
}

final class VideoOutputReady extends VideoOutputEvent {
  const VideoOutputReady(this.output);
  final VideoOutputReceipt output;
  @override
  String get sessionId => output.sessionId;
  @override
  String get deviceId => output.deviceId;
}

final class VideoOutputChanged extends VideoOutputEvent {
  const VideoOutputChanged(this.output);
  final VideoOutputReceipt output;
  @override
  String get sessionId => output.sessionId;
  @override
  String get deviceId => output.deviceId;
}

final class VideoOutputFrame extends VideoOutputEvent {
  const VideoOutputFrame(this.output);
  final VideoOutputReceipt output;
  @override
  String get sessionId => output.sessionId;
  @override
  String get deviceId => output.deviceId;
}

final class VideoOutputFailed extends VideoOutputEvent {
  const VideoOutputFailed({
    required this.sessionId,
    required this.deviceId,
    required this.generation,
    required this.captureGeneration,
    required this.reason,
  });
  @override
  final String sessionId;
  @override
  final String deviceId;
  final String reason;
  final int generation, captureGeneration;
}

@freezed
abstract class VideoPlaybackReceipt with _$VideoPlaybackReceipt {
  const VideoPlaybackReceipt._();
  const factory VideoPlaybackReceipt({
    required VideoSessionSnapshot session,
    required VideoOutputReceipt output,
  }) = _VideoPlaybackReceipt;
}
