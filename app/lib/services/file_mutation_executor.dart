import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/services/file_mutation_batch.dart';

import 'dart:async';

/// 用户明确提交的一批远端变更；创建时固定连接，后续项目不得重选设备连接。
abstract interface class FileMutationExecutor {
  Future<FileMutationBatch> beginMutation(
    String device, {
    required FileCancellation cancellation,
  });
}
