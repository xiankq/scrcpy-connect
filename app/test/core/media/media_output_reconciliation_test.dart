import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/media_output_reconciliation.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  test('快照只回收读取前的同一输出，保留替换输出、新输出及可重试画质会话', () async {
    final ready = Completer<RuntimeSnapshot>();
    final videos = {
      'ended': video('ended'),
      'replaced': video('replaced'),
      'retryable': video('retryable'),
      'failed': video('failed'),
    };
    final audios = {
      'ended': audio('ended'),
      'live': audio('live'),
      'replaced': audio('replaced'),
    };
    final closedVideo = <String>[], closedAudio = <String>[];
    final reading = readAndReconcileMediaSnapshot(
      read: () => ready.future,
      videos: videos,
      audios: audios,
      closeVideo: (id) async {
        closedVideo.add(id);
        videos.remove(id);
      },
      closeAudio: (id) async {
        closedAudio.add(id);
        audios.remove(id);
      },
      current: () => true,
    );
    videos['replaced'] = video('replaced', generation: 2);
    videos['new'] = video('new');
    audios['replaced'] = audio('replaced', generation: 2);
    audios['new'] = audio('new');
    ready.complete(
      RuntimeSnapshot(
        sequence: 1,
        settings: Preferences(),
        sessions: [
          session('retryable', status: .failed, retryable: true),
          session('failed', status: .failed),
        ],
        sources: [audio('live')],
      ),
    );
    final snapshot = await reading;
    expect(closedVideo, ['ended', 'failed']);
    expect(closedAudio, ['ended']);
    expect(videos.keys, unorderedEquals(['replaced', 'retryable', 'new']));
    expect(audios.keys, unorderedEquals(['live', 'replaced', 'new']));
    expect(snapshot.sessions.first.output?.sessionId, 'retryable');
    expect(snapshot.sessions.last.output, isNull);
  });

  test('清理失败保留原输出，下一次核验重试原对象', () async {
    final original = video('ended');
    final videos = {'ended': original};
    var closes = 0;
    var allowed = false;
    Future<RuntimeSnapshot> read() => readAndReconcileMediaSnapshot(
      read: () async => RuntimeSnapshot(sequence: 1, settings: Preferences()),
      videos: videos,
      audios: {},
      closeVideo: (id) async {
        expect(videos[id], same(original));
        closes++;
        if (!allowed) throw StateError('output release failed');
        videos.remove(id);
      },
      closeAudio: (_) async => fail('不应创建音频清理'),
      current: () => true,
    );
    await expectLater(read(), throwsStateError);
    expect(videos['ended'], same(original));
    allowed = true;
    await read();
    expect(closes, 2);
    expect(videos, isEmpty);
  });

  test('无效媒体身份在资源清理前被拒绝', () async {
    final videos = {'ended': video('ended')};
    for (final sessions in [
      [session('')],
      [session('duplicate'), session('duplicate')],
    ]) {
      await expectLater(
        readAndReconcileMediaSnapshot(
          read: () async => RuntimeSnapshot(
            sequence: 1,
            settings: Preferences(),
            sessions: sessions,
          ),
          videos: videos,
          audios: {},
          closeVideo: (_) async => fail('无效快照不能释放输出'),
          closeAudio: (_) async => fail('无效快照不能释放输出'),
          current: () => true,
        ),
        throwsA(
          isA<RequestFailure>().having(
            (e) => e.code,
            'code',
            'invalid_snapshot',
          ),
        ),
      );
    }
    expect(videos, hasLength(1));
  });

  test('核验作废后迟到快照不再清理输出', () async {
    final ready = Completer<RuntimeSnapshot>();
    var current = true;
    final reading = readAndReconcileMediaSnapshot(
      read: () => ready.future,
      videos: {'ended': video('ended')},
      audios: {'ended': audio('ended')},
      closeVideo: (_) async => fail('旧核验不能释放输出'),
      closeAudio: (_) async => fail('旧核验不能释放输出'),
      current: () => current,
    );
    final outcome = expectLater(
      reading,
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    current = false;
    ready.complete(RuntimeSnapshot(sequence: 1, settings: Preferences()));
    await outcome;
  });

  test('恢复的旧纹理保留图像，不将旧输出作为新捕获的解码证据', () {
    final recovered = RecoveredVideoSession(
      session: session('session', captureGeneration: 2).session,
      output: video('session'),
    );
    final view = recovered.toViewSnapshot();
    expect(view['captureGeneration'], 2);
    expect(view['outputCaptureGeneration'], 1);
    expect(view['textureId'], 1);
    expect(view['outputRetained'], isTrue);
    expect(view['firstFrameDecoded'], isFalse);
    expect(view['evidence'], 'retained_previous_output');
  });
}

RecoveredVideoSession session(
  String id, {
  VideoSessionStatus status = .streaming,
  bool retryable = false,
  int captureGeneration = 1,
}) => RecoveredVideoSession(
  session: VideoSessionSnapshot(
    sessionId: id,
    deviceId: 'device',
    name: 'Phone',
    kind: .screen,
    status: status,
    qualityRetryable: retryable,
    captureGeneration: captureGeneration,
  ),
);

VideoOutputReceipt video(String id, {int generation = 1}) => VideoOutputReceipt(
  sessionId: id,
  deviceId: 'device',
  relayId: 'relay',
  textureId: 1,
  decodedWidth: 100,
  decodedHeight: 200,
  codec: 'h264',
  generation: generation,
  captureGeneration: 1,
  paused: false,
  decodedReceipts: 1,
  snapshotReceipts: 1,
);

DeviceAudioSnapshot audio(String id, {int generation = 1}) =>
    DeviceAudioSnapshot(
      sourceId: id,
      deviceId: 'device',
      generation: generation,
      name: 'Phone',
      status: .playing,
      createdAt: 0,
    );
