import '../../support/scrcpy_event_fixture.dart';

import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/media/device_keep_awake_coordinator.dart';

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() async {
    f.native.failStop = false;
    await f.owner.close();
    for (final controller in f.native.events.values) {
      await controller.close();
    }
  });

  test('首末窗口与设置决定每设备共享控制捕获，不亮屏或修改永久超时', () async {
    f.enabled = false;
    await f.owner.sync('phone');
    expect(f.native.created, isEmpty);
    f.enabled = true;
    f.windows = 0;
    await f.owner.sync('phone');
    expect(f.native.created, isEmpty);
    f.windows = 1;
    await f.owner.windowsChanged('phone');
    f.windows = 2;
    await f.owner.windowsChanged('phone');
    f.windows = 1;
    await f.owner.windowsChanged('phone');
    expect(f.native.created, ['capture-1']);
    final options = f.native.options.single;
    expect(options.video, isFalse);
    expect(options.audio, isFalse);
    expect(options.control, isTrue);
    expect(options.keepActive, isTrue);
    expect(options.powerOn, isFalse);
    expect(options.powerOffOnClose, isFalse);
    expect(options.stayAwake, isFalse);
    expect(options.cleanup, isFalse);
    expect(options.clipboardAutosync, isFalse);
    expect(f.owner.projection('phone')['keepActiveApplied'], isTrue);
    f.windows = 0;
    final closing = f.owner.windowsChanged('phone');
    expect(f.owner.projection('phone')['keepActiveLeaseActive'], isFalse);
    await closing;
    expect(f.native.stopped, ['capture-1']);
    final released = f.owner.projection('phone');
    expect(released['localCleanupConfirmed'], isTrue);
    expect(released['cleanupConfirmed'], isTrue);
    expect(released['remoteExitVerified'], isTrue);
    expect(released['remoteRestoreVerified'], isFalse);
  });

  test('设置禁用时创建晚到仍被精确回收，禁用 Future 等实际交付', () async {
    final creation = f.native.creation = Completer<String>();
    final starting = f.owner.sync('phone');
    final rejected = expectLater(starting, throwsA(_error('cancelled')));
    await f.native.createStarted.future;
    f.enabled = false;
    var finished = false;
    final disabling = f.owner
        .settingsChanged(['phone'])
        .then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    creation.complete('late-capture');
    await disabling;
    await rejected;
    expect(f.native.started, isEmpty);
    expect(f.native.stopped, ['late-capture']);
    expect(f.owner.projection('phone')['releasePending'], isFalse);
  });

  test('停止先关闭原捕获唤醒控制握手，再等实际启动退出，不互相等待', () async {
    f.native.control = Completer<ScrcpySessionInfo>();
    final starting = f.owner.sync('phone');
    final rejected = expectLater(starting, throwsA(_error('cancelled')));
    await _until(() => f.native.started.isNotEmpty);
    f.windows = 0;
    await f.owner.windowsChanged('phone');
    await rejected;
    expect(f.native.stopped, ['capture-1']);
    expect(f.owner.projection('phone')['localCleanupConfirmed'], isTrue);
  });

  test('关闭失败保留同句柄与关闭权，重试成功前不能创建第二服务', () async {
    await f.owner.sync('phone');
    f.native.failStop = true;
    f.enabled = false;
    await expectLater(
      f.owner.sync('phone'),
      throwsA(_error('keep_active_cleanup')),
    );
    final pending = f.owner.projection('phone');
    expect(pending['keepActiveApplied'], isFalse);
    expect(pending['keepActiveLeaseActive'], isFalse);
    expect(pending['releasePending'], isTrue);
    expect(pending['pendingCleanup'], hasLength(1));
    f.enabled = true;
    await expectLater(
      f.owner.sync('phone'),
      throwsA(_error('keep_active_cleanup')),
    );
    expect(f.native.created, ['capture-1']);
    f.native.failStop = false;
    await f.owner.sync('phone');
    expect(f.native.created, ['capture-1', 'capture-2']);
    expect(f.owner.projection('phone')['keepActiveLeaseId'], 'capture-2');
    expect(f.owner.projection('phone')['keepActiveLeaseActive'], isTrue);
    expect(f.owner.projection('phone')['pendingCleanup'], isEmpty);
  });

  test('控制握手未结束且关闭失败时及时保留重试入口，重试停止才唤醒原握手', () async {
    f.native.control = Completer<ScrcpySessionInfo>();
    final starting = f.owner.sync('phone');
    var startFinished = false;
    final rejected = expectLater(
      starting,
      throwsA(_error('cancelled')),
    ).then((_) => startFinished = true);
    await _until(() => f.native.started.isNotEmpty);
    f.native.failStop = true;
    f.windows = 0;
    await expectLater(
      f.owner.sync('phone'),
      throwsA(_error('keep_active_cleanup')),
    );
    expect(startFinished, isFalse);
    expect(f.owner.projection('phone')['pendingCleanup'], hasLength(1));
    f.native.failStop = false;
    await f.owner.sync('phone');
    await rejected;
    expect(f.native.created, ['capture-1']);
    expect(f.native.stopped, ['capture-1', 'capture-1']);
    expect(f.owner.projection('phone')['localCleanupConfirmed'], isTrue);
  });

  test('重连先等精确旧捕获回收，旧连接重复停止不会撤销新连接服务', () async {
    await f.owner.sync('phone');
    final previous = f.connection;
    final closing = f.native.closeGate = Completer<void>();
    final stop = f.owner.stopForConnection('phone', previous);
    await _until(() => f.native.stopped.isNotEmpty);
    f.connection = _connection('new-connection');
    final replacement = f.owner.sync('phone');
    await Future<void>.delayed(Duration.zero);
    expect(f.native.created, ['capture-1']);
    closing.complete();
    await stop;
    await replacement;
    expect(f.native.connections, ['connection', 'new-connection']);
    expect(
      f.owner.projection('phone')['keepActiveConnectionId'],
      'new-connection',
    );
    expect(f.owner.projection('phone')['keepActiveLeaseActive'], isTrue);
    await f.owner.stopForConnection('phone', previous);
    expect(f.native.stopped, ['capture-1']);
    expect(f.owner.projection('phone')['keepActiveLeaseId'], 'capture-2');
  });

  test('启动超时不丢弃创建 Future，晚到后真实关闭才结束', () async {
    await f.owner.close();
    f.owner = f.makeOwner(startupTimeout: const Duration(milliseconds: 5));
    final creation = f.native.creation = Completer<String>();
    var finished = false;
    final result = f.owner.sync('phone');
    final rejected = expectLater(
      result,
      throwsA(_error('keep_active_timeout')),
    ).then((_) => finished = true);
    await f.native.createStarted.future;
    await _until(() => f.owner.projection('phone')['releasePending'] == true);
    expect(finished, isFalse);
    creation.complete('late-after-timeout');
    await rejected;
    expect(f.native.stopped, ['late-after-timeout']);
    expect(f.owner.projection('phone')['localCleanupConfirmed'], isTrue);
  });

  test('服务异常结束立即撤销应用投影，后续显式通知才能重建', () async {
    await f.owner.sync('phone');
    f.native.events['capture-1']!.add(
      const ScrcpyStopped(reason: 'remote ended'),
    );
    await _until(() => f.native.stopped.isNotEmpty);
    await _until(
      () => f.owner.projection('phone')['localCleanupConfirmed'] == true,
    );
    expect(f.owner.projection('phone')['keepActiveLeaseActive'], isFalse);
    expect(
      (f.owner.projection('phone')['keepActiveError'] as Map)['code'],
      'keep_active_ended',
    );
    expect(f.native.created, hasLength(1));
    await f.owner.sync('phone');
    expect(f.native.created, hasLength(2));
  });

  test('close 失败仍关闭新准入，重复 close 重试原精确资源', () async {
    await f.owner.sync('phone');
    f.native.failStop = true;
    await expectLater(f.owner.close(), throwsA(_error('keep_active_cleanup')));
    await expectLater(f.owner.sync('phone'), throwsA(_error('disposed')));
    f.native.failStop = false;
    await f.owner.close();
    expect(f.native.created, hasLength(1));
    expect(f.native.stopped, ['capture-1', 'capture-1']);
  });
}

