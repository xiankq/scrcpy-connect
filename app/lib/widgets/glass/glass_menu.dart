import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';

/// 顶部独立按钮使用自己的采样层，避免按压放大被标题栏边界裁切。
///
/// 工具栏按钮仍然是官方 `GlassIconButton`，但不把交互光晕扩散到标题平面；
/// 多按钮集合继续由 [GlassToolbarGroup] 共享一个玻璃平面。
class GlassToolbarIconButton extends StatelessWidget {
  const GlassToolbarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.variant = GlassVariant.regular,
    this.size = DesignTokens.componentIconButtonSize,
    this.iconSize = DesignTokens.componentIconSize,
    this.interactionScale = 1,
    this.anchorStretch = false,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final GlassVariant variant;
  final double size;
  final double iconSize;
  final double interactionScale;
  final bool anchorStretch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return liquid.GlassIconButton(
      icon: IconTheme(
        data: IconThemeData(
          color: onPressed == null
              ? theme.disabledColor
              : theme.colorScheme.onSurface,
          size: iconSize,
        ),
        child: icon,
      ),
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      size: size,
      iconSize: iconSize,
      settings: GlassMaterial.settings(context, variant: variant),
      quality: GlassMaterial.quality(context),
      useOwnLayer: true,
      glowColor: Colors.transparent,
      glowRadius: 0,
      interactionScale: interactionScale,
      anchorStretch: anchorStretch,
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
    this.variant = GlassVariant.regular,
    this.enabled = true,
  }) : assert(actions.length > 0);
  final Widget icon;
  final String tooltip;
  final List<GlassMenuAction> actions;
  final GlassVariant variant;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reducedMotion = liquid.GlassAccessibilityData.of(context)
        .reduceMotion;
    final style = theme.textTheme.labelLarge!;
    final itemHeight = math.max(
      DesignTokens.componentIconButtonSize,
      MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
          2 * DesignTokens.spacingSm,
    );
    if (!enabled) {
      return Tooltip(
        message: tooltip,
        child: liquid.GlassIconButton(
          icon: icon,
          semanticLabel: tooltip,
          onPressed: null,
          size: DesignTokens.componentIconButtonSize,
          iconSize: DesignTokens.componentIconSize,
          settings: GlassMaterial.settings(context, variant: variant),
          quality: GlassMaterial.quality(context),
          useOwnLayer: true,
          interactionScale: reducedMotion
              ? 1
              : DesignTokens.componentGlassInteractionScale,
          anchorStretch: !reducedMotion,
        ),
      );
    }
    final triggerStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
      maximumSize: const Size.square(DesignTokens.componentIconButtonSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: theme.colorScheme.onSurface,
      iconSize: DesignTokens.componentIconSize,
    );
    if (reducedMotion || !ImageFilter.isShaderFilterSupported) {
      // 后端的“瞬时”形变仍使用空间弹簧。
      // 减少动态效果或不支持形变时保留框架菜单生命周期，材料仍交给自适应玻璃后端。
      return MenuAnchor(
        animated: !reducedMotion,
        clipBehavior: Clip.none,
        consumeOutsideTap: true,
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
            variant: variant,
            child: Glass(
              variant: variant,
              radius: DesignTokens.roundedLg,
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingXs,
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
                            DesignTokens.componentIconButtonSize,
                            itemHeight,
                          ),
                        ),
                        textStyle: WidgetStatePropertyAll(style),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.disabled)
                              ? theme.disabledColor
                              : action.destructive
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                        ),
                        iconSize: const WidgetStatePropertyAll(
                          DesignTokens.componentIconSize,
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
        builder: (context, controller, child) => GlassActionIcon(
          style: triggerStyle,
          icon: icon,
          tooltip: tooltip,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }
    return liquid.GlassAccessibilityScope(
      reduceMotion: reducedMotion,
      child: liquid.GlassMenu(
        autoAdjustToScreen: true,
        menuPadding: const EdgeInsets.all(DesignTokens.spacingMd),
        menuBorderRadius: DesignTokens.roundedLg,
        itemBorderRadius: DesignTokens.roundedMd,
        settings: GlassMaterial.settings(context, variant: variant),
        quality: GlassMaterial.quality(context),
        stretch: reducedMotion
            ? 0
            : DesignTokens.componentGlassInteractionStretch,
        triggerBuilder: (context, toggle) => GlassActionIcon(
          style: triggerStyle,
          icon: icon,
          tooltip: tooltip,
          onPressed: toggle,
        ),
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
              iconSize: DesignTokens.componentIconSize,
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
    final compactStyle = IconButton.styleFrom(
      minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    return GlassSurfaceGroup(
      variant: variant,
      child: GlassPressFeedback(
        child: Glass(
          radius: DesignTokens.roundedFull,
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
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// iPhone Duo 侧边栏中的共享工具操作平面。
///
/// 子按钮保持普通按钮语义，共用一个玻璃层；这样侧边轴不会叠出多个
/// 独立镜片，也不会把按钮交互光晕裁切到标题栏边界之外。
class GlassVerticalToolbarGroup extends StatelessWidget {
  const GlassVerticalToolbarGroup({
    super.key,
    required this.children,
    this.variant = GlassVariant.regular,
  });

  final List<Widget> children;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) => GlassSurfaceGroup(
    variant: variant,
    child: GlassPressFeedback(
      child: Glass(
        radius: DesignTokens.roundedFull,
        variant: variant,
        showShadow: false,
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}
