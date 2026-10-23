import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

Matcher _code(String code) =>
    isA<InteropException>().having((e) => e.code, 'code', code);

void main() {
  test('playback changes wait for actual snapshot completion', () async {
    final operations = VideoPlayerOperations();
    final pixels = Completer<int>();
    final calls = <String>[];
    final snapshot = operations.run(() {
      calls.add('snapshot');
      return pixels.future;
    });
    final pause = operations.run(() async => calls.add('pause'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['snapshot']);
    pixels.complete(42);
    expect(await snapshot, 42);
    await pause;
    expect(calls, ['snapshot', 'pause']);
    await operations.close();
  });

  test(
    'caller timeout does not free a native snapshot or allow early disposal',
    () async {
      final operations = VideoPlayerOperations();
      final pixels = Completer<int>();
      final snapshot = operations.run(() => pixels.future);
      await expectLater(
        snapshot.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      var disposed = false;
      final retiring = operations.close().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, false);
      pixels.complete(42);
      await snapshot;
      await retiring;
      expect(disposed, true);
    },
  );

  test(
    'closing rejects queued changes and later snapshots before native calls',
    () async {
      final operations = VideoPlayerOperations();
      final pixels = Completer<int>();
      final snapshot = operations.run(() => pixels.future);
      await Future<void>.delayed(Duration.zero);
      var touched = false;
      final queued = operations.run(() async => touched = true);
      final rejected = expectLater(queued, throwsA(_code('cancelled')));
      final closed = operations.close();
      await expectLater(
        operations.run(() async => touched = true),
        throwsA(_code('cancelled')),
      );
      pixels.complete(42);
      await snapshot;
      await rejected;
      await closed;
      expect(touched, false);
    },
  );

  test(
    'failed snapshots preserve their error and do not strand subsequent work',
    () async {
      final operations = VideoPlayerOperations();
      final failure = StateError('native read failed');
      await expectLater(
        operations.run<int>(() async => throw failure),
        throwsA(same(failure)),
      );
      expect(await operations.run(() async => 7), 7);
      await operations.close();
    },
  );

  test(
    'a stalled native operation cannot accumulate an unbounded queue',
    () async {
      final operations = VideoPlayerOperations();
      final pixels = Completer<int>();
      final first = operations.run(() => pixels.future);
      await Future<void>.delayed(Duration.zero);
      final queued = [
        for (var i = 0; i < 7; i++) operations.run(() async => i),
      ];
      await expectLater(
        operations.run(() async => -1),
        throwsA(_code('renderer_busy')),
      );
      pixels.complete(42);
      expect(await first, 42);
      expect(await Future.wait(queued), [0, 1, 2, 3, 4, 5, 6]);
      await operations.close();
    },
  );
}
