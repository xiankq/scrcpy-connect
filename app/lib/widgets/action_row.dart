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
  Color _iconColor(BuildContext context) {
    if (color != null) return ConnectTokens.accent(context, color!);
    if (icon == LucideIcons.appWindow) {
      return Theme.of(context).colorScheme.onSurface;
    }
    final accent = switch (icon) {
      LucideIcons.folder ||
      LucideIcons.folderOpen ||
      LucideIcons.file ||
      LucideIcons.hardDrive ||
      LucideIcons.download ||
      LucideIcons.upload ||
      LucideIcons.usb ||
      LucideIcons.fileInput ||
      LucideIcons.fileOutput => ConnectTokens.amber,
      LucideIcons.phone || LucideIcons.phoneIncoming => ConnectTokens.mint,
      _ => ConnectTokens.blue,
    };
    return ConnectTokens.accent(context, accent);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: contentPadding,
    minLeadingWidth: DesignTokens.componentIconSize,
    leading: Icon(
      icon,
      color: _iconColor(context),
      size: DesignTokens.componentIconSize,
    ),
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
