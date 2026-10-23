import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/test_controller.dart';

class _AudioFixture {
  final calls = <(String, Json)>[];
  final sources = <String, Json>{};
  final sessions = <Json>[
    {'sessionId': 'a-screen', 'deviceId': 'a', 'status': 'streaming'},
    {'sessionId': 'a-app', 'deviceId': 'a', 'status': 'streaming'},
    {'sessionId': 'b-screen', 'deviceId': 'b', 'status': 'streaming'},
  ];
  final events = StreamController<Json>.broadcast(sync: true);
  final pendingStarts = <String, Completer<Json>>{};
  Completer<Json>? pendingSources;
  Completer<Json>? pendingSessions;
  final failingDevices = <String>{};
  late final controller =
      createTestController((command, [params = const {}]) async {
          calls.add((command, Map.of(params)));
          final device = value(params, 'deviceId');
          if (command == 'audio.sources') {
            return pendingSources?.future ??
                {'sources': sources.values.toList()};
          }
          if (command == 'session.list') {
            return pendingSessions?.future ?? {'sessions': sessions};
          }
          if (command == 'audio.start') {
            if (failingDevices.contains(device)) {
              throw StateError('unsupported $device');
            }
            final source = sources[device] = {
              'deviceId': device,
              'sourceId': 'source-$device',
              'status': 'playing',
            };
            return pendingStarts[device]?.future ?? source;
          }
          if (command == 'audio.stop') {
            if (params['sourceId'] == null ||
                sources[device]?['sourceId'] == params['sourceId']) {
              sources.remove(device);
            }
            return {};
          }
          return {};
        }, events: events.stream)
        ..devices = [
          {'id': 'a', 'status': 'connected'},
          {'id': 'b', 'status': 'connected'},
        ];

