import 'dart:async';

import 'package:device_runtime/src/native_runtime.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host implements FlutterAdb {
  int attempts = 0;
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<void> close() async {
    attempts++;
    await gate?.future;
    if (fail) throw StateError('owned server still running');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'runtime shutdown retries the retained ADB host after close fails',
    () async {
      final host = _Host()..fail = true;
      final owner = NativeAdbHostOwner()..pending = Future.value(host);
      final shutdown = NativeRuntimeShutdown();
      var coreShutdowns = 0;
      Future<void> closeRuntime() async {
        try {
          coreShutdowns++;
        } finally {
          await owner.close();
        }
      }

      await expectLater(shutdown.run(closeRuntime), throwsStateError);
      expect(await owner.pending, same(host));
      host.fail = false;
      host.gate = Completer<void>();
      final retry = shutdown.run(closeRuntime);
      expect(shutdown.run(closeRuntime), same(retry));
      await Future<void>.delayed(Duration.zero);
      expect(host.attempts, 2);
      host.gate!.complete();
      await retry;
      expect(owner.pending, isNull);
      await shutdown.run(closeRuntime);
      expect(coreShutdowns, 2);
      expect(host.attempts, 2);
    },
  );

  test('failed native ADB shutdown retains its owner for a retry', () async {
    final host = _Host()..fail = true;
    final owner = NativeAdbHostOwner()..pending = Future.value(host);
    await expectLater(owner.close(), throwsStateError);
    expect(await owner.pending, same(host));
    expect(owner.closingRequested, isTrue);
    host.fail = false;
    await owner.close();
    expect(host.attempts, 2);
    expect(owner.pending, isNull);
    expect(owner.closingRequested, isFalse);
  });

  test(
    'concurrent shutdowns share cleanup and release only afterward',
    () async {
      final host = _Host()..gate = Completer<void>();
      final owner = NativeAdbHostOwner()..pending = Future.value(host);
      final first = owner.close();
      final second = owner.close();
      expect(identical(first, second), isTrue);
      expect(owner.pending, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(host.attempts, 1);
      host.gate!.complete();
      await first;
      expect(owner.pending, isNull);
    },
  );
}