Matcher _error(String code) =>
    isA<RequestFailure>().having((error) => error.code, 'code', code);
Future<void> _until(bool Function() check) async {
  for (var i = 0; i < 500; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('未到达受控异步边界');
}

DeviceConnection _connection(String id) => DeviceConnection(
  client: _Client(),
  device: AdbDevice(id: id, serial: 'selector', state: 'device'),
);

final class _Fixture {
  _Fixture() {
    owner = makeOwner();
  }
  final native = _Native();
  DeviceConnection connection = _connection('connection');
  bool enabled = true, handoff = false, failEmit = false;
  int windows = 1;
  late DeviceKeepAwakeCoordinator owner;
  DeviceKeepAwakeCoordinator makeOwner({
    Duration startupTimeout = const Duration(seconds: 12),
  }) => DeviceKeepAwakeCoordinator(
    scrcpy: ScrcpyClient(native),
    requireConnection: (_) => connection,
    hasWindowOwner: (_) => windows > 0 || handoff,
    settings: () => {
      'deviceSettings': {
        'phone': {'stayAwake': enabled},
      },
    },
    emit: (_, _, _) {
      if (failEmit) throw StateError('observer failed');
    },
    startupTimeout: startupTimeout,
  );
}

final class _Client implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('保持唤醒不得关闭或另连 ADB');
}

