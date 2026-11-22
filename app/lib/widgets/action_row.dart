import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
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
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
  final Color? color;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) => ListTile(
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
          : Theme.of(context).disabledColor,
    ),
    title: Text(
      title,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: !enabled
            ? Theme.of(context).disabledColor
            : destructive
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    ),
    trailing:
        trailing ??
        (onTap == null
            ? null
            : const Icon(
                AppIcons.forward,
                size: DesignTokens.componentIconSmallSize,
              )),
    onTap: onTap,
  );
}
