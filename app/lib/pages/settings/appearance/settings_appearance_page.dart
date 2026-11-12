import 'package:scrcpy_connect/core/settings/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class AppearancePage extends HookConsumerWidget {
  const AppearancePage({super.key, required this.controller});
  final AppNotifier controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    Future<void> save(Appearance setting) async {
      try {
        await controller.preferences.update(
          PreferenceChanges(appearance: setting),
        );
      } catch (e) {
        if (context.mounted) feedback(context, '$e');
      }
    }

    return PageFrame(
      title: '外观',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          SettingsGroup(
            children: [
              for (final option in const [
                (
                  Appearance.light,
                  '浅色',
                  LucideIcons.sun,
                  DesignTokens.colorListIconAmber,
                ),
                (
                  Appearance.dark,
                  '深色',
                  LucideIcons.moon,
                  DesignTokens.colorListIconPurple,
                ),
                (
                  Appearance.system,
                  '跟随系统',
                  LucideIcons.monitor,
                  DesignTokens.colorListIconSlate,
                ),
              ])
                ChoiceRow<Appearance>(
                  leading: ListIconBadge(
                    icon: option.$3,
                    backgroundColor: option.$4,
                  ),
                  title: Text(option.$2),
                  value: option.$1,
                  groupValue: appSettings.appearance,
                  onChanged: (v) {
                    if (v != null) save(v);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
