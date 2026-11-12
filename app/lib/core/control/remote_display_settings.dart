import 'package:scrcpy_connect/core/settings/preferences.dart';

import 'dart:math' as math;

import 'dart:ui' show Size;

/// 在此解析设备偏好，原生执行层只接收具体像素。
class RemoteDisplaySettings {
  const RemoteDisplaySettings(this.values);
  final DevicePreferences values;

  String get mode => values.remoteAspectRatio?.wire ?? 'original';
  String get label => switch (mode) {
    'auto' => '自动适应',
    '9:16' => '9:16',
    '3:4' => '3:4',
    '1:1' => '1:1',
    '16:9' => '16:9',
    'custom' => values.remoteCustomRatio ?? '9:16',
    _ => '原始比例',
  };

  static double? parseRatio(String text) {
    final parts = text.trim().split(RegExp(r'[:：/]'));
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0].trim());
    final height = double.tryParse(parts[1].trim());
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    final ratio = width / height;
    return ratio >= .2 && ratio <= 5 ? ratio : null;
  }

  /// 视口是导航与安全区扣除后的 Scaffold 内容区，输入法出现不重定义显示尺寸。
  ({int width, int height})? dimensions(Size viewport) {
    var ratio = switch (mode) {
      'original' => null,
      'auto' =>
        viewport.width > 0 && viewport.height > 0
            ? viewport.width / viewport.height
            : null,
      'custom' => parseRatio(values.remoteCustomRatio ?? '9:16'),
      _ => parseRatio(mode),
    };
    if (ratio == null || !ratio.isFinite || ratio <= 0) {
      return null;
    }
    if (mode == 'auto') {
      ratio = ratio.clamp(320 / 4096, 4096 / 320);
    } else if (ratio < .2 || ratio > 5) {
      return null;
    }
    final longSide = math
        .max(1920, (320 * math.max(ratio, 1 / ratio) / 2).ceil() * 2)
        .clamp(1920, 4096);
    int even(double value) => math.max(320, (value / 2).round() * 2);
    return ratio > 1
        ? (width: longSide, height: even(longSide / ratio))
        : (width: even(longSide * ratio), height: longSide);
  }
}
