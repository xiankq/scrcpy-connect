import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// ignore: depend_on_referenced_packages
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import '../../packages/design_system/test/support/official_glass_controls.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'public navigation lens rests, yields to drag and becomes solid',
    (tester) async {
      binding.reportData = {
        'navigationLensComplete': false,
        'shaderSupported': true,
      };
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
      await tester.runAsync(GlassMaterial.initialize);
      final key = GlobalKey<_SceneState>();
      await tester.pumpWidget(GlassMaterial.wrap(child: _Scene(key: key)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsOneWidget,
      );
      await binding.convertFlutterSurfaceToImage();

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 100));
        await binding.callbackManager.takeScreenshot('$name-drain');
        await tester.pump(const Duration(milliseconds: 100));
        await binding.takeScreenshot(name);
        expect(tester.takeException(), isNull);
      }

      await capture('rest');
      final start = tester.getCenter(find.text('设备').first);
      final end = tester.getCenter(find.text('设置').first);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsNothing,
      );
      await capture('held');
      await gesture.moveTo(Offset((start.dx + end.dx) / 2, start.dy));
      await tester.pump(const Duration(milliseconds: 100));
      await capture('drag');
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsNothing,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.selected, 2);
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsOneWidget,
      );
      await capture('returned');

      key.currentState!.scroll.jumpTo(193);
      await tester.pumpAndSettle();
      await capture('scroll');
      key.currentState!.configure(opaque: true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsNothing,
      );
      expect(find.byType(liquid.LiquidGlassLayer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('传输').first);
      await tester.pumpAndSettle();
      expect(key.currentState!.selected, 1);
      await capture('opaque');

      key.currentState!.configure(opaque: false, reduced: true);
      await tester.pumpAndSettle();
      final lens = tester.widget<liquid.AnimatedGlassIndicator>(
        find.byKey(const ValueKey('resting-navigation-lens')),
      );
      expect(lens.pinchStrength, 0);
      expect(lens.expansion, EdgeInsets.zero);
      final reducedGesture = await tester.startGesture(
        tester.getCenter(find.text('设备').first),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsNothing,
      );
      final activeLenses = tester
          .widgetList<liquid.AnimatedGlassIndicator>(
            find.byType(liquid.AnimatedGlassIndicator),
          )
          .where((value) => value.paintGlass && value.thickness > .05)
          .toList();
      expect(activeLenses, hasLength(1));
      expect(activeLenses.single.expansion, EdgeInsets.zero);
      expect(activeLenses.single.pinchStrength, 0);
      await capture('reduced-motion-held');
      await reducedGesture.up();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resting-navigation-lens')),
        findsOneWidget,
      );
      expect(key.currentState!.selected, 0);
      await capture('reduced-motion');
      binding.reportData!['navigationLensComplete'] = true;
    },
  );
}

class _Scene extends StatefulWidget {
  const _Scene({super.key});
  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  final scroll = ScrollController();
  int selected = 0;
  bool opaque = false;
  bool reduced = false;

  void configure({required bool opaque, bool reduced = false}) => setState(() {
    this.opaque = opaque;
    this.reduced = reduced;
  });

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ConnectTokens.theme(Brightness.light),
    home: GlassPreferences(
      reduceTransparency: opaque,
      child: liquid.GlassAccessibilityScope(
        reduceMotion: reduced,
        child: Builder(
          builder: (context) => Scaffold(
            extendBody: true,
            body: ListView.builder(
              controller: scroll,
              itemCount: 50,
              itemBuilder: (_, index) => ListTile(
                tileColor: index.isEven
                    ? Colors.white
                    : const Color(0xffd7dfed),
                leading: const Icon(Icons.folder),
                title: Text('文件 $index — 实际滚动内容'),
                subtitle: const Text('同一滚动视口延伸至导航后方'),
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: officialGlassNavigation(
                  context,
                  selectedIndex: selected,
                  onTabSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
