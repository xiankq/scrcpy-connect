import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActivitiesPage extends HookConsumerWidget {
  const ActivitiesPage({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppController controller;
  final String deviceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    return PageFrame(
      title: '当前活动',
      child: CommandView(
        refreshKey: appEventRevision,
        controller: controller,
        command: 'activities.list',
        params: {'deviceId': deviceId},
        emptyTitle: '暂时无法核验活动',
        builder: (context, data, refresh) {
          final activities = objects(data['activities'])
              .where((activity) => value(activity, 'deviceId') == deviceId)
              .toList();
          if (activities.isEmpty) {
            return PageChromeBody(
              child: EmptyContent(
                icon: LucideIcons.activity,
                title: '暂无正在进行的活动',
                message: '此设备的连接、控制会话、传输、声音与通话会显示在这里。',
                action: TextButton(
                  onPressed: refresh,
                  child: const Text('重新检查'),
                ),
              ),
            );
          }
          final groups = <String, List<Json>>{};
          for (final activity in activities) {
            final id = value(activity, 'deviceId');
            final name = value(activity, 'deviceName');
            final owner = id.isNotEmpty ? 'id:$id' : 'name:$name';
            (groups[owner] ??= []).add(activity);
          }
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingSm,
                  ),
                  child: Text(
                    value(entry.value.first, 'deviceName').isEmpty
                        ? '未标明设备'
                        : value(entry.value.first, 'deviceName'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                ContentPanel(
                  padding: EdgeInsets.zero,
                  key: ValueKey('activities:${entry.key}'),
                  child: Column(
                    children: [
                      for (final activity in entry.value)
                        ActionRow(
                          icon: LucideIcons.activity,
                          title: value(activity, 'name', '当前活动'),

                          trailing: GlassTooltip(
                            message: value(
                              activity,
                              'statusLabel',
                              statusText(value(activity, 'status')),
                            ),
                            child: TextButton(
                              onPressed: activity['canStop'] == false
                                  ? null
                                  : () async {
                                      if (await confirm(
                                            context,
                                            '停止“${value(activity, 'name')}”？',
                                            value(
                                              activity,
                                              'stopImpact',
                                              '主动停止后不会自动恢复该活动。其他设备的活动保持各自状态。',
                                            ),
                                            action: '停止活动',
                                          ) &&
                                          context.mounted) {
                                        await perform(
                                          context,
                                          controller,
                                          'activities.stop',
                                          {'activityId': activity['id']},
                                        );
                                        refresh();
                                      }
                                    },
                              child: const Text('停止'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingMd),
              ],
            ],
          );
        },
      ),
    );
  }
}
