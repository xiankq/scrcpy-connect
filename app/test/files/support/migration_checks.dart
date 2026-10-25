import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';

import 'file_executor_fixture.dart';
import 'transfer_checks.dart' show withTransfer;

class LeaseCache implements FileCacheLeases {
  int reservations = 0, releases = 0;
  final active = <String>{};
  @override
  Future<String> reserve(List<FileCacheReservation> reservations) async {
    final id = 'lease-${++this.reservations}';
    active.add(id);
    return id;
  }

  @override
  Future<void> release(String lease) async {
    require(active.remove(lease), 'released an unowned or duplicate lease');
    releases++;
  }
}

Map<String, Object?> row(
  String id, {
  String status = 'completed',
  String batch = 'b',
  String? parent,
  String kind = 'file',
}) => {
  'id': id,
  'deviceId': 'd',
  'direction': 'push',
  'source': '/source/$id',
  'destination': '/sdcard/$id',
  'name': id,
  'status': status,
  'transferred': 4,
  'total': 4,
  'policy': 'ask',
  'createdAt': 1,
  'batchId': batch,
  'generation': 0,
  'kind': kind,
  'treeVerified': true,
  'parentId': parent,
};

Future<void> seeded(
  List<Map<String, Object?>> rows,
  Future<void> Function(TransferCoordinator, Directory) check,
) async {
  final root = await Directory.systemTemp.createTemp('file-migration-');
  final legacy = File('${root.path}/transfers.json');
  await legacy.writeAsString(jsonEncode(rows));
  TransferCoordinator? owner;
  try {
    owner = await TransferCoordinator.open(
      executor: FixtureExecutor(),
      dataDirectory: root,
    );
    await check(owner, root);
  } finally {
    await owner?.close();
    await root.delete(recursive: true);
  }
}

