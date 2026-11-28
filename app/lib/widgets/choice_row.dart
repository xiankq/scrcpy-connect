import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 单选弹层与单选列表的选项行（design.md「输入与选择」）：
/// 当前项行尾为 `primary` 对勾，不另加底色；对勾占 22 点尾槽，切换时文字宽度不变。
class ChoiceRow<T> extends StatelessWidget implements GroupedRow {
  const ChoiceRow({
    super.key,
    required this.value,
    required this.selected,
    required this.onChanged,
    required this.title,
    this.leading,
    this.contentPadding,
    this.disabledReason,
  });
  final T value;
  final bool selected;
  final ValueChanged<T>? onChanged;
  final Widget title;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final String? disabledReason;

  @override
  double get separatorIndent => listRowSeparatorIndent(
    leading == null ? null : DesignTokens.componentIconTileSize,
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onChanged != null;
    final reason = disabledReason;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: AppListRow(
        enabled: enabled,
        selected: selected,
        contentPadding: contentPadding,
        leading: leading,
        title: title,
        subtitle: reason == null || reason.isEmpty ? null : Text(reason),
        onTap: enabled ? () => onChanged!(value) : null,
        trailing: SizedBox.square(
          dimension: listRowTrailingSlot,
          child: selected
              ? Icon(
                  LucideIcons.check,
                  size: listRowTrailingSlot,
                  color: enabled ? colors.primary : colors.disabled,
                )
              : null,
        ),
      ),
    );
  }
}
