import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';

/// 同一观察代次的生命周期与内容；缓存内容不能单独证明实时观察有效。
final class ObservedDeviceSnapshot {
  ObservedDeviceSnapshot({
    required this.observation,
    required DeviceNotificationsSnapshot notifications,
    required DeviceCallsSnapshot calls,
  }) : notifications = notifications.copyWith(
         notifications: List.unmodifiable(notifications.notifications),
       ),
       calls = calls.copyWith(calls: List.unmodifiable(calls.calls));

  final DeviceObservationSnapshot observation;
  final DeviceNotificationsSnapshot notifications;
  final DeviceCallsSnapshot calls;
}
