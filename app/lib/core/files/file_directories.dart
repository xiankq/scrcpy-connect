import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_snapshot.dart';

export 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart'
    show FileCatalogFilter;
export 'package:scrcpy_connect/core/files/models/file_directory_snapshot.dart';

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
