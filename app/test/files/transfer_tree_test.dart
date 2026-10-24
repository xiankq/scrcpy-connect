import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';

import 'support/file_executor_fixture.dart';
import 'support/transfer_checks.dart' show withTransfer;

void main() {
  test(
    'overlapping source roots reserve only their own selected bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('file-tree-cache-');
      final executor = FixtureExecutor();
      final cache = _Cache();
      final owner = await TransferCoordinator.open(
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