final migrationChecks = <String, Future<void> Function()>{
  'uncertain cache leases transfer across attachments without gaps or duplicates': () async {
    final root = await Directory.systemTemp.createTemp('file-cache-handoff-');
    final cache = LeaseCache();
    TransferCoordinator? owner;
    try {
      await File('${root.path}/transfers.json').writeAsString(
        jsonEncode([
          {
            ...row('uncertain', status: 'finalizing'),
            'direction': 'pull',
            'destination': '${root.path}/cached.bin',
            'destinationScope': 'privateCache',
            'temporaryPath': '${root.path}/cached.part',
          },
        ]),
      );
      for (var i = 0; i < 4; i++) {
        owner = await TransferCoordinator.open(
          executor: FixtureExecutor(),
          dataDirectory: root,
          cache: cache,
        );
        require(
          cache.reservations == 1 &&
              cache.releases == 0 &&
              cache.active.length == 1,
          'reopen duplicated or dropped uncertain source protection',
        );
        await owner.close();
        require(cache.active.length == 1, 'close left an eviction window');
      }
      final replacement = LeaseCache();
      owner = await TransferCoordinator.open(
        executor: FixtureExecutor(),
        dataDirectory: root,
        cache: replacement,
      );
      require(
        replacement.active.length == 1 &&
            cache.active.isEmpty &&
            cache.releases == 1,
        'replacement did not establish protection before releasing old owner',
      );
      await owner.close();
      owner = await TransferCoordinator.open(
        executor: FixtureExecutor(),
        dataDirectory: root,
        cache: cache,
      );
      require(
        cache.reservations == 2 && replacement.active.isEmpty,
        'second handoff lost protection or retained old owner',
      );
      await owner.removeTransfer('uncertain');
      require(
        cache.active.isEmpty && cache.releases == 2,
        'explicit history removal leaked final lease',
      );
      await owner.close();
      owner = await TransferCoordinator.open(
        executor: FixtureExecutor(),
        dataDirectory: root,
        cache: cache,
      );
      require(
        cache.active.isEmpty && cache.reservations == 2,
        'completed handoff was resurrected',
      );
    } finally {
      await owner?.close();
      await root.delete(recursive: true);
    }
  },
  'device cancellation drains an unpublished directory selection snapshot':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps['/source'] = directory;
          executor.blockList = true;
          final preparing = owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/tree'},
          ]);
          final cancelled = preparing.then(
            (_) => false,
            onError: (Object error) =>
                error is FileFailure && error.code == 'cancelled',
          );
          await until(() => executor.calls.contains('list:/source'));
          await owner.cancelDevice('d');
          require(await cancelled, 'selection outlived cancellation');
          require(
            (owner.transfers()['transfers']! as List).isEmpty,
            'cancelled selection published tasks',
          );
        });
      },

  'history removal is durable, includes descendants and never deletes user files':
      () async {
        await seeded(
          [
            row('root', kind: 'directory'),
            row('child', parent: 'root'),
            row('other'),
          ],
          (owner, root) async {
            final saved = File('${root.path}/saved');
            await saved.writeAsString('user data');
            final removed = await owner.removeTransfer('root');
            require(
              (removed['removedIds']! as List).length == 2 &&
                  removed['filesRemoved'] == false,
              'directory removal lost descendants',
            );
            require(
              await saved.readAsString() == 'user data',
              'removed user data',
            );
            final restored = await TransferCoordinator.open(
              executor: FixtureExecutor(),
              dataDirectory: root,
            );
            try {
              require(
                (restored.transfers()['transfers']! as List).length == 1,
                'removal resurrected after restart',
              );
            } finally {
              await restored.close();
            }
          },
        );
      },
  'active batch cannot be forgotten and batch removal keeps unrelated history':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.stamps['/sdcard/exists'] = regular;
          final started = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/exists'},
          ]);
          final id = started['transferId']! as String;
          await until(() => owner.transfer(id)['status'] == 'conflict');
          await rejects(() => owner.removeTransfer(id), 'transfer_active');
          await owner.cancelBatch(started['batchId']! as String);
          await owner.removeTransfer(
            started['batchId']! as String,
            batch: true,
          );
          require(
            (owner.transfers()['transfers']! as List).isEmpty,
            'cancelled batch was not removed',
          );
        });
      },
  'failed removal retains in-memory task and storage remains fail closed':
      () async {
        await seeded([row('one')], (owner, root) async {
          final journal = File('${root.path}/file_tasks.v2.journal');
          await journal.delete();
          await Directory(journal.path).create();
          try {
            await owner.removeTransfer('one');
            throw StateError('expected I/O failure');
          } on FileSystemException {
            /* 预期异常 */
          }
          require(
            (owner.transfers()['transfers']! as List).length == 1,
            'failed persistence removed memory',
          );
          await Directory(journal.path).delete();
          await journal.writeAsString('');
          try {
            await owner.removeTransfer('one');
            throw StateError('poisoned store was reused');
          } catch (e) {
            require(e is! StateError, 'poisoned store was reused');
          }
        });
      },
  'journal rejects missing repeated and torn sequences and older generations':
      () async {
        for (final records in [
          [
            {'version': 2, 'sequence': 2, 'task': row('one')},
          ],
          [
            {'version': 2, 'sequence': 1, 'task': row('one')},
            {'version': 2, 'sequence': 1, 'task': row('one')},
          ],
          [
            {
              'version': 2,
              'sequence': 1,
              'task': {...row('one'), 'generation': 2},
            },
            {'version': 2, 'sequence': 2, 'task': row('one')},
          ],
        ]) {
          final root = await Directory.systemTemp.createTemp('file-corrupt-');
          try {
            final journal = File('${root.path}/file_tasks.v2.journal');
            final original = '${records.map(jsonEncode).join('\n')}\n';
            await journal.writeAsString(original);
            await rejects(
              () => TransferCoordinator.open(
                executor: FixtureExecutor(),
                dataDirectory: root,
              ),
              'transfer_storage_corrupt',
            );
            require(
              await journal.readAsString() == original,
              'corrupt data was overwritten',
            );
          } finally {
            await root.delete(recursive: true);
          }
        }
        final root = await Directory.systemTemp.createTemp('file-torn-');
        try {
          await File('${root.path}/file_tasks.v2.journal').writeAsString(
            jsonEncode({
              'version': 2,
              'sequence': 1,
              'task': row('one', status: 'finalizing'),
            }),
          );
          await rejects(
            () => TransferCoordinator.open(
              executor: FixtureExecutor(),
              dataDirectory: root,
            ),
            'transfer_storage_corrupt',
          );
        } finally {
          await root.delete(recursive: true);
        }
      },
  'journal appends only changed records and compaction cannot resurrect removals':
      () async {
        final root = await Directory.systemTemp.createTemp('file-compaction-');
        TransferCoordinator? owner;
        try {
          final rows = ['before', 'at', 'after', 'keep'].map(row).toList();
          // 在阈值前构造合法旧历史，避免用上千次独立磁盘刷新代替测试准备。
          // 第一次删除只追加；第二次删除跨过生产压缩阈值，并仍保留两项任务。
          final records = [...rows, ...List.generate(1022, (_) => row('keep'))];
          final legacy = File('${root.path}/transfers.json');
          await legacy.writeAsString(jsonEncode(rows), flush: true);
          final file = File('${root.path}/file_tasks.v2.journal');
          final history = [
            for (var index = 0; index < records.length; index++)
              jsonEncode({
                'version': 2,
                'sequence': index + 1,
                'task': records[index],
              }),
          ].join('\n');
          await file.writeAsString('$history\n', flush: true);
          owner = await TransferCoordinator.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
          );
          final before = await file.length();
          await owner.removeTransfer('before');
          require(
            await file.length() - before < 128,
            'single removal rewrote full history',
          );
          await owner.removeTransfer('at');
          final compacted = await file.readAsLines();
          require(
            compacted.length == 2 && await file.length() < 20000,
            'nonempty journal did not compact',
          );
          require(
            jsonDecode(compacted.first)['sequence'] == 1,
            'compaction did not replace old history',
          );
          await owner.close();
          owner = await TransferCoordinator.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
          );
          final restored = (owner.transfers()['transfers']! as List)
              .cast<Map<String, dynamic>>();
          require(
            restored.length == 2 &&
                restored.every(
                  (task) => const ['after', 'keep'].contains(task['id']),
                ),
            'nonempty compaction resurrected removals or lost retained tasks',
          );
          await owner.removeTransfer('after');
          await owner.close();
          owner = await TransferCoordinator.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
          );
          final remaining = owner.transfers()['transfers']! as List;
          require(
            remaining.length == 1 && (remaining.single as Map)['id'] == 'keep',
            'removal appended after compaction was not recovered',
          );
          await owner.removeTransfer('keep');
          final empty = await file.readAsLines();
          require(
            empty.length == 1 &&
                jsonDecode(empty.single)['migrationComplete'] == true,
            'empty compaction did not retain its durable migration marker',
          );
          await owner.close();
          owner = await TransferCoordinator.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
          );
          require(
            (owner.transfers()['transfers']! as List).isEmpty,
            'empty compaction resurrected removed tasks from old history',
          );
          require(
            await legacy.readAsString() == jsonEncode(rows),
            'compaction changed read-only legacy storage',
          );
        } finally {
          await owner?.close();
          await root.delete(recursive: true);
        }
      },
  'directory keepBoth remaps descendants and preserves the conflicting file':
      () async {
        await withTransfer((owner, executor, root) async {
          executor.stamps.addAll({
            '/source': directory,
            '/source/a': regular,
            '/source/empty': directory,
            '/sdcard/tree': regular,
          });
          executor.contents['/sdcard/tree'] = [9];
          executor.children['/source'] = [
            entry('a', regular),
            entry('empty', directory),
          ];
          final started = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/tree'},
          ], policy: 'keepBoth');
          final id = started['transferId']! as String;
          await until(() => owner.transfer(id)['treeVerified'] == true);
          require(
            executor.stamps['/sdcard/tree (1)/empty']?.isDirectory == true,
            'empty directory lost',
          );
          require(
            executor.contents['/sdcard/tree (1)/a']?.length == 4,
            'descendant not remapped',
          );
          require(
            executor.contents['/sdcard/tree']?.single == 9,
            'conflicting file overwritten',
          );
        });
      },
};
