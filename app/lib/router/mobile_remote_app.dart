import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:foldable/foldable.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/mobile_remote_capabilities.dart';
import 'package:scrcpy_connect/router/mobile_remote_window.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/styles/system_visual_preferences.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/app_lifecycle_observer.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';

/// An independent system window starts only this control UI and its renderer.
final class MobileRemoteApp extends StatefulWidget {
  const MobileRemoteApp({super.key, required this.windowId});
  final String windowId;

  @override
  State<MobileRemoteApp> createState() => _MobileRemoteAppState();
}

class _MobileRemoteAppState extends State<MobileRemoteApp> {
  final _events = ReceivePort();
  late final _messages = _events.asBroadcastStream();
  MobileRemoteClient? _client;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  Future<void> _attach() async {
    final port = IsolateNameServer.lookupPortByName(
      mobileRemoteWindowPort(widget.windowId),
    );
    if (port != null) {
      final client = MobileRemoteClient(widget.windowId, port);
      try {
        await client.attach(_events.sendPort);
        client.requests = _messages
            .where((event) => event is MobileRemoteRequest)
            .cast<MobileRemoteRequest>();
        if (mounted) {
          _client = client;
        } else {
          client.players.dispose();
        }
      } on Exception {
        client.players.dispose();
      }
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  void dispose() {
    _events.close();
    _client?.players.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    if (client == null) {
      MaterialPageRoute<void> startupRoute() => MaterialPageRoute(
        builder: (context) => PopScope(
          canPop: false,
          child: Scaffold(
            body: Center(
              child: _finished
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('原来的控制会话已不可用。'),
                        TextButton(
                          onPressed: () =>
                              const PlatformWindowHost().close(widget.windowId),
                          child: const Text('关闭'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator.adaptive(),
            ),
          ),
        ),
      );
      return MaterialApp(
        key: ValueKey(_finished),
        theme: ConnectTokens.theme(Brightness.light),
        darkTheme: ConnectTokens.theme(Brightness.dark),
        onGenerateRoute: (_) => startupRoute(),
        onGenerateInitialRoutes: (_) => [startupRoute()],
      );
    }
    final attachment = client.attachment!;
    return GlassMaterial.wrap(
      child: ProviderScope(
        overrides: [
          ...client.overrides,
          mobileRemoteClientProvider.overrideWithValue(client),
          appSessionProvider.overrideWithValue(
            AppSession(
              events: _messages
                  .where((event) => event is RuntimeEvent)
                  .cast<RuntimeEvent>(),
              initialState: attachment.state,
              initialize: false,
            ),
          ),
        ],
        child: _MobileRemotePresentation(client: client),
      ),
    );
  }
}

class _MobileRemotePresentation extends HookConsumerWidget {
  const _MobileRemotePresentation({required this.client});
  final MobileRemoteClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachment = client.attachment!;
    final router = useMemoized(
      () => createAppRouter(
        initialLocation: attachment.location,
        initialExtra: attachment.extra,
        observer: sessionRouteObserver,
      ),
    );
    useEffect(() => router.dispose, [router]);
    useEffect(() {
      final observer = AppLifecycleObserver(
        setVisible: client.setVisible,
        shutdown: null,
      );
      unawaited(observer.attach());
      return observer.dispose;
    }, [client]);
    final events = ref.watch(runtimeEventsProvider);
    final views = useMemoized(() {
      return RemoteViews(
        videos: client,
        audio: client,
        events: events,
        current: () => context.mounted,
        readSnapshot: () => DeviceAudioViewSnapshot(
          devices: ref.read(deviceListProvider).devices,
          reconciliationPending: ref
              .read(recoveryStateProvider)
              .reconciliationPending,
        ),
        onAudioError: (_) {},
      );
    }, [client, events]);
    useEffect(() => views.dispose, [views]);
    ref.listen(deviceListProvider, (_, _) => views.reconcile());
    ref.listen(recoveryStateProvider, (_, _) => views.reconcile());

    final appearance = ref.watch(
      preferencesProvider.select((state) => state.values.appearance),
    );
    final glassEffects = ref.watch(
      preferencesProvider.select((state) => state.values.glassEffects),
    );
    final visualPreferences = useMemoized(SystemVisualPreferences.new);
    useListenable(visualPreferences);
    useEffect(() {
      visualPreferences.start();
      return visualPreferences.dispose;
    }, [visualPreferences]);
    final glassReady = useState(GlassMaterial.isInitialized);
    useEffect(() {
      if (glassEffects == GlassEffects.off || glassReady.value) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        try {
          await GlassMaterial.initialize();
          if (context.mounted) glassReady.value = true;
        } catch (error) {
          debugPrint('Liquid glass initialization failed: $error');
        }
      });
      return null;
    }, [glassEffects]);
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      title: '邻接',
      theme: ConnectTokens.theme(Brightness.light),
      darkTheme: ConnectTokens.theme(Brightness.dark),
      themeMode: switch (appearance) {
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
        Appearance.system => ThemeMode.system,
      },
      builder: (context, child) => FoldableProvider(
        bridgeMode: DisplayFeatureBridgeMode.full,
        child: WindowEnvironmentScope(
          child: GlassPreferences(
            effects: glassEffects,
            reduceTransparency:
                !glassReady.value || visualPreferences.reduceTransparency,
            child: liquid.GlassNavigationShell(
              child: MobileRemoteScope(
                client: client,
                child: RemoteViewsScope(views: views, child: child!),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
