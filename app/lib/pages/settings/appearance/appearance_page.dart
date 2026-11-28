import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class AppearancePage extends HookConsumerWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(settingsManagementProvider);
    final appSettings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    Future<void> save(Appearance setting) async {
      try {
        await ref
            .read(preferencesProvider.notifier)
            .update(PreferenceChanges(appearance: setting));
      } catch (e) {
        if (context.mounted &&
            identical(ref.read(settingsManagementProvider), source)) {
          feedback(context, '$e');
        }
      }
    }

    return PageFrame(
      title: '外观',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          SettingsGroup(
            children: [
              for (final option in const [
                (Appearance.light, '浅色', LucideIcons.sun, FunctionTone.display),
                (Appearance.dark, '深色', LucideIcons.moon, FunctionTone.display),
                (
                  Appearance.system,
                  '跟随系统',
                  LucideIcons.monitor,
                  FunctionTone.display,
                ),
              ])
                ChoiceRow<Appearance>(
                  leading: ListIconBadge(
                    icon: option.$3,
                    backgroundColor: option.$4,
                  ),
                  title: Text(option.$2),
                  value: option.$1,
                  selected: appSettings.appearance == option.$1,
                  onChanged: save,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
