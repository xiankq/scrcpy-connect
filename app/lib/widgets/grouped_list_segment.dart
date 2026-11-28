import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 逐行构建的分组卡片中的一行：外观与 `SettingsGroup` 相同（`card` 底、首尾圆角 24、
/// 行间分隔线从行标题起点开始），用于条目很多、需要按需构建的动态列表。
///
/// 分隔线起点取 [separatorIndent]；未提供时取 [GroupedRow] 子项自己的起点，否则为行内距。
class GroupedListSegment extends StatelessWidget {
  const GroupedListSegment({
    super.key,
    required this.first,
    required this.last,
    required this.child,
    this.separatorIndent,
  });

  /// 按列表下标构建：首项带上圆角，末项带下圆角且不画分隔线。
  const GroupedListSegment.at({
    super.key,
    required int index,
    required int count,
    required this.child,
    this.separatorIndent,
  }) : first = index == 0,
       last = index == count - 1;

  final bool first;
  final bool last;
  final Widget child;
  final double? separatorIndent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final child = this.child;
    const radius = Radius.circular(DesignTokens.componentListGroupRounded);
    return Material(
      color: colors.card,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // 末行也保留 Stack，行数变化时子树位置不变、状态不丢。
      child: Stack(
        children: [
          child,
          if (!last)
            PositionedDirectional(
              start:
                  separatorIndent ??
                  (child is GroupedRow
                      ? (child as GroupedRow).separatorIndent
                      : listRowSeparatorIndent(null)),
              end: DesignTokens.componentListRowPadding,
              bottom: 0,
              height: DesignTokens.componentSeparatorHeight,
              child: IgnorePointer(child: ColoredBox(color: colors.separator)),
            ),
        ],
      ),
    );
  }
}
