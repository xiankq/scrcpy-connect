import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';

export 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart'
    show FileCatalogFilter;

part 'file_directory_snapshot.freezed.dart';
part 'file_directory_snapshot.g.dart';

typedef FileDirectoryTarget = ({String deviceId, String path});

enum FileDirectorySort { name, size, modified, type }

@freezed
abstract class FileDirectorySnapshot with _$FileDirectorySnapshot {
  const factory FileDirectorySnapshot({
    required String deviceId,
    required String path,
    @Default([]) List<FileCatalogEntry> entries,
    int? total,
    @Default(0) int offset,
    @Default(false) bool hasMore,
    @Default(false) bool truncated,
  }) = _FileDirectorySnapshot;
  factory FileDirectorySnapshot.fromJson(Map<String, dynamic> json) =>
      _$FileDirectorySnapshotFromJson(json);
}
