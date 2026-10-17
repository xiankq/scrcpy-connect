import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/state_recovery.dart';

StateJson snapshot(int sequence) => {
  'sequence': sequence,
  'settings': {'appearance': 'dark'},
  for (final key in [
    'devices',
    'sessions',
    'sources',
    'transfers',
    'activities',
    'shares',
    'companions',
  ])
    key: <StateJson>[],
};

void main() {
  test('unverified state blocks new input and observation startup but permits exact release and stop', () {
    for (final command in [
      'session.start',
      'session.resume',
      'session.text',
      'apps.launch',
      'audio.start',
      'observation.start',
      'notifications.reply',
      'clipboard.set',
    ]) {
      expect(needsVerifiedState(command, {}), isTrue, reason: command);
    }
    for (final command in [
      'session.stop',
      'session.pause',
      'audio.stop',
      'devices.disconnect',
      'transfers.cancel',
      'session.list',
      'observation.list',
      'observation.status',
      'observation.stop',
      'notifications.list',
      'calls.list',
    ]) {
      expect(needsVerifiedState(command, {}), isFalse, reason: command);
    }
    expect(
      needsVerifiedState('session.key', {'sessionId': 'A', 'action': 'down'}),
      isTrue,
    );
    expect(
      needsVerifiedState('session.key', {'deviceId': 'A', 'action': 'up'}),
      isTrue,
    );
    expect(
      needsVerifiedState('session.key', {'sessionId': 'A', 'action': 'up'}),
      isFalse,
    );
    expect(
      needsVerifiedState('session.touch', {
        'sessionId': 'A',
        'action': 'cancel',
      }),
      isFalse,
    );
  });
  test(
    'a snapshot fences delayed events and coalesces concurrent retries',
    () async {
      final events = <StateJson>[];
      final reading = Completer<StateJson>();
      var reads = 0;
      final recovery = StateRecovery(
        read: (_) {
          reads++;
          return reading.future;
        },
        emit: events.add,
        isDisposed: () => false,
      );
      expect(
        recovery.accept({'type': 'settings.changed', 'sequence': 1}),
        isTrue,
      );
      final first = recovery.refresh();
      final second = recovery.refresh();
      expect(identical(first, second), isTrue);
      expect(recovery.pending, isTrue);
      expect(events.single['type'], 'state.resync');
      expect(
        recovery.accept({'type': 'settings.changed', 'sequence': 2}),
        isFalse,
      );
      reading.complete(snapshot(4));
      await first;
      expect(reads, 1);
      expect(recovery.pending, isFalse);
      expect(events.last['type'], 'state.resynced');
      expect(
        recovery.accept({'type': 'settings.changed', 'sequence': 3}),
        isFalse,
      );
      expect(
        recovery.accept({'type': 'session.updated', 'sequence': 4}),
        isFalse,
      );
      expect(
        recovery.accept({'type': 'session.updated', 'sequence': 5}),
        isTrue,
      );
      recovery.dispose();
    },
  );

  test(
    'state arriving during owner cleanup requires a newer snapshot',
    () async {
      final events = <StateJson>[];
      final reads = <Completer<StateJson>>[];
      final recovery = StateRecovery(
        read: (_) {
          final next = Completer<StateJson>();
          reads.add(next);
          return next.future;
        },
        emit: events.add,
        isDisposed: () => false,
      );
      final result = recovery.refresh();
      expect(
        recovery.accept({'type': 'session.disconnected', 'sequence': 8}),
        isFalse,
      );
      reads[0].complete(snapshot(7));
      await Future<void>.delayed(Duration.zero);
      expect(reads.length, 2);
      expect(
        events.where((event) => event['type'] == 'state.resynced'),
        isEmpty,
      );
      reads[1].complete(snapshot(8));
      expect((await result)['sequence'], 8);
      expect(events.last['type'], 'state.resynced');
      recovery.dispose();
    },
  );

  test(
    'a second transport gap during a read is not hidden by its result',
    () async {
      final reads = <Completer<StateJson>>[];
      final recovery = StateRecovery(
        read: (_) {
          final next = Completer<StateJson>();
          reads.add(next);
          return next.future;
        },
        emit: (_) {},
        isDisposed: () => false,
      );
      final result = recovery.refresh();
      recovery.accept({'type': 'state.resync'});
      reads[0].complete(snapshot(10));
      await Future<void>.delayed(Duration.zero);
      expect(reads.length, 2);
      reads[1].complete(snapshot(11));
      expect((await result)['sequence'], 11);
      recovery.dispose();
    },
  );

  test(
    'failure remains unverified and an explicit retry can recover',
    () async {
      var fail = true;
      final events = <StateJson>[];
      final recovery = StateRecovery(
        read: (_) async {
          if (fail) throw StateError('unavailable');
          return snapshot(1);
        },
        emit: events.add,
        isDisposed: () => false,
      );
      await expectLater(recovery.refresh(), throwsStateError);
      expect(recovery.pending, isTrue);
      expect(events.last['type'], 'state.resync.failed');
      expect(
        recovery.accept({'type': 'session.updated', 'sequence': 1}),
        isFalse,
      );
      fail = false;
      await recovery.refresh();
      expect(recovery.pending, isFalse);
      recovery.dispose();
    },
  );

  test('timed out or disposed reads cannot publish a late recovery', () async {
    for (final dispose in [false, true]) {
      final reading = Completer<StateJson>();
      final events = <StateJson>[];
      late bool Function() owned;
      final recovery = StateRecovery(
        read: (current) {
          owned = current;
          return reading.future;
        },
        emit: events.add,
        isDisposed: () => false,
        timeout: const Duration(milliseconds: 10),
      );
      final result = recovery.refresh();
      final failed = expectLater(result, throwsA(isA<Object>()));
      if (dispose) recovery.dispose();
      await failed;
      expect(owned(), isFalse);
      reading.complete(snapshot(99));
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((event) => event['type'] == 'state.resynced'),
        isEmpty,
      );
      recovery.dispose();
    }
  });

  test('malformed snapshots cannot authorize an empty activity set', () async {
    final events = <StateJson>[];
    final recovery = StateRecovery(
      read: (_) async => {'sequence': 1, 'settings': <String, dynamic>{}},
      emit: events.add,
      isDisposed: () => false,
    );
    await expectLater(recovery.refresh(), throwsA(isA<InteropException>()));
    expect(recovery.pending, isTrue);
    expect(events.last['type'], 'state.resync.failed');
    recovery.dispose();
  });
}
