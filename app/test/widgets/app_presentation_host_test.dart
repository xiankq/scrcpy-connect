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
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
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
import 'package:scrcpy_connect/core/notifications/system_notification_sink.dart';
import 'package:scrcpy_connect/core/notifications/system_notification_sink_provider.dart';

void main() {
  testWidgets('类型化来电呈现电话入口，后台前迟到的呈现不打开，新回执可重试', (tester) async {
    final events = StreamController<RuntimeEvent>.broadcast(sync: true);
    addTearDown(events.close);
    final router = await _pumpHost(
      tester,
      events: events,
      target: 'calls',
      device: const DeviceSnapshot(
        id: 'device',
        name: 'Phone',
        status: .connected,
      ),
      settings: Preferences(),
      sink: const NoopSystemNotificationSink(),
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
  testWidgets('系统提醒点击经核心变更流通知宿主，后台等待，前台只打开当前目标一次', (tester) async {
    final events = StreamController<RuntimeEvent>.broadcast(sync: true);
    final sink = _NotificationSink();
    addTearDown(() async {
      await events.close();
      await sink.clicks.close();
    });
    final router = await _pumpHost(
      tester,
      events: events,
      target: 'notifications',
      device: const DeviceSnapshot(id: 'device', status: .connected),
      settings: Preferences(notificationAlerts: true),
      sink: sink,
    );
    await tester.pumpAndSettle();
    const baseline = DeviceNotificationsSnapshot(
      deviceId: 'device',
      live: true,
      observationEnabled: true,
      observationEpoch: 1,
    );
    events.add(
      DeviceObservationChanged(
        ObservedDeviceSnapshot(
          observation: const DeviceObservationSnapshot(
            deviceId: 'device',
            wanted: true,
            phase: .observing,
            generation: 1,
          ),
          notifications: baseline,
          calls: const DeviceCallsSnapshot(deviceId: 'device'),
        ),
      ).toApplicationEvent(),
    );
    events.add(
      DeviceNotificationsChanged(
        baseline.copyWith(
          notifications: [
            const DeviceNotification(
              id: 'notice',
              key: 'notice',
              revision: 'one',
              body: 'private body',
            ),
          ],
        ),
      ).toApplicationEvent(),
    );
    await tester.pumpAndSettle();
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.body, isNot(contains('private body')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    sink.clicks.add(sink.shown.single.payload);
    await tester.pump();
    expect(find.text('通知目标：device'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('通知目标：device'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    sink.clicks.add(sink.shown.single.payload);
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// 挂载首页和 `/devices/:deviceId/$target` 两条路由，目标页显示目标设备。
Future<GoRouter> _pumpHost(
  WidgetTester tester, {
  required StreamController<RuntimeEvent> events,
  required String target,
  required DeviceSnapshot device,
  required Preferences settings,
  required SystemNotificationSink sink,
}) async {
  final label = target == 'calls' ? '通话目标' : '通知目标';
  final navigator = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: navigator,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('首页')),
      ),
      GoRoute(
        path: '/devices/:deviceId/$target',
        builder: (_, state) =>
            Scaffold(body: Text('$label：${state.pathParameters['deviceId']}')),
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
            devices: [device],
            loading: false,
            settings: settings,
          ),
        ),
      ),
      deviceReaderProvider.overrideWithValue(_Devices()),
      settingsManagementProvider.overrideWithValue(_Settings()),
      incomingSharesProvider.overrideWithValue(_Shares()),
      remoteClipboardProvider.overrideWithValue(_Clipboard()),
      systemNotificationSinkProvider.overrideWithValue(sink),
    ],
  );
  addTearDown(() {
    container.dispose();
    router.dispose();
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
  return router;
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

final class _NotificationSink extends NoopSystemNotificationSink {
  final clicks = StreamController<String>.broadcast(sync: true);
  final shown = <SystemNotice>[];
  @override
  Stream<String> get activations => clicks.stream;
  @override
  Future<SystemNotificationStatus> status() async =>
      const SystemNotificationStatus(supported: true, permissionGranted: true);
  @override
  Future<void> show(SystemNotice notice) async => shown.add(notice);
}
