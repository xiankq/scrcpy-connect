import 'package:scrcpy_connect/core/notifications/models/system_notice.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_sync_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_event.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/clipboard_visibility.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/banner.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

/// 来电横幅停留到用户能读完并决定是否查看电话。
const _incomingCallBannerDuration = Duration(seconds: 8);

/// 应用根部的外部意图呈现边界；调度与迟到回调必须同时遵循当前前台资格。
class AppPresentationHost extends HookConsumerWidget {
  const AppPresentationHost({
    super.key,
    required this.navigator,
    required this.router,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigator;
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(runtimeEventsProvider);
    final appPendingShares = ref.watch(
      shareInboxProvider.select((state) => state.shares),
    );
    final clipboard = ref.watch(clipboardSyncProvider.notifier);
    useClipboardVisibility(clipboard);
    final sharing = useRef<Object?>(null);
    final shareCycle = useState(0);
    final lifecycle = useAppLifecycleState();
    final systemNotifications = useSystemNotifications(context, ref);
    useStream(systemNotifications.changes);
    useOnAppLifecycleStateChange((previous, current) {
      // 暂停后可能不再绘制下一帧，因此在生命周期回调中立即更新提醒资格。
      systemNotifications.setForeground(current == AppLifecycleState.resumed);
      if (current == AppLifecycleState.resumed) {
        unawaited(systemNotifications.refreshStatus());
      }
    });
    useEffect(() {
      systemNotifications.setForeground(
        lifecycle == null || lifecycle == AppLifecycleState.resumed,
      );
      return null;
    }, [systemNotifications, lifecycle]);
    final appLoading = ref.watch(
      appSnapshotProvider.select(
        (state) => state.loading || state.reconciliationPending,
      ),
    );
    useEffect(
      () {
        if (appLoading ||
            systemNotifications.pendingActivation == null ||
            (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
          return null;
        }
        var active = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!active ||
              ref.read(appSnapshotProvider).loading ||
              ref.read(appSnapshotProvider).reconciliationPending ||
              (WidgetsBinding.instance.lifecycleState != null &&
                  WidgetsBinding.instance.lifecycleState !=
                      AppLifecycleState.resumed)) {
            return;
          }
          final context = navigator.currentContext;
          if (context == null || !context.mounted) return;
          final activation = systemNotifications.takeActivation();
          if (activation == null) return;
          if (!activation.available) {
            showAppDialog<void>(
              context: context,
              builder: (context) => AppAlertDialog(
                title: const Text('这条提醒已失效'),
                content: Text(activation.reason),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            );
            return;
          }
          switch (activation.target.kind) {
            case SystemNotificationKind.notification:
              router.push<void>(
                NotificationsRoute(deviceId: activation.target.deviceId)
                    .location,
              );
            case SystemNotificationKind.call:
              router.push<void>(
                CallsRoute(deviceId: activation.target.deviceId).location,
              );
          }
        });
        return () => active = false;
      },
      [
        systemNotifications,
        systemNotifications.pendingActivation,
        appLoading,
        lifecycle,
        router,
      ],
    );
    useEffect(() {
      if (appLoading ||
          sharing.value != null ||
          appPendingShares.isEmpty ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return null;
      }
      final share = appPendingShares.first;
      final shareId = share.shareId;
      final reservation = Object();
      sharing.value = reservation;
      var active = true;
      var opened = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final state = navigator.currentState;
        if (!active ||
            state == null ||
            !state.mounted ||
            ref.read(appSnapshotProvider).loading ||
            ref.read(appSnapshotProvider).reconciliationPending ||
            (WidgetsBinding.instance.lifecycleState != null &&
                WidgetsBinding.instance.lifecycleState !=
                    AppLifecycleState.resumed)) {
          if (identical(sharing.value, reservation)) sharing.value = null;
          return;
        }
        opened = true;
        await IncomingShareRoute(shareId: shareId).push<void>(state.context);
        if (identical(sharing.value, reservation)) sharing.value = null;
        if (context.mounted &&
            state.mounted &&
            identical(ref.read(runtimeEventsProvider), events)) {
          shareCycle.value++;
        }
      });
      return () {
        active = false;
        if (!opened && identical(sharing.value, reservation)) {
          sharing.value = null;
        }
      };
    }, [events, appPendingShares, appLoading, lifecycle, shareCycle.value]);
    final presentedCall = useRef<String?>(null);
    final callPresentationEpoch = useRef(0);
    useOnAppLifecycleStateChange((previous, current) {
      if (current != AppLifecycleState.resumed) {
        callPresentationEpoch.value++;
      }
    });
    useEffect(() {
      var active = true;
      final subscription = events.listen((event) {
        final change = event.data;
        if (change is! DeviceCallsChanged ||
            !change.incoming ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        final data = change.snapshot;
        final call = data.calls
            .where((call) => call.state == .ringing)
            .firstOrNull;
        if (call == null || !data.verified || !data.observationEnabled) return;
        final id = call.id ?? '';
        final key =
            '${data.deviceId}:${data.observationEpoch}:$id:${call.generation}';
        if (id.isEmpty || presentedCall.value == key) return;
        final snapshot = ref.read(appSnapshotProvider);
        if (snapshot.loading || snapshot.reconciliationPending) return;
        final matches = snapshot.devices.where(
          (d) => d.id == data.deviceId && d.status == .connected,
        );
        if (matches.isEmpty) return;
        presentedCall.value = key;
        final epoch = callPresentationEpoch.value;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = navigator.currentContext;
          if (!active) return;
          if (epoch != callPresentationEpoch.value ||
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed ||
              context == null ||
              !context.mounted) {
            if (presentedCall.value == key) presentedCall.value = null;
            return;
          }
          final device = matches.first;
          if (router.routeInformationProvider.value.uri.path ==
              CallsRoute(deviceId: device.id).location) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.of(context).card.withAlpha(0),
              elevation: 0,
              padding: EdgeInsets.zero,
              duration: _incomingCallBannerDuration,
              content: AppBanner(
                icon: LucideIcons.phoneIncoming,
                message:
                    '${deviceName(device)} · ${call.name ?? call.number ?? '当前来电'}\n声音仍在手机',
                action: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    CallsRoute(deviceId: device.id).push<void>(context);
                  },
                  child: const Text('查看电话'),
                ),
              ),
            ),
          );
        });
      });
      return () {
        active = false;
        presentedCall.value = null;
        unawaited(subscription.cancel());
      };
    }, [events, navigator]);
    return SystemNotificationsScope(
      notifications: systemNotifications,
      child: child,
    );
  }
}
