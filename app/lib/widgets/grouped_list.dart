import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

/// 开放内容列表由视口分别布局每个子项。
class GroupedListView extends StatelessWidget {
  const GroupedListView({
    super.key,
    required this.children,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
    this.findChildIndexCallback,
  }) : itemCount = null,
       itemBuilder = null;
  const GroupedListView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
    this.findChildIndexCallback,
  }) : children = null;
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final int? Function(Key)? findChildIndexCallback;
  @override
  Widget build(BuildContext context) {
    final recovery = PageChromePadding.hasRecovery(context);
    return PageChromePadding(
      padding: EdgeInsets.zero,
      showRecovery: false,
      child: ListView.builder(
        padding:
            (padding ?? EdgeInsets.zero).resolve(Directionality.of(context)) +
            PageChromePadding.of(context),
        shrinkWrap: shrinkWrap,
        physics: physics,
        controller: controller,
        findChildIndexCallback: findChildIndexCallback == null
            ? null
            : (key) {
                final index = findChildIndexCallback!(key);
                return index == null ? null : index + (recovery ? 1 : 0);
              },
        itemCount: (itemCount ?? children!.length) + (recovery ? 1 : 0),
        itemBuilder: (context, index) {
          if (recovery && index == 0) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 2,
              ),
              child: const RecoveryStatus(padding: EdgeInsets.zero),
            );
          }
          final item = index - (recovery ? 1 : 0);
          return itemBuilder?.call(context, item) ?? children![item];
        },
      ),
    );
  }
}

/// 开关行（Ardot 列表行「尾部=开关」）：整行都是开关的命中区。
class ConnectSwitchRow extends StatelessWidget implements GroupedRow {
  const ConnectSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.componentListRowPadding,
    ),
  });
  final Widget title;
  final Widget? subtitle;
  final IconData? icon;

  /// 功能色，取 [FunctionTone]；默认通用色。
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  double get separatorIndent =>
      icon == null ? listRowSeparatorIndent(null) : tileRowSeparatorIndent;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: AppListRow(
      title: title,
      subtitle: subtitle,
      contentPadding: contentPadding,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      leading: icon == null
          ? null
          : ListIconBadge(
              icon: icon!,
              backgroundColor: onChanged == null
                  ? AppColors.of(context).disabled
                  : iconColor ?? FunctionTone.utility,
            ),
      trailing: ConnectSwitch(value: value, onChanged: onChanged),
    ),
  );
}

/// 有界的关联设置分组（Ardot 分组卡片）：`card` 底、圆角 24，行间用分隔线。
///
/// 分隔线从行标题起点开始（[GroupedRow] 自报起点，其他子项用 [separatorIndent]），
/// 最后一行不画；某行按下时隐藏它上下的分隔线。不用于包裹动态结果列表。
class SettingsGroup extends StatefulWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.separatorIndent = tileRowSeparatorIndent,
  });
  final List<Widget> children;

  /// 不是 [GroupedRow] 的子项下方分隔线的起点。
  final double separatorIndent;

  @override
  State<SettingsGroup> createState() => _SettingsGroupState();
}

class _SettingsGroupState extends State<SettingsGroup> {
  int? _pressed;

  void _onPressedChanged(int index, bool pressed) {
    final next = pressed ? index : (_pressed == index ? null : _pressed);
    if (next != _pressed && mounted) setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final children = widget.children;
    return Material(
      color: colors.card,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentListGroupRounded),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed)
            ListGroupSlot(
              index: index,
              onPressedChanged: _onPressedChanged,
              child: Stack(
                children: [
                  child,
                  if (index < children.length - 1)
                    PositionedDirectional(
                      start: child is GroupedRow
                          ? (child as GroupedRow).separatorIndent
                          : widget.separatorIndent,
                      end: DesignTokens.componentListRowPadding,
                      bottom: 0,
                      height: DesignTokens.componentSeparatorHeight,
                      child: IgnorePointer(
                        child: Visibility(
                          visible: _pressed != index && _pressed != index + 1,
                          child: ColoredBox(color: colors.separator),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
