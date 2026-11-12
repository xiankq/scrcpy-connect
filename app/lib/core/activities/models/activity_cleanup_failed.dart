import 'package:scrcpy_connect/core/events/models/app_event.dart';

/// 资源仍由原模块保留和重试；通知不能代替已完成清理的回执。
final class ActivityCleanupFailed extends AppEvent {
  const ActivityCleanupFailed(this.reason);

  final String reason;
  @override
  String get type => 'activity.cleanup.failed';
}
