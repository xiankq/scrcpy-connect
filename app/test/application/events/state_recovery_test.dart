import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/events/state_recovery.dart';

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
      'session.launch',
      'apps.launch',
      'audio.start',
      'observation.start',
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

  test('本地分享在媒体收尾期间变化时，旧组合快照不能覆盖新终态', () async {
    final first = Completer<StateJson>();
    final events = <StateJson>[];
    var reads = 0;
    final recovery = StateRecovery(
      read: (_) async {
        if (++reads == 1) return first.future;
        return {
          ...snapshot(7),
          'shares': [
            {'shareId': 'share', 'status': 'ready'},
          ],
        };
      },
      emit: events.add,
      isDisposed: () => false,
    );
    final result = recovery.refresh();
    recovery.noteLocalStateChange();
    first.complete({
      ...snapshot(7),
      'shares': [
        {'shareId': 'share', 'status': 'importing'},
      ],
    });
    expect(((await result)['shares'] as List).single['status'], 'ready');
    expect(reads, 2);
    expect(events.where((e) => e['type'] == 'state.resynced'), hasLength(1));
    expect(recovery.pending, isFalse);
    recovery.noteLocalStateChange();
    expect(recovery.pending, isFalse, reason: '普通本地变化不等于全局失去状态');
    recovery.dispose();
  });

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
    await expectLater(
      recovery.refresh(),
      throwsA(isA<ApplicationCommandException>()),
    );
    expect(recovery.pending, isTrue);
    expect(events.last['type'], 'state.resync.failed');
    recovery.dispose();
  });

  test('开始通知及失败通知同时抛错，原操作仍结算并允许显式重试', () async {
    final failure = StateError('开始通知失败');
    var shouldFail = true;
    var reads = 0;
    final recovery = StateRecovery(
      read: (_) async {
        reads++;
        return snapshot(1);
      },
      emit: (event) {
        if (!shouldFail) return;
        if (event['type'] == 'state.resync') throw failure;
        throw StateError('失败通知也失败');
      },
      isDisposed: () => false,
    );
    Future<StateJson>? operation;
    expect(() => operation = recovery.refresh(), returnsNormally);
    await expectLater(operation, throwsA(same(failure)));
    expect(reads, 0);
    expect(recovery.pending, isTrue);
    expect(recovery.hasSnapshot, isFalse);
    expect(
      recovery.accept({'type': 'session.updated', 'sequence': 1}),
      isFalse,
    );
    shouldFail = false;
    expect((await recovery.refresh())['sequence'], 1);
    expect(reads, 1);
    expect(recovery.pending, isFalse);
    recovery.dispose();
  });

  test('成功回执抛错不能推进水位或放行输入，即使失败回执也抛错', () async {
    final failure = StateError('成功回执失败');
    var shouldFail = true;
    var reads = 0;
    final recovery = StateRecovery(
      read: (_) async => snapshot(++reads),
      emit: (event) {
        if (!shouldFail) return;
        if (event['type'] == 'state.resynced') throw failure;
        if (event['type'] == 'state.resync.failed') {
          throw StateError('失败回执失败');
        }
      },
      isDisposed: () => false,
    );
    await expectLater(recovery.refresh(), throwsA(same(failure)));
    expect(recovery.pending, isTrue);
    expect(recovery.hasSnapshot, isFalse);
    expect(
      recovery.accept({'type': 'session.updated', 'sequence': 2}),
      isFalse,
    );
    shouldFail = false;
    expect((await recovery.refresh())['sequence'], 2);
    expect(recovery.pending, isFalse);
    recovery.dispose();
  });

  test('读取失败且失败通知抛错，调用者仍收到原始读取错误', () async {
    final failure = StateError('读取失败');
    var shouldFail = true;
    final recovery = StateRecovery(
      read: (_) async {
        if (shouldFail) throw failure;
        return snapshot(1);
      },
      emit: (event) {
        if (event['type'] == 'state.resync.failed') {
          throw StateError('无法通知');
        }
      },
      isDisposed: () => false,
    );
    await expectLater(recovery.refresh(), throwsA(same(failure)));
    expect(recovery.pending, isTrue);
    shouldFail = false;
    await recovery.refresh();
    expect(recovery.pending, isFalse);
    recovery.dispose();
  });

  test('开始和成功回执同步重入时共享同一未结算操作', () async {
    final reading = Completer<StateJson>();
    final reentered = <Future<StateJson>>[];
    late StateRecovery recovery;
    recovery = StateRecovery(
      read: (_) => reading.future,
      emit: (event) {
        if (event['type'] != 'state.resync.failed') {
          reentered.add(recovery.refresh());
        }
      },
      isDisposed: () => false,
    );
    final result = recovery.refresh();
    expect(reentered.single, same(result));
    reading.complete(snapshot(1));
    await result;
    expect(reentered, [same(result), same(result)]);
    expect(recovery.pending, isFalse);
    recovery.dispose();
  });

  test('失败回执同步发起新恢复，旧失败不能清除后继操作或水位栅栏', () async {
    final failure = StateError('首次读取失败');
    final nextRead = Completer<StateJson>();
    var reads = 0;
    Future<StateJson>? retry;
    late StateRecovery recovery;
    recovery = StateRecovery(
      read: (_) async {
        if (++reads == 1) throw failure;
        return nextRead.future;
      },
      emit: (event) {
        if (event['type'] == 'state.resync.failed') {
          retry = recovery.refresh();
          throw StateError('通知重入后失败');
        }
      },
      isDisposed: () => false,
    );
    await expectLater(recovery.refresh(), throwsA(same(failure)));
    expect(reads, 2);
    expect(retry, isNotNull);
    expect(recovery.refresh(), same(retry));
    expect(recovery.pending, isTrue);
    nextRead.complete(snapshot(3));
    expect((await retry!)['sequence'], 3);
    expect(recovery.pending, isFalse);
    recovery.dispose();
  });
}
