import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import 'generated/design_tokens.g.dart';
import 'connect_theme.dart';
import 'glass_preferences.dart';
import 'glass_geometry.dart';

/// regular 区分浮动控件与内容，clear 用于媒体上方。
enum GlassVariant { regular, clear }

/// 在启动错误处理范围内初始化生产 shader 后端。
abstract final class GlassMaterial {
  static Future<void>? _initialization;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;
  static const backend = 'liquid_glass_widgets';
  static const backendVersion = '1.15.0';
  static const samplingBounds = 'surface-rect-with-optical-headroom';
  static const composition =
      'component-owned-navigation-and-local-surface-groups';

  static Future<void> initialize() {
    if (!ImageFilter.isShaderFilterSupported) return Future<void>.value();
    return _initialization ??=
        liquid.LiquidGlassWidgets.initialize(
              enablePerformanceMonitor: false,
              warmUpMode: liquid.GlassWarmUpMode.always,
            )
            .then((_) {
              _initialized = true;
            })
            .catchError((Object error, StackTrace stack) {
              _initialization = null;
              Error.throwWithStackTrace(error, stack);
            });
  }

  // 只配置官方组件；这些方法不构建 widget，不替换库的手势、焦点或组件生命周期。
  static bool opaque(BuildContext context) => opaqueGlass(context);

  static bool reduceMotion(BuildContext context) =>
      liquid.GlassAccessibilityData.of(context).reduceMotion;

  static liquid.GlassThemeData theme(BuildContext context) {
    final theme = liquid.GlassThemeData.of(context);
    return theme.copyWith(
      interaction: theme.interaction.copyWith(
        stretch: reduceMotion(context)
            ? 0
            : DesignTokens.componentGlassInteractionStretch,
      ),
    );
  }

  static liquid.GlassQuality quality(BuildContext context) =>
      opaque(context) || !ImageFilter.isShaderFilterSupported
      ? liquid.GlassQuality.minimal
      : liquid.GlassQuality.premium;

  static liquid.LiquidGlassSettings settings(
    BuildContext context, {
    GlassVariant variant = GlassVariant.regular,
  }) {
    final settings = Glass.optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    return quality(context) == liquid.GlassQuality.minimal
        ? settings.copyWith(
            blur: 0,
            glassColor: Theme.of(context).colorScheme.surface,
            bodyMode: liquid.GlassBodyMode.clear,
          )
        : settings;
  }

  static double navigationHeight(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge!;
    return math.max(
      DesignTokens.componentNavigationHeight,
      DesignTokens.componentIconSize +
          DesignTokens.spacingMicro +
          MediaQuery.textScalerOf(context).scale(label.fontSize!) *
              label.height! +
          2 * DesignTokens.componentNavigationPadding,
    );
  }

  /// 标签栏局部 clear 镜片，与 regular 玻璃轨道分开。
  static liquid.LiquidGlassSettings navigationLensSettings(
    BuildContext context,
  ) => opaque(context)
      ? settings(context).copyWith(glassColor: DesignTokens.colorTransparent)
      : liquid.AnimatedGlassIndicator.baseIndicatorSettings;

