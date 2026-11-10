import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/services/file_read_batch.dart';

import 'dart:async';

/// 预览读取在创建时固定连接，元数据、传输和发布共用同一资源所有者。
abstract interface class FileReadExecutor {
  Future<FileReadBatch> beginRead(
    String device, {
    required FileCancellation cancellation,
  });
}
