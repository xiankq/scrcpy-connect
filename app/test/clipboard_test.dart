import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/clipboard_coordinator.dart';

import 'support/test_controller.dart';

class _ClipboardFixture {
  final events = StreamController<Json>.broadcast(sync: true);
  final sent = <Json>[];
  final writes = <String>[];
  final remoteReads = <String>[];
  final remote = <String, String>{'a': 'clipboard a', 'b': 'clipboard b'};
  final pending = <String, Future<Json>>{};
  String local = 'original local';
  late final controller =
      createTestController((command, [params = const {}]) async {
          final device = value(params, 'deviceId');
          if (command == 'clipboard.get') {
            remoteReads.add(device);
            return pending[device] ?? {'text': remote[device]};
          }
          if (command == 'clipboard.set') {
            sent.add(Map.of(params));
            remote[device] = params['text'] as String;
            events.add({
              'type': 'clipboard.changed',
              'deviceId': device,
              'data': {'text': remote[device]},
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
          'deviceSettings': {
            'a': {'clipboardSync': true},
            'b': {'clipboardSync': true},
          },
        };

  Future<void> start(WidgetTester tester, [String device = 'a']) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': local};
          if (call.method == 'Clipboard.setData') {
            local = (call.arguments as Map)['text'] as String;
            writes.add(local);
          }
          return null;
        });
    await controller.focusDevice(device);
    testContainer(controller).read(clipboardCoordinatorProvider);
    await tester.pump();
    await tester.pump();
  }

  void changed(String device, String text) => events.add({
    'type': 'clipboard.changed',
    'deviceId': device,
    'data': {'text': text},
  });

  Future<void> dispose() async {
    controller.dispose();
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

void main() {
  testWidgets(
    'desktop focus return detects an external copy without waiting for the poll tick',
    (tester) async {
      final fixture = _ClipboardFixture();
      await fixture.start(tester);
      fixture.local = 'copied in another window';
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(fixture.sent.single['text'], 'copied in another window');
      await fixture.dispose();
    },
  );
  testWidgets(
    'disconnect intent discards a pending device clipboard read immediately',
    (tester) async {
      final fixture = _ClipboardFixture();
      final pending = Completer<Json>();
      fixture.pending['a'] = pending.future;
      await fixture.start(tester);
      await fixture.controller.request('devices.disconnect', {'deviceId': 'a'});
      pending.complete({'text': 'clipboard from the disconnected device'});
      await tester.pump();
      await tester.pump();
      expect(fixture.local, 'original local');
      expect(fixture.writes, isEmpty);
      expect(fixture.controller.clipboardState, 'waitingDevice');
      await fixture.dispose();
    },
  );
  testWidgets('entering each enabled device takes its clipboard immediately', (
    tester,
  ) async {
    final fixture = _ClipboardFixture();
    await fixture.start(tester);
    expect(fixture.local, 'clipboard a');
    expect(fixture.sent, isEmpty);
    await fixture.controller.focusDevice('b');
    await tester.pump();
    await tester.pump();
    expect(fixture.local, 'clipboard b');
    fixture.changed('a', 'late a');
    await tester.pump();
    expect(fixture.local, 'clipboard b');
    expect(fixture.controller.clipboardState, 'watching');
    await fixture.dispose();
  });

  testWidgets(
    'a slow previous-device read neither blocks nor overwrites the next device',
    (tester) async {
      final fixture = _ClipboardFixture();
      final old = Completer<Json>();
      fixture.pending['a'] = old.future;
      await fixture.start(tester);
      await fixture.controller.focusDevice('b');
      await tester.pump();
      await tester.pump();
      expect(fixture.local, 'clipboard b');
      expect(fixture.remoteReads, ['a', 'b']);
      old.complete({'text': 'stale a'});
      await tester.pump();
      expect(fixture.local, 'clipboard b');
      fixture.local = 'new copy for b';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(fixture.sent, [
        {'deviceId': 'b', 'text': 'new copy for b'},
      ]);
      await fixture.dispose();
    },
  );

  testWidgets(
    'automatic sync is opt-in for each device and stops immediately when disabled',
    (tester) async {
      final fixture = _ClipboardFixture();
      fixture.controller.settings = {
        'deviceSettings': {
          'a': {'clipboardSync': true},
        },
      };
      await fixture.start(tester);
      await fixture.controller.focusDevice('b');
      await tester.pump();
      fixture.changed('b', 'disabled b');
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.local, 'clipboard a');
      expect(fixture.remoteReads, ['a']);
      expect(fixture.controller.clipboardState, 'disabled');
      await fixture.controller.updateDeviceSetting('b', 'clipboardSync', true);
      await tester.pump();
      await tester.pump();
      expect(fixture.local, 'clipboard b');
      await fixture.controller.updateDeviceSetting('b', 'clipboardSync', false);
      final reads = fixture.controller.clipboardReadCount;
      fixture.local = 'private local';
      fixture.changed('b', 'disabled again');
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.local, 'private local');
      expect(fixture.controller.clipboardReadCount, reads);
      expect(fixture.sent, isEmpty);
      await fixture.dispose();
    },
  );

  testWidgets(
    'foreground return takes current device clipboard without a conflict prompt',
    (tester) async {
      final fixture = _ClipboardFixture();
      await fixture.start(tester);
      final reads = fixture.controller.clipboardReadCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fixture.local = 'local while away';
      fixture.remote['a'] = 'remote while away';
      fixture.changed('a', 'remote while away');
      await tester.pump(const Duration(seconds: 3));
      expect(fixture.local, 'local while away');
      expect(fixture.controller.clipboardReadCount, reads);
      expect(fixture.controller.clipboardState, 'waitingForeground');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(fixture.local, 'remote while away');
      expect(fixture.controller.clipboardState, 'watching');
      expect(fixture.sent, isEmpty);
      await fixture.dispose();
    },
  );

  testWidgets(
    'device events win concurrent edits and suppress both echo directions',
    (tester) async {
      final fixture = _ClipboardFixture();
      await fixture.start(tester);
      fixture.local = 'concurrent local';
      fixture.changed('a', 'new remote');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.local, 'new remote');
      expect(fixture.sent, isEmpty);
      fixture.local = 'new local';
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.sent, [
        {'deviceId': 'a', 'text': 'new local'},
      ]);
      expect(fixture.controller.clipboardState, 'watching');
      await fixture.dispose();
    },
  );

  testWidgets(
    'reconciliation freezes old work and recovery reads the current device again',
    (tester) async {
      final fixture = _ClipboardFixture();
      await fixture.start(tester);
      fixture.events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      final writes = fixture.writes.length;
      final reads = fixture.controller.clipboardReadCount;
      fixture.changed('a', 'unverified remote');
      fixture.local = 'local during verification';
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.writes, hasLength(writes));
      expect(fixture.controller.clipboardReadCount, reads);
      expect(fixture.controller.clipboardState, 'waitingVerification');
      fixture.remote['a'] = 'verified remote';
      fixture.events.add({
        'type': 'state.resynced',
        'data': {
          'devices': fixture.controller.devices,
          'settings': fixture.controller.settings,
          'sessions': <Json>[],
          'shares': <Json>[],
          'sequence': 3,
        },
      });
      await tester.pump();
      await tester.pump();
      expect(fixture.local, 'verified remote');
      expect(fixture.sent, isEmpty);
      await fixture.dispose();
    },
  );
}
