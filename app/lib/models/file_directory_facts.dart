import 'package:scrcpy_connect/models/file_entry_fact.dart';

class FileDirectoryFacts {
  const FileDirectoryFacts(this.entries, {required this.truncated});
  final List<FileEntryFact> entries;
  final bool truncated;
}
