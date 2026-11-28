import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

VideoSessionChanged videoChange({
  String deviceId = 'device',
  VideoSessionChange change = .frame,
}) => VideoSessionChanged(
  change,
  VideoSessionView(
    session: VideoSessionSnapshot(
      sessionId: 'session',
      deviceId: deviceId,
      name: 'Screen',
      kind: .screen,
      status: .streaming,
    ),
    wake: KeepAwakeSnapshot(deviceId: deviceId),
  ),
);
