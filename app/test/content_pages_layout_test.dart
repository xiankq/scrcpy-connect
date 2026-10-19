import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/details/devices_workspace_files_details_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/index/devices_workspace_gallery_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/pages/devices/details/index/devices_details_index_page.dart';
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
          home: DeviceDetailsPage(
            controller: controller,
            device: fixtures.device,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.text('Pixel 9')).dx,
        closeTo(402 - DesignTokens.spacingMd, .01),
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
}
