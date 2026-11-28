import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// 页头图标按钮（Ardot 图标按钮 37:534「玻璃·页头」）：44 点 glass-regular 正圆，图形 24。
/// 独立圆键使用自己的采样层，保留控件轮廓与按压高光。
class GlassToolbarIconButton extends StatelessWidget {
  const GlassToolbarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.focusNode,
    this.variant = GlassVariant.regular,
    this.size = DesignTokens.componentBarButtonSize,
    this.iconSize = DesignTokens.componentBarGlyphSize,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final FocusNode? focusNode;
  final GlassVariant variant;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final opaque = opaqueGlass(context);
    final animate = !GlassMaterial.reduceMotion(context);
    final foreground = variant == GlassVariant.clear
        ? DesignTokens.colorOnMedia
        : colors.text;
    final button = liquid.GlassButton(
      icon: IconTheme(
        data: IconThemeData(
          color: onPressed == null ? colors.disabled : foreground,
          size: iconSize,
        ),
        child: icon,
      ),
      onTap: onPressed ?? () {},
      enabled: onPressed != null,
      label: semanticLabel,
      focusNode: focusNode,
      width: size,
      height: size,
      iconSize: iconSize,
      settings: opaque
          ? null
          : GlassMaterial.settings(context, variant: variant),
      quality: opaque ? null : GlassMaterial.quality(context),
      useOwnLayer: true,
      interactionScale: animate
          ? GlassPressMetrics.scaleFor(Size.square(size))
          : 1,
      stretch: animate ? DesignTokens.componentGlassInteractionStretch : 0,
      anchorStretch: animate,
      glowColor: DesignTokens.colorGlassRim.withValues(
        alpha: DesignTokens.componentGlassInteractionGlowIntensity,
      ),
      glowRadius: GlassPressMetrics.glowReach,
      surfaceStyle: opaque ? liquid.GlassSurfaceStyle.solid : null,
      color: opaque ? glassSolidColor(context) : null,
      persistPressOnDrag: false,
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const CircleBorder(),
        shadows: opaque ? glassShadows(context, variant, opaque: true) : null,
      ),
      child: GlassRim(
        variant: variant,
        shape: const CircleBorder(),
        visible: !opaque,
        child: button,
      ),
    );
  }
}

/// 已有的单个应用动作，不了解设备或路由。
@immutable
class GlassMenuAction {
  const GlassMenuAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool destructive;
}

