import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';

void main() {
  test('只调度已允许重连的离线网络设备，输入集合与调用方隔离', () async {
    final input = [
      _device('network'),
      _device('usb', transport: .usb),
      _device('disabled', autoReconnect: false),
      _device('online', status: .connected),
      _device('unknown', status: .unknown),
      _device('unauthorized', status: .unauthorized),
    ];
    final host = _Host(_snapshot(1, input));
    input.clear();
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    expect(timers.active, hasLength(1));
    timers.active.single.fire();
    await _pump();
    expect(host.attempts.map((attempt) => attempt.deviceId), ['network']);
    expect(host.attempts.single.owner, host.owners.single.$1);
  });

  test('迟到快照及旧事件不能覆盖更新的连接事实', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    final stale = Completer<DeviceReconnectSnapshot>();
    host.read = () => stale.future;
    final refreshing = service.refresh();
    service.handleEvent(
      DeviceReconnectDeviceChanged(
        _device('network', status: .connected),
        sequence: 3,
      ),
    );
    host.read = null;
    host.snapshot = _snapshot(3, [_device('network', status: .connected)]);
    stale.complete(_snapshot(2, [_device('network')]));
    await refreshing;
    service.handleEvent(
      DeviceReconnectDeviceChanged(_device('network'), sequence: 2),
    );
    expect(timers.active, isEmpty);
    expect(host.attempts, isEmpty);
    expect(host.reads, 3);
  });

  test('恢复期间释放旧租约，旧连接回执不能覆盖恢复后的调度', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    timers.active.single.fire();
    await _pump();
    final previous = host.attempts.single;
    service.handleEvent(const DeviceReconnectInvalidated());
    await _pump();
    expect(timers.active, isEmpty);
    expect(host.owners.last, (previous.owner, false));
    service.handleEvent(
      DeviceReconnectRecovered(_snapshot(2, [_device('network')])),
    );
    await _pump();
    expect(timers.active, hasLength(1));
    previous.done.complete();
    await _pump();
    expect(host.reads, 1);
    timers.active.single.fire();
    await _pump();
    expect(host.attempts, hasLength(2));
    expect(host.attempts.last.owner, isNot(previous.owner));
    expect(host.attempts.last.id, isNot(previous.id));
  });

  test('连接事件早于命令返回时结束调度，不撤回已交付连接', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    timers.active.single.fire();
    await _pump();
    service.handleEvent(
      DeviceReconnectDeviceChanged(
        _device('network', status: .connected),
        sequence: 2,
      ),
    );
    host.attempts.single.done.complete();
    await _pump();
    expect(host.cancelled, isEmpty);
    expect(host.reads, 1);
    expect(timers.active, isEmpty);
  });

  test('隐藏界面遵守后台保持偏好，并丢弃旧偏好事件', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    service.setVisible(false);
    await _pump();
    expect(timers.active, isEmpty);
    service.handleEvent(
      const DeviceReconnectSettingsChanged(true, sequence: 3),
    );
    await _pump();
    expect(timers.active, hasLength(1));
    service.handleEvent(
      const DeviceReconnectSettingsChanged(false, sequence: 2),
    );
    expect(timers.active, hasLength(1));
    service.handleEvent(
      const DeviceReconnectSettingsChanged(false, sequence: 4),
    );
    await _pump();
    expect(timers.active, isEmpty);
  });

  test('宿主停止约束新发现记录，手动连接只恢复目标设备的意图', () async {
    final host = _Host(_snapshot(1, [_device('existing')]));
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    service.stopAutomaticConnections();
    host.snapshot = _snapshot(2, [_device('existing'), _device('new')]);
    await service.refresh();
    await _pump();
    expect(timers.active, isEmpty);
    final finish = service.beginChange(
      const ConnectionChange(
        ConnectionChangeKind.connect,
        deviceId: 'existing',
      ),
    );
    await finish();
    await _pump();
    expect(timers.active, hasLength(1));
    timers.active.single.fire();
    await _pump();
    expect(host.attempts.map((attempt) => attempt.deviceId), ['existing']);
  });

  test('失败退避有上限，只有匹配 GUID 的发现重置延迟', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final timers = _Timers();
    final service = _service(
      host,
      timers,
      policy: const ConnectionPolicy(reconnectMaxDelay: Duration(seconds: 4)),
    );
    await service.start();
    await _pump();
    for (final seconds in [2, 4, 4]) {
      timers.active.single.fire();
      await _pump();
      host.snapshot = _snapshot(host.snapshot.sequence + 1, [
        _device('network'),
      ]);
      host.attempts.last.done.completeError(StateError('connection refused'));
      await _pump();
      expect(timers.active.single.delay, Duration(seconds: seconds));
    }
    service.handleEvent(
      const DeviceReconnectDiscoveryChanged('different-guid', sequence: 5),
    );
    expect(timers.active.single.delay, const Duration(seconds: 4));
    service.handleEvent(
      const DeviceReconnectDiscoveryChanged('network-guid', sequence: 6),
    );
    expect(timers.active.single.delay, Duration.zero);
  });

  test('退出等待原租约释放，退出后的事件和刷新不再启动连接', () async {
    final host = _Host(_snapshot(1, [_device('network')]));
    final released = Completer<void>();
    host.release = () => released.future;
    final timers = _Timers();
    final service = _service(host, timers);
    await service.start();
    await _pump();
    var closed = false;
    final closing = service.dispose().then((_) => closed = true);
    await _pump();
    expect(closed, isFalse);
    expect(timers.active, isEmpty);
    released.complete();
    await closing;
    await service.refresh();
    service.handleEvent(
      DeviceReconnectRecovered(_snapshot(2, [_device('network')])),
    );
    await _pump();
    expect(host.reads, 1);
    expect(timers.active, isEmpty);
    expect(host.attempts, isEmpty);
  });
}

