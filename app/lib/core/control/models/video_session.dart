import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_display_size.dart';
import 'package:scrcpy_connect/core/control/models/video_quality.dart';
import 'package:scrcpy_connect/core/control/video_quality_policy.dart';
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

  /// 仅用于事件、恢复快照和视图适配；业务调用直接消费类型字段。
  Map<String, dynamic> toSnapshot() => {
    'id': sessionId,
    'sessionId': sessionId,
    'deviceId': deviceId,
    'name': name,
    'kind': kind.name,
    'status': status.name.replaceAll('awaitingRenderer', 'awaiting_renderer'),
    'packageName': packageName,
    'captureGeneration': captureGeneration,
    'generation': generation,
    'createdAt': createdAt,
    'quality': quality == null ? null : VideoQualityPolicy.current(quality!),
    'videoCodec': videoCodec?.name,
    'videoEncoder': videoEncoder,
    'captureRef': captureRef,
    'videoSourceId': videoSourceId,
    'width': width,
    'height': height,
    'textureId': textureId,
    'paused': paused,
    'awaitingSession': awaitingSession,
    'capturePaused': capturePaused,
    'audio': audio,
    'apiLevel': apiLevel,
    'displayAuto': displayAuto,
    'displayWidth': displayWidth,
    'displayHeight': displayHeight,
    'displayDensity': displayDensity,
    'displayId': displayId,
    'launchOperationId': launchOperationId,
    'launchOutcome': launchOutcome?.name,
    'taskId': taskId,
    'failureCode': failureCode,
    'reason': reason,
    'frameCount': frameCount,
    'lastFrameAt': lastFrameAt,
    'framesDecoded': framesDecoded,
    'presentationTimeUs': presentationTimeUs,
    'decoder': decoder,
    'renderer': renderer,
    'hardwareAccelerated': hardwareAccelerated,
    'hardwareAcceleration': hardwareAcceleration,
    'decodedWidth': decodedWidth,
    'decodedHeight': decodedHeight,
    'processId': processId,
    'processStarted': processStarted,
    'qualityRebuilding': qualityRebuilding,
    'qualityRebuildTarget': qualityRebuildTarget,
    'qualityRebuildOutcome': qualityRebuildOutcome?.name.replaceAll(
      'awaitingRenderer',
      'awaiting_renderer',
    ),
    'qualityRetryable': qualityRetryable,
    'qualityFailureCode': qualityFailureCode,
    'displayOutcome': displayOutcome?.name,
    'displayFailureCode': displayFailureCode,
    'recordOnly': recordOnly,
    'linkedSessionId': linkedSessionId,
    'codec': videoCodec?.name,
    if (displayWidth != null && displayHeight != null)
      'displaySize': {'width': displayWidth, 'height': displayHeight},
  };
}

/// 一次明确的窗口打开意图；尺寸成对提供，设备设置由所有者读取。
@freezed
abstract class VideoSessionPlan with _$VideoSessionPlan {
  const factory VideoSessionPlan({
    required String deviceId,
    String? sessionId,
    String? name,
    String? packageName,
    VideoDisplaySize? displaySize,
    @Default(false) bool displayAuto,
  }) = _VideoSessionPlan;
}
