import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/connection/device_power_coordinator.dart';

const _id = '00000000-0000-4000-8000-000000000001';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() => fixture.close());

  test('明确请求只执行一次固定 WAKEUP，退出成功不冒充已亮屏或解锁', () async {
    final receipt = await fixture.wake();
    final request = fixture.api.requests.single;
    expect(request.kind, AdbServiceKind.shellRaw);
    expect(request.service, 'input keyevent KEYCODE_WAKEUP');
    expect(request.arguments, isEmpty);
    expect(request.maxOutput, 8192);
    expect(fixture.api.timeouts, [5000]);
    expect(receipt, {
      'deviceId': _id,
      'connectionId': 'physical-1',
      'commandCompleted': true,
      'exitCode': 0,
      'evidence': 'shell_exit_success',
      'screenStateVerified': false,
      'screenOn': null,
      'locked': null,
    });
    expect(fixture.api.cancelled, ['wake-1']);
    expect(fixture.owner.current(_id), same(fixture.connection));
    expect(fixture.client.disconnected, isEmpty);
  });

  test('旧 adbd 发送前选择一次 raw shell，跨包随机尾部与完整 EOF 共同证明退出', () async {
    fixture.api.features = [];
    final nonces = <String>[];
    for (var round = 0; round < 2; round++) {
      var read = 0;
      fixture.api.read = (_) async {
        final nonce = _legacyNonce(fixture);
        if (read++ == 0) {
          nonces.add(nonce);
          return _data('diagnostic output\n${nonce.substring(0, 10)}');
        }
        if (read == 2) return _data('${nonce.substring(10)}:0\n');
        return _event('end', done: true);
      };
      final receipt = await fixture.wake();
      final request = fixture.api.requests.last;
      expect(request.kind, AdbServiceKind.raw);
      expect(
        request.service.startsWith('shell:input keyevent KEYCODE_WAKEUP;'),
        isTrue,
      );
      expect('KEYCODE_WAKEUP'.allMatches(request.service), hasLength(1));
      expect(request.service, contains(r'__wake_status=$?;'));
      expect(request.service, contains(r'"$__wake_status"'));
      expect(receipt['evidence'], 'legacy_shell_exit_success');
      expect(receipt['commandCompleted'], isTrue);
      expect(receipt['screenOn'], isNull);
      expect(receipt['locked'], isNull);
      expect(receipt['screenStateVerified'], isFalse);
    }
    expect(nonces.toSet(), hasLength(2));
    expect(fixture.api.requests, hasLength(2));
    expect(fixture.api.cancelled, ['wake-1', 'wake-2']);
  });

  test('旧 shell 回执保留 input 的真实非零退出，不把后续 echo 成功当唤醒成功', () async {
    fixture.api.features = [];
    var read = 0;
    fixture.api.read = (_) async => read++ == 0
        ? _data('\n${_legacyNonce(fixture)}:127\n')
        : _event('end', done: true);
    await expectLater(
      fixture.wake(),
      throwsA(
        isA<RequestFailure>()
            .having((error) => error.code, 'code', 'wake_failed')
            .having((error) => error.details, 'details', {'exitCode': 127}),
      ),
    );
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelled, ['wake-1']);
  });

  test('旧 shell 缺失、伪造、重复、截断或尾部追加回执均保留结果未知且不重播', () async {
    fixture.api.features = [];
    final invalidOutputs = <String Function(String)>[
      (_) => '',
      (_) => '\nSCRCPY_WAKE_forged:0\n',
      (nonce) => '\n$nonce:0',
      (nonce) => '\n$nonce:0\ntrailing',
      (nonce) => '\n$nonce:0\n\n',
      (nonce) => '\n$nonce:0\n\n$nonce:0\n',
      (nonce) => '\n$nonce:00\n',
      (nonce) => '\n$nonce:256\n',
    ];
    for (final output in invalidOutputs) {
      var read = 0;
      fixture.api.read = (_) async => read++ == 0
          ? _data(output(_legacyNonce(fixture)))
          : _event('end', done: true);
      await expectLater(fixture.wake(), _failure('result_unknown'));
    }
    expect(fixture.api.requests, hasLength(invalidOutputs.length));
    expect(
      fixture.api.requests.every(
        (request) => request.kind == AdbServiceKind.raw,
      ),
      isTrue,
    );
  });

  test('旧 shell 仅收到标记但通道截断，不能把未确认 EOF 当成功', () async {
    fixture.api.features = [];
    var read = 0;
    fixture.api.read = (_) async =>
        read++ == 0 ? _data('\n${_legacyNonce(fixture)}:0\n') : null;
    await expectLater(fixture.wake(), _failure('result_unknown'));
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelled, ['wake-1']);
  });

  test('旧 shell EOF 已返回但 Dart 未处理时取消，精确回收且不转 shell v2 重播', () async {
    fixture.api.features = [];
    final readEof = Completer<void>();
    final eof = Completer<NativeAdbEvent?>();
    var read = 0;
    fixture.api.read = (_) async {
      if (read++ == 0) return _data('\n${_legacyNonce(fixture)}:0\n');
      readEof.complete();
      return eof.future;
    };
    final cancellation = AdbCancellation();
    final rejected = expectLater(
      fixture.wake(cancellation: cancellation),
      _failure('cancelled'),
    );
    await readEof.future;
    eof.complete(_event('end', done: true));
    cancellation.cancel();
    await rejected;
    expect(fixture.api.requests.single.kind, AdbServiceKind.raw);
    expect(fixture.api.cancelled, ['wake-1']);
  });

  test('未知退出码、非零退出和缺少终态均不自动重放', () async {
    for (final (event, code) in [
      (_exit(null), 'result_unknown'),
      (_exit(1), 'wake_failed'),
      (_event('stdout', done: true), 'result_unknown'),
    ]) {
      fixture.api.read = (_) async => event;
      await expectLater(fixture.wake(), _failure(code));
    }
    fixture.api.read = (_) async => null;
    await expectLater(fixture.wake(), _failure('result_unknown'));
    expect(fixture.api.requests, hasLength(4));
    expect(fixture.api.cancelled, ['wake-1', 'wake-2', 'wake-3', 'wake-4']);
  });

  test('stdout 与 stderr 共用字节限额，畸形退出不能当作完成', () async {
    final chunks = [
      _event('stdout', bytes: 4096),
      _event('stderr', bytes: 4097),
    ];
    fixture.api.read = (_) async => chunks.removeAt(0);
    await expectLater(fixture.wake(), _failure('byte_limit'));
    fixture.api.read = (_) async =>
        _event('exit', done: true, bytes: 1, exitCode: 0);
    await expectLater(fixture.wake(), _failure('invalid_data'));
    expect(fixture.api.requests, hasLength(2));
  });

  test('请求携带旧 connectionId 或实际连接已关闭时不执行设备命令', () async {
    await expectLater(
      fixture.wake(connectionId: 'old'),
      _failure('stale_connection'),
    );
    fixture.api.connectionClosed = true;
    await expectLater(fixture.wake(), _failure('stale_connection'));
    fixture.api.connectionClosed = false;
    fixture.api.physicalId = null;
    await expectLater(fixture.wake(), _failure('stale_connection'));
    expect(fixture.api.requests, isEmpty);
  });

  test('读取连接事实期间取消，不创建 shell；取消等待真实读取结束', () async {
    final started = Completer<void>(), release = Completer<void>();
    fixture.api.beforeFacts = () async {
      started.complete();
      await release.future;
    };
    final stop = AdbCancellation();
    final rejected = expectLater(
      fixture.wake(cancellation: stop),
      _failure('cancelled'),
    );
    await started.future;
    stop.cancel();
    var closed = false;
    final closing = fixture.power.close().then((_) => closed = true);
    await Future<void>.value();
    expect(closed, isFalse);
    release.complete();
    await rejected;
    await closing;
    expect(fixture.api.requests, isEmpty);
  });

  test('创建已开始后断开须等待迟到句柄关闭，再释放原连接与平台资源', () async {
    final created = fixture.api.opening = Completer<String>();
    var platformReleased = false;
    await fixture.owner.disconnect(_id);
    fixture.connection = await fixture.connect(
      releasePlatformResources: () async => platformReleased = true,
    );
    final rejected = expectLater(fixture.wake(), _failure('cancelled'));
    await fixture.api.started.future;
    var disconnected = false;
    final disconnecting = fixture.owner
        .disconnect(_id)
        .then((_) => disconnected = true);
    expect(fixture.owner.current(_id), isNull);
    await Future<void>.value();
    expect(disconnected, isFalse);
    expect(platformReleased, isFalse);
    created.complete('late-wake');
    await rejected;
    await disconnecting;
    expect(fixture.api.cancelled, ['late-wake']);
    expect(platformReleased, isTrue);
    expect(fixture.api.requests, hasLength(1));
  });

  test('同一读取已返回而 Dart 未处理时取消，迟到成功不能交付', () async {
    final next = Completer<NativeAdbEvent?>();
    fixture.api.read = (_) => next.future;
    final stop = AdbCancellation();
    final rejected = expectLater(
      fixture.wake(cancellation: stop),
      _failure('cancelled'),
    );
    await fixture.api.reading.future;
    next.complete(_exit(0));
    stop.cancel();
    await rejected;
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelled, ['wake-1']);
  });

  test('停止等待执行和精确 closer 收尾，不把发送取消当作已关闭', () async {
    final next = Completer<NativeAdbEvent?>(), closeGate = Completer<void>();
    fixture.api.read = (_) => next.future;
    fixture.api.beforeCancel = (_) => closeGate.future;
    final rejected = expectLater(fixture.wake(), _failure('cancelled'));
    await fixture.api.reading.future;
    var stopped = false;
    final stopping = fixture.power
        .stopConnection(_id, fixture.connection)
        .then((_) => stopped = true);
    next.complete(_exit(0));
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(fixture.client.disconnected, isEmpty);
    closeGate.complete();
    await rejected;
    await stopping;
    await expectLater(Future.sync(fixture.wake), _failure('stale_connection'));
    expect(fixture.api.requests, hasLength(1));
  });

  test('旧连接退休等待唤醒退出，新连接与旧关闭回执精确隔离', () async {
    final next = Completer<NativeAdbEvent?>();
    fixture.api.read = (_) => next.future;
    final old = fixture.connection;
    final rejected = expectLater(fixture.wake(), _failure('cancelled'));
    await fixture.api.reading.future;
    final replacing = fixture.connect();
    expect(fixture.owner.current(_id), isNull);
    next.complete(_exit(0));
    await rejected;
    final replacement = await replacing;
    fixture.api.read = null;
    await fixture.power.stopConnection(_id, old);
    expect(fixture.owner.current(_id), same(replacement));
    expect((await fixture.wake())['commandCompleted'], isTrue);
    expect(fixture.api.requestDevices, [old.device.id, replacement.device.id]);
    expect(fixture.api.requests, hasLength(2));
  });

  test('Dart 连接对象未变但原生物理身份已替换，不发布成功', () async {
    fixture.api.read = (_) async {
      fixture.api.physicalId = 'physical-2';
      return _exit(0);
    };
    await expectLater(fixture.wake(), _failure('stale_connection'));
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelled, ['wake-1']);
  });

  test('精确关闭失败阻止 ConnectionOwner 断开，重试只清理原句柄', () async {
    fixture.api.failCancel = true;
    await expectLater(fixture.wake(), _failure('wake_cleanup_unconfirmed'));
    await expectLater(
      Future.sync(fixture.wake),
      _failure('wake_cleanup_unconfirmed'),
    );
    await expectLater(
      fixture.owner.disconnect(_id),
      _failure('wake_cleanup_unconfirmed'),
    );
    expect(fixture.client.disconnected, isEmpty);
    fixture.api.failCancel = false;
    await fixture.owner.disconnect(_id);
    expect(fixture.client.disconnected, [fixture.connection.device.id]);
    expect(fixture.api.cancelled.toSet(), {'wake-1'});
    expect(fixture.api.requests, hasLength(1));
  });

  test('全局关闭失败保留同句柄重试且准入永久关闭', () async {
    fixture.api.failCancel = true;
    await expectLater(fixture.wake(), _failure('wake_cleanup_unconfirmed'));
    await expectLater(
      fixture.power.close(),
      _failure('wake_cleanup_unconfirmed'),
    );
    await expectLater(Future.sync(fixture.wake), _failure('disposed'));
    fixture.api.failCancel = false;
    await fixture.power.close();
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.client.disconnected, isEmpty);
  });

  test('已协商 shell v2 的执行失败保留 typed 错误，不发送后回退或重播', () async {
    fixture.api.creationFailure = const AdbException(
      'unsupported',
      'shell_v2 required',
    );
    await expectLater(fixture.wake(), _failure('unsupported'));
    expect(fixture.api.requests, hasLength(1));
    expect(fixture.api.cancelled, isEmpty);
  });
}

Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((error) => error.code, 'code', code));

