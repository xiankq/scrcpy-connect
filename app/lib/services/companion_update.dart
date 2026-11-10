import 'package:scrcpy_connect/services/device_connection.dart';

/// 已通过当前部署和精确连接核验的事件；观察意图仍由观察协调器核验。
final class CompanionUpdate {
  const CompanionUpdate(this.device, this.connection, this.type, this.data);
  final String device, type;
  final DeviceConnection connection;
  final Map<String, Object?> data;
}
