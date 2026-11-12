import 'package:scrcpy_connect/core/devices/models/device_reconnect_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

sealed class DeviceReconnectEvent {
  const DeviceReconnectEvent({this.sequence});
  final int? sequence;
}

final class DeviceReconnectInvalidated extends DeviceReconnectEvent {
  const DeviceReconnectInvalidated();
}

final class DeviceReconnectRecovered extends DeviceReconnectEvent {
  DeviceReconnectRecovered(this.snapshot) : super(sequence: snapshot.sequence);
  final DeviceReconnectSnapshot snapshot;
}

final class DeviceReconnectDevicesChanged extends DeviceReconnectEvent {
  DeviceReconnectDevicesChanged(
    List<DeviceSnapshot> devices, {
    required int sequence,
  }) : devices = immutableDeviceSnapshots(devices),
       super(sequence: sequence);
  final List<DeviceSnapshot> devices;
}

final class DeviceReconnectSettingsChanged extends DeviceReconnectEvent {
  const DeviceReconnectSettingsChanged(
    this.backgroundKeepAlive, {
    required int sequence,
  }) : super(sequence: sequence);
  final bool backgroundKeepAlive;
}

final class DeviceReconnectDiscoveryChanged extends DeviceReconnectEvent {
  const DeviceReconnectDiscoveryChanged(this.guid, {required int sequence})
    : super(sequence: sequence);
  final String? guid;
}

final class DeviceReconnectStopped extends DeviceReconnectEvent {
  const DeviceReconnectStopped({required int sequence})
    : super(sequence: sequence);
}

/// 其他业务变化同样推进水位，迟到的旧投影不能覆盖新状态。
final class DeviceReconnectWatermark extends DeviceReconnectEvent {
  const DeviceReconnectWatermark({required int sequence})
    : super(sequence: sequence);
}
