import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

/// 音源准入只读取当前连接与核验状态，不接管应用快照。
class DeviceAudioViewSnapshot {
  const DeviceAudioViewSnapshot({
    required this.devices,
    required this.reconciliationPending,
  });

  final List<DeviceSnapshot> devices;
  final bool reconciliationPending;
}
