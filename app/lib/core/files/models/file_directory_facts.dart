import 'package:scrcpy_connect/core/files/models/file_entry_fact.dart';

class FileDirectoryFacts {
  FileDirectoryFacts(List<FileEntryFact> entries, {required this.truncated})
    : entries = List.unmodifiable(entries);
  final List<FileEntryFact> entries;
  final bool truncated;
}
