import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_display_size.dart';
import 'package:scrcpy_connect/core/control/models/video_quality.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

part 'video_session.freezed.dart';

enum VideoSessionKind { screen, app }

enum VideoSessionStatus {
  starting,
  streaming,
  paused,
  awaitingRenderer,
  stopping,
  stopped,
  failed,
}

enum VideoLaunchOutcome { sent, observed, unknown }

enum VideoQualityRebuildOutcome {
  rebuilding,
  awaitingRenderer,
  applied,
  failed,
  restored,
}

enum VideoDisplayOutcome { unknown, applied }

enum VideoSessionChange { updated, starting, stopped, failed, frame }

/// 捕获所有者发布的不可变窗口事实；待核对记录不表示可用捕获。
@freezed
abstract class VideoSessionSnapshot with _$VideoSessionSnapshot {
  const VideoSessionSnapshot._();
  const factory VideoSessionSnapshot({
    required String sessionId,
    required String deviceId,
    required String name,
    required VideoSessionKind kind,
    required VideoSessionStatus status,
    String? packageName,
    @Default(0) int captureGeneration,
    @Default(0) int generation,
    @Default(0) int createdAt,
    VideoQuality? quality,
    VideoCodec? videoCodec,
    String? videoEncoder,
    String? captureRef,
    String? videoSourceId,
    int? width,
    int? height,
    int? textureId,
    @Default(false) bool paused,
    @Default(false) bool awaitingSession,
    @Default(false) bool capturePaused,
    @Default(false) bool audio,
    int? apiLevel,
    @Default(false) bool displayAuto,
    int? displayWidth,
    int? displayHeight,
    int? displayDensity,
    int? displayId,
    String? launchOperationId,
    VideoLaunchOutcome? launchOutcome,
    int? taskId,
    String? failureCode,
    String? reason,
    int? frameCount,
    int? lastFrameAt,
    int? framesDecoded,
    int? presentationTimeUs,
    String? decoder,
    String? renderer,
    bool? hardwareAccelerated,
    String? hardwareAcceleration,
    int? decodedWidth,
    int? decodedHeight,
    int? processId,
    int? processStarted,
    @Default(false) bool qualityRebuilding,
    int? qualityRebuildTarget,
    VideoQualityRebuildOutcome? qualityRebuildOutcome,
    @Default(false) bool qualityRetryable,
    String? qualityFailureCode,
    VideoDisplayOutcome? displayOutcome,
    String? displayFailureCode,
    @Default(false) bool recordOnly,
    String? linkedSessionId,
  }) = _VideoSessionSnapshot;

  SessionActivity get activity => SessionActivity(
    sessionId: sessionId,
    deviceId: deviceId,
    name: name,
    status: status == VideoSessionStatus.awaitingRenderer
        ? 'awaiting_renderer'
        : status.name,
    needsLaunchReview: launchOutcome == VideoLaunchOutcome.unknown,
    recordOnly: recordOnly,
    linkedSessionId: linkedSessionId,
    reason: reason,
  );

  bool get live => switch (status) {
    .stopped => false,
    .failed => qualityRetryable,
    _ => true,
  };

  VideoCapture get capture {
    final ref = captureRef, source = videoSourceId, codec = videoCodec;
    final w = width, h = height;
    if (ref == null ||
        source == null ||
        codec == null ||
        w == null ||
        h == null) {
      throw const RequestFailure('media_not_ready', '窗口尚未交付精确视频捕获。');
    }
    return VideoCapture(
      sessionId: sessionId,
      deviceId: deviceId,
      captureRef: ref,
      captureGeneration: captureGeneration,
      generation: generation,
      videoSourceId: source,
      codec: codec,
      width: w,
      height: h,
    );
  }
}

/// 一次明确的窗口打开意图；尺寸成对提供，设备设置由所有者读取。
@freezed
abstract class VideoSessionPlan with _$VideoSessionPlan {
  const factory VideoSessionPlan({
    required String deviceId,
    String? sessionId,
    String? name,
    String? packageName,
    @Default(false) bool moveForegroundApp,
    VideoDisplaySize? displaySize,
    @Default(false) bool displayAuto,
  }) = _VideoSessionPlan;
}
