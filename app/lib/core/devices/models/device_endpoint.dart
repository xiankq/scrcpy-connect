import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

part 'device_endpoint.freezed.dart';

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
