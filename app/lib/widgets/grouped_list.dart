import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';

/// Content stays on an opaque grouped surface; glass is reserved for chrome.
class GroupedListView extends StatelessWidget {
  const GroupedListView({
    super.key,
    required this.children,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  bool _isRow(Widget child) =>
      child is ActionRow ||
      child is ChoiceRow ||
      child is ConnectSwitchRow ||
      child is ListTile ||
      child is CheckboxListTile;
  @override
  Widget build(BuildContext context) {
    final grouped = <Widget>[
      if (PageChromePadding.hasRecovery(context))
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height / 2,
          ),
          child: const RecoveryStatus(padding: EdgeInsets.zero),
        ),
    ];
    final rows = <Widget>[];
    void flush() {
      if (rows.isEmpty) return;
      grouped.add(
        ContentPanel(
          padding: EdgeInsets.zero,
          child: Column(children: List.of(rows)),
        ),
      );
      rows.clear();
    }

    for (final child in children) {
      if (_isRow(child)) {
        rows.add(child);
      } else {
        flush();
        grouped.add(child);
      }
    }
    flush();
    return PageChromePadding(
      padding: EdgeInsets.zero,
      showRecovery: false,
      child: ListView(
        padding:
            (padding ?? EdgeInsets.zero).resolve(Directionality.of(context)) +
            PageChromePadding.of(context),
        shrinkWrap: shrinkWrap,
        physics: physics,
        controller: controller,
        children: grouped,
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
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spacingMd,
    ),
  });
  final Widget title;
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

/// One row in a lazily built group, with a shared content surface and end caps.
class GroupedItem extends StatelessWidget {
  const GroupedItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
  });
  final int index;
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(
        index == 0
            ? DesignTokens.componentContentPanelRounded
            : DesignTokens.spacingZero,
      ),
      bottom: Radius.circular(
        index == count - 1
            ? DesignTokens.componentContentPanelRounded
            : DesignTokens.spacingZero,
      ),
    ),
    child: Column(
      children: [
        child,
        if (child is! ActionRow && index < count - 1)
          const Divider(
            height: DesignTokens.spacingHairline,
            indent:
                DesignTokens.spacingMd +
                DesignTokens.componentListIconSize +
                DesignTokens.componentRowGap,
            endIndent: DesignTokens.spacingMd,
          ),
      ],
    ),
  );
}