  static bool restingNavigationLens(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light &&
      quality(context) == liquid.GlassQuality.premium;

  /// 唯一 regular 导航轨道，先于选择镜片和图标绘制，避免静止镜片采样自身前景标签。
  static liquid.LiquidGlassSettings navigationTrackSettings(
    BuildContext context,
  ) => settings(context).copyWith(
    shadow: !opaque(context) && Theme.of(context).brightness == Brightness.light
        ? const [
            BoxShadow(
              color: ConnectTokens.shadow,
              blurRadius: ConnectTokens.shadowBlur,
              offset: Offset(0, ConnectTokens.shadowOffset),
            ),
          ]
        : const [],
  );

  /// 前景栏保留库的手势和移动镜片。
  /// premium 三层路径中，同时为零的深度和模糊选择无光学快速路径；仅透明仍会绘制玻璃轨道。
  static liquid.LiquidGlassSettings navigationBarSettings(
    BuildContext context,
  ) => restingNavigationLens(context)
      ? settings(context).copyWith(
          thickness: 0,
          blur: 0,
          glassColor: DesignTokens.colorTransparent,
          backerColor: DesignTokens.colorTransparent,
          bodyMode: liquid.GlassBodyMode.clear,
          shadow: const [],
        )
      : navigationTrackSettings(context);

  /// 向后端注册 Material 明暗模式和系统辅助偏好。
  /// 背景采样组只属于局部控件组，不能放在根 Navigator。
  static Widget wrap({required Widget child}) => liquid.LiquidGlassWidgets.wrap(
    child: child,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

/// 共享单次 SDF 与折射的光学平面。
/// 同变体组加入外层平面，不同变体分离；作用域限于当前页面，不能跨 Navigator 或保留标签页。
class GlassSurfaceGroup extends StatelessWidget {
  const GlassSurfaceGroup({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  }) : _isolated = false;

  /// 即使 OverlayPortal 保留来源工具栏的继承组，覆盖层仍拥有新采样平面，不加入来源平面。
  const GlassSurfaceGroup.isolated({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  }) : _isolated = true;
  final Widget child;
  final GlassVariant variant;
  final EdgeInsets clipExpansion;
  final bool _isolated;

  @override
  Widget build(BuildContext context) {
    if (opaqueGlass(context) || !ImageFilter.isShaderFilterSupported) {
      return child;
    }
    final enclosing = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
    if (!_isolated && enclosing?.variant == variant) return child;
    return boundGlassSampling(
      liquid.GlassBackdropGroup(
        child: liquid.AdaptiveLiquidGlassLayer(
          settings: Glass.optics(
            brightness: Theme.of(context).brightness,
            variant: variant,
          ),
          quality: liquid.GlassQuality.premium,
          // 混合值是几何距离，来自同一光学边缘 token。
          blendAmount: DesignTokens.componentGlassRefractionWidth,
          clipBehavior: Clip.none,
          clipExpansion: clipExpansion,
          child: _GlassGroup(variant: variant, child: child),
        ),
      ),
      expansion: clipExpansion,
    );
  }
}

class _GlassGroup extends InheritedWidget {
  const _GlassGroup({required this.variant, required super.child});
  final GlassVariant variant;
  @override
  bool updateShouldNotify(_GlassGroup oldWidget) =>
      variant != oldWidget.variant;
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedLg,
    this.padding = EdgeInsets.zero,
    this.solid = false,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  });
  final Widget child;
  final EdgeInsets clipExpansion;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool solid;
  final GlassVariant variant;

  /// 后端配置采用项目光学深度、色调和光照 token。
  /// 旧后端的折射带宽度不等同于厚度。
  static liquid.LiquidGlassSettings optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
    double radius = DesignTokens.roundedLg,
  }) {
    final dark = brightness == Brightness.dark;
    final clear = variant == GlassVariant.clear;
    return liquid.LiquidGlassSettings(
      thickness: DesignTokens.componentGlassOpticalDepth,
      refractiveIndex: ConnectTokens.glassRefractionIndex,
      chromaticAberration: ConnectTokens.glassDispersion,
      saturation: ConnectTokens.glassSaturation,
      blur: clear
          ? DesignTokens.componentGlassClearBlur
          : ConnectTokens.glassBlur,
      bodyMode: clear
          ? liquid.GlassBodyMode.clear
          : liquid.GlassBodyMode.adaptive,
      glassColor: clear
          ? (dark
                ? DesignTokens.colorGlassClearDark
                : DesignTokens.colorGlassClear)
          : (dark ? ConnectTokens.glassDark : ConnectTokens.glass),
      lightAngle: DesignTokens.componentGlassAngle * math.pi / 180,
      lightIntensity: DesignTokens.componentGlassSpecularIntensity,
      glowIntensity: DesignTokens.componentGlassGlowIntensity,
      shadow: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = opaqueGlass(context, solid: solid);
    final style = optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? Theme.of(context).colorScheme.surface : null,
        borderRadius: BorderRadius.circular(radius),
        border: opaque
            ? Border.all(color: Theme.of(context).colorScheme.outline)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    Widget surface;
    if (opaque) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    } else if (ImageFilter.isShaderFilterSupported) {
      if (!GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final shape = liquid.LiquidRoundedSuperellipse(borderRadius: radius);
      final group = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
      surface = group?.variant == variant
          ? liquid.AdaptiveGlass.grouped(
              shape: shape,
              quality: liquid.GlassQuality.premium,
              child: content,
            )
          : liquid.AdaptiveGlass(
              shape: shape,
              settings: style,
              quality: liquid.GlassQuality.premium,
              allowElevation: false,
              clipExpansion: clipExpansion,
              child: content,
            );
      surface = boundGlassSampling(surface, expansion: clipExpansion);
    } else {
      // Widget 测试及不支持 shader 的后端保留明确的磨砂回退。
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: style.blur, sigmaY: style.blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.glassColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: dark
                    ? ConnectTokens.glassEdgeDark
                    : ConnectTokens.glassEdge,
              ),
            ),
            child: content,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: dark ? ConnectTokens.shadowDark : ConnectTokens.shadow,
            blurRadius: ConnectTokens.shadowBlur,
            offset: const Offset(0, ConnectTokens.shadowOffset),
          ),
        ],
      ),
      child: surface,
    );
  }
}
