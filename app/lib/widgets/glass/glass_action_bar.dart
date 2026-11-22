import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';

class GlassActionBar extends StatelessWidget {
  const GlassActionBar({
    super.key,
    required this.actions,
    this.variant = GlassVariant.regular,
  });

  final List<Widget> actions;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
    child: Glass(
      padding: const EdgeInsets.all(DesignTokens.componentFileActionBarPadding),
      radius: DesignTokens.componentFileActionBarRounded,
      variant: variant,
      showShadow: variant == GlassVariant.regular,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final action in actions) Expanded(child: action)],
      ),
    ),
  );
}

class GlassActionBarButton extends StatelessWidget {
  const GlassActionBarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = GlassPressFeedback(
      enabled: onPressed != null,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          textStyle: theme.textTheme.bodySmall?.merge(
            DesignTokens.componentFileActionBarTypography,
          ),
          iconSize: DesignTokens.componentIconSize,
          minimumSize: const Size(
            DesignTokens.componentIconButtonSize,
            DesignTokens.componentFileActionBarHeight -
                2 * DesignTokens.componentFileActionBarPadding,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXxs,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: DesignTokens.spacingMicro),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null
        ? button
        : Tooltip(
            message: tooltip,
            excludeFromSemantics: onPressed != null,
            child: button,
          );
  }
}
