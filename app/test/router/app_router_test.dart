import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/control/control_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/route_resource_resolver_provider.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
