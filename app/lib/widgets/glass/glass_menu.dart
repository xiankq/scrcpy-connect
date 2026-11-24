import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// 独立圆键使用自己的采样层，保留控件轮廓与按压高光。
class GlassToolbarIconButton extends StatelessWidget {
  const GlassToolbarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.focusNode,
    this.variant = GlassVariant.regular,
    this.size = DesignTokens.componentIconButtonSize,
    this.iconSize = DesignTokens.componentToolGlyphSize,
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
    final theme = Theme.of(context);
    final opaque = opaqueGlass(context);
    final animate = !GlassMaterial.reduceMotion(context) && !opaque;
    return liquid.GlassButton(
      icon: IconTheme(
        data: IconThemeData(
          color: onPressed == null
              ? theme.disabledColor
              : theme.colorScheme.onSurface,
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
      interactionScale: animate ? null : 1,
      stretch: animate ? .5 : 0,
      anchorStretch: animate,
      surfaceStyle: opaque ? liquid.GlassSurfaceStyle.solid : null,
      color: opaque ? theme.colorScheme.surfaceContainerHighest : null,
      persistPressOnDrag: false,
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

/// 使用生产玻璃后端形变的 44 点菜单入口。
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.actions,
    this.label,
    this.variant = GlassVariant.regular,
    this.enabled = true,
  }) : assert(actions.length > 0);
  final Widget icon;
  final String tooltip;
  final List<GlassMenuAction> actions;
  final String? label;
  final GlassVariant variant;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final style = theme.textTheme.labelLarge!;
    final itemHeight = math.max(
      DesignTokens.componentMenuItemHeight,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          2 * DesignTokens.spacingXxs,
    );
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
      minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
      maximumSize: const Size.square(DesignTokens.componentIconButtonSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: theme.colorScheme.onSurface,
      iconSize: DesignTokens.componentToolGlyphSize,
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
        reducedMotion ||
        opaqueGlass(context) ||
        !ImageFilter.isShaderFilterSupported) {
      // 后端的“瞬时”形变仍使用空间弹簧。
      // 减少动态效果或不支持形变时保留框架菜单生命周期，材料仍交给自适应玻璃后端。
      return MenuAnchor(
        animated: !reducedMotion,
        clipBehavior: Clip.none,
        consumeOutsideTap: true,
        alignmentOffset: label == null
            ? Offset.zero
            : const Offset(
                0,
                DesignTokens.componentFileActionBarPadding +
                    DesignTokens.spacingXs,
              ),
        style: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          surfaceTintColor: WidgetStatePropertyAll(
            DesignTokens.colorTransparent,
          ),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        menuChildren: [
          GlassSurfaceGroup.isolated(
            variant: GlassVariant.menu,
            child: Glass(
              variant: GlassVariant.menu,
              radius: DesignTokens.componentMenuRounded,
              padding: const EdgeInsets.all(DesignTokens.componentMenuPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in actions)
                    MenuItemButton(
                      style: ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(
                          Size(
                            DesignTokens.componentIconButtonSize,
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
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? theme.disabledColor
                              : action.destructive
                              ? (theme.brightness == Brightness.dark
                                    ? DesignTokens.colorDangerTextDark
                                    : DesignTokens.colorDangerText)
                              : theme.colorScheme.onSurface,
                        ),
                        iconSize: const WidgetStatePropertyAll(
                          DesignTokens.componentMenuItemSize,
                        ),
                      ),
                      leadingIcon: action.icon,
                      onPressed: action.onPressed,
                      child: Text(action.label),
                    ),
                ],
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
    return liquid.GlassAccessibilityScope(
      reduceMotion: reducedMotion,
      child: liquid.GlassMenu(
        autoAdjustToScreen: true,
        menuPadding: const EdgeInsets.all(DesignTokens.componentMenuPadding),
        menuBorderRadius: DesignTokens.componentMenuRounded,
        itemBorderRadius: DesignTokens.componentMenuItemRounded,
        settings: GlassMaterial.settings(context, variant: GlassVariant.menu),
        quality: GlassMaterial.quality(context),
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
              titleStyle: style,
              iconColor: action.destructive
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
              iconSize: DesignTokens.componentMenuItemSize,
              enablePressScale: !reducedMotion,
            ),
        ],
      ),
    );
  }
}

/// 用单一材质组织相关工具栏控件，子项不重复覆盖玻璃。
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
    final theme = Theme.of(context);
    final compactStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
      foregroundColor: theme.colorScheme.onSurface,
      disabledForegroundColor: theme.disabledColor,
      iconSize: DesignTokens.componentToolGlyphSize,
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final material = children.length > 1 && variant == GlassVariant.regular
        ? GlassVariant.pill
        : variant;
    return GlassSurfaceGroup(
      variant: material,
      child: GlassPressFeedback(
        child: Glass(
          radius: DesignTokens.componentIconButtonRounded,
          circular: children.length == 1,
          variant: material,
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
              spacing: DesignTokens.componentIconButtonGap,
              children: [
                for (final action in children)
                  SizedBox.square(
                    dimension: DesignTokens.componentIconButtonSize,
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

/// 侧边控件按宿主的物理边缘定位。每个按钮拥有自己的轮廓。
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
        spacing: DesignTokens.spacingXs,
        children: children,
      ),
    );
  }
}
