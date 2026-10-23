import 'dart:convert';
import 'dart:io';

import 'package:device_files/device_files.dart';

import 'file_owner_checks.dart';

class LeaseCache implements RemoteFileCache {
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

FileSnapshot row(
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
  List<FileSnapshot> rows,
  Future<void> Function(RemoteFiles, Directory) check,
) async {
  final root = await Directory.systemTemp.createTemp('file-migration-');
  final legacy = File('${root.path}/transfers.json');
  await legacy.writeAsString(jsonEncode(rows));
  RemoteFiles? owner;
  try {
    owner = await RemoteFiles.open(
      executor: FixtureExecutor(),
      dataDirectory: root,
    );
    await check(owner, root);
  } finally {
    await owner?.close();
    await root.delete(recursive: true);
  }
}

Future<void> rejects(Future<Object?> Function() action, String code) async {
  try {
    await action();
  } on FileFailure catch (e) {
    require(e.code == code, 'expected $code, got ${e.code}');
    return;
  }
  throw StateError('expected $code');
}

final migrationChecks = <String, Future<void> Function()>{
  'uncertain cache leases transfer across attachments without gaps or duplicates':
      () async {
        final root = await Directory.systemTemp.createTemp(
          'file-cache-handoff-',
        );
        final cache = LeaseCache();
        RemoteFiles? owner;
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
            owner = await RemoteFiles.open(
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
          await rejects(
            () => RemoteFiles.open(
              executor: FixtureExecutor(),
              dataDirectory: root,
              cache: LeaseCache(),
            ),
            'cache_owner_changed',
          );
          owner = await RemoteFiles.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
            cache: cache,
          );
          require(cache.reservations == 1, 'failed attachment lost handoff');
          await owner.removeTransfer('uncertain');
          require(
            cache.active.isEmpty && cache.releases == 1,
            'explicit history removal leaked final lease',
          );
          await owner.close();
          owner = await RemoteFiles.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
            cache: cache,
          );
          require(
            cache.active.isEmpty && cache.reservations == 1,
            'completed handoff was resurrected',
          );
        } finally {
          await owner?.close();
          await root.delete(recursive: true);
        }
      },
  'device cancellation drains an unpublished directory selection snapshot':
      () async {
        await withOwner((owner, executor, root) async {
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
            final restored = await RemoteFiles.open(
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
        await withOwner((owner, executor, root) async {
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
            /* expected */
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
              () => RemoteFiles.open(
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
            () => RemoteFiles.open(
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
        await seeded(List.generate(1100, (i) => row('$i')), (
          owner,
          root,
        ) async {
          final file = File('${root.path}/file_tasks.v2.journal'),
              before = await File('${root.path}/file_tasks.v2.journal')
                  .length();
          await owner.removeTransfer('0');
          require(
            await file.length() - before < 128,
            'single removal rewrote full history',
          );
          for (var i = 1; i < 1100; i++) {
            await owner.removeTransfer('$i');
          }
          require(await file.length() < 20000, 'journal did not compact');
          final restored = await RemoteFiles.open(
            executor: FixtureExecutor(),
            dataDirectory: root,
          );
          try {
            require(
              (restored.transfers()['transfers']! as List).isEmpty,
              'compaction resurrected removed tasks',
            );
          } finally {
            await restored.close();
          }
        });
      },
  'directory keepBoth remaps descendants and preserves the conflicting file':
      () async {
        await withOwner((owner, executor, root) async {
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
  'search preserves distinct paths and partial gallery excludes protected trees':
      () async {
        await withOwner((owner, executor, root) async {
          executor.children['/sdcard'] = [
            entry('a', directory),
            entry('b', directory),
            entry('Android', directory),
            entry('denied', directory),
          ];
          for (final path in [
            '/sdcard/a',
            '/sdcard/b',
            '/sdcard/Android',
            '/sdcard/denied',
          ]) {
            executor.stamps[path] = directory;
          }
          executor.children['/sdcard/a'] = [entry('same.jpg', regular)];
          executor.children['/sdcard/b'] = [entry('same.jpg', regular)];
          executor.children['/sdcard/Android'] = [
            entry('data', directory),
            entry('obb', directory),
            entry('media', directory),
          ];
          executor.stamps['/sdcard/Android/media'] = directory;
          executor.children['/sdcard/Android/media'] = [
            entry('public.jpg', regular),
          ];
          executor.denied.add('/sdcard/denied');
          final started = owner.startSearch(
                'd',
                '/sdcard',
                query: '',
                gallery: true,
              ),
              id = started['scanId']! as String;
          await until(() => owner.scan('d', id)['status'] != 'scanning');
          final done = owner.scan('d', id);
          require(
            done['status'] == 'partial' && (done['items']! as List).length == 3,
            'accessible media was lost or denied directory called empty',
          );
          require(
            !executor.calls.any(
              (c) =>
                  c == 'list:/sdcard/Android/data' ||
                  c == 'list:/sdcard/Android/obb',
            ),
            'protected trees traversed',
          );
        });
      },
  'scan cancellation is device scoped and enforces active and retained bounds':
      () async {
        await withOwner((owner, executor, root) async {
          executor.blockList = true;
          final scans = List.generate(
            4,
            (_) => owner.startSearch('d', '/sdcard', query: 'a'),
          );
          await rejects(
            () async => owner.startSearch('d', '/sdcard', query: 'a'),
            'busy',
          );
          await rejects(
            () => owner.cancelScan('other', scans.first['searchId']! as String),
            'search_not_found',
          );
          await owner.cancelDevice('d');
          for (final s in scans) {
            require(
              owner.scan('d', s['searchId']! as String)['status'] ==
                  'cancelled',
              'scan outlived cancelDevice',
            );
          }
          executor.blockList = false;
          for (var i = 0; i < 20; i++) {
            final started = owner.startSearch('d', '/sdcard', query: 'a');
            await until(
              () =>
                  owner.scan('d', started['searchId']! as String)['status'] !=
                  'running',
            );
          }
          await rejects(
            () async => owner.scan('d', scans.first['searchId']! as String),
            'search_not_found',
          );
        });
      },
  'gallery truncation is partial and retains wide metadata without child links':
      () async {
        await withOwner((owner, executor, root) async {
          const wide = FileStamp(
            mode: 0x8000,
            size: 4294967315,
            modifiedSeconds: 3,
          );
          executor.children['/sdcard'] = [
            entry('wide.mp4', wide),
            ...List.generate(4200, (i) => entry('$i.txt', regular)),
          ];
          final started = owner.startSearch(
                'd',
                '/sdcard',
                query: '',
                gallery: true,
              ),
              id = started['scanId']! as String;
          await until(() => owner.scan('d', id)['status'] != 'scanning');
          final done = owner.scan('d', id);
          require(
            done['status'] == 'partial' &&
                ((done['items']! as List).single as Map)['size'] == 4294967315,
            'truncated directory or wide metadata lost',
          );
        });
      },
};
