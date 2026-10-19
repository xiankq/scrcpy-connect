import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/gallery/preview/devices_workspace_gallery_preview_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ios_pages_capture_test.dart' show pageFixtures, fixtureRequest;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final size in [const Size(280, 620), const Size(620, 280)]) {
    testWidgets(
      'every page respects $size with 2x text and parent constraints',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final controller = createTestController(fixtureRequest);
        await controller.initialize();
        for (final entry in pageFixtures(controller).entries) {
          await tester.pumpWidget(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: RouterTestApp(
                  key: ValueKey(entry.key),
                  controller: controller,
                  theme: ConnectTokens.theme(Brightness.light),
                  home: entry.value,
                ),
              ),
            ),
          );
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (entry.key == 'media_preview' ||
              entry.key == 'media_preview_unavailable') {
            final canvas = find
                .descendant(
                  of: find.byType(MediaPreviewPage),
                  matching: find.byType(Stack),
                )
                .first;
            expect(
              tester.getSize(canvas),
              size,
              reason: 'Media content fills its parent, including behind floating tools.',
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key}: $size, 2x text',
          );
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
  for (final size in [const Size(280, 620), const Size(1194, 280)]) {
    testWidgets('root navigation respects desktop parent $size at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: TestProviderScope(
              controller: controller,
              child: const ConnectApp(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(GlassTabBar),
        size.width < 850 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
