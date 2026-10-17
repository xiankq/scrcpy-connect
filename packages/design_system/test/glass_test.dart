import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as liquid;

void main() {
  testWidgets('opaque preferences bypass optics and preserve the control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var activations = 0;
    const controlKey = ValueKey('control');

    try {
      for (final preference in [
        'solid',
        'reduceTransparency',
        'highContrast',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(highContrast: preference == 'highContrast'),
              child: GlassPreferences(
                reduceTransparency: preference == 'reduceTransparency',
                child: Center(
                  child: Glass(
                    solid: preference == 'solid',
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      label: '共享控制',
                      button: true,
                      child: GestureDetector(
                        key: controlKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => activations++,
                        child: const SizedBox(width: 44, height: 44),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(liquid.LiquidGlassLens), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.bySemanticsLabel('共享控制'), findsOneWidget);
        expect(tester.getSize(find.byType(Glass)), const Size(76, 76));
        final decorations = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(Glass),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          decorations.any(
            (widget) =>
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color == Colors.white &&
                (widget.decoration as BoxDecoration).gradient == null,
          ),
          isTrue,
        );
        await tester.tap(find.byKey(controlKey));
      }
      expect(activations, 3);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('unsupported renderer retains the frosted material', (
    tester,
  ) async {
    // The widget-test renderer has no Impeller shader image filters. The
    // production shader branch is covered by device rendering checks.
    expect(ImageFilter.isShaderFilterSupported, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        home: const Center(child: Glass(child: Text('可用控制'))),
      ),
    );

    expect(find.byType(liquid.LiquidGlassLens), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('可用控制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('app bars choose system icons for the active appearance', () {
    final light = ConnectTokens.theme(Brightness.light).appBarTheme;
    final dark = ConnectTokens.theme(Brightness.dark).appBarTheme;
    expect(light.systemOverlayStyle!.statusBarIconBrightness, Brightness.dark);
    expect(light.systemOverlayStyle!.statusBarBrightness, Brightness.light);
    expect(dark.systemOverlayStyle!.statusBarIconBrightness, Brightness.light);
    expect(dark.systemOverlayStyle!.statusBarBrightness, Brightness.dark);
  });
}
