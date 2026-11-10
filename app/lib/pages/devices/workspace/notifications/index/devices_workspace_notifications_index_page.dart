import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/widgets/notification_card.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_source_row.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationsPage extends HookConsumerWidget {
  const NotificationsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppStore controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(systemNotificationsProvider);
    useListenable(alerts.changes);
    final settings = ref.watch(
      appStoreProvider.select((state) => state.settings),
    );
    final enablingAlerts = useState(false);
    final alertStatus = alerts.status;
    final showEnableAlerts =
        settings['notificationAlerts'] != true ||
        !alertStatus.supported ||
        alertStatus.permissionGranted != true ||
        alertStatus.notificationChannelEnabled == false;
    Future<void> enableAlerts() async {
      if (enablingAlerts.value) return;
      enablingAlerts.value = true;
      try {
        // 通知页只开启通知意图，来电意图仍由用户单独选择。
        await controller.updateSetting('notificationAlerts', true);
        var status = await alerts.refreshStatus();
        final requested = status.permissionGranted != true && status.canRequest;
        if (requested) {
          status = await alerts.requestPermission();
        }
        if (!context.mounted) return;
        if (status.supported &&
            status.permissionGranted == true &&
            status.notificationChannelEnabled != false) {
          feedback(context, '系统通知提醒已开启；当前通知页可见时仅更新列表。');
        } else if (!requested && status.canOpenSettings) {
          final opened = await alerts.openSettings();
          if (context.mounted) {
            feedback(
              context,
              opened
                  ? '请在系统设置中允许通知提醒；仍可在这里查看当前通知。'
                  : '暂时无法打开系统通知设置；仍可在这里查看当前通知。',
            );
          }
        } else {
          feedback(
            context,
            '${status.reason.isEmpty ? '系统提醒尚未获准' : status.reason}；仍可在这里查看当前通知。',
          );
        }
      } catch (error) {
        if (context.mounted) feedback(context, '系统提醒未能确认开启：$error');
      } finally {
        if (context.mounted) enablingAlerts.value = false;
      }
    }

    final notificationHeader = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceSourceRow(
          device: device,
          padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
        ),
        if (showEnableAlerts)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
            child: OutlinedButton(
              onPressed: enablingAlerts.value ? null : enableAlerts,
              child: Text(enablingAlerts.value ? '正在核验系统提醒…' : '开启系统提醒'),
            ),
          ),
      ],
    );
    Widget emptyWithHeader(Widget content) => PageChromeBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: notificationHeader,
          ),
          Expanded(child: content),
        ],
      ),
    );
    final route = ModalRoute.of(context);
    final deviceId = value(device, 'id');
    useEffect(
      () => alerts.claimNotificationPage(
        deviceId,
        () => context.mounted && route?.isCurrent != false,
      ),
      [alerts, deviceId, route],
    );
    final clearing = useState(false);
    final refreshing = useRef<VoidCallback?>(null);

    Future<void> clearAll() async {
      if (clearing.value) return;
      clearing.value = true;
      try {
        final current = await perform(
          context,
          controller,
          'notifications.list',
          {'deviceId': device['id']},
        );
        if (current == null || !context.mounted) return;
        if (current['live'] != true) {
          feedback(context, '请先核验手机当前通知，再清除。');
          return;
        }
        var cleared = 0;
        var pending = 0;
        var failed = 0;
        final candidates = objects(current['notifications'])
            .where((item) => item['canDismiss'] == true)
            .toList();
        if (candidates.isNotEmpty &&
            (!await confirm(
                  context,
                  '清除全部通知？',
                  '将清除 ${deviceName(device)} 当前可清除的 ${candidates.length} 条通知。常驻通知和无法核验的通知会保留；清除不代表原应用已读。',
                  action: '清除通知',
                ) ||
                !context.mounted)) {
          return;
        }
        for (final item in candidates) {
          // 每个不透明引用都在手机再次核验，不本机隐藏项目，也不重试结果未知的命令。
          try {
            final result = await controller.request('notifications.dismiss', {
              'deviceId': device['id'],
              'notificationId': item['id'],
            });
            if (result['dismissed'] == true) {
              cleared++;
            } else {
              pending++;
            }
          } catch (_) {
            failed++;
          }
        }
        if (context.mounted) {
          refreshing.value?.call();
          feedback(
            context,
            candidates.isEmpty
                ? '没有可清除的通知；常驻通知由手机应用管理。'
                : '已清除 $cleared 条通知'
                      '${pending > 0 ? '，$pending 条等待手机确认' : ''}'
                      '${failed > 0 ? '，$failed 条未能确认，请刷新核对' : ''}。',
          );
        }
      } finally {
        if (context.mounted) clearing.value = false;
      }
    }

    final starting = useState(false);
    return PageFrame(
      title: '实时通知',
      actions: [
        Semantics(
          liveRegion: true,
          value: clearing.value ? '正在清除通知' : '',
          child: GlassActionIcon(
            tooltip: '清除全部通知',
            onPressed: clearing.value ? null : clearAll,
            icon: const Icon(LucideIcons.checkCheck),
          ),
        ),
      ],
      child: CommandView(
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
          refreshing.value = refresh;
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
              .where(
                (n) =>
                    n['groupSummary'] != true ||
                    value(n, 'title').trim().isNotEmpty ||
                    value(n, 'body').trim().isNotEmpty,
              )
              .toList();
          final state = value(data, 'status', 'unknown');
          if (notifications.isEmpty && state != 'available') {
            return emptyWithHeader(
              EmptyContent(
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
            return emptyWithHeader(
              EmptyContent(
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
          final hasStatus =
              data['status'] == 'limited' && value(data, 'reason').isNotEmpty;
          final offset = hasStatus ? 2 : 1;
          Key notificationKey(Json item) =>
              ValueKey('${value(device, 'id')}:${value(item, 'id')}');
          final indices = <Key, int>{
            for (var index = 0; index < notifications.length; index++)
              notificationKey(notifications[index]): index + offset,
          };
          return RefreshIndicator(
            onRefresh: verify,
            child: GroupedListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              itemCount: notifications.length + offset,
              findChildIndexCallback: (key) => indices[key],
              itemBuilder: (context, index) {
                if (index == 0) {
                  return notificationHeader;
                }
                if (hasStatus && index == 1) {
                  return StateNote(
                    value(data, 'reason'),
                    icon: LucideIcons.circleAlert,
                  );
                }
                final notification = notifications[index - offset];
                return Padding(
                  key: notificationKey(notification),
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingSm,
                  ),
                  child: NotificationCard(
                    controller: controller,
                    device: device,
                    notification: notification,
                    clearing: clearing.value,
                    onClear: () async {
                      if (clearing.value) return;
                      clearing.value = true;
                      try {
                        final result = await perform(
                          context,
                          controller,
                          'notifications.dismiss',
                          {
                            'deviceId': device['id'],
                            'notificationId': notification['id'],
                          },
                        );
                        if (context.mounted) {
                          refresh();
                          if (result != null) {
                            feedback(
                              context,
                              result['dismissed'] == true
                                  ? '已清除手机上的通知。'
                                  : '清除请求已提交，等待手机确认。',
                            );
                          }
                        }
                      } finally {
                        if (context.mounted) clearing.value = false;
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
