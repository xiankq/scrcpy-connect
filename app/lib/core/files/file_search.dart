import 'package:scrcpy_connect/core/files/models/file_search_snapshot.dart';

export 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart'
    show FileCatalogFilter;
export 'package:scrcpy_connect/core/files/models/file_search_snapshot.dart';

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
