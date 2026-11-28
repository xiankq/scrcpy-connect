import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_app.dart';
import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/pages/devices/workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart'
    show AppIcons;
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/navigation_scaffold.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

import '../support/fixed_state.dart';

void main() {
  testWidgets('桌面侧栏展开时保留图标位置和正文滚动', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(700, 660);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        home: DesktopWindowInsets(
          left: 72,
          right: 0,
          top: 28,
          child: AppNavigationShell(
            uri: Uri(path: '/devices'),
            child: ListView(
              controller: scroll,
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('app-sidebar'));
    final icon = find.byIcon(AppIcons.navigationDevices);
    final position = tester.getCenter(icon);
    expect(tester.getSize(sidebar).width, 72);
    scroll.jumpTo(190);

    tester.view.physicalSize = const Size(900, 660);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(sidebar).width, inExclusiveRange(72, 220));
    expect(tester.getCenter(icon), position);
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 220);
    expect(scroll.offset, 190);

    tester.view.physicalSize = const Size(550, 660);
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 0);
    expect(scroll.offset, 190);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'navigation and device panes retain selection at width thresholds',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(599, 800);
      const connected = 'pixel-8';
      const offline = 'pixel-9';
      const sidebar = ValueKey('app-sidebar');
      const bottom = ValueKey('app-bottom-navigation');
      final router = createAppRouter();
      addTearDown(router.dispose);
      final subscription = StateSubscription(_WorkspaceSession());
      addTearDown(subscription.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateSubscriptionProvider.overrideWithValue(subscription),
            deviceListProvider.overrideWith(
              () => FixedDeviceList(
                devices: [
                  DeviceSnapshot(
                    id: connected,
                    name: 'Pixel 8',
                    status: .connected,
                    transport: .tls,
                    androidVersion: '15',
                    battery: 78,
                    batteryUpdatedAt:
                        DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  ),
                  const DeviceSnapshot(
                    id: offline,
                    name: 'Pixel 9',
                    status: .offline,
                  ),
                ],
              ),
            ),
            recoveryStateProvider.overrideWith(FixedRecovery.new),
            preferencesProvider.overrideWith(FixedPreferences.new),
            deviceConnectionsProvider.overrideWithValue(_ConnectionControl()),
            audioErrorProvider.overrideWith(_AudioError.new),
            routeResourceResolverProvider.overrideWithValue(
              RouteResourceResolver(
                readDevice: (id) async =>
                    DeviceSnapshot(id: id, name: 'Pixel 9'),
                readTransfer: (_) async => throw UnimplementedError(),
                readSessions: (_) async => [],
                readDirectory: (_) async => throw UnimplementedError(),
                readShare: (_) async => null,
              ),
            ),
            deviceCallsSnapshotProvider(connected).overrideWith(
              (_) async => const DeviceCallsSnapshot(deviceId: connected),
            ),
            runningDeviceAppsProvider(connected).overrideWith(
              (_) async => const RunningDeviceApps(
                deviceId: connected,
                apps: [],
                userId: 0,
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      Future<void> resize(double width, [double height = 800]) async {
        tester.view.physicalSize = Size(width, height);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await resize(599);
      expect(find.byKey(bottom), findsOneWidget);
      expect(find.byType(DeviceWorkspacePage), findsNothing);

      await resize(600);
      expect(find.byKey(bottom), findsNothing);
      expect(tester.getSize(find.byKey(sidebar)).width, 72);
      await resize(839);
      expect(tester.getSize(find.byKey(sidebar)).width, 72);
      await resize(840);
      expect(tester.getSize(find.byKey(sidebar)).width, 220);
      await resize(1079);
      expect(find.byType(DeviceWorkspacePage), findsNothing);

      await resize(1080);
      expect(find.byType(DeviceWorkspacePage), findsOneWidget);
      expect(find.byType(DeviceCard), findsNWidgets(2));
      expect(
        tester.getTopRight(find.byType(DeviceCard).first).dx,
        lessThan(tester.getTopLeft(find.byType(DeviceWorkspacePage)).dx),
      );
      await resize(1180, 780);

      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DeviceWorkspacePage>(find.byType(DeviceWorkspacePage))
            .device
            .id,
        offline,
      );
      await resize(839);
      expect(find.byType(DeviceCard), findsNothing);
      expect(
        tester
            .widget<DeviceWorkspacePage>(find.byType(DeviceWorkspacePage))
            .device
            .id,
        offline,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DeviceCard), findsNWidgets(2));
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceWorkspacePage), findsOneWidget);
      await resize(1180, 780);
      expect(find.byType(DeviceCard), findsNWidgets(2));
      expect(
        tester
            .widget<DeviceWorkspacePage>(find.byType(DeviceWorkspacePage))
            .device
            .id,
        offline,
      );
      await resize(839);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DeviceCard), findsNWidgets(2));
      await resize(1120, 479);
      expect(tester.getSize(find.byKey(sidebar)).width, 72);
      await resize(1120, 480);
      expect(tester.getSize(find.byKey(sidebar)).width, 220);
    },
  );

  testWidgets(
    'keeps the single bottom glass bar mounted when transparency changes',
    (tester) async {
      final reduceTransparency = ValueNotifier(false);
      addTearDown(reduceTransparency.dispose);
      await _pumpShell(
        tester,
        const Size(402, 844),
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: reduceTransparency,
          builder: (context, reduced, _) =>
              GlassPreferences(reduceTransparency: reduced, child: child!),
        ),
      );

      const key = ValueKey('app-bottom-navigation');
      final first = tester.element(find.byKey(key));
      expect(find.byKey(key), findsOneWidget);

      reduceTransparency.value = true;
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byKey(key), findsOneWidget);
      expect(tester.element(find.byKey(key)), same(first));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps the bottom glass bar state while the keyboard is shown', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await _pumpShell(tester, const Size(402, 844));

    const key = ValueKey('app-bottom-navigation');
    final first = tester.element(find.byKey(key));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    final mounted = find.byKey(key, skipOffstage: false);
    expect(mounted, findsOneWidget);
    expect(tester.element(mounted), same(first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone Duo vertical bar owns the compact navigation strip', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pumpShell(
      tester,
      const Size(402, 874),
      media: const MediaQueryData(
        size: Size(402, 874),
        viewPadding: EdgeInsets.only(right: 120),
        padding: EdgeInsets.only(right: 120),
      ),
      builder: (context, child) => liquid.GlassNavigationShell(child: child!),
    );

    final bars = tester
        .widgetList<liquid.GlassVerticalBar>(
          find.byType(liquid.GlassVerticalBar),
        )
        .toList();
    expect(
      bars.any((bar) => bar.data?.edge == liquid.GlassVerticalBarEdge.trailing),
      isTrue,
    );
    final navigation = find.byKey(const ValueKey('app-bottom-navigation'));
    expect(navigation, findsOneWidget);
    expect(tester.getBottomRight(navigation).dx, closeTo(402, 1));
    expect(find.byType(GlassSideToolbar), findsNothing);
    expect(find.text('添加第一台设备'), findsOneWidget);
    expect(find.text('添加设备'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo vertical navigation wins over the tablet sidebar', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      const Size(1200, 900),
      builder: (context, child) => liquid.GlassVerticalBar(
        data: const liquid.GlassVerticalBarData(
          edge: liquid.GlassVerticalBarEdge.trailing,
          width: 84,
          top: 24,
        ),
        child: child!,
      ),
    );

    expect(find.byKey(const ValueKey('app-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('app-bottom-navigation')), findsOneWidget);
    expect(find.byType(liquid.GlassTabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet sidebar occupies the full available work area', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(1200, 900));

    final sidebar = find.byKey(const ValueKey('app-sidebar'));
    expect(tester.getRect(sidebar).top, closeTo(0, 1));
    expect(tester.getRect(sidebar).height, closeTo(900, 1));
    expect(tester.takeException(), isNull);
  });
}

/// 用空设备列表挂载完整路由壳。
Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  TransitionBuilder? builder,
  MediaQueryData? media,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = createAppRouter();
  addTearDown(router.dispose);
  final app = MaterialApp.router(
    theme: ConnectTokens.theme(Brightness.light),
    routerConfig: router,
    builder: builder,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceListProvider.overrideWith(FixedDeviceList.new),
        recoveryStateProvider.overrideWith(FixedRecovery.new),
        preferencesProvider.overrideWith(FixedPreferences.new),
      ],
      child: media == null ? app : MediaQuery(data: media, child: app),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

class _ConnectionControl implements DeviceConnectionControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioError extends AudioErrorNotifier {
  @override
  String? build() => null;
}

class _WorkspaceSession implements AppSession {
  @override
  AppState get initialState => AppState();
  @override
  Stream<RuntimeEvent> get events => const Stream.empty();
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
