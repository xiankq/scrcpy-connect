import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 带功能色块的动作或导航行（Ardot 列表行「前导=色块」）。
///
/// 有 [onTap] 且没有 [trailing] 时行尾显示箭头；危险动作标题用 `error`、色块用通知色。
class ActionRow extends StatelessWidget implements GroupedRow {
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
    this.subtitle,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.componentListRowPadding,
    ),
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;

  /// 功能色，取 [FunctionTone]；默认通用色，危险动作为通知色。
  final Color? color;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  @override
  double get separatorIndent => tileRowSeparatorIndent;

  @override
  Widget build(BuildContext context) => AppListRow(
    enabled: enabled,
    onTap: onTap,
    destructive: destructive,
    contentPadding: contentPadding,
    leading: ListIconBadge(
      icon: icon,
      backgroundColor: enabled
          ? color ??
                (destructive ? FunctionTone.notification : FunctionTone.utility)
          : AppColors.of(context).disabled,
    ),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: trailing == null ? value : null,
    trailing: trailing,
    chevron: trailing == null && onTap != null,
  );
}
