import 'dart:convert';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/services/connection/device_query.dart';
import 'package:scrcpy_connect/models/device_record.dart';

/// 本次实际属性查询的结果；空值表示未知，不以设备记录或连接选择器补齐。
final class DeviceFacts {
  const DeviceFacts({
    this.serial,
    this.bootSerial,
    this.model,
    this.androidVersion,
    this.apiLevel,
    this.guid,
  });

  /// 本次 ro.serialno；与 ro.boot.serialno 分别保存，不能跨属性冒充同一身份。
  final String? serial;
  final String? bootSerial;
  final String? model;
  final String? androidVersion;
  final int? apiLevel;
  final String? guid;

  /// 普通重连拒绝已知冲突；修改配置或重新授权还须核验原记录的真实序列号。
  /// 缺失事实不证明原缓存有效；本方法不更新记录，也不证明主控密钥或 TLS 信任。
  void assertMatches(DeviceRecord record, {bool requireKnownSerial = false}) {
    if (record.serial != null && serial != null && record.serial != serial ||
        record.guid != null && guid != null && record.guid != guid) {
      throw const RequestFailure(
        'device_identity_mismatch',
        '连接目标与原设备身份不符，请核对设备。',
      );
    }
    if (requireKnownSerial && (record.serial == null || serial == null)) {
      throw const RequestFailure(
        'device_identity_unverified',
        '无法核验原设备身份，请检查设备授权与连接。',
      );
    }
  }
}

/// 单次电池事实，未知电量、充电状态及供电方式不能相互推断。
final class DeviceBattery {
  const DeviceBattery({
    this.level,
    this.charging,
    this.status,
    this.health,
    this.temperatureC,
    this.voltageMv,
  });

  /// 仅解析本次 dumpsys 回执；不由供电方式或旧缓存推断动态状态。
  factory DeviceBattery.fromDumpsys(String text) {
    double? number(String key) {
      for (final line in const LineSplitter().convert(text)) {
        final field = line.trim();
        if (!field.startsWith(key)) continue;
        final value = double.tryParse(field.substring(key.length).trim());
        if (value != null && value.isFinite) return value;
      }
      return null;
    }

    int? unsigned(String key) {
      final value = number(key);
      return value != null &&
              value >= 0 &&
              value <= 0xffffffff &&
              value == value.truncateToDouble()
          ? value.toInt()
          : null;
    }

    final level = number('level:');
    final scale = number('scale:');
    final status = unsigned('status:');
    return DeviceBattery(
      level:
          level != null &&
              scale != null &&
              scale > 0 &&
              level >= 0 &&
              level <= scale
          ? (level / scale * 100).round()
          : null,
      charging: switch (status) {
        2 => true,
        3 || 4 || 5 => false,
        _ => null,
      },
      status: status,
      health: unsigned('health:'),
      temperatureC: switch (number('temperature:')) {
        final value? => value / 10,
        null => null,
      },
      voltageMv: number('voltage:'),
    );
  }

  final int? level;
  final bool? charging;
  final int? status;
  final int? health;
  final double? temperatureC;
  final double? voltageMv;
}

/// 通过固定只读命令探测精确连接，不持有设备记录或发布业务状态。
/// 调用方应在返回后核对 ConnectionOwner 代次，再接纳事实或更新缓存。
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
