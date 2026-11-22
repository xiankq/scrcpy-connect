import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/app_startup.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/widgets/content.dart';

void main() {
  testWidgets('first frame shows real navigation and keeps the selected tab', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preparation = Completer<AppBootstrap>();
    final glass = Completer<void>();
    await tester.pumpWidget(
      AppStartup(
        initialLocation: '/devices',
        loadSession: () => preparation.future,
        initializeGlass: () => glass.future,
      ),
    );

    final navigation = find.byKey(const ValueKey('app-bottom-navigation'));
    final initialNavigation = tester.element(navigation);
    expect(find.text('设备'), findsWidgets);
    expect(find.text('正在启动邻接'), findsNothing);
    expect(find.text('添加第一台设备'), findsNothing);
    expect(find.byType(ContentLoadingIndicator), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('设置')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('设置'), findsWidgets);
    expect(find.text('使用偏好'), findsNothing);

    preparation.complete(_Session());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('使用偏好'), findsOneWidget);
    expect(find.text('关于与更新'), findsOneWidget);
    expect(tester.element(navigation), same(initialNavigation));

    glass.completeError(StateError('shader unavailable'));
    await tester.pump();
    expect(find.text('使用偏好'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session error and retry stay inside the current page', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final retry = Completer<AppBootstrap>();
    var attempts = 0;
    await tester.pumpWidget(
      AppStartup(
        initialLocation: '/devices',
        loadSession: () {
          attempts++;
          return attempts == 1
              ? Future.error(StateError('device records unavailable'))
              : retry.future;
        },
        initializeGlass: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取应用数据。请重试。'), findsOneWidget);
    final navigation = find.byKey(const ValueKey('app-bottom-navigation'));
    final initialNavigation = tester.element(navigation);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('暂时无法读取应用数据。请重试。'), findsNothing);
    expect(find.byType(ContentLoadingIndicator), findsOneWidget);
    retry.complete(_Session());
    await tester.pumpAndSettle();
    expect(find.text('添加第一台设备'), findsOneWidget);
    expect(tester.element(navigation), same(initialNavigation));
    expect(tester.takeException(), isNull);
  });
}

class _Session implements AppBootstrap {
  @override
  List<Override> get overrides {
    final source = _Capabilities();
    return [
      appSessionProvider.overrideWithValue(
        AppSession(initialize: false, initialState: AppState(loading: false)),
      ),
      deviceReaderProvider.overrideWithValue(source),
      settingsManagementProvider.overrideWithValue(source),
      videoSessionsProvider.overrideWithValue(source),
      remoteAudioProvider.overrideWithValue(source),
      incomingSharesProvider.overrideWithValue(source),
      remoteClipboardProvider.overrideWithValue(source),
      backgroundControlProvider.overrideWithValue(source),
      appInfoReaderProvider.overrideWithValue(
        () async => const AppInfo(
          appName: '邻接',
          packageName: 'test',
          version: '0.1.0',
          buildNumber: '1',
        ),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Capabilities
    implements
        DeviceReader,
        SettingsManagement,
        VideoSessions,
        RemoteAudio,
        IncomingShares,
        RemoteClipboard,
        BackgroundControl {
  @override
  Future<BackgroundStatus> readBackgroundStatus() async =>
      const BackgroundStatus();

  @override
  void Function() bindClipboardAdmission(
    bool Function(String deviceId, String sessionId, int generation) check,
  ) => () {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
