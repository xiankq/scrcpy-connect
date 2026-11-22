import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';

void main() {
  test('退役禁止恢复和新租约，旧租约仍排空输入并关闭原能力', () async {
    final videos = _Videos();
    final registry = SessionViewRegistry(videos);
    final lease = registry.claim('session', visible: true);
    registry.retire();
    expect(lease.isCurrent, isFalse);
    expect(lease.ownsBinding, isTrue);
    expect(() => registry.claim('new', visible: true), throwsStateError);
    expect(await lease.resume(), isNull);
    expect(videos.calls, isEmpty);
    final input = Completer<void>();
    final close = lease.close(afterInput: input.future);
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, isEmpty);
    input.complete();
    expect((await close)?.sessionId, 'session');
    expect(videos.calls, ['stop:session']);
    expect(lease.ownsBinding, isFalse);
  });

  test('关闭排在已提交的暂停和输入清理之后，重复关闭不重放', () async {
    final videos = _Videos();
    final registry = SessionViewRegistry(videos);
    final lease = registry.claim('session', visible: true);
    final pause = lease.pause();
    final failure = expectLater(pause, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, ['pause:session']);
    final input = Completer<void>();
    final close = lease.close(afterInput: input.future);
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, ['pause:session']);
    videos.pausing.completeError(StateError('pause not confirmed'));
    await failure;
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, ['pause:session']);
    input.complete();
    await close;
    await lease.close();
    expect(videos.calls, ['pause:session', 'stop:session']);
  });

  test('同名会话的新页面接管后，旧关闭只等待旧输入，不停止新绑定', () async {
    final videos = _Videos();
    final registry = SessionViewRegistry(videos);
    final previous = registry.claim('session', visible: true);
    final input = Completer<void>();
    final current = registry.claim('session', visible: true);
    final oldClose = previous.close(afterInput: input.future);
    final close = current.close();
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, isEmpty);
    input.complete();
    expect(await oldClose, isNull);
    await close;
    expect(videos.calls, ['stop:session']);
  });

  test('关闭失败保留原租约，重试关闭同一会话', () async {
    final videos = _Videos()..stopping = Completer<VideoStopReceipt>();
    final registry = SessionViewRegistry(videos);
    final lease = registry.claim('session', visible: true);
    final first = lease.close();
    final failure = StateError('stop failed');
    final expectation = expectLater(first, throwsA(same(failure)));
    await Future<void>.delayed(Duration.zero);
    videos.stopping!.completeError(failure);
    await expectation;
    expect(lease.ownsBinding, isTrue);
    expect(lease.isCurrent, isFalse);
    expect(await lease.resume(), isNull);
    videos.stopping = null;
    expect((await lease.close())?.sessionId, 'session');
    expect(videos.calls, ['stop:session', 'stop:session']);
    expect(lease.ownsBinding, isFalse);
  });

  test('窗口销毁可等待且去重，视图退役不丢失原会话的清理责任', () async {
    final videos = _Videos()..stopping = Completer<VideoStopReceipt>();
    final audio = _Audio();
    final views = RemoteViews(
      videos: videos,
      audio: audio,
      events: const Stream.empty(),
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
      current: () => true,
    );
    final window = RemoteWindow(
      control: _Control(),
      videos: videos,
      inspection: _Inspection(),
      apps: _Apps(),
      connectionId: () => 'connection',
      lockOnClose: () => false,
      current: () => true,
      deviceId: 'device',
      views: views,
    );
    window.presentation.bindStart(
      const VideoSessionView(
        session: VideoSessionSnapshot(
          sessionId: 'session',
          deviceId: 'device',
          name: 'Phone',
          kind: .screen,
          status: .streaming,
        ),
        wake: KeepAwakeSnapshot(deviceId: 'device'),
      ),
      retained: false,
      recoveringConnection: false,
      submittedAppStart: false,
    );
    window.bind(visible: true);
    views.dispose();
    final input = Completer<void>();
    final cleanup = window.dispose(() => input.future);
    expect(
      window.dispose(() => throw StateError('duplicate cleanup')),
      same(cleanup),
    );
    var completed = false;
    unawaited(cleanup.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, isEmpty);
    input.complete();
    await Future<void>.delayed(Duration.zero);
    expect(videos.calls, ['stop:session']);
    expect(completed, isFalse);
    videos.stopping!.complete(const VideoStopReceipt(sessionId: 'session'));
    await cleanup;
    expect(completed, isTrue);
  });
}

class _Videos implements VideoSessions {
  final calls = <String>[];
  final pausing = Completer<VideoPlaybackReceipt>();
  Completer<VideoStopReceipt>? stopping;
  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) async {
    calls.add('stop:${target.sessionId}');
    return stopping?.future ?? VideoStopReceipt(sessionId: target.sessionId!);
  }

  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) {
    calls.add('pause:${target.sessionId}');
    return pausing.future;
  }

  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) {
    calls.add('resume:${target.sessionId}');
    throw StateError('unexpected resume');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements RemoteAudio {
  final stops = <String>[];
  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({
    String? deviceId,
  }) async => [];
  @override
  Future<Set<String>> readAudioEligibleDevices() async => {};
  @override
  Future<void> stopAudio(DeviceAudioTarget target) async {
    stops.add(target.deviceId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Control implements RemoteControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Inspection implements DeviceInspection {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Apps implements DeviceApps {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
