import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';
import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_surface.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  testWidgets('声明式路由覆盖和恢复控制页时安全转移剪贴板焦点', (tester) async {
    final videos = _Videos();
    final dependencies = _Session();
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceReaderProvider.overrideWithValue(dependencies.devices),
        settingsManagementProvider.overrideWithValue(dependencies.settings),
        runtimeEventsProvider.overrideWithValue(const Stream.empty()),
        videoSessionsProvider.overrideWithValue(videos),
        remoteControlProvider.overrideWithValue(_Control()),
        deviceInspectionProvider.overrideWithValue(_Inspection()),
        deviceAppsProvider.overrideWithValue(_Apps()),
        videoDisplayProvider.overrideWithValue(_Displays()),
      ],
    );
    final views = RemoteViews(
      videos: videos,
      audio: _Audio(),
      events: const Stream.empty(),
      current: () => true,
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
    );
    final router = GoRouter(
      observers: [sessionRouteObserver],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ControlPage(
            device: _device,
            packageName: 'com.example.remote',
          ),
        ),
        GoRoute(
          path: '/screenshot',
          builder: (_, _) => const Scaffold(body: Text('截图')),
        ),
      ],
    );
    videos.starting.complete(
      VideoSessionView(
        session: const VideoSessionSnapshot(
          sessionId: 'session',
          deviceId: 'device',
          name: 'Phone',
          kind: .screen,
          packageName: 'com.example.remote',
          status: .streaming,
          captureGeneration: 2,
          generation: 3,
          width: 100,
          height: 200,
        ),
        wake: const KeepAwakeSnapshot(deviceId: 'device'),
        output: _output(),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RemoteViewsScope(
          views: views,
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    expect(container.read(currentDeviceProvider), 'device');
    unawaited(router.push<void>('/screenshot'));
    await tester.pumpAndSettle();
    expect(container.read(clipboardFocusProvider), isNull);
    expect(videos.pauses, ['session']);
    expect(tester.takeException(), isNull);
    router.pop();
    await tester.pumpAndSettle();
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    expect(container.read(currentDeviceProvider), 'device');
    expect(videos.resumes, ['session']);
    expect(videos.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(videos.stops, ['session']);
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      deviceReaderProvider.overrideWithValue(dependencies.devices),
      settingsManagementProvider.overrideWithValue(dependencies.settings),
      runtimeEventsProvider.overrideWithValue(const Stream.empty()),
      videoSessionsProvider.overrideWithValue(_Videos()),
      remoteControlProvider.overrideWithValue(
        container.read(remoteControlProvider),
      ),
      deviceInspectionProvider.overrideWithValue(
        container.read(deviceInspectionProvider),
      ),
      deviceAppsProvider.overrideWithValue(container.read(deviceAppsProvider)),
      videoDisplayProvider.overrideWithValue(
        container.read(videoDisplayProvider),
      ),
    ]);
    await tester.pump();
    expect(container.read(clipboardFocusProvider), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(container.read(clipboardFocusProvider), isNull);
    views.dispose();
    router.dispose();
    container.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制页直接消费类型化输出及会话，丢弃旧捕获失败并等待画质双回执', (tester) async {
    final videos = _Videos();
    final events = StreamController<RuntimeEvent>.broadcast(sync: true);
    final dependencies = _Session();
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceReaderProvider.overrideWithValue(dependencies.devices),
        settingsManagementProvider.overrideWithValue(dependencies.settings),
        runtimeEventsProvider.overrideWithValue(events.stream),
        videoSessionsProvider.overrideWithValue(videos),
        remoteControlProvider.overrideWithValue(_Control()),
        deviceInspectionProvider.overrideWithValue(_Inspection()),
        deviceAppsProvider.overrideWithValue(_Apps()),
        videoDisplayProvider.overrideWithValue(_Displays()),
      ],
    );
    final views = RemoteViews(
      videos: videos,
      audio: _Audio(),
      events: events.stream,
      current: () => true,
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
    );
    final originalOutput = _output();
    final original = VideoSessionView(
      session: const VideoSessionSnapshot(
        sessionId: 'session',
        deviceId: 'device',
        name: 'Phone',
        kind: .screen,
        status: .streaming,
        captureGeneration: 2,
        generation: 3,
        width: 100,
        height: 200,
      ),
      wake: const KeepAwakeSnapshot(deviceId: 'device'),
      output: originalOutput,
    );
    videos.starting.complete(original);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: RemoteViewsScope(
            views: views,
            child: const ControlPage(device: _device),
          ),
        ),
      ),
    );
    await tester.pump();
    final presentation = tester
        .widget<RemoteStage>(find.byType(RemoteStage))
        .presentation;
    expect(
      presentation.canSendInput(foreground: true, ownerCurrent: true),
      isTrue,
    );
    events.add(
      const VideoOutputFailed(
        sessionId: 'session',
        deviceId: 'device',
        captureGeneration: 1,
        generation: 3,
        reason: 'old capture',
      ).toApplicationEvent(),
    );
    await tester.pump();
    expect(presentation.error, isNull);
    expect(presentation.paused, isFalse);
    events.add(
      VideoSessionChanged(
        .updated,
        original.copyWith(
          session: original.session.copyWith(
            qualityRebuilding: true,
            qualityRebuildTarget: 3,
          ),
          output: null,
        ),
      ).toApplicationEvent(),
    );
    await tester.pump();
    expect(presentation.qualityRebuilding, isTrue);
    expect(
      presentation.canSendInput(foreground: true, ownerCurrent: true),
      isFalse,
    );
    final replacement = _output().copyWith(
      captureGeneration: 3,
      generation: 4,
      textureId: 4,
      decodedWidth: 200,
      decodedHeight: 100,
    );
    events.add(VideoOutputChanged(replacement).toApplicationEvent());
    await tester.pump();
    expect(presentation.qualityRebuilding, isTrue);
    expect(presentation.session!.output, originalOutput);
    events.add(
      VideoSessionChanged(
        .updated,
        original.copyWith(
          session: original.session.copyWith(
            captureGeneration: 3,
            generation: 4,
            width: 200,
            height: 100,
            qualityRebuildOutcome: .applied,
          ),
          output: null,
        ),
      ).toApplicationEvent(),
    );
    await tester.pump();
    expect(presentation.qualityRebuilding, isFalse);
    expect(presentation.session!.output, replacement);
    expect(
      presentation.canSendInput(foreground: true, ownerCurrent: true),
      isTrue,
    );
    events.add(RuntimeEvent(const RecoveryFailed('连接状态核对失败。')));
    await tester.pump();
    expect(presentation.stateUnverified, isTrue);
    expect(presentation.error, '连接状态核对失败。');
    expect(presentation.session!.output, replacement);
    expect(
      presentation.canSendInput(foreground: true, ownerCurrent: true),
      isFalse,
    );
    expect(videos.starts, 1);
    expect(videos.stops, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    views.dispose();
    container.dispose();
    await events.close();
    expect(videos.stops, ['session']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制页能力换源不重放打开，迟到启动只由原能力清理', (tester) async {
    final original = _Videos();
    final replacement = _Videos();
    final events = StreamController<RuntimeEvent>.broadcast(sync: true);
    final dependencies = _Session();
    final control = _Control();
    final inspection = _Inspection();
    final apps = _Apps();
    final displays = _Displays();
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceReaderProvider.overrideWithValue(dependencies.devices),
        settingsManagementProvider.overrideWithValue(dependencies.settings),
        runtimeEventsProvider.overrideWithValue(events.stream),
        videoSessionsProvider.overrideWithValue(original),
        remoteControlProvider.overrideWithValue(control),
        deviceInspectionProvider.overrideWithValue(inspection),
        deviceAppsProvider.overrideWithValue(apps),
        videoDisplayProvider.overrideWithValue(displays),
      ],
    );
    final views = RemoteViews(
      videos: original,
      audio: _Audio(),
      events: events.stream,
      current: () => true,
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: RemoteViewsScope(
            views: views,
            child: const ControlPage(device: _device),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(original.starts, 1);
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      deviceReaderProvider.overrideWithValue(dependencies.devices),
      settingsManagementProvider.overrideWithValue(dependencies.settings),
      runtimeEventsProvider.overrideWithValue(events.stream),
      videoSessionsProvider.overrideWithValue(replacement),
      remoteControlProvider.overrideWithValue(control),
      deviceInspectionProvider.overrideWithValue(inspection),
      deviceAppsProvider.overrideWithValue(apps),
      videoDisplayProvider.overrideWithValue(displays),
    ]);
    await tester.pump();
    expect(find.text('画面来源已变化，请关闭本页后重新打开。'), findsOneWidget);
    original.starting.complete(
      const VideoSessionView(
        session: VideoSessionSnapshot(
          sessionId: 'late-session',
          deviceId: 'device',
          name: 'Phone',
          kind: .screen,
          status: .streaming,
        ),
        wake: KeepAwakeSnapshot(deviceId: 'device'),
      ),
    );
    await tester.pump();
    expect(original.stops, ['late-session']);
    expect(replacement.starts, 0);
    expect(replacement.reads, 0);
    expect(replacement.stops, isEmpty);
    events.add(
      RuntimeEvent(
        RecoveryCompleted(
          RuntimeSnapshot(sequence: 1, settings: Preferences()),
        ),
      ),
    );
    await tester.pump();
    expect(replacement.starts, 0);
    await tester.pumpWidget(const SizedBox());
    views.dispose();
    container.dispose();
    await events.close();
    expect(tester.takeException(), isNull);
  });
}