  Future<void> dispose() async {
    controller.dispose();
    await events.close();
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('event bursts coalesce while an audio state read is pending', (
    tester,
  ) async {
    final fixture = _AudioFixture();
    final pending = fixture.pendingSources = Completer<Json>();
    final close = fixture.controller.claimRemoteDeviceView('a');
    await _flush(tester);
    for (var i = 0; i < 50; i++) {
      fixture.events.add({
        'type': 'session.updated',
        'deviceId': 'a',
        'data': fixture.sessions.first,
      });
      await tester.pump();
    }
    expect(
      fixture.calls.where((call) => call.$1 == 'audio.sources'),
      hasLength(1),
    );
    fixture.pendingSources = null;
    pending.complete({'sources': <Json>[]});
    await _flush(tester);
    expect(fixture.sources.keys, ['a']);
    expect(
      fixture.calls.where((call) => call.$1 == 'audio.sources'),
      hasLength(2),
    );
    expect(
      fixture.calls.where((call) => call.$1 == 'audio.start'),
      hasLength(1),
    );
    close();
    await _flush(tester);
    expect(fixture.sources, isEmpty);
    await fixture.dispose();
  });

  testWidgets('an old source snapshot cannot restart a just completed start', (
    tester,
  ) async {
    final fixture = _AudioFixture();
    final starting = fixture.pendingStarts['a'] = Completer<Json>();
    final close = fixture.controller.claimRemoteDeviceView('a');
    await _flush(tester);
    expect(
      fixture.calls.where((call) => call.$1 == 'audio.start'),
      hasLength(1),
    );

    final sources = fixture.pendingSources = Completer<Json>();
    final sessions = fixture.pendingSessions = Completer<Json>();
    fixture.events.add({
      'type': 'session.updated',
      'deviceId': 'a',
      'data': fixture.sessions.first,
    });
    await _flush(tester);
    fixture.pendingSources = null;
    sources.complete({'sources': <Json>[]});
    await _flush(tester);
    starting.complete(fixture.sources['a']);
    await _flush(tester);
    fixture.pendingSessions = null;
    sessions.complete({'sessions': fixture.sessions});
    await _flush(tester);
    expect(
      fixture.calls.where((call) => call.$1 == 'audio.start'),
      hasLength(1),
    );
    close();
    await _flush(tester);
    await fixture.dispose();
  });

  testWidgets(
    'connected devices and ordinary device focus never enable sound',
    (tester) async {
      final fixture = _AudioFixture();
      await fixture.controller.focusDevice('a');
      await fixture.controller.focusDevice('b');
      await _flush(tester);
      expect(fixture.calls, isEmpty);
      expect(fixture.sources, isEmpty);
      await fixture.dispose();
    },
  );

  testWidgets(
    'opened remote pages mix device sound and deduplicate same-device windows',
    (tester) async {
      final fixture = _AudioFixture();
      final closeA = fixture.controller.claimRemoteDeviceView('a');
      final closeAppA = fixture.controller.claimRemoteDeviceView('a');
      final closeB = fixture.controller.claimRemoteDeviceView('b');
      await _flush(tester);
      expect(fixture.sources.keys, unorderedEquals(['a', 'b']));
      expect(
        fixture.calls.where((call) => call.$1 == 'audio.start'),
        hasLength(2),
      );
      await fixture.controller.focusDevice('b');
      await _flush(tester);
      expect(fixture.sources.keys, unorderedEquals(['a', 'b']));
      closeA();
      await _flush(tester);
      expect(fixture.sources.keys, unorderedEquals(['a', 'b']));
      closeAppA();
      closeAppA();
      await _flush(tester);
      expect(fixture.sources.keys, ['b']);
      expect(fixture.calls.where((call) => call.$1 == 'audio.stop').single.$2, {
        'deviceId': 'a',
      });
      closeB();
      await _flush(tester);
      expect(fixture.sources, isEmpty);
      expect(fixture.calls.where((call) => call.$1 == 'session.stop'), isEmpty);
      await fixture.dispose();
    },
  );

  testWidgets(
    'a page waiting for its first session starts sound after capture becomes available',
    (tester) async {
      final fixture = _AudioFixture();
      fixture.sessions.clear();
      final close = fixture.controller.claimRemoteDeviceView('a');
      await _flush(tester);
      expect(fixture.sources, isEmpty);
      fixture.sessions.add({
        'sessionId': 'new-a',
        'deviceId': 'a',
        'status': 'streaming',
      });
      fixture.events.add({
        'type': 'session.updated',
        'deviceId': 'a',
        'data': fixture.sessions.single,
      });
      await _flush(tester);
      expect(fixture.sources.keys, ['a']);
      close();
      await _flush(tester);
      await fixture.dispose();
    },
  );

  testWidgets(
    'closing the last page during a pending start discards and cleans up its late source',
    (tester) async {
      final fixture = _AudioFixture();
      final pending = fixture.pendingStarts['a'] = Completer<Json>();
      final close = fixture.controller.claimRemoteDeviceView('a');
      await _flush(tester);
      expect(
        fixture.calls.where((call) => call.$1 == 'audio.start'),
        hasLength(1),
      );
      close();
      pending.complete({
        'deviceId': 'a',
        'sourceId': 'source-a',
        'status': 'playing',
      });
      await _flush(tester);
      expect(fixture.sources, isEmpty);
      expect(
        fixture.calls.where((call) => call.$1 == 'audio.stop'),
        isNotEmpty,
      );
      await fixture.dispose();
    },
  );

  testWidgets(
    'lost sessions stop device sound while another open device continues',
    (tester) async {
      final fixture = _AudioFixture();
      final closeA = fixture.controller.claimRemoteDeviceView('a');
      final closeB = fixture.controller.claimRemoteDeviceView('b');
      await _flush(tester);
      fixture.sessions.removeWhere((session) => session['deviceId'] == 'a');
      fixture.events.add({
        'type': 'session.disconnected',
        'deviceId': 'a',
        'data': {'sessionId': 'a-screen', 'deviceId': 'a', 'status': 'stopped'},
      });
      await _flush(tester);
      expect(fixture.sources.keys, ['b']);
      closeA();
      closeB();
      await _flush(tester);
      await fixture.dispose();
    },
  );

  testWidgets('closing playing B stops it while A startup is still pending', (
    tester,
  ) async {
    final fixture = _AudioFixture();
    final pending = fixture.pendingStarts['a'] = Completer<Json>();
    final closeA = fixture.controller.claimRemoteDeviceView('a');
    final closeB = fixture.controller.claimRemoteDeviceView('b');
    await _flush(tester);
    expect(fixture.sources['b']?['status'], 'playing');
    closeB();
    await _flush(tester);
    expect(fixture.sources.containsKey('b'), isFalse);
    expect(pending.isCompleted, isFalse);
    closeA();
    await _flush(tester);
    expect(
      fixture.calls.where(
        (call) => call.$1 == 'audio.stop' && call.$2['deviceId'] == 'a',
      ),
      isNotEmpty,
    );
    expect(pending.isCompleted, isFalse);
    pending.complete({
      'deviceId': 'a',
      'sourceId': 'source-a',
      'status': 'playing',
    });
    await _flush(tester);
    expect(fixture.sources, isEmpty);
    await fixture.dispose();
  });

  testWidgets('unsupported device audio leaves another opened device playing', (
    tester,
  ) async {
    final fixture = _AudioFixture()..failingDevices.add('a');
    final closeA = fixture.controller.claimRemoteDeviceView('a');
    final closeB = fixture.controller.claimRemoteDeviceView('b');
    await _flush(tester);
    expect(fixture.sources.keys, ['b']);
    expect(fixture.controller.audioError, contains('unsupported a'));
    closeA();
    closeB();
    await _flush(tester);
    await fixture.dispose();
  });

  testWidgets(
    'device preference writes merge against the latest queued settings',
    (tester) async {
      final fixture = _AudioFixture();
      final first = fixture.controller.updateDeviceSetting(
        'a',
        'clipboardSync',
        true,
      );
      final second = fixture.controller.updateDeviceSetting(
        'a',
        'showNavigationBar',
        false,
      );
      final third = fixture.controller.updateDeviceSetting(
        'b',
        'clipboardSync',
        true,
      );
      await Future.wait([first, second, third]);
      expect(fixture.controller.settings['deviceSettings'], {
        'a': {'clipboardSync': true, 'showNavigationBar': false},
        'b': {'clipboardSync': true},
      });
      await fixture.dispose();
    },
  );
}
