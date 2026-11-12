import 'package:scrcpy_connect/core/events/models/app_event.dart';

/// 宿主已停止连接；本地准入撤销后才向应用交付这一事实。
final class ConnectionsStopped extends AppEvent {
  const ConnectionsStopped();
  @override
  String get type => 'connections.stopped';
}
