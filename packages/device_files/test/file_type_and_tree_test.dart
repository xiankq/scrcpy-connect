import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:device_files/device_files.dart';

import 'support/file_owner_checks.dart';

void main() {
  test(
    'classification uses known MIME before names and generic MIME falls back',
    () {
      expect(
        FileTypePolicy.kind(
          name: 'photo.jpg',
          mime: 'APPLICATION/PDF; charset=utf-8',
        ),
        FileKind.documents,
      );
      expect(
        FileTypePolicy.kind(
          name: 'report.json',
          mime: 'application/octet-stream',
        ),
        FileKind.documents,
      );
      expect(
        FileTypePolicy.kind(name: 'unknown.bin', mime: 'image/png'),
        FileKind.images,
      );
      expect(FileTypePolicy.kind(name: 'photo.JPG'), FileKind.images);
      expect(FileTypePolicy.kind(name: 'clip.MP4'), FileKind.videos);
      expect(FileTypePolicy.kind(name: 'song.FLAC'), FileKind.audio);
      expect(FileTypePolicy.kind(name: 'archive.xz'), FileKind.archives);
      expect(
        FileTypePolicy.kind(name: 'unknown.bin', mime: 'application/x-unknown'),
        FileKind.other,
      );
      expect(FileTypePolicy.mime('/path/report.json'), 'application/json');
    },
  );

  test(
    'document browse and search include JSON XML RTF and OpenDocument',
    () async {
      await withOwner((owner, executor, root) async {
        final names = [
          'data.json',
          'feed.xml',
          'notes.rtf',
          'letter.odt',
          'sheet.ods',
          'slides.odp',
        ];
        executor.children['/sdcard'] = [
          for (final name in names) entry(name, regular),
        ];
        final listing = await owner.browse('d', '/sdcard', filter: 'documents');
        expect(
          (listing['entries']! as List).map(
            (e) => (e as Map<String, Object?>)['name'],
          ),
          unorderedEquals(names),
        );
        final search = owner.startSearch(
          'd',
          '/sdcard',
          query: '',
          filter: 'documents',
        );
        final id = search['searchId']! as String;
        await until(() => owner.scan('d', id)['status'] != 'running');
        expect(
          (owner.scan('d', id)['items']! as List).map(
            (e) => (e as Map<String, Object?>)['name'],
          ),
          unorderedEquals(names),
        );
      });
    },
  );

  test(
    'overlapping source roots reserve only their own selected bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('file-tree-cache-');
      final executor = FixtureExecutor();
      final cache = _Cache();
      final owner = await RemoteFiles.open(
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
      await withOwner((owner, executor, root) async {
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

class _Cache implements RemoteFileCache {
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
