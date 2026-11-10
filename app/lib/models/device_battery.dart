import 'dart:convert';

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
