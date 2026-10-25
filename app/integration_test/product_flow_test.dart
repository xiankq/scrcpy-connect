import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/details/data/devices_details_data_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_summary.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/connection/connection_validation.dart';

import 'dart:ui' as ui;

import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/details/diagnostics/devices_details_diagnostics_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/widgets/file_breadcrumbs.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
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
  const transport = String.fromEnvironment(
    'CONNECT_E2E_TRANSPORT',
    defaultValue: 'tls',
  );
  const minimumVideoEdge = int.fromEnvironment('CONNECT_E2E_MIN_VIDEO_EDGE');
  const requireShaderGlass = bool.fromEnvironment(
    'CONNECT_E2E_REQUIRE_SHADER_GLASS',
  );
  const requestedVideoEdge = int.fromEnvironment(
    'CONNECT_E2E_VIDEO_MAX_SIZE',
    defaultValue: 1280,
  );
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
    expect(
      transport,
      isIn(['tls', 'tcp']),
      reason: 'Select the real target transport explicitly; the port does not identify its security type.',
    );
    final originalHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    final semantics = tester.ensureSemantics();
    var converted = false;
    Future<void> capture(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot(name);
    }

    try {
      await app.main();
      await waitFor(
        tester,
        () => find.byTooltip('添加设备').evaluate().isNotEmpty,
        reason: 'The actual application must finish initialization.',
      );
      await tester.tap(find.byTooltip('添加设备'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('IP连接'));
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () => find.byType(ConnectionFormPage).evaluate().isNotEmpty,
        reason: 'The actual connection form must finish its route loading.',
      );
      if (transport == 'tls') {
        // 测试提供已授权的加密端点；新 IP 页签本身不能根据端口猜测加密。
        const ConnectionFormRoute(transport: ConnectionTransport.tls)
            .pushReplacement(tester.element(find.byType(ConnectionFormPage)));
        await tester.pumpAndSettle();
      }
      await waitFor(
        tester,
        () =>
            ModalRoute.of(tester.element(find.byType(ConnectionFormPage)))
                ?.animation
                ?.status ==
            AnimationStatus.completed,
        reason: 'The connection route must settle before attaching text input.',
      );
      await tester.enterText(find.byType(TextFormField).at(0), address);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller
            ?.text,
        address,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '65536');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller
            ?.text,
        address,
        reason: 'Editing the port must retain the entered target address.',
      );
      await tapPageAction(
        tester,
        find.byType(ConnectionFormPage),
        find.text('连接设备'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), port);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller
            ?.text,
        address,
        reason: 'Correcting an invalid port must retain the target address.',
      );
      await tapPageAction(
        tester,
        find.byType(ConnectionFormPage),
        find.text('连接设备'),
      );
      await waitFor(
        tester,
        () => find.text('打开手机屏幕').evaluate().isNotEmpty,
        reason: 'A real authorized target must establish a connection.',
      );
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find.text('文件管理'),
      );
      await waitFor(
        tester,
        () =>
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget is FileBreadcrumbs && widget.path == '/sdcard',
                )
                .evaluate()
                .isNotEmpty &&
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
      // 沿真实导航与 JSON 投影操作，不直接经桥接调用诊断或画质修改。
      await waitFor(
        tester,
        () => find
            .descendant(
              of: find.byType(DeviceWorkspacePage),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isEmpty,
        reason: 'Device information must finish before scrolling diagnostics.',
      );
      expect(find.text('Android 版本'), findsNothing);
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find
            .ancestor(
              of: find.byType(DeviceSummary),
              matching: find.byType(InkWell),
            )
            .first,
        delta: -250,
      );
      await waitFor(
        tester,
        () =>
            find.byType(DeviceDataPage).evaluate().isNotEmpty &&
            find.text('设备型号').evaluate().isNotEmpty,
        reason: 'The summary opens actual read-only target facts.',
      );
      expect(find.text('ADB 私钥'), findsNothing);
      expect(find.text('编辑地址与端口'), findsNothing);
      final originalStamp = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .firstWhere((text) => text.startsWith('更新于'));
      await capture('real-device-data');
      // 目标观察按整秒记录；跨过此边界后只刷新一次，避免同一秒内同样新鲜的响应被拒绝。
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('刷新'));
      await waitFor(
        tester,
        () => tester
            .widgetList<Text>(find.byType(Text))
            .any(
              (text) =>
                  (text.data ?? '').startsWith('更新于') &&
                  text.data != originalStamp,
            ),
        reason: 'Refreshing facts must complete a new target observation.',
      );
      binding.reportData!['deviceDataRefreshVerified'] = true;
      await tester.pageBack();
      await waitFor(
        tester,
        () => find.byType(DeviceDataPage).evaluate().isEmpty,
        reason: 'Device data returns to the same workspace.',
      );
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find.text('连接诊断'),
      );
      await waitFor(
        tester,
        () => find.text('设备连接正常').evaluate().isNotEmpty,
        reason: 'Actual Rust diagnostic results must appear in the page.',
      );
      expect(find.text('网络地址可达'), findsOneWidget);
      expect(find.text('本机授权身份已就绪'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('real-diagnostics');
      await tester.pageBack();
      await waitFor(
        tester,
        () => find.byType(DiagnosticsPage).evaluate().isEmpty,
        reason: 'Diagnostics must return to the same device workspace.',
      );
      await tapPageAction(
        tester,
        find.byType(DeviceWorkspacePage),
        find.text('画面设置'),
      );
      await waitFor(
        tester,
        () => find.byType(QualityPage).evaluate().isNotEmpty,
        reason: 'Device screen settings own the shared quality.',
      );
      await waitFor(
        tester,
        () => find.text('编码格式').evaluate().isNotEmpty,
        reason: 'The actual quality options must load.',
      );
      await tapPageAction(tester, find.byType(QualityPage), find.text('编码格式'));
      await tester.pump(const Duration(milliseconds: 400));
      final hevc = find.widgetWithText(ListTile, 'h265');
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
            find.widgetWithText(ListTile, 'h265').evaluate().isNotEmpty &&
            find.text('编码格式').evaluate().isNotEmpty &&
            find.byType(BottomSheet).evaluate().isEmpty,
        reason: 'The real screen settings page must persist device-wide H.265.',
      );
      if (minimumVideoEdge > 0) {
        await tapPageAction(
          tester,
          find.byType(QualityPage),
          find.text('分辨率上限'),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithText(ListTile, '$requestedVideoEdge'),
          ),
        );
        await waitFor(
          tester,
          () =>
              find.byType(BottomSheet).evaluate().isEmpty &&
              find.text('$requestedVideoEdge px').evaluate().isNotEmpty,
          reason:
              'Resolution acceptance must request $requestedVideoEdge through the product page.',
        );
      }
      await tester.pageBack();
      await waitFor(
        tester,
        () => find.byType(QualityPage).evaluate().isEmpty,
        reason: 'Screen settings return to the same device workspace.',
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
      binding.reportData!['shaderImageFiltersSupported'] =
          ui.ImageFilter.isShaderFilterSupported;
      if (requireShaderGlass) {
        expect(
          ui.ImageFilter.isShaderFilterSupported,
          isTrue,
          reason: 'This visual run requires the real backdrop shader backend.',
        );
      }
      final viewport = tester.getRect(
        find
            .ancestor(of: find.byType(Texture), matching: find.byType(Listener))
            .first,
      );
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
      for (final tooltip in ['返回', '主屏幕', '最近任务']) {
        final button = find.descendant(
          of: remote,
          matching: find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == tooltip,
          ),
        );
        expect(button, findsOneWidget);
        await waitFor(
          tester,
          () => tester.widget<IconButton>(button).onPressed != null,
          reason:
              'The decoded picture must establish input authority before $tooltip.',
        );
      }
      binding.reportData!['defaultNavigationButtonsPresent'] = true;
      await binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        remote,
        findsOneWidget,
        reason: 'System Back must control the target while retaining the remote route.',
      );
      expectHealthyRemote();
      final exitRect = tester.getRect(
        find.descendant(
          of: find.byType(ExitHandle),
          matching: find.byType(GestureDetector),
        ),
      );
      final letterbox = [
        if (surface.left - viewport.left > 2)
          Offset((viewport.left + surface.left) / 2, viewport.center.dy),
        if (viewport.right - surface.right > 2)
          Offset((surface.right + viewport.right) / 2, viewport.center.dy),
        if (surface.top - viewport.top > 2)
          Offset(viewport.center.dx, (viewport.top + surface.top) / 2),
        if (viewport.bottom - surface.bottom > 2)
          Offset(viewport.center.dx, (surface.bottom + viewport.bottom) / 2),
      ].where((point) => !exitRect.contains(point)).firstOrNull;
      expect(
        letterbox,
        isNotNull,
        reason:
            'This fixture must expose a real letterbox area outside the video.',
      );
      await tester.tapAt(letterbox!);
      await tester.pump(const Duration(milliseconds: 500));
      expect(remote, findsOneWidget);
      expectHealthyRemote();
      final sessions = objects(
        (await controller.request('session.list'))['sessions'],
      );
      final session = sessions.singleWhere(
        (item) => item['status'] == 'streaming',
      );
      expect(session['codec'], 'h265');
      expect(session['firstFrameDecoded'], isTrue);
      expect(session['evidence'], 'media_codec.decodedFrame');
      expect(session['capturePaused'], isNot(true));
      binding.reportData!['systemBackRetainsStreamingRemote'] = true;
      binding.reportData!['letterboxTapRetainsStreamingRemote'] = true;
      binding.reportData!['letterboxTap'] = {
        'x': letterbox.dx,
        'y': letterbox.dy,
      };
      await binding.takeScreenshot('remote-after-system-back-and-letterbox');
      binding.reportData!['pageSelectedCodec'] = session['codec'];
      binding.reportData!['actualStreamWidth'] = session['width'];
      binding.reportData!['actualStreamHeight'] = session['height'];
      binding.reportData!['requestedQuality'] = session['quality'];
      binding.reportData!['minimumVideoEdge'] = minimumVideoEdge;
      binding.reportData!['decodedWidth'] = session['decodedWidth'];
      binding.reportData!['decodedHeight'] = session['decodedHeight'];
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('remote-live');
      if (minimumVideoEdge > 0) {
        expect(jsonObject(session['quality'])['maxSize'], requestedVideoEdge);
        final width = session['width'] as int;
        final height = session['height'] as int;
        expect(
          width > height ? width : height,
          greaterThanOrEqualTo(minimumVideoEdge),
          reason: 'Real encoded pixels must meet the explicitly requested acceptance resolution.',
        );
        final decodedWidth = session['decodedWidth'] as int;
        final decodedHeight = session['decodedHeight'] as int;
        expect(
          decodedWidth > decodedHeight ? decodedWidth : decodedHeight,
          greaterThanOrEqualTo(minimumVideoEdge),
          reason:
              'An encoded-size receipt alone does not prove decoded quality.',
        );
      }
      final handle = find.byKey(const ValueKey('remote-tool-handle'));
      await tester.drag(
        handle,
        Offset(viewport.width * .72, viewport.height * .5),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      final collapsed = find.bySemanticsLabel(RegExp('展开画面工具，'));
      expect(collapsed, findsOneWidget);
      await binding.takeScreenshot('remote-handle-collapsed');
      expectHealthyRemote();
      final collapsedRect = tester.getRect(collapsed);
      await tester.tap(collapsed);
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('remote-handle-expanded');
      expectHealthyRemote();
      final expanded = find.bySemanticsLabel(RegExp('收起画面工具，'));
      expect(
        expanded,
        findsOneWidget,
        reason:
            'Tap must expand the collapsed control at $collapsedRect; current hit area is ${tester.getRect(handle)}.',
      );
      await tester.drag(handle, const Offset(100, 20));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(collapsed, findsOneWidget);
      await tester.drag(collapsed, const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(collapsed, findsNothing);
      expect(
        expanded,
        findsOneWidget,
        reason: 'Dragging inward must leave the exit button available.',
      );
      final inward = tester.getRect(expanded);
      expect(inward.right, lessThan(viewport.width - 24));
      await binding.takeScreenshot('remote-handle-inward-expanded');
      binding.reportData!['inwardExitHandleExpanded'] = true;
      expectHealthyRemote();
      await tester.ensureVisible(find.text('关闭画面'));
      await tester.tap(find.text('关闭画面'));
      await waitFor(
        tester,
        () => find.byType(RemotePage).evaluate().isEmpty,
        reason: 'Close must release the window and return to the workspace.',
      );
      expect(find.text('打开手机屏幕'), findsOneWidget);
      final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
      List<Json> remaining;
      do {
        remaining =
            objects((await controller.request('session.list'))['sessions'])
                .where(
                  (item) =>
                      item['sessionId'] == session['sessionId'] &&
                      item['status'] != 'stopped',
                )
                .toList();
        if (remaining.isEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      } while (DateTime.now().isBefore(closeDeadline));
      expect(remaining, isEmpty);
      binding.reportData!['exitReleasesWindow'] = true;
      final remoteDeviceId = value(session, 'deviceId');
      expect(remoteDeviceId, isNotEmpty);
      List<Json> activeAudio = [];
      final audioDeadline = DateTime.now().add(const Duration(seconds: 5));
      do {
        activeAudio =
            objects((await controller.request('audio.sources'))['sources'])
                .where(
                  (source) =>
                      source['deviceId'] == remoteDeviceId &&
                      ['playing', 'starting'].contains(source['status']),
                )
                .toList();
        if (activeAudio.isEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      } while (DateTime.now().isBefore(audioDeadline));
      expect(
        activeAudio,
        isEmpty,
        reason: 'Closing the final picture must release its device audio.',
      );
      binding.reportData!['closedRemoteStopsDeviceAudio'] = true;
      await tester.pump(const Duration(milliseconds: 500));
      await binding.takeScreenshot('workspace-after-remote');
      expect(tester.takeException(), isNull);
    } catch (error) {
      binding.reportData!['failure'] = '$error';
      binding.reportData!['lifecycle'] = binding.lifecycleState?.name;
      if (find.byType(ConnectApp).evaluate().isNotEmpty) {
        final controller = ProviderScope.containerOf(
          tester.element(find.byType(ConnectApp)),
        ).read(appControllerProvider.notifier);
        try {
          binding.reportData!['failureSessions'] = await controller
              .request('session.list')
              .timeout(const Duration(seconds: 5));
        } catch (stateError) {
          binding.reportData!['failureStateError'] = '$stateError';
        }
      }
      binding.reportData!['failureTexts'] = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .take(100)
          .toList();
      try {
        await capture('product-flow-failed');
      } catch (captureError) {
        binding.reportData!['failureCaptureError'] = '$captureError';
      }
      rethrow;
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = originalHitTestPolicy;
      semantics.dispose();
    }
    binding.reportData!['productAcceptanceComplete'] = true;
  });
}
