import 'package:scrcpy_connect/models/file_stamp.dart';

import 'dart:async';

/// 保留本批已创建的精确执行句柄；关闭失败时必须保留本对象供重试。
abstract interface class FileMutationBatch {
  Future<String> mutate(
    String action,
    String path, {
    String destination = '',
    FileStamp? expected,
  });

  /// 撤销本批准入，并等待已创建或迟到交付的执行资源实际释放。
  Future<void> close();
}
