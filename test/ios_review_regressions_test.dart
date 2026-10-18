import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/rendering.dart';

import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ios_pages_capture_test.dart' show fixtureRequest, pageFixtures;
import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('add-device content has no adjacent duplicate separators', (
    tester,
  ) async {
    final controller = createTestController(fixtureRequest);
    await controller.initialize();
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: pageFixtures(controller)['add_device']!,
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byType(ContentPanel).first;
    final positions =
        find
            .descendant(of: panel, matching: find.byType(Divider))
            .evaluate()
            .map(
              (element) => tester.getCenter(find.byWidget(element.widget)).dy,
            )
            .toList()
          ..sort();
    for (var i = 1; i < positions.length; i++) {
      expect(
        positions[i] - positions[i - 1],
        greaterThanOrEqualTo(DesignTokens.componentIconButtonSize),
      );
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'guide and import feature icons remain square under list constraints',
    (tester) async {
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      for (final page in ['document_import', 'usb_guide', 'wireless_guide']) {
        await tester.pumpWidget(
          RouterTestApp(
            key: ValueKey(page),
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: pageFixtures(controller)[page]!,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(FeatureIcon).first),
          const Size.square(DesignTokens.componentFeatureIconSize),
          reason: page,
        );
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'call state is localized and reject text is readable in ${brightness.name}',
      (tester) async {
        final controller = createTestController(fixtureRequest);
        await controller.initialize();
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(brightness),
            home: pageFixtures(controller)['calls']!,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的手机 · 来电响铃'), findsOneWidget);
        await tester.ensureVisible(find.text('拒接'));
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '拒接'),
        );
        final background = button.style!.backgroundColor!.resolve({})!;
        final foreground = DefaultTextStyle.of(tester.element(find.text('拒接')))
            .style
            .color!;
        final light = math.max(
          background.computeLuminance(),
          foreground.computeLuminance(),
        );
        final dark = math.min(
          background.computeLuminance(),
          foreground.computeLuminance(),
        );
        expect((light + .05) / (dark + .05), greaterThanOrEqualTo(4.5));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
  testWidgets('narrow large text keeps device status on one readable line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 620);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final controller = createTestController(fixtureRequest);
    await controller.initialize();
    await tester.pumpWidget(
      TestProviderScope(controller: controller, child: const ConnectApp()),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(find.text('已连接'));
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
      ),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'short landscape initially shows the complete first device above navigation',
    (tester) async {
      tester.view.physicalSize = const Size(620, 280);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(DeviceCard).first).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(GlassTabBar)).top),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'domain status, quality units and startup error remain understandable',
    (tester) async {
      final controller = createTestController(fixtureRequest);
      await controller.initialize();
      for (final entry in {
        'sessions': '运行中',
        'quality': '8 Mbps',
        'startup_error': '无法读取本机设备连接配置',
      }.entries) {
        await tester.pumpWidget(
          RouterTestApp(
            key: ValueKey(entry.key),
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: pageFixtures(controller)[entry.key]!,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.textContaining('Bad state:'), findsNothing);
      }
      expect(sessionStatusText('running'), '运行中');
      expect(statusText('running'), '传输中');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'empty connect and pairing fields explain validation without submitting',
    (tester) async {
      final requests = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add(command);
        return {};
      });
      for (final entry in {
        'connection_form': '连接设备',
        'pairing_form': '配对并检查连接',
      }.entries) {
        await tester.pumpWidget(
          RouterTestApp(
            key: ValueKey(entry.key),
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: pageFixtures(controller)[entry.key]!,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(entry.value));
        await tester.tap(find.text(entry.value));
        await tester.pumpAndSettle();
        expect(find.text('请输入被控手机的地址'), findsOneWidget);
        expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
        if (entry.key == 'pairing_form')
          expect(find.text('请输入六位配对码'), findsOneWidget);
      }
      expect(
        requests.where(
          (command) => ['devices.connect', 'devices.pair'].contains(command),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
