import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

void main() {
  testWidgets(
    'alert preserves keyboard focus, route result and narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? result;
      ModalRoute<dynamic>? alertRoute;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showGlassDialog<String>(
                    context: context,
                    builder: (context) {
                      alertRoute = ModalRoute.of(context);
                      return GlassAlertDialog(
                        title: const Text('编辑文件夹名称'),
                        content: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(autofocus: true),
                            Text('说明内容随文字放大与键盘缩小视口后，仍可滚动访问所有操作。'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, 'saved'),
                            child: const Text('保存'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        alertRoute!.traversalEdgeBehavior,
        TraversalEdgeBehavior.closedLoop,
      );
      expect(find.byType(liquid.GlassMaterializeTransition), findsOneWidget);
      expect(find.byType(liquid.AdaptiveGlass), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), '新名称');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, 'saved');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'alert retains arbitrary actions and route-local opaque preferences',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: GlassPreferences(
            reduceTransparency: true,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
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
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(liquid.GlassCard), findsNothing);
      expect(find.byType(liquid.AdaptiveGlass), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final surface = find.byType(Glass);
      expect(
        GlassPreferences.reduced(tester.element(surface)),
        isTrue,
        reason: 'A modal route must retain the invoking subtree preference.',
      );
      final plane = find.ancestor(
        of: surface,
        matching: find.byType(GlassSurfaceGroup),
      );
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
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showGlassModalSheet<int>(
                  context: context,
                  constraints: const BoxConstraints(maxHeight: 260),
                  builder: (context) => ListView(
                    controller: controller,
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < 8; i++)
                        ListTile(title: Text('操作 $i')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, 7),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(controller.hasClients, isTrue);
    expect(find.byType(liquid.GlassSheet), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    final sheetClip = tester.widget<ClipRSuperellipse>(
      find.ancestor(
        of: find.text('操作 0'),
        matching: find.byType(ClipRSuperellipse),
      ),
    );
    expect(
      sheetClip.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(DesignTokens.componentSheetRounded),
      ),
      reason:
          'Opaque fallback keeps the same open bottom edge as native glass.',
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, 7);
    expect(controller.hasClients, isFalse);
    // A route never owns this controller; it remains usable after dismissal.
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
      final localPlane = find
          .ancestor(
            of: find.byType(Glass),
            matching: find.byType(GlassSurfaceGroup),
          )
          .first;
      expect(
        tester.getRect(localPlane),
        tester.getRect(find.byType(Glass)),
        reason: 'A toolbar tooltip must own its overlay sampling plane.',
      );
      final ambientFade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(liquid.GlassMaterializeTransition),
              matching: find.byType(FadeTransition),
            )
            .first,
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

  testWidgets('reduced-motion menu owns an overlay plane with menu bounds', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: TooltipVisibility(visible: false, child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlassSurfaceGroup(
                child: GlassToolbarGroup(
                  children: [
                    GlassMenuButton(
                      icon: const Icon(Icons.more_horiz),
                      tooltip: '更多',
                      actions: [
                        GlassMenuAction(
                          label: '设备详情',
                          onPressed: () => activations++,
                        ),
                        const GlassMenuAction(label: '暂不可用', onPressed: null),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    final menu = find
        .ancestor(of: find.text('设备详情'), matching: find.byType(Glass))
        .first;
    final nearestPlane = find
        .ancestor(of: menu, matching: find.byType(GlassSurfaceGroup))
        .first;
    expect(
      tester.getRect(nearestPlane),
      tester.getRect(menu),
      reason: 'An overlay must sample its own bounds, not its source toolbar plane.',
    );
    expect(find.text('设备详情').hitTestable(), findsOneWidget);
    expect(find.text('暂不可用'), findsOneWidget);
    await tester.tap(find.text('设备详情'));
    await tester.pump();
    expect(activations, 1);
    expect(find.text('设备详情'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('press deforms with touch movement and reverses continuously', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassPressFeedback(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );
    final target = find.byType(GlassPressFeedback);
    Matrix4 matrix() => tester
        .widget<Transform>(
          find.descendant(of: target, matching: find.byType(Transform)),
        )
        .transform;
    final original = matrix().clone();
    final first = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(matrix().entry(0, 0), greaterThan(1));
    await first.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(matrix().entry(0, 0), greaterThan(matrix().entry(1, 1)));
    await first.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final settling = matrix().clone();
    final second = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    expect(matrix().entry(0, 0), closeTo(settling.entry(0, 0), .0001));
    await second.up();
    await tester.pumpAndSettle();
    expect(matrix(), original);
    expect(taps, 1);
  });

  testWidgets(
    'reduced motion retains light feedback without spatial deformation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(
              child: GlassPressFeedback(child: SizedBox(width: 80, height: 80)),
            ),
          ),
        ),
      );
      final target = find.byType(GlassPressFeedback);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(25, 10));
      await tester.pumpAndSettle();
      final transform = tester.widget<Transform>(
        find.descendant(of: target, matching: find.byType(Transform)),
      );
      expect(transform.transform, Matrix4.identity());
      final overlay = tester.widget<DecoratedBox>(
        find.descendant(of: target, matching: find.byType(DecoratedBox)),
      );
      expect((overlay.decoration as ShapeDecoration).color!.a, greaterThan(0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
