import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/app_state.dart';
import 'package:scrcpy_connect/services/system_notifications.dart';

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
      ).read(systemNotificationCoordinatorProvider);
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
      // The OS need not grant another UI frame before suspending the view.
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
