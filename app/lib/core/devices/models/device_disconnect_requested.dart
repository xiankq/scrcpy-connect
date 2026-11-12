import 'package:scrcpy_connect/core/events/models/app_event.dart';

/// 用户明确停止此设备；页面须同步撤销自动恢复及输入意图。
final class DeviceDisconnectRequested extends AppEvent {
  const DeviceDisconnectRequested(this.deviceId);

  @override
  final String deviceId;
  @override
  String get type => 'device.disconnect.requested';
}
