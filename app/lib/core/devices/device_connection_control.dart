import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';

export 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';

/// 显式连接意图；自动重连的租约和调度不属于页面可调用的操作。
abstract interface class DeviceConnectionControl {
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  });

  /// 仅在核验实际候选后保存端点；失败仍由原所有者回收精确连接。
  Future<DeviceConnectionReceipt> configureDevice(
    String deviceId,
    DeviceEndpoint endpoint, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  });
}
