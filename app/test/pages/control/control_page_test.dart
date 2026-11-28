import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/video_session_changed.dart';
import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy/scrcpy.dart' show ScrcpyControlCompletion;
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
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/router/route_observers.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  testWidgets('整机和独立应用按设备保留，重开聚焦已有窗口，关闭只停止所属会话', (tester) async {
    final tablet = _device.copyWith(id: 'tablet', name: 'Tablet');
    final dependencies = _Session([_device, tablet]);
    final control = _Control();
    final videos = _Videos()
      ..startPlan = (plan) async {
        final id = plan.packageName ?? plan.deviceId;
        return VideoSessionView(
          session: VideoSessionSnapshot(
            sessionId: id,
            deviceId: plan.deviceId,
            name: id,
            kind: .screen,
            packageName: plan.packageName,
            status: .streaming,
            captureGeneration: 2,
            generation: 3,
            width: 100,
            height: 200,
          ),
          wake: KeepAwakeSnapshot(deviceId: plan.deviceId),
          output: _output().copyWith(sessionId: id, deviceId: plan.deviceId),
        );
      };
    final container = ProviderContainer(
      overrides: _overrides(dependencies, videos, control: control),
    );
    final views = _views(videos, const Stream.empty());
    late BuildContext workbench;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            workbench = context;
            return const Scaffold(body: RemoteWindowsButton());
          },
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RemoteViewsScope(
          views: views,
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
            builder: (context, child) =>
                RemoteWindows(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final windows = RemoteWindows.maybeOf(workbench)!;

    await openRemoteRoute(workbench, deviceId: 'device');
    await tester.pumpAndSettle();
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).device.id,
      'device',
    );
    windows.showWorkbench();
    await tester.pumpAndSettle();
    expect(videos.pauses, ['device']);
    expect(videos.stops, isEmpty);

    await openRemoteRoute(workbench, deviceId: tablet.id);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).device.id,
      tablet.id,
    );
    windows.showWorkbench();
    await tester.pumpAndSettle();
    const package = 'com.example.remote';
    await openRemoteRoute(
      workbench,
      deviceId: 'device',
      packageName: package,
      appName: '示例应用',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).packageName,
      package,
    );
    windows.showWorkbench();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RemoteWindowsButton),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('手机屏幕'), findsNWidgets(2));
    await tester.tap(find.text('示例应用'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).packageName,
      package,
    );
    expect(videos.starts, 3);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1040, 700);
    await tester.pumpAndSettle();
    final switcher = windows.showSwitcher(
      tester.element(find.byType(ControlPage)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(
          ValueKey<RemoteWindowTarget>((
            deviceId: tablet.id,
            packageName: null,
          )),
        ),
        matching: find.byTooltip('与当前画面并排'),
      ),
    );
    await tester.pumpAndSettle();
    await switcher;
    expect(find.byType(ControlPage), findsNWidgets(2));
    expect(videos.resumes, contains(tablet.id));
    final paired = find.byWidgetPredicate(
      (widget) =>
          widget is RemoteWindowScope &&
          widget.pane.target.deviceId == tablet.id,
    );
    expect(tester.widget<RemoteWindowScope>(paired).focused, isFalse);
    await tester.tapAt(const Offset(995, 30));
    await tester.pumpAndSettle();
    expect(tester.widget<RemoteWindowScope>(paired).focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(control.sent.map((call) => call.$1.sessionId), ['tablet', 'tablet']);
    control.sent.clear();
    tester.view.physicalSize = const Size(700, 700);
    await tester.pumpAndSettle();
    expect(find.byType(ControlPage), findsOneWidget);
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).device.id,
      tablet.id,
    );
    tester.view.physicalSize = const Size(1040, 700);
    await tester.pumpAndSettle();
    expect(find.byType(ControlPage), findsNWidgets(2));
    expect(videos.starts, 3);

    final pane = windows.windowFor((deviceId: 'device', packageName: package))!;
    final closed = pane.close!();
    await tester.pumpAndSettle();
    expect(await closed, isTrue);
    expect(videos.stops, [package]);
    expect(
      tester.widget<ControlPage>(find.byType(ControlPage)).device.id,
      tablet.id,
    );
    await openRemoteRoute(workbench, deviceId: 'device');
    await tester.pumpAndSettle();
    expect(videos.starts, 3);
    expect(videos.resumes, contains('device'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(control.sent.map((call) => call.$1.sessionId), ['device', 'device']);
    control.sent.clear();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(control.sent.map((call) => call.$1.sessionId), ['device', 'device']);
    expect(control.sent.map((call) => (call.$2 as ControlKey).keyCode), [4, 4]);

    await openRemoteRoute(
      workbench,
      deviceId: 'device',
      packageName: package,
      onPhoneScreen: true,
    );
    await tester.pumpAndSettle();
    expect(videos.starts, 3);
    expect(control.sent.last.$1.sessionId, 'device');
    expect(
      control.sent.last.$2,
      const ControlAction.launchApplication(package),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    views.dispose();
    router.dispose();
    container.dispose();
  });

  testWidgets('声明式路由覆盖和恢复控制页时安全转移剪贴板焦点', (tester) async {
    final videos = _Videos();
    final dependencies = _Session();
    final container = ProviderContainer(
      overrides: _overrides(dependencies, videos),
    );
    final views = _views(videos, const Stream.empty());
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    router.pop();
    await tester.pumpAndSettle();
    expect(videos.resumes, ['session']);
    expect(container.read(clipboardFocusProvider), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    expect(container.read(currentDeviceProvider), 'device');
    expect(videos.resumes, ['session']);
    expect(videos.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(container.read(clipboardFocusProvider), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(videos.resumes, ['session']);
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(videos.stops, ['session']);
    container.updateOverrides(
      _overrides(
        dependencies,
        _Videos(),
        control: container.read(remoteControlProvider),
        inspection: container.read(deviceInspectionProvider),
        apps: container.read(deviceAppsProvider),
        displays: container.read(videoDisplayProvider),
      ),
    );
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
      overrides: _overrides(dependencies, videos, events: events.stream),
    );
    final views = _views(videos, events.stream);
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
      overrides: _overrides(
        dependencies,
        original,
        events: events.stream,
        control: control,
        inspection: inspection,
        apps: apps,
        displays: displays,
      ),
    );
    final views = _views(original, events.stream);
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
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ControlPage), findsOneWidget);
    expect(original.stops, isEmpty);
    expect(control.sent, isEmpty);
    container.updateOverrides(
      _overrides(
        dependencies,
        replacement,
        events: events.stream,
        control: control,
        inspection: inspection,
        apps: apps,
        displays: displays,
      ),
    );
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

List<Override> _overrides(
  _Session session,
  VideoSessions videos, {
  Stream<RuntimeEvent> events = const Stream.empty(),
  RemoteControl? control,
  DeviceInspection? inspection,
  DeviceApps? apps,
  VideoDisplayControl? displays,
}) => [
  appSessionProvider.overrideWithValue(session),
  deviceReaderProvider.overrideWithValue(session.devices),
  settingsManagementProvider.overrideWithValue(session.settings),
  runtimeEventsProvider.overrideWithValue(events),
  videoSessionsProvider.overrideWithValue(videos),
  remoteControlProvider.overrideWithValue(control ?? _Control()),
  deviceInspectionProvider.overrideWithValue(inspection ?? _Inspection()),
  deviceAppsProvider.overrideWithValue(apps ?? _Apps()),
  videoDisplayProvider.overrideWithValue(displays ?? _Displays()),
];

RemoteViews _views(VideoSessions videos, Stream<RuntimeEvent> events) =>
    RemoteViews(
      videos: videos,
      audio: _Audio(),
      events: events,
      current: () => true,
      readSnapshot: () => const DeviceAudioViewSnapshot(
        devices: [],
        reconciliationPending: false,
      ),
      onAudioError: (_) {},
    );

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
  _Session([List<DeviceSnapshot> records = const [_device]])
    : devices = _Devices(records),
      initialState = AppState(
        devices: records,
        loading: false,
        settings: Preferences(
          deviceSettings: {
            for (final device in records)
              device.id: const DevicePreferences(wakeOnConnect: false),
          },
        ),
      );

  @override
  final AppState initialState;
  final DeviceReader devices;
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
  Future<VideoSessionView> Function(VideoSessionPlan)? startPlan;
  final _opened = <String, VideoSessionView>{};
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
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) async {
    starts++;
    final view = await (startPlan?.call(plan) ?? starting.future);
    _opened[view.sessionId] = view;
    return view;
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
        session: _opened[id]!.session.copyWith(status: status),
        output: _opened[id]!.output!.copyWith(paused: status == .paused),
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
  final sent = <(ControlTarget, ControlAction)>[];

  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) async {
    sent.add((target, action));
    return const ControlReceipt.delivered(ScrcpyControlCompletion.written);
  }
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
  _Devices(this.devices);
  final List<DeviceSnapshot> devices;

  @override
  Future<DeviceSnapshot> readDevice(String deviceId) async =>
      devices.singleWhere((device) => device.id == deviceId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
