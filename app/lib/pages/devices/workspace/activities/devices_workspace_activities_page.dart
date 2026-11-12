import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/application/activities_notifier.dart';
import 'package:scrcpy_connect/core/control/session_activity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActivitiesPage extends HookConsumerWidget {
  const ActivitiesPage({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppNotifier controller;
  final String deviceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = activitiesProvider(deviceId: deviceId);
    final query = ref.watch(provider);
    Future<void> refresh() => ref.read(provider.notifier).refresh();
    return PageFrame(
      title: '当前活动',
      child: AsyncContent<ActivityCollection>(
        loading: query.loading,
        data: query.data,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法核验活动',
        builder: (context, data) {
          final unresolved = data.pendingApplications;
          final unresolvedIds = unresolved
              .map((item) => item.sessionId)
              .toSet();
          final activities = data.activities
              .where(
                (activity) =>
                    activity.target is! SessionActivityTarget ||
                    !unresolvedIds.contains(
                      (activity.target as SessionActivityTarget).sessionId,
                    ),
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
                          .where((device) => device.id == deviceId)
                          .firstOrNull ??
                      DeviceSnapshot(id: deviceId),
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
                        activities.firstOrNull?.deviceName ?? '此设备',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (unresolved.isNotEmpty) const SectionTitle('待核对'),
                      WorkspaceCallCard(
                        controller: controller,
                        device:
                            controller
                                .snapshot()
                                .devices
                                .where((device) => device.id == deviceId)
                                .firstOrNull ??
                            DeviceSnapshot(id: deviceId),
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
                    key: ValueKey(activity.target),
                    icon: LucideIcons.activity,
                    title: activity.name,
                    trailing: GlassTooltip(
                      message: statusText(activity.status),
                      child: TextButton(
                        onPressed: () async {
                          if (await confirm(
                                context,
                                '停止“${activity.name}”？',
                                activity.stopImpact,
                                action: '停止活动',
                              ) &&
                              context.mounted) {
                            await performAction(
                              context,
                              () => controller.activities.stopActivity(
                                activity.target,
                              ),
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
  final AppNotifier controller;
  final String deviceId;
  final SessionActivity session;
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

    final id = session.sessionId;
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(session.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(session.reason ?? '应用打开请求可能已提交，尚未确认画面。'),
          Wrap(
            spacing: DesignTokens.spacingSm,
            children: [
              TextButton(
                onPressed: busy.value
                    ? null
                    : () => run(() async {
                        final result = await controller.activities
                            .readActivities(deviceId: deviceId);
                        if (!context.mounted) return;
                        final linked = session.linkedSessionId ?? id;
                        final pendingIds = result.pendingApplications
                            .map((item) => item.sessionId)
                            .toSet();
                        final live = result.activities
                            .where(
                              (item) =>
                                  item.target is SessionActivityTarget &&
                                  (item.target as SessionActivityTarget)
                                          .sessionId ==
                                      linked &&
                                  !pendingIds.contains(linked) &&
                                  !const {
                                    'failed',
                                    'stopped',
                                    'error',
                                  }.contains(item.status),
                            )
                            .firstOrNull;
                        refresh();
                        if (live != null) {
                          await openRemoteRoute(
                            context,
                            deviceId: deviceId,
                            sessionId: (live.target as SessionActivityTarget)
                                .sessionId,
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
                        await controller.activities.stopActivity(
                          ActivityTarget.session(id),
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
