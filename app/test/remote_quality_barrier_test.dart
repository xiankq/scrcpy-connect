import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const pixels = <String, dynamic>{
  'sessionId': 'window',
  'deviceId': 'phone',
  'status': 'streaming',
  'textureId': 1,
  'width': 200,
  'height': 400,
  'captureGeneration': 1,
  'generation': 10,
  'firstFrameDecoded': true,
  'evidence': 'media_codec.snapshot',
};

void main() {
  testWidgets('旧工具按键回执不能释放重建捕获上新按住的同名按键', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = StreamController<Json>.broadcast(sync: true);
    final calls = <(String, Json)>[];
    final oldDown = Completer<Json>();
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add((command, params));
      if (command == 'session.start') return pixels;
      if (command == 'session.key' &&
          params['captureGeneration'] == 1 &&
          params['action'] == 'down') {
        return oldDown.future;
      }
      return {};
    }, events: events.stream);
    try {
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
            initialAction: const RemoteControlIntent.key(20),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.$1 == 'session.key'), hasLength(1));
      events.add({
        'type': 'session.updated',
        'data': {
          ...pixels,
          'qualityRebuilding': true,
          'qualityRebuildTarget': 2,
        },
      });
      final fresh = {
        ...pixels,
        'captureGeneration': 2,
        'generation': 20,
        'textureId': 2,
      };
      events.add({'type': 'session.output.changed', 'data': fresh});
      events.add({
        'type': 'session.updated',
        'data': {
          ...fresh,
          'qualityRebuilding': false,
          'qualityRebuildOutcome': 'applied',
        },
      });
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      oldDown.complete({});
      await tester.pumpAndSettle();
      Iterable<Json> newKeys() => calls
          .where(
            (call) =>
                call.$1 == 'session.key' && call.$2['captureGeneration'] == 2,
          )
          .map((call) => call.$2);
      expect(newKeys().map((params) => params['action']), ['down']);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(newKeys().map((params) => params['action']), ['down', 'up']);
      expect(
        calls
            .where(
              (call) =>
                  call.$1 == 'session.key' && call.$2['captureGeneration'] == 1,
            )
            .map((call) => call.$2['action']),
        ['down', 'up'],
      );
    } finally {
      if (!oldDown.isCompleted) oldDown.complete({});
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    }
  });

  testWidgets(
    'capture geometry cannot stretch the retained decoded texture or admit input',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final calls = <(String, Json)>[];
      final decoded = {...pixels, 'decodedWidth': 200, 'decodedHeight': 400};
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'session.start' ? decoded : {};
      }, events: events.stream);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getRect(find.byType(Texture)).center,
        );
        await tester.pump();
        events.add({
          'type': 'session.updated',
          'data': {'sessionId': 'window', 'width': 400, 'height': 200},
        });
        await tester.pump();
        final previous = tester.getRect(find.byType(Texture));
        expect(previous.width / previous.height, closeTo(.5, .001));
        expect(
          calls
              .where((c) => c.$1 == 'session.touch')
              .map((c) => c.$2['action']),
          ['down', 'cancel'],
        );
        await gesture.up();
        await tester.tapAt(previous.center);
        await tester.pump();
        expect(calls.where((c) => c.$1 == 'session.touch'), hasLength(2));
        events.add({
          'type': 'session.output.changed',
          'data': {
            ...decoded,
            'width': 400,
            'height': 200,
            'decodedWidth': 400,
            'decodedHeight': 200,
            'generation': 11,
            'textureId': 2,
          },
        });
        await tester.pump();
        final current = tester.getRect(find.byType(Texture));
        expect(current.width / current.height, closeTo(2, .001));
        await tester.tapAt(current.center);
        await tester.pump();
        expect(
          calls
              .where((c) => c.$1 == 'session.touch')
              .map((c) => c.$2['action']),
          ['down', 'cancel', 'down', 'up'],
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );

  testWidgets(
    'retryable quality failure pushes settings without closing or starting another window',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'session.start' ? pixels : {};
      }, events: events.stream);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [
              {'id': 'phone', 'name': '手机', 'status': 'connected'},
            ],
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        events.add({
          'type': 'session.updated',
          'data': {
            ...pixels,
            'qualityRebuilding': true,
            'qualityRebuildTarget': 2,
          },
        });
        events.add({
          'type': 'session.updated',
          'data': {
            ...pixels,
            'qualityRebuilding': false,
            'qualityRebuildOutcome': 'failed',
            'status': 'failed',
            'qualityRetryable': true,
            'reason': 'encoder failed',
          },
        });
        await tester.pumpAndSettle();
        expect(find.text('画面调整未完成'), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, '画面设置'));
        await tester.tap(find.widgetWithText(OutlinedButton, '画面设置'));
        await tester.pumpAndSettle();
        expect(find.byType(QualityPage), findsOneWidget);
        expect(find.byType(RemotePage, skipOffstage: false), findsOneWidget);
        expect(calls.where((c) => c.$1 == 'session.stop'), isEmpty);
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('画面调整未完成'), findsOneWidget);
        expect(
          calls.where(
            (c) => [
              'session.stop',
              'session.resume',
              'devices.wake',
            ].contains(c.$1),
          ),
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );
  testWidgets(
    'quality rebuild drains held input and keeps the same window until both new receipts agree',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'session.start' ? pixels : {};
      }, events: events.stream);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final texture = tester.getRect(find.byType(Texture));
        final gesture = await tester.startGesture(texture.center, pointer: 71);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        events.add({
          'type': 'session.updated',
          'data': {
            ...pixels,
            'qualityRebuilding': true,
            'qualityRebuildTarget': 2,
          },
        });
        await tester.pump();
        expect(find.text('正在调整画面…'), findsOneWidget);
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
        expect(
          calls
              .where((c) => c.$1 == 'session.touch')
              .map((c) => c.$2['action']),
          ['down', 'cancel'],
        );
        expect(
          calls.where((c) => c.$1 == 'session.key').map((c) => c.$2['action']),
          ['down', 'up'],
        );
        await gesture.moveBy(const Offset(5, 5));
        await gesture.up();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.tapAt(texture.center);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(calls.where((c) => c.$1 == 'session.touch'), hasLength(2));
        expect(calls.where((c) => c.$1 == 'session.key'), hasLength(2));
        events.add({
          'type': 'session.output.changed',
          'data': {...pixels, 'generation': 999, 'textureId': 99},
        });
        events.add({
          'type': 'session.failed',
          'data': {...pixels, 'generation': 999, 'reason': 'old capture'},
        });
        await tester.pump();
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
        expect(find.text('正在调整画面…'), findsOneWidget);
        final fresh = {
          ...pixels,
          'captureGeneration': 2,
          'generation': 20,
          'textureId': 2,
        };
        events.add({'type': 'session.output.changed', 'data': fresh});
        await tester.pump();
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
        events.add({
          'type': 'session.updated',
          'data': {
            ...fresh,
            'qualityRebuilding': false,
            'qualityRebuildOutcome': 'applied',
          },
        });
        await tester.pump();
        expect(find.text('正在调整画面…'), findsNothing);
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 2);
        await tester.tapAt(texture.center);
        await tester.pump();
        expect(
          calls
              .where((c) => c.$1 == 'session.touch')
              .map((c) => c.$2['action']),
          ['down', 'cancel', 'down', 'up'],
        );
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        expect(
          calls.where(
            (c) => [
              'devices.wake',
              'session.stop',
              'session.pause',
            ].contains(c.$1),
          ),
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );
}
