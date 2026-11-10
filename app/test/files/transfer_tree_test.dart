import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';
import 'package:scrcpy_connect/models/file_cache_reservation.dart';
import 'package:scrcpy_connect/services/file_cache_leases.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';

import 'support/file_executor_fixture.dart';
import 'support/transfer_checks.dart' show withTransfer;

void main() {
  test(
    'queued paths spend the shared byte budget before reading descendants',
    () async {
      await withTransfer((owner, executor, root) async {
        final source = '/${'x' * 3000}';
        executor.stamps[source] = directory;
        executor.children[source] = List.generate(
          6000,
          (i) => entry('$i', regular),
        );
        await expectLater(
          owner.startTransfer('d', true, [
            {'source': source, 'destination': '/sdcard/tree'},
          ]),
          throwsA(
            isA<FileFailure>().having((e) => e.code, 'code', 'tree_limit'),
          ),
        );
        expect(executor.calls, ['stat:$source', 'list:$source']);
        expect(owner.transfers()['transfers'], isEmpty);
      });
    },
  );

  test(
    'wide directories spend the shared entry budget before enqueueing',
    () async {
      final root = await Directory.systemTemp.createTemp('file-tree-width-');
      final executor = _WideTreeExecutor();
      final owner = await FileTransferService.open(
        executor: executor,
        dataDirectory: root,
      );
      try {
        await expectLater(
          owner.startTransfer('d', true, [
            {'source': '/wide', 'destination': '/sdcard/wide'},
          ]),
          throwsA(
            isA<FileFailure>().having((e) => e.code, 'code', 'tree_limit'),
          ),
        );
        expect(executor.enumerations, [10000 - 1, 10000 - 6001]);
        expect(owner.transfers()['transfers'], isEmpty);
      } finally {
        await owner.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'overlapping source roots reserve only their own selected bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('file-tree-cache-');
      final executor = FixtureExecutor();
      final cache = _Cache();
      final owner = await FileTransferService.open(
        executor: executor,
        dataDirectory: root,
        cache: cache,
      );
      try {
        executor.stamps.addAll({
          '/sdcard/tree': directory,
          '/sdcard/tree/sub': directory,
          '/sdcard/tree/sub/file': regular,
        });
        executor.children['/sdcard/tree'] = [entry('sub', directory)];
        executor.children['/sdcard/tree/sub'] = [entry('file', regular)];
        await owner.startTransfer('d', false, [
          {'source': '/sdcard/tree', 'destination': '/cache/first'},
          {'source': '/sdcard/tree/sub', 'destination': '/cache/second'},
        ], destinationScope: 'privateCache');
        await until(() => cache.released);
        expect(
          {for (final item in cache.reserved) item.path: item.bytes},
          {'/cache/first': 4, '/cache/second': 4},
        );
      } finally {
        await owner.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'overlapping source roots retain independent destination tree results',
    () async {
      await withTransfer((owner, executor, root) async {
        executor.stamps.addAll({
          '/source': directory,
          '/source/nested': directory,
          '/source/nested/file': regular,
        });
        executor.children['/source'] = [entry('nested', directory)];
        executor.children['/source/nested'] = [entry('file', regular)];
        executor.beforeCommit = (_, destination) async {
          if (destination == '/sdcard/other/file') {
            throw const FileFailure(
              'permission_denied',
              'other root cannot publish',
            );
          }
        };
        final started = await owner.startTransfer('d', true, [
          {'source': '/source', 'destination': '/sdcard/first'},
          {'source': '/source/nested', 'destination': '/sdcard/other'},
        ]);
        final id = started['transferId']! as String;
        await until(() {
          final items = owner.transfer(id)['items']! as List;
          return items.every(
                (e) =>
                    (e as Map<String, Object?>)['treeVerified'] == true ||
                    e['kind'] != 'directory',
              ) &&
              items.every(
                (e) => ![
                  'queued',
                  'running',
                  'finalizing',
                ].contains((e as Map<String, Object?>)['status']),
              );
        });
        final items = (owner.transfer(id)['items']! as List)
            .cast<Map<String, Object?>>();
        final first = items.singleWhere(
          (e) => e['destination'] == '/sdcard/first',
        );
        final nested = items.singleWhere(
          (e) => e['destination'] == '/sdcard/first/nested',
        );
        final other = items.singleWhere(
          (e) => e['destination'] == '/sdcard/other',
        );
        expect(first['treeComplete'], isTrue);
        expect(nested['treeComplete'], isTrue);
        expect(other['treeComplete'], isFalse);
        expect(
          items.singleWhere(
            (e) => e['destination'] == '/sdcard/other/file',
          )['status'],
          'failed',
        );
      });
    },
  );
}

/// The second level would enqueue 36 million paths if every one of its 6000
/// directories were enumerated without reserving the already queued entries.
class _WideTreeExecutor extends FixtureExecutor {
  final enumerations = <int>[];

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    return directory;
  }

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    enumerations.add(limit);
    if (enumerations.length > 2) {
      throw StateError('The first child exceeded the remaining tree budget.');
    }
    return FileDirectoryFacts(
      List.generate(limit < 6000 ? limit : 6000, (i) => entry('$i', directory)),
      truncated: limit < 6000,
    );
  }
}

class _Cache implements FileCacheLeases {
  List<FileCacheReservation> reserved = [];
  bool released = false;
  @override
  Future<String> reserve(List<FileCacheReservation> reservations) async {
    reserved = reservations;
    return 'lease';
  }

  @override
  Future<void> release(String lease) async {
    released = true;
  }
}
