import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/files/catalog/file_catalog.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';

import '../support/file_executor_fixture.dart';

Future<void> withCatalog(
  Future<void> Function(FileCatalog, FixtureExecutor) check,
) async {
  final executor = FixtureExecutor();
  final catalog = FileCatalog(executor);
  try {
    await check(catalog, executor);
  } finally {
    await catalog.close();
  }
}

void main() {
  test(
    'document browse and search include JSON XML RTF and OpenDocument',
    () async {
      await withCatalog((owner, executor) async {
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

  final checks = <String, Future<void> Function()>{
    'search preserves distinct paths and partial gallery excludes protected trees':
        () async {
          await withCatalog((owner, executor) async {
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
              done['status'] == 'partial' &&
                  (done['items']! as List).length == 3,
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
          await withCatalog((owner, executor) async {
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
              () =>
                  owner.cancelScan('other', scans.first['searchId']! as String),
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
          await withCatalog((owner, executor) async {
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
                  ((done['items']! as List).single as Map)['size'] ==
                      4294967315,
              'truncated directory or wide metadata lost',
            );
          });
        },

    'Dart owns directory sorting, filtering and raw-name boundaries': () async {
      await withCatalog((owner, executor) async {
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
    'gallery freezes ordering and paging until traversal has finished':
        () async {
          await withCatalog((owner, executor) async {
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
              started['status'] == 'scanning' &&
                  (started['items']! as List).isEmpty,
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
  };
  for (final check in checks.entries) {
    test(check.key, check.value);
  }
}
