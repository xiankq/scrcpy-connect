import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 设置行（Ardot 列表行「前导=色块」）：功能色块 + 标题，可带副标题、行尾值与控件。
///
/// 有 [onTap] 且没有 [trailing] 时是导航行，行尾显示箭头。危险动作不用列表行，
/// 用页面上的通栏危险胶囊（design.md「列表」）。
class SettingsRow extends StatelessWidget implements GroupedRow {
  const SettingsRow({
    super.key,
    required this.icon,
    this.color = FunctionTone.utility,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;

  /// 功能色，取 [FunctionTone]。
  final Color color;
  final String title;
  final String? subtitle, value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 关闭时整行与色块呈禁用色。导航行未提供 [onTap] 时不必关闭。
  final bool enabled;

  @override
  double get separatorIndent => tileRowSeparatorIndent;

  @override
  Widget build(BuildContext context) => AppListRow(
    enabled: enabled,
    onTap: onTap,
    leading: ListIconBadge(
      icon: icon,
      backgroundColor: enabled ? color : AppColors.of(context).disabled,
    ),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    trailing: trailing,
    chevron: trailing == null && onTap != null,
  );
}
