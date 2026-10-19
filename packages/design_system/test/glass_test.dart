import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as liquid;

void main() {
  test(
    'generated tokens preserve both theme appearances and optical values',
    () {
      final light = ConnectTokens.theme(Brightness.light);
      final dark = ConnectTokens.theme(Brightness.dark);
      expect(light.colorScheme.primary, const Color(0xff1b1b1f));
      expect(dark.colorScheme.primary, const Color(0xfff2f2f4));
      for (final theme in [light, dark]) {
        final style = theme.filledButtonTheme.style!;
        final fill = style.backgroundColor!.resolve({})!;
        final label = style.foregroundColor!.resolve({})!;
        final a = label.computeLuminance();
        final b = fill.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        expect(theme.splashFactory, NoSplash.splashFactory);
      }
      expect(light.colorScheme.surface, Colors.white);
      expect(dark.colorScheme.surface, const Color(0xff1c1c1e));
      expect(light.textTheme.displaySmall!.fontSize, 28);
      expect(light.textTheme.displaySmall!.height, 1.15);
      expect(light.textTheme.displaySmall!.letterSpacing, -.6);
      expect(light.textTheme.bodyMedium!.fontSize, 14);
      expect(light.textTheme.bodyMedium!.height, 1.4);
      expect(light.textTheme.bodyMedium!.fontWeight, FontWeight.w400);
      expect(ConnectTokens.glass, const Color(0x80ffffff));
      expect(ConnectTokens.glassDark, const Color(0x991c1c1e));
      expect(ConnectTokens.glassRefractionIndex, 1.1);
      expect(ConnectTokens.glassRefractionWidth, 16);
      expect(
        light.filledButtonTheme.style!.minimumSize!.resolve({}),
        const Size(44, 44),
      );
    },
  );

  test(
    'optical materials preserve transmitted content and visible edge lighting',
    () {
      for (final brightness in Brightness.values) {
        final regular = Glass.optics(brightness: brightness);
        final clear = Glass.optics(
          brightness: brightness,
          variant: GlassVariant.clear,
        );
        for (final style in [regular, clear]) {
          expect(
            style.shape!.cornerStyle,
            liquid.LiquidGlassCornerStyle.continuousRoundedRectangle,
          );
          expect(style.refractionIndex, greaterThan(1.02));
          expect(style.refractionWidth, greaterThan(0));
          expect(style.specular!.thickness, greaterThan(0));
          expect(style.specular!.intensity, greaterThan(0));
          expect(style.glow!.thickness, greaterThan(style.specular!.thickness));
          expect(style.glow!.intensity, greaterThan(0));
          expect(style.color.a, lessThan(1));
          expect(style.dispersion, 0);
        }
        expect(clear.blur, lessThan(regular.blur));
        expect(clear.color.a, lessThan(regular.color.a));
      }
    },
  );

  test('clear relies on the media layer for bright-background protection', () {
    for (final backdrop in [Colors.white, Colors.black]) {
      final material = Glass.optics(
        brightness: Brightness.dark,
        variant: GlassVariant.clear,
      );
      final center = Color.alphaBlend(
        material.color,
        Color.alphaBlend(DesignTokens.colorMediaShade, backdrop),
      );
      final a = Colors.white.computeLuminance();
      final b = center.computeLuminance();
      final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('translucent surfaces do not carry a second protection mask', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final variant in GlassVariant.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(brightness),
            home: Center(
              child: Glass(variant: variant, child: const Text('控制')),
            ),
          ),
        );
        final decorations = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(Glass),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          decorations.where(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient != null,
          ),
          isEmpty,
        );
      }
    }
  });

  testWidgets('icon control keeps a bounded 44 point rest footprint', (
    tester,
  ) async {
    await GlassMaterial.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassIconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加',
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Glass)), const Size(44, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating navigation remains reachable with large text on a narrow screen',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: GlassTabBar(
                  destinations: const [
                    GlassDestination(icon: Icons.devices, label: '设备'),
                    GlassDestination(icon: Icons.swap_vert, label: '传输'),
                    GlassDestination(icon: Icons.settings, label: '设置'),
                  ],
                  selectedIndex: selected,
                  onSelected: (index) => selected = index,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      for (final label in ['设备', '传输', '设置']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(CupertinoButton),
        );
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.text('传输'));
      expect(selected, 1);
    },
  );

  testWidgets(
    'glass icon control keeps its label and touch target in reduced transparency',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: GlassPreferences(
            reduceTransparency: true,
            child: Center(
              child: GlassIconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出控制',
                onPressed: () => activations++,
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('退出控制'), findsOneWidget);
      final size = tester.getSize(find.byType(CupertinoButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byType(CupertinoButton));
      expect(activations, 1);
      expect(find.byType(BackdropFilter), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'toolbar uses one material with 44-point actions and wraps to available width',
    (tester) async {
      var activations = 0;
      for (final scenario in [
        (1, null, const Size(44, 44)),
        (3, null, const Size(132, 44)),
        (3, 88.0, const Size(88, 88)),
      ]) {
        final buttons = List.generate(
          scenario.$1,
          (index) => IconButton(
            tooltip: '操作 $index',
            onPressed: () => activations++,
            icon: const Icon(Icons.more_horiz),
          ),
        );
        Widget toolbar = GlassToolbarGroup(children: buttons);
        if (scenario.$2 != null) {
          toolbar = SizedBox(width: scenario.$2, child: toolbar);
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: Center(child: toolbar),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Glass), findsOneWidget);
        expect(tester.getSize(find.byType(GlassToolbarGroup)), scenario.$3);
        for (var index = 0; index < scenario.$1; index++) {
          expect(
            tester.getSize(find.byTooltip('操作 $index')),
            const Size(44, 44),
          );
          await tester.tap(find.byTooltip('操作 $index'));
        }
      }
      expect(activations, 7);
    },
  );

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
