import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/settings/appearance/settings_appearance_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final paneHeight in [620.0, 280.0]) {
    testWidgets(
      'large text header fits a narrow pane of height $paneHeight on desktop',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final controller = createTestController(
          (command, [params = const {}]) async => {},
        );
        addTearDown(controller.dispose);
        var confirmed = false;
        await tester.pumpWidget(
          TestProviderScope(
            controller: controller,
            child: MaterialApp(
              theme: ConnectTokens.theme(Brightness.light),
              home: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 280,
                  height: paneHeight,
                  child: PageFrame(
                    title: '连接与已授权设备的详细设置',
                    bottom: FilledButton(
                      onPressed: () => confirmed = true,
                      child: const Text('保存设置'),
                    ),
                    child: ListView(children: const [Text('设备连接偏好')]),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(PageFrame)), Size(280, paneHeight));
        expect(tester.takeException(), isNull);
        expect(find.text('保存设置').hitTestable(), findsOneWidget);
        await tester.tap(find.text('保存设置'));
        expect(confirmed, isTrue);
      },
    );
  }

  testWidgets(
    'device switches default independently and save only that device',
    (tester) async {
      final updates = <Map<String, dynamic>>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'settings.update') updates.add(Map.of(params));
        return {};
      });
      addTearDown(controller.dispose);
      controller.settings = {
        'deviceSettings': {
          'other': {'clipboardSync': true, 'showNavigationBar': false},
        },
      };
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DeviceWorkspacePage(
            controller: controller,
            device: const {'id': 'phone', 'name': '手机'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final clipboard = find.widgetWithText(ConnectSwitchRow, '自动同步剪贴板');
      final navigation = find.widgetWithText(ConnectSwitchRow, '显示导航键');
      await tester.scrollUntilVisible(clipboard, 200);
      expect(tester.widget<ConnectSwitchRow>(clipboard).value, isFalse);
      expect(tester.widget<ConnectSwitchRow>(navigation).value, isTrue);
      await tester.tap(clipboard);
      await tester.pumpAndSettle();
      await tester.ensureVisible(navigation);
      await tester.tap(navigation);
      await tester.pumpAndSettle();
      expect(updates, hasLength(2));
      expect(controller.settings['deviceSettings'], {
        'other': {'clipboardSync': true, 'showNavigationBar': false},
        'phone': {'clipboardSync': true, 'showNavigationBar': false},
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(280, 620), const Size(620, 280)]) {
    testWidgets('appearance and IP connection remain reachable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = createTestController(
        (command, [params = const {}]) async => {},
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: AppearancePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('跟随系统'), 100);
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      expect(controller.settings['appearance'], 'system');
      expect(find.byType(ConnectSwitchRow), findsNothing);
      expect(tester.takeException(), isNull);

      // Rebuild with a new router to exercise the public method selection.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: AddDevicePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('IP连接'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('IP连接')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('IP连接').hitTestable(), findsOneWidget);
      await tester.tap(find.text('IP连接'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      final portField = find.widgetWithText(TextFormField, '连接端口');
      final verticalScroll = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        portField,
        100,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(portField).controller!.text, '5555');
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height > 300 ? 220 : 80,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('连接设备'),
        100,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接设备').hitTestable(), findsOneWidget);
      tester.view.resetViewInsets();
      expect(tester.takeException(), isNull);
    });
  }
}