final class _Native implements NativeScrcpyApi, NativeScrcpyStagedApi {
  final created = <String>[],
      connections = <String>[],
      stopped = <String>[],
      started = <String>[];
  final options = <ScrcpyOptions>[];
  final events = <String, StreamController<ScrcpyEvent>>{};
  final createStarted = Completer<void>();
  Completer<String>? creation;
  Completer<ScrcpySessionInfo>? control;
  Completer<void>? closeGate;
  Object? startError;
  bool failStop = false;
  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) async {
    connections.add(connectionId);
    this.options.add(options);
    if (!createStarted.isCompleted) createStarted.complete();
    final id = creation == null
        ? 'capture-${created.length + 1}'
        : await creation!.future;
    created.add(id);
    events[id] = StreamController<ScrcpyEvent>.broadcast();
    return id;
  }

  @override
  Future<ScrcpySessionInfo> startControl(String sessionId) async {
    started.add(sessionId);
    if (startError case final error?) throw error;
    return control == null ? _info(sessionId) : control!.future;
  }

  @override
  Future<void> stopSession(String sessionId) async {
    stopped.add(sessionId);
    if (failStop) throw const ScrcpyException('capture_cleanup_unconfirmed');
    if (control case final waiting? when !waiting.isCompleted) {
      waiting.completeError(const ScrcpyException('cancelled'));
    }
    await closeGate?.future;
  }

  @override
  ScrcpyEventObserver openEvents(String captureRef) =>
      observeFixtureEvents(events[captureRef]!.stream);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('保持唤醒不得等待媒体或发送输入');
}

ScrcpySessionInfo _info(String id) => ScrcpySessionInfo(
  id: id,
  deviceName: 'fixture',
  videoCodec: ScrcpyVideoCodec.h264,
  width: 0,
  height: 0,
  videoEnabled: false,
  audioEnabled: false,
  controlReady: true,
  mediaReady: false,
  processId: 42,
  processStarted: 123,
);
