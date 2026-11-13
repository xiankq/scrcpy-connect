import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

/// 提醒资格使用同次状态提交的只读投影，不执行应用操作。
class SystemNotificationSnapshot {
  const SystemNotificationSnapshot({
    required this.devices,
    required this.settings,
    required this.loading,
    required this.reconciliationPending,
  });

  final List<DeviceSnapshot> devices;
  final Preferences settings;
  final bool loading;
  final bool reconciliationPending;
}
