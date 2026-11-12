import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/control/models/device_keep_awake_changed.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

void main() {
  for (final cleanupFails in [false, true]) {
    test(
      '保持唤醒启动中撤权保留原连接，迟到句柄${cleanupFails ? '释放失败后按原对象重试' : '等待实际释放'}',
      () async {
        final native = _Native()..failStop = cleanupFails;
        final connection = DeviceConnection(
          client: _UnusedClient(),
          device: const AdbDevice(
            id: 'connection',
            serial: 'phone',
            state: 'device',
          ),
        );
        final changes = <DeviceKeepAwakeChanged>[];
        final wake = DeviceWakeService(
          scrcpy: ScrcpyClient(native),
          requireConnection: (_) => connection,
          hasWindowOwner: (_) => true,
          keepAwakeEnabled: (_) => true,
          onChanged: changes.add,
        );
        final starting = expectLater(
          wake.sync('device'),
          throwsA(isA<RequestFailure>()),
        );
        expect(changes.single.snapshot.status, KeepAwakeStatus.starting);
        expect(changes.single.snapshot.keepActiveConnectionId, 'connection');
        await Future<void>.delayed(Duration.zero);
        expect(native.created, 1);
        var stopped = false;
        final stopping = wake
            .stopForConnection('device', connection)
            .then((_) => stopped = true);
        final closing = cleanupFails
            ? expectLater(stopping, throwsA(isA<RequestFailure>()))
            : stopping;
        expect(changes.last.snapshot.status, KeepAwakeStatus.stopping);
        expect(stopped, isFalse);
        native.registered.complete('original-capture');
        await starting;
        await closing;
        expect(native.stops, isNotEmpty);
        expect(native.stops.every((id) => id == 'original-capture'), isTrue);
        if (cleanupFails) {
          expect(
            changes.last.snapshot.status,
            KeepAwakeStatus.cleanupUnconfirmed,
          );
          expect(changes.last.snapshot.releasePending, isTrue);
          expect(changes.last.snapshot.localCleanupConfirmed, isFalse);
          expect(wake.readWake('device').pendingCleanup, isNotEmpty);
          native.failStop = false;
        }
        await wake.close();
        final released = changes.last.snapshot;
        expect(released.status, KeepAwakeStatus.released);
        expect(released.keepActiveLeaseId, 'original-capture');
        expect(released.keepActiveConnectionId, 'connection');
        expect(released.cleanupConfirmed, isTrue);
        expect(released.localCleanupConfirmed, isTrue);
        expect(released.remoteExitVerified, isTrue);
        expect(released.remoteRestoreVerified, isFalse);
        expect(native.created, 1);
        final closed = native.stops.length;
        await wake.close();
        expect(native.stops, hasLength(closed));
      },
    );
  }
}

final class _Native implements NativeScrcpyApi {
  final registered = Completer<String>();
  int created = 0;
  bool failStop = false;
  final stops = <String>[];

  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) {
    expect(connectionId, 'connection');
    expect(options.keepActive, isTrue);
    expect(options.control, isTrue);
    expect(options.video, isFalse);
    expect(options.audio, isFalse);
    expect(options.powerOn, isFalse);
    created++;
    return registered.future;
  }

  @override
  Future<void> stopSession(String id) async {
    stops.add(id);
    if (failStop) throw StateError('原生关闭尚未确认');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('撤权后不能调用 ${invocation.memberName}');
}

final class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('保持唤醒不能重建连接');
}
