import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';

void main() {
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
    expect((await media.snapshot(() => true))['sessions'], isEmpty);
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

const _snapshot = <String, dynamic>{
  'sequence': 0,
  'settings': <String, dynamic>{},
  'devices': <Map<String, dynamic>>[],
  'sessions': <Map<String, dynamic>>[],
  'sources': <Map<String, dynamic>>[],
  'transfers': <Map<String, dynamic>>[],
  'activities': <Map<String, dynamic>>[],
  'shares': <Map<String, dynamic>>[],
  'companions': <Map<String, dynamic>>[],
};
