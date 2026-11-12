import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';

part 'session_activity.freezed.dart';

/// 控制所有者交付给活动聚合的只读事实，不取得捕获或应用任务的关闭权。
@freezed
abstract class SessionActivity with _$SessionActivity {
  const factory SessionActivity({
    required String sessionId,
    required String deviceId,
    required String name,
    required String status,
    @Default(false) bool needsLaunchReview,
    @Default(false) bool recordOnly,
    String? linkedSessionId,
    String? reason,
  }) = _SessionActivity;

  factory SessionActivity.fromSession(VideoSessionSnapshot session) =>
      SessionActivity(
        sessionId: session.sessionId,
        deviceId: session.deviceId,
        name: session.name,
        status: session.status == VideoSessionStatus.awaitingRenderer
            ? 'awaiting_renderer'
            : session.status.name,
        needsLaunchReview: session.launchOutcome == VideoLaunchOutcome.unknown,
        recordOnly: session.recordOnly,
        linkedSessionId: session.linkedSessionId,
        reason: session.reason,
      );
}

@freezed
abstract class VideoStopReceipt with _$VideoStopReceipt {
  const factory VideoStopReceipt({
    required String sessionId,
    String? deviceId,
    @Default(false) bool recordOnly,
    KeepAwakeSnapshot? wakeCleanup,
  }) = _VideoStopReceipt;
}
