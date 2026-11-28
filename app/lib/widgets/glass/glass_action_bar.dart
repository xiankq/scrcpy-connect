import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';

/// 文件与相册底栏 `foot-bar`（Ardot 底栏 37:742）：高 64 的 glass-pill 胶囊，内距 8，各项等宽。
/// 左右 16 的页面边距由宿主（例如 PageFrame 的底部槽）负责。
class GlassActionBar extends StatelessWidget {
  const GlassActionBar({
    super.key,
    required this.actions,
    this.variant = GlassVariant.pill,
  });

  final List<Widget> actions;
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(DesignTokens.componentFootBarPadding),
    radius: DesignTokens.componentFootBarRounded,
    variant: variant,
    showShadow: variant != GlassVariant.clear,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final action in actions) Expanded(child: action)],
    ),
  );
}

/// 底栏中的一项：24 点图形在上、`caption-emphasis` 标签在下，间距 2。
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final button = GlassPressFeedback(
      enabled: onPressed != null,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: colors.text,
          disabledForegroundColor: colors.disabled,
          overlayColor: colors.page.withAlpha(0),
          textStyle: type.captionEmphasis,
          iconSize: DesignTokens.componentBarGlyphSize,
          minimumSize: const Size(
            DesignTokens.componentBarButtonSize,
            DesignTokens.componentFootBarHeight -
                2 * DesignTokens.componentFootBarPadding,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXxs,
          ),
          shape: const StadiumBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: DesignTokens.spacingXxs),
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
