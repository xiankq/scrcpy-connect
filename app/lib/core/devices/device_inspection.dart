import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_details.dart';

export 'package:scrcpy_connect/core/devices/models/device_details.dart';

/// 每次读取只属于一个实际连接；离线详情仅包含本机稳定信息。
abstract interface class DeviceInspection {
  Future<DeviceReading<DeviceDetails>> readDetails(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
  Future<DeviceReading<DeviceBattery>> readBattery(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
  Future<DeviceReading<DeviceCapacity>> readSharedStorageCapacity(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
  Future<DeviceReading<DeviceScreenState>> readScreenState(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
  Future<DeviceReading<({int width, int height})?>> readScreenSize(
    String deviceId,
  );
  Future<DeviceReading<String>> readForegroundApp(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  });
}
