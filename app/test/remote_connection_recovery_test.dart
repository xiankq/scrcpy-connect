import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final scenario in [
    'visible',
    'retained',
    'explicit stop',
    'activity stop',
    'connection stop',
    'manual disconnect',
    'app window',
    'background',
    'closed output',
    'reconciled',
  ]) {
    testWidgets('connection recovery respects $scenario intent', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final starts = <Json>[];
      final retained = scenario == 'retained';
      Json receipt(String id) => {
        'sessionId': id,
        'status': 'streaming',
        'textureId': 1,
        'width': 200,
        'height': 400,
        'firstFrameDecoded': true,
        'evidence': 'media_codec.snapshot',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.start') {
          starts.add({...params});
          return receipt('session-${starts.length}');
        }
        if (command == 'session.resume') {
          return receipt(value(params, 'sessionId'));
        }
        if (command == 'session.pause' && scenario == 'closed output') {
          throw const RequestFailure('no_frame', '该视频输出已结束。');
        }
        return <String, dynamic>{};
      }, events: events.stream);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
              packageName: scenario == 'app window'
                  ? 'com.android.settings'
                  : null,
              existingSession: retained ? receipt('retained') : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = starts.length;
        final original = retained ? 'retained' : 'session-1';
        if (scenario == 'reconciled') {
          events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
          events.add({
            'type': 'state.resynced',
            'data': {
              'devices': <Json>[],
              'settings': <String, dynamic>{},
              'shares': <Json>[],
              'sequence': 1,
              'sessions': [receipt(original)],
            },
          });
          await tester.pumpAndSettle();
        }
        if (const [
          'explicit stop',
          'activity stop',
          'connection stop',
        ].contains(scenario)) {
          await controller.request(
            scenario == 'explicit stop' ? 'session.stop' : 'activities.stop',
            scenario == 'explicit stop'
                ? {'sessionId': original}
                : {
                    'activityId': scenario == 'activity stop'
                        ? 'session:$original'
                        : 'connection:phone',
                  },
          );
          await tester.pumpAndSettle();
        }
        if (scenario == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pumpAndSettle();
        }
        events.add({
          'type': 'session.disconnected',
          'deviceId': 'phone',
          'data': {
            'sessionId': original,
            'status': 'stopped',
            'reason': 'link ended',
          },
        });
        await tester.pumpAndSettle();
        void devices(String status) => events.add({
          'type': 'devices.changed',
          'data': {
            'devices': [
              {
                'id': 'phone',
                'status': status,
                'autoReconnect': scenario != 'manual disconnect',
              },
            ],
          },
        });
        devices('offline');
        await tester.pumpAndSettle();
        devices('connected');
        devices('connected');
        await tester.pumpAndSettle();
        final shouldRecover = const [
          'visible',
          'retained',
          'closed output',
          'reconciled',
        ].contains(scenario);
        expect(starts.length, before + (shouldRecover ? 1 : 0));
        if (shouldRecover) {
          expect(starts.last.containsKey('packageName'), false);
          expect(find.text('画面已暂停'), findsNothing);
          // An old stopped session must not regain control over its successor.
          events.add({
            'type': 'session.disconnected',
            'deviceId': 'phone',
            'data': {'sessionId': original, 'reason': 'late old termination'},
          });
          await tester.pumpAndSettle();
          expect(find.text('late old termination'), findsNothing);
        }
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
        await events.close();
      }
    });
  }
  for (final interruption in [
    'stop before submission',
    'stop after submission',
    'background',
  ]) {
    testWidgets('a delayed recovery respects $interruption', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final gate = Completer<Json>();
      var starts = 0;
      var interrupted = false;
      final stopped = <String>[];
      Json receipt(String id) => {
        'sessionId': id,
        'textureId': 1,
        'width': 200,
        'height': 400,
        'status': 'streaming',
        'firstFrameDecoded': true,
        'evidence': 'media_codec.snapshot',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.list' &&
            interrupted &&
            interruption != 'stop after submission') {
          return gate.future;
        }
        if (command == 'session.start') {
          starts++;
          if (starts == 2 && interruption == 'stop after submission') {
            return gate.future;
          }
          return receipt('session-$starts');
        }
        if (command == 'session.stop') stopped.add(value(params, 'sessionId'));
        return <String, dynamic>{};
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
        interrupted = true;
        events.add({
          'type': 'session.disconnected',
          'deviceId': 'phone',
          'data': {'sessionId': 'session-1'},
        });
        for (final status in ['offline', 'connected']) {
          events.add({
            'type': 'devices.changed',
            'data': {
              'devices': [
                {'id': 'phone', 'status': status, 'autoReconnect': true},
              ],
            },
          });
          await tester.pump();
        }
        if (interruption == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          await controller.request('session.stop', {'sessionId': 'session-1'});
        }
        gate.complete(
          interruption == 'stop after submission'
              ? receipt('session-2')
              : <String, dynamic>{},
        );
        await tester.pumpAndSettle();
        expect(starts, interruption == 'stop after submission' ? 2 : 1);
        if (interruption == 'stop after submission') {
          expect(stopped, contains('session-2'));
        }
        if (interruption == 'background') {
          interrupted = false;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(
            starts,
            2,
            reason: 'Deferred recovery resumes only when visible again.',
          );
        }
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
        await events.close();
      }
    });
  }
}
