import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/reply/devices_workspace_notifications_reply_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_state.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

// These are production widget branches under scoped bridge responses. PNGs use
// the widget-test material fallback and do not assert GPU material appearance.
void main() {
  testWidgets('capture device and guarded reply recovery branches', (
    tester,
  ) async {
    for (final font in [
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final cjk = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (cjk.existsSync()) {
      for (final family in ['Roboto', 'ConnectCaptureCJK', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(cjk.readAsBytesSync())),
            ))
            .load();
      }
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
    final output = Platform.environment['CONNECT_CAPTURE_DIR'];
    Future<void> capture(String name, GlobalKey boundary) async {
      expect(tester.takeException(), isNull, reason: name);
      if (output == null) return;
      final contract = fixtures.captureLayout(boundary);
      await tester.runAsync(() async {
        final directory = Directory(output);
        await directory.create(recursive: true);
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        await File('${directory.path}/$name.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'materialBackend': 'widget-test-fallback',
            ...contract,
          }),
        );
        image.dispose();
      });
    }

    for (final brightness in Brightness.values) {
      for (final scenario in [
        'empty',
        'search_no_results',
        'checking',
        'offline',
      ]) {
        final devices = switch (scenario) {
          'search_no_results' => [fixtures.device],
          'offline' => [
            {
              ...fixtures.device,
              'status': 'offline',
              'reason': '当前地址的连接服务没有响应。',
            },
          ],
          _ => <Json>[],
        };
        final controller = createTestController(
          fixtures.fixtureRequest,
          initialState: AppState(
            devices: devices,
            loading: scenario == 'checking',
            settings: {'appearance': brightness.name},
          ),
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: TestProviderScope(
              controller: controller,
              child: ConnectApp(key: ValueKey('$scenario-${brightness.name}')),
            ),
          ),
        );
        // The actual checking branch has an indeterminate progress animation.
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DevicesPage), findsOneWidget);
        if (scenario == 'search_no_results') {
          await tester.enterText(find.byType(TextField), '不存在的设备');
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('没有找到设备'), findsOneWidget);
          expect(find.text('清除搜索'), findsOneWidget);
        } else if (scenario == 'checking') {
          expect(find.text('正在检查设备'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
        } else if (scenario == 'offline') {
          expect(find.text('设备当前均不在线。连接后即可继续使用应用和内容。'), findsOneWidget);
          expect(find.textContaining('离线'), findsOneWidget);
        } else {
          expect(find.text('添加你的第一台设备'), findsOneWidget);
        }
        await capture('devices_$scenario-${brightness.name}', boundary);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
      }

      for (final scenario in [
        'unknown',
        'accepted',
        'submitted',
        'expired',
        'local_retained',
      ]) {
        var submissions = 0;
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'notifications.reply') {
            submissions++;
            return {
              'status': switch (scenario) {
                'accepted' => 'acceptedBySystem',
                'submitted' => 'completed',
                _ => 'unknown',
              },
            };
          }
          if (scenario == 'local_retained' && command == 'notifications.list') {
            return {
              'status': 'unavailable',
              'live': false,
              'notifications': <Json>[],
            };
          }
          return fixtures.fixtureRequest(command, params);
        });
        await controller.initialize();
        final key = AppController.notificationReplyKey(
          'fixture',
          fixtures.notification,
        );
        expect(
          controller.updateNotificationReplyDraft(key, '好的，我会提前到。'),
          isTrue,
        );
        if (scenario == 'expired') {
          controller.reconcileNotificationReplies('fixture', {
            'status': 'available',
            'live': true,
            'notifications': <Json>[],
          });
        } else {
          await controller.submitNotificationReply(key);
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: RouterTestApp(
              key: ValueKey('reply-$scenario-${brightness.name}'),
              controller: controller,
              theme: fixtures.captureTheme(brightness),
              devices: [fixtures.device],
              home: scenario == 'local_retained'
                  ? const Scaffold(body: SizedBox())
                  : NotificationReplyPage(
                      controller: controller,
                      device: fixtures.device,
                      notification: fixtures.notification,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scenario == 'local_retained') {
          NotificationReplyRoute(
            deviceId: 'fixture',
            notificationId: 'message',
          ).push<void>(tester.element(find.byType(Scaffold)));
          await tester.pumpAndSettle();
          expect(find.text('本机保留的回复'), findsOneWidget);
        }
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.readOnly, isTrue);
        expect(input.maxLength, 16384);
        expect(input.controller!.text, '好的，我会提前到。');
        expect(find.text('发送回复'), findsNothing);
        expect(find.text('到手机上核对'), findsOneWidget);
        expect(find.text('复制保留内容'), findsOneWidget);
        await capture('reply_$scenario-${brightness.name}', boundary);
        expect(submissions, scenario == 'expired' ? 0 : 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
      }

      final controller = createTestController(
        (command, [params = const {}]) async => command == 'notifications.list'
            ? {'status': 'available', 'live': true, 'notifications': <Json>[]}
            : fixtures.fixtureRequest(command, params),
      );
      await controller.initialize();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: RouterTestApp(
            key: ValueKey('missing-notification-${brightness.name}'),
            controller: controller,
            theme: fixtures.captureTheme(brightness),
            home: const Scaffold(body: SizedBox()),
            devices: [fixtures.device],
          ),
        ),
      );
      await tester.pumpAndSettle();
      NotificationReplyRoute(
        deviceId: 'fixture',
        notificationId: 'gone',
      ).push<void>(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();
      expect(find.byType(RouteErrorPage), findsOneWidget);
      expect(find.textContaining('这条通知已失效或无法核验'), findsOneWidget);
      expect(find.text('重新读取'), findsOneWidget);
      expect(find.text('返回设备列表'), findsOneWidget);
      await capture('missing_notification-${brightness.name}', boundary);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      controller.dispose();
    }
  });
}
