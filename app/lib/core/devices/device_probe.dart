import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_query.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_facts.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 通过固定只读命令探测精确连接，不持有设备记录或发布业务状态。
/// 调用方应在返回后核对 DeviceConnectionPool 代次，再接纳事实或更新缓存。
final class DeviceProbe {
  const DeviceProbe();

  // 属性值使用独立 NUL 边界，不能让多行型号或异常输出改变后续身份字段的位置。
  static const _identityCommand = r'''for property in ro.serialno ro.boot.serialno ro.product.model ro.build.version.release ro.build.version.sdk persist.adb.tls_server.guid; do
value=$(getprop "$property") || exit
printf '%s\000' "$value"
done''';

  Future<DeviceFacts> readIdentity(
    DeviceConnection connection, {
    AdbCancellation? cancellation,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final text = await readDeviceText(
      connection,
      _identityCommand,
      cancellation: cancellation,
      timeout: timeout,
      maxBytes: 64 * 1024,
    );
    cancellation?.check();
    final fields = text.split('\x00');
    if (fields.length != 7 || fields.last.isNotEmpty) {
      throw const RequestFailure('invalid_data', '设备属性回执不完整或边界无效。');
    }
    final serial = _property(fields[0]);
    final bootSerial = _property(fields[1]);
    final api = int.tryParse(fields[4].trim(), radix: 10);
    return DeviceFacts(
      serial: serial,
      bootSerial: bootSerial,
      model: _property(fields[2]),
      androidVersion: _property(fields[3]),
      apiLevel: api != null && api >= 0 && api <= 0xffffffff ? api : null,
      guid: _property(fields[5]),
    );
  }

  /// 可选查询独立于身份准入；本方法不会触发身份探测或沿用旧电量。
  Future<DeviceBattery> readBattery(
    DeviceConnection connection, {
    AdbCancellation? cancellation,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final text = await readDeviceText(
      connection,
      'dumpsys battery',
      cancellation: cancellation,
      timeout: timeout,
      maxBytes: 64 * 1024,
    );
    cancellation?.check();
    return DeviceBattery.fromDumpsys(text);
  }
}

String? _property(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value == 'unknown' || value == 'null') return null;
  if (value.length > 256 ||
      value.runes.any((c) => c < 32 || c >= 127 && c <= 159)) {
    throw const RequestFailure('invalid_data', '设备属性包含无效或过长内容。');
  }
  return value;
}
