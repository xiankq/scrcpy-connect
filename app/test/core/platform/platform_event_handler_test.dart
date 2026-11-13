import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/models/platform_share_notice.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/connections_stopped.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/platform/platform_event_handler.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';

void main() {
  for (final failing in ['connections', 'publish', 'media']) {
    test('宿主停止先撤销原重连，$failing 失败仍等待两条原清理', () async {
      final host = _Host();
      final reconnections = DeviceReconnectService(
        host: host,
        policy: const ConnectionPolicy(),
      );
      addTearDown(reconnections.dispose);
      await reconnections.start();
      final attempt = await host.started.future;
      final order = <String>[];
      final connections = Completer<void>();
      final media = Completer<void>();
      final failure = StateError(failing);
      final handler = PlatformEventHandler(
        reconnections: reconnections,
        isDisposed: () => false,
        stopConnections: () {
          expect(host.cancelled, [attempt]);
          order.add('connections');
          return connections.future;
        },
        emit: (event) {
          expect(host.cancelled, [attempt]);
          expect(event, isA<ConnectionsStopped>());
          order.add('publish');
          if (failing == 'publish') throw failure;
        },
        stopMedia: () {
          order.add('media');
          return media.future;
        },
        handleAudio: (_) async => fail('停止宿主不伪造声音平台事件'),
        handleShare: (_) async => fail('停止连接不能进入分享接收'),
      );
      final result = handler.handle(const {'type': 'connections.stopped'});
      var settled = false;
      final checked = expectLater(result, throwsA(same(failure))).then((_) {
        settled = true;
      });
      expect(order, ['connections', 'publish', 'media']);
      if (failing == 'connections') {
        connections.completeError(failure);
      } else {
        connections.complete();
      }
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      if (failing == 'media') {
        media.completeError(failure);
      } else {
        media.complete();
      }
      await checked;
      reconnections.handleEvent(
        DeviceReconnectDevicesChanged(host.devices, sequence: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(host.attempts, 1);
      host.connection.complete();
    });
  }

  test('原生分享与声音协议仅交给所属能力，未知消息和已关闭入口不发布业务事件', () async {
    var disposed = false;
    final reconnections = DeviceReconnectService(
      host: _Host(),
      policy: const ConnectionPolicy(),
    );
    addTearDown(reconnections.dispose);
    final published = <AppEvent>[];
    final shares = <PlatformShareNotice>[];
    final audio = <AudioPlatformEvent>[];
    final handler = PlatformEventHandler(
      reconnections: reconnections,
      isDisposed: () => disposed,
      stopConnections: () async => fail('未收到停止消息'),
      emit: published.add,
      handleShare: (data) async => shares.add(data),
      handleAudio: (event) async => audio.add(event),
      stopMedia: () async => fail('未收到停止消息'),
    );
    const share = {
      'type': 'share.platform.pending',
      'data': {'shareId': 'one', 'sourceCount': 0},
    };
    const focus = {
      'type': 'audio.platform.focus',
      'data': {'epoch': 1, 'signal': 'permanentLoss'},
    };
    await handler.handle(share);
    await handler.handle(focus);
    await handler.handle(const {'type': 'unknown'});
    expect(shares.single.shareId, 'one');
    expect(shares.single.sourceCount, 0);
    await expectLater(
      handler.handle(const {
        'type': 'share.platform.pending',
        'data': {'shareId': 'bad', 'sourceCount': '1'},
      }),
      throwsA(isA<FileFailure>()),
    );
    expect(shares, hasLength(1));
    expect(
      audio.single,
      isA<AudioFocusChanged>()
          .having((event) => event.epoch, 'epoch', 1)
          .having(
            (event) => event.signal,
            'signal',
            AudioFocusSignal.permanentLoss,
          ),
    );
    expect(published, isEmpty);
    disposed = true;
    await handler.handle(share);
    await handler.handle(focus);
    await handler.handle(const {'type': 'connections.stopped'});
    expect(shares, hasLength(1));
    expect(audio, hasLength(1));
    expect(published, isEmpty);
  });
}

final class _Host implements DeviceReconnectHost {
  final devices = [
    const DeviceSnapshot(
      id: 'device',
      transport: .tcp,
      status: .offline,
      autoReconnect: true,
    ),
  ];
  final started = Completer<String>();
  final connection = Completer<void>();
  final cancelled = <String>[];
  var attempts = 0;
  @override
  Future<DeviceReconnectSnapshot> readSnapshot() async =>
      DeviceReconnectSnapshot(
        sequence: 0,
        devices: devices,
        backgroundKeepAlive: false,
      );
  @override
  Future<void> setOwner(String ownerId, bool active) async {}
  @override
  Future<void> connect(String deviceId, String attemptId, String ownerId) {
    attempts++;
    started.complete(attemptId);
    return connection.future;
  }

  @override
  Future<void> cancel(String attemptId) async => cancelled.add(attemptId);
}