DeviceReconnectService _service(
  _Host host,
  _Timers timers, {
  ConnectionPolicy policy = const ConnectionPolicy(),
}) {
  final service = DeviceReconnectService(
    host: host,
    policy: policy,
    schedule: timers.schedule,
    ownerPrefix: 'test',
  );
  addTearDown(() async {
    await service.dispose();
    for (final attempt in host.attempts) {
      if (!attempt.done.isCompleted) attempt.done.complete();
    }
  });
  return service;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

DeviceSnapshot _device(
  String id, {
  DeviceTransport transport = .tcp,
  DeviceConnectionStatus status = .offline,
  bool autoReconnect = true,
}) => DeviceSnapshot(
  id: id,
  guid: '$id-guid',
  transport: transport,
  status: status,
  autoReconnect: autoReconnect,
);

DeviceReconnectSnapshot _snapshot(int sequence, List<DeviceSnapshot> devices) =>
    DeviceReconnectSnapshot(
      sequence: sequence,
      devices: devices,
      backgroundKeepAlive: false,
    );

class _Host implements DeviceReconnectHost {
  _Host(this.snapshot);
  DeviceReconnectSnapshot snapshot;
  Future<DeviceReconnectSnapshot> Function()? read;
  Future<void> Function()? release;
  var reads = 0;
  final owners = <(String, bool)>[];
  final attempts = <_Attempt>[];
  final cancelled = <String>[];
  @override
  Future<DeviceReconnectSnapshot> readSnapshot() async {
    reads++;
    return await read?.call() ?? snapshot;
  }

  @override
  Future<void> setOwner(String id, bool active) async {
    owners.add((id, active));
    if (!active) await release?.call();
  }

  @override
  Future<void> connect(String deviceId, String attemptId, String ownerId) {
    final attempt = _Attempt(deviceId, attemptId, ownerId);
    attempts.add(attempt);
    return attempt.done.future;
  }

  @override
  Future<void> cancel(String attemptId) async => cancelled.add(attemptId);
}

class _Attempt {
  _Attempt(this.deviceId, this.id, this.owner);
  final String deviceId, id, owner;
  final done = Completer<void>();
}

class _Timers {
  final _all = <_Timer>[];
  List<_Timer> get active => _all.where((timer) => timer.isActive).toList();
  Timer schedule(Duration delay, void Function() run) {
    final timer = _Timer(delay, run);
    _all.add(timer);
    return timer;
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
  void cancel() => isActive = false;
  void fire() {
    expect(isActive, isTrue);
    isActive = false;
    tick++;
    run();
  }
}
