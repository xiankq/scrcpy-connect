import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActivitiesPage extends HookWidget {
  const ActivitiesPage({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppController controller;
  final String deviceId;
  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: '当前活动',
      child: CommandView(
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
          return GroupedListView.builder(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            itemCount: activities.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: Text(
                    value(activities.first, 'deviceName', '此设备'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final activity = activities[index - 1];
              return ActionRow(
                key: ValueKey(value(activity, 'id')),
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
              );
            },
          );
        },
      ),
    );
  }
}
