import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/clipboard_visibility.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/clipboard_sync_store.dart';

import 'support/test_controller.dart';

Json _enabled(List<String> devices) => {
  'deviceSettings': {
    for (final device in devices) device: {'clipboardSync': true},
  },
};

Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void _windowFocus(WidgetTester tester, ViewFocusState state) =>
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: state,
        direction: ViewFocusDirection.undefined,
      ),
    );

class _ClipboardFixture {
  final events = StreamController<Json>.broadcast(sync: true);
  final sent = <Json>[];
  final writes = <String>[];
  final remoteReads = <String>[];
  final remote = <String, String>{'a': 'clipboard a', 'b': 'clipboard b'};
  final pending = <String, Future<Json>>{};
  String? local = 'original local';
  bool ignoreWrite = false;
  late final controller =
      createTestController((command, params) async {
          final device = value(params, 'deviceId');
          if (command == 'clipboard.get') {
            remoteReads.add(device);
            return pending[device] ?? {'text': remote[device]};
          }
          if (command == 'clipboard.set') {
            sent.add(Map.of(params));
            remote[device] = params['text'] as String;
            changed(device, remote[device]!);
            return {'applied': true};
          }
          return {};
        }, events: events.stream)
        ..devices = [
          {'id': 'a', 'status': 'connected'},
          {'id': 'b', 'status': 'connected'},
        ]
        ..settings = _enabled(['a', 'b']);

  Future<void> start(WidgetTester tester, [String device = 'a']) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return local == null ? null : {'text': local};
          }
          if (call.method == 'Clipboard.setData') {
            final text = (call.arguments as Map)['text'] as String;
            if (!ignoreWrite) local = text;
            writes.add(text);
          }
          return null;
        });
    await focus(device);
    final sync = testContainer(controller).read(clipboardSyncProvider);
    await tester.pumpWidget(
      HookBuilder(
        builder: (context) {
          useClipboardVisibility(sync);
          return const SizedBox();
        },
      ),
    );
    await _drain(tester);
  }

  Future<void> focus(String device) async {
    controller.focusClipboardSession(device, 'session-$device', true);
    await controller.focusDevice(device);
  }

  void changed(String device, String text) => events.add({
    'type': 'clipboard.changed',
    'deviceId': device,
    'data': {'text': text, 'sessionId': 'session-$device'},
  });

  Future<void> dispose() async {
    controller.dispose();
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

void main() {
  testWidgets('同设备替换连接后拒绝旧读取并重新取得新连接剪贴板', (tester) async {
    final fixture = _ClipboardFixture();
    final oldRead = Completer<Json>();
    fixture.controller.devices = [
      {'id': 'a', 'status': 'connected', 'connectionId': 'connection-1'},
    ];
    fixture.pending['a'] = oldRead.future;
    await fixture.start(tester);
    fixture.pending.remove('a');
    fixture.remote['a'] = 'new connection clipboard';
    fixture.controller.devices = [
      {'id': 'a', 'status': 'connected', 'connectionId': 'connection-2'},
    ];
    await _drain(tester);
    oldRead.complete({'text': 'stale connection clipboard'});
    await _drain(tester);
    expect(fixture.remoteReads, ['a', 'a']);
    expect(fixture.local, 'original local');
    expect(fixture.writes, isEmpty);
    expect(fixture.sent, isEmpty);
    await fixture.dispose();
  });

  testWidgets(
    'desktop blur stops sync and focus return preserves copies made elsewhere',
    (tester) async {
      final fixture = _ClipboardFixture();
      await fixture.start(tester);
      _windowFocus(tester, ViewFocusState.unfocused);
      fixture.local = 'copied in another window';
      fixture.changed('a', 'copied while blurred');
      await tester.pump(const Duration(seconds: 2));
      _windowFocus(tester, ViewFocusState.focused);
      await _drain(tester);
      expect(fixture.sent, isEmpty);
      expect(fixture.writes, isEmpty);
      expect(fixture.local, 'copied in another window');
      fixture.local = null;
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.controller.clipboardState, 'limited');
      expect(fixture.controller.clipboardError, contains('无法读取本机文字'));
      for (final text in ['first update', 'second update']) {
        fixture.changed('a', text);
        await _drain(tester);
      }
      expect(fixture.writes, isEmpty);
      expect(fixture.local, isNull);
      expect(fixture.controller.clipboardState, 'limited');
      await fixture.dispose();
    },
  );
  testWidgets(
    'automatic sync is opt-in for each device and stops immediately when disabled',
    (tester) async {
      final fixture = _ClipboardFixture();
      fixture.controller.settings = _enabled(['a']);
      await fixture.start(tester);
      await fixture.focus('b');
      await tester.pump();
      fixture.changed('b', 'disabled b');
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.local, 'original local');
      expect(fixture.remoteReads, ['a']);
      expect(fixture.controller.clipboardState, 'disabled');
      await fixture.controller.updateDeviceSetting('b', 'clipboardSync', true);
      await _drain(tester);
      expect(fixture.local, 'original local');
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
      expect(fixture.sent.single, containsPair('text', 'new local'));
      expect(fixture.controller.clipboardState, 'watching');
      fixture.ignoreWrite = true;
      fixture.changed('a', 'silently rejected by local system');
      await _drain(tester);
      expect(fixture.controller.clipboardState, 'limited');
      expect(fixture.controller.clipboardError, contains('核验一致'));
      final sent = fixture.sent.length;
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.sent, hasLength(sent));
      expect(fixture.local, 'new local');
      await fixture.dispose();
    },
  );
}
