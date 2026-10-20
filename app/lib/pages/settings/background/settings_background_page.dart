import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BackgroundPage extends HookConsumerWidget {
  const BackgroundPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final changing = useState(false);
    final revision = useState(0);
    final alerts = ref.watch(systemNotificationCoordinatorProvider);
    useListenable(alerts.changes);
    final alertStatus = alerts.status;
    Future<void> updateAlert(String key, bool value) async {
      if (changing.value) return;
      changing.value = true;
      try {
        await controller.updateSetting(key, value);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      } finally {
        if (context.mounted) changing.value = false;
      }
    }

    return PageFrame(
      title: '后台与连接',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConnectSwitchRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许后台保持'),

                  value: appSettings['backgroundKeepAlive'] == true,
                  onChanged: changing.value
                      ? null
                      : (v) async {
                          changing.value = true;
                          try {
                            await controller.updateSetting(
                              'backgroundKeepAlive',
                              v,
                            );
                            await controller.execute(
                              InteropCommand.backgroundRequest,
                              {'enabled': v, 'askNotificationPermission': v},
                            );
                          } catch (e) {
                            if (context.mounted) feedback(context, '$e');
                          } finally {
                            if (context.mounted) {
                              changing.value = false;
                              revision.value++;
                            }
                          }
                        },
                ),
                const Divider(height: DesignTokens.spacingHairline),
                const SizedBox(height: DesignTokens.spacingMd),
                CommandView(
                  controller: controller,
                  command: 'background.status',
                  refreshKey: revision.value,
                  emptyTitle: '尚未获得后台运行资格',
                  builder: (context, data, refresh) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value(data, 'title', '系统后台条件'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: DesignTokens.spacingSm),
                      Text(value(data, 'reason', '后台运行取决于系统授权、电量策略与活动类型。')),
                      if (data['canRequest'] == true)
                        TextButton(
                          onPressed: () async {
                            await perform(
                              context,
                              controller,
                              'background.request',
                              {
                                'enabled': true,
                                'askNotificationPermission': true,
                              },
                            );
                            refresh();
                          },
                          child: const Text('检查系统设置'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('系统提醒'),
          ConnectSwitchRow(
            title: const Text('远端通知提醒'),

            value: appSettings['notificationAlerts'] != false,
            onChanged: changing.value
                ? null
                : (value) => updateAlert('notificationAlerts', value),
          ),
          ConnectSwitchRow(
            title: const Text('远端来电提醒'),

            value: appSettings['callAlerts'] != false,
            onChanged: changing.value
                ? null
                : (value) => updateAlert('callAlerts', value),
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
