import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

GlassEffects platformGlassEffects(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => GlassEffects.premium,
      TargetPlatform.windows => GlassEffects.off,
      _ => GlassEffects.standard,
    };

/// 将应用偏好接入官方辅助功能作用域。
///
/// 降低透明度只把玻璃换成同尺寸实体面，按压膨胀等动效不变；减少动态由系统偏好关闭。
class GlassPreferences extends StatelessWidget {
  const GlassPreferences({
    super.key,
    required this.reduceTransparency,
    this.effects = GlassEffects.automatic,
    required this.child,
  });
  final bool reduceTransparency;
  final GlassEffects effects;
  final Widget child;
  static GlassEffects effectsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassPreferences>()
          ?.effects ??
      platformGlassEffects(defaultTargetPlatform);

  static bool isOpaque(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassPreferences>()?.opaque ??
      platformGlassEffects(defaultTargetPlatform) == GlassEffects.off;

  static liquid.GlassQuality qualityFor(GlassEffects effects) =>
      switch (effects) {
        GlassEffects.off => liquid.GlassQuality.minimal,
        GlassEffects.premium when ImageFilter.isShaderFilterSupported =>
          liquid.GlassQuality.premium,
        _ => liquid.GlassQuality.standard,
      };

  @override
  Widget build(BuildContext context) {
    final resolved = effects == GlassEffects.automatic
        ? platformGlassEffects(defaultTargetPlatform)
        : effects;
    final opaque =
        resolved == GlassEffects.off ||
        reduceTransparency ||
        MediaQuery.highContrastOf(context) ||
        liquid.GlassAccessibilityData.of(context).reduceTransparency;
    return _GlassPreferences(
      effects: resolved,
      opaque: opaque,
      child: liquid.GlassAccessibilityScope(
        reduceTransparency: opaque,
        child: liquid.GlassTheme(
          data: liquid.GlassThemeData.simple(
            quality: opaque
                ? liquid.GlassQuality.minimal
                : qualityFor(resolved),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassPreferences extends InheritedWidget {
  const _GlassPreferences({
    required this.effects,
    required this.opaque,
    required super.child,
  });
  final GlassEffects effects;
  final bool opaque;
  @override
  bool updateShouldNotify(_GlassPreferences oldWidget) =>
      effects != oldWidget.effects || opaque != oldWidget.opaque;
}

bool opaqueGlass(BuildContext context, {bool solid = false}) =>
    solid ||
    GlassPreferences.isOpaque(context) ||
    liquid.GlassAccessibilityData.of(context).reduceTransparency ||
    MediaQuery.highContrastOf(context);
