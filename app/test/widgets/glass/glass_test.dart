import 'dart:ui';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

Finder inside(Finder parent, Type type) =>
    find.descendant(of: parent, matching: find.byType(type));

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey(brightness),
    theme: ConnectTokens.theme(brightness),
    builder: (context, child) =>
        TooltipVisibility(visible: false, child: child!),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('compact switches keep geometry, keyboard and toggle semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final brightness in Brightness.values) {
      var value = false;
      var enabled = true;
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
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
        brightness: brightness,
      );
      final control = find.byType(ConnectSwitch);
      SemanticsFlags flags() => tester.getSemantics(control).flagsCollection;
      expect(tester.getSize(control), const Size(44, 44));
      final track = inside(control, AnimatedContainer);
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
      expect(flags().isToggled, Tristate.isFalse);
      await tester.tapAt(tester.getTopLeft(control) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(flags().isToggled, Tristate.isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(flags().isEnabled, Tristate.isFalse);
      await tester.tap(control);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
    }
    semantics.dispose();
  });

  testWidgets(
    'visual preference changes preserve control state and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var activations = 0;
      const controlKey = ValueKey('control');
      final rawGesture = inside(find.byKey(controlKey), RawGestureDetector);
      RawGestureDetectorState? initial;

      for (final preference in [
        'normal',
        'solid',
        'reduceTransparency',
        'highContrast',
        'normal',
      ]) {
        await mount(
          tester,
          MediaQuery(
            data: MediaQueryData(highContrast: preference == 'highContrast'),
            child: GlassPreferences(
              reduceTransparency: preference == 'reduceTransparency',
              child: GlassSurfaceGroup(
                child: GlassPressFeedback(
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

        final state = tester.state<RawGestureDetectorState>(rawGesture);
        initial ??= state;
        expect(state, same(initial));
        expect(find.bySemanticsLabel('共享控制'), findsOneWidget);
        expect(tester.getSize(find.byType(Glass)), const Size(76, 76));
        if (preference != 'normal') {
          expect(find.byType(liquid.AdaptiveGlass), findsNothing);
          expect(find.byType(BackdropFilter), findsNothing);
          final decorations = tester.widgetList<DecoratedBox>(
            inside(find.byType(Glass), DecoratedBox),
          );
          expect(
            decorations.any(
              (widget) => switch (widget.decoration) {
                BoxDecoration(color: Colors.white, gradient: null) => true,
                _ => false,
              },
            ),
            isTrue,
          );
        } else {
          expect(find.byType(liquid.AdaptiveGlass), findsOneWidget);
        }
        await tester.tap(find.byKey(controlKey));
      }
      expect(activations, 5);
      semantics.dispose();
    },
  );

  testWidgets(
    'pointer feedback clears on cancellation without owning gestures',
    (tester) async {
      var taps = 0;
      var pans = 0;
      var enabled = true;
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return GlassPressFeedback(
              enabled: enabled,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                onPanUpdate: (_) => pans++,
                child: const SizedBox(width: 52, height: 52),
              ),
            );
          },
        ),
      );
      final target = find.byType(GlassPressFeedback);
      final decoration = inside(target, DecoratedBox);
      Color? overlay() =>
          (tester.widget<DecoratedBox>(decoration).decoration
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
    'menu preserves adaptive material, actions and dismissal without Impeller',
    (tester) async {
      expect(ImageFilter.isShaderFilterSupported, isFalse);
      var activations = 0;
      await mount(
        tester,
        GlassMenuButton(
          icon: const Icon(Icons.more_horiz),
          tooltip: '更多',
          actions: [
            GlassMenuAction(label: '设备详情', onPressed: () => activations++),
            const GlassMenuAction(label: '不可用', onPressed: null),
          ],
        ),
      );
      final menu = find.byType(GlassMenuButton);
      final trigger = inside(menu, IconButton);
      expect(tester.getSize(menu), const Size(44, 44));
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final material = tester.widget<liquid.AdaptiveGlass>(
        find.ancestor(
          of: find.text('设备详情'),
          matching: find.byType(liquid.AdaptiveGlass),
        ),
      );
      expect(material.quality, isNot(liquid.GlassQuality.minimal));
      await tester.tap(find.text('不可用'));
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(find.text('设备详情'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(find.text('设备详情'), findsNothing);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备详情'));
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
