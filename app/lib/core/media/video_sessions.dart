import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

export 'package:scrcpy_connect/core/media/models/video_session_view.dart';

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

/// 应用启动已经提交，输出失败不证明远端任务没有打开。
final class VideoStartUncertain extends RequestFailure {
  VideoStartUncertain(this.session)
    : super('app_launch_unknown', '应用可能已在手机上打开，请先核对本次记录。');
  final VideoSessionSnapshot session;
}
