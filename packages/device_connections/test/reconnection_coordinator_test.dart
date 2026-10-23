import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_connections/device_connections.dart';

Future<void> settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.value();
  }
}

class _Timer implements Timer {
  _Timer(this.delay, this.run);
  final Duration delay;
  final void Function() run;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() {
    isActive = false;
  }

  void fire() {
    if (isActive) {
      isActive = false;
      tick++;
      run();
    }
  }
}

class _Host {
  final calls = <(String, ReconnectJson)>[];
  final timers = <_Timer>[];
  int sequence = 1;
  List<ReconnectJson> devices = [device()];
  ReconnectJson settings = {'backgroundKeepAlive': true};
  Future<ReconnectJson> Function(ReconnectJson)? connect;

  static ReconnectJson device({
    String id = 'phone',
    bool retry = true,
    String status = 'offline',
  }) => {
    'id': id,
    'guid': 'trusted-guid',
    'autoReconnect': retry,
    'status': status,
  };
  ReconnectJson snapshot() => jsonDecode(
    jsonEncode({
      'sequence': sequence,
      'devices': devices,
      'settings': settings,
    }),
  ) as ReconnectJson;
  Future<ReconnectJson> request(String command, ReconnectJson params) async {
    calls.add((command, Map.of(params)));
    if (command == 'state.snapshot') return snapshot();
    if (command == 'devices.connect') {
      if (connect != null) return connect!(params);
      throw StateError('endpoint unreachable');
    }
    return {};
  }

  ReconnectionCoordinator coordinator({
    ConnectionPolicy policy = const ConnectionPolicy(),
    String name = 'owner',
  }) => ReconnectionCoordinator(
    request: request,
    policy: policy,
    ownerPrefix: name,
    schedule: (delay, run) {
      final timer = _Timer(delay, run);
      timers.add(timer);
      return timer;
    },
  );
  List<_Timer> get active => timers.where((timer) => timer.isActive).toList();
  List<ReconnectJson> get attempts => calls
      .where((call) => call.$1 == 'devices.connect')
      .map((call) => call.$2)
      .toList();
  void publish(ReconnectionCoordinator owner) {
    sequence++;
    owner.handleEvent({
      'type': 'devices.changed',
      'sequence': sequence,
      'data': {'devices': snapshot()['devices']},
    });
  }

  void updateSettings(ReconnectionCoordinator owner, ReconnectJson value) {
    settings = value;
    sequence++;
    owner.handleEvent({
      'type': 'settings.changed',
      'sequence': sequence,
      'data': value,
    });
  }
}

