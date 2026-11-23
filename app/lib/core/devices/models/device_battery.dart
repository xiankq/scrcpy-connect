import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_battery.freezed.dart';

enum DeviceBatteryStatus { unknown, charging, discharging, notCharging, full }

/// 单次电池事实，电量与充电状态各自读取。
@freezed
abstract class DeviceBattery with _$DeviceBattery {
  const factory DeviceBattery({
    int? level,
    @Default(DeviceBatteryStatus.unknown) DeviceBatteryStatus status,
    int? health,
    double? temperatureC,
    double? voltageMv,
  }) = _DeviceBattery;

  /// 仅解析本次 dumpsys 回执；不由供电方式或旧缓存推断动态状态。
  factory DeviceBattery.fromDumpsys(String text) {
    final fields = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      fields[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
    if (fields['present'] == 'false') return const DeviceBattery();

    double? number(String key) {
      final value = double.tryParse(fields[key] ?? '');
      return value != null && value.isFinite ? value : null;
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

    final level = number('level');
    final scale = number('scale');
    final status = unsigned('status');
    return DeviceBattery(
      level:
          level != null &&
              scale != null &&
              scale > 0 &&
              level >= 0 &&
              level <= scale
          ? (level / scale * 100).round()
          : null,
      status: switch (status) {
        2 => .charging,
        3 => .discharging,
        4 => .notCharging,
        5 => .full,
        _ => .unknown,
      },
      health: unsigned('health'),
      temperatureC: switch (number('temperature')) {
        final value? => value / 10,
        null => null,
      },
      voltageMv: number('voltage'),
    );
  }
}
