import 'package:scrcpy_connect/core/events/models/app_event.dart';

/// 停止精确会话的意图先于异步释放交付，阻止迟到回执重新打开画面。
final class VideoStopRequested extends AppEvent {
  const VideoStopRequested(this.sessionId);

  final String sessionId;
  @override
  String get type => 'session.stop.requested';
}