const _device = DeviceSnapshot(
  id: 'device',
  name: 'Phone',
  status: .connected,
  connectionId: 'connection',
);

VideoOutputReceipt _output() => const VideoOutputReceipt(
  sessionId: 'session',
  deviceId: 'device',
  relayId: 'relay',
  textureId: 3,
  decodedWidth: 100,
  decodedHeight: 200,
  codec: 'h264',
  generation: 3,
  captureGeneration: 2,
  paused: false,
  decodedReceipts: 1,
  snapshotReceipts: 1,
);

class _Session implements AppSession {
  @override
  final initialState = AppState(
    devices: [_device],
    loading: false,
    settings: Preferences(
      deviceSettings: {'device': const DevicePreferences(wakeOnConnect: false)},
    ),
  );
  final DeviceReader devices = _Devices();
  final SettingsManagement settings = _Settings();
  @override
  Stream<RuntimeEvent> get events => const Stream.empty();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Videos implements VideoSessions {
  final starting = Completer<VideoSessionView>();
  final stops = <String>[];
  final pauses = <String>[];
  final resumes = <String>[];
  int starts = 0, reads = 0;
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) async {
    reads++;
    return [];
  }

  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) {
    starts++;
    return starting.future;
  }

  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) async {
    stops.add(target.sessionId!);
    return VideoStopReceipt(sessionId: target.sessionId!);
  }

  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) async {
    pauses.add(target.sessionId!);
    return _playback(target.sessionId!, .paused);
  }

  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) async {
    resumes.add(target.sessionId!);
    return _playback(target.sessionId!, .streaming);
  }

  VideoPlaybackReceipt _playback(String id, VideoSessionStatus status) =>
      VideoPlaybackReceipt(
        session: VideoSessionSnapshot(
          sessionId: id,
          deviceId: 'device',
          name: 'Phone',
          kind: .screen,
          status: status,
          captureGeneration: 2,
          generation: 3,
        ),
        output: _output().copyWith(paused: status == .paused),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Inspection implements DeviceInspection {
  @override
  Future<DeviceReading<DeviceScreenState>> readScreenState(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) async => throw StateError('screen state unavailable');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Control implements RemoteControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Apps implements DeviceApps {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Displays implements VideoDisplayControl {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices implements DeviceReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
