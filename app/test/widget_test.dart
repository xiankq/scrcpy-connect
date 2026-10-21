import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
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

      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      await tester.enterText(find.byType(TextFormField).at(2), '123456');
      await tester.ensureVisible(find.text('配对并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('配对并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '应用并连接'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pairParams?['deviceId'], 'restored-id');
      expect(pairParams?['address'], 'phone.local');
      await tester.ensureVisible(find.text('取消本次尝试'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('取消本次尝试'));
      await tester.pumpAndSettle();
      expect(cancelParams?['attemptId'], pairParams?['attemptId']);
      expect(cancelParams?['attemptId'], isNotEmpty);
      pending.completeError(StateError('cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('已取消本次尝试。'), findsOneWidget);
      expect(find.byType(ConnectionFailureNote), findsNothing);
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
      expect(find.text('需要重新授权'), findsOneWidget);
      expect(find.textContaining('97%'), findsNothing);
      expect(find.text('连接后查看后台应用'), findsOneWidget);
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
      final frame = tester.getRect(find.byType(Texture));
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
      expect(
        touches.first['y'],
        ((300 - frame.top) / frame.height * 400).round(),
      );
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
}
