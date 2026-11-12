import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/media/audio_player.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/media/models/audio_output_event.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_changed.dart';
import 'package:scrcpy_connect/core/media/models/audio_format.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/widgets/remote_audio_views.dart';

void main() {
  test('播放链直接交付原输出回执，焦点丢失需要明确恢复且旧焦点不能影响新租约', () async {
    final fixture = _Audio();
    addTearDown(fixture.media.dispose);
    await fixture.media.setVisible(true);
    final playback = await fixture.media.startAudio('device');
    expect(playback.output.playbackClockAdvanced, isTrue);
    expect(playback.output.sourcePcmReceived, isTrue);
    expect(playback.output.audibleContentVerified, isFalse);
    expect(fixture.capture.ready, same(playback.output));
    const target = DeviceAudioTarget(deviceId: 'device', sourceId: 'source');
    await fixture.media.pauseAudio(target);
    await _flush();
    final presentation = fixture.events
        .whereType<AudioPresentationChanged>()
        .last;
    expect(fixture.capture.presented, contains(same(presentation.receipt)));
    expect(presentation.receipt.manualPaused, isTrue);
    await fixture.media.handlePlatformEvent({
      'type': 'audio.platform.focus',
      'data': {'epoch': 1, 'signal': 'noisy'},
    });
    final interruption = fixture.events.whereType<AudioResumeRequired>().single;
    expect(interruption.sourceId, 'source');
    expect(interruption.deviceId, 'device');
    expect(interruption.focusSignal, 'noisy');
    final views = DeviceAudioViewCoordinator(
      audio: fixture.media,
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onError: (_) => fail('没有页面租约时不应开始声音协调'),
    );
    addTearDown(views.dispose);
    views.handleEvent(interruption.toApplicationEvent());
    final oldRevision = views.playbackRequestRevision('device');
    views.handleEvent(interruption.toApplicationEvent());
    final currentRevision = views.playbackRequestRevision('device');
    expect(currentRevision, greaterThan(oldRevision));
    views.playbackSucceeded(playback, oldRevision);
    expect(views.playbackRequestRevision('device'), currentRevision);
    final interrupted = fixture.events
        .whereType<AudioPresentationChanged>()
        .last
        .receipt;
    expect(interrupted.requiresUserResume, isTrue);
    expect(interrupted.focusPaused, isTrue);
    final resumed = await fixture.media.resumeAudio(target);
    expect(resumed.output.focusEpoch, 2);
    expect(resumed.output.requiresUserResume, isFalse);
    expect(resumed.output.playState, AudioPlayState.playing);
    views.playbackSucceeded(resumed, currentRevision);
    expect(views.playbackRequestRevision('device'), 0);
    final delivered = fixture.events.length;
    await fixture.media.handlePlatformEvent({
      'type': 'audio.platform.focus',
      'data': {'epoch': 1, 'signal': 'permanentLoss'},
    });
    expect(fixture.events, hasLength(delivered));
    expect(fixture.capture.stopped, isEmpty);
    await fixture.media.stopAudio(target);
    expect(fixture.capture.stopped, [('source', 'device')]);
    expect(fixture.player.releases, 1);
  });

  test('终止快照仅关闭同设备同代次音源，迟到和无归属回执不影响当前输出', () async {
    final fixture = _Audio();
    addTearDown(fixture.media.dispose);
    await fixture.media.setVisible(true);
    await fixture.media.startAudio('device');
    for (final stale in [
      _source.copyWith(status: .stopped, deviceId: 'other'),
      _source.copyWith(status: .error, generation: 1),
      _source.copyWith(status: .stopped, sourceId: 'old-source'),
    ]) {
      fixture.media.handleApplicationEvent(
        DeviceAudioChanged(stale).toApplicationEvent(),
      );
    }
    await _flush();
    expect(fixture.player.releases, 0);
    fixture.media.handleApplicationEvent(
      DeviceAudioChanged(_source.copyWith(status: .stopped))
          .toApplicationEvent(),
    );
    await _flush();
    expect(fixture.player.releases, 1);
    expect(fixture.capture.stopped, isEmpty);
    await fixture.media.dispose();
    expect(fixture.player.releases, 1);
  });

  test('播放器失败只发布一次类型化事实，并回收精确音源及原播放器', () async {
    final fixture = _Audio();
    addTearDown(fixture.media.dispose);
    await fixture.media.setVisible(true);
    await fixture.media.startAudio('device');
    fixture.player.notifications.add({'kind': 'failed'});
    fixture.player.notifications.add({'kind': 'failed'});
    await _flush();
    final failure = fixture.events.whereType<AudioOutputFailed>().single;
    expect(failure.sourceId, 'source');
    expect(failure.deviceId, 'device');
    expect(failure.code, 'audio_failed');
    expect(fixture.capture.stopped, [('source', 'device')]);
    expect(fixture.player.releases, 1);
    await fixture.media.dispose();
    expect(fixture.player.releases, 1);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

const _source = DeviceAudioSnapshot(
  sourceId: 'source',
  deviceId: 'device',
  generation: 2,
  name: 'Phone',
  status: .starting,
  createdAt: 1,
  captureReady: true,
  mediaReady: true,
  audioSourceId:
      '0000000000000000000000000000000000000000000000000000000000000001',
);

class _Audio {
  final player = _Player();
  final capture = _Capture();
  final events = <AudioOutputEvent>[];
  int _focus = 0;
  late final media = MediaPlayback(
    captures: () => capture,
    capture: () => throw StateError('声音不应创建视频适配'),
    readCapturedAudio: () async => [],
    readSnapshot: () async =>
        RuntimeSnapshot(sequence: 0, settings: Preferences()),
    readSettings: () => throw StateError('声音不应读取画质'),
    platform: (command, params) async => switch (command) {
      'audio.platform.focus.acquire' => {'granted': true, 'epoch': ++_focus},
      'audio.platform.focus.release' => {'released': true},
      'audio.platform.background' => {'supported': false, 'ready': false},
      _ => throw StateError('非声音平台操作 $command'),
    },
    emit: (event) => events.add(event as AudioOutputEvent),
    isDisposed: () => false,
    requireVerifiedState: () {},
    dataDirectory: '/unused',
    audioPlayerFactory: () => player,
  );
}

class _Capture implements MediaCapture {
  AudioOutputReceipt? ready;
  final presented = <AudioOutputReceipt>[];
  final stopped = <(String, String)>[];

  @override
  Future<DeviceAudioSnapshot> startAudio(String deviceId) async => _source;
  @override
  DeviceAudioSnapshot prepareAudioPresentation(DeviceAudioTarget target) =>
      _source;
  @override
  Future<String?> stopDeviceAudio(DeviceAudioTarget target) async {
    stopped.add((target.sourceId!, target.deviceId));
    return target.sourceId;
  }

  @override
  Future<DeviceAudioSnapshot> readyAudio(AudioOutputReceipt receipt) async {
    ready = receipt;
    return _source.copyWith(status: .playing);
  }

  @override
  Future<DeviceAudioSnapshot> presentAudio(AudioOutputReceipt receipt) async {
    presented.add(receipt);
    return _source;
  }

  @override
  Future<void> stopAudio(String sourceId, String deviceId) async =>
      stopped.add((sourceId, deviceId));
  @override
  Future<MediaCodecSource> openAudioSource(
    String sourceId,
    int generation,
  ) async => MediaCodecSource(
    sourceId: sourceId,
    generation: generation,
    codec: 'pcm_s16le',
    attachAddress: 1,
    detachAddress: 2,
  );
  @override
  Future<ScrcpySourceStatus> sourceStatus(String sourceId) async =>
      ScrcpySourceStatus(
        captureRef: 'capture',
        sourceId: sourceId,
        generation: 1,
        kind: .audio,
        codec: 'pcm_s16le',
        status: .streaming,
        packets: 2,
        bytes: 4096,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('声音不应调用 ${invocation.memberName}');
}

class _Player implements AudioPlayer {
  final notifications = StreamController<AudioJson>.broadcast(sync: true);
  int _position = 0;
  int releases = 0;
  @override
  Stream<AudioJson> get events => notifications.stream;
  @override
  int get positionMs => (_position += 20);
  @override
  AudioJson get outputStatus => {'nativeReady': true, 'bytesWritten': 4096};
  @override
  Future<AudioFormat> open(MediaCodecSource source) async =>
      const AudioFormat('pcm_s16le', 48000, 2);
  @override
  Future<void> setPaused(bool paused) async {}
  @override
  Future<void> volume(double value, bool muted) async {}
  @override
  Future<AudioJson> release() async {
    releases++;
    await notifications.close();
    return {'nativeDeleteConfirmed': true};
  }
}
