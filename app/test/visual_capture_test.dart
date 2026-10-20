import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional visual artifacts use explicit test fixtures, never production data.
/// CONNECT_CAPTURE_DIR=/tmp/connect-visual flutter test test/visual_capture_test.dart
void main() {
  final output = Platform.environment['CONNECT_CAPTURE_DIR'];
  if (output == null) return;
  testWidgets('capture phone UI for visual review', (tester) async {
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var devices = <Json>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'devices.list') return {'devices': devices};
      if (command == 'device.info') {
        final matches = devices.where(
          (device) => device['id'] == params['deviceId'],
        );
        if (matches.isNotEmpty) {
          return {
            ...matches.first,
            'androidVersion': '15',
            'address': '192.168.1.8',
          };
        }
      }
      return {};
    });
    await controller.initialize();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TestProviderScope(
          controller: controller,
          child: const ConnectApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(output);
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('empty-devices');
    await tester.tap(find.byTooltip('添加设备'));
    await tester.pumpAndSettle();
    await capture('add-device');
    await Scrollable.ensureVisible(
      tester.element(find.text('连接帮助')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接帮助'));
    await tester.pumpAndSettle();
    await capture('connection-help');
    await Scrollable.ensureVisible(
      tester.element(find.text('知道了')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('IP连接')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('IP连接'));
    await tester.pumpAndSettle();
    await capture('ip-address-form');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').hitTestable().first);
    await tester.pumpAndSettle();
    await capture('settings');
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await capture('appearance');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备').last);
    devices = [
      {
        'id': 'fixture-connected',
        'name': '测试手机 A',
        'model': 'Android 测试设备',
        'status': 'connected',
        'transport': 'tls',
        'battery': 78,
      },
      {
        'id': 'fixture-offline',
        'name': '测试手机 B',
        'status': 'offline',
        'lastSeenLabel': '最近连接：昨天',
      },
    ];
    await controller.refreshDevices();
    await tester.pumpAndSettle();
    await capture('device-list-fixture');
    await tester.tap(find.text('测试手机 A'));
    await tester.pumpAndSettle();
    await capture('workspace-fixture');
    await capture('workspace-settings-top-fixture');
    await tester.scrollUntilVisible(find.text('自动同步剪贴板'), 160);
    await tester.pumpAndSettle();
    await capture('workspace-settings-fixture');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await controller.updateSetting('appearance', 'dark');
    await tester.pumpAndSettle();
    await capture('devices-dark-fixture');
    tester.view.physicalSize = const Size(1194, 834);
    await tester.pumpAndSettle();
    await capture('tablet-devices-fixture');
    tester.view.physicalSize = const Size(280, 620);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await capture('narrow-large-text-devices-fixture');
    await tester.tap(find.byTooltip('添加设备'));
    await tester.pumpAndSettle();
    await capture('narrow-large-text-add-device');
    await Scrollable.ensureVisible(
      tester.element(find.text('IP连接')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('IP连接'));
    await tester.pumpAndSettle();
    await capture('narrow-large-text-ip-form');
    tester.view.physicalSize = const Size(620, 280);
    await tester.pumpAndSettle();
    await capture('landscape-large-text-ip-form');
  });
}
