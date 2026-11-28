import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/background_status_provider.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

import '../widgets/settings_row.dart';

class BackgroundPage extends HookConsumerWidget {
  const BackgroundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(backgroundStatusProvider);
    final alerts = useSystemNotifications(context, ref);
    useStream(alerts.changes);
    final status = alerts.status;

    void refresh() {
      ref.invalidate(backgroundStatusProvider);
      alerts.refreshStatus();
    }

    useEffect(() {
      final listener = AppLifecycleListener(onResume: refresh);
      return listener.dispose;
    }, [alerts]);

    return PageFrame(
      title: '后台运行',
      actions: [
        GlassActionIcon(
          tooltip: '重新检查',
          icon: const Icon(AppIcons.refresh),
          onPressed: refresh,
        ),
      ],
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          SettingsGroup(
            children: [
              if (background.value case final data?)
                SettingsRow(
                  icon: LucideIcons.shieldCheck,
                  color: data.supported
                      ? FunctionTone.connection
                      : FunctionTone.utility,
                  title: data.title,
                  subtitle: data.reason,
                )
              else
                SettingsRow(
                  icon: LucideIcons.shieldCheck,
                  title: background.hasError ? '无法读取后台运行状态' : '正在检查后台运行',
                  onTap: background.hasError ? refresh : null,
                ),
            ],
          ),
          const SectionTitle('系统提醒'),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: LucideIcons.bell,
                color: FunctionTone.notification,
                title: '通知与来电权限',
                value: switch (status.permissionGranted) {
                  true => '已允许',
                  false => '未允许',
                  null => null,
                },
                onTap: status.canOpenSettings
                    ? () async {
                        if (!await alerts.openSettings() && context.mounted) {
                          feedback(context, '暂时无法打开系统通知设置。');
                        }
                      }
                    : null,
              ),
            ],
          ),
          if (status.reason.isNotEmpty) StateNote(status.reason),
        ],
      ),
    );
  }
}
