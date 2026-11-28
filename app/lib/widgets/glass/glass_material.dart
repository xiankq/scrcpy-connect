import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_geometry.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// designs/design.md「材质」的五种玻璃预设。
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
    final settings = Glass.optics(
      brightness: Theme.of(context).brightness,
      variant: variant,
    );
    return quality(context) == liquid.GlassQuality.minimal
        ? settings.copyWith(
            blur: 0,
            frost: 0,
            bodyShade: 0,
            glassColor: glassSolidColor(context),
            bodyMode: liquid.GlassBodyMode.clear,
          )
        : settings;
  }

  /// 底部导航胶囊高 62；200% 文字时随图形、间距与标签增高。
  static double navigationHeight(BuildContext context) {
    final label = AppTypography.of(context).tabLabel;
    return math.max(
      DesignTokens.componentNavigationDockHeight,
      DesignTokens.componentDockItemSize +
          DesignTokens.componentDockItemGap +
          MediaQuery.textScalerOf(context).scale(label.fontSize!) *
              label.height! +
          2 * DesignTokens.componentNavigationDockPadding,
    );
  }

  /// 实体导航保留托盘几何，托盘本身由 indicatorColor 着色；玻璃档位沿用库的镜片材质。
  static liquid.LiquidGlassSettings? navigationIndicatorSettings(
    BuildContext context,
  ) => opaqueGlass(context)
      ? settings(context)
            .copyWith(glassColor: AppColors.of(context).page.withAlpha(0))
      : null;

  /// 向后端注册 Material 明暗模式和系统辅助偏好。
  /// 背景采样组只属于局部控件组，不能放在根 Navigator。
  static Widget wrap({required Widget child}) => liquid.LiquidGlassWidgets.wrap(
    child: child,
    brightnessResolver: Theme.maybeBrightnessOf,
  );
}

/// 玻璃关闭、降低透明度或提高对比度时的实体浮层面：浅色 `card`，深色 `block`。
Color glassSolidColor(BuildContext context) {
  final colors = AppColors.of(context);
  return Theme.of(context).brightness == Brightness.dark
      ? colors.block
      : colors.card;
}

/// 玻璃上的二级填充（分段轨道、非主按钮）：`glass-on-glass`；
/// 玻璃回退为实体浮层面时取浮层面的下一层（浅色 `block`，深色 `inset`）。
Color glassOnGlassColor(BuildContext context) {
  final colors = AppColors.of(context);
  if (!opaqueGlass(context)) return colors.glassFill;
  return Theme.of(context).brightness == Brightness.dark
      ? colors.inset
      : colors.block;
}

/// 各预设的投影，见 designs/design.md「玻璃配方」。实体回退统一使用 `dock-shadow`。
List<BoxShadow> glassShadows(
  BuildContext context,
  GlassVariant variant, {
  bool opaque = false,
}) {
  final colors = AppColors.of(context);
  final dock = [
    BoxShadow(
      color: colors.shadowDock,
      blurRadius: DesignTokens.componentDockShadowShadowBlur,
      offset: const Offset(0, DesignTokens.componentDockShadowShadowOffset),
    ),
    // 贴边的第二层：同色一半强度，blur 3 y1（Ardot 底部导航 37:741）。
    BoxShadow(
      color: colors.shadowDock.withValues(alpha: colors.shadowDock.a / 2),
      blurRadius: _contactShadowBlur,
      offset: const Offset(0, DesignTokens.spacingHairline),
    ),
  ];
  if (opaque) return dock;
  return switch (variant) {
    GlassVariant.pill => dock,
    GlassVariant.menu || GlassVariant.alert => [
      BoxShadow(
        color: colors.shadow,
        blurRadius: DesignTokens.componentGlassMenuShadowBlur,
        offset: const Offset(0, DesignTokens.componentGlassMenuShadowOffset),
      ),
    ],
    GlassVariant.regular || GlassVariant.clear => const [],
  };
}

const _contactShadowBlur = 3.0;

/// 共享单次 SDF 与折射的光学平面。
/// 同变体组加入外层平面，不同变体分离；作用域限于当前页面，不能跨 Navigator 或保留标签页。
class GlassSurfaceGroup extends StatefulWidget {
  const GlassSurfaceGroup({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(glassRefractionWidth),
  }) : _isolated = false;

