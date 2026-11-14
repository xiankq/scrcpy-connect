import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/window_environment_scope.dart';

void main() {
  testWidgets('freeform desktop windows keep the workspace toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(720, 900)),
          child: WindowEnvironmentScope(
            readHostEnvironment: () async => const WindowEnvironment(
              width: 720,
              height: 900,
              mode: WindowMode.freeform,
              windowId: 'desktop:window-7',
            ),
            watchHostEnvironment: () => const Stream.empty(),
            child: const PageFrame(
              root: true,
              title: '设备',
              child: Center(child: Text('内容')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('freeform desktop detail pages keep workspace chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(720, 900)),
          child: WindowEnvironmentScope(
            readHostEnvironment: () async => const WindowEnvironment(
              width: 720,
              height: 900,
              mode: WindowMode.freeform,
              windowId: 'desktop:window-8',
            ),
            watchHostEnvironment: () => const Stream.empty(),
            child: PageFrame(
              title: '设备详情',
              root: false,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('设备详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact navigation keeps the title plane opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: WindowEnvironmentScope(
            readHostEnvironment: () async => const WindowEnvironment(
              width: 390,
              height: 844,
              windowId: 'phone:window-1',
            ),
            watchHostEnvironment: () => const Stream.empty(),
            child: const PageFrame(
              root: true,
              title: '设备',
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassSurfaceGroup), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
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
                root: true,
                title: '设备',
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

    expect(find.byType(GlassVerticalToolbarGroup), findsOneWidget);
    expect(find.byKey(actionKey), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(actionKey)).dx, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo navigation shell exposes its side bar to page chrome', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(402, 874),
          viewPadding: EdgeInsets.only(right: 84),
        ),
        child: MaterialApp(
          home: liquid.GlassNavigationShell(
            child: PageFrame(
              root: true,
              title: '设备',
              actions: [
                IconButton(
                  key: const ValueKey('duo-shell-action'),
                  onPressed: null,
                  icon: const Icon(Icons.add),
                ),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassVerticalToolbarGroup), findsOneWidget);
    expect(find.byKey(const ValueKey('duo-shell-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo side bar also owns a trailing text action', (tester) async {
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

    expect(find.byType(GlassVerticalToolbarGroup), findsOneWidget);
    expect(find.byKey(const ValueKey('duo-trailing-action')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('duo-trailing-action'))).dx,
      greaterThan(300),
    );
    expect(tester.takeException(), isNull);
  });
}
