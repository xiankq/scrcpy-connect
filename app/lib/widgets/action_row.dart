import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.color,
    this.trailing,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacingMd,
    ),
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
  final Color? color;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrow = onTap == null
        ? null
        : const Icon(
            AppIcons.forward,
            size: DesignTokens.componentIconSmallSize,
          );
    Widget tile(Widget? end) => ListTile(
      enabled: enabled,
      contentPadding: contentPadding,
      minLeadingWidth: DesignTokens.componentListIconSize,
      leading: ListIconBadge(
        icon: icon,
        backgroundColor: enabled
            ? color ??
                  (destructive
                      ? DesignTokens.colorListIconCoral
                      : DesignTokens.colorListIconUtility)
            : theme.disabledColor,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: !enabled
              ? theme.disabledColor
              : destructive
              ? theme.colorScheme.error
              : null,
        ),
      ),
      trailing: end,
      onTap: onTap,
    );

    if (value case final label? when trailing == null) {
      return LayoutBuilder(
        builder: (context, constraints) => tile(
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .44),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Tooltip(
                    message: label,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                if (arrow != null) ...[
                  const SizedBox(width: DesignTokens.spacingXxs),
                  arrow,
                ],
              ],
            ),
          ),
        ),
      );
    }
    return tile(trailing ?? arrow);
  }
}
