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
    return PageFrame(
      title: '实时通知',
      subtitle: deviceName(device),
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
          final notifications = objects(data['notifications'])
              .where((n) => !hidden.value.contains(value(n, 'id')))
              .toList();
          final state = value(data, 'status', 'unknown');
          if (notifications.isEmpty && state != 'available') {
            return EmptyContent(
              icon: LucideIcons.bellOff,
              title: switch (state) {
                'needsSetup' => '通知访问需要设置',
                'unknown' || 'checking' => '通知状态尚未核验',
                _ => '通知同步受限',
              },
              message: value(data, 'reason', '这台设备尚未提供可靠的通知访问。你可以在手机原应用中处理。'),
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () =>
                        openRemoteRoute(context, deviceId: value(device, 'id')),
                    child: const Text('在手机上查看'),
                  ),
                  TextButton(onPressed: refresh, child: const Text('重新核验通知')),
                ],
              ),
            );
          }
          if (notifications.isEmpty) {
            return EmptyContent(
              icon: LucideIcons.bell,
              title: '没有当前通知',
              message: '这里只显示仍有效的通知，不建立长期通知档案。',
              action: TextButton(
                onPressed: refresh,
                child: const Text('刷新当前通知'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.all(24),
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
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ContentPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const FeatureIcon(LucideIcons.messageSquare),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  value(notification, 'appName', '手机通知'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '通知操作',
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'hide',
                                    child: Text('仅在本机隐藏'),
                                  ),
                                  if (notification['canDismiss'] == true)
                                    const PopupMenuItem(
                                      value: 'dismiss',
                                      child: Text('清除手机上的通知'),
                                    ),
                                ],
                                onSelected: (action) async {
                                  if (action == 'hide') {
                                    hidden.value = {
                                      ...hidden.value,
                                      value(notification, 'id'),
                                    };
                                  } else {
                                    await perform(
                                      context,
                                      controller,
                                      'notifications.dismiss',
                                      {
                                        'deviceId': device['id'],
                                        'notificationId': notification['id'],
                                      },
                                    );
                                    refresh();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            value(notification, 'title'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(value(notification, 'body')),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            children: [
                              OutlinedButton(
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
                                child: Text(
                                  notification['canOpen'] == false
                                      ? '在手机上查看'
                                      : '进入手机原应用',
                                ),
                              ),
                              if (notification['canReply'] == true)
                                TextButton(
                                  onPressed: () => NotificationReplyRoute(
                                    deviceId: value(device, 'id'),
                                    notificationId: value(notification, 'id'),
                                  ).push<void>(context),
                                  child: const Text('快捷回复'),
                                ),
                            ],
                          ),
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
