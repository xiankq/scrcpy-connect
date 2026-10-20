import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/index/widgets/device_card.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _device = {'id': 'phone', 'name': '我的 Android 手机', 'status': 'connected'};

Future<Json> _request(String command, [Json params = const {}]) async =>
    switch (command) {
      'devices.list' => {
        'devices': [_device],
      },
      'device.capabilities' => {
        'capabilities': [
          {'id': 'screen', 'status': 'available'},
          {'id': 'files', 'status': 'available'},
          {'id': 'audio', 'status': 'limited'},
        ],
      },
      'session.list' => {
        'sessions': [
          {'deviceId': 'phone', 'status': 'paused', 'sessionId': 'retained'},
          {'deviceId': 'phone', 'status': 'stopped', 'sessionId': 'stopped'},
          {'deviceId': 'another', 'status': 'paused', 'sessionId': 'other'},
        ],
      },
      _ => {},
    };

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  Widget page,
  Size parent,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    controller.dispose();
  });
  await tester.pumpWidget(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: parent.width,
        height: parent.height,
        child: RouterTestApp(
          controller: controller,
          devices: const [_device],
          theme: ConnectTokens.theme(Brightness.light),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('action rows are 56 high and grow for enlarged multiline text', (
    tester,
  ) async {
    var taps = 0;
    Future<void> pumpRow(String title, double scale) => tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 248,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: ActionRow(
                  icon: LucideIcons.folder,
                  title: title,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpRow('文件管理', 1);
    expect(tester.getSize(find.byType(ActionRow)).height, 56);
    final badge = find.byType(ListIconBadge);
    expect(tester.getSize(badge), const Size(28, 28));
    expect(
      tester.widget<ListIconBadge>(badge).backgroundColor,
      DesignTokens.colorListIconAmber,
    );
    expect(
      tester
          .widget<Icon>(find.descendant(of: badge, matching: find.byType(Icon)))
          .color,
      DesignTokens.componentListIconTextColor,
    );
    expect(
      tester.getTopLeft(find.text('文件管理')).dx - tester.getTopRight(badge).dx,
      12,
    );
    await tester.tap(find.text('文件管理'));
    expect(taps, 1);
    await pumpRow('很长的设备功能名称需要在窄容器内完整换行', 2);
    expect(tester.getSize(find.byType(ActionRow)).height, greaterThan(56));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('很长的设备功能名称需要在窄容器内完整换行'));
    expect(taps, 2);
  });

  test('offline identity shows its real connection time', () {
    final label = deviceConnectionLabel({
      'status': 'offline',
      'lastSeen': DateTime(2026, 10, 19, 9, 42).millisecondsSinceEpoch ~/ 1000,
    });
    expect(label, '离线 · 上次连接 2026/10/19 09:42');
    expect(deviceConnectionLabel({'status': 'unauthorized'}), '需要重新授权');
    expect(deviceConnectionLabel({'status': 'checking'}), '正在检查');
  });

  for (final size in [const Size(280, 620), const Size(620, 280)]) {
    testWidgets('last device stays reachable at $size with enlarged text', (
      tester,
    ) async {
      final controller = createTestController(_request);
      controller.devices = [
        for (var index = 0; index < 9; index++)
          {
            'id': 'device-$index',
            'name': '设备 $index 很长的设备名称',
            'status': index == 8 ? 'offline' : 'connected',
            'lastSeen': 1792374120,
          },
      ];
      await _pump(
        tester,
        controller,
        Scaffold(body: DevicesPage(controller: controller)),
        size,
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('设备 8 很长的设备名称'),
        300,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      final more = find.text('设备 8 很长的设备名称');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      expect(more.hitTestable(), findsOneWidget);
      expect(more.hitTestable(), findsOneWidget);
      final card = find.ancestor(of: more, matching: find.byType(DeviceCard));
      expect(tester.getSize(card).height, greaterThanOrEqualTo(108));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'workspace context and final action remain reachable at $size',
      (tester) async {
        final controller = createTestController(_request);
        controller.devices = [_device];
        await _pump(
          tester,
          controller,
          DeviceWorkspacePage(controller: controller, device: _device),
          size,
        );
        expect(find.text('已连接'), findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(find.text('打开手机屏幕')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        expect(find.text('打开手机屏幕').hitTestable(), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.byType(FilledButton).first,
        );
        expect(button.onPressed, isNotNull);
        await tester.scrollUntilVisible(
          find.text('功能支持状态'),
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('功能支持状态')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        expect(find.text('功能支持状态').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('every device card enters the combined workspace', (
    tester,
  ) async {
    final controller = createTestController(_request);
    controller.devices = [_device];
    await _pump(
      tester,
      controller,
      Scaffold(body: DevicesPage(controller: controller)),
      const Size(393, 852),
    );
    expect(find.text('设备详情'), findsNothing);
    await tester.tap(find.text('我的 Android 手机'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceWorkspacePage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('移除此设备'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    expect(find.text('移除此设备').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unavailable background apps retain the screen action', (
    tester,
  ) async {
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      throw const RequestFailure('unavailable', '暂时无法核验');
    });
    controller.devices = [_device];
    await _pump(
      tester,
      controller,
      DeviceWorkspacePage(controller: controller, device: _device),
      const Size(393, 852),
    );
    expect(find.text('暂时无法读取后台应用'), findsOneWidget);
    expect(find.text('没有已启动的应用'), findsNothing);
    expect(find.text('打开手机屏幕'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
