import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_changed.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

void main() {
  for (final cleanupFails in [false, true]) {
    test('启动中停止保留原音源身份，迟到登记${cleanupFails ? '清理失败后可重试' : '由原所有者关闭'}', () async {
      final native = _Native()..failStop = cleanupFails;
      final events = <DeviceAudioChanged>[];
      final connection = DeviceConnection(
        client: _UnusedClient(),
        device: const AdbDevice(
          id: 'connection',
          serial: 'phone',
          state: 'device',
        ),
      );
      final owner = DeviceAudioService(
        scrcpy: ScrcpyClient(native),
        requireConnection: (_) => connection,
        hasAudioOwner: (_) => true,
        onChanged: events.add,
      );
      final starting = owner.start('device');
      final cancelled = expectLater(
        starting,
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      final original = events.single.snapshot;
      expect(original.status, DeviceAudioStatus.starting);
      expect(original.deviceId, 'device');
      await Future<void>.delayed(Duration.zero);
      expect(native.created, 1);
      var completed = false;
      final stopping = owner.stop('device').then((_) => completed = true);
      final stopped = cleanupFails
          ? expectLater(stopping, throwsA(same(native.closeFailure)))
          : stopping;
      expect(events.last.snapshot.sourceId, original.sourceId);
      expect(events.last.snapshot.generation, original.generation);
      expect(events.last.snapshot.status, DeviceAudioStatus.stopped);
      expect(completed, isFalse);
      expect(native.stops, isEmpty);
      native.registered.complete('original-capture');
      await cancelled;
      await stopped;
      expect(native.stops, ['original-capture']);
      if (cleanupFails) {
        final retained = owner.snapshots().single;
        expect(events.last.snapshot, same(retained));
        expect(retained.sourceId, original.sourceId);
        expect(retained.cleanupError!.code, 'audio_cleanup_unconfirmed');
        expect(retained.localReleased, isFalse);
        native.failStop = false;
      }
      await owner.close();
      expect(owner.snapshots(), isEmpty);
      expect(native.created, 1);
      expect(native.stops, [
        'original-capture',
        if (cleanupFails) 'original-capture',
      ]);
      await owner.close();
      expect(native.stops, hasLength(cleanupFails ? 2 : 1));
    });
  }
}

class _Native implements NativeScrcpyApi {
  final registered = Completer<String>();
  final stops = <String>[];
  int created = 0;
  bool failStop = false;
  final closeFailure = StateError('native close not confirmed');
  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) {
    expect(connectionId, 'connection');
    expect(options.audio, isTrue);
    expect(options.video, isFalse);
    created++;
    return registered.future;
  }

  @override
  Future<void> stopSession(String sessionId) async {
    stops.add(sessionId);
    if (failStop) throw closeFailure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('停止后不应调用 ${invocation.memberName}');
}

class _UnusedClient implements AdbClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('音源不应重建连接');
}
