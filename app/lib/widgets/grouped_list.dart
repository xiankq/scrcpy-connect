import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

/// An open content list. Each child is laid out independently by the viewport.
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

/// The compact control and the row's text keep independent minimum sizes.
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
                  backgroundColor: functionalIconColor(icon!, color: iconColor),
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

/// A bounded group of related settings, not a wrapper for dynamic results.
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
