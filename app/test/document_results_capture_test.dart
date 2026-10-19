import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/transfers/details/export/transfers_details_export_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('system-save receipts and review gate use the real export form', (
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
    final scenarios = <(String, String, String, Json?)>[
      (
        'Gfe22',
        'cancelled',
        '本次系统保存已取消',
        {'status': 'cancelled', 'partialDestinationPossible': false},
      ),
      (
        'mcRQa',
        'saved',
        '已保存到系统位置',
        {
          'status': 'saved',
          'name': '旅行清单.pdf',
          'files': 1,
          'directories': 0,
          'bytes': 2468000,
        },
      ),
      (
        'vSjZS',
        'failed_empty',
        '本次保存未开始',
        {
          'status': 'failed',
          'files': 0,
          'directories': 0,
          'bytes': 0,
          'partialDestinationPossible': false,
        },
      ),
      (
        'pSoci',
        'unknown',
        '系统保存结果待核对',
        {'status': 'result_unknown', 'partialDestinationPossible': true},
      ),
      ('uhuiJ', 'ready', '选择系统位置并保存', null),
    ];
    for (final brightness in Brightness.values) {
      for (final layout in [
        ('phone', const Size(402, 874), 1.0),
        ('narrow', const Size(280, 620), 2.0),
      ]) {
        tester.view.physicalSize = layout.$2;
        tester.platformDispatcher.textScaleFactorTestValue = layout.$3;
        for (final scenario in scenarios) {
          var writes = 0;
          var reads = 0;
          final writeRequests = <Json>[];
          final controller = createTestController((
            command, [
            params = const {},
          ]) async {
            if (command == 'delivery.get') {
              reads++;
              expect(params['sourceId'], 'transfer:verified-original');
              return {
                'record': scenario.$4 == null
                    ? null
                    : {
                        'operationId': '${scenario.$2}-receipt',
                        'status': scenario.$4!['status'],
                        'result': scenario.$4,
                      },
              };
            }
            if (command == 'media.cache.acquire') {
              expect(params['transferId'], 'verified-original');
              return {'cacheLeaseId': 'original-capture-lease'};
            }
            if (command == 'documents.export') {
              writes++;
              writeRequests.add(params);
              return scenario.$4 ?? {'status': 'cancelled'};
            }
            return fixtures.fixtureRequest(command, params);
          });
          await controller.initialize();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: RouterTestApp(
                key: ValueKey('${scenario.$2}-${layout.$1}-${brightness.name}'),
                controller: controller,
                theme: fixtures.captureTheme(brightness),
                home: DocumentExportPage(
                  controller: controller,
                  transferId: 'verified-original',
                  localPath: '/private/cache/旅行清单.pdf',
                  name: '旅行清单.pdf',
                  kind: 'file',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(scenario.$3), findsOneWidget);
          expect(reads, greaterThan(0));
          expect(writes, 0, reason: 'Opening a receipt never repeats a save.');
          final retry = find.widgetWithText(FilledButton, '重新选择系统位置');
          final scrollable = find.byType(Scrollable).first;
          final position = tester.state<ScrollableState>(scrollable).position;
          final action = scenario.$2 == 'saved'
              ? find.widgetWithText(OutlinedButton, '再保存一份')
              : scenario.$2 == 'ready'
              ? find.widgetWithText(FilledButton, '选择系统位置并保存')
              : retry;
          await tester.scrollUntilVisible(action, 160, scrollable: scrollable);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          if (scenario.$2 == 'ready') {
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, '选择系统位置并保存'),
                  )
                  .onPressed,
              isNotNull,
            );
          } else if (scenario.$2 == 'saved') {
            expect(find.byType(FilledButton), findsNothing);
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, '再保存一份'),
                  )
                  .onPressed,
              isNotNull,
            );
          } else {
            expect(
              tester.widget<FilledButton>(retry).onPressed == null,
              scenario.$2 == 'unknown',
            );
          }
          List<double> rect(Rect bounds) => [
            bounds.left,
            bounds.top,
            bounds.width,
            bounds.height,
          ];

          Future<void> capture([String suffix = '']) async {
            expect(tester.takeException(), isNull);
            if (output == null) return;
            final contract = fixtures.captureLayout(boundary);
            String? hex(Color? color) => color == null
                ? null
                : '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
            final buttonStyles = <Map<String, Object?>>[];
            for (final element in find.byType(FilledButton).evaluate()) {
              final button = element.widget as FilledButton;
              final states = <WidgetState>{
                if (button.onPressed == null) WidgetState.disabled,
              };
              final theme = button.themeStyleOf(element);
              final defaults = button.defaultStyleOf(element);
              buttonStyles.add({
                'enabled': button.onPressed != null,
                'globalBounds': rect(tester.getRect(find.byWidget(button))),
                'backgroundColorHex': hex(
                  button.style?.backgroundColor?.resolve(states) ??
                      theme?.backgroundColor?.resolve(states) ??
                      defaults.backgroundColor?.resolve(states),
                ),
                'foregroundColorHex': hex(
                  button.style?.foregroundColor?.resolve(states) ??
                      theme?.foregroundColor?.resolve(states) ??
                      defaults.foregroundColor?.resolve(states),
                ),
              });
            }
            final checkboxes = <Map<String, Object?>>[];
            for (final element in find.byType(Checkbox).evaluate()) {
              final checkbox = element.widget as Checkbox;
              final box = element.findRenderObject()! as RenderBox;
              final bounds = MatrixUtils.transformRect(
                box.getTransformTo(null),
                Offset.zero & box.size,
              );
              checkboxes.add({
                'value': checkbox.value,
                'enabled': checkbox.onChanged != null,
                'controlAffinity': 'trailing (production default)',
                'shape':
                    (checkbox.shape ?? Theme.of(element).checkboxTheme.shape)
                        .runtimeType
                        .toString(),
                'globalBounds': rect(bounds),
                // Checkbox.width is its framework paint diameter; the RenderBox
                // additionally owns the larger interactive target.
                'nominalPaintBounds': rect(
                  Rect.fromCenter(
                    center: bounds.center,
                    width: Checkbox.width,
                    height: Checkbox.width,
                  ),
                ),
                'paintBoundsSource':
                    'Checkbox.width centered in actual RenderBox',
                'listTileGlobalBounds': rect(
                  tester.getRect(find.byType(CheckboxListTile)),
                ),
              });
            }
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
                  '${scenario.$2}-${layout.$1}-${brightness.name}$suffix';
              await File('${directory.path}/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              await File('${directory.path}/$name.json').writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
                  'sourceState': scenario.$1,
                  'scenario': scenario.$2,
                  'materialBackend': 'widget-test-fallback',
                  'nativePixelsRendered': false,
                  'systemPickerRendered': false,
                  'receipt': scenario.$4,
                  'verifiedCacheLease': true,
                  'loadedRecord': true,
                  'scrollOffset': position.pixels,
                  'scrollMaxExtent': position.maxScrollExtent,
                  'checkboxes': checkboxes,
                  'filledButtonStyles': buttonStyles,
                  ...contract,
                }),
              );
              image.dispose();
            });
          }

          position.jumpTo(0);
          await tester.pumpAndSettle();
          await capture();
          if (position.maxScrollExtent > 0) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            await capture('-actions');
          }
          if (scenario.$2 == 'unknown') {
            final tile = find.byType(CheckboxListTile);
            expect(tester.widget<CheckboxListTile>(tile).value, false);
            final label = tester.getRect(find.text('我已在系统文件应用核对，仍需重新保存'));
            final checkbox = tester.getRect(find.byType(Checkbox));
            expect(checkbox.left, greaterThanOrEqualTo(label.right));
            expect(
              Theme.of(tester.element(tile)).checkboxTheme.shape,
              isA<CircleBorder>(),
            );
            await tester.ensureVisible(tile);
            await tester.pumpAndSettle();
            await tester.tap(find.byType(Checkbox));
            await tester.pumpAndSettle();
            expect(tester.widget<CheckboxListTile>(tile).value, true);
            expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            await capture('-reviewed');
            await tester.ensureVisible(retry);
            await tester.tap(retry);
            await tester.pumpAndSettle();
            expect(writes, 1);
            expect(
              writeRequests.single['reviewedOperationId'],
              'unknown-receipt',
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          controller.dispose();
        }
      }
    }
  });
}
