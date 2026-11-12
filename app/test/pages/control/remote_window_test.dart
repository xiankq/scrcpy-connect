import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  test('未知打开只查询原记录，不准备新窗口或重放应用启动', () async {
    final fixture = _Window();
    fixture.videos.listed = [
      _view(status: .failed, launch: .unknown, texture: null),
    ];
    expect(await fixture.open(), isNull);
    expect(fixture.window.presentation.appLaunchUnknown, isTrue);
    expect(fixture.window.presentation.sessionId, 'session');
    expect(fixture.preparations, 0);
    expect(fixture.videos.starts, 0);
    await fixture.window.checkAppLaunch('app');
    expect(fixture.videos.reads, 2);
    expect(fixture.videos.starts, 0);
    expect(
      await fixture.window.closeAppLaunchRecord(resetInitialAction: true),
      isTrue,
    );
    expect(fixture.videos.stops, [('session', false)]);
    expect(fixture.window.presentation.appLaunchClosed, isTrue);
  });

  test('可重试画质失败保留既有窗口与旧输出，不创建第二个应用任务', () async {
    final fixture = _Window();
    fixture.videos.listed = [_view(status: .failed, retryable: true)];
    final opened = await fixture.open();
    expect(opened!.retained, isTrue);
    expect(opened.view.sessionId, 'session');
    expect(fixture.preparations, 0);
    expect(fixture.videos.starts, 0);
    expect(fixture.window.presentation.qualityRetryable, isTrue);
    expect(fixture.window.view!.ownsBinding, isTrue);
  });

  test('关闭恢复记录后明确重新打开，不再复用路由携带的旧快照', () async {
    final fixture = _Window();
    final original = _view(status: .failed, launch: .unknown, texture: null);
    await fixture.open(existing: original);
    expect(
      await fixture.window.closeAppLaunchRecord(resetInitialAction: true),
      isTrue,
    );
    fixture.videos.starting = Future.value(_view(sessionId: 'new-session'));
    final reopened = await fixture.open(existing: original);
    expect(reopened!.retained, isFalse);
    expect(reopened.view.sessionId, 'new-session');
    expect(fixture.videos.starts, 1);
    expect(fixture.preparations, 1);
    expect(fixture.window.presentation.appLaunchClosed, isFalse);
    expect(fixture.window.presentation.appLaunchUnknown, isFalse);
  });

  test('关闭未知记录使在途核对失效，迟到列表不能复活已关闭记录', () async {
    final fixture = _Window();
    fixture.videos.listed = [
      _view(status: .failed, launch: .unknown, texture: null),
    ];
    await fixture.open();
    final listed = Completer<List<VideoSessionView>>();
    fixture.videos.listing = listed.future;
    final checking = fixture.window.checkAppLaunch('app');
    expect(
      await fixture.window.closeAppLaunchRecord(resetInitialAction: true),
      isTrue,
    );
    listed.complete(fixture.videos.listed);
    await checking;
    expect(fixture.window.presentation.appLaunchClosed, isTrue);
    expect(fixture.window.presentation.sessionId, isEmpty);
    expect(fixture.videos.starts, 0);
    expect(fixture.videos.stops, [('session', false)]);
  });

  test('销毁后的迟到启动等待原能力停止，保留应用打开记录', () async {
    final fixture = _Window();
    final native = Completer<VideoSessionView>();
    final stopping = Completer<VideoStopReceipt>();
    fixture.videos.starting = native.future;
    fixture.videos.stopping = stopping.future;
    var settled = false;
    final opening = fixture.open().then((result) {
      settled = true;
      return result;
    });
    await fixture.videos.submitted.future;
    await fixture.window.dispose(() async {});
    native.complete(_view());
    await fixture.videos.stopStarted.future;
    expect(settled, isFalse);
    expect(fixture.videos.stops, [('session', true)]);
    expect(fixture.window.view, isNull);
    stopping.complete(const VideoStopReceipt(sessionId: 'session'));
    expect(await opening, isNull);
  });

  test('状态核验作废在途呈现，迟到结果只保留身份且不会再提交打开', () async {
    final fixture = _Window();
    final native = Completer<VideoSessionView>();
    fixture.videos.starting = native.future;
    final opening = fixture.open();
    await fixture.videos.submitted.future;
    fixture.window.presentation.beginReconciliation();
    native.complete(_view());
    expect(await opening, isNull);
    expect(fixture.window.presentation.sessionId, 'session');
    expect(fixture.window.presentation.stateUnverified, isTrue);
    expect(fixture.window.presentation.session!['textureId'], isNull);
    expect(fixture.window.view, isNull);
    expect(fixture.videos.stops, isEmpty);
    expect(await fixture.open(), isNull);
    expect(fixture.videos.starts, 1);
    expect(fixture.videos.reads, 1);
  });

  test('恢复在等待尺寸时被停止，准备阶段不再唤醒或提交捕获', () async {
    final fixture = _Window();
    final preparing = Completer<void>();
    final viewport = Completer<void>();
    var wakes = 0;
    final opening = fixture.window.open(
      packageName: 'app',
      recoveringConnection: true,
      releaseInputs: () async {},
      canProceed: () => true,
      prepare: (current) async {
        preparing.complete();
        await viewport.future;
        if (!current()) return null;
        wakes++;
        return const VideoSessionPlan(deviceId: 'device', packageName: 'app');
      },
    );
    await preparing.future;
    expect(fixture.window.recoveringConnection, isTrue);
    fixture.window.cancelRecovery();
    viewport.complete();
    expect(await opening, isNull);
    expect(wakes, 0);
    expect(fixture.videos.starts, 0);
    expect(fixture.window.recoveringConnection, isFalse);
  });

  test('成功回执交付前已取得视图租约，随后销毁仍等待精确会话释放', () async {
    final fixture = _Window();
    fixture.videos.starting = Future.value(_view());
    final opened = await fixture.open();
    expect(opened, isNotNull);
    expect(fixture.window.view!.ownsBinding, isTrue);
    final stopped = Completer<VideoStopReceipt>();
    fixture.videos.stopping = stopped.future;
    var disposed = false;
    final closing = fixture.window
        .dispose(() async {})
        .then((_) => disposed = true);
    await fixture.videos.stopStarted.future;
    expect(disposed, isFalse);
    expect(fixture.videos.stops, [('session', false)]);
    stopped.complete(const VideoStopReceipt(sessionId: 'session'));
    await closing;
    expect(disposed, isTrue);
  });
}

