import 'device_snapshot.dart';

/// 连接查询只依赖实际连接身份、状态和恢复准入，不随设备名称等元数据失效。
final class DeviceReadiness {
  const DeviceReadiness({
    this.connectionId,
    this.status,
    this.recovering = false,
  });
  final String? connectionId;
  final DeviceConnectionStatus? status;
  final bool recovering;

  bool get ready => status == DeviceConnectionStatus.connected && !recovering;

  @override
  bool operator ==(Object other) =>
      other is DeviceReadiness &&
      connectionId == other.connectionId &&
      status == other.status &&
      recovering == other.recovering;

  @override
  int get hashCode => Object.hash(connectionId, status, recovering);
}
