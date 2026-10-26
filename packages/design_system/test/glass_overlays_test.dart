import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

Finder ancestors(Finder child, Type type) =>
    find.ancestor(of: child, matching: find.byType(type));

Future<void> openModal(
  WidgetTester tester,
  Future<void> Function(BuildContext) onPressed, {
  bool reduced = false,
  ValueNotifier<bool>? highContrast,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ConnectTokens.theme(Brightness.dark),
      builder: (context, child) => ListenableBuilder(
        listenable: Listenable.merge([highContrast]),
        builder: (context, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(reduced ? 2 : 1),
            highContrast: highContrast?.value ?? false,
          ),
          child: child!,
        ),
      ),
      home: GlassPreferences(
        reduceTransparency: reduced,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'alert retains arbitrary actions and route-local opaque preferences',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? result;
      await openModal(tester, (context) async {
        result = await showGlassDialog<int>(
          context: context,
          builder: (context) => GlassAlertDialog(
            title: const Text.rich(
              TextSpan(
                text: '选择操作',
                children: [TextSpan(text: '类型')],
              ),
            ),
            content: const Text('保留全部可用操作，文字放大后可滚动访问。'),
            actions: [
              for (var i = 0; i < 4; i++)
                TextButton(
                  onPressed: () => Navigator.pop(context, i),
                  child: Text('执行操作 $i'),
                ),
            ],
          ),
        );
      }, reduced: true);
      expect(find.byType(liquid.GlassContainer), findsNothing);
      expect(find.byType(liquid.AdaptiveGlass), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final surface = find.byType(Glass);
      expect(
        GlassPreferences.reduced(tester.element(surface)),
        isTrue,
        reason: 'A modal route must retain the invoking subtree preference.',
      );
      final plane = ancestors(surface, GlassSurfaceGroup);
      expect(plane, findsOneWidget);
      expect(tester.getRect(plane), tester.getRect(surface));
      await tester.ensureVisible(find.text('执行操作 3'));
      await tester.tap(find.text('执行操作 3'));
      await tester.pumpAndSettle();
      expect(result, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sheet keeps result and externally owned scrolling controller', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final highContrast = ValueNotifier(false);
    addTearDown(highContrast.dispose);
    int? result;
    await openModal(tester, (context) async {
      result = await showGlassModalSheet<int>(
        context: context,
        constraints: const BoxConstraints(maxHeight: 260),
        builder: (context) => ListView(
          controller: controller,
          shrinkWrap: true,
          children: [
            for (var i = 0; i < 8; i++) ListTile(title: Text('操作 $i')),
            TextButton(
              onPressed: () => Navigator.pop(context, 7),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }, highContrast: highContrast);
    expect(controller.hasClients, isTrue);
    expect(
      tester
          .widget<liquid.AdaptiveGlass>(find.byType(liquid.AdaptiveGlass))
          .quality,
      isNot(liquid.GlassQuality.minimal),
    );
    final sheetClip = tester.widget<ClipRSuperellipse>(
      ancestors(find.text('操作 0'), ClipRSuperellipse),
    );
    expect(
      sheetClip.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(DesignTokens.componentSheetRounded),
      ),
      reason: 'The sheet keeps its rounded top and open bottom edge.',
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final scroll = find.byType(Scrollable);
    final state = tester.state(scroll);
    final offset = controller.offset;
    for (final value in [true, false]) {
      highContrast.value = value;
      await tester.pumpAndSettle();
      expect(
        find.byType(liquid.AdaptiveGlass),
        value ? findsNothing : findsOneWidget,
      );
      expect(tester.state(scroll), same(state));
      expect(controller.offset, offset);
      expect(controller.positions, hasLength(1));
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller,
        same(controller),
      );
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, 7);
    expect(controller.hasClients, isFalse);
    // 路由不拥有该控制器；关闭路由后控制器仍可使用。
    controller.addListener(() {});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible tooltip preserves its semantics and passes taps and drags through',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      var dragUpdates = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    onPanUpdate: (_) => dragUpdates++,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
                const Center(
                  child: GlassSurfaceGroup(
                    child: GlassTooltip(
                      message: '查看来源文件',
                      triggerMode: TooltipTriggerMode.manual,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.info),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.semantics
            .byPredicate((node) => node.getSemanticsData().tooltip == '查看来源文件')
            .evaluate(),
        hasLength(1),
      );
      final tooltip = tester.state<TooltipState>(find.byType(Tooltip));
      tooltip.ensureTooltipVisible();
      await tester.pumpAndSettle();
      final materialization = tester.widget<liquid.GlassMaterializeTransition>(
        find.byType(liquid.GlassMaterializeTransition),
      );
      final localPlane = ancestors(
        find.byType(liquid.GlassContainer),
        GlassSurfaceGroup,
      ).first;
      expect(
        tester.getRect(localPlane),
        tester.getRect(find.byType(liquid.GlassContainer)),
        reason: 'A toolbar tooltip must own its overlay sampling plane.',
      );
      final ambientFade = tester.widget<FadeTransition>(
        ancestors(
          find.byType(liquid.GlassMaterializeTransition),
          FadeTransition,
        ).first,
      );
      expect(materialization.animation, same(ambientFade.opacity));
      expect(
        materialization.scaleFrom,
        DesignTokens.componentGlassMaterializeScale,
      );
      final bubble = tester.getCenter(find.text('查看来源文件'));
      await tester.tapAt(bubble);
      await tester.pumpAndSettle();
      expect(taps, 1);
      tooltip.ensureTooltipVisible();
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(find.text('查看来源文件')),
        const Offset(50, 0),
      );
      await tester.pumpAndSettle();
      expect(dragUpdates, greaterThan(0));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
