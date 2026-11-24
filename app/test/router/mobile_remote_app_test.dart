import 'dart:async';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/platform/window_isolate_port.dart';
import 'package:scrcpy_connect/core/platform/window_launch_route.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/mobile_remote_app.dart';
import 'package:scrcpy_connect/router/mobile_remote_capabilities.dart';
import 'package:scrcpy_connect/router/mobile_remote_window.dart';

void main() {
  testWidgets('系统启动地址交付窗口身份，子引擎显示工作台交付的实际路由', (tester) async {
    const id = 'test-window';
    final providers = ProviderContainer();
    addTearDown(providers.dispose);
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        independentWindowLaunchRoute(id);
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.scrcpyconnect/window_environment/events'),
      (_) async => null,
    );
    final name = mobileRemoteWindowPort(id);
    addTearDown(() => IsolateNameServer.removePortNameMapping(name));

    await tester.runAsync(() async {
      final attached = Completer<void>();
      final owner = WindowIsolateOwner(
        MobileRemoteCapabilities(
          providers,
          attach: (_, _) {
            attached.complete();
            return (
              state: AppState(
                loading: false,
                settings: Preferences(glassEffects: GlassEffects.off),
              ),
              location: const RouteErrorRoute(reason: 'missing-session')
                  .location,
              extra: null,
              request: null,
            );
          },
          start: (_) => throw StateError('尚未进入有效会话'),
          open: (_) async {},
          entries: () => [],
          activate: (_) async {},
          workbench: () async {},
          close: (_) async {},
          focus: (_, _) async {},
          setVisible: (_) async {},
        ),
      );
      addTearDown(owner.dispose);
      expect(IsolateNameServer.registerPortWithName(owner.port, name), isTrue);
      await tester.pumpWidget(const MobileRemoteApp(windowId: id));
      await attached.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    await tester.pumpAndSettle();
    expect(find.text('这次打开的画面已不可用。请回到设备工作台重新打开。'), findsOneWidget);
    expect(find.text('这个位置无法打开，请从设备列表重新选择功能。'), findsNothing);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  });
}
