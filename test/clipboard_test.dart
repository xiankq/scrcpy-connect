import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/clipboard/clipboard_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/clipboard_coordinator.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ['fixed', 'follow']) {
    testWidgets(
      '$mode recovery keeps background clipboard access frozen and baselines the current target',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final events = StreamController<Json>.broadcast(sync: true);
        var local = 'existing local';
        final reads = <String>[];
        final writes = <String>[];
        final sent = <Json>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData') return {'text': local};
          if (call.method == 'Clipboard.setData') {
            local = (call.arguments as Map)['text'] as String;
            writes.add(local);
          }
          return null;
        });
        final controller =
            createTestController((command, [params = const {}]) async {
                if (command == 'clipboard.get') {
                  reads.add(params['deviceId'] as String);
                  return {'text': '${params['deviceId']} baseline'};
                }
                if (command == 'clipboard.set') {
                  sent.add(params);
                  return {'applied': true};
                }
                return {};
              }, events: events.stream)
              ..devices = [
                {'id': 'a', 'status': 'connected'},
                {'id': 'b', 'status': 'connected'},
              ]
              ..settings = {
                'clipboardSync': true,
                'clipboardMode': mode,
                'clipboardDevice': 'a',
              };
        await controller.focusDevice('a');
        testContainer(controller).read(clipboardCoordinatorProvider);
        await tester.pump();
        await tester.pump();
        expect(reads, ['a']);
        events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
        final readsAtMarker = controller.clipboardReadCount;
        await controller.focusDevice('b');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        local = 'local changed during verification';
        events.add({
          'type': 'clipboard.changed',
          'deviceId': 'a',
          'data': {'text': 'old a'},
        });
        await tester.pump(const Duration(seconds: 3));
        expect(controller.clipboardReadCount, readsAtMarker);
        expect(reads, ['a']);
        expect(writes, isEmpty);
        expect(sent, isEmpty);
        events.add({
          'type': 'state.resynced',
          'data': {
            'devices': controller.devices,
            'settings': {...controller.settings, 'clipboardDevice': 'b'},
            'sessions': <Json>[],
            'shares': <Json>[],
            'sequence': 2,
          },
        });
        await tester.pump(const Duration(seconds: 2));
        expect(controller.clipboardState, 'waitingForeground');
        expect(controller.clipboardReadCount, readsAtMarker);
        expect(reads, ['a']);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump();
        expect(reads, ['a', 'b']);
        expect(controller.clipboardState, 'watching');
        expect(local, 'local changed during verification');
        expect(sent, isEmpty);
        events.add({
          'type': 'clipboard.changed',
          'deviceId': 'a',
          'data': {'text': 'still old a'},
        });
        events.add({
          'type': 'clipboard.changed',
          'deviceId': 'b',
          'data': {'text': 'fresh copy from b'},
        });
        await tester.pump();
        await tester.pump();
        expect(writes, ['fresh copy from b']);
        expect(sent, isEmpty);
        controller.dispose();
        await events.close();
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      },
    );
  }

  testWidgets(
    'resync freezes queued clipboard writes and recovery establishes a fresh baseline',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final oldLocalRead = Completer<Object?>();
      var local = 'initial local';
      var remote = 'initial remote';
      var holdLocalRead = false;
      var localReads = 0;
      final writes = <String>[];
      final sent = <Json>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          localReads++;
          return holdLocalRead ? oldLocalRead.future : {'text': local};
        }
        if (call.method == 'Clipboard.setData') {
          local = (call.arguments as Map)['text'] as String;
          writes.add(local);
        }
        return null;
      });
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'clipboard.get') return {'text': remote};
              if (command == 'clipboard.set') {
                sent.add(params);
                return {'applied': true};
              }
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'a', 'status': 'connected'},
            ]
            ..settings = {
              'clipboardSync': true,
              'clipboardMode': 'fixed',
              'clipboardDevice': 'a',
            };
      testContainer(controller).read(clipboardCoordinatorProvider);
      await tester.pump();
      await tester.pump();
      expect(controller.clipboardState, 'watching');
      holdLocalRead = true;
      events.add({
        'type': 'clipboard.changed',
        'deviceId': 'a',
        'data': {'text': 'queued old remote'},
      });
      await tester.pump();
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resync.failed',
        'data': {'reason': 'snapshot unavailable'},
      });
      final readsAtMarker = localReads;
      oldLocalRead.complete({'text': 'initial local'});
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(writes, isEmpty);
      expect(sent, isEmpty);
      expect(localReads, readsAtMarker);
      expect(controller.clipboardState, 'waitingVerification');
      holdLocalRead = false;
      local = 'current local';
      remote = 'current remote';
      events.add({
        'type': 'state.resynced',
        'data': {
          'devices': controller.devices,
          'settings': controller.settings,
          'shares': <Json>[],
          'sessions': <Json>[],
          'sequence': 3,
        },
      });
      await tester.pump();
      await tester.pump();
      expect(controller.clipboardState, 'watching');
      expect(local, 'current local');
      expect(remote, 'current remote');
      expect(writes, isEmpty);
      expect(sent, isEmpty);
      local = 'new copy after baseline';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(sent, [
        {'deviceId': 'a', 'text': 'new copy after baseline'},
      ]);
      controller.dispose();
      await events.close();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );

  testWidgets(
    'manual clipboard sends require an applied receipt and preserve the local draft otherwise',
    (tester) async {
      const draft = '需要保留的本机文字';
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': draft};
            if (call.method == 'Clipboard.setData') writes++;
            return null;
          });
      final requests = <(String, Json)>[];
      final controller =
          createTestController((command, [params = const {}]) async {
              requests.add((command, params));
              return {'applied': false, 'reason': '手机未确认写入，请在原手机核对。'};
            })
            ..devices = [
              {'id': 'phone', 'name': '手机', 'status': 'connected'},
            ]
            ..settings = {'clipboardMode': 'fixed', 'clipboardDevice': 'phone'};
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: ClipboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发送本机剪贴板'));
      await tester.tap(find.text('发送本机剪贴板'));
      await tester.pumpAndSettle();
      expect(requests.single.$1, 'clipboard.set');
      expect(requests.single.$2, {'deviceId': 'phone', 'text': draft});
      expect(find.text('手机未确认写入，请在原手机核对。'), findsOneWidget);
      expect(find.text('手机已确认剪贴板操作'), findsNothing);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    'follow discards a late previous-device read and never writes an unselected device',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final oldRead = Completer<Json>();
      var local = 'local baseline';
      final sent = <Json>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': local};
            if (call.method == 'Clipboard.setData') {
              local = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'clipboard.get') {
                return params['deviceId'] == 'a'
                    ? oldRead.future
                    : {'text': 'b baseline'};
              }
              if (command == 'clipboard.set') {
                sent.add(params);
                return {'applied': true};
              }
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'a', 'status': 'connected'},
              {'id': 'b', 'status': 'connected'},
            ]
            ..settings = {'clipboardSync': true, 'clipboardMode': 'follow'}
            ..loading = false;
      await controller.focusDevice('a');
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pump();
      await controller.focusDevice('b');
      oldRead.complete({'text': 'late a'});
      await tester.pump();
      await tester.pump();
      expect(local, 'local baseline');
      events.add({
        'type': 'clipboard.changed',
        'deviceId': 'a',
        'data': {'text': 'old device copy'},
      });
      await tester.pump();
      local = 'copy for b';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(sent, [
        {'deviceId': 'b', 'text': 'copy for b'},
      ]);
      expect(local, 'copy for b');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    'background reads stop and conflicting changes are preserved for explicit review on return',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      var local = 'local baseline';
      var remote = 'remote baseline';
      final sent = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': local};
            if (call.method == 'Clipboard.setData') {
              local = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'clipboard.get') return {'text': remote};
              if (command == 'clipboard.set') {
                remote = params['text'] as String;
                sent.add(remote);
                return {'applied': true};
              }
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'a', 'status': 'connected'},
            ]
            ..settings = {
              'clipboardSync': true,
              'clipboardMode': 'fixed',
              'clipboardDevice': 'a',
            }
            ..loading = false;
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final reads = controller.clipboardReadCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      local = 'new local while away';
      remote = 'new remote while away';
      events.add({
        'type': 'clipboard.changed',
        'deviceId': 'a',
        'data': {'text': remote},
      });
      await tester.pump(const Duration(seconds: 3));
      expect(controller.clipboardReadCount, reads);
      expect(controller.clipboardWriteCount, 0);
      expect(sent, isEmpty);
      expect(local, 'new local while away');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(controller.clipboardState, 'needsReview');
      expect(local, 'new local while away');
      expect(remote, 'new remote while away');
      expect(sent, isEmpty);
      local = 'new explicit copy';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(sent, ['new explicit copy']);
      expect(controller.clipboardState, 'watching');
      await controller.updateSetting('clipboardSync', false);
      final disabledReads = controller.clipboardReadCount;
      await tester.pump(const Duration(seconds: 2));
      expect(controller.clipboardReadCount, disabledReads);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    'automatic clipboard synchronizes only the selected device and suppresses both echo directions',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      var local = 'existing local';
      final sent = <Json>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': local};
            if (call.method == 'Clipboard.setData') {
              local = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      final controller =
          createTestController((command, [params = const {}]) async {
              if (command == 'clipboard.get') {
                return {'text': 'existing remote'};
              }
              if (command == 'clipboard.set') {
                sent.add(params);
                events.add({
                  'type': 'clipboard.changed',
                  'deviceId': params['deviceId'],
                  'data': {'text': params['text']},
                });
                return {'applied': true};
              }
              return {};
            }, events: events.stream)
            ..devices = [
              {'id': 'a', 'status': 'connected'},
              {'id': 'b', 'status': 'connected'},
            ]
            ..settings = {
              'clipboardSync': true,
              'clipboardMode': 'fixed',
              'clipboardDevice': 'a',
            }
            ..loading = false;
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        local,
        'existing local',
        reason: 'Enabling must preserve both existing clipboards.',
      );
      events.add({
        'type': 'clipboard.changed',
        'deviceId': 'b',
        'data': {'text': 'unselected remote'},
      });
      await tester.pump();
      expect(local, 'existing local');
      events.add({
        'type': 'clipboard.changed',
        'deviceId': 'a',
        'data': {'text': 'new remote'},
      });
      await tester.pump();
      await tester.pump();
      expect(local, 'new remote');
      await tester.pump(const Duration(seconds: 2));
      expect(
        sent,
        isEmpty,
        reason: 'A remote copy must not echo back to the same phone.',
      );
      local = 'new local';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(sent, [
        {'deviceId': 'a', 'text': 'new local'},
      ]);
      await tester.pump(const Duration(seconds: 2));
      expect(sent, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
}
