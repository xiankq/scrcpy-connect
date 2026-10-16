import 'package:scrcpy_connect/pages/device_workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/device_details/device_details_page.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/diagnostics/diagnostics_page.dart';
import 'package:scrcpy_connect/pages/quality/quality_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
    find.descendant(of: remote, matching: find.byType(SnackBar)),
    findsNothing,
    reason: 'Feedback from another page must not cover the remote device.',
  );
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

Future<void> tapPageAction(
  WidgetTester tester,
  Finder page,
  Finder action, {
  double delta = 250,
}) async {
  final route = ModalRoute.of(tester.element(page));
  await waitFor(
    tester,
    () => route?.animation?.status == AnimationStatus.completed,
    timeout: const Duration(seconds: 5),
    reason: 'Wait for the actual page transition before scrolling.',
  );
  await tester.scrollUntilVisible(
    action,
    delta,
    scrollable: find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 12,
  );
  await Scrollable.ensureVisible(tester.element(action), alignment: .5);
  await tester.pump(const Duration(milliseconds: 300));
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action.hitTestable());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('CONNECT_E2E_ADDRESS');
  const port = String.fromEnvironment('CONNECT_E2E_PORT');
  binding.reportData = {
    ...?binding.reportData,
    'productAcceptanceComplete': false,
  };
  testWidgets('real connection, files and full screen remote control', (
    tester,
  ) async {
    expect(
      address.trim(),
      isNotEmpty,
      reason: 'Set CONNECT_E2E_ADDRESS to a real authorized target; this test requires the full product flow.',
    );
    expect(
      int.tryParse(port),
      inInclusiveRange(1, 65535),
      reason:
          'Set CONNECT_E2E_PORT to the real target connection port (1–65535).',
    );
    final originalHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
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
      await tester.enterText(find.byType(TextFormField).at(0), address);
      await tester.enterText(find.byType(TextFormField).at(1), '65536');
      await tester.ensureVisible(find.text('连接设备'));
      await tester.tap(find.text('连接设备'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
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
      // Follow the real navigation and JSON projection, rather than invoking
      // diagnose or quality mutations directly through the bridge.
      await tester.tap(find.byTooltip('设备详情'));
      await waitFor(
        tester,
        () =>
            find.text('Android 版本').evaluate().isNotEmpty &&
            find
                .descendant(
                  of: find.byType(DeviceDetailsPage),
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty,
        reason: 'Device information must finish before scrolling diagnostics.',
      );
      await tapPageAction(
        tester,
        find.byType(DeviceDetailsPage),
        find.text('连接诊断'),
      );
      await waitFor(
        tester,
        () => find.text('设备连接正常').evaluate().isNotEmpty,
        reason: 'Actual Rust diagnostic results must appear in the page.',
      );
      expect(find.text('网络地址可达'), findsOneWidget);
      expect(find.text('本机授权身份已就绪'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('real-diagnostics');
      await tester.pageBack();
      await waitFor(
        tester,
        () => find.byType(DiagnosticsPage).evaluate().isEmpty,
        reason: 'Diagnostics must return to the same device details.',
      );
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find.text('画质与声音'),
      );
      await waitFor(
        tester,
        () => find.text('编码格式').evaluate().isNotEmpty,
        reason: 'The actual quality options must load.',
      );
      await tester.ensureVisible(find.text('编码格式'));
      await tester.tap(find.text('编码格式'));
      await tester.pump(const Duration(milliseconds: 400));
      final hevc = find.widgetWithText(ListTile, 'H.265');
      expect(hevc, findsOneWidget);
      expect(
        tester.widget<ListTile>(hevc).enabled,
        isTrue,
        reason:
            'A never-decoded runtime candidate must allow its first attempt.',
      );
      await binding.takeScreenshot('first-codec-selection');
      await tester.tap(hevc);
      await waitFor(
        tester,
        () =>
            find.widgetWithText(ListTile, 'H.265').evaluate().isNotEmpty &&
            find.text('编码格式').evaluate().isNotEmpty &&
            find.byType(BottomSheet).evaluate().isEmpty,
        reason:
            'The real quality page must persist H.265 for the next session.',
      );
      await tester.pageBack();
      await waitFor(
        tester,
        () => find.byType(QualityPage).evaluate().isEmpty,
        reason: 'Quality must return to the device workspace.',
      );
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find.text('打开手机屏幕'),
        delta: -250,
      );
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
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      final sessions = objects(
        (await controller.request('session.list'))['sessions'],
      );
      final session = sessions.singleWhere(
        (item) => item['status'] == 'streaming',
      );
      expect(session['codec'], 'h265');
      expect(session['firstFrameDecoded'], isTrue);
      expect(session['evidence'], 'mdk.snapshot');
      binding.reportData!['pageSelectedCodec'] = session['codec'];
      binding.reportData!['actualStreamWidth'] = session['width'];
      binding.reportData!['actualStreamHeight'] = session['height'];
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
      WidgetController.hitTestWarningShouldBeFatal = originalHitTestPolicy;
      semantics.dispose();
    }
    binding.reportData!['productAcceptanceComplete'] = true;
  });
}
