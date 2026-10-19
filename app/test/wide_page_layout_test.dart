import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/index/widgets/device_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'ios_pages_capture_test.dart' show fixtureRequest;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding();
  tester.view.viewPadding = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

void main() {
  testWidgets(
    'tablet devices route keeps sidebar and centers a reading column',
    (tester) async {
      viewport(tester, const Size(1194, 834));
      final controller = createTestController(fixtureRequest);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(DevicesPage)).left, 244);
      final scroll = find.descendant(
        of: find.byType(DevicesPage),
        matching: find.byType(CustomScrollView),
      );
      expect(tester.getRect(scroll), const Rect.fromLTWH(359, 0, 720, 834));
      expect(tester.getRect(find.byType(DeviceCard).first).left, 375);
      expect(tester.getSize(find.byType(DeviceCard).first).width, 688);
      expect(tester.getRect(find.byType(AppBar)).left, 359);
      expect(tester.getSize(find.byType(AppBar)).width, 720);
      expect(find.text('邻接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop workspace uses root navigator and full-height scrolling',
    (tester) async {
      viewport(tester, const Size(1440, 960));
      final controller = createTestController(fixtureRequest);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(DevicesPage)))
          .push<void>(const WorkspaceRoute(deviceId: 'fixture').location);
      await tester.pumpAndSettle();

      expect(find.text('邻接'), findsNothing);
      expect(
        tester.getRect(find.byType(PageFrame)),
        const Rect.fromLTWH(0, 0, 1440, 960),
      );
      expect(
        tester.getRect(find.byType(GroupedListView)),
        const Rect.fromLTWH(360, 0, 720, 960),
      );
      expect(tester.getRect(find.byType(DeviceHero)).left, 376);
      expect(tester.getSize(find.byType(DeviceHero)).width, 688);
      await tester.drag(find.byType(GroupedListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('功能支持状态').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('page bottom action shares the centered body column', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 960));
    final controller = createTestController(fixtureRequest);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: PageFrame(
          title: '测试页面',
          bottom: FilledButton(onPressed: () {}, child: const Text('继续')),
          child: ListView(
            children: List.generate(
              40,
              (index) => SizedBox(height: 56, child: Text('第 $index 项')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byType(FilledButton));
    final frame = find
        .ancestor(of: find.byType(FilledButton), matching: find.byType(Glass))
        .first;
    expect(tester.getRect(frame).left, 376);
    expect(tester.getSize(frame).width, 688);
    expect(button.left, 376 + DesignTokens.spacingSm);
    expect(button.width, 688 - 2 * DesignTokens.spacingSm);
    expect(button.height, 44);
    expect(tester.getRect(find.byType(ListView)).left, 360);
    expect(tester.getSize(find.byType(ListView)).width, 720);
    expect(
      tester.getRect(find.byType(ListView)),
      const Rect.fromLTWH(360, 0, 720, 960),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(find.text('第 39 项').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
