import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
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

/// 紧凑控件与行内文字分别保持自己的最小尺寸。
class ConnectSwitchRow extends StatelessWidget {
  const ConnectSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacingMd,
    ),
  });
  final Widget title;
  final IconData? icon;
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.componentRowHeight,
        ),
        child: Padding(
          padding: contentPadding.add(
            const EdgeInsets.symmetric(vertical: DesignTokens.spacingTight),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                ListIconBadge(
                  icon: icon!,
                  backgroundColor:
                      iconColor ?? DesignTokens.colorListIconUtility,
                ),
                const SizedBox(width: DesignTokens.spacingSm),
              ],
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyLarge!,
                  child: title,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              ConnectSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 有界的关联设置分组，不用于包裹动态结果列表。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ContentPanel(
    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXxs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}
