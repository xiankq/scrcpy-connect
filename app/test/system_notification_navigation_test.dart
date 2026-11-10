import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/models/app_state.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

class _Sink implements SystemNotificationSink {
  final shown = <SystemNotice>[];
  @override
  Stream<String> get activations => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<SystemNotificationStatus> status() async =>
      const SystemNotificationStatus(supported: true, permissionGranted: true);
  @override
  Future<SystemNotificationStatus> requestPermission() => status();
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> show(SystemNotice notice) async {
    shown.add(notice);
  }

  @override
  Future<void> cancel(int id) async {}
}

void main() {
  testWidgets('分享排入下一帧后进入后台时等待恢复前台再呈现', (tester) async {
    final dependencies = AppDependencies(
      initialize: false,
      request: (_, [params = const {}]) async => {},
      events: const Stream.empty(),
      initialState: AppState(
        loading: false,
        pendingShares: [
          {'shareId': 'pending-share', 'text': '保留分享'},
        ],
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var scheduled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDependenciesProvider.overrideWithValue(dependencies),
          systemNotificationSinkProvider.overrideWithValue(_Sink()),
        ],
        child: Builder(
          builder: (context) {
            if (!scheduled) {
              scheduled = true;
              // 在根呈现回调执行前失去前台资格，不额外等待一次重建。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.inactive,
                );
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.hidden,
                );
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.paused,
                );
              });
            }
            return const ConnectApp();
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(IncomingSharePage), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(IncomingSharePage), findsOneWidget);
    expect(find.text('保留分享'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'paused before a new frame still delivers the next background event',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final sink = _Sink();
      final dependencies = AppDependencies(
        initialize: false,
        request: (_, [params = const {}]) async => {},
        events: events.stream,
        initialState: AppState(
          loading: false,
          devices: [
            {'id': 'phone', 'name': '手机', 'status': 'connected'},
          ],
          settings: {'notificationAlerts': true, 'callAlerts': true},
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDependenciesProvider.overrideWithValue(dependencies),
            systemNotificationSinkProvider.overrideWithValue(sink),
          ],
          child: const ConnectApp(),
        ),
      );
      await tester.pumpAndSettle();
      final coordinator = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(systemNotificationsProvider);
      await coordinator.initialize();
      Json notifications(List<Json> items) => {
        'live': true,
        'observationEnabled': true,
        'observationEpoch': 1,
        'notifications': items,
      };
      events.add({
        'type': 'observation.changed',
        'deviceId': 'phone',
        'data': {
          'generation': 1,
          'wanted': true,
          'phase': 'observing',
          'notifications': notifications([]),
          'calls': {
            'live': true,
            'observationEnabled': true,
            'observationEpoch': 1,
            'calls': <Json>[],
          },
        },
      });
      await tester.pumpAndSettle();
      // 系统暂停视图前不一定再允许界面绘制一帧。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      events.add({
        'type': 'notifications.changed',
        'deviceId': 'phone',
        'data': notifications([
          {'id': 'new', 'revision': 'r1', 'key': 'key'},
        ]),
      });
      await coordinator.drain();
      expect(
        sink.shown,
        hasLength(1),
        reason: 'Publication eligibility must update in the lifecycle callback, without a rendered frame.',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await events.close();
    },
  );
}
