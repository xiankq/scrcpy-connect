import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/add_device/add_device_page.dart';
import 'package:scrcpy_connect/pages/connection_form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/services/remote_input.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';

void main() {
  testWidgets(
    'first-time manual connection can switch to pairing without a prior result',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => {},
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: ConnectionFormPage(
            controller: controller,
            address: 'phone.local',
          ),
        ),
      );
      await tester.tap(find.text('尚未配对？使用配对码'));
      await tester.pumpAndSettle();
      expect(find.text('使用配对码'), findsOneWidget);
      expect(find.text('phone.local'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reauthorization preserves device identity and cancellation targets its attempt',
    (tester) async {
      final pending = Completer<Json>();
      Json? pairParams;
      Json? cancelParams;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'devices.pair') {
          pairParams = Map<String, dynamic>.from(params);
          return pending.future;
        }
        if (command == 'devices.cancel') {
          cancelParams = Map<String, dynamic>.from(params);
          return {'cancelled': true};
        }
        return command == 'devices.list' ? {'devices': <Json>[]} : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: AddDevicePage(
            controller: controller,
            initialDevice: const {
              'id': 'restored-id',
              'name': '恢复的手机',
              'address': 'phone.local',
            },
          ),
        ),
      );
      await tester.tap(find.text('无线连接'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('使用配对码'));
      await tester.tap(find.text('使用配对码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      await tester.enterText(find.byType(TextFormField).at(2), '123456');
      await tester.ensureVisible(find.text('配对并检查连接'));
      await tester.tap(find.text('配对并检查连接'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pairParams?['deviceId'], 'restored-id');
      expect(pairParams?['address'], 'phone.local');
      await tester.ensureVisible(find.text('取消本次尝试'));
      await tester.tap(find.text('取消本次尝试'));
      await tester.pumpAndSettle();
      expect(cancelParams?['attemptId'], pairParams?['attemptId']);
      expect(cancelParams?['attemptId'], isNotEmpty);
      pending.completeError(StateError('cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('本次尝试已取消。已建立的配对信任会保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small phone and large text preserve reachable device navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'devices.list' ? {'devices': <Json>[]} : {},
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('外观与易用性'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'wireless fields accept IP and hostnames and reject malformed input',
    () {
      for (final address in [
        '192.168.0.8',
        'phone.local',
        '2001:db8::1',
        '[2001:db8::1]',
        'fe80::1%wlan0',
      ]) {
        expect(validateAddress(address), isNull, reason: address);
      }
      for (final address in [
        '',
        '256.0.0.1',
        'http://phone',
        'phone:37123',
        '::::',
        'phone..local',
      ]) {
        expect(validateAddress(address), isNotNull, reason: address);
      }
      for (final port in ['1', '65535', '37123']) {
        expect(validatePort(port), isNull);
      }
      for (final port in ['', '0', '65536', '12.5', 'abc']) {
        expect(validatePort(port), isNotNull);
      }
    },
  );
  test('source input preserves aspect ratio and excludes letterbox space', () {
    const viewport = Size(400, 800);
    const landscape = Size(1920, 1080);
    expect(
      sourcePoint(const Offset(200, 400), viewport, landscape),
      const Offset(960, 540),
    );
    expect(sourcePoint(const Offset(200, 20), viewport, landscape), isNull);
    expect(sourcePoint(const Offset(200, 799), viewport, landscape), isNull);
    expect(
      sourcePoint(const Offset(200, 20), viewport, landscape, clamp: true),
      const Offset(960, 0),
    );
    expect(
      sourcePoint(const Offset(399, 400), viewport, landscape)!.dx,
      closeTo(1915.2, .01),
    );
    expect(sourcePoint(Offset.zero, viewport, Size.zero), isNull);
  });
  testWidgets(
    'first screen remains an empty device list without invented devices',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        return command == 'devices.list' ? {'devices': <Json>[]} : {};
      });
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加你的第一台设备'), findsOneWidget);
      expect(find.text('设备'), findsNWidgets(2));
      expect(find.textContaining('Pixel'), findsNothing);
      expect(calls.where((call) => call.startsWith('session.')), isEmpty);
      await tester.tap(find.text('添加设备').last);
      await tester.pumpAndSettle();
      expect(find.text('选择连接方式'), findsOneWidget);
      expect(find.text('手动填写地址'), findsOneWidget);
    },
  );
  testWidgets('invalid connection port cannot reach device backend', (
    tester,
  ) async {
    final calls = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add(command);
      return {};
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: ConnectionFormPage(controller: controller),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), '192.168.1.8');
    await tester.enterText(find.byType(TextFormField).at(1), '65536');
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
    expect(calls, isEmpty);
  });
  testWidgets(
    'metadata-only device stays unauthorized and has no live battery',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => command == 'device.info'
            ? {'id': 'restored', 'name': '恢复的手机', 'status': 'unauthorized'}
            : command == 'devices.list'
            ? {
                'devices': [
                  {
                    'id': 'restored',
                    'name': '恢复的手机',
                    'status': 'unauthorized',
                    'battery': 97,
                  },
                ],
              }
            : {},
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要重新授权'), findsOneWidget);
      expect(find.textContaining('97%'), findsNothing);
      await tester.tap(find.text('恢复的手机'));
      await tester.pumpAndSettle();
      expect(find.text('重新授权'), findsOneWidget);
      expect(find.textContaining('旧记录不代表当前授权'), findsOneWidget);
    },
  );
  testWidgets('missing live texture reports failure and blocks remote input', (
    tester,
  ) async {
    final calls = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add(command);
      return {'sessionId': 'actual-session', 'reason': '设备未提供解码画面'};
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: RemotePage(
          controller: controller,
          device: const {'id': 'phone', 'name': '测试手机'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法打开实时画面'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    await tester.tapAt(const Offset(400, 500));
    await tester.pump();
    expect(calls.where((call) => call == 'session.touch'), isEmpty);
  });

  testWidgets(
    'multitouch uses source pixels and preserves pointer identities',
    (tester) async {
      final touches = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.touch') {
          touches.add(Map<String, dynamic>.from(params));
        }
        return command == 'session.start'
            ? {
                'sessionId': 'session',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final one = await tester.startGesture(
        const Offset(400, 300),
        pointer: 101,
      );
      final two = await tester.startGesture(
        const Offset(475, 450),
        pointer: 102,
      );
      await one.moveBy(const Offset(15, 0));
      await one.up();
      await two.cancel();
      await tester.pumpAndSettle();
      expect(touches.first['x'], 100);
      expect(touches.first['y'], 200);
      expect(touches.first['screenWidth'], 200);
      expect(touches.first['screenHeight'], 400);
      expect(
        touches.where((p) => p['pointerId'] == 101).map((p) => p['action']),
        ['down', 'move', 'up'],
      );
      expect(
        touches.where((p) => p['pointerId'] == 102).map((p) => p['action']),
        ['down', 'cancel'],
      );
    },
  );

  testWidgets(
    'dragging exit consumes touches and collapsed handle requires expansion',
    (tester) async {
      var exits = 0;
      var remoteTouches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => remoteTouches++,
                    child: const SizedBox.expand(),
                  ),
                ),
                ExitHandle(deviceLabel: '测试手机', onExit: () => exits++),
              ],
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(36, 106), const Offset(700, 80));
      await tester.pumpAndSettle();
      expect(exits, 0);
      expect(remoteTouches, 0);
      final collapsed = find.bySemanticsLabel('展开退出按钮，测试手机');
      expect(collapsed, findsOneWidget);
      await tester.tap(collapsed);
      await tester.pumpAndSettle();
      expect(exits, 0);
      await tester.tap(find.bySemanticsLabel('退出控制，返回测试手机'));
      await tester.pump();
      expect(exits, 1);
      expect(remoteTouches, 0);
    },
  );
}
