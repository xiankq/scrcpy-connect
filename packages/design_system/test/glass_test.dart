import 'dart:ui';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import 'support/official_glass_controls.dart';

void main() {
  testWidgets('filled connection labels remain inside their surface', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey((brightness, scale)),
            theme: ConnectTokens.theme(brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: TextFormField(
                      initialValue: '192.168.1.22',
                      decoration: const InputDecoration(labelText: 'IP 地址或主机名'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.getRect(find.byType(InputDecorator));
        final label = tester.getRect(find.text('IP 地址或主机名'));
        expect(label.top, greaterThanOrEqualTo(surface.top));
        expect(label.bottom, lessThanOrEqualTo(surface.bottom));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'read-only identity fields stay compact without a change affordance',
    (tester) async {
      for (final scenario in [(370.0, 1.0), (248.0, 2.0)]) {
        var mutations = 0;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(scenario),
            theme: ConnectTokens.theme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: scenario.$1,
                  child: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(scenario.$2),
                    ),
                    child: ConnectSelectionField<String>(
                      label: 'ADB 私钥',
                      value: 'device',
                      readOnly: true,
                      icon: const Icon(Icons.expand_more),
                      items: const [
                        DropdownMenuItem(
                          value: 'device',
                          child: Text('设备专属私钥'),
                        ),
                      ],
                      onChanged: (_) => mutations++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(ConnectSelectionField<String>);
        final bounds = tester.getRect(field);
        expect(bounds.height, scenario.$2 == 1 ? 56 : greaterThan(56));
        expect(
          tester.getRect(find.text('ADB 私钥')).top,
          greaterThanOrEqualTo(bounds.top),
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(mutations, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('selection fields keep labels inside and grow for large text', (
    tester,
  ) async {
    for (final scenario in [(370.0, 1.0), (248.0, 2.0)]) {
      var selected = 'modern';
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: scenario.$1,
                child: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scenario.$2),
                  ),
                  child: StatefulBuilder(
                    builder: (context, update) => ConnectSelectionField<String>(
                      label: '连接方式',
                      value: selected,
                      icon: const Icon(Icons.expand_more, size: 16),
                      items: const [
                        DropdownMenuItem(
                          value: 'modern',
                          child: Text('现代无线调试（加密）'),
                        ),
                        DropdownMenuItem(
                          value: 'legacy',
                          child: Text('旧版 TCP（USB 授权后开启）'),
                        ),
                      ],
                      onChanged: (next) => update(() => selected = next!),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(ConnectSelectionField<String>);
      final fieldBounds = tester.getRect(field);
      expect(fieldBounds.height, scenario.$2 == 1 ? 56 : greaterThan(56));
      final labelBounds = tester.getRect(find.text('连接方式'));
      expect(labelBounds.top, greaterThanOrEqualTo(fieldBounds.top));
      expect(labelBounds.bottom, lessThanOrEqualTo(fieldBounds.bottom));
      expect(tester.takeException(), isNull);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('旧版 TCP（USB 授权后开启）').last);
      await tester.pumpAndSettle();
      expect(selected, 'legacy');
      final selectedBounds = tester.getRect(find.text('旧版 TCP（USB 授权后开启）'));
      final updatedBounds = tester.getRect(field);
      expect(selectedBounds.top, greaterThanOrEqualTo(updatedBounds.top));
      expect(selectedBounds.bottom, lessThanOrEqualTo(updatedBounds.bottom));
      expect(tester.takeException(), isNull);
    }
  });

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

  testWidgets(
    'floating navigation keeps its standard height and grows for large text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = 0;
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ConnectTokens.theme(brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 280,
                    child: Builder(
                      builder: (context) => officialGlassNavigation(
                        context,
                        selectedIndex: selected,
                        onTabSelected: (index) => selected = index,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final navigationHeight = tester
              .getSize(find.byType(GlassTabBar))
              .height;
          expect(navigationHeight, scale == 1 ? 64 : greaterThan(64));
          for (final label in ['设备', '传输', '设置']) {
            final button = find.bySemanticsLabel(label);
            final size = tester.getSize(button);
            expect(size.width, greaterThanOrEqualTo(44));
            expect(size.height, greaterThanOrEqualTo(44));
          }
          await tester.tap(find.bySemanticsLabel('传输'));
          expect(selected, 1);
        }
      }
      semantics.dispose();
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

  testWidgets('unsupported renderer retains the frosted material', (
    tester,
  ) async {
    // 组件测试渲染器不支持 Impeller 着色器图像过滤；生产着色器分支由设备渲染检查覆盖。
    expect(ImageFilter.isShaderFilterSupported, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        home: const Center(child: Glass(child: Text('可用控制'))),
      ),
    );

    expect(find.byType(liquid.AdaptiveGlass), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('可用控制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('press cancellation and disabling cannot commit a stale action', (
    tester,
  ) async {
    var activations = 0;
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: officialGlassIconButton(
                context,
                icon: const Icon(Icons.add),
                label: '添加',
                onPressed: enabled ? () => activations++ : null,
              ),
            );
          },
        ),
      ),
    );
    final button = find.byType(GlassIconButton);
    final initial = tester.getRect(button);
    final cancelled = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 16));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(activations, 0);
    expect(tester.getRect(button), initial);

    final interrupted = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 16));
    rebuild(() {
      enabled = false;
    });
    await tester.pump();
    await interrupted.up();
    await tester.pumpAndSettle();
    expect(activations, 0);
    rebuild(() {
      enabled = true;
    });
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(activations, 1);
    expect(tester.getRect(button), initial);
    expect(tester.takeException(), isNull);
  });
  testWidgets('navigation retargets continuously and reducing motion snaps', (
    tester,
  ) async {
    var selected = 0;
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                child: SizedBox(
                  width: 280,
                  child: Builder(
                    builder: (context) => officialGlassNavigation(
                      context,
                      selectedIndex: selected,
                      onTabSelected: (index) =>
                          setState(() => selected = index),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final indicator = find.byType(liquid.AnimatedGlassIndicator).first;
    double alignment() => tester
        .widget<liquid.AnimatedGlassIndicator>(indicator)
        .alignment
        .resolve(TextDirection.ltr)
        .x;
    final initial = alignment();
    final bar = tester.getRect(find.byType(GlassTabBar));
    await tester.tapAt(Offset(bar.left + bar.width * 5 / 6, bar.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    final moving = alignment();
    expect(moving, greaterThan(initial));
    expect(moving, lessThan(1));
    await tester.tapAt(bar.center);
    await tester.pump();
    expect(alignment(), closeTo(moving, .01));
    update(() => reduced = true);
    await tester.pump();
    expect(alignment(), closeTo(0, .01));
    await tester.pump(const Duration(seconds: 1));
    expect(alignment(), closeTo(0, .01));
    expect(tester.takeException(), isNull);
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
  testWidgets(
    'reduced-motion menu opens immediately and keeps actions reachable',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(2),
            ),
            child: TooltipVisibility(visible: false, child: child!),
          ),
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
                ],
              ),
            ),
          ),
        ),
      );
      final trigger = find.descendant(
        of: find.byType(GlassMenuButton),
        matching: find.byType(IconButton),
      );
      await tester.tap(trigger);
      await tester.pump();
      expect(find.text('设备详情'), findsOneWidget);
      expect(
        tester.getSize(find.byType(MenuItemButton)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text('设备详情'), findsNothing);
      expect(activations, 0);
      await tester.tap(trigger);
      await tester.pump();
      await tester.tap(find.text('设备详情'));
      await tester.pump();
      expect(activations, 1);
      expect(find.text('设备详情'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
