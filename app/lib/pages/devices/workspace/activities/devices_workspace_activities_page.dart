import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActivitiesPage extends HookWidget {
  const ActivitiesPage({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppStore controller;
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
          final sessions = objects(data['sessions'])
              .where((session) => session['deviceId'] == deviceId)
              .toList();
          final unresolved = sessions
              .where(
                (session) =>
                    session['launchOutcome'] == 'unknown' ||
                    session['recordOnly'] == true,
              )
              .toList();
          final unresolvedIds = unresolved
              .map((session) => 'session:${session['sessionId']}')
              .toSet();
          final activities = objects(data['activities'])
              .where(
                (activity) =>
                    value(activity, 'deviceId') == deviceId &&
                    !unresolvedIds.contains(activity['id']),
              )
              .toList();
          if (activities.isEmpty && unresolved.isEmpty) {
            return GroupedListView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              children: [
                WorkspaceCallCard(
                  controller: controller,
                  device:
                      controller
                          .snapshot()
                          .devices
                          .where((device) => device['id'] == deviceId)
                          .firstOrNull ??
                      {'id': deviceId},
                ),
                EmptyContent(
                  icon: LucideIcons.activity,
                  title: '暂无正在进行的活动',
                  message: '此设备的连接、控制会话、传输、声音与通话会显示在这里。',
                  action: TextButton(
                    onPressed: refresh,
                    child: const Text('重新检查'),
                  ),
                ),
              ],
            );
          }
          return GroupedListView.builder(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            itemCount: activities.length + unresolved.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        value(
                          activities.firstOrNull ?? const {},
                          'deviceName',
                          '此设备',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (unresolved.isNotEmpty) const SectionTitle('待核对'),
                      WorkspaceCallCard(
                        controller: controller,
                        device:
                            controller
                                .snapshot()
                                .devices
                                .where((device) => device['id'] == deviceId)
                                .firstOrNull ??
                            {'id': deviceId},
                      ),
                    ],
                  ),
                );
              }
              if (index <= unresolved.length) {
                return _PendingLaunch(
                  controller: controller,
                  deviceId: deviceId,
                  session: unresolved[index - 1],
                  refresh: refresh,
                );
              }
              final activity = activities[index - unresolved.length - 1];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index == unresolved.length + 1)
                    const SectionTitle('正在进行'),
                  ActionRow(
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
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PendingLaunch extends HookWidget {
  const _PendingLaunch({
    required this.controller,
    required this.deviceId,
    required this.session,
    required this.refresh,
  });
  final AppStore controller;
  final String deviceId;
  final Json session;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    Future<void> run(Future<void> Function() operation) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await operation();
      } catch (error) {
        if (context.mounted) feedback(context, '未完成：$error');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final id = value(session, 'sessionId');
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value(session, 'name', value(session, 'packageName', '应用打开')),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(value(session, 'reason', '应用打开请求可能已提交，尚未确认画面。')),
          Wrap(
            spacing: DesignTokens.spacingSm,
            children: [
              TextButton(
                onPressed: busy.value
                    ? null
                    : () => run(() async {
                        final result = await controller.execute(
                          ApplicationCommand.sessionList,
                          {'deviceId': deviceId},
                        );
                        if (!context.mounted) return;
                        final linked = value(session, 'linkedSessionId', id);
                        final live = objects(result['sessions'])
                            .where(
                              (item) =>
                                  item['deviceId'] == deviceId &&
                                  item['sessionId'] == linked &&
                                  item['recordOnly'] != true &&
                                  item['launchOutcome'] != 'unknown' &&
                                  ![
                                    'failed',
                                    'stopped',
                                    'error',
                                  ].contains(item['status']),
                            )
                            .firstOrNull;
                        refresh();
                        if (live != null) {
                          await openRemoteRoute(
                            context,
                            deviceId: deviceId,
                            sessionId: value(live, 'sessionId'),
                          );
                        } else {
                          feedback(context, '本次打开仍待核对，请在手机检查。未重新发送打开请求。');
                        }
                      }),
                child: const Text('重新核对'),
              ),
              TextButton(
                onPressed: busy.value
                    ? null
                    : () => run(() async {
                        if (!await confirm(
                              context,
                              '关闭本次打开记录？',
                              '仅结束本次跟踪及所属捕获，手机上的应用任务保留。之后重新打开可能迁移现有任务。',
                              action: '关闭记录',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        await controller.execute(
                          ApplicationCommand.sessionStop,
                          {
                            'deviceId': deviceId,
                            'sessionId': id,
                            'keepTask': true,
                          },
                        );
                        refresh();
                      }),
                child: const Text('关闭记录'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
