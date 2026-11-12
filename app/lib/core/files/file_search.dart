import 'package:freezed_annotation/freezed_annotation.dart';

import 'file_catalog_entry.dart';
export 'file_catalog_entry.dart' show FileCatalogFilter;

part 'file_search.freezed.dart';
part 'file_search.g.dart';

/// 任务 ID 保持不透明；调用始终同时携带原设备及根路径。
typedef FileSearchTarget = ({String deviceId, String searchId, String path});

abstract interface class FileSearch {
  Future<FileSearchSnapshot> startSearch(
    String deviceId, {
    required String path,
    required String query,
    FileCatalogFilter filter = .all,
  });
  Future<FileSearchSnapshot> readSearch(
    FileSearchTarget target, {
    int offset = 0,
    int limit = 500,
  });
  Future<void> cancelSearch(FileSearchTarget target);
}

enum FileSearchStatus {
  unknown,
  running,
  completed,
  partial,
  cancelled,
  failed,
}

@freezed
abstract class FileSearchSnapshot with _$FileSearchSnapshot {
  const FileSearchSnapshot._();
  const factory FileSearchSnapshot({
    required String deviceId,
    required String searchId,
    required String path,
    DateTime? startedAt,
    DateTime? checkedAt,
    @Default('') String query,
    @Default(FileCatalogFilter.all) FileCatalogFilter filter,
    @JsonKey(unknownEnumValue: FileSearchStatus.unknown)
    @Default(FileSearchStatus.unknown)
    FileSearchStatus status,
    @Default([]) List<FileCatalogEntry> entries,
    @Default([]) List<FileCatalogIssue> issues,
    @Default(0) int visitedEntries,
    @Default(0) int visitedDirectories,
    @Default('') String currentDirectory,
    @Default(0) int total,
    @Default(false) bool hasMore,
    @Default(false) bool limited,
  }) = _FileSearchSnapshot;
  factory FileSearchSnapshot.fromJson(Map<String, dynamic> json) =>
      _$FileSearchSnapshotFromJson(json);

  FileSearchTarget get target =>
      (deviceId: deviceId, searchId: searchId, path: path);
}
