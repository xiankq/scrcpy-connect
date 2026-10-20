import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

/// The application's configuration applied to the official test subject.
Widget officialGlassNavigation(
  BuildContext context, {
  required int selectedIndex,
  required ValueChanged<int> onTabSelected,
}) {
  final theme = Theme.of(context);
  final opaque = GlassMaterial.opaque(context);
  final reducedMotion = GlassMaterial.reduceMotion(context);
  return liquid.GlassAccessibilityScope(
    reduceTransparency: opaque,
    child: GlassTabBar.bottom(
      key: ValueKey(reducedMotion),
      tabs: const [
        liquid.GlassTab(icon: Icon(Icons.devices), label: '设备'),
        liquid.GlassTab(icon: Icon(Icons.swap_vert), label: '传输'),
        liquid.GlassTab(icon: Icon(Icons.settings), label: '设置'),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onTabSelected,
      horizontalPadding: 0,
      verticalPadding: 0,
      barHeight: GlassMaterial.navigationHeight(context),
      barBorderRadius: DesignTokens.componentNavigationRounded,
      tabPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.componentNavigationPadding,
      ),
      iconLabelSpacing: DesignTokens.spacingMicro,
      iconSize: DesignTokens.componentIconSize,
      labelFontSize: theme.textTheme.labelLarge!.fontSize!,
      textStyle: theme.textTheme.labelLarge,
      selectedIconColor: theme.colorScheme.primary,
      selectedLabelColor: theme.colorScheme.primary,
      unselectedIconColor: theme.colorScheme.onSurfaceVariant,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      indicatorColor: opaque
          ? theme.colorScheme.surfaceContainerHigh
          : theme.brightness == Brightness.dark
          ? DesignTokens.colorGlassSelectedDark
          : DesignTokens.colorGlassSelected,
      settings: GlassMaterial.settings(context),
      quality: GlassMaterial.quality(context),
      indicatorSettings: opaque
          ? GlassMaterial.settings(context)
                .copyWith(glassColor: DesignTokens.colorTransparent)
          : null,
      pressScale: reducedMotion
          ? 1
          : DesignTokens.componentGlassInteractionScale,
      interactionBehavior: reducedMotion
          ? liquid.GlassInteractionBehavior.glowOnly
          : liquid.GlassInteractionBehavior.full,
    ),
  );
}

Widget officialGlassIconButton(
  BuildContext context, {
  required Widget icon,
  required String label,
  required VoidCallback? onPressed,
}) {
  final reducedMotion = GlassMaterial.reduceMotion(context);
  return liquid.GlassAccessibilityScope(
    reduceTransparency: GlassMaterial.opaque(context),
    child: GlassSurfaceGroup(
      child: GlassTooltip(
        message: label,
        child: GlassIconButton(
          icon: icon,
          semanticLabel: label,
          onPressed: onPressed,
          size: DesignTokens.componentIconButtonSize,
          iconSize: DesignTokens.componentIconSize,
          settings: GlassMaterial.settings(context),
          quality: GlassMaterial.quality(context),
          interactionScale: reducedMotion
              ? 1
              : DesignTokens.componentGlassInteractionScale,
          anchorStretch: !reducedMotion,
        ),
      ),
    ),
  );
}
