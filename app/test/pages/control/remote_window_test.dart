import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_stop_requested.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/pages/control/remote_session_lifecycle.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/control/remote_window.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  test('启动先核验原会话，命令完成仍等待权威快照，重复快照不重复协调视图', () async {
    final fixture = _Window();
    fixture.videos.listed = [_view()];
    await fixture.open();
    fixture.reconciliationPending = true;
    final native = Completer<void>();
    fixture.reconciliation = () => native.future;
    final lifecycle = fixture.lifecycle();
    final reads = fixture.videos.reads;
    final starting = lifecycle.start(
      prepare: (_) async => throw StateError('不应准备新窗口'),
    );
    expect(fixture.window.presentation.stateUnverified, isTrue);
    expect(fixture.blurs, 1);
    expect(fixture.releases, 1);
    native.complete();
    expect(await starting, isNull);
    expect(fixture.window.presentation.stateUnverified, isTrue);
    expect(fixture.videos.reads, reads);
    expect(fixture.videos.starts, 0);
    final event = RecoveryCompleted(_snapshot()).toApplicationEvent();
    expect(lifecycle.acceptEvent(event), RemoteSessionEvent.reconciled);
    expect(fixture.window.presentation.stateUnverified, isFalse);
    expect(fixture.window.presentation.paused, isTrue);
    final changes = fixture.changes;
    expect(lifecycle.acceptEvent(event), RemoteSessionEvent.handled);
    expect(fixture.changes, changes);
  });

  test('核验快照先确认成功，迟到的命令错误不能覆盖成功状态', () async {
    final fixture = _Window();
    fixture.videos.listed = [_view()];
    await fixture.open();
    final native = Completer<void>();
    fixture.reconciliation = () => native.future;
    final lifecycle = fixture.lifecycle();
    final checking = lifecycle.reconcileState();
    lifecycle.acceptEvent(RecoveryCompleted(_snapshot()).toApplicationEvent());
    expect(fixture.window.presentation.error, isNull);
    final changes = fixture.changes;
    native.completeError(StateError('late command error'));
    await checking;
    expect(fixture.window.presentation.error, isNull);
    expect(fixture.changes, changes);
    fixture.reconciliation = () => Future.error(StateError('current failure'));
    await lifecycle.reconcileState();
    expect(fixture.window.presentation.stateUnverified, isTrue);
    expect(fixture.window.presentation.error, contains('current failure'));
  });

  test('遮挡保留一次恢复意图，明确停止作废准备中的恢复且不再启动', () async {
    final fixture = _Window();
    final screen = _view().copyWith(
      session: _view().session.copyWith(packageName: null, kind: .screen),
    );
    fixture.videos.starting = Future.value(screen);
    final lifecycle = fixture.lifecycle(packageName: null);
    await lifecycle.start(
      prepare: (_) async => const VideoSessionPlan(deviceId: 'device'),
    );
    lifecycle.viewed();
    lifecycle.acceptEvent(_connection(.offline));
    lifecycle.acceptEvent(_connection(.connected));
    fixture.window.presentation.cover(true);
    expect(lifecycle.takeConnectionRecovery(), isFalse);
    expect(lifecycle.recoveryPending, isTrue);
    fixture.window.presentation.cover(false);
    expect(lifecycle.takeConnectionRecovery(), isTrue);
    expect(lifecycle.takeConnectionRecovery(), isFalse);
    final preparing = Completer<void>();
    final viewport = Completer<void>();
    var wakes = 0;
    final recovering = lifecycle.start(
      recoveringConnection: true,
      prepare: (current) async {
        preparing.complete();
        await viewport.future;
        if (!current()) return null;
        wakes++;
        return const VideoSessionPlan(deviceId: 'device');
      },
    );
    await preparing.future;
    expect(fixture.window.recoveringConnection, isTrue);
    expect(
      lifecycle.acceptEvent(
        const VideoStopRequested('session').toApplicationEvent(),
      ),
      RemoteSessionEvent.handled,
    );
    viewport.complete();
    expect(await recovering, isNull);
    lifecycle.acceptEvent(_connection(.connected));
    expect(lifecycle.takeConnectionRecovery(), isFalse);
    expect(wakes, 0);
    expect(fixture.videos.starts, 1);
  });

  test('未知应用打开仅核对原记录，退役后迟到核验不再发布页面状态', () async {
    final fixture = _Window();
    fixture.videos.listed = [_view(launch: .unknown, texture: null)];
    final lifecycle = fixture.lifecycle();
    Future<VideoSessionPlan?> prepare(bool Function() _) async =>
        throw StateError('不应重放打开');
    expect(await lifecycle.start(prepare: prepare), isNull);
    expect(await lifecycle.start(prepare: prepare), isNull);
    expect(fixture.videos.reads, 2);
    expect(fixture.videos.starts, 0);
    final native = Completer<void>();
    fixture.reconciliation = () => native.future;
    final checking = lifecycle.reconcileState();
    lifecycle.retire();
    final changes = fixture.changes;
    native.completeError(StateError('retired'));
    await checking;
    expect(
      lifecycle.acceptEvent(
        RecoveryCompleted(_snapshot()).toApplicationEvent(),
      ),
      RemoteSessionEvent.handled,
    );
    expect(fixture.changes, changes);
    expect(fixture.window.presentation.stateUnverified, isTrue);
    expect(fixture.window.presentation.error, contains('画面来源已变化'));
  });

  test('窗口只接受当前设备会话及捕获代次的失败回执', () async {
    final fixture = _Window();
    fixture.videos.listed = [
      _view().copyWith(
        session: _view().session.copyWith(captureGeneration: 2, generation: 3),
      ),
    ];
    await fixture.open();
    VideoOutputFailed failure({
      String session = 'session',
      String device = 'device',
      int capture = 2,
      int generation = 3,
    }) => VideoOutputFailed(
      sessionId: session,
      deviceId: device,
      captureGeneration: capture,
      generation: generation,
      reason: 'decoder failed',
    );
    for (final event in [
      failure(session: 'other'),
      failure(device: 'other'),
      failure(capture: 1, generation: 99),
      failure(generation: 2),
    ]) {
      expect(
        fixture.window.acceptVideoEvent(event.toApplicationEvent()),
        isNull,
      );
      expect(fixture.window.presentation.error, isNull);
    }
    final update = fixture.window.acceptVideoEvent(
      failure().toApplicationEvent(),
    );
    expect(update!.releaseInputs, isTrue);
    expect(update.geometryChanged, isFalse);
    expect(fixture.window.presentation.error, 'decoder failed');
    expect(fixture.window.presentation.paused, isTrue);
    expect(fixture.videos.starts, 0);
  });

  test('会话结束回执只要求释放旧绑定输入，帧遥测不能代替结束回执', () async {
    final fixture = _Window();
    final original = _view();
    fixture.videos.listed = [original];
    await fixture.open();
    final binding = fixture.window.presentation.binding;
    final stopped = original.copyWith(
      session: original.session.copyWith(status: .stopped, reason: 'ended'),
    );
    expect(
      fixture.window.acceptVideoEvent(
        VideoSessionChanged(.frame, stopped).toApplicationEvent(),
      ),
      isNull,
    );
    expect(fixture.window.presentation.session!.session.live, isTrue);
    final update = fixture.window.acceptVideoEvent(
      VideoSessionChanged(.stopped, stopped).toApplicationEvent(),
    );
    expect(update!.releaseInputs, isTrue);
    expect(update.previousBinding, binding);
    expect(update.wake, stopped.wake);
    expect(fixture.window.presentation.session!.session.live, isFalse);
    expect(fixture.window.presentation.error, 'ended');
  });

  test('待核验或窗口已销毁时迟到媒体事件不能产生输入和提示工作', () async {
    final fixture = _Window();
    fixture.videos.listed = [_view()];
    await fixture.open();
    final stopped = VideoSessionChanged(
      .stopped,
      _view(status: .stopped),
    ).toApplicationEvent();
    fixture.window.presentation.beginReconciliation();
    expect(fixture.window.acceptVideoEvent(stopped), isNull);
    expect(fixture.window.presentation.session!.session.live, isTrue);
    await fixture.window.dispose(() async {});
    expect(fixture.window.acceptVideoEvent(stopped), isNull);
  });

  test('输出失败保留类型化的未知打开身份，核对不重放原启动', () async {
    final fixture = _Window();
    final native = Completer<VideoSessionView>();
    fixture.videos.starting = native.future;
    final opening = fixture.open();
    await fixture.videos.submitted.future;
    native.completeError(VideoStartUncertain(_view().session));
    expect(await opening, isNull);
    expect(fixture.window.presentation.appLaunchUnknown, isTrue);
    expect(fixture.window.presentation.sessionId, 'session');
    expect(fixture.window.presentation.session!.textureId, isNull);
    expect(fixture.window.view, isNull);
    await fixture.window.checkAppLaunch('app');
    expect(fixture.window.presentation.sessionId, 'session');
    expect(fixture.videos.starts, 1);
    expect(fixture.videos.reads, 2);
  });

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
    expect(fixture.window.presentation.session!.textureId, isNull);
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
  int changes = 0, releases = 0, blurs = 0;
  bool reconciliationPending = false;
  Future<void> Function() reconciliation = () async {};

  RemoteSessionLifecycle lifecycle({String? packageName = 'app'}) {
    final lifecycle = RemoteSessionLifecycle(
      window: window,
      packageName: packageName,
      existingSession: null,
      foreground: () => true,
      routeCurrent: () => true,
      reconciliationPending: () => reconciliationPending,
      reconcile: () => reconciliation(),
      releaseInputs: () async {
        releases++;
      },
      onChanged: () {
        changes++;
      },
      onFocusLost: () {
        blurs++;
      },
    );
    addTearDown(lifecycle.dispose);
    return lifecycle;
  }

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

RuntimeSnapshot _snapshot() => RuntimeSnapshot(
  sequence: 1,
  settings: Preferences(),
  sessions: [RecoveredVideoSession(session: _view().session)],
);

RuntimeEvent _connection(DeviceConnectionStatus status) => DeviceListChanged([
  DeviceSnapshot(
    id: 'device',
    name: 'Phone',
    status: status,
    autoReconnect: true,
  ),
]).toApplicationEvent();

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
