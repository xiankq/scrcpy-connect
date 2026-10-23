import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_files/device_files.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> until(bool Function() ready) async {
  final limit = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(limit)) {
      throw StateError('timed out waiting for task');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const regular = FileStamp(mode: 0x8000, size: 4, modifiedSeconds: 3);
const directory = FileStamp(mode: 0x4000, size: 0, modifiedSeconds: 3);
FileEntryFact entry(String name, FileStamp stamp) => FileEntryFact(
  nameBytes: Uint8List.fromList(utf8.encode(name)),
  stamp: stamp,
);

class FixtureExecutor implements RemoteFileExecutor {
  final stamps = <String, FileStamp>{'/sdcard': directory};
  final children = <String, List<FileEntryFact>>{};
  final contents = <String, List<int>>{};
  final calls = <String>[];
  Completer<void>? copyStarted;
  bool blockCopy = false, unknownCommit = false, blockList = false;
  final denied = <String>{};
  Future<void> Function(String, String)? beforeCommit;
  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    calls.add('stat:$path');
    final stamp = stamps[path];
    if (stamp == null) throw const FileFailure('not_found', 'absent');
    return stamp;
  }

  @override
  Future<DirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    calls.add('list:$path');
    if (blockList) {
      await cancellation.whenCancelled;
      cancellation.check();
    }
    if (denied.contains(path)) {
      throw const FileFailure('permission_denied', 'denied');
    }
    final list = children[path] ?? [];
    return DirectoryFacts(
      list.take(limit).toList(),
      truncated: list.length > limit,
    );
  }

  @override
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    calls.add('copy:$temporary');
    if (copyStarted != null && !copyStarted!.isCompleted) {
      copyStarted!.complete();
    }
    if (blockCopy) {
      await cancellation.whenCancelled;
      cancellation.check();
    }
    require(stamps[source] == expected, 'source stamp changed');
    contents[temporary] = [1, 2, 3, 4];
    stamps[temporary] = regular;
    onProgress(4);
    return 4;
  }

  @override
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    calls.add('$action:$path');
    if (action == 'releasePart') return 'released';
    if (action == 'mkdir') {
      if (stamps.containsKey(path)) {
        throw const FileFailure('conflict', 'exists');
      }
      stamps[path] = directory;
      return 'directoryCreated';
    }
    if (action == 'commit') {
      await beforeCommit?.call(path, destination);
      if (!replace && stamps.containsKey(destination)) {
        throw const FileFailure('conflict', 'exists');
      }
      if (unknownCommit) {
        throw const FileFailure('disconnected', 'lost receipt');
      }
      contents[destination] = contents.remove(path)!;
      stamps[destination] = stamps.remove(path)!;
      return 'atomicNoReplace';
    }
    throw StateError('unexpected mutation $action');
  }
}

Future<void> withOwner(
  Future<void> Function(RemoteFiles, FixtureExecutor, Directory) check,
) async {
  final root = await Directory.systemTemp.createTemp('file-owner-');
  final executor = FixtureExecutor();
  final owner = await RemoteFiles.open(executor: executor, dataDirectory: root);
  try {
    await check(owner, executor, root);
  } finally {
    await owner.close();
    await root.delete(recursive: true);
  }
}