NativeAdbEvent _exit(int? code) => _event('exit', done: true, exitCode: code);
NativeAdbEvent _data(String text) => NativeAdbEvent(
  kind: 'data',
  bytes: Uint8List.fromList(utf8.encode(text)),
  done: false,
);
String _legacyNonce(_Fixture fixture) =>
    RegExp(r'SCRCPY_WAKE_[0-9a-f]{32}')
        .firstMatch(fixture.api.requests.last.service)![0]!;
NativeAdbEvent _event(
  String kind, {
  bool done = false,
  int bytes = 0,
  int? exitCode,
}) => NativeAdbEvent(
  kind: kind,
  bytes: Uint8List(bytes),
  done: done,
  exitCode: exitCode,
);

final class _Fixture {
  final api = _Api();
  late final client = _Client(api);
  late final ConnectionOwner owner;
  late final DevicePowerCoordinator power;
  late DeviceConnection connection;
  int _next = 0;

  static Future<_Fixture> open() async {
    final fixture = _Fixture();
    fixture.power = DevicePowerCoordinator(
      requireConnection: (id) => fixture.owner.require(id),
    );
    fixture.owner = ConnectionOwner(
      stopActivities: fixture.power.stopConnection,
    );
    fixture.connection = await fixture.connect();
    return fixture;
  }

