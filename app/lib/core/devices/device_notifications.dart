import 'package:adb/adb.dart' show AdbCancellation;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_notifications.freezed.dart';
part 'device_notifications.g.dart';

/// 定位回执不证明原应用已显示或内容已读；画面接续由 Widget 持有。
typedef DeviceNotificationOpening = ({bool located, String? message});

abstract interface class DeviceNotifications {
  /// 只读取本次观察，不部署服务或恢复已停止的观察。
  Future<DeviceNotificationsSnapshot> readNotifications(
    String deviceId, {
    AdbCancellation? cancellation,
  });

  /// notificationId 是手机签发的不透明引用；失效或需认证时不会重放。
  Future<DeviceNotificationOpening> openNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  });

  /// true 仅表示手机已确认移除；false 仍待核对，均不代表原应用已读。
  Future<bool> dismissNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  });
}

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
    @Default([]) List<DeviceNotification> notifications,
    String? reason,
  }) = _DeviceNotificationsSnapshot;
  factory DeviceNotificationsSnapshot.fromJson(Map<String, dynamic> json) =>
      _$DeviceNotificationsSnapshotFromJson(json);
}
