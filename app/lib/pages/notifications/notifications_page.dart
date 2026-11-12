import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/notifications/widgets/notification_card.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_source_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

class NotificationsPage extends HookConsumerWidget {
  const NotificationsPage({super.key, required this.device});
  final DeviceSnapshot device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = useSystemNotifications(context, ref);
    useListenable(alerts.changes);
    final settings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    final enablingAlerts = useState(false);
    final alertStatus = alerts.status;
    final showEnableAlerts =
        settings.notificationAlerts != true ||
        !alertStatus.supported ||
        alertStatus.permissionGranted != true ||
        alertStatus.notificationChannelEnabled == false;
    Future<void> enableAlerts() async {
      if (enablingAlerts.value) return;
      enablingAlerts.value = true;
      try {
        // 通知页只开启通知意图，来电意图仍由用户单独选择。
        await ref
            .read(preferencesProvider.notifier)
            .update(PreferenceChanges(notificationAlerts: true));
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
    final deviceId = device.id;
    useEffect(
      () => alerts.claimNotificationPage(
        deviceId,
        () => context.mounted && route?.isCurrent != false,
      ),
      [alerts, deviceId, route],
    );
    final notificationsAccess = ref.watch(deviceNotificationsProvider);
    final queryProvider = deviceNotificationsSnapshotProvider(device.id);
    final query = ref.watch(queryProvider);
    void refresh() => ref.invalidate(queryProvider);
    final clearing = useValueNotifier(false, [notificationsAccess, device.id]);
    useListenable(clearing);
    final currentClearing = useRef(clearing);
    currentClearing.value = clearing;
    bool notificationsCurrent() =>
        context.mounted &&
        identical(currentClearing.value, clearing) &&
        identical(notificationsAccess, ref.read(deviceNotificationsProvider));

    Future<void> clearAll() async {
      if (clearing.value || !notificationsCurrent()) return;
      clearing.value = true;
      try {
        final current = await notificationsAccess.readNotifications(device.id);
        if (!context.mounted || !notificationsCurrent()) return;
        if (!current.live) {
          feedback(context, '请先核验手机当前通知，再清除。');
          return;
        }
        var cleared = 0;
        var pending = 0;
        var failed = 0;
        final candidates = current.notifications
            .where((item) => item.canDismiss == true)
            .toList();
        if (candidates.isNotEmpty &&
            (!await confirm(
                  context,
                  '清除全部通知？',
                  '将清除 ${deviceName(device)} 当前可清除的 ${candidates.length} 条通知。常驻通知和无法核验的通知会保留；清除不代表原应用已读。',
                  action: '清除通知',
                ) ||
                !notificationsCurrent())) {
          return;
        }
        for (final item in candidates) {
          // 每个不透明引用都在手机再次核验，不本机隐藏项目，也不重试结果未知的动作。
          if (!context.mounted || !notificationsCurrent()) return;
          try {
            final dismissed = await notificationsAccess.dismissNotification(
              device.id,
              item.id,
            );
            if (!context.mounted || !notificationsCurrent()) return;
            if (dismissed) {
              cleared++;
            } else {
              pending++;
            }
          } catch (_) {
            if (!context.mounted || !notificationsCurrent()) return;
            failed++;
          }
        }
        if (context.mounted && notificationsCurrent()) {
          refresh();
          feedback(
            context,
            candidates.isEmpty
                ? '没有可清除的通知；常驻通知由手机应用管理。'
                : '已清除 $cleared 条通知'
                      '${pending > 0 ? '，$pending 条等待手机确认' : ''}'
                      '${failed > 0 ? '，$failed 条未能确认，请刷新核对' : ''}。',
          );
        }
      } catch (error) {
        if (context.mounted && notificationsCurrent()) {
          feedback(context, '$error');
        }
      } finally {
        if (notificationsCurrent()) clearing.value = false;
      }
    }

    Future<void> clearNotification(DeviceNotification notification) async {
      if (clearing.value || !notificationsCurrent()) return;
      clearing.value = true;
      try {
        final dismissed = await notificationsAccess.dismissNotification(
          device.id,
          notification.id,
        );
        if (context.mounted && notificationsCurrent()) {
          refresh();
          feedback(context, dismissed ? '已清除手机上的通知。' : '清除请求已提交，等待手机确认。');
        }
      } catch (error) {
        if (context.mounted && notificationsCurrent()) {
          refresh();
          feedback(context, '$error');
        }
      } finally {
        if (notificationsCurrent()) clearing.value = false;
      }
    }

    final observation = ref.watch(deviceObservationProvider);
    final starting = useValueNotifier(false, [observation, device.id]);
    useListenable(starting);
    final currentStarting = useRef(starting);
    currentStarting.value = starting;
    bool observationCurrent() =>
        context.mounted &&
        identical(currentStarting.value, starting) &&
        identical(observation, ref.read(deviceObservationProvider));
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
      child: AsyncContent(
        loading: query.isLoading,
        data: query.value,
        error: query.error,
        onRefresh: refresh,
        emptyTitle: '当前无法同步通知',
        alternative: TextButton(
          onPressed: () => openRemoteRoute(context, deviceId: device.id),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data) {
          Future<void> verify() async {
            if (starting.value) return;
            starting.value = true;
            try {
              await observation.startObservation(device.id);
              if (observationCurrent()) refresh();
            } catch (error) {
              if (context.mounted && observationCurrent()) {
                feedback(context, '$error');
              }
            } finally {
              if (observationCurrent()) starting.value = false;
            }
          }

          final notifications = data.notifications
              .where(
                (n) =>
                    !n.groupSummary ||
                    n.title.trim().isNotEmpty ||
                    n.body.trim().isNotEmpty,
              )
              .toList();
          final state = data.status;
          if (notifications.isEmpty && state != .available) {
            return emptyWithHeader(
              EmptyContent(
                icon: LucideIcons.bellOff,
                title: switch (state) {
                  .needsSetup => '通知访问需要设置',
                  .stopped => '通知观察已停止',
                  .unknown || .checking || .starting => '通知状态尚未核验',
                  .available || .limited => '通知同步受限',
                },
                message: data.reason ?? '这台设备尚未提供可靠的通知访问。你可以在手机原应用中处理。',
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () =>
                          openRemoteRoute(context, deviceId: device.id),
                      child: const Text('在手机上查看'),
                    ),
                    TextButton(
                      onPressed: starting.value ? null : verify,
                      child: Text(state == .stopped ? '启用通知与来电观察' : '重新核验通知'),
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
              data.status == .limited && (data.reason?.isNotEmpty ?? false);
          final offset = hasStatus ? 2 : 1;
          Key notificationKey(DeviceNotification item) =>
              ValueKey('${device.id}:${item.id}');
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
                  return StateNote(data.reason!, icon: LucideIcons.circleAlert);
                }
                final notification = notifications[index - offset];
                return Padding(
                  key: notificationKey(notification),
                  padding: const EdgeInsets.only(
                    bottom: DesignTokens.spacingSm,
                  ),
                  child: NotificationCard(
                    device: device,
                    notification: notification,
                    clearing: clearing.value,
                    onClear: () => clearNotification(notification),
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
