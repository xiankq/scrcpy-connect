import 'package:scrcpy_connect/core/files/models/file_kind.dart';

import 'models/file_browser.dart';

export 'models/file_browser.dart';

import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart'
    show FileSortKey;

export 'package:scrcpy_connect/core/files/models/file_kind.dart';
export 'package:scrcpy_connect/core/settings/models/preferences.dart'
    show FileViewMode, FileSortKey;

DirectoryListing buildDirectoryListing({
  required List<FileCatalogEntry> entries,
  required FileTypeFilter typeFilter,
  required FileSortKey sortKey,
  required bool ascending,
}) {
  final folders = entries.where((entry) => entry.isDirectory).toList();
  final files = entries
      .where((entry) => !entry.isDirectory)
      .where((entry) => fileMatchesType(entry, typeFilter))
      .toList();
  final folderSortKey = sortKey == FileSortKey.type
      ? FileSortKey.name
      : sortKey;
  folders.sort((a, b) => compareFileEntries(a, b, folderSortKey, ascending));
  files.sort((a, b) => compareFileEntries(a, b, sortKey, ascending));
  return DirectoryListing(folders: folders, files: files);
}

bool fileMatchesType(FileCatalogEntry entry, FileTypeFilter filter) =>
    switch (filter) {
      FileTypeFilter.all => true,
      FileTypeFilter.documents => fileKindOf(entry) == FileKind.documents,
      FileTypeFilter.images => fileKindOf(entry) == FileKind.images,
      FileTypeFilter.videos => fileKindOf(entry) == FileKind.videos,
      FileTypeFilter.audio => fileKindOf(entry) == FileKind.audio,
    };

FileKind fileKindOf(FileCatalogEntry entry) =>
    FileKind.classify(name: entry.name, mime: entry.mime);

int compareFileEntries(
  FileCatalogEntry a,
  FileCatalogEntry b,
  FileSortKey sortKey,
  bool ascending,
) {
  final aValue = _sortValue(a, sortKey);
  final bValue = _sortValue(b, sortKey);
  // 缺失元数据无法比较，无论升降序均排在有值项目后面。
  if (aValue == null && bValue == null) return _stableNamePath(a, b);
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  final comparison = _comparePresentValues(aValue, bValue);
  if (comparison != 0) return ascending ? comparison : -comparison;
  return _stableNamePath(a, b);
}

Object? _sortValue(FileCatalogEntry entry, FileSortKey key) => switch (key) {
  FileSortKey.name => entry.name.toLowerCase(),
  FileSortKey.size => entry.size,
  FileSortKey.modified => entry.modified,
  FileSortKey.type =>
    fileKindOf(entry) == FileKind.other ? null : fileKindOf(entry).index,
};

int _comparePresentValues(Object left, Object right) => switch ((left, right)) {
  (final String a, final String b) => a.compareTo(b),
  (final num a, final num b) => a.compareTo(b),
  _ => 0,
};

int _stableNamePath(FileCatalogEntry a, FileCatalogEntry b) {
  final nameComparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return nameComparison != 0
      ? nameComparison
      : (a.path ?? '').compareTo(b.path ?? '');
}

List<FileBreadcrumb> fileBreadcrumbs(String path) {
  final normalized = path == '/' ? path : path.replaceFirst(RegExp(r'/$'), '');
  if (normalized == '/sdcard' || normalized.startsWith('/sdcard/')) {
    final crumbs = [(label: '内部存储', path: '/sdcard')];
    for (final segment
        in normalized
            .substring('/sdcard'.length)
            .split('/')
            .where((part) => part.isNotEmpty)) {
      final previous = crumbs.last.path;
      crumbs.add((label: segment, path: '$previous/$segment'));
    }
    return crumbs;
  }
  if (normalized == '/') {
    return const [(label: '设备根目录', path: '/')];
  }
  final crumbs = <FileBreadcrumb>[(label: '设备文件', path: '/')];
  for (final segment
      in normalized.split('/').where((part) => part.isNotEmpty)) {
    crumbs.add((
      label: segment,
      path: '${crumbs.last.path}/$segment'.replaceFirst('//', '/'),
    ));
  }
  return crumbs;
}

String? fileParentPath(String path) {
  final normalized = path == '/' ? path : path.replaceFirst(RegExp(r'/$'), '');
  if (normalized == '/' || normalized == '/sdcard') return null;
  final separator = normalized.lastIndexOf('/');
  return separator <= 0 ? '/' : normalized.substring(0, separator);
}

String fileModifiedLabel(FileCatalogEntry entry) {
  final seconds = entry.modified;
  if (seconds == null || seconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
    isUtc: true,
  ).toLocal();
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

String fileRecentModifiedLabel(FileCatalogEntry entry) {
  final seconds = entry.modified;
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

bool fileCanOpen(FileCatalogEntry file) =>
    file.path?.isNotEmpty == true && file.canOpen;
bool fileCanManage(FileCatalogEntry file) =>
    file.path?.isNotEmpty == true && file.canManage;
String fileUnavailableReason(FileCatalogEntry file) =>
    file.reason ?? '文件名无法解析为有效路径，暂时无法操作。';
