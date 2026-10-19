import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('actual app opening sheet and failed window preserve recovery', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
      await (FontLoader(
            'ConnectCaptureCJK',
          )..addFont(Future.value(ByteData.sublistView(cjk.readAsBytesSync()))))
          .load();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final output = Platform.environment['CONNECT_CAPTURE_DIR'];
    for (final brightness in Brightness.values) {
      for (final layout in [
        ('phone', const Size(402, 874), 1.0),
        ('narrow', const Size(280, 620), 2.0),
        ('landscape', const Size(620, 280), 2.0),
      ]) {
        tester.view.physicalSize = layout.$2;
        tester.platformDispatcher.textScaleFactorTestValue = layout.$3;
        for (final scenario in ['apps_modes', 'apps_window_failed']) {
          final calls = <(String, Json)>[];
          final controller = createTestController((
            command, [
            params = const {},
          ]) async {
            calls.add((command, params));
            if (command == 'session.list') return {'sessions': <Json>[]};
            if (command == 'session.start') {
              throw const RequestFailure('unsupported', '独立窗口不可用');
            }
            return fixtures.fixtureRequest(command, params);
          });
          await controller.initialize();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: RouterTestApp(
                key: ValueKey('$scenario-${layout.$1}-${brightness.name}'),
                controller: controller,
                devices: [fixtures.device],
                theme: fixtures.captureTheme(brightness),
                home: const Scaffold(body: SizedBox()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          const AppsRoute(deviceId: 'fixture')
              .push<void>(tester.element(find.byType(Scaffold)));
          await tester.pumpAndSettle();
          expect(find.byType(AppsPage), findsOneWidget);
          final headerGroup = find.ancestor(
            of: find.byType(AppBar),
            matching: find.byType(GlassSurfaceGroup),
          );
          expect(headerGroup, findsOneWidget);
          expect(
            tester.widget<GlassSurfaceGroup>(headerGroup).variant,
            GlassVariant.regular,
          );
          await tester.scrollUntilVisible(
            find.text('地图'),
            80,
            scrollable: find
                .descendant(
                  of: find.byType(AppsPage),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(find.text('地图').hitTestable(), findsOneWidget);
          await tester.tap(find.text('地图'));
          await tester.pumpAndSettle();
          expect(find.text('打开“地图”'), findsOneWidget);
          expect(find.text('在独立窗口打开'), findsOneWidget);
          expect(find.text('在手机屏幕打开'), findsOneWidget);
          expect(find.text('在手机屏幕打开会切换手机当前的前台应用。'), findsOneWidget);

          Future<void> capture([String suffix = '']) async {
            expect(
              tester.takeException(),
              isNull,
              reason: '$scenario-${layout.$1}',
            );
            if (output == null || layout.$1 == 'landscape') return;
            final contract = fixtures.captureLayout(boundary);
            List<double> rect(Rect value) => [
              value.left,
              value.top,
              value.width,
              value.height,
            ];
            final recoveryViewport = find.byKey(
              const ValueKey('remote-recovery-content'),
            );
            final exit = find.descendant(
              of: find.byType(ExitHandle),
              matching: find.byType(Glass),
            );
            await tester.runAsync(() async {
              final directory = Directory(output);
              await directory.create(recursive: true);
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final name = '$scenario-${layout.$1}-${brightness.name}$suffix';
              await File('${directory.path}/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              await File('${directory.path}/$name.json').writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
                  'scenario': scenario,
                  'sourceState': scenario == 'apps_modes' ? 'tch6A' : 'qTeGO',
                  'materialBackend': 'widget-test-fallback',
                  'bridgeFixture': {
                    'session.list': <Json>[],
                    'session.start': 'unsupported: 独立窗口不可用',
                  },
                  'nativeTextureSupplied': false,
                  'nativePixelsSupplied': false,
                  if (recoveryViewport.evaluate().isNotEmpty)
                    'recoveryViewportBounds': rect(
                      tester.getRect(recoveryViewport),
                    ),
                  if (exit.evaluate().isNotEmpty)
                    'exitControlBounds': rect(tester.getRect(exit.first)),
                  ...contract,
                }),
              );
              image.dispose();
            });
          }

          if (scenario == 'apps_modes') {
            for (final label in ['在独立窗口打开', '在手机屏幕打开', '取消']) {
              await tester.ensureVisible(find.text(label));
              await tester.pumpAndSettle();
              final button = find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is FilledButton ||
                          widget is OutlinedButton ||
                          widget is TextButton,
                    ),
                  )
                  .first;
              expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            }
            final scroll = tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(BottomSheet),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;
            scroll.jumpTo(0);
            await tester.pumpAndSettle();
            await capture();
            if (scroll.maxScrollExtent > 0) {
              scroll.jumpTo(scroll.maxScrollExtent);
              await tester.pumpAndSettle();
              await capture('-actions');
            }
            expect(calls.where((call) => call.$1 == 'session.start'), isEmpty);
          } else {
            await tester.ensureVisible(find.text('在独立窗口打开'));
            await tester.tap(find.text('在独立窗口打开'));
            await tester.pumpAndSettle();
            expect(find.byType(RemotePage), findsOneWidget);
            expect(find.byType(Texture), findsNothing);
            expect(find.text('暂时无法打开实时画面'), findsOneWidget);
            expect(find.text('独立窗口不可用'), findsOneWidget);
            expect(find.text('在手机屏幕继续'), findsOneWidget);
            expect(find.text('重新检查'), findsOneWidget);
            final exitBounds = tester.getRect(
              find
                  .descendant(
                    of: find.byType(ExitHandle),
                    matching: find.byType(Glass),
                  )
                  .first,
            );
            final recoveryBounds = tester.getRect(
              find.byKey(const ValueKey('remote-recovery-content')),
            );
            expect(
              recoveryBounds.overlaps(exitBounds),
              isFalse,
              reason: 'The visible recovery viewport must avoid the actual exit control',
            );
            expect(
              calls
                  .where((call) => call.$1 == 'session.start')
                  .single
                  .$2['packageName'],
              'com.google.android.apps.maps',
            );
            // The recovery confirmation must precede any phone-screen launch.
            await tester.ensureVisible(find.text('在手机屏幕继续'));
            await tester.tap(find.text('在手机屏幕继续'));
            await tester.pumpAndSettle();
            expect(find.text('在手机屏幕继续？'), findsOneWidget);
            expect(calls.where((call) => call.$1 == 'session.launch'), isEmpty);
            await tester.ensureVisible(find.text('取消'));
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
            expect(calls.where((call) => call.$1 == 'session.launch'), isEmpty);
            final scroll = tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(RemotePage),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;
            scroll.jumpTo(0);
            await tester.pumpAndSettle();
            await capture();
            if (scroll.maxScrollExtent > 0) {
              scroll.jumpTo(scroll.maxScrollExtent);
              await tester.pumpAndSettle();
              await capture('-actions');
            }
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          controller.dispose();
        }
      }
    }
  });
}
