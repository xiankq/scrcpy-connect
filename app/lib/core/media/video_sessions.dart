import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/control/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/session_activity.dart';
import 'package:scrcpy_connect/core/control/video_session.dart';

import 'video_output.dart';
import 'video_output_snapshot.dart';

part 'video_sessions.freezed.dart';

/// 只读组合窗口、输出和设备共享租约；三个事实仍各由原所有者持有。
@freezed
abstract class VideoSessionView with _$VideoSessionView {
  const VideoSessionView._();
  const factory VideoSessionView({
    required VideoSessionSnapshot session,
    required KeepAwakeSnapshot wake,
    VideoOutputReceipt? output,
  }) = _VideoSessionView;

  String get sessionId => session.sessionId;
  String get deviceId => session.deviceId;
  Map<String, dynamic> toSnapshot() => {
    ...sessionWithVideoOutput(session.toSnapshot(), output?.toSnapshot()),
    ...wake.sessionSnapshot,
  };
}

abstract interface class VideoSessions {
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId});
  Future<VideoSessionView> startVideo(VideoSessionPlan plan);
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  });
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target);
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target);
}
