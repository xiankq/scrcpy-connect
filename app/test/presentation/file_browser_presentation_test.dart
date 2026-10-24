import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/presentation/file_browser_presentation.dart';

void main() {
  final folderB = <String, dynamic>{
    'name': '资料',
    'path': '/sdcard/Download/资料',
    'isDirectory': true,
    'modified': 200,
  };
  final folderA = <String, dynamic>{
    'name': 'Download',
    'path': '/sdcard/Download',
    'isDirectory': true,
    'modified': 100,
  };
  final document = <String, dynamic>{
    'name': '报告.pdf',
    'path': '/sdcard/报告.pdf',
    'mime': 'application/pdf',
    'size': 50,
    'modified': 20,
  };
  final image = <String, dynamic>{
    'name': '照片.jpg',
    'path': '/sdcard/照片.jpg',
    'mime': 'image/jpeg',
    'size': 100,
    'modified': 10,
  };
  final unknown = <String, dynamic>{
    'name': '未知.bin',
    'path': '/sdcard/未知.bin',
    'mime': '',
  };

  test('type filters files while folders and unknown entries stay visible', () {
    final listing = buildDirectoryListing(
      entries: [folderB, folderA, document, image, unknown],
      typeFilter: FileTypeFilter.documents,
      sortKey: FileSortKey.name,
      ascending: true,
    );

    expect(listing.folders.map((entry) => value(entry, 'name')), [
      'Download',
      '资料',
    ]);
    expect(listing.files.map((entry) => value(entry, 'name')), ['报告.pdf']);
    expect(
      listing.folders.any((entry) => value(entry, 'name') == '未知.bin'),
      isFalse,
    );
  });

  test('file sorting keeps folders first and missing metadata last', () {
    final listing = buildDirectoryListing(
      entries: [folderB, folderA, document, image, unknown],
      typeFilter: FileTypeFilter.all,
      sortKey: FileSortKey.size,
      ascending: false,
    );

    expect(listing.folders.map((entry) => value(entry, 'name')), [
      'Download',
      '资料',
    ]);
    expect(listing.files.map((entry) => value(entry, 'name')), [
      '照片.jpg',
      '报告.pdf',
      '未知.bin',
    ]);
  });

  test('folder order follows comparable sort metadata and direction', () {
    final listing = buildDirectoryListing(
      entries: [folderA, folderB],
      typeFilter: FileTypeFilter.all,
      sortKey: FileSortKey.modified,
      ascending: false,
    );

    expect(listing.folders.map((entry) => value(entry, 'name')), [
      '资料',
      'Download',
    ]);
  });

  test('breadcrumbs retain paths for every parent', () {
    expect(fileBreadcrumbs('/sdcard/Download/资料'), [
      predicate<FileBreadcrumb>(
        (crumb) => crumb.label == '内部存储' && crumb.path == '/sdcard',
      ),
      predicate<FileBreadcrumb>(
        (crumb) =>
            crumb.label == 'Download' && crumb.path == '/sdcard/Download',
      ),
      predicate<FileBreadcrumb>(
        (crumb) => crumb.label == '资料' && crumb.path == '/sdcard/Download/资料',
      ),
    ]);
  });

  test('file page parents stop at the shared storage root', () {
    expect(fileParentPath('/sdcard/Download/资料'), '/sdcard/Download');
    expect(fileParentPath('/sdcard/Download'), '/sdcard');
    expect(fileParentPath('/sdcard'), isNull);
    expect(fileParentPath('/'), isNull);
  });

  test('a directory listing exposes one folder-first content stream', () {
    final listing = buildDirectoryListing(
      entries: [image, folderA, document, folderB],
      typeFilter: FileTypeFilter.all,
      sortKey: FileSortKey.name,
      ascending: true,
    );

    expect(listing.entries.map((entry) => value(entry, 'name')), [
      'Download',
      '资料',
      '报告.pdf',
      '照片.jpg',
    ]);
    expect(identical(listing.entries, listing.entries), isTrue);
  });

  test('file labels use compact sizes and short dates', () {
    expect(fileSizeLabel(126 * 1024), '126 KB');
    expect(fileSizeLabel(5505024), '5.25 MB');
    expect(
      fileRecentModifiedLabel({'modified': 20}),
      matches(r'^\d{2}/\d{2}$'),
    );
    expect(
      fileModifiedLabel({'modified': 20}),
      matches(r'^\d{4}/\d{2}/\d{2}$'),
    );
  });
}
