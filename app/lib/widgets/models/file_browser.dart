import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';

enum FileTypeFilter { all, documents, images, videos, audio }

typedef FileBreadcrumb = ({String label, String path});

class DirectoryListing {
  DirectoryListing({
    required List<FileCatalogEntry> folders,
    required List<FileCatalogEntry> files,
  }) : folders = List.unmodifiable(folders),
       files = List.unmodifiable(files),
       entries = List<FileCatalogEntry>.unmodifiable([...folders, ...files]);

  final List<FileCatalogEntry> folders;
  final List<FileCatalogEntry> files;
  final List<FileCatalogEntry> entries;

  bool get isEmpty => folders.isEmpty && files.isEmpty;
}
