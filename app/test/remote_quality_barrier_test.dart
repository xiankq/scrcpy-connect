import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/quality/devices_workspace_quality_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';

import 'package:scrcpy_connect/models/app_state.dart';

import 'support/remote_page_fixture.dart';

const pixels = RemotePageFixture.pixels;

AppState _qualityState() => AppState(
  settings: const {
    'deviceSettings': {
      'phone': {'wakeOnConnect': false},
    },
  },
);

void main() {
  testWidgets('旧工具按键回执不能释放重建捕获上新按住的同名按键', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final oldDown = Completer<Json>();
    final h = RemotePageFixture(
      initialState: _qualityState(),
      onRequest: (command, params) {
        if (command == 'session.key' &&
            params['captureGeneration'] == 1 &&
            params['action'] == 'down') {
          return oldDown.future;
        }
        return null;
      },
    );
    addTearDown(() {
      if (!oldDown.isCompleted) oldDown.complete({});
    });
    await h.show(tester, initialAction: const RemoteControlIntent.key(20));
    await tester.pumpAndSettle();
    expect(h.commands('session.key'), hasLength(1));
    h.events.add({
      'type': 'session.updated',
      'data': {...pixels, 'qualityRebuilding': true, 'qualityRebuildTarget': 2},
    });
    final fresh = {
      ...pixels,
      'captureGeneration': 2,
      'generation': 20,
      'textureId': 2,
    };
    h.events.add({'type': 'session.output.changed', 'data': fresh});
    h.events.add({
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
    Iterable<Json> newKeys() =>
        h.commands('session.key').where((p) => p['captureGeneration'] == 2);
    expect(newKeys().map((params) => params['action']), ['down']);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(newKeys().map((params) => params['action']), ['down', 'up']);
    expect(
      h
          .commands('session.key')
          .where((p) => p['captureGeneration'] == 1)
          .map((p) => p['action']),
      ['down', 'up'],
    );
  });

  testWidgets(
    'retryable quality failure pushes settings without closing or starting another window',
    (tester) async {
      final h = RemotePageFixture(initialState: _qualityState());
      await h.show(
        tester,
        devices: const [
          {'id': 'phone', 'name': '手机', 'status': 'connected'},
        ],
      );
      await tester.pumpAndSettle();
      h.events.add({
        'type': 'session.updated',
        'data': {
          ...pixels,
          'qualityRebuilding': true,
          'qualityRebuildTarget': 2,
        },
      });
      h.events.add({
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
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, '画面与控制'));
      await tester.tap(find.widgetWithText(OutlinedButton, '画面与控制'));
      await tester.pumpAndSettle();
      expect(find.byType(QualityPage), findsOneWidget);
      expect(find.byType(RemotePage, skipOffstage: false), findsOneWidget);
      expect(h.commands('session.stop'), isEmpty);
      expect(h.commands('session.start'), hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('画面调整未完成'), findsOneWidget);
      expect(
        h.calls.where(
          (c) =>
              ['session.stop', 'session.resume', 'devices.wake'].contains(c.$1),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'quality rebuild drains held input and keeps the same window until both new receipts agree',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = RemotePageFixture(initialState: _qualityState());
      await h.show(tester);
      await tester.pumpAndSettle();
      final texture = tester.getRect(find.byType(Texture));
      final gesture = await tester.startGesture(texture.center, pointer: 71);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      h.events.add({
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
      expect(h.commands('session.touch').map((p) => p['action']), [
        'down',
        'cancel',
      ]);
      expect(h.commands('session.key').map((p) => p['action']), ['down', 'up']);
      await gesture.moveBy(const Offset(5, 5));
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.tapAt(texture.center);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.commands('session.touch'), hasLength(2));
      expect(h.calls.where((c) => c.$1 == 'session.key'), hasLength(2));
      h.events.add({
        'type': 'session.output.changed',
        'data': {...pixels, 'generation': 999, 'textureId': 99},
      });
      h.events.add({
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
      h.events.add({'type': 'session.output.changed', 'data': fresh});
      await tester.pump();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
      h.events.add({
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
      expect(h.commands('session.touch').map((p) => p['action']), [
        'down',
        'cancel',
        'down',
        'up',
      ]);
      expect(h.commands('session.start'), hasLength(1));
      expect(
        h.calls.where(
          (c) =>
              ['devices.wake', 'session.stop', 'session.pause'].contains(c.$1),
        ),
        isEmpty,
      );
    },
  );
}