final fileOwnerChecks = <String, Future<void> Function()>{
  'Dart owns directory sorting, filtering and raw-name boundaries': () async {
    await withOwner((owner, executor, root) async {
      executor.children['/sdcard'] = [
        entry('b.mp4', regular),
        entry('Folder', directory),
        entry('a.jpg', regular),
        FileEntryFact(nameBytes: Uint8List.fromList([255]), stamp: regular),
        entry(
          'link',
          const FileStamp(mode: 0xa000, size: 4, modifiedSeconds: 3),
        ),
      ];
      final listing = await owner.browse('d', '/sdcard', limit: 2);
      final entries = (listing['entries']! as List)
          .cast<Map<String, Object?>>();
      require(
        entries[0]['name'] == 'Folder' &&
            listing['total'] == 5 &&
            listing['hasMore'] == true,
        'directory sorting/paging not owned by Dart',
      );
      final images = await owner.browse('d', '/sdcard', filter: 'images');
      require(
        (images['entries']! as List).length == 1,
        'extension filter failed',
      );
      final all =
          (await owner.browse('d', '/sdcard', limit: 10))['entries']! as List;
      final invalid = all.cast<Map<String, Object?>>().firstWhere(
        (e) => e['nameIsUtf8'] == false,
      );
      require(
        invalid['path'] == null && invalid['canManage'] == false,
        'invalid raw filename became operable',
      );
    });
  },
  'gallery freezes ordering and paging until traversal has finished': () async {
    await withOwner((owner, executor, root) async {
      executor.children['/sdcard'] = [
        entry('z.jpg', regular),
        entry('a.mp4', regular),
        entry('dir', directory),
        entry(
          'outside',
          const FileStamp(mode: 0xa000, size: 1, modifiedSeconds: 1),
        ),
      ];
      executor.stamps['/sdcard/dir'] = directory;
      executor.children['/sdcard/dir'] = [
        entry(
          'b.jpg',
          const FileStamp(mode: 0x8000, size: 4, modifiedSeconds: 8),
        ),
      ];
      final started = owner.startSearch(
        'd',
        '/sdcard',
        query: '',
        gallery: true,
      );
      final id = started['scanId']! as String;
      require(
        started['status'] == 'scanning' && (started['items']! as List).isEmpty,
        'gallery exposed an unstable page',
      );
      await until(() => owner.scan('d', id)['status'] != 'scanning');
      final page = owner.scan('d', id, limit: 2);
      require(page['nextOffset'] == 2, 'gallery missing stable cursor');
      final items = page['items']! as List;
      require(
        (items.first as Map)['path'] == '/sdcard/dir/b.jpg' &&
            (items[1] as Map)['path'] == '/sdcard/a.mp4',
        'mtime/path tie ordering failed',
      );
      require(
        !executor.calls.contains('list:/sdcard/outside'),
        'followed child symlink',
      );
    });
  },
  'file transaction persists finalizing before commit and resolves conflicts':
      () async {
        await withOwner((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.stamps['/sdcard/existing'] = regular;
          executor.contents['/sdcard/existing'] = [9];
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/existing'},
          ]);
          final id = receipt['transferId']! as String;
          await until(() => owner.transfer(id)['status'] == 'conflict');
          require(
            !executor.calls.any((c) => c.startsWith('copy:')),
            'copied bytes before conflict decision',
          );
          executor.beforeCommit = (part, target) async {
            final records = await File('${root.path}/file_tasks.v2.journal')
                .readAsLines();
            final latest =
                records
                        .map((line) => jsonDecode(line) as Map)
                        .where((r) => (r['task'] as Map?)?['id'] == id)
                        .last['task']
                    as Map;
            require(
              latest['status'] == 'finalizing' &&
                  latest['temporaryPath'] == part,
              'commit preceded durable finalizing record',
            );
            require(
              !executor.contents.containsKey(target),
              'published before commit',
            );
          };
          await owner.resolveTransfer(id, 'keepBoth');
          await until(() => owner.transfer(id)['status'] == 'completed');
          require(
            executor.contents['/sdcard/existing']!.single == 9 &&
                executor.contents['/sdcard/existing (1)']!.length == 4,
            'keepBoth overwrote existing data',
          );
        });
      },
  'cancellation waits for worker cleanup and never publishes partial files':
      () async {
        await withOwner((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.blockCopy = true;
          executor.copyStarted = Completer<void>();
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/new'},
          ]);
          await executor.copyStarted!.future;
          final id = receipt['transferId']! as String;
          await owner.cancelTransfer(id);
          require(
            owner.transfer(id)['status'] == 'cancelled',
            'cancel returned before terminal worker result',
          );
          require(
            !executor.contents.containsKey('/sdcard/new') &&
                !executor.calls.any((c) => c.startsWith('commit:')),
            'cancelled bytes were published',
          );
        });
      },
  'legacy migration is read-only and unknown commit cannot be retried':
      () async {
        final root = await Directory.systemTemp.createTemp('file-migration-');
        final legacy = File('${root.path}/transfers.json');
        final raw = jsonEncode({
          'version': 1,
          'sequence': 1,
          'transfers': [
            {
              'id': 'old',
              'batchId': 'old',
              'deviceId': 'd',
              'direction': 'pull',
              'source': '/sdcard/s',
              'destination': '${root.path}/kept',
              'kind': 'file',
              'status': 'finalizing',
              'policy': 'ask',
              'generation': 2,
              'transferred': 4,
              'total': 4,
              'sourceStamp': regular.toJson(),
            },
          ],
        });
        await legacy.writeAsString(raw, flush: true);
        await File('${root.path}/kept').writeAsString('user data', flush: true);
        final owner = await RemoteFiles.open(
          executor: FixtureExecutor(),
          dataDirectory: root,
        );
        try {
          final task = owner.transfer('old');
          require(
            task['status'] == 'interrupted' &&
                task['errorCode'] == 'result_unknown' &&
                task['canRestart'] == false,
            'unknown commit became retryable',
          );
          require(
            await legacy.readAsString() == raw &&
                await File('${root.path}/kept').readAsString() == 'user data',
            'migration modified legacy journal or user data',
          );
        } finally {
          await owner.close();
          await root.delete(recursive: true);
        }
      },
  'missing commit receipt preserves source and refuses automatic replay':
      () async {
        await withOwner((owner, executor, root) async {
          executor.stamps['/source'] = regular;
          executor.unknownCommit = true;
          final receipt = await owner.startTransfer('d', true, [
            {'source': '/source', 'destination': '/sdcard/new'},
          ]);
          final id = receipt['transferId']! as String;
          await until(() => owner.transfer(id)['status'] == 'failed');
          require(
            owner.transfer(id)['errorCode'] == 'result_unknown' &&
                owner.transfer(id)['canRestart'] == false,
            'lost receipt was classified as safely retryable',
          );
          require(executor.stamps.containsKey('/source'), 'source was deleted');
        });
      },
};
