import 'package:adb/adb.dart' show AdbCancellation;
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';

export 'package:scrcpy_connect/core/devices/models/device_notification.dart';

/// 定位回执不证明原应用已显示或内容已读；画面接续由 Widget 持有。

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
