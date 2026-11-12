import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';

export 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart'
    show FileCatalogFilter;

part 'file_search_snapshot.freezed.dart';
part 'file_search_snapshot.g.dart';

/// 任务 ID 保持不透明；调用始终同时携带原设备及根路径。
typedef FileSearchTarget = ({String deviceId, String searchId, String path});

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
