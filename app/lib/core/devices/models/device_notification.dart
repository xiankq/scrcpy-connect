import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_notification.freezed.dart';
part 'device_notification.g.dart';

enum DeviceNotificationAvailability {
  unknown,
  available,
  limited,
  needsSetup,
  stopped,
  checking,
  starting,
}

@freezed
abstract class DeviceNotification with _$DeviceNotification {
  const factory DeviceNotification({
    required String id,
    String? key,
    String? revision,
    @Default('') String packageName,
    @Default('') String appName,
    @Default('') String title,
    @Default('') String body,
    int? userId,
    int? postedAt,
    @Default(false) bool groupSummary,
    bool? canOpen,
    bool? canDismiss,
  }) = _DeviceNotification;
  factory DeviceNotification.fromJson(Map<String, dynamic> json) =>
      _$DeviceNotificationFromJson(json);
}

@freezed
abstract class DeviceNotificationsSnapshot with _$DeviceNotificationsSnapshot {
  const factory DeviceNotificationsSnapshot({
    required String deviceId,
    @JsonKey(unknownEnumValue: DeviceNotificationAvailability.unknown)
    @Default(DeviceNotificationAvailability.unknown)
    DeviceNotificationAvailability status,
    @Default(false) bool live,
    int? observationEpoch,
    @Default(false) bool observationEnabled,
    @Default(false) bool truncated,
    @Default([]) List<DeviceNotification> notifications,
    String? reason,
  }) = _DeviceNotificationsSnapshot;
  factory DeviceNotificationsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceNotificationsSnapshotFromJson(json);
}

typedef DeviceNotificationOpening = ({bool located, String? message});

extension DeviceNotificationTime on DeviceNotification {
  DateTime? get postedTime => switch (postedAt) {
    final int timestamp when timestamp > 0 && timestamp <= 8640000000000000 =>
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    _ => null,
  };
}
