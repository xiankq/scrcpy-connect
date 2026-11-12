import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_event.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/app_presentation_host.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

void main() {
  testWidgets('类型化来电呈现电话入口，后台前迟到的呈现不打开，新回执可重试', (tester) async {
    final events = StreamController<RuntimeEvent>.broadcast(sync: true);
    final navigator = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: navigator,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('首页')),
        ),
        GoRoute(
          path: '/devices/:deviceId/calls',
          builder: (_, state) =>
              Scaffold(body: Text('通话目标：${state.pathParameters['deviceId']}')),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(
          AppSession(
            events: events.stream,
            initialize: false,
            initialState: AppState(
              devices: [
                const DeviceSnapshot(
                  id: 'device',
                  name: 'Phone',
                  status: .connected,
                ),
              ],
              loading: false,
              settings: Preferences(),
            ),
          ),
        ),
        deviceReaderProvider.overrideWithValue(_Devices()),
        settingsManagementProvider.overrideWithValue(_Settings()),
        incomingSharesProvider.overrideWithValue(_Shares()),
        remoteClipboardProvider.overrideWithValue(_Clipboard()),
        systemNotificationSinkProvider.overrideWithValue(
          const NoopSystemNotificationSink(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      router.dispose();
      await events.close();
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
          builder: (_, child) => AppPresentationHost(
            navigator: navigator,
            router: router,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const calls = DeviceCallsSnapshot(
      deviceId: 'device',
      status: .available,
      live: true,
      observationEnabled: true,
      observationEpoch: 1,
      calls: [
        DeviceCall(id: 'call', generation: 1, state: .ringing, name: '来电者'),
      ],
    );
    events.add(
      DeviceCallsChanged(
        calls.copyWith(live: false),
        incoming: true,
      ).toApplicationEvent(),
    );
    await tester.pump();
    expect(find.text('查看电话'), findsNothing);
    events.add(
      const DeviceCallsChanged(calls, incoming: true).toApplicationEvent(),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('查看电话'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    events.add(
      const DeviceCallsChanged(calls, incoming: true).toApplicationEvent(),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('来电者'), findsOneWidget);
    await tester.tap(find.text('查看电话'));
    await tester.pumpAndSettle();
    expect(find.text('通话目标：device'), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _Devices implements DeviceReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Shares implements IncomingShares {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Clipboard implements RemoteClipboard {
  @override
  void Function() bindClipboardAdmission(
    bool Function(String, String, int) check,
  ) => () {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
