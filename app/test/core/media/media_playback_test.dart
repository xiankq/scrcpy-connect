import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';
import 'package:scrcpy_connect/core/media/models/video_session_view.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  for (final removed in [false, true]) {
    test('${removed ? '移除' : '离线'}设备撤销在途声音，迟到音源由原所有者停止', () async {
      final capture = _PendingAudio();
      final media = _playback(() => capture);
      final starting = expectLater(
        media.startAudio('device'),
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      media.handleApplicationEvent(
        RuntimeEvent(
          DeviceListChanged([
            if (!removed) const DeviceSnapshot(id: 'device', status: .offline),
            const DeviceSnapshot(id: 'other', status: .connected),
          ]),
        ),
      );
      capture.source.complete(_lateSource);
      await starting;
      expect(capture.stopped, [('late-source', 'device')]);
      await media.dispose();
      expect(capture.stopped, [('late-source', 'device')]);
    });
  }

  test('宿主停止等待在途声音启动和迟到源清理，不创建输出', () async {
    final capture = _PendingAudio();
    final media = _playback(() => capture);
    final starting = expectLater(
      media.startAudio('device'),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    var stopped = false;
    final stopping = media.stopForHost().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    capture.source.complete(_lateSource);
    await stopping;
    await starting;
    expect(capture.stopped, [('late-source', 'device')]);
    await media.dispose();
    expect(capture.stopped, [('late-source', 'device')]);
  });

  testWidgets('退出超时保留原启动责任，迟到源收尾后可重试关闭', (tester) async {
    final capture = _PendingAudio();
    final media = _playback(() => capture);
    final starting = expectLater(
      media.startAudio('device'),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    final closing = expectLater(
      media.dispose(),
      throwsA(
        isA<RequestFailure>().having(
          (e) => e.code,
          'code',
          'media_cleanup_unconfirmed',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 46));
    await closing;
    capture.source.complete(_lateSource);
    await tester.pump();
    await media.dispose();
    await starting;
    expect(capture.stopped, [('late-source', 'device')]);
  });

  test('空快照、设备收尾和退出不创建捕获或播放器', () async {
    final media = _playback(() => throw StateError('不应创建捕获'));
    expect(await media.readAudioSources(), isEmpty);
    await media.retireUnownedAudio();
    expect((await media.snapshot(() => true)).sessions, isEmpty);
    media.stopDeviceIntent('device');
    await media.finishDeviceStop('device');
    media.handleApplicationEvent(
      const VideoSessionChanged(
        .stopped,
        VideoSessionView(
          session: VideoSessionSnapshot(
            sessionId: 'unowned',
            deviceId: 'device',
            name: 'Phone',
            kind: .screen,
            status: .stopped,
          ),
          wake: KeepAwakeSnapshot(deviceId: 'device'),
        ),
      ).toApplicationEvent(),
    );
    await media.dispose();
    await media.handlePlatformEvent(const AudioVisibilityChanged(true));
    await media.stopForHost();
    await media.dispose();
  });

  test('首次打开才请求捕获，关闭后的打开不会重建能力', () async {
    var creations = 0;
    final failure = StateError('capture unavailable');
    final media = _playback(() {
      creations++;
      throw failure;
    });
    const plan = VideoSessionPlan(deviceId: 'device');
    await expectLater(media.startVideo(plan), throwsA(same(failure)));
    expect(creations, 1);
    await media.dispose();
    await expectLater(media.startVideo(plan), throwsA(isA<RequestFailure>()));
    expect(creations, 1);
  });
}

final _snapshot = RuntimeSnapshot(sequence: 0, settings: Preferences());

const _lateSource = DeviceAudioSnapshot(
  sourceId: 'late-source',
  deviceId: 'device',
  generation: 1,
  name: 'Audio',
  status: .starting,
  createdAt: 1,
);

MediaPlayback _playback(MediaCapture Function() captures) => MediaPlayback(
  captures: captures,
  capture: () => throw StateError('不应创建视频输入'),
  readCapturedAudio: () async => [],
  readSnapshot: () async => _snapshot,
  readSettings: () => throw StateError('不应读取画质'),
  platform: _UnusedAudioPlatform(),
  emit: (_) {},
  isDisposed: () => false,
  requireVerifiedState: () {},
  dataDirectory: '/unused',
);

class _UnusedAudioPlatform implements AudioPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应创建平台声音活动');
}

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
