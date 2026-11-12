import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

import '../models/quality_choice.dart';

export '../models/quality_choice.dart';

class QualityOptionsSheet<T> extends StatelessWidget {
  const QualityOptionsSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
  });
  final String title;
  final IconData icon;
  final List<QualityChoice<T>> options;
  final T selected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
        minHeight: options.length > 8
            ? MediaQuery.sizeOf(context).height * .8
            : 0,
      ),
      child: GroupedListView.builder(
        shrinkWrap: options.length <= 8,
        padding: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
        itemCount: options.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            );
          }
          final item = options[index - 1];
          return GlassTooltip(
            message: item.reason,
            child: ListTile(
              leading: ListIconBadge(
                icon: icon,
                backgroundColor: functionalIconColor(icon),
              ),
              title: Text(item.label),
              enabled: item.available,
              trailing: selected == item.value
                  ? const Icon(LucideIcons.check)
                  : null,
              onTap: () => Navigator.pop(context, item),
            ),
          );
        },
      ),
    ),
  );
}
