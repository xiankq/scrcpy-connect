import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_capabilities.dart';

export 'package:scrcpy_connect/core/devices/models/device_capabilities.dart';

/// 只解释本次读取的事实；不会为检查功能而创建连接、授权身份或互联服务。
abstract interface class DeviceAssessment {
  Future<DeviceCapabilities> readCapabilities(
    String deviceId, {
    AdbCancellation? cancellation,
  });
  Future<DeviceDiagnosis> diagnoseDevice(
    String deviceId, {
    AdbCancellation? cancellation,
  });
}
