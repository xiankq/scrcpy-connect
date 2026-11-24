import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('从全部应用打开的独立会话可以返回所属设备工作台', (tester) async {
    const target = (deviceId: 'phone', packageName: 'com.example.settings');
    final workspace = WorkspaceRoute(deviceId: target.deviceId).location;
    final router = GoRouter(
      initialLocation: '/apps',
      routes: [
        GoRoute(
          path: '/apps',
          builder: (_, _) => const Scaffold(body: Text('全部应用')),
        ),
        GoRoute(
          path: workspace,
          builder: (_, _) => const Scaffold(body: Text('设备工作台')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceAppIconProvider((
            deviceId: target.deviceId,
            packageName: target.packageName,
            userId: null,
          )).overrideWith((_) async => throw StateError('图标暂不可用')),
        ],
        child: MaterialApp.router(
          theme: ConnectTokens.theme(Brightness.light),
          routerConfig: router,
          builder: (context, child) =>
              RemoteWindows(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final windows = RemoteWindows.maybeOf(tester.element(find.text('全部应用')))!;
    windows.open(
      target,
      (observer) => GoRouter(
        observers: [observer],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('独立应用画面')),
          ),
        ],
      ),
      workbenchLocation: workspace,
      appName: '设置',
    );
    await tester.pumpAndSettle();

    final show = windows.showSwitcher(tester.element(find.text('独立应用画面')));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneAppIcon), findsOneWidget);
    expect(find.byTooltip('关闭窗口'), findsNothing);
    await tester.tap(find.text('返回工作台'));
    await tester.pumpAndSettle();
    await show;

    expect(find.text('设备工作台'), findsOneWidget);
    expect(find.text('全部应用'), findsNothing);
    expect(windows.windowFor(target), isNotNull);
  });
}
