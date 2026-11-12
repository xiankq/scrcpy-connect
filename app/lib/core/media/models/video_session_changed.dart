import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

final class VideoSessionChanged extends AppEvent {
  const VideoSessionChanged(this.change, this.view);
  final VideoSessionChange change;
  final VideoSessionView view;

  @override
  String get type => 'session.${change.name}';
  @override
  String get deviceId => view.deviceId;
  @override
  bool get telemetry => change == VideoSessionChange.frame;
}
