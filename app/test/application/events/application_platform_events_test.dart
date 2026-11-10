import 'dart:async';

import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/services/device_reconnect_service.dart';
import 'package:scrcpy_connect/services/application_platform_events.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingTimer implements Timer {
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  test('宿主停止在核心回执前撤销自动重连，新增设备快照也不能解除停止', () async {
    final timers = <_PendingTimer>[];
    final coreStop = Completer<void>();
    final connectionStop = Completer<void>();
    var admitted = true;
    var finished = false;
    final calls = <String>[];
    final reconnections = DeviceReconnectService(
      policy: const ConnectionPolicy(),
      request: (command, params) async {
        calls.add(command);
        if (command == 'state.snapshot') {
          return {
            'sequence': 1,
            'settings': {'backgroundKeepAlive': true},
            'devices': [
              {'id': 'phone', 'autoReconnect': true, 'status': 'offline'},
            ],
          };
        }
        return {};
      },
      schedule: (_, _) {
        final timer = _PendingTimer();
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(reconnections.dispose);
    await reconnections.start();
    await _settle();
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    final emitted = <Map<String, dynamic>>[];
    final platform = ApplicationPlatformEvents(
      reconnections: reconnections,
      isDisposed: () => false,
      emit: (event) {
        expect(admitted, isFalse);
        expect(timers.where((timer) => timer.isActive), isEmpty);
        emitted.add(event);
      },
      handleShare: (_) async {},
      handleMedia: (_) async => coreStop.future,
      stopConnections: () {
        admitted = false;
        return connectionStop.future;
      },
    );

    // 宿主事件没有核心 sequence，不能等待核心停止事件或清理回执才撤销资格。
    final stopping = platform
        .handle({'type': 'connections.stopped', 'data': <String, dynamic>{}})
        .then((_) => finished = true);
    expect(coreStop.isCompleted, isFalse);
    expect(timers.where((timer) => timer.isActive), isEmpty);
    expect(emitted.single['type'], 'connections.stopped');

    reconnections.handleEvent({
      'type': 'devices.changed',
      'sequence': 2,
      'data': {
        'devices': [
          {'id': 'phone', 'autoReconnect': true, 'status': 'offline'},
          {'id': 'new-phone', 'autoReconnect': true, 'status': 'offline'},
        ],
      },
    });
    await _settle();
    expect(timers.where((timer) => timer.isActive), isEmpty);
    expect(calls.where((command) => command == 'devices.connect'), isEmpty);
    coreStop.complete();
    await _settle();
    expect(finished, isFalse);
    connectionStop.complete();
    await stopping;
  });

  for (final failConnections in [true, false]) {
    test('停止${failConnections ? '连接' : '媒体'}失败仍等待另一条真实清理', () async {
      final reconnections = DeviceReconnectService(
        policy: const ConnectionPolicy(),
        request: (_, _) async => {},
      );
      addTearDown(reconnections.dispose);
      final remaining = Completer<void>();
      final failure = StateError('cleanup not confirmed');
      final calls = <String>[];
      var finished = false;
      final platform = ApplicationPlatformEvents(
        reconnections: reconnections,
        isDisposed: () => false,
        emit: (_) => calls.add('event'),
        handleShare: (_) async {},
        stopConnections: () {
          calls.add('connections');
          if (failConnections) throw failure;
          return remaining.future;
        },
        handleMedia: (_) {
          calls.add('media');
          if (!failConnections) throw failure;
          return remaining.future;
        },
      );
      final stopping = platform.handle({'type': 'connections.stopped'});
      final checked = expectLater(
        stopping,
        throwsA(same(failure)),
      ).then((_) => finished = true);
      expect(calls, ['connections', 'event', 'media']);
      await _settle();
      expect(finished, isFalse);
      remaining.complete();
      await checked;
    });
  }

  test('停止事件呈现回调失败也不跳过连接和媒体回收', () async {
    final reconnections = DeviceReconnectService(
      policy: const ConnectionPolicy(),
      request: (_, _) async => {},
    );
    addTearDown(reconnections.dispose);
    final calls = <String>[];
    final failure = StateError('observer failed');
    final platform = ApplicationPlatformEvents(
      reconnections: reconnections,
      isDisposed: () => false,
      emit: (_) => throw failure,
      handleShare: (_) async {},
      stopConnections: () async {
        calls.add('connections');
      },
      handleMedia: (_) async {
        calls.add('media');
      },
    );
    await expectLater(
      platform.handle({'type': 'connections.stopped'}),
      throwsA(same(failure)),
    );
    expect(calls, ['connections', 'media']);
  });
}