/// 锚点菜单（Ardot 37:771）：glass-menu，宽 240、外角 24、内距 8；项高 44、项角 16、
/// 图形 20 在文字前间距 12；危险项用 `error`。菜单从触发按钮生长出来。
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.actions,
    this.label,
    this.variant = GlassVariant.regular,
    this.enabled = true,
    this.controller,
  }) : assert(actions.length > 0);
  final Widget icon;
  final String tooltip;
  final List<GlassMenuAction> actions;

  /// 提供时为底栏按钮（[GlassActionBarButton]，图形在上、标签在下），菜单从按钮上方展开。
  final String? label;
  final GlassVariant variant;
  final bool enabled;

  /// 由调用方开关菜单（例如退出选择时先收起菜单）。提供时使用框架菜单生命周期。
  final MenuController? controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final style = AppTypography.of(context).subheadline;
    final itemHeight = math.max(
      DesignTokens.componentMenuItemHeight,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          2 * DesignTokens.spacingXxs,
    );
    Color foreground(GlassMenuAction action) => action.onPressed == null
        ? colors.disabled
        : action.destructive
        ? colors.error
        : colors.text;
    if (!enabled) {
      if (label case final label?) {
        return GlassActionBarButton(
          label: label,
          icon: icon,
          tooltip: tooltip,
          onPressed: null,
        );
      }
      return Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: GlassToolbarIconButton(
          icon: icon,
          semanticLabel: tooltip,
          onPressed: null,
          variant: variant,
        ),
      );
    }
    final triggerStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentBarButtonSize),
      maximumSize: const Size.square(DesignTokens.componentBarButtonSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: colors.text,
      iconSize: DesignTokens.componentBarGlyphSize,
    );
    Widget trigger(VoidCallback onPressed) => switch (label) {
      final label? => GlassActionBarButton(
        label: label,
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
      null => GlassActionIcon(
        style: triggerStyle,
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    };
    if (label != null ||
        controller != null ||
        reducedMotion ||
        opaqueGlass(context) ||
        !ImageFilter.isShaderFilterSupported) {
      // 后端的“瞬时”形变仍使用空间弹簧。
      // 减少动态效果或不支持形变时保留框架菜单生命周期，材料仍交给自适应玻璃后端。
      final clear = colors.page.withAlpha(0);
      return MenuAnchor(
        controller: controller,
        animated: !reducedMotion,
        clipBehavior: Clip.none,
        consumeOutsideTap: true,
        alignmentOffset: label == null
            ? Offset.zero
            : const Offset(
                0,
                DesignTokens.componentFootBarPadding + DesignTokens.spacingXs,
              ),
        style: MenuStyle(
          // 底栏按钮的菜单从按钮底边中点对齐展开，空间不足时向上翻转。
          alignment: label == null ? null : Alignment.bottomCenter,
          backgroundColor: WidgetStatePropertyAll(clear),
          surfaceTintColor: WidgetStatePropertyAll(clear),
          shadowColor: WidgetStatePropertyAll(clear),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        menuChildren: [
          GlassSurfaceGroup.isolated(
            variant: GlassVariant.menu,
            child: Glass(
              variant: GlassVariant.menu,
              radius: DesignTokens.componentMenuRounded,
              padding: const EdgeInsets.all(DesignTokens.componentMenuPadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth:
                      DesignTokens.componentMenuWidth -
                      2 * DesignTokens.componentMenuPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final action in actions)
                      MenuItemButton(
                        style: ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(
                            Size(
                              DesignTokens.componentBarButtonSize,
                              itemHeight,
                            ),
                          ),
                          textStyle: WidgetStatePropertyAll(style),
                          shape: const WidgetStatePropertyAll(
                            RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(
                                  DesignTokens.componentMenuItemRounded,
                                ),
                              ),
                            ),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(
                              horizontal: DesignTokens.componentMenuItemPadding,
                            ),
                          ),
                          backgroundColor: WidgetStatePropertyAll(clear),
                          overlayColor: WidgetStateProperty.resolveWith(
                            (states) =>
                                states.contains(WidgetState.pressed) ||
                                    states.contains(WidgetState.hovered) ||
                                    states.contains(WidgetState.focused)
                                ? colors.pressed
                                : clear,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            foreground(action),
                          ),
                          iconColor: WidgetStatePropertyAll(foreground(action)),
                          iconSize: const WidgetStatePropertyAll(
                            DesignTokens.componentMenuItemSize,
                          ),
                        ),
                        // 框架在图形与文字之间留 12，与设计稿一致。
                        leadingIcon: action.icon,
                        onPressed: action.onPressed,
                        child: Text(action.label),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        builder: (context, controller, child) {
          void toggle() =>
              controller.isOpen ? controller.close() : controller.open();
          if (label != null) return trigger(toggle);
          return Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: GlassToolbarIconButton(
              icon: icon,
              semanticLabel: tooltip,
              variant: variant,
              onPressed: toggle,
            ),
          );
        },
      );
    }
    final base = Theme.of(context).brightness == Brightness.dark
        ? liquid.LiquidGlassSettings.ios27Dark
        : liquid.LiquidGlassSettings.ios27Light;
    return liquid.GlassAccessibilityScope(
      reduceMotion: reducedMotion,
      child: liquid.GlassMenu(
        autoAdjustToScreen: true,
        menuWidth: DesignTokens.componentMenuWidth,
        menuPadding: const EdgeInsets.all(DesignTokens.componentMenuPadding),
        menuBorderRadius: DesignTokens.componentMenuRounded,
        itemBorderRadius: DesignTokens.componentMenuItemRounded,
        // 库自绘菜单面板，无法叠加 GlassRim；保留后端自身的上下高光与外缘线。
        settings: GlassMaterial.settings(
          context,
          variant: GlassVariant.menu,
        ).copyWith(rimLight: base.rimLight, rimShade: base.rimShade),
        quality: GlassMaterial.quality(context),
        selectionColor: colors.pressed,
        opaqueColor: glassSolidColor(context),
        glowColor: DesignTokens.colorGlassRim.withValues(
          alpha: DesignTokens.componentGlassInteractionGlowIntensity,
        ),
        triggerBuilder: (context, toggle) => trigger(toggle),
        items: [
          for (final action in actions)
            liquid.GlassMenuItem(
              title: action.label,
              icon: action.icon,
              onTap: action.onPressed ?? () {},
              enabled: action.onPressed != null,
              isDestructive: action.destructive,
              height: itemHeight,
              titleStyle: style.copyWith(color: foreground(action)),
              iconColor: foreground(action),
              iconSize: DesignTokens.componentMenuItemSize,
              enablePressScale: !reducedMotion,
            ),
        ],
      ),
    );
  }
}

/// 页头按钮组（Ardot 37:527）：相邻图标按钮合成一个 glass-regular 胶囊，项宽 44、组内间距 0，
/// 每项保留独立命中区。单个按钮是 44 点正圆。
class GlassToolbarGroup extends StatelessWidget {
  const GlassToolbarGroup({
    super.key,
    required this.children,
    this.variant = GlassVariant.regular,
  });
  final List<Widget> children;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final compactStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentBarButtonSize),
      foregroundColor: variant == GlassVariant.clear
          ? DesignTokens.colorOnMedia
          : colors.text,
      disabledForegroundColor: colors.disabled,
      iconSize: DesignTokens.componentBarGlyphSize,
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    return GlassSurfaceGroup(
      variant: variant,
      child: GlassPressFeedback(
        child: Glass(
          radius: DesignTokens.componentBarButtonRounded,
          circular: children.length == 1,
          variant: variant,
          showShadow: false,
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style:
                  IconButtonTheme.of(context).style?.merge(compactStyle) ??
                  compactStyle,
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final action in children)
                  SizedBox.square(
                    dimension: DesignTokens.componentBarButtonSize,
                    child: action,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// iPhone Duo 竖栏：页头按钮沿系统指定外缘纵向排列，每个按钮拥有自己的轮廓。
class GlassSideToolbar extends StatelessWidget {
  const GlassSideToolbar({
    super.key,
    required this.bar,
    required this.children,
  });

  final liquid.GlassVerticalBarData bar;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final left = bar.edge == liquid.GlassVerticalBarEdge.leading;
    return Positioned(
      top: bar.top,
      left: left ? 0 : null,
      right: left ? null : 0,
      width: math.min(bar.width, liquid.GlassVerticalBarMetrics.stripWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignTokens.spacingSm,
        children: children,
      ),
    );
  }
}
