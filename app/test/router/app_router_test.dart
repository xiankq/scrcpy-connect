import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('系统恢复保留页面位置与返回链，切换主页保留运行中的状态', (tester) async {
    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(_Devices.new),
          recoveryStateProvider.overrideWith(_Recovery.new),
          preferencesProvider.overrideWith(_Preferences.new),
          runtimeEventsProvider.overrideWithValue(const Stream.empty()),
          appSnapshotProvider.overrideWithValue(AppState(loading: false)),
          settingsManagementProvider.overrideWithValue(_Settings()),
          backgroundControlProvider.overrideWithValue(_Background()),
          appInfoReaderProvider.overrideWithValue(
            () async => throw StateError('unused'),
          ),
        ],
        child: MaterialApp.router(
          restorationScopeId: 'route-test',
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await _settle(tester);
    final data = await tester.getRestorationData();
    await tester.restoreFrom(data);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('AVD'), findsOneWidget);
    tester.widget<TextField>(find.byType(TextField)).controller!.text = '测试';
    await tester.pump();
    router.go(const SettingsRoute().location);
    await _settle(tester);
    router.go(const DevicesRoute().location);
    await _settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '测试',
    );
    router.go(const SettingsRoute().location);
    await _settle(tester);
    await tester.restartAndRestore();
    await _settle(tester);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('使用偏好'), findsOneWidget);
    expect(find.text('本机数据'), findsOneWidget);
    expect(find.text('后台运行资格'), findsOneWidget);
    unawaited(router.push<void>(const RouteErrorRoute().location));
    await _settle(tester);
    await tester.restartAndRestore();
    await _settle(tester);
    expect(find.text('页面缺少必要的记录信息，请返回设备列表重新选择。'), findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await _settle(tester);
    expect(find.text('外观'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('迁移后的文件、相册和传输深链仍能匹配并保留查询参数', () {
    final router = createAppRouter();
    addTearDown(router.dispose);
    final search = FileSearchRoute(
      deviceId: 'device',
      path: '/sdcard/工作 文档',
      query: '报告 & 图片',
    );
    final searchMatch = router.configuration.findMatch(
      Uri.parse(search.location),
    );
    expect(searchMatch.isError, isFalse);
    expect(searchMatch.fullPath, '/devices/:deviceId/file-search');
    expect(searchMatch.pathParameters['deviceId'], 'device');
    expect(searchMatch.uri.queryParameters['path'], '/sdcard/工作 文档');
    expect(searchMatch.uri.queryParameters['query'], '报告 & 图片');
    for (final location in [
      const FilesRoute(deviceId: 'device').location,
      const GalleryRoute(deviceId: 'device').location,
      const TransferDetailsRoute(taskId: 'transfer').location,
    ]) {
      expect(
        router.configuration.findMatch(Uri.parse(location)).isError,
        isFalse,
      );
    }
  });

  test('独立控制窗口深链保留原会话身份', () {
    final router = createAppRouter();
    addTearDown(router.dispose);
    const route = RemoteSessionRoute(
      deviceId: 'device/one',
      sessionId: 'session/one',
    );
    final match = router.configuration.findMatch(Uri.parse(route.location));
    expect(match.isError, isFalse);
    expect(match.fullPath, '/devices/:deviceId/sessions/:sessionId');
    expect(match.pathParameters['deviceId'], 'device/one');
    expect(match.pathParameters['sessionId'], 'session/one');
  });

  testWidgets('控制深链及恢复不创建新画面，返回后保留原路由', (tester) async {
    final resources = _Resources();
    const initial = RouteErrorRoute(reason: 'missing-session');
    final router = createAppRouter(initialLocation: initial.location);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryStateProvider.overrideWith(_Recovery.new),
          routeResourceResolverProvider.overrideWithValue(resources),
        ],
        child: MaterialApp.router(
          restorationScopeId: 'route-test',
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await _settle(tester);
    final pushed = router.push<void>(
      const RemoteRoute(deviceId: 'device').location,
    );
    await _settle(tester);
    const message = '请从设备工作台明确打开画面。恢复这个位置不会自动创建新的控制会话。';
    expect(find.text(message), findsOneWidget);
    expect(find.byType(ControlPage), findsNothing);
    expect(resources.reads, 1);
    router.pop();
    await _settle(tester);
    await pushed;
    expect(
      router.routeInformationProvider.value.uri.toString(),
      initial.location,
    );
    unawaited(
      router.push<void>(const RemoteRoute(deviceId: 'device').location),
    );
    await _settle(tester);
    await tester.restartAndRestore();
    await _settle(tester);
    expect(find.text(message), findsOneWidget);
    expect(find.byType(ControlPage), findsNothing);
    expect(router.canPop(), isTrue);
    router.pop();
    await _settle(tester);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      initial.location,
    );
    expect(find.text('无法识别这个控制会话。请从设备工作台重新选择；不会自动创建新画面。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

class _Resources implements RouteResourceResolver {
  int reads = 0;
  @override
  Future<DeviceSnapshot> device(String id) async {
    reads++;
    return DeviceSnapshot(id: id, name: 'test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

class _Devices extends DeviceListNotifier {
  @override
  DeviceListState build() => DeviceListState(
    loading: false,
    devices: const [DeviceSnapshot(id: 'avd', name: 'AVD')],
  );
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() => PreferencesState();
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Background implements BackgroundControl {
  @override
  Future<BackgroundStatus> readBackgroundStatus() async =>
      const BackgroundStatus();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
