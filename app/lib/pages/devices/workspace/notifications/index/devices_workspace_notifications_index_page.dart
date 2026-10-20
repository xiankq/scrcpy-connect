import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
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
        for (final item in candidates) {
          // Each opaque reference is checked on the phone again. Never hide
          // an item locally or retry a command with an unknown result.
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
            tooltip: '全部已读',
            onPressed: clearing.value ? null : clearAll,
            icon: const Icon(LucideIcons.checkCheck),
          ),
        ),
      ],
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
          final hasStatus =
              data['status'] == 'limited' && value(data, 'reason').isNotEmpty;
          final offset = hasStatus ? 1 : 0;
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
                if (hasStatus && index == 0) {
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
                  child: _NotificationCard(
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

class _NotificationCard extends HookWidget {
  const _NotificationCard({
    required this.controller,
    required this.device,
    required this.notification,
    required this.clearing,
    required this.onClear,
  });
  final AppController controller;
  final Json device;
  final Json notification;
  final bool clearing;
  final VoidCallback onClear;

  Future<void> _open(BuildContext context) async {
    if (notification['canOpen'] == false) {
      feedback(context, '这条通知没有可接续的原始动作，将打开手机界面。');
      await openRemoteRoute(context, deviceId: value(device, 'id'));
      return;
    }
    try {
      final result = await controller.request('notifications.open', {
        'deviceId': device['id'],
        'notificationId': notification['id'],
      });
      if (!context.mounted) return;
      if (result['located'] != true) {
        feedback(context, value(result, 'message', '未能定位原内容，将打开手机界面'));
      }
    } catch (error) {
      if (!context.mounted) return;
      feedback(context, '$error');
      if (error is! RequestFailure || error.code != 'authentication_required') {
        return;
      }
    }
    if (context.mounted) {
      await openRemoteRoute(context, deviceId: value(device, 'id'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final opening = useState(false);
    final appName = value(notification, 'appName').trim();
    final packageName = value(notification, 'packageName');
    final timestamp = notification['postedAt'];
    final posted =
        timestamp is int && timestamp > 0 && timestamp <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final time = posted == null
        ? null
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(posted),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final sameDay =
        posted != null &&
        posted.year == now.year &&
        posted.month == now.month &&
        posted.day == now.day;
    final timeLabel = posted == null
        ? null
        : sameDay
        ? time
        : '${localizations.formatShortMonthDay(posted)} · $time';
    return ContentPanel(
      key: ValueKey('notification-${value(notification, 'id')}'),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: opening.value
              ? null
              : () async {
                  opening.value = true;
                  try {
                    await _open(context);
                  } finally {
                    if (context.mounted) opening.value = false;
                  }
                },
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (packageName.isNotEmpty)
                      SizedBox.square(
                        dimension: DesignTokens.componentSmallButtonSize,
                        child: FittedBox(
                          child: PhoneAppIcon(
                            controller: controller,
                            deviceId: value(device, 'id'),
                            packageName: packageName,
                            userId: notification['userId'] == null
                                ? null
                                : value(notification, 'userId'),
                          ),
                        ),
                      )
                    else
                      const Icon(LucideIcons.imageOff, semanticLabel: '图标暂不可用'),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: DesignTokens.spacingSm,
                        runSpacing: DesignTokens.spacingXxs,
                        children: [
                          Text(
                            appName.isEmpty || appName == packageName
                                ? '手机通知'
                                : appName,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (timeLabel != null)
                            Text(
                              timeLabel,
                              semanticsLabel:
                                  '收到于 ${localizations.formatFullDate(posted!)} $time',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
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
                if (notification['canOpen'] == false)
                  const StateNote('此通知没有可接续的原始动作；点击将仅打开手机界面。'),
                if (notification['canDismiss'] is bool ||
                    notification['canReply'] == true) ...[
                  const SizedBox(height: DesignTokens.spacingSm),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: DesignTokens.spacingSm,
                      runSpacing: DesignTokens.spacingXxs,
                      children: [
                        if (notification['canDismiss'] == true)
                          GlassTooltip(
                            message: '已读（清除）',
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  DesignTokens.componentIconButtonSize,
                                  DesignTokens.componentIconButtonSize,
                                ),
                              ),
                              onPressed: clearing ? null : onClear,
                              icon: const Icon(
                                LucideIcons.checkCheck,
                                size: DesignTokens.componentIconSmallSize,
                              ),
                              label: const Text('已读（清除）'),
                            ),
                          )
                        else if (notification['canDismiss'] == false)
                          Text(
                            '手机系统将此项标为不可清除，请在原应用中处理。',
                            style: Theme.of(context).textTheme.bodySmall,
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