  /// 即使 OverlayPortal 保留来源工具栏的继承组，覆盖层仍拥有新采样平面，不加入来源平面。
  const GlassSurfaceGroup.isolated({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.clipExpansion = const EdgeInsets.all(glassRefractionWidth),
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
          // 相邻玻璃胶囊静止时以 smooth-min 8 融合（interaction-motion「触点反馈」）。
          blendAmount: DesignTokens.spacingSm,
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

/// 浮在内容上的玻璃面：底色、模糊、边缘折射由后端渲染，上下高光与两侧细线由 [GlassRim] 描边。
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
    this.clipExpansion = const EdgeInsets.all(glassRefractionWidth),
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

  /// 使用库的明暗镜片和采样模型，并应用 designs/design.md「玻璃配方」的光学参数。
  /// 高光与细线由 [GlassRim] 绘制，后端只负责底色、模糊、饱和度与折射。
  static liquid.LiquidGlassSettings optics({
    required Brightness brightness,
    GlassVariant variant = GlassVariant.regular,
  }) {
    final dark = brightness == Brightness.dark;
    final palette = dark ? AppColors.dark : AppColors.light;
    final base = dark
        ? liquid.LiquidGlassSettings.ios27Dark
        : liquid.LiquidGlassSettings.ios27Light;
    final clear = variant == GlassVariant.clear;
    final pill = variant == GlassVariant.pill;
    final (tint, blur, saturation, refraction) = switch (variant) {
      GlassVariant.regular => (
        palette.glassRegular,
        DesignTokens.componentGlassRegularBlur,
        DesignTokens.componentGlassRegularSaturation,
        _GlassRefraction.regular,
      ),
      // pill 的模糊是 72% 雾化层，镜面本身不模糊（Prism pill: blur 0, haze .72/15.6）。
      GlassVariant.pill => (
        palette.glassPill,
        0.0,
        DesignTokens.componentGlassPillSaturation,
        _GlassRefraction.pill,
      ),
      GlassVariant.menu => (
        palette.glassMenu,
        DesignTokens.componentGlassMenuBlur,
        DesignTokens.componentGlassMenuSaturation,
        _GlassRefraction.menu,
      ),
      GlassVariant.alert => (
        palette.glassMenu,
        DesignTokens.componentGlassAlertBlur,
        DesignTokens.componentGlassAlertSaturation,
        _GlassRefraction.alert,
      ),
      GlassVariant.clear => (
        DesignTokens.colorGlassClear,
        DesignTokens.componentGlassClearBlur,
        1.0,
        _GlassRefraction.clear,
      ),
    };
    return base.copyWith(
      glassColor: tint,
      blur: blur,
      frost: pill ? DesignTokens.componentGlassPillBlur : 0,
      frostOpacity: pill ? _pillFrostOpacity : null,
      saturation: saturation,
      thickness: glassRefractionWidth,
      refractiveIndex: refraction,
      lightIntensity: 0,
      rimLight: 0,
      rimShade: 0,
      bodyShade: clear ? 0 : null,
      bodyMode: clear ? liquid.GlassBodyMode.clear : null,
      shadow: const [],
    );
  }

  Widget _build(BuildContext context, GlobalKey contentKey) {
    final colors = AppColors.of(context);
    final opaque = opaqueGlass(context, solid: solid);
    final OutlinedBorder shape = circular
        ? const CircleBorder()
        : RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          );
    final content = KeyedSubtree(
      key: contentKey,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    Widget surface;
    if (opaque) {
      final filled = DecoratedBox(
        decoration: ShapeDecoration(
          color: glassSolidColor(context),
          shape: MediaQuery.highContrastOf(context)
              ? shape.copyWith(side: BorderSide(color: colors.outline))
              : shape,
        ),
        child: content,
      );
      surface = circular
          ? ClipOval(child: filled)
          : ClipRSuperellipse(
              borderRadius: BorderRadius.all(Radius.circular(radius)),
              child: filled,
            );
    } else {
      if (ImageFilter.isShaderFilterSupported && !GlassMaterial.isInitialized) {
        throw StateError(
          'Await GlassMaterial.initialize() before mounting glass controls.',
        );
      }
      final liquidShape = circular
          ? const liquid.LiquidOval()
          : liquid.LiquidRoundedSuperellipse(borderRadius: radius);
      final group = context.dependOnInheritedWidgetOfExactType<_GlassGroup>();
      surface = group?.variant == variant
          ? liquid.AdaptiveGlass.grouped(
              shape: liquidShape,
              quality: GlassMaterial.quality(context),
              child: content,
            )
          : liquid.AdaptiveGlass(
              shape: liquidShape,
              settings: Glass.optics(
                brightness: Theme.of(context).brightness,
                variant: variant,
              ),
              quality: GlassMaterial.quality(context),
              allowElevation: false,
              clipExpansion: clipExpansion,
              child: content,
            );
      surface = boundGlassSampling(
        GlassRim(variant: variant, shape: shape, child: surface),
        expansion: clipExpansion,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: showShadow
            ? glassShadows(context, variant, opaque: opaque)
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

/// 后端透镜的折射率。Ardot GLASS refraction 为 regular/pill 0.9、menu/alert 0.6、clear 0.9
/// （clear 色散与外展更强），在库的近轴透镜模型下取对应的等效值。
abstract final class _GlassRefraction {
  static const regular = 1.104;
  static const pill = 1.1;
  static const menu = 1.054;
  static const alert = 1.046;
  static const clear = 1.132;
}

/// designs/design.md「玻璃配方」：glass-pill 雾化 72%。
const _pillFrostOpacity = 0.72;

/// 玻璃的上下高光与两侧细线，取自 Ardot 玻璃母组件的两层内描边。
///
/// 高光：纵向线性渐变的白色内描边，只出现在上下边缘；细线：横向线性渐变的黑色内描边，
/// 两侧最深。光照固定，不随手势或陀螺仪变化。
class GlassRim extends StatelessWidget {
  const GlassRim({
    super.key,
    required this.variant,
    required this.shape,
    required this.child,
    this.visible = true,
  });

  final GlassVariant variant;
  final ShapeBorder shape;
  final Widget child;

  /// 实体回退时关闭描边但保留同一层级，宿主控件的状态不因材质切换而重建。
  final bool visible;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: !visible
        ? null
        : _GlassRimPainter(
            spec: _GlassRimSpec.of(variant),
            shape: shape,
            textDirection: Directionality.maybeOf(context),
            highlight: DesignTokens.colorGlassRim,
            hairline: AppColors.of(context).shadow,
          ),
    child: child,
  );
}

@immutable
class _GlassRimSpec {
  const _GlassRimSpec({
    required this.width,
    required this.top,
    required this.bottom,
    required this.highlightStop,
    this.side = 0,
    this.flat = 0,
    this.hairlineStop = .15,
  });

  final double width;
  final double top;
  final double bottom;
  final double highlightStop;
  final double side;
  final double flat;
  final double hairlineStop;

  // 数值见 designs/design.md「Ardot 中的表达」及锚点菜单 37:771、确认框母组件。
  static _GlassRimSpec of(GlassVariant variant) => switch (variant) {
    GlassVariant.regular => const _GlassRimSpec(
      width: DesignTokens.componentGlassRegularSpecularThickness,
      top: .7,
      bottom: .7,
      highlightStop: .3,
      side: .22,
      flat: .04,
    ),
    GlassVariant.pill => const _GlassRimSpec(
      width: DesignTokens.componentGlassPillSpecularThickness,
      top: .9,
      bottom: .9,
      highlightStop: .3,
    ),
    GlassVariant.menu => const _GlassRimSpec(
      width: DesignTokens.spacingHairline,
      top: .6,
      bottom: .4,
      highlightStop: .15,
      side: .25,
      flat: .09,
      hairlineStop: .2,
    ),
    GlassVariant.alert => const _GlassRimSpec(
      width: DesignTokens.spacingHairline,
      top: .6,
      bottom: .4,
      highlightStop: .15,
      side: .35,
      flat: .09,
      hairlineStop: .2,
    ),
    GlassVariant.clear => const _GlassRimSpec(
      width: DesignTokens.componentGlassRegularSpecularThickness,
      top: .7,
      bottom: .7,
      highlightStop: .3,
    ),
  };
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.spec,
    required this.shape,
    required this.textDirection,
    required this.highlight,
    required this.hairline,
  });

  final _GlassRimSpec spec;
  final ShapeBorder shape;
  final TextDirection? textDirection;
  final Color highlight;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(
      rect.deflate(spec.width / 2),
      textDirection: textDirection,
    );
    Paint stroke(Gradient gradient) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.width
      ..shader = gradient.createShader(rect);
    canvas.drawPath(
      path,
      stroke(
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, spec.highlightStop, 1 - spec.highlightStop, 1],
          colors: [
            highlight.withValues(alpha: spec.top),
            highlight.withValues(alpha: 0),
            highlight.withValues(alpha: 0),
            highlight.withValues(alpha: spec.bottom),
          ],
        ),
      ),
    );
    if (spec.side > 0) {
      canvas.drawPath(
        path,
        stroke(
          LinearGradient(
            stops: [0, spec.hairlineStop, 1 - spec.hairlineStop, 1],
            colors: [
              hairline.withValues(alpha: spec.side),
              hairline.withValues(alpha: spec.flat),
              hairline.withValues(alpha: spec.flat),
              hairline.withValues(alpha: spec.side),
            ],
          ),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.shape != shape ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.highlight != highlight ||
      oldDelegate.hairline != hairline;
}
