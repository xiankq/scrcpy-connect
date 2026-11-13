import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/platform/window_environment.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
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
}
