import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';

sealed class DeviceObservationEvent extends AppEvent {
  const DeviceObservationEvent();
  @override
  String get deviceId;
}

final class DeviceObservationChanged extends DeviceObservationEvent {
  const DeviceObservationChanged(this.snapshot);
  final ObservedDeviceSnapshot snapshot;
  @override
  String get deviceId => snapshot.observation.deviceId;
  @override
  String get type => 'observation.changed';
}

final class DeviceNotificationsChanged extends DeviceObservationEvent {
  const DeviceNotificationsChanged(this.snapshot);
  final DeviceNotificationsSnapshot snapshot;
  @override
  String get deviceId => snapshot.deviceId;
  @override
  String get type => 'notifications.changed';
}

final class DeviceCallsChanged extends DeviceObservationEvent {
  const DeviceCallsChanged(this.snapshot, {this.incoming = false});
  final DeviceCallsSnapshot snapshot;
  final bool incoming;
  @override
  String get deviceId => snapshot.deviceId;
  @override
  String get type => incoming ? 'calls.incoming' : 'calls.changed';
}
