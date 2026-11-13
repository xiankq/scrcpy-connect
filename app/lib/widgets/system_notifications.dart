import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/notifications/system_notifications.dart';
import 'package:scrcpy_connect/core/notifications/system_notification_sink_provider.dart';
import 'package:scrcpy_connect/core/notifications/models/system_notification_snapshot.dart';

/// 界面拥有提醒订阅、展示与销毁；provider 只提供可替换的系统能力。
SystemNotifications useSystemNotifications(
  BuildContext context,
  WidgetRef ref,
) {
  final shared = context
      .dependOnInheritedWidgetOfExactType<SystemNotificationsScope>()
      ?.notifications;
  final events = ref.watch(runtimeEventsProvider);
  final sink = ref.watch(systemNotificationSinkProvider);
  final notifications = useMemoized(
    () =>
        shared ??
        SystemNotifications(
          events: events,
          sink: sink,
          current: () =>
              context.mounted &&
              identical(ref.read(runtimeEventsProvider), events) &&
              identical(ref.read(systemNotificationSinkProvider), sink),
          readSnapshot: () {
            final snapshot = ref.read(appSnapshotProvider);
            return SystemNotificationSnapshot(
              devices: snapshot.devices,
              settings: snapshot.settings,
              loading: snapshot.loading,
              reconciliationPending: snapshot.reconciliationPending,
            );
          },
        ),
    [shared, events, sink],
  );
  ref.listen(
    appSnapshotProvider.select(
      (state) => (
        state.devices,
        state.settings,
        state.loading,
        state.reconciliationPending,
      ),
    ),
    (_, next) {
      if (shared == null) notifications.configure();
    },
  );
  useEffect(() {
    if (shared != null) return null;
    unawaited(notifications.initialize());
    return notifications.dispose;
  }, [shared, notifications]);
  return notifications;
}

class SystemNotificationsScope extends InheritedWidget {
  const SystemNotificationsScope({
    super.key,
    required this.notifications,
    required super.child,
  });
  final SystemNotifications notifications;
  @override
  bool updateShouldNotify(SystemNotificationsScope oldWidget) =>
      notifications != oldWidget.notifications;
}
