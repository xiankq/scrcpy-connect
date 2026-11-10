import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/models/app_state.dart';
import 'package:scrcpy_connect/widgets/system_notifications.dart';

import '../support/test_controller.dart';

class FakeSink implements SystemNotificationSink {
  final taps = StreamController<String>.broadcast(sync: true);
  final shown = <SystemNotice>[];
  final cancelled = <int>[];
  final cancellationAttempts = <int>[];
  int cancellationFailures = 0;
  final showStarted = Completer<void>();
  Future<void>? waitForShow;
  String? launchPayload;
  bool failInitialization = false;
  Future<void>? waitForInitialize;
  var statusCalls = 0;
  SystemNotificationStatus permissions = const SystemNotificationStatus(
    supported: true,
    permissionGranted: true,
    notificationChannelEnabled: true,
    callChannelEnabled: true,
  );
  @override
  Stream<String> get activations => taps.stream;
  @override
  Future<void> initialize() async {
    await waitForInitialize;
    if (launchPayload case final payload?) taps.add(payload);
    if (failInitialization) throw StateError('unavailable plugin');
  }

  @override
  Future<SystemNotificationStatus> status() async {
    statusCalls++;
    return permissions;
  }

  @override
  Future<SystemNotificationStatus> requestPermission() => status();
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> show(SystemNotice notice) async {
    shown.add(notice);
    if (!showStarted.isCompleted) showStarted.complete();
    await waitForShow;
  }

  @override
  Future<void> cancel(int id) async {
    cancellationAttempts.add(id);
    if (cancellationFailures-- > 0) throw StateError('cancel unavailable');
    cancelled.add(id);
  }
}

Json notification(String id, {String key = 'remote-key'}) => {
  'id': id,
  'revision': id,
  'key': key,
  'title': 'SECRET OTP 123456',
  'body': 'PRIVATE MESSAGE',
};
Json section(
  List<Json> items, {
  String kind = 'notifications',
  int epoch = 1,
}) => {
  'live': true,
  'observationEnabled': true,
  'observationEpoch': epoch,
  kind: items,
};
Json observation({
  int epoch = 1,
  List<Json> notifications = const [],
  List<Json> calls = const [],
}) => {
  'type': 'observation.changed',
  'deviceId': 'phone',
  'data': {
    'generation': epoch,
    'wanted': true,
    'phase': 'observing',
    'notifications': section(notifications, epoch: epoch),
    'calls': section(calls, kind: 'calls', epoch: epoch),
  },
};

Future<
  ({
    SystemNotifications coordinator,
    FakeSink sink,
    StreamController<Json> events,
    AppStore controller,
  })
>
notificationFixture({
  FakeSink? targetSink,
  List<String>? commands,
  List<Json> devices = const [
    {'id': 'phone', 'status': 'connected'},
  ],
}) async {
  final events = StreamController<Json>.broadcast(sync: true);
  final controller = createTestController(
    (command, [params = const {}]) async {
      commands?.add(command);
      return {};
    },
    events: events.stream,
    initialState: AppState(
      loading: false,
      devices: devices,
      settings: {'notificationAlerts': true, 'callAlerts': true},
    ),
  );
  final sink = targetSink ?? FakeSink();
  final coordinator = SystemNotifications(controller, sink);
  addTearDown(() async {
    coordinator.dispose();
    await coordinator.drain();
    controller.dispose();
    await events.close();
    await sink.taps.close();
  });
  await coordinator.initialize();
  return (
    coordinator: coordinator,
    sink: sink,
    events: events,
    controller: controller,
  );
}

