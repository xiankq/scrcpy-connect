import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';
import 'package:scrcpy_connect/widgets/workspace_panes.dart';

void main() {
  testWidgets('独立页头动作在手机和桌面保留各自的圆面和点击范围', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final tapped = <String>[];
    for (final (width, brightness, opaque) in [
      (320.0, Brightness.light, false),
      (1120.0, Brightness.dark, true),
    ]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: GlassPreferences(
            reduceTransparency: opaque,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(width < 400 ? 2 : 1)),
                child: PageFrame(
                  root: true,
                  title: '设备',
                  actions: [
                    IconButton(
                      tooltip: '远控窗口',
                      onPressed: () => tapped.add('远控窗口'),
                      icon: const Icon(Icons.layers),
                    ),
                    IconButton(
                      tooltip: '添加设备',
                      onPressed: () => tapped.add('添加设备'),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final surfaces = find.byType(Glass);
      expect(surfaces, findsNWidgets(2));
      for (final label in ['远控窗口', '添加设备']) {
        final action = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == label,
        );
        final surface = find.ancestor(of: action, matching: surfaces);
        expect(tester.getSize(surface), const Size.square(44));
        expect(tester.getSize(action), const Size.square(44));
        expect(tester.widget<Glass>(surface).circular, isTrue);
        if (opaque) {
          final outline = find.descendant(
            of: surface,
            matching: find.byType(ClipOval),
          );
          expect(tester.getSize(outline), const Size.square(44));
        } else {
          final outline = find.descendant(
            of: surface,
            matching: find.byType(liquid.AdaptiveGlass),
          );
          expect(
            tester.widget<liquid.AdaptiveGlass>(outline).shape,
            isA<liquid.LiquidOval>(),
          );
        }
        await tester.tap(action);
      }
      expect(
        tester.getRect(surfaces.first).right,
        lessThan(tester.getRect(surfaces.last).left),
      );
      expect(tester.takeException(), isNull);
    }
    expect(tapped, ['远控窗口', '添加设备', '远控窗口', '添加设备']);
  });

  testWidgets('明确成组的传输页动作横排共用胶囊，竖栏分别显示圆面', (tester) async {
    final page = PageFrame(
      title: '传输',
      root: true,
      groupHorizontalActions: true,
      actions: [
        IconButton(
          tooltip: '清空记录',
          onPressed: null,
          icon: const Icon(Icons.delete_outline),
        ),
        IconButton(
          tooltip: '刷新任务',
          onPressed: () {},
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(MaterialApp(home: page));
    final surface = find.byType(Glass);
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface), const Size(88, 44));
    expect(tester.widget<Glass>(surface).circular, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: liquid.GlassVerticalBar(
          data: const liquid.GlassVerticalBarData(
            edge: liquid.GlassVerticalBarEdge.trailing,
            width: 84,
            top: 24,
          ),
          child: page,
        ),
      ),
    );
    expect(surface, findsNWidgets(2));
    for (final part in [surface.first, surface.last]) {
      expect(tester.getSize(part), const Size.square(44));
      expect(tester.widget<Glass>(part).circular, isTrue);
    }
  });

  testWidgets('Duo split panes put actions on the physical window edge', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final edge in liquid.GlassVerticalBarEdge.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: liquid.GlassVerticalBar(
            data: liquid.GlassVerticalBarData(edge: edge, width: 120, top: 24),
            child: WorkspacePanes(
              builder: (context, split, useSideToolbar) {
                expect(split, isTrue);
                expect(useSideToolbar, isTrue);
                return (
                  list: const SizedBox.expand(),
                  detail: const SizedBox.expand(),
                  sideActions: [
                    IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.settings),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final actions = find.byType(GlassToolbarGroup);
      expect(actions, findsNWidgets(2));
      final surfaces = find.byType(Glass);
      for (final surface in [surfaces.first, surfaces.last]) {
        expect(tester.getSize(surface), const Size.square(44));
        expect(tester.widget<Glass>(surface).circular, isTrue);
      }
      final x = edge == liquid.GlassVerticalBarEdge.leading ? 42.0 : 1158.0;
      expect(tester.getCenter(actions.first), Offset(x, 46));
      expect(tester.getCenter(actions.last).dx, x);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('自定义页头前置圆键的尺寸独立于返回槽', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PageFrame(
          title: '已选择 2 项',
          leading: GlassToolbarIconButton(
            semanticLabel: '退出选择',
            icon: const Icon(Icons.close),
            onPressed: () {},
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(liquid.GlassIconButton)),
      const Size.square(44),
    );
  });

  testWidgets('正文与底部操作在同一安全窗格内水平居中', (tester) async {
    const bodyKey = ValueKey('page-body');
    const bottomKey = ValueKey('page-bottom');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(padding: const EdgeInsets.only(left: 40)),
              child: const PageFrame(
                title: '连接',
                bottom: SizedBox(key: bottomKey, height: 50),
                child: SizedBox.expand(key: bodyKey),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final body = tester.getRect(find.byKey(bodyKey));
      final bottom = tester.getRect(find.byKey(bottomKey));
      expect(
        body.width,
        width == 1280 ? DesignTokens.componentPageContentMaxWidth : width - 40,
      );
      expect(body.center.dx, (width + 40) / 2);
      expect(bottom.center.dx, body.center.dx);
      expect(bottom.width, body.width - 2 * DesignTokens.spacingMd);
    }
  });

  testWidgets('desktop window titles stay above scrolling content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const cases = [
      (WindowMode.freeform, 'desktop:window-7', true),
      (WindowMode.freeform, 'desktop:window-8', false),
      (WindowMode.fullScreen, 'macos:42', false),
    ];
    for (final (mode, windowId, root) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: WindowEnvironmentScope(
            key: ValueKey(windowId),
            readHostEnvironment: () async => WindowEnvironment(
              width: 720,
              height: 900,
              mode: mode,
              windowId: windowId,
            ),
            watchHostEnvironment: () => const Stream.empty(),
            child: PageFrame(
              root: root,
              title: '设备',
              child: ListView(
                children: [
                  for (var row = 1; row <= 30; row++)
                    SizedBox(height: 64, child: Text('内容 $row')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final title = find.text('设备');
      final row = find.text('内容 5');
      final titleBefore = tester.getRect(title);
      final rowBefore = tester.getTopLeft(row).dy;
      expect(find.byType(AppBar), findsNothing);
      expect(
        tester.getTopLeft(find.byType(ListView)).dy,
        greaterThanOrEqualTo(titleBefore.bottom),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -128));
      await tester.pumpAndSettle();

      expect(tester.getRect(title), titleBefore);
      expect(tester.getTopLeft(row).dy, lessThan(rowBefore - 64));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Duo side bar moves page actions out of the title plane', (
    tester,
  ) async {
    final actionKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(402, 874)),
          child: liquid.GlassVerticalBar(
            data: const liquid.GlassVerticalBarData(
              edge: liquid.GlassVerticalBarEdge.trailing,
              width: 84,
              top: 24,
            ),
            child: WindowEnvironmentScope(
              readHostEnvironment: () async => const WindowEnvironment(
                width: 402,
                height: 874,
                windowId: 'ios:duo-cover',
              ),
              watchHostEnvironment: () => const Stream.empty(),
              child: PageFrame(
                title: '设备',
                onBack: () {},
                actions: [
                  IconButton(
                    key: actionKey,
                    tooltip: '添加设备',
                    onPressed: null,
                    icon: const Icon(Icons.add),
                  ),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final action = find.byType(GlassToolbarGroup);
    final back = find.byType(GlassToolbarIconButton);
    expect(action, findsOneWidget);
    expect(back, findsOneWidget);
    expect(tester.getSize(action), const Size.square(44));
    expect(tester.getSize(back), const Size.square(44));
    expect(tester.getCenter(action).dx, tester.getCenter(back).dx);
    expect(
      tester.getTopLeft(action).dy,
      greaterThan(tester.getBottomLeft(back).dy),
    );
    expect(find.byKey(actionKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(actionKey)).dx, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo navigation shell puts actions inside the system edge', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.viewPadding = const FakeViewPadding(right: 84);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    var opened = false;
    const actionKey = ValueKey('duo-shell-action');
    await tester.pumpWidget(
      MaterialApp(
        home: liquid.GlassNavigationShell(
          child: PageFrame(
            root: true,
            title: '设备',
            actions: [
              IconButton(
                key: actionKey,
                onPressed: () => opened = true,
                icon: const Icon(Icons.add),
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    final action = find.byKey(actionKey);
    expect(tester.getTopLeft(action).dx, greaterThanOrEqualTo(402 - 84));
    expect(tester.getTopRight(action).dx, lessThanOrEqualTo(402));
    expect(
      find.descendant(of: find.byType(AppBar), matching: action),
      findsNothing,
    );
    await tester.tap(action);
    expect(opened, isTrue);
  });

  testWidgets('Duo keeps trailing text actions in the horizontal title row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(402, 874)),
          child: liquid.GlassVerticalBar(
            data: const liquid.GlassVerticalBarData(
              edge: liquid.GlassVerticalBarEdge.trailing,
              width: 84,
              top: 24,
            ),
            child: WindowEnvironmentScope(
              readHostEnvironment: () async => const WindowEnvironment(
                width: 402,
                height: 874,
                windowId: 'ios:duo-trailing-action',
              ),
              watchHostEnvironment: () => const Stream.empty(),
              child: PageFrame(
                title: '发送到设备',
                trailingAction: TextButton(
                  key: const ValueKey('duo-trailing-action'),
                  onPressed: null,
                  child: const Text('取消'),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final action = find.byKey(const ValueKey('duo-trailing-action'));
    expect(find.byType(GlassToolbarGroup), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: action),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
