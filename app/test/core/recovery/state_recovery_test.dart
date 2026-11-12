import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  test('合并核验请求，等待期间更新事件水位使旧快照重读', () async {
    final reads = <Completer<RuntimeSnapshot>>[];
    final emitted = <RecoveryEvent>[];
    final recovery = StateRecovery(
      read: (_) {
        final read = Completer<RuntimeSnapshot>();
        reads.add(read);
        return read.future;
      },
      emit: emitted.add,
      isDisposed: () => false,
    );
    addTearDown(recovery.dispose);
    final reading = recovery.refresh();
    expect(recovery.refresh(), same(reading));
    expect(recovery.pending, isTrue);
    expect(
      recovery.requireVerifiedState,
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'state_unverified'),
      ),
    );
    expect(recovery.accept(sequence: 9), isFalse);
    reads.first.complete(snapshot(8));
    await Future<void>.delayed(Duration.zero);
    expect(reads, hasLength(2));
    final verified = snapshot(9);
    reads.last.complete(verified);
    expect(await reading, same(verified));
    expect((emitted.last as RecoveryCompleted).snapshot, same(verified));
    expect(recovery.pending, isFalse);
    recovery.requireVerifiedState();
    expect(recovery.accept(sequence: 8), isFalse);
    expect(recovery.accept(sequence: 9), isFalse);
    expect(recovery.accept(sequence: 10), isTrue);
    recovery.dispose();
    expect(
      recovery.requireVerifiedState,
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'disposed')),
    );
  });

  test('缺失水位启动核验，重复缺口要求重读，遥测不推进业务水位', () async {
    final first = Completer<RuntimeSnapshot>();
    var reads = 0;
    final emitted = <RecoveryEvent>[];
    final recovery = StateRecovery(
      read: (_) => ++reads == 1 ? first.future : Future.value(snapshot(0)),
      emit: emitted.add,
      isDisposed: () => false,
    );
    addTearDown(recovery.dispose);
    expect(recovery.accept(sequence: null), isFalse);
    final reading = recovery.refresh();
    recovery.reportGap();
    expect(recovery.accept(sequence: 99, telemetry: true), isFalse);
    first.complete(snapshot(0));
    await reading;
    expect(reads, 2);
    expect(emitted.whereType<RecoveryCompleted>(), hasLength(1));
    expect(recovery.accept(sequence: 1), isTrue);
  });

  test('本地版本变化同样使快照重读，旧水位不能解除核验门禁', () async {
    final first = Completer<RuntimeSnapshot>();
    var reads = 0;
    var next = 3;
    final recovery = StateRecovery(
      read: (_) => ++reads == 1 ? first.future : Future.value(snapshot(next)),
      emit: (_) {},
      isDisposed: () => false,
    );
    addTearDown(recovery.dispose);
    final reading = recovery.refresh();
    recovery.noteLocalStateChange();
    first.complete(snapshot(3));
    await reading;
    expect(reads, 2);
    next = 2;
    await expectLater(
      recovery.refresh(),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'invalid_snapshot'),
      ),
    );
    expect(recovery.pending, isTrue);
    next = 4;
    await recovery.refresh();
    expect(recovery.pending, isFalse);
  });

  test('回执交付失败回滚水位，失败通知再抛错仍结算原失败并允许重试', () async {
    final failure = StateError('delivery failed');
    var reject = true;
    var next = 7;
    final recovery = StateRecovery(
      read: (_) async => snapshot(next),
      emit: (event) {
        if (reject && event is RecoveryCompleted) throw failure;
        if (reject && event is RecoveryFailed) {
          throw StateError('notification failed');
        }
      },
      isDisposed: () => false,
    );
    addTearDown(recovery.dispose);
    await expectLater(recovery.refresh(), throwsA(same(failure)));
    expect(recovery.hasSnapshot, isFalse);
    expect(recovery.pending, isTrue);
    reject = false;
    next = 6;
    await recovery.refresh();
    expect(recovery.hasSnapshot, isTrue);
    expect(recovery.pending, isFalse);
  });

  test('超时使原读取失效，迟到结果不能交付；下一次核验使用新读取', () async {
    final late = Completer<RuntimeSnapshot>();
    late bool Function() current;
    var reads = 0;
    final delivered = <RecoveryEvent>[];
    final recovery = StateRecovery(
      read: (valid) {
        current = valid;
        return ++reads == 1 ? late.future : Future.value(snapshot(2));
      },
      emit: delivered.add,
      isDisposed: () => false,
      timeout: Duration.zero,
    );
    addTearDown(recovery.dispose);
    await expectLater(recovery.refresh(), throwsA(isA<TimeoutException>()));
    expect(current(), isFalse);
    late.complete(snapshot(1));
    await Future<void>.delayed(Duration.zero);
    expect(delivered.whereType<RecoveryCompleted>(), isEmpty);
    await recovery.refresh();
    expect((delivered.last as RecoveryCompleted).snapshot.sequence, 2);
  });
}

RuntimeSnapshot snapshot(int sequence) =>
    RuntimeSnapshot(sequence: sequence, settings: Preferences());
