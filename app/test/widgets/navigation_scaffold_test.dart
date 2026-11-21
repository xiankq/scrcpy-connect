import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  testWidgets(
    'navigation and device panes retain selection at width thresholds',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(599, 800);
      const connected = 'pixel-8';
      const offline = 'pixel-9';
      const key = ValueKey('workspace-test-capture');
      const sidebar = ValueKey('app-sidebar');
      const bottom = ValueKey('app-bottom-navigation');
      final router = createAppRouter();
      addTearDown(router.dispose);
      final subscription = StateSubscription(_WorkspaceSession());
      addTearDown(subscription.dispose);

      final output = Platform.environment['INTERCONNECT_VISUAL_OUTPUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final asset = File(
            '../designs/assets/fonts/misans/MiSans-Regular.woff2',
          );
          final bytes = await asset.readAsBytes();
          await (FontLoader(
            'WorkspaceFixture',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
                rootBundle.load(
                  'packages/lucide_icons_flutter/assets/lucide.ttf',
                ),
              ))
              .load();
        });
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stateSubscriptionProvider.overrideWithValue(subscription),
            deviceListProvider.overrideWith(
              () => _Devices([
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
              ]),
            ),
            recoveryStateProvider.overrideWith(_Recovery.new),
            preferencesProvider.overrideWith(_Preferences.new),
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
          child: RepaintBoundary(
            key: key,
            child: MaterialApp.router(
              theme: ConnectTokens.theme(
                Brightness.light,
                fontFamily: output == null ? null : 'WorkspaceFixture',
              ),
              debugShowCheckedModeBanner: false,
              routerConfig: router,
            ),
          ),
        ),
      );
      Future<void> resize(double width, [double height = 800]) async {
        tester.view.physicalSize = Size(width, height);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        if (output == null) return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('$output/$name.png').writeAsBytes(
            bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          picture.dispose();
        });
      }

      await resize(599);
      expect(find.byKey(bottom), findsOneWidget);
      expect(find.byType(DeviceWorkspacePage), findsNothing);
      await capture('W12-599-fixture');

      await resize(600);
      expect(find.byKey(bottom), findsNothing);
      expect(
        tester.getSize(find.byKey(sidebar)).width,
        DesignTokens.componentSidebarCompactWidth,
      );
      await resize(839);
      expect(tester.getSize(find.byKey(sidebar)).width, 72);
      await resize(840);
      expect(tester.getSize(find.byKey(sidebar)).width, 208);
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
      await capture('W16-1180-fixture');

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
      expect(tester.getSize(find.byKey(sidebar)).width, 208);
    },
  );

  testWidgets(
    'keeps the single bottom glass bar mounted when transparency changes',
    (tester) async {
      final oldSize = tester.view.physicalSize;
      final oldRatio = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view
          ..physicalSize = oldSize
          ..devicePixelRatio = oldRatio;
      });
      tester.view
        ..physicalSize = const Size(402, 844)
        ..devicePixelRatio = 1;

      final reduceTransparency = ValueNotifier(false);
      addTearDown(reduceTransparency.dispose);
      final router = createAppRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceListProvider.overrideWith(_Devices.new),
            recoveryStateProvider.overrideWith(_Recovery.new),
            preferencesProvider.overrideWith(_Preferences.new),
          ],
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
            builder: (context, child) => ValueListenableBuilder<bool>(
              valueListenable: reduceTransparency,
              builder: (context, reduced, _) =>
                  GlassPreferences(reduceTransparency: reduced, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      const key = ValueKey('app-bottom-navigation');
      final first = tester.element(find.byKey(key));
      expect(find.byKey(key), findsOneWidget);
      final bounds = tester.getRect(find.byKey(key));
      expect(bounds.width, closeTo(284, 1));
      expect(bounds.center.dx, closeTo(201, 1));
      final isolation = tester.widget<liquid.GlassIsolationScope>(
        find.ancestor(
          of: find.byKey(key),
          matching: find.byType(liquid.GlassIsolationScope),
        ),
      );
      expect(isolation.isolated, isTrue);
      expect(
        isolation.defaultQuality,
        GlassMaterial.quality(tester.element(find.byKey(key))),
      );

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
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    final oldInsets = tester.view.viewInsets;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio
        ..viewInsets = oldInsets;
    });
    tester.view
      ..physicalSize = const Size(402, 844)
      ..devicePixelRatio = 1;

    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(_Devices.new),
          recoveryStateProvider.overrideWith(_Recovery.new),
          preferencesProvider.overrideWith(_Preferences.new),
        ],
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

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
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio;
    });
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;

    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(_Devices.new),
          recoveryStateProvider.overrideWith(_Recovery.new),
          preferencesProvider.overrideWith(_Preferences.new),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 874),
            viewPadding: EdgeInsets.only(right: 120),
            padding: EdgeInsets.only(right: 120),
          ),
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
            builder: (context, child) =>
                liquid.GlassNavigationShell(child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final bars = tester
        .widgetList<liquid.GlassVerticalBar>(
          find.byType(liquid.GlassVerticalBar),
        )
        .toList();
    expect(
      bars.any((bar) => bar.data?.edge == liquid.GlassVerticalBarEdge.trailing),
      isTrue,
    );
    expect(bars.any((bar) => bar.data?.width == 84), isTrue);
    final navigation = find.byKey(const ValueKey('app-bottom-navigation'));
    expect(navigation, findsOneWidget);
    expect(tester.getBottomRight(navigation).dx, closeTo(402, 1));
    expect(find.byType(GlassVerticalToolbarGroup), findsNothing);
    expect(find.text('添加第一台设备'), findsOneWidget);
    expect(find.text('添加设备'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo vertical navigation wins over the tablet sidebar', (
    tester,
  ) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio;
    });
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;

    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(_Devices.new),
          recoveryStateProvider.overrideWith(_Recovery.new),
          preferencesProvider.overrideWith(_Preferences.new),
        ],
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
          builder: (context, child) => liquid.GlassVerticalBar(
            data: const liquid.GlassVerticalBarData(
              edge: liquid.GlassVerticalBarEdge.trailing,
              width: 84,
              top: 24,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('app-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('app-bottom-navigation')), findsOneWidget);
    expect(find.byType(liquid.GlassTabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet sidebar occupies the full available work area', (
    tester,
  ) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio;
    });
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;

    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(_Devices.new),
          recoveryStateProvider.overrideWith(_Recovery.new),
          preferencesProvider.overrideWith(_Preferences.new),
        ],
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final sidebar = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('app-sidebar')),
    );
    expect(sidebar.size.height, closeTo(tester.view.physicalSize.height, 1));
    expect(sidebar.localToGlobal(Offset.zero).dy, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

class _Devices extends DeviceListNotifier {
  _Devices([this.initial = const []]);
  final List<DeviceSnapshot> initial;
  @override
  DeviceListState build() => DeviceListState(loading: false, devices: initial);
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() => PreferencesState();
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
