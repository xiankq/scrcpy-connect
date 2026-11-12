import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  for (final removed in [false, true]) {
    test('${removed ? '移除' : '离线'}设备撤销在途声音，迟到音源由原所有者停止', () async {
      final capture = _PendingAudio();
      final media = MediaPlayback(
        captures: () => capture,
        capture: () => throw StateError('不应创建视频输入'),
        readCapturedAudio: () async => [],
        readSnapshot: () async => _snapshot,
        readSettings: () => throw StateError('不应读取画质'),
        platform: (_, _) => throw StateError('不应创建声音输出'),
        emit: (_) {},
        isDisposed: () => false,
        requireVerifiedState: () {},
        dataDirectory: '/unused',
      );
      final starting = expectLater(
        media.startAudio('device'),
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      media.handleApplicationEvent({
        'type': 'devices.changed',
        'data': DeviceListChanged([
          if (!removed) const DeviceSnapshot(id: 'device', status: .offline),
          const DeviceSnapshot(id: 'other', status: .connected),
        ]),
      });
      capture.source.complete(
        const DeviceAudioSnapshot(
          sourceId: 'late-source',
          deviceId: 'device',
          generation: 1,
          name: 'Audio',
          status: .starting,
          createdAt: 1,
        ),
      );
      await starting;
      expect(capture.stopped, [('late-source', 'device')]);
      await media.dispose();
      expect(capture.stopped, [('late-source', 'device')]);
    });
  }

  test('空快照、设备收尾和退出不创建捕获或播放器', () async {
    final media = MediaPlayback(
      captures: () => throw StateError('不应创建捕获'),
      capture: () => throw StateError('不应创建视频输入'),
      readCapturedAudio: () async => [],
      readSnapshot: () async => _snapshot,
      readSettings: () => throw StateError('不应读取画质'),
      platform: (_, _) => throw StateError('不应调用平台媒体'),
      emit: (_) {},
      isDisposed: () => false,
      requireVerifiedState: () {},
      dataDirectory: '/unused',
    );
    expect(await media.readAudioSources(), isEmpty);
    await media.retireUnownedAudio();
    expect((await media.snapshot(() => true)).sessions, isEmpty);
    media.stopDeviceIntent('device');
    await media.finishDeviceStop('device');
    media.handleApplicationEvent({
      'type': 'session.disconnected',
      'data': {'sessionId': 'unowned'},
    });
    await media.dispose();
    await media.dispose();
  });

  test('首次打开才请求捕获，关闭后的打开不会重建能力', () async {
    var creations = 0;
    final failure = StateError('capture unavailable');
    final media = MediaPlayback(
      captures: () {
        creations++;
        throw failure;
      },
      capture: () => throw StateError('不应创建视频输入'),
      readCapturedAudio: () async => [],
      readSnapshot: () async => _snapshot,
      readSettings: () => throw StateError('不应读取画质'),
      platform: (_, _) => throw StateError('不应调用平台媒体'),
      emit: (_) {},
      isDisposed: () => false,
      requireVerifiedState: () {},
      dataDirectory: '/unused',
    );
    const plan = VideoSessionPlan(deviceId: 'device');
    await expectLater(media.startVideo(plan), throwsA(same(failure)));
    expect(creations, 1);
    await media.dispose();
    await expectLater(media.startVideo(plan), throwsA(isA<RequestFailure>()));
    expect(creations, 1);
  });
}

final _snapshot = RuntimeSnapshot(sequence: 0, settings: Preferences());

class _PendingAudio implements MediaCapture {
  final source = Completer<DeviceAudioSnapshot>();
  final stopped = <(String, String)>[];

  @override
  Future<DeviceAudioSnapshot> startAudio(String deviceId) => source.future;

  @override
  Future<void> stopAudio(String sourceId, String deviceId) async {
    stopped.add((sourceId, deviceId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应调用捕获能力 ${invocation.memberName}');
}
