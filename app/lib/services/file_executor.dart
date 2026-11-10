import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';

import 'dart:async';

/// 执行本机与被控设备文件操作，不持有排序、遍历、冲突策略或任务状态。
/// 实现返回类型化批次并直接写入未发布片段；取消成功前必须完成 worker 清理。
/// 清理失败须保留精确执行对象供重试，不能以调用结束代替实际资源退出。
abstract interface class FileExecutor {
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  });
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  });
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  });
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  });
}
