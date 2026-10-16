import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'glass retains readable control contrast over black and white video in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final backdrop in [Colors.black, Colors.white]) {
          final boundary = GlobalKey();
          final theme = ConnectTokens.theme(brightness);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                backgroundColor: backdrop,
                body: Center(
                  child: RepaintBoundary(
                    key: boundary,
                    child: const Glass(
                      radius: 999,
                      child: SizedBox(width: 100, height: 100),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          late Color pixel;
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final offset =
                ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
            pixel = Color.fromARGB(
              data.getUint8(offset + 3),
              data.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2),
            );
            image.dispose();
          });
          final visible = Color.alphaBlend(pixel, backdrop).computeLuminance();
          final foreground = theme.colorScheme.onSurface.computeLuminance();
          final contrast =
              (math.max(visible, foreground) + .05) /
              (math.min(visible, foreground) + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '$brightness over $backdrop must remain legible.',
          );
        }
      }
    },
  );
}
