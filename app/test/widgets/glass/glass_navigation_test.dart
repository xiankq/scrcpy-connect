import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui' show SemanticsAction;

import 'package:flutter_test/flutter_test.dart';

import 'support/official_glass_controls.dart';

void main() {
  testWidgets(
    'navigation exposes one actionable destination and follows its host',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return officialGlassNavigation(
                      context,
                      selectedIndex: selected,
                      onTabSelected: (index) =>
                          setState(() => selected = index),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['设备', '传输', '设置']) {
        final destination = find.bySemanticsLabel(label);
        expect(destination, findsOneWidget);
        expect(
          tester
              .getSemantics(destination)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      }
      final target = tester.getSemantics(find.bySemanticsLabel('设置'));
      target.owner!.performAction(target.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(selected, 2);
      update(() => selected = 0);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(GlassTabBar));
      // 外部路由恢复后，重新选择当前标签仍须保留可点击区域，且其他目标仍可访问。
      await tester.tapAt(Offset(bar.left + bar.width / 6, bar.center.dy));
      await tester.pumpAndSettle();
      expect(selected, 0);
      await tester.tapAt(bar.center);
      await tester.pumpAndSettle();
      expect(selected, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'changing transparency and contrast preserves a focused destination',
    (tester) async {
      var selected = 0;
      var opaque = false;
      var contrast = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(highContrast: contrast),
                child: GlassPreferences(
                  reduceTransparency: opaque,
                  child: Scaffold(
                    body: Center(
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
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('传输').first)).requestFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      for (final next in [(true, false), (false, true), (false, false)]) {
        update(() {
          opaque = next.$1;
          contrast = next.$2;
        });
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focused));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(selected, 1);
      }
    },
  );
}
