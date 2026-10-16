import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/main.dart' as app;

import 'flows.dart';

void expectHealthyRemote() {
  final remote = find.byType(RemotePage);
  expect(
    find.descendant(of: remote, matching: find.text('画面已暂停')),
    findsNothing,
  );
  expect(
    find.descendant(of: remote, matching: find.text('暂时无法打开实时画面')),
    findsNothing,
  );
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 35),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  testWidgets('real connection, files and full screen remote control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await app.main();
      await waitFor(
        tester,
        () => find.byTooltip('添加设备').evaluate().isNotEmpty,
        reason: 'The actual application must finish initialization.',
      );
      await tester.tap(find.byTooltip('添加设备'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('手动填写地址'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        address.isEmpty ? '192.0.2.1' : address,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '65536');
      await tester.ensureVisible(find.text('连接设备'));
      await tester.tap(find.text('连接设备'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
      if (address.isEmpty || port.isEmpty) return;
      await tester.enterText(find.byType(TextFormField).at(1), port);
      await tester.ensureVisible(find.text('连接设备'));
      await tester.tap(find.text('连接设备'));
      await waitFor(
        tester,
        () => find.text('打开手机屏幕').evaluate().isNotEmpty,
        reason: 'A real authorized target must establish a connection.',
      );
      await tester.ensureVisible(find.text('文件管理'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('文件管理'));
      await waitFor(
        tester,
        () =>
            find.text('/sdcard').evaluate().isNotEmpty &&
            find
                .descendant(
                  of: find.byType(FilesPage),
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty,
        reason: 'The actual file directory must load.',
      );
      expect(find.text('无法读取这个目录'), findsNothing);
      await returnFromFiles(tester);
      await tester.tap(find.text('打开手机屏幕'));
      await waitFor(
        tester,
        () => find.byType(Texture).evaluate().isNotEmpty,
        reason: 'Remote control must receive an actual native texture and first frame.',
      );
      final remote = find.byType(RemotePage);
      expect(remote, findsOneWidget);
      expect(
        find.descendant(of: remote, matching: find.byType(AppBar)),
        findsNothing,
      );
      expect(
        find.descendant(of: remote, matching: find.byType(Card)),
        findsNothing,
      );
      final surface = tester.getRect(find.byType(Texture));
      final viewport = tester.getRect(remote);
      expect(surface.width, lessThanOrEqualTo(viewport.width));
      expect(surface.height, lessThanOrEqualTo(viewport.height));
      expect(
        (surface.width - viewport.width).abs() < 2 ||
            (surface.height - viewport.height).abs() < 2,
        isTrue,
        reason: 'The source must fill one viewport axis without a phone frame.',
      );
      await tester.tapAt(surface.center);
      await tester.pump(const Duration(milliseconds: 500));
      expectHealthyRemote();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('remote-live');
      final handle = find.descendant(
        of: find.byType(ExitHandle),
        matching: find.byType(GestureDetector),
      );
      await tester.drag(handle, Offset(viewport.width * .72, 100));
      await tester.pump(const Duration(milliseconds: 1200));
      final collapsed = find.bySemanticsLabel(RegExp('展开退出按钮，'));
      expect(collapsed, findsOneWidget);
      await binding.takeScreenshot('remote-handle-collapsed');
      expectHealthyRemote();
      final collapsedRect = tester.getRect(collapsed);
      await tester.tap(collapsed);
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('remote-handle-expanded');
      expectHealthyRemote();
      final expanded = find.bySemanticsLabel(RegExp('退出控制，返回'));
      expect(
        expanded,
        findsOneWidget,
        reason:
            'Tap must expand the collapsed control at $collapsedRect; current hit area is ${tester.getRect(handle)}.',
      );
      await tester.tap(expanded);
      await waitFor(
        tester,
        () => find.byType(RemotePage).evaluate().isEmpty,
        reason:
            'Explicit exit must stop the session and return to the workspace.',
      );
      expect(find.text('打开手机屏幕'), findsOneWidget);
      await binding.takeScreenshot('workspace-after-remote');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
