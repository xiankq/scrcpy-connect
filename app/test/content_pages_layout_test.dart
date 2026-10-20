import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/discovery/connection_discovery_page.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/settings/background/settings_background_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/file_row_title.dart';
import 'package:scrcpy_connect/widgets/media_thumbnail.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('file size uses the trailing edge and survives large text', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final layout in [(300.0, 1.0), (150.0, 2.0), (140.0, 3.0)]) {
      tester.platformDispatcher.textScaleFactorTestValue = layout.$2;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: const ValueKey('file-identity'),
                width: layout.$1,
                child: const FileRowTitle(
                  name: 'Travel preparation.pdf',
                  path: '/sdcard/Download/Travel preparation.pdf',
                  size: '2.4 MB',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('2.4 MB'), findsOneWidget);
      expect(
        tester.getBottomRight(find.text('2.4 MB')).dx,
        closeTo(
          tester.getBottomRight(find.byKey(const ValueKey('file-identity'))).dx,
          .01,
        ),
      );
      expect(
        find.byTooltip('/sdcard/Download/Travel preparation.pdf'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'page facts use content edges and the wide sidebar fills height',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = createTestController(fixtures.fixtureRequest);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        RouterTestApp(
          key: const ValueKey('device-facts'),
          controller: controller,
          theme: fixtures.captureTheme(Brightness.light),
          home: DeviceWorkspacePage(
            controller: controller,
            device: fixtures.device,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('192.168.1.8').last).dx,
        closeTo(tester.getTopLeft(find.text('Pixel 9').last).dx, .01),
      );
      await tester.pumpWidget(
        RouterTestApp(
          key: const ValueKey('background-facts'),
          controller: controller,
          theme: fixtures.captureTheme(Brightness.light),
          home: BackgroundPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in ['后台保持已就绪', '系统允许当前设备连接继续运行。']) {
        expect(
          tester.getTopLeft(find.text(text)).dx,
          closeTo(DesignTokens.spacingMd * 2, .01),
        );
      }
      tester.view.physicalSize = const Size(1194, 834);
      const DevicesRoute().go(tester.element(find.byType(BackgroundPage)));
      await tester.pumpAndSettle();
      final sidebar = find.ancestor(
        of: find.text('邻接'),
        matching: find.byType(Glass),
      );
      expect(sidebar, findsOneWidget);
      final bounds = tester.getRect(sidebar);
      expect(bounds.top, closeTo(DesignTokens.spacingMd, .01));
      expect(bounds.bottom, closeTo(834 - DesignTokens.spacingMd, .01));
      expect(tester.getTopLeft(find.text('邻接')).dy, lessThan(100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'content pages keep real content and reachable actions at large text',
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
          ('landscape', const Size(620, 280), 2.0),
        ]) {
          tester.view.physicalSize = layout.$2;
          tester.platformDispatcher.textScaleFactorTestValue = layout.$3;
          final controller = createTestController((
            command, [
            params = const {},
          ]) async {
            final data = await fixtures.fixtureRequest(command, params);
            if (command == 'session.quality.options' && layout.$1 != 'phone') {
              return {
                ...data,
                'current': {
                  ...jsonObject(data['current']),
                  'videoEncoder': 'c2.android.avc.encoder',
                },
              };
            }
            return data;
          });
          await controller.initialize();
          final pages = {
            'quality': QualityPage(
              controller: controller,
              device: fixtures.device,
            ),
            'file_details': FileDetailsPage(
              controller: controller,
              device: fixtures.device,
              file: {
                ...fixtures.file,
                if (layout.$1 != 'phone')
                  'name': '这是一份需要保留完整名称的旅行准备与行程核对清单.pdf',
              },
            ),
            'gallery': GalleryPage(
              controller: controller,
              device: fixtures.device,
            ),
            'notifications': NotificationsPage(
              controller: controller,
              device: fixtures.device,
            ),
          };
          for (final page in pages.entries) {
            final boundary = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: RouterTestApp(
                  key: ValueKey('${page.key}-${layout.$1}-${brightness.name}'),
                  controller: controller,
                  theme: fixtures.captureTheme(brightness),
                  home: page.value,
                ),
              ),
            );
            for (var frame = 0; frame < 8; frame++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (page.key == 'gallery') {
              await fixtures.waitForPageImages(tester);
              expect(find.text('相册范围与未读项目'), findsOneWidget);
              expect(find.textContaining('已显示 1 / 1 项'), findsOneWidget);
              if (layout.$1 == 'phone') {
                expect(
                  tester.getTopLeft(find.byType(MediaThumbnail)).dy,
                  lessThan(250),
                  reason: 'Photos precede a separate scope card.',
                );
              }
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.key}-${layout.$1}-${brightness.name}',
            );
            Future<void> capture([String suffix = '']) async {
              if (output == null) return;
              await tester.runAsync(() async {
                final directory = Directory(output);
                await directory.create(recursive: true);
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${directory.path}/${page.key}-${layout.$1}-${brightness.name}$suffix.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }

            await capture();
            final target = switch (page.key) {
              'quality' => find.text('视频编码器'),
              'file_details' => find.text('交给系统分享'),
              'gallery' => find.text('相册范围与未读项目'),
              _ => find.text('进入手机原应用'),
            };
            await tester.scrollUntilVisible(
              target,
              160,
              scrollable: find.byType(Scrollable).first,
            );
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget);
            if (page.key == 'quality' && layout.$1 != 'phone') {
              expect(find.text('c2.android.avc.encoder'), findsOneWidget);
            }
            if (page.key == 'notifications') {
              final button = find.ancestor(
                of: target,
                matching: find.byType(TextButton),
              );
              expect(button, findsOneWidget);
              expect(
                tester.getSize(button).height,
                greaterThanOrEqualTo(DesignTokens.componentIconButtonSize),
              );
            }
            expect(tester.takeException(), isNull);
            if (layout.$1 != 'phone') await capture('-action');
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          }
          controller.dispose();
        }
      }
    },
  );

  testWidgets('empty discovery keeps every existing recovery route reachable', (
    tester,
  ) async {
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
        var discoveries = 0;
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'devices.discover') {
            discoveries++;
            return {'devices': <Json>[]};
          }
          return fixtures.fixtureRequest(command, params);
        });
        await controller.initialize();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: RouterTestApp(
              key: ValueKey('empty-discovery-${layout.$1}-${brightness.name}'),
              controller: controller,
              theme: fixtures.captureTheme(brightness),
              home: DiscoveryPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('未发现设备'), findsOneWidget);
        final before = discoveries;
        await tester.ensureVisible(find.text('重新查找'));
        await tester.tap(find.text('重新查找'));
        await tester.pumpAndSettle();
        expect(discoveries, before + 1);
        for (final recovery in [
          ('IP 连接', ConnectionFormPage),
          ('使用无线配对码', ConnectionFormPage),
          ('改用 USB', UsbGuidePage),
        ]) {
          final action = find.text(recovery.$1).last;
          await tester.scrollUntilVisible(
            action,
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(
            tester
                .getSize(
                  find
                      .ancestor(
                        of: action,
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is OutlinedButton ||
                              widget.runtimeType.toString() == 'ActionRow',
                        ),
                      )
                      .first,
                )
                .height,
            greaterThanOrEqualTo(44),
          );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(find.byType(recovery.$2), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        if (output != null) {
          final contract = fixtures.captureLayout(boundary);
          await tester.runAsync(() async {
            final directory = Directory(output);
            await directory.create(recursive: true);
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final name = 'discovery_empty-${layout.$1}-${brightness.name}';
            await File('${directory.path}/$name.png')
                .writeAsBytes(data!.buffer.asUint8List());
            await File('${directory.path}/$name.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert(contract),
            );
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
      }
    }
  });

  testWidgets('local rename and removal dialogs stay readable before mutation', (
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
    for (final brightness in Brightness.values) {
      for (final layout in [
        ('phone', const Size(402, 874), 1.0),
        ('narrow', const Size(280, 620), 2.0),
      ]) {
        tester.view.physicalSize = layout.$2;
        tester.platformDispatcher.textScaleFactorTestValue = layout.$3;
        final mutations = <String>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if ([
            'devices.rename',
            'devices.disconnect',
            'devices.forget',
            'files.rename',
            'files.delete',
          ].contains(command)) {
            mutations.add(command);
          }
          return fixtures.fixtureRequest(command, params);
        });
        await controller.initialize();
        for (final state in [
          'device_rename',
          'device_disconnect',
          'device_remove',
          'file_rename',
          'file_delete',
        ]) {
          final boundary = GlobalKey();
          final isDevice = state.startsWith('device_');
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: RouterTestApp(
                key: ValueKey('$state-${layout.$1}-${brightness.name}'),
                controller: controller,
                theme: fixtures.captureTheme(brightness),
                home: isDevice
                    ? DeviceWorkspacePage(
                        controller: controller,
                        device: fixtures.device,
                      )
                    : FilesPage(
                        controller: controller,
                        device: fixtures.device,
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (isDevice) {
            final action = find.text(switch (state) {
              'device_rename' => '设备名称',
              'device_disconnect' => '断开设备连接',
              _ => '移除此设备',
            });
            await tester.scrollUntilVisible(action, 160);
            await Scrollable.ensureVisible(
              tester.element(action),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            await tester.tap(action);
          } else {
            await tester.tap(find.byTooltip('文件操作').last);
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(state == 'file_rename' ? '重命名' : '删除').last,
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(GlassAlertDialog), findsOneWidget);
          if (state.endsWith('rename')) {
            final input = find.descendant(
              of: find.byType(GlassAlertDialog),
              matching: find.byType(TextField),
            );
            expect(input, findsOneWidget);
            expect(
              tester.widget<TextField>(input).controller!.text,
              isDevice ? '我的手机' : '旅行清单.pdf',
            );
          }
          expect(tester.takeException(), isNull, reason: '$state-${layout.$1}');
          Future<void> capture([String suffix = '']) async {
            if (output == null) return;
            final dialog = find.byType(GlassAlertDialog);
            List<double> rect(Rect value) => [
              value.left,
              value.top,
              value.width,
              value.height,
            ];
            final bounds = tester.getRect(
              find
                  .descendant(
                    of: dialog,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Material &&
                          widget.type == MaterialType.card,
                    ),
                  )
                  .first,
            );
            final contract = <String, Object?>{
              'coordinateSpace':
                  'uncropped source image; logical pixels at DPR 1',
              'components': [
                for (final type in [TextField, TextButton, FilledButton])
                  for (final element
                      in find
                          .descendant(of: dialog, matching: find.byType(type))
                          .evaluate())
                    {
                      'type': type.toString(),
                      'globalBounds': rect(
                        tester.getRect(
                          find.byElementPredicate(
                            (candidate) => candidate == element,
                          ),
                        ),
                      ),
                    },
              ],
              'paragraphs': [
                for (final element
                    in find
                        .descendant(of: dialog, matching: find.byType(RichText))
                        .evaluate())
                  if (element.renderObject case final RenderParagraph paragraph)
                    {
                      'text': paragraph.text.toPlainText(),
                      'globalBounds': rect(
                        tester.getRect(
                          find.byElementPredicate(
                            (candidate) => candidate == element,
                          ),
                        ),
                      ),
                      'fontSize': paragraph.text.style?.fontSize,
                      'fontWeight': paragraph.text.style?.fontWeight?.value,
                      'height': paragraph.text.style?.height,
                      'styleRuns': fixtures.captureTextStyleRuns(
                        paragraph.text,
                      ),
                      'textScaleAt14': paragraph.textScaler.scale(14) / 14,
                    },
              ],
              'editableTexts': [
                for (final element
                    in find
                        .descendant(
                          of: dialog,
                          matching: find.byElementPredicate(
                            (element) =>
                                element is RenderObjectElement &&
                                element.renderObject is RenderEditable,
                          ),
                        )
                        .evaluate())
                  if (element.renderObject case final RenderEditable editable)
                    {
                      'text': editable.text?.toPlainText() ?? '',
                      'value': element
                          .findAncestorWidgetOfExactType<EditableText>()
                          ?.controller
                          .text,
                      'readOnly': editable.readOnly,
                      'obscureText': editable.obscureText,
                      'globalBounds': rect(
                        tester.getRect(
                          find.byElementPredicate(
                            (candidate) => candidate == element,
                          ),
                        ),
                      ),
                      'fieldGlobalBounds': rect(
                        tester.getRect(
                          find
                              .descendant(
                                of: dialog,
                                matching: find.byType(TextField),
                              )
                              .first,
                        ),
                      ),
                      'textScaleAt14': editable.textScaler.scale(14) / 14,
                      'styleRuns': fixtures.captureTextStyleRuns(editable.text),
                    },
              ],
            };
            await tester.runAsync(() async {
              final directory = Directory(output);
              await directory.create(recursive: true);
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${directory.path}/$state-${layout.$1}-${brightness.name}$suffix.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
              await File(
                '${directory.path}/$state-${layout.$1}-${brightness.name}$suffix.json',
              ).writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'state': state,
                  'dialogBounds': [
                    bounds.left,
                    bounds.top,
                    bounds.width,
                    bounds.height,
                  ],
                  ...contract,
                }),
              );
            });
          }

          await capture();
          if (!state.endsWith('rename')) {
            final scrollable = find.descendant(
              of: find.byType(GlassAlertDialog),
              matching: find.byType(Scrollable),
            );
            expect(scrollable, findsOneWidget);
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.maxScrollExtent > 0) {
              position.jumpTo(position.maxScrollExtent);
              await tester.pumpAndSettle();
              await capture('-scrolled');
            }
          }
          final cancel = find.widgetWithText(TextButton, '取消');
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(GlassAlertDialog), findsNothing);
          expect(mutations, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
        controller.dispose();
      }
    }
  });
}
