import 'package:scrcpy_connect/core/settings/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/application/app_dependencies_provider.dart';
import 'package:scrcpy_connect/core/platform/background_status_provider.dart';

import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BackgroundPage extends HookConsumerWidget {
  const BackgroundPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    final changing = useState(false);
    final background = ref.watch(backgroundStatusProvider);
    useEffect(() {
      final lifecycle = AppLifecycleListener(
        onResume: () => ref.invalidate(backgroundStatusProvider),
      );
      return lifecycle.dispose;
    }, const []);
    final alerts = useSystemNotifications(context, ref);
    useListenable(alerts.changes);
    final alertStatus = alerts.status;
    Future<void> updateAlert(PreferenceChanges changes) async {
      if (changing.value) return;
      changing.value = true;
      try {
        await ref.read(preferencesProvider.notifier).update(changes);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      } finally {
        if (context.mounted) changing.value = false;
      }
    }

    Future<void> updateBackground(bool enabled) async {
      if (changing.value) return;
      final dependencies = ref.read(appDependenciesProvider);
      changing.value = true;
      try {
        await ref
            .read(preferencesProvider.notifier)
            .update(PreferenceChanges(backgroundKeepAlive: enabled));
        if (!context.mounted ||
            !identical(ref.read(appDependenciesProvider), dependencies)) {
          return;
        }
        await dependencies.background.requestBackground(
          enabled: enabled,
          askNotificationPermission: enabled,
        );
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      } finally {
        if (context.mounted) {
          changing.value = false;
          ref.invalidate(backgroundStatusProvider);
        }
      }
    }

    return PageFrame(
      title: '后台与提醒',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                background.when(
                  data: (data) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.supported)
                        ConnectSwitchRow(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('允许后台保持'),
                          value: appSettings.backgroundKeepAlive,
                          onChanged:
                              changing.value ||
                                  (!data.canRequest &&
                                      !appSettings.backgroundKeepAlive)
                              ? null
                              : updateBackground,
                        ),
                      if (data.supported) ...[
                        const Divider(height: DesignTokens.spacingHairline),
                        const SizedBox(height: DesignTokens.spacingMd),
                      ],
                      Text(
                        data.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      Text(data.reason),
                      if (data.supported && data.canRequest)
                        TextButton(
                          onPressed: changing.value
                              ? null
                              : () => updateBackground(true),
                          child: Text(
                            appSettings.backgroundKeepAlive && data.running
                                ? '允许连接通知'
                                : '重新启用后台保持',
                          ),
                        ),
                    ],
                  ),
                  loading: () => const PageChromeBody(
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  ),
                  error: (error, _) => PageChromeBody(
                    child: EmptyContent(
                      icon: LucideIcons.circleAlert,
                      title: '尚未获得后台运行资格',
                      message: '$error',
                      action: OutlinedButton.icon(
                        onPressed: () =>
                            ref.invalidate(backgroundStatusProvider),
                        icon: const Icon(
                          LucideIcons.refreshCw,
                          size: DesignTokens.componentIconActionSize,
                        ),
                        label: const Text('重新检查'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('系统提醒'),
          ConnectSwitchRow(
            title: const Text('远端通知提醒'),

            value: appSettings.notificationAlerts,
            onChanged: changing.value
                ? null
                : (value) =>
                      updateAlert(PreferenceChanges(notificationAlerts: value)),
          ),
          ConnectSwitchRow(
            title: const Text('远端来电提醒'),

            value: appSettings.callAlerts,
            onChanged: changing.value
                ? null
                : (value) => updateAlert(PreferenceChanges(callAlerts: value)),
          ),
          StateNote(
            alertStatus.reason.isEmpty ? '正在检查系统通知条件。' : alertStatus.reason,
          ),
          if (alertStatus.notificationChannelEnabled == false)
            const StateNote('远端实时通知渠道已关闭，请在系统设置中开启。'),
          if (alertStatus.callChannelEnabled == false)
            const StateNote('远端来电提醒渠道已关闭，请在系统设置中开启。'),
          Wrap(
            spacing: DesignTokens.spacingSm,
            children: [
              if (alertStatus.canRequest)
                OutlinedButton(
                  onPressed: changing.value
                      ? null
                      : () async {
                          changing.value = true;
                          try {
                            await alerts.requestPermission();
                          } finally {
                            if (context.mounted) changing.value = false;
                          }
                        },
                  child: const Text('允许系统提醒'),
                ),
              if (alertStatus.canOpenSettings)
                TextButton(
                  onPressed: () async {
                    if (!await alerts.openSettings() && context.mounted) {
                      feedback(context, '暂时无法打开系统通知设置。');
                    }
                  },
                  child: const Text('系统通知设置'),
                ),
            ],
          ),
          const SectionTitle('离开前台后'),
          const ActionRow(icon: LucideIcons.link, title: '连接与通知'),
          const ActionRow(icon: LucideIcons.arrowUpDown, title: '文件传输'),
          const ActionRow(icon: LucideIcons.pause, title: '不可见画面'),
          const ActionRow(icon: LucideIcons.audioLines, title: '声音与通话'),
          const StateNote(
            '系统停止、强行结束或回收应用后，不保证活动仍在进行。再次打开会核验状态；用户主动停止的活动保持停止，未知结果的回复、删除和拨号不会自动重复。',
          ),
          OutlinedButton(
            onPressed: () => const DevicesRoute().push<void>(context),
            child: const Text('选择设备查看活动'),
          ),
        ],
      ),
    );
  }
}
