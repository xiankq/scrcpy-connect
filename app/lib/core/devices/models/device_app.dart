import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_app.freezed.dart';

@freezed
abstract class DeviceApp with _$DeviceApp {
  const factory DeviceApp({
    required String packageName,
    required String name,
    @Default(false) bool system,
    int? taskId,
    int? userId,
  }) = _DeviceApp;
}

@freezed
abstract class RunningDeviceApps with _$RunningDeviceApps {
  const factory RunningDeviceApps({
    required String deviceId,
    required List<DeviceApp> apps,
    String? connectionId,
    required int userId,
  }) = _RunningDeviceApps;
}

/// 图标是已核验目标与用户的 PNG；调用方不能修改共享查询中的字节。
final class DeviceAppIcon {
  DeviceAppIcon({
    required this.deviceId,
    required this.packageName,
    required this.userId,
    required Uint8List bytes,
    required this.width,
    required this.height,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String deviceId, packageName;
  final int userId, width, height;
  final Uint8List bytes;
}

/// 查询缓存的结构化 key；同一设备、包与 Android 用户才共享图标。
typedef DeviceAppIconTarget = ({
  String deviceId,
  String packageName,
  int? userId,
});
