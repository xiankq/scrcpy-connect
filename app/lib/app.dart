import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:foldable/foldable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/system_typography.dart';
import 'package:scrcpy_connect/styles/system_visual_preferences.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/app_lifecycle_observer.dart';
import 'package:scrcpy_connect/widgets/app_presentation_host.dart';
import 'package:scrcpy_connect/widgets/app_session_scope.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';

class ConnectApp extends HookConsumerWidget {
  const ConnectApp({
    super.key,
    this.initialLocation = '/devices',
    this.glassReady = true,
    this.desktopWindow = false,
  });

  final String initialLocation;
  final bool glassReady;
  final bool desktopWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = AppSessionScope.maybeOf(context)?.ready ?? true;
    final appearance = ready
        ? ref.watch(
            preferencesProvider.select((state) => state.values.appearance),
          )
        : Appearance.system;
    final navigator = useMemoized(() => GlobalKey<NavigatorState>());
    final router = useMemoized(
      () => createAppRouter(
        navigatorKey: navigator,
        initialLocation: initialLocation,
      ),
      [initialLocation],
    );
    useEffect(() => router.dispose, [router]);
    final contentKey = useMemoized(GlobalKey.new);
    final systemVisualPreferences = useMemoized(SystemVisualPreferences.new);
    useListenable(systemVisualPreferences);
    useEffect(() {
      systemVisualPreferences.start();
      return systemVisualPreferences.dispose;
    }, [systemVisualPreferences]);
    final systemTypography = useMemoized(SystemTypography.new);
    useListenable(systemTypography);
    useEffect(() {
      systemTypography.start();
      return systemTypography.dispose;
    }, [systemTypography]);
    final mode = switch (appearance) {
      Appearance.dark => ThemeMode.dark,
      Appearance.system => ThemeMode.system,
      Appearance.light => ThemeMode.light,
    };
    final fontFamily = systemTypography.fontFamily;
    final lightTheme = useMemoized(
      () => _appTheme(Brightness.light, fontFamily),
      [fontFamily],
    );
    final darkTheme = useMemoized(
      () => _appTheme(Brightness.dark, fontFamily),
      [fontFamily],
    );
    return MaterialApp.router(
      title: '邻接',
      restorationScopeId: 'connect-app',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      builder: (context, child) {
        final content = KeyedSubtree(key: contentKey, child: child!);
        final application = FoldableProvider(
          // Expose the hinge while the iPhone Duo is partially open.
          bridgeMode: DisplayFeatureBridgeMode.full,
          child: WindowEnvironmentScope(
            child: liquid.GlassTheme(
              data: GlassMaterial.theme(context),
              child: liquid.GlassAccessibilityScope(
                reduceTransparency:
                    !glassReady ||
                    systemVisualPreferences.reduceTransparency ||
                    MediaQuery.highContrastOf(context) ||
                    liquid.GlassAccessibilityData.of(context)
                        .reduceTransparency,
                child: liquid.GlassNavigationShell(
                  child: ready
                      ? _SessionPresentation(
                          navigator: navigator,
                          router: router,
                          child: content,
                        )
                      : content,
                ),
              ),
            ),
          ),
        );
        return desktopWindow
            ? DesktopWindowFrame(child: application)
            : application;
      },
    );
  }
}

class _SessionPresentation extends HookConsumerWidget {
  const _SessionPresentation({
    required this.navigator,
    required this.router,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigator;
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(stateSubscriptionProvider);
    final events = ref.watch(runtimeEventsProvider);
    final videos = ref.watch(videoSessionsProvider);
    final audio = ref.watch(remoteAudioProvider);
    final appSession = ref.watch(appSessionProvider);
    useEffect(() {
      final lifecycle = AppLifecycleObserver(
        setVisible: appSession.setVisible,
        diagnostics: appSession.diagnostics,
        shutdown: appSession.close,
      );
      unawaited(lifecycle.attach());
      return lifecycle.dispose;
    }, [appSession]);
    final views = useMemoized(() {
      bool current() =>
          context.mounted &&
          !session.disposed &&
          identical(ref.read(stateSubscriptionProvider), session) &&
          identical(ref.read(runtimeEventsProvider), events) &&
          identical(ref.read(videoSessionsProvider), videos) &&
          identical(ref.read(remoteAudioProvider), audio);
      return RemoteViews(
        videos: videos,
        audio: audio,
        events: events,
        current: current,
        readSnapshot: () {
          if (!current()) {
            return const DeviceAudioViewSnapshot(
              devices: [],
              reconciliationPending: true,
            );
          }
          final snapshot = ref.read(appSnapshotProvider);
          return DeviceAudioViewSnapshot(
            devices: snapshot.devices,
            reconciliationPending: snapshot.reconciliationPending,
          );
        },
        onAudioError: (error) {
          if (current()) ref.read(audioErrorProvider.notifier).update(error);
        },
      );
    }, [session, events, videos, audio]);
    useEffect(() => views.dispose, [views]);
    ref.listen(
      appSnapshotProvider.select((s) => (s.devices, s.reconciliationPending)),
      (_, _) => views.reconcile(),
    );
    return RemoteViewsScope(
      views: views,
      child: AppPresentationHost(
        navigator: navigator,
        router: router,
        child: child,
      ),
    );
  }
}

ThemeData _appTheme(Brightness brightness, String? fontFamily) =>
    ConnectTokens.theme(brightness, fontFamily: fontFamily).copyWith(
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
