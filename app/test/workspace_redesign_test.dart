import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'ios_pages_capture_test.dart' as captures;
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
Json _runningResult(String id) => {
  'deviceId': id,
  'source': 'runningTasks',
  'live': true,
  'apps': [
    {
      'name': '设置',
      'packageName': 'com.android.settings',
      'userId': 0,
      'taskId': 42,
    },
  ],
};
const _device = {
  'id': 'phone',
  'name': '我的手机',
  'model': 'Pixel 9',
  'androidVersion': '15',
  'apiLevel': 35,
  'status': 'connected',
};

void main() {
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
            body: SingleChildScrollView(
              child: RunningApps(controller: controller, device: _device),
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
      expect(calls.where((c) => c == 'apps.list' || c == 'apps.icon'), isEmpty);
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
      expect(find.text('断开设备连接'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  final output = Platform.environment['CONNECT_WORKSPACE_CAPTURE_DIR'];
  if (output == null) return;
  testWidgets(
    'capture redesigned workspace in light dark and connection states',
    (tester) async {
      await captures.loadCaptureFonts();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      await tester.runAsync(() => Directory(output).create(recursive: true));
      for (final state in [
        'connected',
        'offline',
        'connecting',
        'unauthorized',
      ]) {
        for (final brightness in Brightness.values) {
          final controller = createTestController(
            (command, [params = const {}]) async => switch (command) {
              'apps.list' => _runningResult('phone'),
              'apps.icon' => _iconResult('phone'),
              _ => {},
            },
          );
          final device = {..._device, 'status': state};
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: RouterTestApp(
                controller: controller,
                theme: captures.captureTheme(brightness),
                home: DeviceWorkspacePage(
                  controller: controller,
                  device: device,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final context = tester.element(find.byType(DeviceWorkspacePage));
            for (final image in tester.widgetList<Image>(find.byType(Image))) {
              await precacheImage(image.image, context);
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          Future<void> capture(String name) async {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('$output/$name.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          await capture('workspace-$state-${brightness.name}');
          if (state == 'connected') {
            await tester.scrollUntilVisible(
              find.text('移除此设备'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await Scrollable.ensureVisible(
              tester.element(find.text('移除此设备')),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            await capture('workspace-management-${brightness.name}');
          }
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      }
    },
  );
}
