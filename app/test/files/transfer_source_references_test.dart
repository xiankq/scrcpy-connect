import 'package:scrcpy_connect/models/shared_source_file.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/stores/file_share_store.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';

import 'support/file_executor_fixture.dart';

void main() {
  for (final largeBatch in [false, true]) {
    for (final failedConsumer in [false, true]) {
      test(
        '${largeBatch ? 'large unrelated tree' : 'long unrelated history'} '
        'does not prevent checking ${failedConsumer ? 'retained' : 'completed'} share sources',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'source-references-',
          );
          FileTransferService? owner;
          try {
            final store = await FileShareStore.open(cacheDirectory: root);
            const share = '11111111-1111-4111-8111-111111111111';
            const batch = '22222222-2222-4222-8222-222222222222';
            await store.reserve(share);
            final source = File('${store.root.path}/$share/source');
            await source.writeAsBytes([1, 2, 3]);
            await store.complete(share, const [
              SharedSourceFile(diskName: 'source', name: 'source', size: 3),
            ]);
            await store.begin(share, {
              'items': [
                {'source': source.path, 'destination': '/sdcard/source'},
              ],
            });
            await store.finish(share, {'batchId': batch, 'status': 'queued'});
            await store.command('sharing.consume', {'shareId': share});

            final tasks = [
              for (var i = 0; i < (largeBatch ? 2049 : 1025); i++)
                _task(
                  'history-$i',
                  largeBatch ? 'tree' : 'batch-$i',
                  '/unrelated/$i',
                ),
              _task('published', batch, source.path),
              if (failedConsumer)
                {
                  ..._task(
                    'failed',
                    '33333333-3333-4333-8333-333333333333',
                    source.path,
                  ),
                  'status': 'failed',
                  'errorCode': 'result_unknown',
                },
            ];
            // Construct a valid durable history without thousands of fsyncs.
            await File('${root.path}/file_tasks.v2.journal').writeAsString(
              [
                for (var i = 0; i < tasks.length; i++)
                  jsonEncode({
                    'version': 2,
                    'sequence': i + 1,
                    'task': tasks[i],
                  }),
                '',
              ].join('\n'),
              flush: true,
            );
            owner = await FileTransferService.open(
              executor: FixtureExecutor(),
              dataDirectory: root,
              publication: store,
            );
            final result = await owner.reconcileShares();
            expect(result['reconciled'], isTrue);
            expect(result['snapshotComplete'], isTrue);
            expect(await source.exists(), failedConsumer);
            expect(owner.transfers()['transfers'], hasLength(tasks.length));
          } finally {
            await owner?.close();
            await root.delete(recursive: true);
          }
        },
      );
    }
  }
}

Map<String, Object?> _task(String id, String batch, String source) => {
  'id': id,
  'batchId': batch,
  'deviceId': 'device',
  'source': source,
  'destination': '/sdcard/$id',
  'direction': 'push',
  'status': 'completed',
  'kind': 'file',
  'name': id,
  'generation': 0,
};
