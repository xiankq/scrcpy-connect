import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

void main() {
  test(
    'requests before querying and confirms even without a Dart callback',
    () async {
      final changes = StreamController<String>.broadcast();
      final calls = <String>[];
      final owner = PlaybackConfirmation<String>(
        changes: changes.stream,
        request: (target) => calls.add('request:$target'),
        query: (target) {
          calls.add('query:$target');
          return true;
        },
      );
      final receipt = await owner.set('playing');
      expect(calls, ['request:playing', 'query:playing']);
      expect(receipt.queries, 1);
      await owner.close();
      await changes.close();
    },
  );

  test(
    'delayed old callback cannot acknowledge an opposite native state',
    () async {
      final changes = StreamController<String>.broadcast();
      var actual = 'playing';
      final requests = <String>[];
      final owner = PlaybackConfirmation<String>(
        changes: changes.stream,
        request: requests.add,
        query: (target) => target == actual,
        interval: const Duration(milliseconds: 1),
      );
      await owner.set('playing');
      actual = 'paused'; // Native pause confirmed ahead of its queued callback.
      await owner.set('paused');
      var resumed = false;
      final resume = owner.set('playing').then((_) => resumed = true);
      changes.add('playing'); // Earlier play callback, delivered late.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(resumed, false);
      expect(requests, ['playing', 'paused', 'playing']);
      actual = 'playing';
      changes.add(
        'paused',
      ); // Even an irrelevant callback triggers a real query.
      await resume;
      await owner.close();
      await changes.close();
    },
  );

  test('close drains pending waits before native deletion and prevents late queries', () async {
    final changes = StreamController<String>.broadcast();
    var queries = 0, requests = 0;
    var deleted = false;
    final owner = PlaybackConfirmation<String>(
      changes: changes.stream,
      request: (_) {
        expect(deleted, false);
        requests++;
      },
      query: (_) {
        expect(deleted, false);
        queries++;
        return false;
      },
      interval: const Duration(milliseconds: 1),
    );
    final pending = expectLater(
      owner.set('paused'),
      throwsA(isA<InteropException>()),
    );
    await owner.close();
    deleted = true;
    await pending;
    final count = queries;
    changes.add('paused');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(queries, count);
    await expectLater(owner.set('playing'), throwsA(isA<InteropException>()));
    expect(requests, 1);
    await owner.close();
    await changes.close();
  });

  test(
    'timeout and native query failure remain failures and leave no polling',
    () async {
      final changes = StreamController<String>.broadcast();
      var queries = 0;
      final owner = PlaybackConfirmation<String>(
        changes: changes.stream,
        request: (_) {},
        query: (_) {
          queries++;
          return false;
        },
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 5),
      );
      await expectLater(owner.set('paused'), throwsA(isA<TimeoutException>()));
      final count = queries;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(queries, count);
      await owner.close();
      final broken = PlaybackConfirmation<String>(
        changes: changes.stream,
        request: (_) {},
        query: (_) => throw StateError('native query failed'),
      );
      await expectLater(broken.set('playing'), throwsStateError);
      await broken.close();
      await changes.close();
    },
  );

  for (final synchronous in [true, false]) {
    test(
      'failed request hook drains confirmation (sync=$synchronous)',
      () async {
        final changes = StreamController<String>.broadcast();
        final calls = <String>[];
        var actual = false;
        final owner = PlaybackConfirmation<String>(
          changes: changes.stream,
          request: (_) => calls.add('native'),
          query: (_) => actual,
        );
        final failure = StateError('refresh failed');
        var settled = false;
        final pending = owner
            .set(
              'paused',
              onRequested: () {
                calls.add('refresh');
                if (synchronous) throw failure;
                return Future<void>.error(failure);
              },
            )
            .whenComplete(() => settled = true);
        final rejected = expectLater(pending, throwsA(same(failure)));
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['native', 'refresh']);
        expect(
          settled,
          false,
          reason: 'Failed refresh cannot release pending native queries.',
        );
        actual = true;
        changes.add('paused');
        await rejected;
        await owner.close();
        await changes.close();
      },
    );
  }

  test('submission failure never invokes the refresh hook', () async {
    final changes = StreamController<String>.broadcast();
    var refreshed = false;
    final owner = PlaybackConfirmation<String>(
      changes: changes.stream,
      request: (_) => throw StateError('native submission failed'),
      query: (_) => false,
    );
    await expectLater(
      owner.set('paused', onRequested: () async => refreshed = true),
      throwsStateError,
    );
    expect(refreshed, false);
    await owner.close();
    await changes.close();
  });
}
