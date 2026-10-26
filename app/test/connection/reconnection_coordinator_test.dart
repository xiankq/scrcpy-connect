import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/stores/connection/reconnection_coordinator.dart';

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
  Future<ReconnectJson> Function(ReconnectJson)? ownership;
  Future<ReconnectJson> Function()? readSnapshot;

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
    if (command == 'state.snapshot') return readSnapshot?.call() ?? snapshot();
    if (command == 'devices.connect') {
      if (connect != null) return connect!(params);
      throw StateError('endpoint unreachable');
    }
    if (command == 'devices.reconnect.owner' && ownership != null) {
      return ownership!(params);
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
  test('宿主停止撤旧权限并等待释放后取得新租约，不自动恢复设备意图', () async {
    final host = _Host();
    final released = Completer<ReconnectJson>();
    host.ownership = (params) async {
      if (params['ownerId'] == 'owner-1' && params['active'] == false) {
        return released.future;
      }
      return {};
    };
    final owner = host.coordinator();
    addTearDown(() async {
      // 断言失败也必须释放夹具门闩，避免 teardown 等待未交付的测试回执。
      if (!released.isCompleted) released.complete({});
      await owner.dispose();
    });
    await owner.start();
    await settle();
    expect(host.active, hasLength(1));
    final oldTimer = host.active.single;
    owner.stopAutomaticConnections();
    expect(oldTimer.isActive, isFalse);
    oldTimer.fire();
    expect(host.attempts, isEmpty);
    await settle();
    expect(host.active, isEmpty);
    expect(
      host.calls
          .where((call) => call.$1 == 'devices.reconnect.owner')
          .map((call) => call.$2),
      [
        {'ownerId': 'owner-1', 'active': true},
        {'ownerId': 'owner-1', 'active': false},
      ],
    );
    released.complete({});
    await settle();
    expect(host.active, isEmpty);
    expect(host.calls.last.$1, 'devices.reconnect.owner');
    expect(host.calls.last.$2, {'ownerId': 'owner-2', 'active': true});
    host.publish(owner);
    await settle();
    expect(host.active, isEmpty);
    final finish = owner.beforeRequest('devices.connect', {
      'deviceId': 'phone',
    });
    await finish();
    await settle();
    host.active.single.fire();
    await settle();
    expect(host.attempts.single['ownerId'], 'owner-2');
  });

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
          {..._Host.device(id: 'usb'), 'transport': 'usb'},
          _Host.device(id: 'connected', status: 'connected'),
        ];
      final owner = host.coordinator();
      addTearDown(owner.dispose);
      await owner.start();
      await settle();
      expect(host.active, isEmpty);
      expect(host.attempts, isEmpty);
      host.devices = [_Host.device()];
      host.publish(owner);
      host.connect = (_) async {
        host.devices = [_Host.device(status: 'unauthorized', retry: false)];
        host.publish(owner);
        return {};
      };
      host.active.single.fire();
      await settle();
      expect(host.active, isEmpty);
      expect(host.calls.where((call) => call.$1 == 'devices.cancel'), isEmpty);
    },
  );

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

  test('核验等待及失败期间停止不依赖快照，核验成功仍保留精确停止意图', () async {
    final host = _Host()..devices = [_Host.device(), _Host.device(id: 'other')];
    final owner = host.coordinator();
    addTearDown(owner.dispose);
    await owner.start();
    await settle();
    expect(host.active, hasLength(2));
    final snapshot = Completer<ReconnectJson>();
    host.readSnapshot = () => snapshot.future;
    try {
      for (final phase in ['state.resync', 'state.resync.failed']) {
        owner.handleEvent({'type': phase});
        await settle();
        final finish = owner.beforeRequest('devices.disconnect', {
          'deviceId': 'phone',
        });
        await finish().timeout(const Duration(seconds: 1));
        expect(host.active, isEmpty);
      }
      host.sequence++;
      owner.handleEvent({'type': 'state.resynced', 'data': host.snapshot()});
      await settle();
      expect(host.active, hasLength(1));
      host.active.single.fire();
      await settle();
      expect(host.attempts.map((attempt) => attempt['deviceId']), ['other']);
    } finally {
      snapshot.complete(host.snapshot());
    }
  });

  test('停止先等待刷新时，随后开始核验也须立即释放收尾等待并保留停止意图', () async {
    final host = _Host()..devices = [_Host.device(), _Host.device(id: 'other')];
    final owner = host.coordinator();
    addTearDown(owner.dispose);
    await owner.start();
    await settle();
    final entered = Completer<void>();
    final snapshot = Completer<ReconnectJson>();
    host.readSnapshot = () {
      if (!entered.isCompleted) entered.complete();
      return snapshot.future;
    };
    final finish = owner.beforeRequest('devices.disconnect', {
      'deviceId': 'phone',
    });
    final finishing = finish();
    try {
      await entered.future;
      owner.handleEvent({'type': 'state.resync'});
      await finishing.timeout(const Duration(seconds: 1));
      expect(snapshot.isCompleted, isFalse, reason: '停止不能等待核验所依赖的快照。');
      owner.handleEvent({'type': 'state.resync.failed'});
      host.sequence++;
      snapshot.complete(host.snapshot());
      await owner.refresh();
      await settle();
      expect(host.active, isEmpty, reason: '旧刷新晚到也不能解除失败的核验。');
      owner.handleEvent({'type': 'state.resynced', 'data': host.snapshot()});
      await settle();
      expect(host.active, hasLength(1));
      host.active.single.fire();
      await settle();
      expect(host.attempts.map((attempt) => attempt['deviceId']), ['other']);
    } finally {
      if (!snapshot.isCompleted) snapshot.complete(host.snapshot());
      await finishing;
    }
  });

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
}
