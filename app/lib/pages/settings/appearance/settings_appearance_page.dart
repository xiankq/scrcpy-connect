import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:design_system/design_system.dart';

class AppearancePage extends HookConsumerWidget {
  const AppearancePage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    Future<void> save(String key, dynamic setting) async {
      try {
        await controller.updateSetting(key, setting);
      } catch (e) {
        if (context.mounted) feedback(context, '$e');
      }
    }

    return PageFrame(
      title: '外观',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          for (final option in const [
            ('light', '浅色', LucideIcons.sun),
            ('dark', '深色', LucideIcons.moon),
            ('system', '跟随系统', LucideIcons.monitor),
          ])
            ChoiceRow<String>(
              leading: Icon(
                option.$3,
                size: DesignTokens.componentIconSize,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              title: Text(option.$2),
              value: option.$1,
              groupValue: value(appSettings, 'appearance', 'light'),
              onChanged: (v) => save('appearance', v),
            ),
        ],
      ),
    );
  }
}
