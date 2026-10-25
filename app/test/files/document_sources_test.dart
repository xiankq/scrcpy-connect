import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/files/document_sources.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/services/files/composite_publication_leases.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';

import 'support/file_executor_fixture.dart';

const batch = '22222222-2222-4222-8222-222222222222';

void main() {
  late Directory cache;
  setUp(
    () async =>
        cache = await Directory.systemTemp.createTemp('document-sources-'),
  );
  tearDown(() async => cache.delete(recursive: true));

  for (final managed in [false, true]) {
    for (final closing in [false, true]) {
      test(
        '${closing ? 'close' : 'device stop'} drains a suspended ${managed ? 'managed' : 'unmanaged'} source lookup',
        () async {
          final publication = _Lookup();
          final executor = FixtureExecutor()..stamps['/source'] = regular;
          final transfers = await TransferCoordinator.open(
            executor: executor,
            dataDirectory: cache,
            publication: publication,
          );
          final pending = transfers.startTransfer('phone', true, [
            {'source': '/source', 'destination': '/sdcard/a.txt'},
          ]);
          final outcome = pending.then<Object?>(
            (value) => value,
            onError: (Object error) => error,
          );
          await publication.entered.future;
          var stopped = false;
          final stopping =
              (closing ? transfers.close() : transfers.cancelDevice('phone'))
                  .then((_) => stopped = true);
          await Future<void>.delayed(Duration.zero);
          final stoppedBeforeLookup = stopped;
          publication.gate.complete(managed ? 'document:owner' : null);
          await stopping.timeout(const Duration(seconds: 3));
          final result = await outcome;
          try {
            expect(stoppedBeforeLookup, isFalse);
            expect(
              result,
              isA<FileFailure>().having(
                (error) => error.code,
                'code',
                'cancelled',
              ),
            );
            expect(executor.calls, isEmpty);
            expect(publication.begins, 0);
            expect(transfers.transfers()['transfers'], isEmpty);
          } finally {
            await transfers.close();
          }
        },
      );
    }
  }

  Future<({String id, String path})> ready(
    DocumentSources owner, {
    int bytes = 3,
  }) async {
    final source = await owner.reserve();
    await Directory(source.path).create();
    await File('${source.path}/a.txt').writeAsBytes(List.filled(bytes, 1));
    await owner.complete(source.id, 'folder');
    return (id: source.id, path: source.path);
  }

  test('a second publication cannot borrow its first completed batch while planning', () async {
    final documents = await DocumentSources.open(cacheDirectory: cache);
    final source = await ready(documents);
    final publication = CompositePublicationLeases(documents: documents);
    await publication.begin(source.id, {
      'items': [
        {'source': source.path, 'destination': '/sdcard/first'},
      ],
    });
    await publication.finish(source.id, {'batchId': batch});
    await File('${cache.path}/file_tasks.v2.journal').writeAsString(
      '${jsonEncode({'version': 2, 'sequence': 1, 'task': _task('old', batch, source.path)})}\n',
      flush: true,
    );
    final executor = FixtureExecutor()
      ..stamps[source.path] = directory
      ..blockList = true;
    final transfers = await TransferCoordinator.open(
      executor: executor,
      dataDirectory: cache,
      publication: publication,
    );
    try {
      await transfers.reconcileShares();
      expect((await documents.store.sources())['leases'], isEmpty);
      final pending = transfers
          .startTransfer('phone', true, [
            {'source': source.path, 'destination': '/sdcard/second'},
          ])
          .then<Object?>((value) => value, onError: (Object error) => error);
      await until(() => executor.calls.contains('list:${source.path}'));
      final freshLease =
          ((await documents.store.sources())['leases'] as List).single as Map;
      expect(freshLease['transferId'], isNotNull);
      expect(freshLease['transferId'], isNot(batch));
      expect(freshLease['publication'], 'publishing');
      await transfers.reconcileShares();
      await documents.release(source.id);
      final retained = await Directory(source.path).exists();
      await transfers.cancelDevice('phone');
      expect(await pending, isA<FileFailure>());
      expect(
        retained,
        isTrue,
        reason:
            'Old completed history must not release a newly publishing owner.',
      );
      expect(
        await Directory(source.path).exists(),
        isFalse,
        reason: 'Cancellation before any new task is durable proves this attempt unpublished.',
      );
    } finally {
      await transfers.close();
    }
  });

  for (final identified in [false, true]) {
    test(
      'cold recovery keeps a second ${identified ? 'identified' : 'legacy unidentified'} unknown attempt despite old completed history',
      () async {
        final documents = await DocumentSources.open(cacheDirectory: cache);
        final source = await ready(documents);
        const nextBatch = '33333333-3333-4333-8333-333333333333';
        Map<String, Object?> proof(List<String> ids) => {
          'complete': true,
          'transfers': [
            for (final id in ids)
              {
                'id': id,
                'status': 'completed',
                'sources': [source.path],
              },
          ],
        };
        await documents.begin(source.id, {
          'items': [
            {'source': source.path, 'destination': '/sdcard/first'},
          ],
        }, transferId: batch);
        await documents.finish(source.id, {'batchId': batch});
        await documents.store.reconcile(proof([batch]));
        await documents.begin(source.id, {
          'items': [
            {'source': source.path, 'destination': '/sdcard/second'},
          ],
        }, transferId: identified ? nextBatch : null);
        final recovered = await DocumentSources.open(cacheDirectory: cache);
        await recovered.store.reconcile(proof([batch]));
        expect(await Directory(source.path).exists(), isTrue);
        final leases = (await recovered.store.sources())['leases'] as List;
        expect(leases.single['publication'], 'unknown');
        expect(leases.single['transferId'], identified ? nextBatch : null);
        await recovered.store.reconcile({
          'complete': true,
          'transfers': [
            {
              'id': batch,
              'status': 'completed',
              'sources': [source.path],
            },
            {
              'id': nextBatch,
              'status': 'retained',
              'sources': [source.path],
            },
          ],
        });
        expect(await Directory(source.path).exists(), isTrue);
        await recovered.store.reconcile(proof([batch, nextBatch]));
        expect(
          await Directory(source.path).exists(),
          !identified,
          reason: 'Only the prebound exact attempt can be proven complete.',
        );
      },
    );
  }

  test('page release reclaims an unpublished source and allows reuse of its budget', () async {
    final owner = await DocumentSources.open(
      cacheDirectory: cache,
      totalBytes: 5,
    );
    final source = await ready(owner, bytes: 5);
    await expectLater(owner.reserve(), throwsA(isA<FileFailure>()));
    expect(await Directory(source.path).exists(), isTrue);
    await owner.release(source.id);
    expect(await Directory(source.path).exists(), isFalse);
    final next = await owner.reserve();
    expect(next.availableBytes, 5);
  });

  test(
    'legacy document trees consume the total budget and are never guessed away',
    () async {
      final legacy = File('${cache.path}/documents/old/result');
      await legacy.parent.create(recursive: true);
      await legacy.writeAsBytes(List.filled(4, 1));
      final owner = await DocumentSources.open(
        cacheDirectory: cache,
        totalBytes: 5,
      );
      final reservation = await owner.reserve();
      expect(reservation.availableBytes, 1);
      expect(await legacy.readAsBytes(), List.filled(4, 1));
    },
  );

  test(
    'legacy links make admission fail closed without deleting existing paths',
    () async {
      final legacy = Directory('${cache.path}/documents/old');
      await legacy.create(recursive: true);
      final link = Link('${legacy.path}/outside');
      await link.create(cache.path);
      final owner = await DocumentSources.open(cacheDirectory: cache);
      await expectLater(owner.reserve(), throwsA(isA<FileFailure>()));
      expect(await link.target(), cache.path);
    },
  );

  test(
    'cold recovery releases vanished pages but preserves unknown publications',
    () async {
      final first = await DocumentSources.open(cacheDirectory: cache);
      final unsubmitted = await ready(first);
      final published = await ready(first);
      await first.begin(published.id, {
        'items': [
          {'source': '${published.path}/a.txt', 'destination': '/sdcard/a.txt'},
        ],
      });
      final recovered = await DocumentSources.open(cacheDirectory: cache);
      expect(await Directory(unsubmitted.path).exists(), isFalse);
      expect(await Directory(published.path).exists(), isTrue);
      final result = await recovered.store.sources();
      expect((result['leases'] as List).single['publication'], 'unknown');
      await recovered.release(published.id);
      expect(await Directory(published.path).exists(), isTrue);
    },
  );

  test(
    'proven unpublished admission releases its marker before page release',
    () async {
      final owner = await DocumentSources.open(cacheDirectory: cache);
      final source = await ready(owner);
      await owner.begin(source.id, {
        'items': [
          {'source': source.path, 'destination': '/sdcard/a'},
        ],
      });
      await owner.finish(source.id, null, definitelyUnpublished: true);
      await owner.release(source.id);
      expect(await Directory(source.path).exists(), isFalse);
    },
  );

  for (final retainedChild in [false, true]) {
    test(
      'directory proof includes independent ${retainedChild ? 'failed' : 'completed'} descendant consumers',
      () async {
        final documents = await DocumentSources.open(cacheDirectory: cache);
        final source = await ready(documents);
        final publication = CompositePublicationLeases(documents: documents);
        await publication.begin(source.id, {
          'items': [
            {'source': source.path, 'destination': '/sdcard/folder'},
          ],
        });
        await publication.finish(source.id, {'batchId': batch});
        await documents.release(source.id);
        final tasks = [
          _task('root', batch, source.path),
          {
            ..._task(
              'child',
              '33333333-3333-4333-8333-333333333333',
              '${source.path}/a.txt',
            ),
            'status': retainedChild ? 'failed' : 'completed',
            'errorCode': 'result_unknown',
          },
        ];
        await File('${cache.path}/file_tasks.v2.journal').writeAsString(
          [
            for (var i = 0; i < tasks.length; i++)
              jsonEncode({'version': 2, 'sequence': i + 1, 'task': tasks[i]}),
            '',
          ].join('\n'),
          flush: true,
        );
        final transfers = await TransferCoordinator.open(
          executor: FixtureExecutor(),
          dataDirectory: cache,
          publication: publication,
        );
        try {
          final result = await transfers.reconcileShares();
          expect(result['snapshotComplete'], isTrue);
          expect(await Directory(source.path).exists(), retainedChild);
        } finally {
          await transfers.close();
        }
      },
    );
  }

  test('automatic managed source recognition cannot be bypassed by omitting shareId', () async {
    final documents = await DocumentSources.open(cacheDirectory: cache);
    final source = await ready(documents);
    final executor = FixtureExecutor()
      ..stamps['${source.path}/a.txt'] = regular
      ..blockCopy = true;
    final transfers = await TransferCoordinator.open(
      executor: executor,
      dataDirectory: cache,
      publication: CompositePublicationLeases(documents: documents),
    );
    try {
      final receipt = await transfers.startTransfer('phone', true, [
        {'source': '${source.path}/a.txt', 'destination': '/sdcard/a.txt'},
      ]);
      expect(receipt['batchId'], isNotNull);
      await documents.release(source.id);
      final sources = await documents.store.sources();
      expect(sources['leases'], isNotEmpty);
      expect(await Directory(source.path).exists(), isTrue);
    } finally {
      await transfers.close();
    }
  });
}

final class _Lookup implements ManagedFilePublicationLeases {
  final entered = Completer<void>();
  final gate = Completer<String?>();
  int begins = 0;
  @override
  Future<String?> ownerForSources(List<String> sources) {
    entered.complete();
    return gate.future;
  }

  @override
  Future<Set<String>> get sourcePaths async => {};
  @override
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request, {
    String? transferId,
  }) async {
    begins++;
    return null;
  }

  @override
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) async {}
  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> references, {
    Set<String>? coveredSources,
  }) async => {'reconciled': true};
}

Map<String, Object?> _task(String id, String group, String source) => {
  'id': id,
  'batchId': group,
  'deviceId': 'phone',
  'source': source,
  'destination': '/sdcard/$id',
  'direction': 'push',
  'status': 'completed',
  'kind': 'file',
  'name': id,
  'generation': 0,
};
