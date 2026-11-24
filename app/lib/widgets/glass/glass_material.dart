import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_geometry.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

enum GlassVariant { regular, pill, menu, alert, clear }

/// 在启动错误处理范围内初始化生产 shader 后端。
abstract final class GlassMaterial {
  static Future<void>? _initialization;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> initialize() {
    return _initialization ??=
        liquid.LiquidGlassWidgets.initialize(
              enablePerformanceMonitor: false,
              warmUpMode: ImageFilter.isShaderFilterSupported
                  ? liquid.GlassWarmUpMode.always
                  : liquid.GlassWarmUpMode.auto,
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
  static bool reduceMotion(BuildContext context) =>
      liquid.GlassAccessibilityData.of(context).reduceMotion;

  static liquid.GlassQuality quality(BuildContext context) =>
      opaqueGlass(context)
      ? liquid.GlassQuality.minimal
      : GlassPreferences.qualityFor(GlassPreferences.effectsOf(context));

  static liquid.LiquidGlassSettings settings(
    BuildContext context, {
    GlassVariant variant = GlassVariant.regular,
  }) {
    final theme = Theme.of(context);
    final settings = Glass.optics(
      brightness: theme.brightness,
      variant: variant,
    );
    return quality(context) == liquid.GlassQuality.minimal
        ? settings.copyWith(
            blur: 0,
            frost: 0,
            bodyShade: 0,
            glassColor: _solidColor(theme, variant),
            bodyMode: liquid.GlassBodyMode.clear,
          )
        : settings;
  }

  static double navigationHeight(BuildContext context) {
    final label = Theme.of(context).textTheme.bodySmall!;
    return math.max(
      DesignTokens.componentNavigationHeight,
      DesignTokens.componentToolGlyphSize +
          DesignTokens.spacingMicro +
          MediaQuery.textScalerOf(context).scale(label.fontSize!) *
              label.height! +
          2 * DesignTokens.componentNavigationPadding,
    );
  }

  /// 实体导航保留指示器和几何，玻璃档位沿用库的镜片材质。
  static liquid.LiquidGlassSettings? navigationIndicatorSettings(
    BuildContext context,
  ) => opaqueGlass(context)
      ? settings(context).copyWith(glassColor: DesignTokens.colorTransparent)
      : null;

  /// 向后端注册 Material 明暗模式和系统辅助偏好。
  /// 背景采样组只属于局部控件组，不能放在根 Navigator。
  static Widget wrap({required Widget child}) => liquid.LiquidGlassWidgets.wrap(
    child: child,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

/// 共享单次 SDF 与折射的光学平面。
/// 同变体组加入外层平面，不同变体分离；作用域限于当前页面，不能跨 Navigator 或保留标签页。
class GlassSurfaceGroup extends StatefulWidget {
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
  State<GlassSurfaceGroup> createState() => _GlassSurfaceGroupState();

  Widget _build(BuildContext context, Widget child) {
    if (opaqueGlass(context)) {
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
          quality: GlassMaterial.quality(context),
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

class _GlassSurfaceGroupState extends State<GlassSurfaceGroup> {
  // 材料切换会改变包装层级；内容只重挂载，保留焦点、滚动与业务状态。
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) => widget._build(
    context,
    KeyedSubtree(key: _contentKey, child: widget.child),
  );
}

class _GlassGroup extends InheritedWidget {
  const _GlassGroup({required this.variant, required super.child});
  final GlassVariant variant;
  @override
  bool updateShouldNotify(_GlassGroup oldWidget) =>
      variant != oldWidget.variant;
}

class Glass extends StatefulWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedLg,
    this.padding = EdgeInsets.zero,
    this.solid = false,
    this.showShadow = true,
    this.variant = GlassVariant.regular,
    this.circular = false,
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  });
  final Widget child;
  final EdgeInsets clipExpansion;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool solid;
  final bool circular;

  /// Toolbars turn this off when their parent has a sampling edge, so the
  /// edge never crops a button shadow.
  final bool showShadow;
  final GlassVariant variant;

  @override
  State<Glass> createState() => _GlassState();

  /// 使用库的明暗镜片和采样模型，并应用设计稿各材质的光学参数。
  static liquid.LiquidGlassSettings optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
  }) {
    final dark = brightness == Brightness.dark;
    final clear = variant == GlassVariant.clear;
    final base = dark
        ? liquid.LiquidGlassSettings.ios27Dark
        : liquid.LiquidGlassSettings.ios27Light;
    final (tint, opticalDepth, blur, refraction, light) = switch (variant) {
      GlassVariant.regular => (
        dark
            ? DesignTokens.componentGlassRegularDarkBackgroundColor
            : DesignTokens.componentGlassRegularBackgroundColor,
        DesignTokens.componentGlassRegularOpticalDepth,
        DesignTokens.componentGlassRegularBlur,
        DesignTokens.componentGlassRegularRefractionIndex,
        DesignTokens.componentGlassRegularSpecularIntensity,
      ),
      GlassVariant.pill => (
        dark
            ? DesignTokens.componentNavigationDarkBackgroundColor
            : DesignTokens.componentNavigationBackgroundColor,
        DesignTokens.componentGlassPillOpticalDepth,
        DesignTokens.componentGlassPillBlur,
        DesignTokens.componentGlassPillRefractionIndex,
        DesignTokens.componentGlassPillSpecularIntensity,
      ),
      GlassVariant.menu => (
        dark
            ? DesignTokens.componentGlassMenuDarkBackgroundColor
            : DesignTokens.componentGlassMenuBackgroundColor,
        DesignTokens.componentGlassMenuOpticalDepth,
        DesignTokens.componentGlassMenuBlur,
        DesignTokens.componentGlassMenuRefractionIndex,
        DesignTokens.componentGlassMenuSpecularIntensity,
      ),
      GlassVariant.alert => (
        dark
            ? DesignTokens.componentGlassAlertDarkBackgroundColor
            : DesignTokens.componentGlassAlertBackgroundColor,
        DesignTokens.componentGlassAlertOpticalDepth,
        DesignTokens.componentGlassAlertBlur,
        DesignTokens.componentGlassAlertRefractionIndex,
        DesignTokens.componentGlassAlertSpecularIntensity,
      ),
      GlassVariant.clear => (
        DesignTokens.componentGlassClearBackgroundColor,
        DesignTokens.componentGlassClearOpticalDepth,
        DesignTokens.componentGlassClearBlur,
        DesignTokens.componentGlassClearRefractionIndex,
        DesignTokens.componentGlassClearSpecularIntensity,
      ),
    };
    return base.copyWith(
      blur: blur,
      thickness: opticalDepth,
      refractiveIndex: refraction,
      lightIntensity: light,
      frost: clear ? 0 : null,
      bodyShade: clear ? 0 : null,
      saturation: clear ? 1 : null,
      bodyMode: clear ? liquid.GlassBodyMode.clear : null,
      glassColor: tint,
      shadow: const [],
    );
  }

  Widget _build(BuildContext context, GlobalKey contentKey) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final opaque = opaqueGlass(context, solid: solid);
    final style = optics(brightness: theme.brightness, variant: variant);
    final content = KeyedSubtree(
      key: contentKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: opaque ? _solidColor(theme, variant) : null,
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : BorderRadius.circular(radius),
          border: opaque && MediaQuery.highContrastOf(context)
              ? Border.all(color: theme.colorScheme.outline)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    Widget surface;
    if (opaque) {
      surface = circular
          ? ClipOval(child: content)
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: content,
            );
    } else {
      if (ImageFilter.isShaderFilterSupported && !GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final shape = circular
          ? const liquid.LiquidOval()
          : liquid.LiquidRoundedSuperellipse(borderRadius: radius);
      final group = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
      surface = group?.variant == variant
          ? liquid.AdaptiveGlass.grouped(
              shape: shape,
              quality: GlassMaterial.quality(context),
              child: content,
            )
          : liquid.AdaptiveGlass(
              shape: shape,
              settings: style,
              quality: GlassMaterial.quality(context),
              allowElevation: false,
              clipExpansion: clipExpansion,
              child: content,
            );
      surface = boundGlassSampling(surface, expansion: clipExpansion);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(radius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: dark ? ConnectTokens.shadowDark : ConnectTokens.shadow,
                  blurRadius: ConnectTokens.shadowBlur,
                  offset: const Offset(0, ConnectTokens.shadowOffset),
                ),
              ]
            : const [],
      ),
      child: surface,
    );
  }
}

Color _solidColor(ThemeData theme, GlassVariant variant) => switch (variant) {
  GlassVariant.menu || GlassVariant.alert =>
    theme.brightness == Brightness.dark
        ? DesignTokens.componentFloatingSurfaceDarkBackgroundColor
        : DesignTokens.componentFloatingSurfaceBackgroundColor,
  GlassVariant.regular ||
  GlassVariant.pill => theme.colorScheme.surfaceContainerHighest,
  GlassVariant.clear => theme.colorScheme.surface,
};

class _GlassState extends State<Glass> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) => widget._build(context, _contentKey);
}
