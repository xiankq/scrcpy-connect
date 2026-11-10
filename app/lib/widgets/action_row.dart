import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  Color get _badgeColor => functionalIconColor(icon, color: color);

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    contentPadding: contentPadding,
    minLeadingWidth: DesignTokens.componentListIconSize,
    leading: ListIconBadge(
      icon: icon,
      backgroundColor: enabled ? _badgeColor : Theme.of(context).disabledColor,
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
                LucideIcons.chevronRight,
                size: DesignTokens.componentIconSmallSize,
              )),
    onTap: onTap,
  );
}

/// 功能色属于操作背景，图形符号保持白色。
Color functionalIconColor(IconData icon, {Color? color}) {
  if (color == ConnectTokens.danger || color == ConnectTokens.coral) {
    return DesignTokens.colorListIconCoral;
  }
  if (color == ConnectTokens.amber) return DesignTokens.colorListIconAmber;
  if (color == ConnectTokens.mint) return DesignTokens.colorListIconMint;
  if (color != null &&
      [
        DesignTokens.colorListIconBlue,
        DesignTokens.colorListIconMint,
        DesignTokens.colorListIconAmber,
        DesignTokens.colorListIconCoral,
        DesignTokens.colorListIconSlate,
        DesignTokens.colorListIconPurple,
      ].contains(color)) {
    return color;
  }
  return switch (icon) {
    LucideIcons.trash2 ||
    LucideIcons.unplug ||
    LucideIcons.lock ||
    LucideIcons.moon => DesignTokens.colorListIconCoral,
    LucideIcons.folder ||
    LucideIcons.folderOpen ||
    LucideIcons.file ||
    LucideIcons.hardDrive ||
    LucideIcons.download ||
    LucideIcons.upload ||
    LucideIcons.usb ||
    LucideIcons.fileInput ||
    LucideIcons.fileOutput ||
    LucideIcons.clipboard ||
    LucideIcons.sun ||
    LucideIcons.alarmClock ||
    LucideIcons.stethoscope ||
    LucideIcons.keyRound ||
    LucideIcons.cpu => DesignTokens.colorListIconAmber,
    LucideIcons.phone ||
    LucideIcons.phoneIncoming ||
    LucideIcons.activity ||
    LucideIcons.shieldCheck ||
    LucideIcons.battery ||
    LucideIcons.batteryCharging ||
    LucideIcons.gauge ||
    LucideIcons.refreshCw => DesignTokens.colorListIconMint,
    LucideIcons.slidersHorizontal ||
    LucideIcons.ratio ||
    LucideIcons.monitor ||
    LucideIcons.panelsTopLeft ||
    LucideIcons.images => DesignTokens.colorListIconPurple,
    LucideIcons.network ||
    LucideIcons.wifi ||
    LucideIcons.radio ||
    LucideIcons.link => DesignTokens.colorListIconBlue,
    _ => DesignTokens.colorListIconSlate,
  };
}
