import 'dart:async';

import 'package:adb/adb.dart';

/// 一次实际连接及其 SDK 所有者；业务记录 ID 不进入原生连接登记表。
final class DeviceConnection {
  const DeviceConnection({
    required this.client,
    required this.device,
    this.releasePlatformResources,
  });
  final AdbClient client;
  final AdbDevice device;

  /// 此精确连接借用的平台传输资源，只在 SDK 实际断开成功后释放。
  /// 失败时保留回调与退休记录，后续重试不得重新断开已确认释放的传输。
  final Future<void> Function()? releasePlatformResources;
}
