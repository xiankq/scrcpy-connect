import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_facts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

final _icon = File('../designs/assets/android-settings-api36.png')
    .readAsBytesSync();
Json _iconResult(String id) => {
  'deviceId': id,
  'packageName': 'com.android.settings',
  'userId': 0,
  'mimeType': 'image/png',
  'dataBase64': base64Encode(_icon),
};
const _device = {
  'id': 'phone',
  'name': '我的手机',
  'model': 'Pixel 9',
  'androidVersion': '15',
  'apiLevel': 35,
  'transport': 'tls',
  'address': '192.168.1.8',
  'port': 37123,
  'status': 'connected',
};

void main() {
  testWidgets(
    'picture settings summarize the current device preference and keep its disclosure',
    (tester) async {
      tester.view.physicalSize = const Size(280, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = createTestController(
        (command, [params = const {}]) async => {},
      );
      addTearDown(controller.dispose);
      controller.settings = {
        'qualityPreset': 'clear',
        'deviceQuality': {
          'phone': {'qualityPreset': 'smooth'},
          'other': {'qualityPreset': 'balanced'},
        },
      };
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(280, 874),
              textScaler: TextScaler.linear(2),
            ),
            child: DeviceWorkspacePage(controller: controller, device: _device),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ActionRow, '画面设置');
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      Future<void> expectSummary(Json settings, String expected) async {
        controller.settings = settings;
        await tester.pumpAndSettle();
        final label = find.descendant(of: row, matching: find.text(expected));
        expect(label, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(LucideIcons.chevronRight),
          ),
          findsOneWidget,
        );
        final titleRect = tester.getRect(
          find.descendant(of: row, matching: find.text('画面设置')),
        );
        expect(titleRect.right, lessThan(tester.getTopLeft(label).dx));
        expect(tester.widget<Text>(find.text('画面设置')).maxLines, isNull);
        expect(tester.takeException(), isNull);
      }

      await expectSummary(controller.settings, '流畅');
      await expectSummary({'qualityPreset': 'clear'}, '清晰');
      await expectSummary({
        'qualityPreset': 'clear',
        'deviceQuality': {
          'phone': {'qualityPreset': 'balanced'},
        },
      }, '均衡');
      await expectSummary({
        'deviceQuality': {
          'phone': {'qualityPreset': 'custom'},
        },
      }, '自定义');
      await expectSummary({}, '未获取');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'app opening actions keep primary and secondary colors in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(280, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = ConnectTokens.theme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openPhoneApp(context, _device, {
                    'name': '具有很长名称的远端应用',
                    'packageName': 'example.app',
                  }),
                  child: const Text('打开应用'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开应用'));
        await tester.pumpAndSettle();
        final primary = find.widgetWithText(FilledButton, '在独立窗口打开');
        final secondary = find.widgetWithText(OutlinedButton, '在手机屏幕打开');
        Material material(Finder button) => tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        );
        expect(material(primary).color, theme.colorScheme.primary);
        expect(
          material(secondary).color,
          theme.colorScheme.surfaceContainerHigh,
        );
        expect(material(primary).color, isNot(material(secondary).color));
        expect(
          tester.getTopLeft(secondary).dy - tester.getBottomLeft(primary).dy,
          DesignTokens.spacingSm,
        );
        expect(find.text('取消').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'workspace hero keeps a compact summary and expands for long values',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => {},
      );
      addTearDown(controller.dispose);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final device = {
        ..._device,
        'battery': 78,
        'charging': true,
        'batteryUpdatedAt': now,
      };
      Future<void> pump(Json current, double width, double scale) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1500),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: DeviceHero(controller: controller, device: current),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(device, 402, 1);
      final compactHeight = tester.getSize(find.byType(DeviceHero)).height;
      expect(compactHeight, inInclusiveRange(180, 200));
      final status = tester.getRect(find.text('已连接'));
      final transport = tester.getRect(find.text('无线调试'));
      expect(status.left, lessThan(transport.left));
      expect(status.top, lessThan(transport.bottom));
      expect(transport.top, lessThan(status.bottom));
      expect(find.byIcon(LucideIcons.batteryCharging), findsOneWidget);
      const address = '2001:db8:abcd:ef01:2345:6789:abcd:ef01';
      await pump(
        {...device, 'model': '具有很长设备型号名称的 Android 手机', 'address': address},
        280,
        2,
      );
      expect(
        tester.getSize(find.byType(DeviceHero)).height,
        greaterThan(compactHeight),
      );
      final endpoint = find.text('[$address]:37123');
      expect(endpoint, findsOneWidget);
      expect(
        tester.getSize(endpoint).height,
        greaterThan(DesignTokens.typographyCaptionFontSize * 2),
      );
      expect(find.text('打开手机屏幕').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('linear battery icons only describe current connected readings', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Future<void> pump(Json update) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(body: DeviceFacts(device: {..._device, ...update})),
        ),
      );
    }

    await pump({'battery': 78, 'charging': true, 'batteryUpdatedAt': now});
    expect(find.byIcon(LucideIcons.batteryCharging), findsOneWidget);
    expect(find.text('78% · 正在充电'), findsOneWidget);
    await pump({'battery': 37, 'charging': false, 'batteryUpdatedAt': now});
    expect(find.byIcon(LucideIcons.battery), findsOneWidget);
    expect(find.byIcon(LucideIcons.batteryCharging), findsNothing);
    for (final update in [
      {'battery': 37, 'batteryUpdatedAt': now - 91},
      {'battery': 37, 'batteryUpdatedAt': now, 'status': 'offline'},
      {'batteryUpdatedAt': now},
      {'battery': 37},
    ]) {
      await pump(update);
      expect(find.byIcon(LucideIcons.battery), findsNothing);
      expect(find.byIcon(LucideIcons.batteryCharging), findsNothing);
      expect(find.text('37%'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'active applications share the caption hierarchy and spacing of sections',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => {},
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SectionTitle('快捷操作')),
                RunningApps(
                  controller: controller,
                  device: {..._device, 'status': 'offline'},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final quick = tester.widget<Text>(find.text('快捷操作'));
      final active = tester.widget<Text>(find.text('活跃应用'));
      expect(active.style, quick.style);
      expect(active.style?.fontSize, DesignTokens.typographyCaptionFontSize);
      expect(active.style?.color, DesignTokens.colorSecondary);
      final quickSectionRect = tester.getRect(
        find.widgetWithText(SectionTitle, '快捷操作'),
      );
      final quickCaptionRect = tester.getRect(find.text('快捷操作'));
      expect(
        quickCaptionRect.top - quickSectionRect.top,
        DesignTokens.spacingSectionTitle,
      );
      expect(
        quickSectionRect.bottom - quickCaptionRect.bottom,
        DesignTokens.spacingSm,
      );
      final section = find.ancestor(
        of: find.text('活跃应用'),
        matching: find.byType(SectionTitle),
      );
      final sectionRect = tester.getRect(section);
      final captionRect = tester.getRect(find.text('活跃应用'));
      expect(captionRect.top - sectionRect.top, inInclusiveRange(28, 32));
      expect(sectionRect.bottom - captionRect.bottom, greaterThanOrEqualTo(12));
      for (final button in [
        find.byTooltip('刷新后台应用'),
        find.widgetWithText(TextButton, '全部应用'),
      ]) {
        final buttonRect = tester.getRect(button);
        expect(buttonRect.width, greaterThanOrEqualTo(44));
        expect(buttonRect.height, greaterThanOrEqualTo(44));
        expect(sectionRect.contains(buttonRect.topLeft), isTrue);
        expect(
          sectionRect.contains(buttonRect.bottomRight - const Offset(.1, .1)),
          isTrue,
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(buttonRect.center.dy, closeTo(captionRect.center.dy, .1));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'workspace section actions use existing whitespace and keep full hit areas',
    (tester) async {
      var reads = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'apps.list') {
          reads++;
          return {
            'deviceId': 'phone',
            'source': 'runningTasks',
            'live': true,
            'apps': [
              {
                'name': '设置',
                'packageName': 'com.android.settings',
                'userId': 0,
              },
            ],
          };
        }
        if (command == 'apps.icon') return _iconResult('phone');
        return {};
      });
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final (width, scale) in [(402.0, 1.0), (280.0, 2.0)]) {
        await tester.pumpWidget(const SizedBox());
        tester.view.physicalSize = Size(width, 1800);
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1800),
                textScaler: TextScaler.linear(scale),
              ),
              child: DeviceWorkspacePage(
                controller: controller,
                device: _device,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final shortcutsRect = tester.getRect(find.byType(ContentShortcuts));
        final captionRect = tester.getRect(find.text('活跃应用'));
        final sectionRect = tester.getRect(
          find.widgetWithText(SectionTitle, '活跃应用'),
        );
        final refresh = find.byTooltip('刷新后台应用');
        final refreshRect = tester.getRect(refresh);
        final allApps = find.widgetWithText(TextButton, '全部应用');
        final allAppsRect = tester.getRect(allApps);
        final iconRect = tester.getRect(find.byType(PhoneAppIcon));
        if (scale == 1) {
          expect(
            captionRect.top - shortcutsRect.bottom,
            inInclusiveRange(28, 32),
          );
          expect(sectionRect.top, shortcutsRect.bottom);
          expect(iconRect.top - shortcutsRect.bottom, inInclusiveRange(64, 70));
        } else {
          expect(sectionRect.height, greaterThan(60));
          expect(
            captionRect.height,
            greaterThan(DesignTokens.typographyCaptionFontSize * scale),
          );
        }
        for (final rect in [refreshRect, allAppsRect]) {
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(sectionRect.contains(rect.topLeft), isTrue);
          expect(
            sectionRect.contains(rect.bottomRight - const Offset(.1, .1)),
            isTrue,
          );
        }
        expect(refresh.hitTestable(), findsOneWidget);
        expect(allApps.hitTestable(), findsOneWidget);
        final before = reads;
        // Exercise the edge of the actual button area, outside its 16px glyph.
        await tester.tapAt(refreshRect.topCenter + const Offset(0, 1));
        await tester.pumpAndSettle();
        expect(reads, before + 1);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'background grid requests only target tasks and rejects installed-list responses',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'apps.list'
            ? {
                'apps': [
                  {'name': '未启动应用', 'packageName': 'not.running'},
                ],
              }
            : {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [RunningApps(controller: controller, device: _device)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'apps.list');
      expect(calls.single.$2, {'deviceId': 'phone', 'filter': 'running'});
      expect(find.text('未启动应用'), findsNothing);
      expect(find.text('暂时无法读取后台应用'), findsOneWidget);
      expect(find.text('没有已启动的应用'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'one thousand running apps request icons only around the visible rows',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final iconRequests = <String>[];
      final image = base64Encode(_icon);
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'apps.list') {
          return {
            'deviceId': 'phone',
            'source': 'runningTasks',
            'live': true,
            'apps': List.generate(
              1000,
              (index) => {
                'name': '应用 $index',
                'packageName': 'dev.fixture.app$index',
                'userId': 0,
                'taskId': index,
              },
            ),
          };
        }
        if (command == 'apps.icon') {
          iconRequests.add(value(params, 'packageName'));
          return {
            'deviceId': 'phone',
            'packageName': params['packageName'],
            'userId': 0,
            'mimeType': 'image/png',
            'dataBase64': image,
          };
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [RunningApps(controller: controller, device: _device)],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(iconRequests, isNotEmpty);
        expect(
          iconRequests.length,
          lessThanOrEqualTo(72),
          reason: 'A viewport plus its cache must not request all one thousand package icons.',
        );
        expect(iconRequests, isNot(contains('dev.fixture.app999')));
        expect(find.text('应用 999'), findsNothing);
        final initial = iconRequests.length;
        await tester.drag(find.byType(Scrollable), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(iconRequests.length, greaterThan(initial));
        expect(iconRequests.length, lessThanOrEqualTo(120));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets('icons discard an old device response after switching target', (
    tester,
  ) async {
    final old = Completer<Json>();
    final next = Completer<Json>();
    final controller = createTestController(
      (command, [params = const {}]) =>
          params['deviceId'] == 'a' ? old.future : next.future,
    );
    addTearDown(controller.dispose);
    Future<void> pump(String id) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneAppIcon(
            controller: controller,
            deviceId: id,
            packageName: 'com.android.settings',
            userId: '0',
          ),
        ),
      ),
    );
    await pump('a');
    await pump('b');
    next.complete(_iconResult('b'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    old.complete({'deviceId': 'a', 'mimeType': 'wrong'});
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offline workspace keeps management and never queries live applications',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        return {};
      });
      addTearDown(controller.dispose);
      final device = {..._device, 'status': 'offline'};
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DeviceWorkspacePage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接手机'), findsOneWidget);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.text('设备信息'), findsNothing);
      expect(find.text('信息来自本机记录'), findsOneWidget);
      expect(calls.where((c) => c == 'apps.list' || c == 'apps.icon'), isEmpty);
      await tester.scrollUntilVisible(
        find.text('文件管理'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('文件管理')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件管理'));
      await tester.pumpAndSettle();
      expect(find.text('设备尚未连接'), findsOneWidget);
      expect(
        calls.where((c) => c == 'devices.connect' || c == 'files.list'),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c == 'devices.connect' || c == 'files.list'),
        isEmpty,
      );

      await tester.scrollUntilVisible(
        find.text('移除此设备'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('移除此设备')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('移除此设备').hitTestable(), findsOneWidget);
      final disconnect = tester.widget<ActionRow>(
        find.widgetWithText(ActionRow, '断开设备连接'),
      );
      expect(disconnect.enabled, false);
      expect(disconnect.onTap, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
