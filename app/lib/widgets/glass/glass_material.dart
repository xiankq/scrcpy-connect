import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_geometry.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// regular 区分浮动控件与内容，clear 用于媒体上方。
enum GlassVariant { regular, clear }

/// 在启动错误处理范围内初始化生产 shader 后端。
abstract final class GlassMaterial {
  static Future<void>? _initialization;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;
  static const backend = 'liquid_glass_widgets';
  static const backendVersion = '1.17.3';
  static const samplingBounds = 'surface-rect-with-optical-headroom';
  static const composition =
      'component-owned-navigation-and-local-surface-groups';

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

  static liquid.GlassQuality quality(BuildContext context) {
    if (opaque(context)) return liquid.GlassQuality.minimal;
    // Premium is the package's Impeller path and matches Apple's iOS 27
    // preset. Other platforms use the documented standard approximation so
    // desktop/Android do not pretend to have the same native material or
    // spend a premium shader budget on every local action group.
    final apple = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
    return apple && ImageFilter.isShaderFilterSupported
        ? liquid.GlassQuality.premium
        : liquid.GlassQuality.standard;
  }

  static liquid.LiquidGlassSettings settings(
    BuildContext context, {
    GlassVariant variant = GlassVariant.regular,
  }) {
    final settings = Glass.optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
      includeShadow: false,
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

  /// 标签栏指示器的局部 clear 材质，与 regular 玻璃轨道分开。
  static liquid.LiquidGlassSettings navigationIndicatorSettings(
    BuildContext context,
  ) => opaque(context)
      ? settings(context).copyWith(glassColor: DesignTokens.colorTransparent)
      : liquid.AnimatedGlassIndicator.baseIndicatorSettings;

  /// The package-owned navigation track and indicator share one optical layer.
  /// Keeping the shadow on that same settings object avoids a second overlay
  /// that can be clipped or disappear while the official indicator settles.
  static liquid.LiquidGlassSettings navigationTrackSettings(
    BuildContext context,
  ) => Glass.optics(
    brightness: Theme.of(context).brightness,
    includeShadow: !opaque(context),
  );

  /// The official bottom bar owns both the track and its moving indicator.
  /// Its preset shadow is resolved by the package so the shadow follows the
  /// same visibility and accessibility state as the platter.
  static liquid.LiquidGlassSettings navigationBarSettings(
    BuildContext context,
  ) => navigationTrackSettings(context);

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
    this.clipExpansion = const EdgeInsets.all(
      DesignTokens.componentGlassRefractionWidth,
    ),
  });
  final Widget child;
  final EdgeInsets clipExpansion;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool solid;

  /// Toolbars turn this off when their parent has a sampling edge, so the
  /// edge never crops a button shadow.
  final bool showShadow;
  final GlassVariant variant;

  @override
  State<Glass> createState() => _GlassState();

  /// 后端配置采用项目光学深度、色调和光照 token。
  /// 旧后端的折射带宽度不等同于厚度。
  static liquid.LiquidGlassSettings optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
    double radius = DesignTokens.roundedLg,
    bool includeShadow = false,
  }) {
    final dark = brightness == Brightness.dark;
    final clear = variant == GlassVariant.clear;
    final base = switch (defaultTargetPlatform) {
      // The package preset tracks Apple's current regular material (including
      // frost, rim shade and paraxial lens terms). Keep the app's clear
      // media variant explicit, but do not replace the regular system optics
      // with a hand-tuned approximation on Apple platforms.
      TargetPlatform.iOS || TargetPlatform.macOS =>
        dark
            ? liquid.LiquidGlassSettings.ios27Dark
            : liquid.LiquidGlassSettings.ios27Light,
      _ => liquid.LiquidGlassSettings(
        thickness: DesignTokens.componentGlassOpticalDepth,
        refractiveIndex: ConnectTokens.glassRefractionIndex,
        chromaticAberration: ConnectTokens.glassDispersion,
        saturation: ConnectTokens.glassSaturation,
        blur: ConnectTokens.glassBlur,
        bodyMode: liquid.GlassBodyMode.adaptive,
        glassColor: dark ? ConnectTokens.glassDark : ConnectTokens.glass,
        lightAngle: DesignTokens.componentGlassAngle * math.pi / 180,
        lightIntensity: DesignTokens.componentGlassSpecularIntensity,
        glowIntensity: DesignTokens.componentGlassGlowIntensity,
      ),
    };
    final resolved = base.copyWith(
      blur: clear ? DesignTokens.componentGlassClearBlur : null,
      bodyMode: clear ? liquid.GlassBodyMode.clear : null,
      glassColor: clear
          ? (dark
                ? DesignTokens.colorGlassClearDark
                : DesignTokens.colorGlassClear)
          : null,
    );
    return includeShadow ? resolved : resolved.copyWith(shadow: const []);
  }

  Widget _build(BuildContext context, GlobalKey contentKey) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = opaqueGlass(context, solid: solid);
    final style = optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    final content = KeyedSubtree(
      key: contentKey,
      child: DecoratedBox(
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
      ),
    );
    Widget surface;
    if (opaque) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    } else {
      if (ImageFilter.isShaderFilterSupported && !GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final shape = liquid.LiquidRoundedSuperellipse(borderRadius: radius);
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
        borderRadius: BorderRadius.circular(radius),
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

class _GlassState extends State<Glass> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) => widget._build(context, _contentKey);
}