class _Window {
  _Window() {
    views = RemoteViews(
      videos: videos,
      audio: _Audio(),
      events: const Stream.empty(),
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
      current: () => true,
    );
    window = RemoteWindow(
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
    addTearDown(() async {
      await window.dispose(() async {});
      views.dispose();
    });
  }
  final videos = _Videos();
  late final RemoteViews views;
  late final RemoteWindow window;
  int preparations = 0;

  Future<RemoteWindowOpened?> open({VideoSessionView? existing}) => window.open(
    packageName: 'app',
    recoveringConnection: false,
    existing: existing,
    releaseInputs: () async {},
    canProceed: () => true,
    prepare: (_) async {
      preparations++;
      return const VideoSessionPlan(deviceId: 'device', packageName: 'app');
    },
  );
}

VideoSessionView _view({
  String sessionId = 'session',
  VideoSessionStatus status = .streaming,
  VideoLaunchOutcome? launch,
  bool retryable = false,
  int? texture = 1,
}) => VideoSessionView(
  session: VideoSessionSnapshot(
    sessionId: sessionId,
    deviceId: 'device',
    name: 'App',
    kind: .app,
    status: status,
    packageName: 'app',
    launchOutcome: launch,
    qualityRetryable: retryable,
    textureId: texture,
    width: 100,
    height: 200,
  ),
  wake: const KeepAwakeSnapshot(deviceId: 'device'),
);

class _Videos implements VideoSessions {
  List<VideoSessionView> listed = [];
  Future<List<VideoSessionView>>? listing;
  Future<VideoSessionView>? starting;
  Future<VideoStopReceipt>? stopping;
  final submitted = Completer<void>();
  final stopStarted = Completer<void>();
  final stops = <(String, bool)>[];
  int starts = 0, reads = 0;
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) async {
    reads++;
    return listing ?? listed;
  }

  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) {
    starts++;
    if (!submitted.isCompleted) submitted.complete();
    return starting ?? (throw StateError('没有允许新的捕获'));
  }

  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) async {
    stops.add((target.sessionId!, keepLaunchRecord));
    if (!stopStarted.isCompleted) stopStarted.complete();
    return stopping ?? VideoStopReceipt(sessionId: target.sessionId!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应调用 ${invocation.memberName}');
}

class _Audio implements RemoteAudio {
  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({
    String? deviceId,
  }) async => [];
  @override
  Future<Set<String>> readAudioEligibleDevices() async => {};
  @override
  Future<void> stopAudio(DeviceAudioTarget target) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('不应调用声音 ${invocation.memberName}');
}

class _Control implements RemoteControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应发送输入');
}

class _Inspection implements DeviceInspection {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应读取设备');
}

class _Apps implements DeviceApps {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应启动其他应用');
}
