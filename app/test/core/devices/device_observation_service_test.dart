import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/companion/models/companion_config.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_event.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';

void main() {
  test('真实伴生订阅交付类型化快照，旧查询不能覆盖同代新事件', () async {
    final fixture = await _Observation.open();
    final first = await fixture.owner.startObservation(fixture.device);
    expect(first.phase, DeviceObservationPhase.observing);
    expect(first.notificationsLive, isTrue);
    expect(first.callsLive, isTrue);
    final ready = (fixture.changes.last as DeviceObservationChanged).snapshot;
    expect(ready.observation.generation, first.generation);
    expect(
      ready.notifications.status,
      DeviceNotificationAvailability.available,
    );
    expect(ready.calls.status, DeviceCallAvailability.available);
    fixture.native.holdCalls = true;
    final reading = fixture.owner.readCalls(fixture.device);
    await fixture.native.callsRequested.future;
    fixture.native.update('calls.incoming', {
      ...fixture.native.section('calls'),
      'calls': [
        {'id': 'new-call', 'generation': 2, 'state': 'ringing'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    final incoming = fixture.changes.whereType<DeviceCallsChanged>().single;
    expect(incoming.incoming, isTrue);
    expect(incoming.deviceId, fixture.device);
    expect(incoming.snapshot.calls.single.id, 'new-call');
    expect(incoming.snapshot.calls.single.deviceName, 'Observed phone');
    fixture.native.completeCalls();
    expect((await reading).calls.single.id, 'new-call');
    final before = fixture.changes.length;
    fixture.native.update('notifications.changed', {
      ...fixture.native.section('notifications'),
      'observationEpoch': first.generation - 1,
      'notifications': [
        {'id': 'stale'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(fixture.changes, hasLength(before));
    fixture.native.update('notifications.changed', {
      ...fixture.native.section('notifications'),
      'notifications': [
        {'id': 'current', 'revision': '1', 'body': 'message'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    final changed = fixture.changes
        .whereType<DeviceNotificationsChanged>()
        .single;
    expect(changed.snapshot.notifications.single.id, 'current');
    expect(changed.snapshot.observationEpoch, first.generation);
    expect(
      () => changed.snapshot.notifications.clear(),
      throwsUnsupportedError,
    );
    fixture.connection = DeviceConnection(
      client: fixture.client,
      device: const AdbDevice(
        id: 'successor',
        serial: 'phone',
        state: 'device',
      ),
    );
    final delivered = fixture.changes.length;
    fixture.native.update('notifications.changed', {
      ...fixture.native.section('notifications'),
      'notifications': [
        {'id': 'late-original-connection'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(fixture.changes, hasLength(delivered));
    expect(
      fixture.owner.currentSnapshot(fixture.device).notificationsLive,
      isFalse,
    );
  });

  test('无效实时字段在协议入口失效，发布未知快照并撤销旧动作准入', () async {
    final fixture = await _Observation.open();
    await fixture.owner.startObservation(fixture.device);
    fixture.native.update('notifications.changed', {
      ...fixture.native.section('notifications'),
      'notifications': [
        {'id': 123},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(fixture.changes.whereType<DeviceNotificationsChanged>(), isEmpty);
    final failed = (fixture.changes.last as DeviceObservationChanged).snapshot;
    expect(failed.observation.phase, DeviceObservationPhase.failed);
    expect(failed.observation.notificationsLive, isFalse);
    expect(failed.notifications.live, isFalse);
    expect(failed.notifications.notifications, isEmpty);
    expect(
      (await fixture.owner.readNotifications(fixture.device)).live,
      isFalse,
    );
  });
}

final class _Observation {
  _Observation(
    this.device,
    this.client,
    this.connection,
    this.native,
    this.owner,
    this.changes,
  );
  final String device;
  final _Client client;
  DeviceConnection connection;
  final _Native native;
  final DeviceObservationService owner;
  final List<DeviceObservationEvent> changes;

  static Future<_Observation> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'typed-observation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final records = await DeviceRecordStorage.open(directory: directory);
    final record = await records.add(
      address: '192.0.2.1',
      port: 5555,
      name: 'Observed phone',
    );
    final native = _Native();
    final client = _Client(native);
    late _Observation fixture;
    final companion = CompanionService(
      requireConnection: (_) => fixture.connection,
      serverBytes: Uint8List.fromList([1, 2, 3]),
      config: const CompanionConfig(
        startupTimeout: Duration(seconds: 5),
        requestTimeout: Duration(seconds: 5),
        cleanupTimeout: Duration(seconds: 5),
        sessionTimeout: Duration(seconds: 60),
      ),
      emit: (_, _, _) {},
    );
    final changes = <DeviceObservationEvent>[];
    final owner = DeviceObservationService(
      companion: companion,
      records: records,
      onChanged: changes.add,
    );
    fixture = _Observation(
      record.id,
      client,
      DeviceConnection(
        client: client,
        device: const AdbDevice(
          id: 'original',
          serial: 'phone',
          state: 'device',
        ),
      ),
      native,
      owner,
      changes,
    );
    addTearDown(() async {
      native.completeCalls();
      await owner.close();
      await companion.close();
      await client.services.close();
    });
    return fixture;
  }
}

/// 只替换 SDK 执行；部署、认证、RPC、观察代次和关闭均走真实实现。
final class _Client implements AdbClient {
  _Client(_Native native) {
    services = AdbServices(() => native, (device) async => device, () {});
  }
  @override
  late final AdbServices services;
  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    yield AdbShellEvent(
      .stdout,
      utf8.encode(command.startsWith('rm -f') ? 'removed' : 'released:absent'),
    );
    yield AdbShellEvent(.exit, Uint8List(0), exitCode: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应创建连接：${invocation.memberName}');
}

final class _Native implements NativeAdbApi {
  final _queues = <String, Queue<NativeAdbEvent>>{};
  final _pending = <String, Completer<NativeAdbEvent?>>{};
  final _kinds = <String, String>{};
  String? _socket, _calls;
  int epoch = 0;
  bool enabled = false, holdCalls = false;
  final callsRequested = Completer<void>();

  String _open(String kind) {
    final id = '$kind-${_queues.length}';
    _queues[id] = Queue();
    _kinds[id] = kind;
    return id;
  }

  void _send(String id, NativeAdbEvent event) {
    final waiter = _pending.remove(id);
    if (waiter != null) {
      waiter.complete(event);
    } else {
      _queues[id]!.add(event);
    }
  }

  void _message(Object value) => _send(
    _socket!,
    NativeAdbEvent(
      kind: 'data',
      bytes: utf8.encode('${jsonEncode(value)}\n'),
      done: false,
    ),
  );
  void update(String type, Map<String, Object?> data) =>
      _message({'event': type, 'data': data});
  Map<String, Object?> section(String name) => {
    'status': enabled ? 'available' : 'stopped',
    'live': enabled,
    'observationEnabled': enabled,
    'observationEpoch': epoch,
    name: <Object?>[],
  };
  void completeCalls() {
    if (_calls case final id?) {
      _calls = null;
      _message({'requestId': id, 'result': section('calls')});
    }
  }

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async =>
      _open('upload');
  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    if (request.kind == .exec) {
      final process = _open('process');
      _send(
        process,
        NativeAdbEvent(
          kind: 'data',
          bytes: utf8.encode(
            '__INTEROP_PID__123:456\nINTEROP_COMPANION_READY 123\n',
          ),
          done: false,
        ),
      );
      return process;
    }
    expect(request.kind, AdbServiceKind.raw);
    return _socket = _open('socket');
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    if (_kinds[id] == 'upload') {
      if (input.kind == .finish) {
        _send(
          id,
          NativeAdbEvent(
            kind: 'done',
            bytes: Uint8List(0),
            done: true,
            transferred: 3,
          ),
        );
      }
      return;
    }
    final message =
        jsonDecode(utf8.decode(input.bytes)) as Map<String, dynamic>;
    if (message.containsKey('token')) {
      _message({'event': 'ready', 'protocol': 1, 'uid': 2000});
      return;
    }
    final command = message['command'];
    if (command == 'observation.set') {
      epoch = message['epoch'] as int;
      enabled = message['enabled'] as bool;
      _message({
        'requestId': message['requestId'],
        'result': {
          'observationEpoch': epoch,
          'observationEnabled': enabled,
          'cleanupConfirmed': true,
          'notifications': section('notifications'),
          'calls': section('calls'),
        },
      });
    } else if (command == 'calls.list' && holdCalls) {
      _calls = message['requestId'] as String;
      callsRequested.complete();
    } else {
      expect(command, 'notifications.list');
      _message({
        'requestId': message['requestId'],
        'result': section('notifications'),
      });
    }
  }

  @override
  Future<NativeAdbEvent?> next(String id) {
    if (_queues[id]!.isNotEmpty) {
      return Future.value(_queues[id]!.removeFirst());
    }
    return (_pending[id] = Completer<NativeAdbEvent?>()).future;
  }

  @override
  Future<void> cancel(String id) async =>
      _send(id, NativeAdbEvent(kind: 'done', bytes: Uint8List(0), done: true));
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应执行 ${invocation.memberName}');
}