void changedNotifications(
  StreamController<Json> events,
  List<Json> items, {
  String deviceId = 'phone',
}) => events.add({
  'type': 'notifications.changed',
  'deviceId': deviceId,
  'data': section(items),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('background source changes publish generic alerts and withdrawal cancels only the owned alert', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.title, '设备有新通知');
    expect(sink.shown.single.body, '请打开邻接查看');
    expect(sink.shown.single.payload, isNot(contains('SECRET')));
    expect(sink.shown.single.payload, isNot(contains('PRIVATE')));
    expect(sink.shown.single.id, isNot(2101));
    sink.cancellationFailures = 3;
    changedNotifications(events, []);
    await coordinator.drain();
    expect(sink.cancelled, isEmpty);
    changedNotifications(events, [notification('replacement')]);
    await coordinator.drain();
    expect(sink.shown.last.id, isNot(sink.shown.first.id));
    await coordinator.refreshStatus();
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.first.id]);
    expect(sink.cancellationAttempts, everyElement(sink.shown.first.id));
  });

  test('foreground notifications keep a quiet first snapshot and deduplicate live changes', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    events.add(observation(notifications: [notification('existing')]));
    await coordinator.drain();
    expect(sink.shown, isEmpty);
    final update = {
      'type': 'notifications.changed',
      'deviceId': 'phone',
      'data': section([
        notification('existing'),
        notification('new', key: 'new-key'),
      ]),
    };
    events.add(update);
    events.add(update);
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    expect(
      SystemNotificationTarget.decode(sink.shown.single.payload)?.objectId,
      'new',
    );
    changedNotifications(events, [notification('existing')]);
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
  });

  test('updates retain a local identity and stopping observation rejects queued old generations', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await coordinator.drain();
    changedNotifications(events, [notification('updated')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(2));
    expect(sink.shown[1].id, sink.shown[0].id);
    events.add({
      'type': 'observation.changed',
      'deviceId': 'phone',
      'data': {'generation': 2, 'wanted': false, 'phase': 'stopped'},
    });
    changedNotifications(events, [notification('late')]);
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown[0].id]);
    expect(sink.shown, hasLength(2));
  });

  test('ringing calls alert in background and an active call withdraws that reminder', () async {
    final commands = <String>[];
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture(
      commands: commands,
    );
    coordinator.setForeground(false);
    events.add(observation());
    final call = {
      'id': 'call',
      'state': 'ringing',
      'name': 'SECRET CALLER',
      'number': 'PRIVATE NUMBER',
    };
    events.add({
      'type': 'calls.incoming',
      'deviceId': 'phone',
      'data': section([call], kind: 'calls'),
    });
    events.add({
      'type': 'calls.incoming',
      'deviceId': 'phone',
      'data': section([call], kind: 'calls'),
    });
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    expect(sink.shown.single.kind, SystemNotificationKind.call);
    expect(sink.shown.single.title, '设备有来电');
    expect(sink.shown.single.payload, isNot(contains('SECRET')));
    events.add({
      'type': 'calls.changed',
      'deviceId': 'phone',
      'data': section([
        {'id': 'call', 'state': 'active'},
      ], kind: 'calls'),
    });
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
    expect(commands, isEmpty);
  });

  test('OS activations wait for foreground, validate exact current objects and never execute remote commands', () async {
    final commands = <String>[];
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture(
      commands: commands,
    );
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await coordinator.drain();
    final payload = sink.shown.single.payload;
    sink.taps.add(payload);
    sink.taps.add(payload);
    expect(coordinator.pendingActivation, isNull);
    coordinator.setForeground(true);
    expect(coordinator.pendingActivation?.available, isTrue);
    final activation = coordinator.takeActivation();
    expect(activation?.target.deviceId, 'phone');
    expect(activation?.target.objectId, 'first');
    expect(coordinator.takeActivation(), isNull);
    sink.taps.add(payload);
    expect(coordinator.pendingActivation, isNull);
    final stale = SystemNotificationTarget(
      kind: SystemNotificationKind.notification,
      deviceId: 'phone',
      objectId: 'removed',
      revision: 'removed',
      observationGeneration: 1,
    );
    sink.taps.add(stale.encode());
    expect(coordinator.takeActivation()?.available, isFalse);
    expect(commands, isEmpty);
  });

  test('a state gap withdraws alerts and authoritative recovery forms a quiet baseline', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await coordinator.drain();
    events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
    changedNotifications(events, [notification('gap-event')]);
    events.add({
      'type': 'state.resynced',
      'data': {
        'sequence': 99,
        'devices': [
          {'id': 'phone', 'status': 'connected'},
        ],
        'settings': {'notificationAlerts': true, 'callAlerts': true},
        'observations': [
          {
            'deviceId': 'phone',
            ...jsonObject(
              observation(notifications: [notification('recovered')])['data'],
            ),
          },
        ],
        'companions': <Json>[],
        'sessions': <Json>[],
        'shares': <Json>[],
      },
    });
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    changedNotifications(events, [notification('new-after-recovery')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(2));
  });

  test('changed revisions update the same OS item in both foreground and background', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('same')]);
    await coordinator.drain();
    changedNotifications(events, [
      {...notification('same'), 'revision': 'revision-2'},
    ]);
    await coordinator.drain();
    expect(sink.shown, hasLength(2));
    expect(sink.shown[0].id, sink.shown[1].id);
    coordinator.setForeground(true);
    changedNotifications(events, [
      {...notification('same'), 'revision': 'revision-3'},
    ]);
    await coordinator.drain();
    expect(sink.shown, hasLength(3));
    expect(sink.shown.last.id, sink.shown.first.id);
    expect(sink.cancelled, isEmpty);
    sink.taps.add(sink.shown.first.payload);
    expect(coordinator.takeActivation()?.available, isFalse);
    sink.taps.add(sink.shown.last.payload);
    expect(coordinator.takeActivation()?.available, isTrue);
  });

  test('truncated snapshots retain missing owners, but unverified snapshots withdraw without replay', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await coordinator.drain();
    events.add({
      'type': 'notifications.changed',
      'deviceId': 'phone',
      'data': {...section([]), 'truncated': true},
    });
    await coordinator.drain();
    expect(sink.cancelled, isEmpty);
    events.add({
      'type': 'notifications.changed',
      'deviceId': 'phone',
      'data': {...section([]), 'live': null},
    });
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
    changedNotifications(events, [notification('old-after-unverified')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    changedNotifications(events, [notification('fresh')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(2));
  });

  test('disposing while an OS publish is pending cancels that owner after publication finishes', () async {
    final completeShow = Completer<void>();
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture(
      targetSink: FakeSink()..waitForShow = completeShow.future,
    );
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('first')]);
    await sink.showStarted.future;
    changedNotifications(events, [notification('queued-update')]);
    coordinator.dispose();
    completeShow.complete();
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    expect(sink.cancelled, [sink.shown.single.id]);
  });

  test('large source snapshots bound OS owners and keep every allocated ID in its namespace', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [
      for (var i = 0; i < 160; i++) notification('notice-$i', key: 'key-$i'),
    ]);
    await coordinator.drain();
    expect(sink.shown.length, inInclusiveRange(1, 128));
    expect(
      sink.shown.map((notice) => notice.id).toSet(),
      hasLength(sink.shown.length),
    );
    expect(
      sink.shown.every(
        (notice) =>
            notice.id >= systemNotificationIdMin &&
            notice.id <= systemNotificationIdMax,
      ),
      isTrue,
    );
    events.add({'type': 'connections.stopped', 'data': <String, dynamic>{}});
    await coordinator.drain();
    expect(
      sink.cancelled.toSet(),
      sink.shown.map((notice) => notice.id).toSet(),
    );
  });

  test('status refresh waits for initialization and cold-launch activations are retained once', () async {
    final controller = createTestController(
      (_, [params = const {}]) async => {},
      initialState: AppState(loading: false),
    );
    final gate = Completer<void>();
    final target = SystemNotificationTarget(
      kind: SystemNotificationKind.call,
      deviceId: 'phone',
      objectId: 'previous-process-call',
      revision: '1',
      observationGeneration: 1,
    );
    final sink = FakeSink()
      ..waitForInitialize = gate.future
      ..launchPayload = target.encode();
    final coordinator = SystemNotifications(controller, sink);
    addTearDown(() async {
      coordinator.dispose();
      controller.dispose();
      await sink.taps.close();
    });
    final initialization = coordinator.initialize();
    final refresh = coordinator.refreshStatus();
    expect(sink.statusCalls, 0);
    gate.complete();
    await initialization;
    await refresh;
    expect(
      coordinator.pendingActivation?.target.objectId,
      'previous-process-call',
    );
    expect(coordinator.takeActivation()?.available, isFalse);
    sink.taps.add(target.encode());
    expect(coordinator.takeActivation(), isNull);
  });

  test('permissions, channel settings, user intent and known source eligibility remain independent', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture(
      targetSink: FakeSink()
        ..permissions = const SystemNotificationStatus(
          supported: true,
          permissionGranted: false,
        ),
    );
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('denied')]);
    await coordinator.drain();
    expect(sink.shown, isEmpty);
    sink.permissions = const SystemNotificationStatus(
      supported: true,
      permissionGranted: true,
    );
    await coordinator.refreshStatus();
    changedNotifications(events, [notification('allowed')]);
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    sink.permissions = const SystemNotificationStatus(
      supported: true,
      permissionGranted: true,
      notificationChannelEnabled: false,
    );
    await coordinator.refreshStatus();
    await coordinator.drain();
    expect(sink.cancelled, [sink.shown.single.id]);
    controller.settings = {'notificationAlerts': false, 'callAlerts': true};
    coordinator.configure();
    changedNotifications(events, [notification('disabled-intent')]);
    events.add({...observation(), 'deviceId': 'unknown'});
    events.add({
      'type': 'calls.incoming',
      'deviceId': 'unknown',
      'data': section([
        {'id': 'untrusted', 'state': 'ringing'},
      ], kind: 'calls'),
    });
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
  });

  test('native Stop before observation blocks late owners until a fresh connection lifecycle', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    final controller = createTestController(
      (_, [params = const {}]) async => {
        'devices': [
          {'id': 'phone', 'status': 'connected'},
        ],
      },
      events: events.stream,
      initialState: AppState(
        loading: false,
        devices: [
          {'id': 'phone', 'status': 'connected'},
        ],
        settings: {'notificationAlerts': true, 'callAlerts': true},
      ),
    );
    final sink = FakeSink();
    final coordinator = SystemNotifications(controller, sink);
    addTearDown(() async {
      coordinator.dispose();
      controller.dispose();
      await events.close();
      await sink.taps.close();
    });
    await coordinator.initialize();
    coordinator.setForeground(false);
    events.add({'type': 'connections.stopped', 'data': <String, dynamic>{}});
    events.add(
      observation(
        calls: [
          {'id': 'late-call', 'state': 'ringing'},
        ],
      ),
    );
    await coordinator.drain();
    expect(sink.shown, isEmpty);
    events.add({
      'type': 'device.changed',
      'deviceId': 'phone',
      'data': {'id': 'phone', 'status': 'paired'},
    });
    events.add({
      'type': 'device.changed',
      'deviceId': 'phone',
      'data': {'id': 'phone', 'status': 'connected'},
    });
    events.add(
      observation(
        epoch: 2,
        calls: [
          {'id': 'fresh-call', 'state': 'ringing'},
        ],
      ),
    );
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
  });

  test('truncated snapshot metadata eviction cannot strand an older OS notification', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [notification('A', key: 'A')]);
    await coordinator.drain();
    final olderId = sink.shown.single.id;
    events.add({
      'type': 'notifications.changed',
      'deviceId': 'phone',
      'data': {
        ...section([
          for (var i = 0; i < 1000; i++)
            notification('different-$i', key: 'different-$i'),
        ]),
        'truncated': true,
      },
    });
    await coordinator.drain();
    expect(sink.cancelled, contains(olderId));
    changedNotifications(events, []);
    await coordinator.drain();
    expect(
      sink.cancelled.toSet(),
      sink.shown.map((notice) => notice.id).toSet(),
    );
  });
  test('group summaries stay available for navigation without duplicating child OS reminders', () async {
    final (
      coordinator: coordinator,
      sink: sink,
      events: events,
      controller: controller,
    ) = await notificationFixture();
    coordinator.setForeground(false);
    events.add(observation());
    changedNotifications(events, [
      {...notification('summary', key: 'group'), 'groupSummary': true},
      notification('message', key: 'message'),
    ]);
    await coordinator.drain();
    expect(sink.shown, hasLength(1));
    expect(
      SystemNotificationTarget.decode(sink.shown.single.payload)!.objectId,
      'message',
    );
    changedNotifications(events, [
      {...notification('summary-changed', key: 'group'), 'groupSummary': true},
    ]);
    await coordinator.drain();
    expect(
      sink.shown,
      hasLength(1),
      reason: 'A changed summary must not become another independent reminder.',
    );
    expect(sink.cancelled, [sink.shown.single.id]);
  });
  test(
    'only the visible source notification page suppresses new system alerts',
    () async {
      final events = StreamController<Json>.broadcast(sync: true);
      final controller = createTestController(
        (_, [params = const {}]) async => {},
        events: events.stream,
        initialState: AppState(
          loading: false,
          devices: [
            {'id': 'phone', 'status': 'connected'},
            {'id': 'other', 'status': 'connected'},
          ],
          settings: {'notificationAlerts': true, 'callAlerts': true},
        ),
      );
      final sink = FakeSink();
      final coordinator = SystemNotifications(controller, sink);
      addTearDown(() async {
        coordinator.dispose();
        controller.dispose();
        await events.close();
        await sink.taps.close();
      });
      await coordinator.initialize();
      var current = true;
      final release = coordinator.claimNotificationPage('phone', () => current);
      events.add(observation());
      events.add({...observation(), 'deviceId': 'other'});
      changedNotifications(events, [notification('visible')]);
      changedNotifications(events, [
        notification('other-new'),
      ], deviceId: 'other');
      await coordinator.drain();
      expect(sink.shown, hasLength(1));
      current = false;
      changedNotifications(events, [
        notification('visible'),
        notification('covered'),
      ]);
      await coordinator.drain();
      expect(sink.shown, hasLength(2));
      current = true;
      coordinator.setForeground(false);
      changedNotifications(events, [
        notification('visible'),
        notification('covered'),
        notification('background'),
      ]);
      await coordinator.drain();
      expect(sink.shown, hasLength(3));
      coordinator.setForeground(true);
      release();
      changedNotifications(events, [notification('released')]);
      await coordinator.drain();
      expect(sink.shown, hasLength(4));
    },
  );
}
