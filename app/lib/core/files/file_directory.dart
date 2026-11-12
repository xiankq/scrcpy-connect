import 'package:freezed_annotation/freezed_annotation.dart';

import 'file_cancellation.dart';
import 'file_catalog_entry.dart';
export 'file_catalog_entry.dart' show FileCatalogFilter;

part 'file_directory.freezed.dart';
part 'file_directory.g.dart';

typedef FileDirectoryTarget = ({String deviceId, String path});

enum FileDirectorySort { name, size, modified, type }

abstract interface class FileDirectories {
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  });
}

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
