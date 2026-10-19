import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/index/connection_wireless_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'USB denial and system selection cancellation keep app recovery',
    (tester) async {
      for (final font in [
        (
          'packages/lucide_icons_flutter/Lucide',
          'packages/lucide_icons_flutter/assets/lucide.ttf',
        ),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
      }
      final cjk = File(
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      );
      if (cjk.existsSync()) {
        await (FontLoader('ConnectCaptureCJK')..addFont(
              Future.value(ByteData.sublistView(cjk.readAsBytesSync())),
            ))
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
        ]) {
          tester.view.physicalSize = layout.$2;
          tester.platformDispatcher.textScaleFactorTestValue = layout.$3;
          for (final scenario in [
            ('usb_access_denied', 'permission_denied', '尚未允许主控应用访问 USB 设备。'),
            ('usb_selection_cancelled', 'cancelled', '已取消选择 USB 设备。'),
          ]) {
            final requests = <Json>[];
            final controller = createTestController((
              command, [
              params = const {},
            ]) async {
              if (command == 'devices.usb') {
                requests.add(params);
                throw RequestFailure(scenario.$2, scenario.$3);
              }
              return fixtures.fixtureRequest(command, params);
            });
            await controller.initialize();
            final boundary = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: RouterTestApp(
                  key: ValueKey(
                    '${scenario.$1}-${layout.$1}-${brightness.name}',
                  ),
                  controller: controller,
                  theme: fixtures.captureTheme(brightness),
                  home: const Scaffold(body: SizedBox()),
                ),
              ),
            );
            await tester.pumpAndSettle();
            const UsbGuideRoute().push<void>(
              tester.element(find.byType(Scaffold)),
            );
            await tester.pumpAndSettle();
            expect(find.byType(UsbGuidePage), findsOneWidget);
            final check = find.widgetWithText(FilledButton, '已连接，检查授权');
            for (var attempt = 0; attempt < 2; attempt++) {
              await tester.scrollUntilVisible(
                check,
                180,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.ensureVisible(check);
              await tester.pumpAndSettle();
              await tester.tap(check);
              await tester.pumpAndSettle();
              expect(find.text(scenario.$3), findsOneWidget);
              expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
              expect(find.text('取消本次检查'), findsNothing);
            }
            expect(requests, hasLength(2));
            expect(
              requests.every(
                (request) => value(request, 'attemptId').isNotEmpty,
              ),
              isTrue,
            );
            expect(
              requests.first['attemptId'],
              isNot(requests.last['attemptId']),
            );
            expect(
              requests.every((request) => request['connect'] != true),
              isTrue,
            );
            // The actual recovery route remains reachable after either result.
            await tester.scrollUntilVisible(
              find.text('改用无线连接'),
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(find.text('改用无线连接'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('改用无线连接'));
            await tester.pumpAndSettle();
            expect(find.byType(WirelessGuidePage), findsOneWidget);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(find.text(scenario.$3), findsOneWidget);
            final position = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            position.jumpTo(0);
            await tester.pumpAndSettle();

            Future<void> capture([String suffix = '']) async {
              expect(tester.takeException(), isNull);
              if (output == null) return;
              final contract = fixtures.captureLayout(boundary);
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
                final name =
                    '${scenario.$1}-${layout.$1}-${brightness.name}$suffix';
                await File('${directory.path}/$name.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                await File('${directory.path}/$name.json').writeAsString(
                  const JsonEncoder.withIndent('  ').convert({
                    'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
                    'sourceState': 'w38WDx',
                    'scenario': scenario.$1,
                    'bridgeError': {
                      'code': scenario.$2,
                      'message': scenario.$3,
                    },
                    'errorTextSource': 'Android MainActivity USB receiver / chooser cancel listener',
                    'systemPermissionSurfaceRendered': false,
                    'systemChooserSurfaceRendered': false,
                    'materialBackend': 'widget-test-fallback',
                    'scrollOffset': position.pixels,
                    ...contract,
                  }),
                );
                image.dispose();
              });
            }

            await capture();
            if (position.maxScrollExtent > 0) {
              position.jumpTo(position.maxScrollExtent);
              await tester.pumpAndSettle();
              await capture('-feedback');
            }
            expect(requests, hasLength(2));
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            controller.dispose();
          }
        }
      }
    },
  );
}
