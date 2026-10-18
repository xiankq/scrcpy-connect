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
  });
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  Color _iconColor(BuildContext context) {
    if (color != null) return ConnectTokens.accent(context, color!);
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
      LucideIcons.images ||
      LucideIcons.image ||
      LucideIcons.camera => ConnectTokens.coral,
      LucideIcons.phone || LucideIcons.phoneIncoming => ConnectTokens.mint,
      _ => ConnectTokens.blue,
    };
    return ConnectTokens.accent(context, accent);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingXxs,
        ),
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
      ),
      PositionedDirectional(
        start: DesignTokens.componentIconSize + DesignTokens.componentRowGap,
        end: DesignTokens.spacingZero,
        bottom: DesignTokens.spacingZero,
        child: Divider(
          height: DesignTokens.spacingHairline,
          thickness: DesignTokens.spacingHairline,
        ),
      ),
    ],
  );
}
