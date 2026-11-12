import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';

export 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';

/// 设备记录保存观察意图；当前连接拥有监听和本代状态。
/// 只读操作不会建立连接、部署互联服务或恢复已停止的观察。
abstract interface class DeviceObservation {
  Future<List<DeviceObservationSnapshot>> readObservations({
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> readObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> startObservation(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  });
  Future<DeviceObservationSnapshot> stopObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}
