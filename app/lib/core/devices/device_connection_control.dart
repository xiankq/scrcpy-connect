import 'package:adb/adb.dart' show AdbCancellation;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'device_snapshot.dart';

part 'device_connection_control.freezed.dart';

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

enum ConnectionCandidateSource { saved, discovery }

@freezed
abstract class DeviceEndpoint with _$DeviceEndpoint {
  const factory DeviceEndpoint({
    required String address,
    required int port,
    @Default(DeviceTransport.tcp) DeviceTransport transport,
  }) = _DeviceEndpoint;
}

/// 连接已经交付的事实，不表示画面或其他设备活动已经启动。
@freezed
abstract class DeviceConnectionReceipt with _$DeviceConnectionReceipt {
  const DeviceConnectionReceipt._();
  const factory DeviceConnectionReceipt({
    required DeviceSnapshot device,
    bool? adbBurstActive,
  }) = _DeviceConnectionReceipt;

  String get deviceId => device.id;
}
