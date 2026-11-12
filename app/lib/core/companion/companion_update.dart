import 'package:scrcpy_connect/core/devices/device_connection.dart';

/// 已通过当前部署和精确连接核验的事件；观察意图仍由观察协调器核验。
sealed class CompanionUpdate {
  const CompanionUpdate(this.device, this.connection);
  final String device;
  final DeviceConnection connection;
}

final class CompanionConnectionLost extends CompanionUpdate {
  const CompanionConnectionLost(super.device, super.connection);
}

enum CompanionObservationSection { notifications, calls }

/// 内容是伴生协议的原始分区，在观察所有者的协议适配处解码。
final class CompanionObservationUpdate extends CompanionUpdate {
  const CompanionObservationUpdate(
    super.device,
    super.connection,
    this.section,
    this.data, {
    this.incoming = false,
  });
  final CompanionObservationSection section;
  final Map<String, Object?> data;
  final bool incoming;
}
