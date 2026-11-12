import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
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
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_surface.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/models/device_audio_view_snapshot.dart';
import 'package:scrcpy_connect/widgets/remote_views.dart';

void main() {
  testWidgets('控制页直接消费类型化输出及会话，丢弃旧捕获失败并等待画质双回执', (tester) async {
    final videos = _Videos();
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
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
    events.add({
      'type': 'session.updated',
      'deviceId': 'device',
      'data': original.copyWith(
        session: original.session.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: 3,
        ),
        output: null,
      ),
    });
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
    events.add({
      'type': 'session.updated',
      'deviceId': 'device',
      'data': original.copyWith(
        session: original.session.copyWith(
          captureGeneration: 3,
          generation: 4,
          width: 200,
          height: 100,
          qualityRebuildOutcome: .applied,
        ),
        output: null,
      ),
    });
    await tester.pump();
    expect(presentation.qualityRebuilding, isFalse);
    expect(presentation.session!.output, replacement);
    expect(
      presentation.canSendInput(foreground: true, ownerCurrent: true),
      isTrue,
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
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
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
    events.add({
      'type': 'state.resynced',
      'data': RuntimeSnapshot(sequence: 1, settings: Preferences()),
    });
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
  Stream<Map<String, dynamic>> get events => const Stream.empty();
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
