import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

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