  Future<DeviceConnection> connect({
    Future<void> Function()? releasePlatformResources,
  }) => owner.replace(
    _id,
    open: (_) async => DeviceConnection(
      client: client,
      device: AdbDevice(
        id: 'connection-${++_next}',
        serial: '192.0.2.1:5555',
        state: 'device',
      ),
      releasePlatformResources: releasePlatformResources,
    ),
    verify: (_, _) async {},
  );

  Future<Map<String, Object?>> wake({
    String? connectionId = 'physical-1',
    AdbCancellation? cancellation,
  }) => power.command('devices.wake', {
    'deviceId': _id,
    'connectionId': ?connectionId,
  }, cancellation: cancellation);

  Future<void> close() async {
    api.failCancel = false;
    await power.close();
    await owner.close();
  }
}

final class _Client implements AdbClient {
  _Client(this.api);
  final _Api api;
  final disconnected = <String>[];
  @override
  late final services = AdbServices(() => api, (device) async => device, () {});
  @override
  Future<void> disconnect(AdbDevice device) async =>
      disconnected.add(device.id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Api implements NativeAdbApi {
  final requests = <AdbServiceRequest>[];
  final requestDevices = <String>[];
  final timeouts = <int>[];
  final cancelled = <String>[];
  final started = Completer<void>(), reading = Completer<void>();
  Completer<String>? opening;
  Future<void> Function()? beforeFacts;
  Future<void> Function(String)? beforeCancel;
  Future<NativeAdbEvent?> Function(String)? read;
  Object? creationFailure;
  bool failCancel = false, connectionClosed = false;
  List<String> features = const ['shell_v2'];
  String? physicalId = 'physical-1';

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    await beforeFacts?.call();
    return AdbConnectionFacts(
      officialServer: false,
      closed: connectionClosed,
      features: features,
      connectionId: physicalId,
    );
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    requests.add(request);
    requestDevices.add(id);
    timeouts.add(timeoutMs);
    if (!started.isCompleted) started.complete();
    if (creationFailure case final error?) throw error;
    return opening?.future ?? 'wake-${requests.length}';
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    if (!reading.isCompleted) reading.complete();
    return read?.call(id) ?? _exit(0);
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    await beforeCancel?.call(id);
    if (failCancel) {
      throw const AdbException('io_error', 'injected cleanup failure');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
