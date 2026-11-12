import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';

final class DeviceKeepAwakeChanged extends AppEvent {
  const DeviceKeepAwakeChanged(this.snapshot);
  final KeepAwakeSnapshot snapshot;
  @override
  String get deviceId => snapshot.deviceId;
  @override
  String get type => 'device.keep_active.updated';
}
