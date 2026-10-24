import '../../support/scrcpy_event_fixture.dart';

import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/events/application_snapshot_reader.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/media/capture/device_keep_awake_coordinator.dart';

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() async {
    f.native.failClose = false;
    await f.owner.close();
    for (final stream in f.native.events.values) {
      await stream.close();
    }
  });

  test('设备共享保持唤醒投影进入每个窗口，不覆盖捕获或渲染代次及退出证明', () async {
    await f.owner.windowsChanged('phone');
    final projection = f.owner.projection('phone');
    for (final id in ['first', 'second']) {
      final session = _window(id);
      final projected = sessionWithKeepAwake(session, projection);
      expect(projected['keepActiveApplied'], isTrue);
      expect(projected['keepActiveLeaseActive'], isTrue);
      expect(projected['keepActiveLeaseId'], 'keep-1');
      expect(projected['keepActivePid'], 42);
      expect(projected['keepActiveConnectionId'], 'connection-phone');
      expect(projected['sessionId'], id);
      expect(projected['captureRef'], 'capture-$id');
      expect(projected['captureGeneration'], 3);
      expect(projected['rendererGeneration'], 7);
      expect(projected['status'], 'streaming');
      expect(projected['remoteExitVerified'], isTrue);
      expect(projected['localCleanupConfirmed'], isTrue);
      expect(projected['pendingCleanup'], ['capture-cleanup']);
      expect(session, isNot(contains('keepActiveLeaseId')));
    }
    expect(f.native.created, ['keep-1'], reason: '组合投影不能启动另一份设备服务');
  });

  test('公开 SDK 关闭失败保留精确租约，重试仅确认主进程退出，不声明设置恢复', () async {
    await f.owner.windowsChanged('phone');
    f.native.failClose = true;
    f.enabled = false;
    await expectLater(
      f.owner.settingsChanged(['phone']),
      throwsA(
        isA<ApplicationCommandException>().having(
          (error) => error.code,
          'code',
          'keep_active_partial',
        ),
      ),
    );
    final failed = sessionWithKeepAwake(
      _window('first'),
      f.owner.projection('phone'),
    );
    expect(failed['keepActiveApplied'], isFalse);
    expect(failed['keepActiveLeaseActive'], isFalse);
    expect(failed['keepActiveLeaseId'], 'keep-1');
    expect(
      (failed['keepActiveError']! as Map<String, Object?>)['code'],
      'keep_active_cleanup',
    );
    final pending = failed['keepActiveCleanup']! as Map<String, Object?>;
    expect(pending['leaseId'], 'keep-1');
    expect(pending['releasePending'], isTrue);
    expect(pending['localCleanupConfirmed'], isFalse);
    expect(pending['cleanupConfirmed'], isFalse);
    expect(pending['remoteExitVerified'], isFalse);
    expect(pending['pendingCleanup'], hasLength(1));
    expect(failed['pendingCleanup'], ['capture-cleanup']);
    expect(failed['remoteExitVerified'], isTrue);

    f.native.failClose = false;
    await f.owner.windowsChanged('phone');
    final retried = sessionWithKeepAwake(
      _window('first'),
      f.owner.projection('phone'),
    );
    expect(retried['keepActiveError'], isNull);
    final cleanup = retried['keepActiveCleanup']! as Map<String, Object?>;
    expect(cleanup['releasePending'], isFalse);
    expect(cleanup['pendingCleanup'], isEmpty);
    expect(cleanup['localCleanupConfirmed'], isTrue);
    expect(cleanup['cleanupConfirmed'], isTrue);
    expect(cleanup['remoteExitVerified'], isTrue);
    expect(cleanup['remoteRestoreVerified'], isFalse);
    expect(f.native.created, ['keep-1']);
  });

  test('原生握手失败保留到恢复投影，不能因本机关闭成功而清掉启动错误', () async {
    f.native.startFailure = true;
    await expectLater(
      f.owner.sync('phone'),
      throwsA(isA<ApplicationCommandException>()),
    );
    final state = sessionWithKeepAwake(
      _window('first'),
      f.owner.projection('phone'),
    );
    expect(state['keepActiveApplied'], isFalse);
    expect(state['keepActiveLeaseActive'], isFalse);
    expect(
      (state['keepActiveError']! as Map<String, Object?>)['code'],
      'control_failed',
    );
    final cleanup = state['keepActiveCleanup']! as Map<String, Object?>;
    expect(cleanup['localCleanupConfirmed'], isTrue);
    expect(cleanup['remoteRestoreVerified'], isFalse);
    expect(state['status'], 'streaming', reason: '保持唤醒失败不能伪造画面失败');
  });

  test('另一设备和从未启动的窗口不能继承当前设备的保持唤醒租约', () async {
    await f.owner.sync('phone');
    final tablet = sessionWithKeepAwake(
      _window('tablet-window', device: 'tablet'),
      f.owner.projection('tablet'),
    );
    expect(tablet['keepActive'], isFalse);
    expect(tablet['keepActiveLeaseActive'], isFalse);
    expect(tablet['keepActiveLeaseId'], isNull);
    expect(tablet['keepActiveError'], isNull);
    expect(
      () => sessionWithKeepAwake(
        _window('tablet-window', device: 'tablet'),
        f.owner.projection('phone'),
      ),
      throwsArgumentError,
    );
    expect(f.native.created, ['keep-1']);
  });
}

Map<String, Object?> _window(String id, {String device = 'phone'}) => {
  'sessionId': id,
  'deviceId': device,
  'captureRef': 'capture-$id',
  'captureGeneration': 3,
  'rendererGeneration': 7,
  'status': 'streaming',
  'localCleanupConfirmed': true,
  'remoteExitVerified': true,
  'pendingCleanup': ['capture-cleanup'],
};

final class _Fixture {
  _Fixture() {
    owner = DeviceKeepAwakeCoordinator(
      scrcpy: ScrcpyClient(native),
      requireConnection: (id) => connections.putIfAbsent(
        id,
        () => DeviceConnection(
          client: client,
          device: AdbDevice(
            id: 'connection-$id',
            serial: 'selector-$id',
            state: 'device',
          ),
        ),
      ),
      hasWindowOwner: (_) => true,
      settings: () => {
        'deviceSettings': {
          'phone': {'stayAwake': enabled},
        },
      },
      emit: (_, _, _) {},
    );
  }
  bool enabled = true;
  final native = _Native();
  final client = _Client();
  final connections = <String, DeviceConnection>{};
  late final DeviceKeepAwakeCoordinator owner;
}

final class _Client implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('读取快照不能操作共享 ADB 连接');
}

final class _Native implements NativeScrcpyApi, NativeScrcpyStagedApi {
  final created = <String>[];
  final events = <String, StreamController<ScrcpyEvent>>{};
  bool failClose = false, startFailure = false;

  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) async {
    final id = 'keep-${created.length + 1}';
    created.add(id);
    events[id] = StreamController<ScrcpyEvent>.broadcast();
    return id;
  }

  @override
  Future<ScrcpySessionInfo> startControl(String sessionId) async {
    if (startFailure) throw const ScrcpyException('control_failed');
    return ScrcpySessionInfo(
      id: sessionId,
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
  }

  @override
  Future<void> stopSession(String captureRef) async {
    if (failClose) throw const ScrcpyException('capture_cleanup_unconfirmed');
  }

  @override
  ScrcpyEventObserver openEvents(String captureRef) =>
      observeFixtureEvents(events[captureRef]!.stream);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('组合快照不能创建媒体或操作输入');
}
