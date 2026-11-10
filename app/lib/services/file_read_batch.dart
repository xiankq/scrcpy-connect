import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/services/file_execution_resource.dart';

import 'dart:async';

/// 暂存片段属于本批；close 先排空全部执行，再精确释放未发布片段。
abstract interface class FileReadBatch implements FileExecutionResource {
  Future<FileStamp> stat(String path);
  Future<int> copy(
    String source,
    String temporary, {
    required FileStamp expected,
    required void Function(int) onProgress,
  });
  Future<void> commit(String temporary, String destination);
}
