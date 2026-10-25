import 'package:scrcpy_connect/models/application_request.dart';

export 'package:scrcpy_connect/models/file_kind.dart';

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
