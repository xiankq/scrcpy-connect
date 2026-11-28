import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/pages/transfers/transfer_history_provider.dart';
import 'package:scrcpy_connect/pages/transfers/transfers_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/router/route_resource_view.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/styles/motion.dart';

import '../support/fixed_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('页面资源读取完成前显示加载，完成后显示目标页面', (tester) async {
    final resource = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteResourceView(
          identity: 'pending',
          load: () => resource.future,
          builder: (_, value) => Text(value),
        ),
      ),
    );
    final loader = find.byType(CircularProgressIndicator);
    expect(loader, findsOneWidget);

    resource.complete('目标页面');
    await tester.pumpAndSettle();
    expect(loader, findsNothing);
    expect(find.text('目标页面'), findsOneWidget);
  });

  testWidgets('系统恢复保留页面位置与返回链，切换主页保留运行中的状态', (tester) async {
    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceListProvider.overrideWith(
            () => FixedDeviceList(
              devices: const [DeviceSnapshot(id: 'avd', name: 'AVD')],
            ),
          ),
          recoveryStateProvider.overrideWith(FixedRecovery.new),
          fileTransfersProvider.overrideWithValue(_Transfers()),
          transferHistoryRowsProvider.overrideWith((_) => const AsyncData([])),
          preferencesProvider.overrideWith(FixedPreferences.new),
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
    await tester.tap(find.byKey(const ValueKey('page-search-open')));
    await _settle(tester);
    await tester.enterText(find.byType(EditableText), '测试');
    await _settle(tester);
    final devices = tester.element(find.byType(DevicesPage));
    router.go(const TransfersRoute().location);
    await tester.pump();
    // 切换途中，正在淡出的旧页不再接收输入。
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.byType(EditableText).hitTestable(), findsNothing);
    await _settle(tester);
    expect(find.byType(DevicesPage), findsNothing);
    final ongoing = find.text('暂无正在传输的任务');
    final completed = find.text('暂无已结束的传输');
    final selector = find.text('传输中');
    final stableSelector = tester.element(selector);
    await tester.tap(find.text('已结束').hitTestable());
    await tester.pump();
    await tester.pump(shortTransitionDuration ~/ 2);
    expect(tester.element(selector), same(stableSelector));
    expect(ongoing, findsOneWidget);
    expect(ongoing.hitTestable(), findsNothing);
    expect(completed, findsOneWidget);
    await _settle(tester);
    expect(ongoing, findsNothing);
    expect(completed, findsOneWidget);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    router.go(const SettingsRoute().location);
    await tester.pump();
    expect(find.byType(TransfersPage), findsNothing);
    expect(find.text('外观'), findsOneWidget);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await _settle(tester);
    router.go(const DevicesRoute().location);
    await _settle(tester);
    expect(tester.element(find.byType(DevicesPage)), same(devices));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '测试',
    );
    router.go(const SettingsRoute().location);
    await _settle(tester);
    await tester.restartAndRestore();
    await _settle(tester);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('使用偏好'), findsOneWidget);
    expect(find.text('本机数据'), findsOneWidget);
    expect(find.text('后台运行'), findsOneWidget);
    unawaited(router.push<void>(const RouteErrorRoute().location));
    await _settle(tester);
    await tester.restartAndRestore();
    await _settle(tester);
    expect(find.text('找不到这项内容。请返回设备列表重新选择。'), findsOneWidget);
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
      const FileSendRoute(
        deviceId: 'device',
        path: '/sdcard/Download',
      ).location,
      const ShareDirectoryRoute(
        deviceId: 'device',
        path: '/sdcard/Download',
      ).location,
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
          recoveryStateProvider.overrideWith(FixedRecovery.new),
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
    const message = '无法恢复手机画面。请回到设备工作台，点「打开手机屏幕」。';
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
    expect(find.text('这次打开的画面已不可用。请回到设备工作台重新打开。'), findsOneWidget);
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

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transfers implements FileTransfers {
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
