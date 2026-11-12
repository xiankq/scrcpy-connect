import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/widgets/models/system_notification_snapshot.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

void main() {
  final snapshot = SystemNotificationSnapshot(
    devices: [const DeviceSnapshot(id: 'device', status: .connected)],
    settings: Preferences(notificationAlerts: true),
    loading: false,
    reconciliationPending: false,
  );
  test('初始化期间换源不继续申请权限，迟到状态不再提交', () async {
    var current = true;
    final sink = _Sink()..initializing = Completer<void>();
    final notifications = SystemNotifications(
      events: const Stream.empty(),
      readSnapshot: () => snapshot,
      current: () => current,
      sink: sink,
    );
    final permission = notifications.requestPermission();
    current = false;
    sink.initializing!.complete();
    await permission;
    expect(sink.permissions, 0);
    expect(sink.statusReads, 0);
    expect(notifications.status.supported, isFalse);
    notifications.dispose();
    await sink.activationsController.close();

    current = true;
    final late = _Sink()..statusResult = Completer<SystemNotificationStatus>();
    final original = SystemNotifications(
      events: const Stream.empty(),
      readSnapshot: () => snapshot,
      current: () => current,
      sink: late,
    );
    final reading = original.initialize();
    await Future<void>.delayed(Duration.zero);
    current = false;
    late.statusResult!.complete(
      const SystemNotificationStatus(supported: true),
    );
    await reading;
    expect(original.status.supported, isFalse);
    original.dispose();
    await late.activationsController.close();
  });

  test('迟到展示仍由原系统能力撤回，不撤销替换来源的提醒', () async {
    var current = true;
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    final sink = _Sink()..showing = Completer<void>();
    final original = SystemNotifications(
      events: events.stream,
      readSnapshot: () => snapshot,
      current: () => current,
      sink: sink,
    );
    await original.initialize();
    events.add(observing());
    events.add(notificationsChanged('first'));
    await Future<void>.delayed(Duration.zero);
    expect(sink.shown, hasLength(1));
    final payload = sink.shown.single.payload;
    expect(payload, isNot(contains('sensitive message')));
    current = false;
    original.dispose();

    final newEvents = StreamController<Map<String, dynamic>>.broadcast(
      sync: true,
    );
    final newSink = _Sink();
    final replacement = SystemNotifications(
      events: newEvents.stream,
      readSnapshot: () => snapshot,
      current: () => true,
      sink: newSink,
    );
    await replacement.initialize();
    newEvents.add(observing());
    newEvents.add(notificationsChanged('second'));
    await replacement.drain();
    expect(newSink.shown, hasLength(1));
    sink.showing!.complete();
    await original.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
    expect(newSink.cancelled, isEmpty);
    events.add(notificationsChanged('late'));
    sink.activationsController.add(payload);
    expect(original.pendingActivation, isNull);
    expect(newSink.shown, hasLength(1));
    replacement.dispose();
    await replacement.drain();
    await events.close();
    await newEvents.close();
    await sink.activationsController.close();
    await newSink.activationsController.close();
  });
}

Map<String, dynamic> observing() => {
  'type': 'observation.changed',
  'deviceId': 'device',
  'data': {
    'wanted': true,
    'phase': 'observing',
    'generation': 1,
    'notifications': notificationData(null),
  },
};
Map<String, dynamic> notificationsChanged(String id) => {
  'type': 'notifications.changed',
  'deviceId': 'device',
  'data': notificationData(id),
};
Map<String, dynamic> notificationData(String? id) => {
  'live': true,
  'observationEnabled': true,
  'observationEpoch': 1,
  'notifications': [
    if (id != null)
      {
        'id': id,
        'key': id,
        'revision': 'revision',
        'body': 'sensitive message',
      },
  ],
};

class _Sink implements SystemNotificationSink {
  final activationsController = StreamController<String>.broadcast(sync: true);
  final shown = <SystemNotice>[];
  final cancelled = <int>[];
  Completer<void>? initializing;
  Completer<void>? showing;
  Completer<SystemNotificationStatus>? statusResult;
  int permissions = 0, statusReads = 0;
  @override
  Stream<String> get activations => activationsController.stream;
  @override
  Future<void> initialize() async {
    await initializing?.future;
  }

  @override
  Future<SystemNotificationStatus> status() async {
    statusReads++;
    return statusResult?.future ??
        const SystemNotificationStatus(
          supported: true,
          permissionGranted: true,
        );
  }

  @override
  Future<SystemNotificationStatus> requestPermission() async {
    permissions++;
    return status();
  }

  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> show(SystemNotice notice) async {
    shown.add(notice);
    await showing?.future;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}
