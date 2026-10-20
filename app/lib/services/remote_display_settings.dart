import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Device preferences are resolved here; native code receives concrete pixels.
class RemoteDisplaySettings {
  const RemoteDisplaySettings(this.values);
  final Map<String, dynamic> values;

  String get mode => values['remoteAspectRatio'] as String? ?? 'original';
  String get label => switch (mode) {
    'auto' => '自动适应',
    '9:16' => '9:16',
    '3:4' => '3:4',
    '1:1' => '1:1',
    '16:9' => '16:9',
    'custom' => '${values['remoteCustomRatio'] ?? '9:16'}',
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

  /// The viewport is the Scaffold body, after navigation and safe areas.
  /// IME appearance does not redefine the chosen display size.
  ({int width, int height})? dimensions(Size viewport) {
    var ratio = switch (mode) {
      'original' => null,
      'auto' =>
        viewport.width > 0 && viewport.height > 0
            ? viewport.width / viewport.height
            : null,
      'custom' => parseRatio('${values['remoteCustomRatio'] ?? '9:16'}'),
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
