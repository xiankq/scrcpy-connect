import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.color,
    this.trailing,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacingMd,
    ),
  });
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;
  Color get _badgeColor {
    if (color == ConnectTokens.danger ||
        color == ConnectTokens.coral ||
        color == DesignTokens.colorListIconCoral) {
      return DesignTokens.colorListIconCoral;
    }
    if (color == ConnectTokens.amber ||
        color == DesignTokens.colorListIconAmber) {
      return DesignTokens.colorListIconAmber;
    }
    if (color == ConnectTokens.mint ||
        color == DesignTokens.colorListIconMint) {
      return DesignTokens.colorListIconMint;
    }
    return switch (icon) {
      LucideIcons.folder ||
      LucideIcons.folderOpen ||
      LucideIcons.file ||
      LucideIcons.hardDrive ||
      LucideIcons.download ||
      LucideIcons.upload ||
      LucideIcons.usb ||
      LucideIcons.fileInput ||
      LucideIcons.fileOutput => DesignTokens.colorListIconAmber,
      LucideIcons.phone ||
      LucideIcons.phoneIncoming => DesignTokens.colorListIconMint,
      _ => DesignTokens.colorListIconBlue,
    };
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: contentPadding,
    minLeadingWidth: DesignTokens.componentListIconSize,
    leading: ListIconBadge(icon: icon, backgroundColor: _badgeColor),
    title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
    trailing:
        trailing ??
        (onTap == null
            ? null
            : const Icon(
                LucideIcons.chevronRight,
                size: DesignTokens.componentIconSmallSize,
              )),
    onTap: onTap,
  );
}
