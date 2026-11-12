import 'package:freezed_annotation/freezed_annotation.dart';

import 'dart:convert';

part 'device_battery.freezed.dart';

/// 单次电池事实，未知电量、充电状态及供电方式不能相互推断。
@freezed
abstract class DeviceBattery with _$DeviceBattery {
  const factory DeviceBattery({
    int? level,
    bool? charging,
    int? status,
    int? health,
    double? temperatureC,
    double? voltageMv,
  }) = _DeviceBattery;

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
}
