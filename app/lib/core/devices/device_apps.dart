import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_app.dart';

export 'package:scrcpy_connect/core/devices/models/device_app.dart';

abstract interface class DeviceApps {
  Future<List<DeviceApp>> readInstalledApps(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<RunningDeviceApps> readRunningApps(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  });
  Future<DeviceAppIcon> readAppIcon(
    String deviceId,
    String packageName, {
    int? userId,
    bool allowStart = true,
    AdbCancellation? cancellation,
  });
}
