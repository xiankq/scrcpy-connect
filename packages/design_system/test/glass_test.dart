import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

void main() {
  testWidgets('compact switches keep geometry, keyboard and toggle semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final brightness in Brightness.values) {
      var value = false;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(brightness),
          theme: ConnectTokens.theme(brightness),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ConnectSwitch(
                    value: value,
                    onChanged: enabled
                        ? (next) => setState(() => value = next)
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      );
      final control = find.byType(ConnectSwitch);
      expect(tester.getSize(control), const Size(44, 44));
      final track = find.descendant(
        of: control,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(track), const Size(44, 28));
      final thumb = find.descendant(
        of: control,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(tester.getSize(thumb), const Size(20, 20));
      expect(
        tester.getSemantics(control).flagsCollection.isToggled,
        Tristate.isFalse,
      );
      await tester.tapAt(tester.getTopLeft(control) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(
        tester.getSemantics(control).flagsCollection.isToggled,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(control).flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(control);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
    }
    semantics.dispose();
  });

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

        expect(find.byType(liquid.AdaptiveGlass), findsNothing);
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

  testWidgets(
    'pointer feedback clears on cancellation without owning gestures',
    (tester) async {
      var taps = 0;
      var pans = 0;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: GlassPressFeedback(
                  enabled: enabled,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    onPanUpdate: (_) => pans++,
                    child: const SizedBox(width: 52, height: 52),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final target = find.byType(GlassPressFeedback);
      Color? overlay() =>
          (tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: target,
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as ShapeDecoration)
              .color;
      final initial = overlay();
      final cancelled = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      expect(overlay(), isNot(initial));
      expect(overlay()!.a, greaterThan(0));
      await cancelled.cancel();
      await tester.pump();
      expect(overlay(), initial);
      expect(taps, 0);
      final drag = await tester.startGesture(tester.getCenter(target));
      await drag.moveBy(const Offset(60, 0));
      await tester.pump();
      await drag.moveBy(const Offset(10, 0));
      await drag.up();
      await tester.pump();
      expect(pans, greaterThan(0));
      expect(taps, 0);
      expect(overlay(), initial);
      final interrupted = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      update(() => enabled = false);
      await tester.pump();
      expect(overlay(), initial);
      await interrupted.cancel();
      await tester.pump();
      expect(tester.getSize(target), const Size(52, 52));
    },
  );

  testWidgets(
    'menu preserves actions and dismissal in the non-shader renderer',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          builder: (context, child) =>
              TooltipVisibility(visible: false, child: child!),
          home: Scaffold(
            body: Center(
              child: GlassMenuButton(
                icon: const Icon(Icons.more_horiz),
                tooltip: '更多',
                actions: [
                  GlassMenuAction(
                    label: '设备详情',
                    onPressed: () => activations++,
                  ),
                  const GlassMenuAction(label: '不可用', onPressed: null),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(GlassMenuButton)), const Size(44, 44));
      await tester.tap(
        find.descendant(
          of: find.byType(GlassMenuButton),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('不可用'));
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(find.text('设备详情'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(find.text('设备详情'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(GlassMenuButton),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备详情'));
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
