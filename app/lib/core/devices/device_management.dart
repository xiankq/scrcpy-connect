import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/device_connection_control.dart'
    show DeviceEndpoint;
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_wake_receipt.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

export 'package:scrcpy_connect/core/devices/models/device_wake_receipt.dart';

/// 设备记录及连接的修改操作；跨能力取消和清理由操作所有者协调。
abstract interface class DeviceManagement {
  /// 创建手动连接记录并绑定本次身份；保存记录不代表已连接或已授权。
  Future<DeviceSnapshot> addDevice(
    DeviceEndpoint endpoint, {
    String name = 'Android 设备',
    SetupIdentity? identity,
    AdbCancellation? cancellation,
  });

  /// 只更新已有离线记录的端点；在线或正在连接时须使用配置核验流程。
  Future<DeviceSnapshot> updateDeviceEndpoint(
    String deviceId,
    DeviceEndpoint endpoint, {
    AdbCancellation? cancellation,
  });

  Future<void> renameDevice(String id, String name);
  Future<void> disconnectDevice(String id);
  Future<void> forgetDevice(String id);
  Future<void> cancelConnectionAttempt(String attemptId);
}

abstract interface class DeviceWake {
  /// 仅确认 WAKEUP 命令退出成功；屏幕是否点亮或解锁须独立读取。
  Future<DeviceWakeReceipt> wakeDevice(String id, {String? connectionId});
}
