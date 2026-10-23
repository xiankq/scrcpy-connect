import 'package:device_files/device_files.dart' show FileKind, FileTypePolicy;
import 'package:scrcpy_connect/services/app_controller.dart';

export 'package:device_files/device_files.dart' show FileKind;

enum FileViewMode { grid, list }

enum FileSortKey { name, size, modified, type }

enum FileTypeFilter { all, documents, images, videos, audio }

class FileBreadcrumb {
  const FileBreadcrumb({required this.label, required this.path});

  final String label;
  final String path;
}

class DirectoryListing {
  DirectoryListing({required this.folders, required this.files})
    : entries = List<Json>.unmodifiable([...folders, ...files]);

  final List<Json> folders;
  final List<Json> files;
  final List<Json> entries;

  bool get isEmpty => folders.isEmpty && files.isEmpty;
}

DirectoryListing buildDirectoryListing({
  required List<Json> entries,
  required FileTypeFilter typeFilter,
  required FileSortKey sortKey,
  required bool ascending,
}) {
  final folders = entries
      .where((entry) => entry['isDirectory'] == true)
      .toList();
  final files = entries
      .where((entry) => entry['isDirectory'] != true)
      .where((entry) => fileMatchesType(entry, typeFilter))
      .toList();
  final folderSortKey = sortKey == FileSortKey.type
      ? FileSortKey.name
      : sortKey;
  folders.sort((a, b) => compareFileEntries(a, b, folderSortKey, ascending));
  files.sort((a, b) => compareFileEntries(a, b, sortKey, ascending));
  return DirectoryListing(folders: folders, files: files);
}

bool fileMatchesType(Json entry, FileTypeFilter filter) => switch (filter) {
  FileTypeFilter.all => true,
  FileTypeFilter.documents => fileKindOf(entry) == FileKind.documents,
  FileTypeFilter.images => fileKindOf(entry) == FileKind.images,
  FileTypeFilter.videos => fileKindOf(entry) == FileKind.videos,
  FileTypeFilter.audio => fileKindOf(entry) == FileKind.audio,
};

FileKind fileKindOf(Json entry) =>
    FileTypePolicy.kind(name: value(entry, 'name'), mime: value(entry, 'mime'));

int compareFileEntries(Json a, Json b, FileSortKey sortKey, bool ascending) {
  final aValue = _sortValue(a, sortKey);
  final bValue = _sortValue(b, sortKey);
  // Missing metadata is not comparable; keep it after every present value in
  // both directions instead of reversing the fallback with the sort order.
  if (aValue == null && bValue == null) return _stableNamePath(a, b);
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  final comparison = _comparePresentValues(aValue, bValue);
  if (comparison != 0) return ascending ? comparison : -comparison;
  return _stableNamePath(a, b);
}

Object? _sortValue(Json entry, FileSortKey key) => switch (key) {
  FileSortKey.name => value(entry, 'name').toLowerCase(),
  FileSortKey.size => num.tryParse('${entry['size']}'),
  FileSortKey.modified => num.tryParse('${entry['modified']}'),
  FileSortKey.type =>
    fileKindOf(entry) == FileKind.other ? null : fileKindOf(entry).index,
};

int _comparePresentValues(Object left, Object right) => switch ((left, right)) {
  (final String a, final String b) => a.compareTo(b),
  (final num a, final num b) => a.compareTo(b),
  _ => 0,
};

int _stableNamePath(Json a, Json b) {
  final nameComparison = value(
    a,
    'name',
  ).toLowerCase().compareTo(value(b, 'name').toLowerCase());
  return nameComparison != 0
      ? nameComparison
      : value(a, 'path').compareTo(value(b, 'path'));
}

List<FileBreadcrumb> fileBreadcrumbs(String path) {
  final normalized = path == '/' ? path : path.replaceFirst(RegExp(r'/$'), '');
  if (normalized == '/sdcard' || normalized.startsWith('/sdcard/')) {
    final crumbs = [const FileBreadcrumb(label: '内部存储', path: '/sdcard')];
    for (final segment
        in normalized
            .substring('/sdcard'.length)
            .split('/')
            .where((part) => part.isNotEmpty)) {
      final previous = crumbs.last.path;
      crumbs.add(FileBreadcrumb(label: segment, path: '$previous/$segment'));
    }
    return crumbs;
  }
  if (normalized == '/') {
    return const [FileBreadcrumb(label: '设备根目录', path: '/')];
  }
  final crumbs = <FileBreadcrumb>[
    const FileBreadcrumb(label: '设备文件', path: '/'),
  ];
  for (final segment
      in normalized.split('/').where((part) => part.isNotEmpty)) {
    crumbs.add(
      FileBreadcrumb(
        label: segment,
        path: '${crumbs.last.path}/$segment'.replaceFirst('//', '/'),
      ),
    );
  }
  return crumbs;
}

String? fileParentPath(String path) {
  final normalized = path == '/' ? path : path.replaceFirst(RegExp(r'/$'), '');
  if (normalized == '/' || normalized == '/sdcard') return null;
  final separator = normalized.lastIndexOf('/');
  return separator <= 0 ? '/' : normalized.substring(0, separator);
}

String fileModifiedLabel(Json entry) {
  final seconds = num.tryParse('${entry['modified']}');
  if (seconds == null || seconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
    isUtc: true,
  ).toLocal();
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

String fileRecentModifiedLabel(Json entry) {
  final seconds = num.tryParse('${entry['modified']}');
  if (seconds == null || seconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
    isUtc: true,
  ).toLocal();
  return '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

String fileSizeLabel(Object? input) {
  final amount = num.tryParse('$input') ?? 0;
  if (amount < 1024) return '${amount.toInt()} B';
  final (unit, divisor) = switch (amount) {
    < 1048576 => ('KB', 1024),
    < 1073741824 => ('MB', 1048576),
    _ => ('GB', 1073741824),
  };
  final value = amount / divisor;
  final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text $unit';
}

String fileDirectoryLabel(String path) {
  if (path == '/sdcard') return '内部存储根目录';
  final crumbs = fileBreadcrumbs(path);
  return crumbs.isEmpty ? path : crumbs.last.label;
}
