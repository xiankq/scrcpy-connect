import 'package:freezed_annotation/freezed_annotation.dart';

import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;

import '../identity/setup_identity.dart';
import 'device_connection_control.dart' show DeviceEndpoint;
import 'device_snapshot.dart';

part 'device_management.freezed.dart';

/// 本机设备记录及其实际交付的连接投影；读取不产生连接或重新执行操作。
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

  FutureOr<List<DeviceSnapshot>> readDevices();
  FutureOr<DeviceSnapshot> readDevice(String id);
  Future<void> renameDevice(String id, String name);
  Future<void> disconnectDevice(String id);
  Future<void> forgetDevice(String id);
  Future<void> cancelConnectionAttempt(String attemptId);
}

abstract interface class DeviceWake {
  /// 仅确认 WAKEUP 命令退出成功；屏幕是否点亮或解锁须独立读取。
  Future<DeviceWakeReceipt> wakeDevice(String id, {String? connectionId});
}

enum DeviceWakeEvidence { shellExitSuccess, legacyShellExitSuccess }

@freezed
abstract class DeviceWakeReceipt with _$DeviceWakeReceipt {
  const factory DeviceWakeReceipt({
    required String deviceId,
    required String connectionId,
    required DeviceWakeEvidence evidence,
  }) = _DeviceWakeReceipt;
}
