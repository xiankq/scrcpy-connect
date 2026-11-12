import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

/// 自动重连只读事实；不借用媒体、文件或全应用恢复快照。
final class DeviceReconnectSnapshot {
  DeviceReconnectSnapshot({
    required this.sequence,
    required List<DeviceSnapshot> devices,
    required this.backgroundKeepAlive,
  }) : assert(sequence >= 0),
       devices = immutableDeviceSnapshots(devices);

  final int sequence;
  final List<DeviceSnapshot> devices;
  final bool backgroundKeepAlive;
}
