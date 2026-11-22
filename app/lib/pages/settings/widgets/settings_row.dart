import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.compact = false,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle, value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool compact, destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: compact
          ? DesignTokens.componentSettingsRowHeight
          : DesignTokens.componentRowHeight,
      minVerticalPadding: DesignTokens.spacingXxs,
      minLeadingWidth: 0,
      leading: ListIconBadge(
        icon: icon,
        backgroundColor: color,
        compact: compact,
      ),
      title: Text(
        title,
        style:
            (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
                ?.copyWith(color: destructive ? theme.colorScheme.error : null),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.bodySmall),
      trailing:
          trailing ??
          (value != null || onTap != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value != null)
                      Text(value!, style: theme.textTheme.bodySmall),
                    if (onTap != null) ...[
                      if (value != null)
                        const SizedBox(width: DesignTokens.spacingXs),
                      const Icon(
                        AppIcons.forward,
                        size: DesignTokens.componentIconSmallSize,
                      ),
                    ],
                  ],
                )
              : null),
      onTap: onTap,
    );
  }
}
