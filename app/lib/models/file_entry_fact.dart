import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';

import 'dart:convert';
import 'dart:typed_data';

class FileEntryFact {
  const FileEntryFact({required this.nameBytes, this.stamp, this.error});
  final Uint8List nameBytes;
  final FileStamp? stamp;
  final FileFailure? error;
  String get displayName => utf8.decode(nameBytes, allowMalformed: true);
  String? get pathName {
    try {
      final name = utf8.decode(nameBytes);
      return name.isEmpty ||
              name == '.' ||
              name == '..' ||
              name.contains('/') ||
              name.contains('\u0000')
          ? null
          : name;
    } on FormatException {
      return null;
    }
  }
}
