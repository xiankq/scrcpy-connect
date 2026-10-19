import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationsPage extends HookConsumerWidget {
  const NotificationsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    final hidden = useState<Set<String>>({});
    final starting = useState(false);
    return PageFrame(
      title: '实时通知',
      child: CommandView(
        refreshKey: appEventRevision,
        controller: controller,
        command: 'notifications.list',
        params: {'deviceId': device['id']},
        emptyTitle: '当前无法同步通知',
        alternative: TextButton(
          onPressed: () =>
              openRemoteRoute(context, deviceId: value(device, 'id')),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data, refresh) {
          Future<void> verify() async {
            if (starting.value) return;
            starting.value = true;
            try {
              final result = await perform(
                context,
                controller,
                'observation.start',
                {'deviceId': device['id']},
              );
              if (context.mounted && result != null) refresh();
            } finally {
              if (context.mounted) starting.value = false;
            }
          }

          final notifications = objects(data['notifications'])
              .where((n) => !hidden.value.contains(value(n, 'id')))
              .where(
                (n) =>
                    n['groupSummary'] != true ||
                    value(n, 'title').trim().isNotEmpty ||
                    value(n, 'body').trim().isNotEmpty,
              )
              .toList();
          final state = value(data, 'status', 'unknown');
          if (notifications.isEmpty && state != 'available') {
            return PageChromeBody(
              child: EmptyContent(
                icon: LucideIcons.bellOff,
                title: switch (state) {
                  'needsSetup' => '通知访问需要设置',
                  'stopped' => '通知观察已停止',
                  'unknown' || 'checking' || 'starting' => '通知状态尚未核验',
                  _ => '通知同步受限',
                },
                message: value(data, 'reason', '这台设备尚未提供可靠的通知访问。你可以在手机原应用中处理。'),
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () => openRemoteRoute(
                        context,
                        deviceId: value(device, 'id'),
                      ),
                      child: const Text('在手机上查看'),
                    ),
                    TextButton(
                      onPressed: starting.value ? null : verify,
                      child: Text(state == 'stopped' ? '启用通知与来电观察' : '重新核验通知'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (notifications.isEmpty) {
            return PageChromeBody(
              child: EmptyContent(
                icon: LucideIcons.bell,
                title: '没有当前通知',
                message: '这里只显示仍有效的通知，不建立长期通知档案。',
                action: TextButton(
                  onPressed: starting.value ? null : verify,
                  child: const Text('刷新当前通知'),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: verify,
            child: GroupedListView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              children: [
                if (data['status'] == 'limited' &&
                    value(data, 'reason').isNotEmpty)
                  StateNote(
                    value(data, 'reason'),
                    icon: LucideIcons.circleAlert,
                  ),
                const StateNote('通知来自被控手机；清除不等于已读。涉及认证时请在手机真实界面完成。'),
                for (final notification in notifications)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacingMd,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spacingMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const FeatureIcon(LucideIcons.messageSquare),
                              const SizedBox(width: DesignTokens.spacingSm),
                              Expanded(
                                child: Text(
                                  value(notification, 'appName', '手机通知'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              GlassMenuButton(
                                icon: const Icon(LucideIcons.ellipsisVertical),
                                tooltip: '通知操作',
                                actions: [
                                  GlassMenuAction(
                                    label: '仅在本机隐藏',
                                    onPressed: () {
                                      hidden.value = {
                                        ...hidden.value,
                                        value(notification, 'id'),
                                      };
                                    },
                                  ),
                                  if (notification['canDismiss'] == true)
                                    GlassMenuAction(
                                      label: '清除手机上的通知',
                                      onPressed: () async {
                                        await perform(
                                          context,
                                          controller,
                                          'notifications.dismiss',
                                          {
                                            'deviceId': device['id'],
                                            'notificationId':
                                                notification['id'],
                                          },
                                        );
                                        refresh();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                          if (value(notification, 'title').isNotEmpty) ...[
                            const SizedBox(height: DesignTokens.spacingSm),
                            Text(
                              value(notification, 'title'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                          if (value(notification, 'body').isNotEmpty) ...[
                            const SizedBox(height: DesignTokens.spacingTight),
                            Text(value(notification, 'body')),
                          ],
                          if (value(notification, 'title').isEmpty &&
                              value(notification, 'body').isEmpty) ...[
                            const SizedBox(height: DesignTokens.spacingTight),
                            Text(
                              '此通知未提供预览内容',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: DesignTokens.spacingSm),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: DesignTokens.spacingSm,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      DesignTokens.componentIconButtonSize,
                                      DesignTokens.componentIconButtonSize,
                                    ),
                                  ),
                                  iconAlignment: IconAlignment.end,
                                  icon: const Icon(
                                    LucideIcons.arrowUpRight,
                                    size: DesignTokens.componentIconSmallSize,
                                  ),
                                  onPressed: () async {
                                    if (notification['canOpen'] == false) {
                                      openRemoteRoute(
                                        context,
                                        deviceId: value(device, 'id'),
                                      );
                                      return;
                                    }
                                    final result = await perform(
                                      context,
                                      controller,
                                      'notifications.open',
                                      {
                                        'deviceId': device['id'],
                                        'notificationId': notification['id'],
                                      },
                                    );
                                    if (result != null && context.mounted) {
                                      if (result['located'] != true) {
                                        feedback(
                                          context,
                                          value(
                                            result,
                                            'message',
                                            '未能定位原内容，将打开手机界面',
                                          ),
                                        );
                                      }
                                      openRemoteRoute(
                                        context,
                                        deviceId: value(device, 'id'),
                                      );
                                    }
                                  },
                                  label: Text(
                                    notification['canOpen'] == false
                                        ? '在手机上查看'
                                        : '进入手机原应用',
                                  ),
                                ),
                                if (notification['canReply'] == true)
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(
                                        DesignTokens.componentIconButtonSize,
                                        DesignTokens.componentIconButtonSize,
                                      ),
                                    ),
                                    onPressed: () => NotificationReplyRoute(
                                      deviceId: value(device, 'id'),
                                      notificationId: value(notification, 'id'),
                                    ).push<void>(context),
                                    child: const Text('快捷回复'),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spacingMd),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
