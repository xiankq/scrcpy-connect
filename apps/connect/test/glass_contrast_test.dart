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
          for (final size in [const Size(100, 100), const Size(354, 72)]) {
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
                      child: Glass(
                        radius: 999,
                        child: SizedBox(width: size.width, height: size.height),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final pixels = <Color>[];
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = (await image.toByteData(
                // Color.alphaBlend expects straight-alpha RGB. rawRgba is
                // premultiplied and would apply transparency a second time.
                format: ui.ImageByteFormat.rawStraightRgba,
              ))!;
              // Include the left/right navigation labels, rather than proving
              // contrast only at the brightest point in a wide control.
              for (final x in [1 / 6, .5, 5 / 6]) {
                final offset =
                    ((image.height ~/ 2) * image.width +
                        (image.width * x).floor()) *
                    4;
                pixels.add(
                  Color.fromARGB(
                    data.getUint8(offset + 3),
                    data.getUint8(offset),
                    data.getUint8(offset + 1),
                    data.getUint8(offset + 2),
                  ),
                );
              }
              image.dispose();
            });
            for (final pixel in pixels) {
              final visible = Color.alphaBlend(
                pixel,
                backdrop,
              ).computeLuminance();
              final foreground = theme.colorScheme.onSurface.computeLuminance();
              final contrast =
                  (math.max(visible, foreground) + .05) /
                  (math.min(visible, foreground) + .05);
              expect(
                contrast,
                greaterThanOrEqualTo(4.5),
                reason:
                    '$brightness $size over $backdrop must remain legible across the controls.',
              );
            }
          }
        }
      }
    },
  );
}
