import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';

/// 设备所有者发布的完整投影；记录、连接与身份变化共同使用这一份事实。
/// 不是设备序列化协议，消费者无需重新读取或重新解析设备字段。
final class DeviceListChanged extends AppEvent {
  DeviceListChanged(Iterable<DeviceSnapshot> devices)
    : devices = List.unmodifiable(devices);

  final List<DeviceSnapshot> devices;
  @override
  String get type => 'devices.changed';
}
