import 'dart:async';

import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/clipboard_coordinator.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ConnectApp extends HookConsumerWidget {
  const ConnectApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider.notifier);
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final appPendingShares = ref.watch(
      appControllerProvider.select((state) => state.pendingShares),
    );
    final appEventRevision = ref.watch(
      appControllerProvider.select((state) => state.eventRevision),
    );
    ref.watch(clipboardCoordinatorProvider);
    final navigator = useMemoized(() => GlobalKey<NavigatorState>());
    final router = useMemoized(() => createAppRouter(navigatorKey: navigator), [
      controller,
    ]);
    useEffect(() => router.dispose, [router]);
    final sharing = useRef<String?>(null);
    final shareCycle = useState(0);
    final lifecycle = useAppLifecycleState();
    final systemNotifications = ref.watch(
      systemNotificationCoordinatorProvider,
    );
    useListenable(systemNotifications.changes);
    useOnAppLifecycleStateChange((previous, current) {
      // Pausing can prevent the next frame. Delivery eligibility must change
      // in the lifecycle callback, before any subsequent source event.
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
      appControllerProvider.select(
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
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
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
    useEffect(
      () {
        if (sharing.value != null ||
            appPendingShares.isEmpty ||
            (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
          return null;
        }
        final share = appPendingShares.first;
        sharing.value = value(share, 'shareId');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final state = navigator.currentState;
          if (state == null || !state.mounted) {
            sharing.value = null;
            return;
          }
          await IncomingShareRoute(shareId: value(share, 'shareId'))
              .push<void>(state.context);
          sharing.value = null;
          if (state.mounted) shareCycle.value++;
        });
        return null;
      },
      [appPendingShares.length, appEventRevision, lifecycle, shareCycle.value],
    );
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
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingLg,
                    0,
                    DesignTokens.spacingLg,
                    DesignTokens.spacingLg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FeatureIcon(
                        LucideIcons.phoneIncoming,
                        color: ConnectTokens.mint,
                        size: 64,
                      ),
                      const SizedBox(height: DesignTokens.spacingMd),
                      Text(
                        value(call, 'name', value(call, 'number', '当前来电')),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: DesignTokens.spacingTight),
                      Text('${deviceName(device)} 有来电'),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          CallsRoute(deviceId: value(device, 'id'))
                              .push<void>(navigator.currentContext!);
                        },
                        child: const Text('查看来电与声音'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          openRemoteRoute(
                            navigator.currentContext!,
                            deviceId: value(device, 'id'),
                          );
                        },
                        child: const Text('在手机上处理'),
                      ),
                      const StateNote('新的来电不会自动接听或抢占现有通话。'),
                    ],
                  ),
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
    final mode = switch (appSettings['appearance']) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    final lightTheme = useMemoized(() => _appTheme(Brightness.light));
    final darkTheme = useMemoized(() => _appTheme(Brightness.dark));
    return MaterialApp.router(
      title: '邻接',
      restorationScopeId: 'connect-app',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
    );
  }
}

ThemeData _appTheme(Brightness brightness) =>
    ConnectTokens.theme(brightness).copyWith(
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(LucideIcons.chevronLeft),
        ),
        closeButtonIconBuilder: (_) => const Icon(LucideIcons.x),
        drawerButtonIconBuilder: (_) => const Icon(LucideIcons.menu),
        endDrawerButtonIconBuilder: (_) => const Icon(LucideIcons.menu),
      ),
    );
