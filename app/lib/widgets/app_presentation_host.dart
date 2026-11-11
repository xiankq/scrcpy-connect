import 'package:scrcpy_connect/widgets/clipboard_visibility.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/stores/clipboard_sync_store.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/router/app_router.dart';

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
    final controller = ref.watch(appStoreProvider.notifier);
    final appPendingShares = ref.watch(
      appStoreProvider.select((state) => state.pendingShares),
    );
    final clipboard = ref.watch(clipboardSyncProvider);
    useClipboardVisibility(clipboard);
    final sharing = useRef<Object?>(null);
    final shareCycle = useState(0);
    final lifecycle = useAppLifecycleState();
    final systemNotifications = useSystemNotifications(context, ref);
    useListenable(systemNotifications.changes);
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
      appStoreProvider.select(
        (state) => state.loading || state.reconciliationPending,
      ),
    );
    useEffect(() {
      if (appLoading ||
          systemNotifications.pendingActivation == null ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return null;
      }
      var active = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!active ||
            controller.snapshot().loading ||
            controller.snapshot().reconciliationPending ||
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
          showGlassDialog<void>(
            context: context,
            builder: (context) => GlassAlertDialog(
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
              NotificationsRoute(deviceId: activation.target.deviceId).location,
            );
          case SystemNotificationKind.call:
            router.push<void>(
              CallsRoute(deviceId: activation.target.deviceId).location,
            );
        }
      });
      return () => active = false;
    }, [systemNotifications.pendingActivation, appLoading, lifecycle, router]);
    useEffect(() {
      if (appLoading ||
          sharing.value != null ||
          appPendingShares.isEmpty ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return null;
      }
      final share = appPendingShares.first;
      final shareId = value(share, 'shareId');
      final reservation = Object();
      sharing.value = reservation;
      var active = true;
      var opened = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final state = navigator.currentState;
        if (!active ||
            state == null ||
            !state.mounted ||
            controller.snapshot().loading ||
            controller.snapshot().reconciliationPending ||
            (WidgetsBinding.instance.lifecycleState != null &&
                WidgetsBinding.instance.lifecycleState !=
                    AppLifecycleState.resumed)) {
          if (identical(sharing.value, reservation)) sharing.value = null;
          return;
        }
        opened = true;
        await IncomingShareRoute(shareId: shareId).push<void>(state.context);
        if (identical(sharing.value, reservation)) sharing.value = null;
        if (context.mounted && state.mounted) shareCycle.value++;
      });
      return () {
        active = false;
        if (!opened && identical(sharing.value, reservation)) {
          sharing.value = null;
        }
      };
    }, [appPendingShares, appLoading, lifecycle, shareCycle.value]);
    final presentedCall = useRef<String?>(null);
    final callPresentationEpoch = useRef(0);
    useOnAppLifecycleStateChange((previous, current) {
      if (current != AppLifecycleState.resumed) {
        callPresentationEpoch.value++;
      }
    });
    useEffect(() {
      var active = true;
      final subscription = controller.eventStream().listen((event) {
        if (!['calls.incoming', 'call.incoming'].contains(event['type']) ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        final data = jsonObject(event['data']);
        final call = data['id'] != null
            ? data
            : objects(data['calls'])
                  .where((call) => call['state'] == 'ringing')
                  .firstOrNull;
        if (call == null || data['live'] == false) return;
        final id = value(call, 'id');
        final key = '${event['deviceId']}:$id';
        if (id.isEmpty || presentedCall.value == key) return;
        final matches = controller.snapshot().devices.where(
          (d) => d['id'] == event['deviceId'],
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
              CallsRoute(deviceId: value(device, 'id')).location) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.transparent,
              elevation: 0,
              padding: EdgeInsets.zero,
              duration: const Duration(seconds: 8),
              content: Glass(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Row(
                  children: [
                    const ListIconBadge(
                      icon: LucideIcons.phoneIncoming,
                      backgroundColor: DesignTokens.colorListIconMint,
                    ),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(
                      child: Text(
                        '${deviceName(device)} · ${value(call, 'name', value(call, 'number', '当前来电'))}\n声音仍在手机',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        CallsRoute(deviceId: value(device, 'id'))
                            .push<void>(context);
                      },
                      child: const Text('查看电话'),
                    ),
                  ],
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
    }, [controller, navigator]);
    return SystemNotificationsScope(
      notifications: systemNotifications,
      child: child,
    );
  }
}