void main() {
  test('host stop fences the first and later snapshots until a device is manually resumed', () async {
    final host = _Host();
    final owner = host.coordinator();
    addTearDown(owner.dispose);
    owner.stopAutomaticConnections();
    await owner.start();
    await settle();
    expect(host.active, isEmpty);
    host.devices.add(_Host.device(id: 'second'));
    host.publish(owner);
    await settle();
    expect(host.active, isEmpty);
    final finish = owner.beforeRequest('devices.connect', {
      'deviceId': 'phone',
    });
    await finish();
    await settle();
    expect(host.active, hasLength(1));
    host.active.single.fire();
    await settle();
    expect(host.attempts.map((p) => p['deviceId']), ['phone']);
  });
  test('offline USB records wait for explicit system authorization', () async {
    final host = _Host()
      ..devices = [
        {..._Host.device(), 'transport': 'usb'},
      ];
    final owner = host.coordinator();
    addTearDown(owner.dispose);
    await owner.start();
    await settle();
    expect(host.active, isEmpty);
    expect(host.attempts, isEmpty);
    host.publish(owner);
    await settle();
    expect(host.active, isEmpty);
  });

  test(
    'initial offline records retry once per device with bounded backoff',
    () async {
      final host = _Host();
      final owner = host.coordinator(
        policy: const ConnectionPolicy(
          reconnectInitialDelay: Duration(seconds: 2),
          reconnectMaxDelay: Duration(seconds: 8),
        ),
      );
      addTearDown(owner.dispose);
      final first = owner.start();
      expect(identical(first, owner.start()), true);
      await first;
      await settle();
      expect(host.active.single.delay, Duration.zero);
      host.active.single.fire();
      await settle();
      expect(host.attempts.single['automatic'], true);
      expect(host.attempts.single['ownerId'], 'owner-1');
      expect(host.active.single.delay, const Duration(seconds: 2));
      host.publish(owner);
      expect(host.active.length, 1);
      for (final seconds in [4, 8, 8]) {
        host.active.single.fire();
        await settle();
        expect(host.active.single.delay, Duration(seconds: seconds));
      }
    },
  );

  test(
    'newly restored and unauthorized records never authorize reconnect',
    () async {
      final host = _Host()
        ..devices = [
          _Host.device(id: 'restored', retry: false),
          _Host.device(id: 'unauthorized', status: 'unauthorized'),
          _Host.device(id: 'paired', retry: false, status: 'paired'),
          _Host.device(id: 'connected', status: 'connected'),
        ];
      final owner = host.coordinator();
      addTearDown(owner.dispose);
      await owner.start();
      await settle();
      expect(host.active, isEmpty);
      expect(host.attempts, isEmpty);
    },
  );

  test('background keep-alive revokes pending work and foreground obtains a new lease', () async {
    final host = _Host();
    final pending = Completer<ReconnectJson>();
    host.connect = (_) => pending.future;
    final owner = host.coordinator();
    addTearDown(owner.dispose);
    await owner.start();
    await settle();
    host.active.single.fire();
    await settle();
    final attempt = host.attempts.single['attemptId'];
    host.updateSettings(owner, {
      'backgroundConnection': false,
      'backgroundKeepAlive': true,
    });
    owner.setVisible(false);
    await settle();
    expect(
      host.calls.any((call) => call.$1 == 'devices.cancel'),
      false,
      reason: 'only keep-alive controls retry',
    );
    host.updateSettings(owner, {'backgroundKeepAlive': false});
    await settle();
    expect(host.active, isEmpty);
    expect(
      host.calls.any(
        (call) =>
            call.$1 == 'devices.cancel' && call.$2['attemptId'] == attempt,
      ),
      true,
    );
    expect(
      host.calls.any(
        (call) =>
            call.$1 == 'devices.reconnect.owner' &&
            call.$2['ownerId'] == 'owner-1' &&
            call.$2['active'] == false,
      ),
      true,
    );
    pending.complete({'connected': true});
    await settle();
    expect(host.active, isEmpty);
    owner.setVisible(true);
    host.updateSettings(owner, {'backgroundKeepAlive': true});
    await settle();
    expect(host.active.length, 1);
    host.active.single.fire();
    await settle();
    expect(host.attempts.last['ownerId'], 'owner-2');
  });

  test('explicit stop survives stale offline events and native persisted state on reattachment', () async {
    final host = _Host();
    final owner = host.coordinator();
    await owner.start();
    await settle();
    final finish = owner.beforeRequest('devices.disconnect', {
      'deviceId': 'phone',
    });
    host.publish(owner);
    expect(host.active, isEmpty);
    host.devices = [_Host.device(retry: false)];
    host.sequence++;
    await finish();
    await settle();
    await owner.dispose();
    final next = host.coordinator(name: 'next');
    addTearDown(next.dispose);
    await next.start();
    await settle();
    expect(host.active, isEmpty);
    final connected = next.beforeRequest('devices.connect', {
      'deviceId': 'phone',
    });
    host.devices = [_Host.device()];
    host.sequence++;
    await connected();
    await settle();
    expect(host.active.length, 1);
  });

  test(
    'event gaps revoke old attempts and apply only current recovery snapshots',
    () async {
      final host = _Host();
      final pending = Completer<ReconnectJson>();
      host.connect = (_) => pending.future;
      final owner = host.coordinator();
      addTearDown(owner.dispose);
      await owner.start();
      await settle();
      host.active.single.fire();
      await settle();
      owner.handleEvent({'type': 'state.resync', 'data': <String, dynamic>{}});
      await settle();
      expect(host.active, isEmpty);
      host.sequence = 5;
      await owner.refresh();
      await settle();
      expect(
        host.active,
        isEmpty,
        reason: 'an internal refresh cannot end gap recovery',
      );
      owner.handleEvent({'type': 'session.frame', 'sequence': 999});
      owner.handleEvent({'type': 'runtime.heartbeat', 'sequence': 1000});
      host.sequence = 20;
      owner.handleEvent({'type': 'state.resynced', 'data': host.snapshot()});
      await settle();
      expect(host.active.length, 1);
      owner.handleEvent({
        'type': 'devices.changed',
        'sequence': 10,
        'data': {'devices': <ReconnectJson>[]},
      });
      expect(host.active.length, 1);
      pending.complete({'connected': true});
      await settle();
      expect(host.active.length, 1);
      expect(host.attempts.length, 1);
    },
  );

  test(
    'identity replacement and removal discard late work without replay',
    () async {
      final host = _Host();
      final pending = Completer<ReconnectJson>();
      host.connect = (_) => pending.future;
      final owner = host.coordinator();
      addTearDown(owner.dispose);
      await owner.start();
      await settle();
      host.active.single.fire();
      await settle();
      final finish = owner.beforeRequest(
        'identity.global.reset',
        <String, dynamic>{},
      );
      host.devices = [_Host.device(retry: false, status: 'unauthorized')];
      host.sequence++;
      await finish();
      await settle();
      pending.complete({'connected': true});
      await settle();
      expect(host.active, isEmpty);
      host.devices = <ReconnectJson>[];
      host.publish(owner);
      await settle();
      expect(host.active, isEmpty);
    },
  );

  test(
    'disposed coordinator cannot add timers to a later attachment',
    () async {
      final host = _Host();
      final pending = Completer<ReconnectJson>();
      host.connect = (_) => pending.future;
      final first = host.coordinator();
      await first.start();
      await settle();
      host.active.single.fire();
      await settle();
      await first.dispose();
      final next = host.coordinator(name: 'next');
      addTearDown(next.dispose);
      await next.start();
      await settle();
      expect(host.active.length, 1);
      pending.complete({});
      await settle();
      expect(host.active.length, 1);
      expect(
        host.calls
            .where(
              (call) =>
                  call.$1 == 'devices.reconnect.owner' &&
                  call.$2['active'] == true,
            )
            .map((call) => call.$2['ownerId']),
        ['owner-1', 'next-1'],
      );
    },
  );

  test(
    'disabled application retry policy never claims a native owner',
    () async {
      final host = _Host();
      final owner = host.coordinator(
        policy: const ConnectionPolicy(reconnectEnabled: false),
      );
      addTearDown(owner.dispose);
      await owner.start();
      await settle();
      expect(host.calls.map((call) => call.$1), ['state.snapshot']);
      expect(host.active, isEmpty);
    },
  );
}
