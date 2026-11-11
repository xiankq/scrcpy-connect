import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';

import 'dart:async';

import 'package:scrcpy_connect/models/file_failure.dart';

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

/// 预览读取在创建时固定连接，元数据、传输和发布共用同一资源所有者。
abstract interface class FileReadExecutor {
  Future<FileReadBatch> beginRead(
    String device, {
    required FileCancellation cancellation,
  });
}

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

/// 用户明确提交的一批远端变更；创建时固定连接，后续项目不得重选设备连接。
abstract interface class FileMutationExecutor {
  Future<FileMutationBatch> beginMutation(
    String device, {
    required FileCancellation cancellation,
  });
}

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

/// 已完成执行域接管的事实；同 key 换发 id 前必须实际排空旧域的操作与片段。
///
/// 这两个值来自执行能力的真实 attach，不是产品设备 ID，也不授予旧域关闭权。
abstract interface class ScopedFileExecutor {
  String get fileScopeKey;
  String get fileScopeId;
}

/// 一次精确执行的回收责任；失败后保留同一对象重试，不关闭共享连接。
abstract interface class FileExecutionResource {
  Future<void> close();
}

/// 单次便捷调用回收失败时，把精确执行对象交还调用者，而非只保留错误文本。
final class FileExecutionCleanupFailure extends FileFailure {
  FileExecutionCleanupFailure(this.execution, this.cause)
    : super('file_cleanup_unconfirmed', '文件执行资源尚未确认释放：$cause');
  final FileExecutionResource execution;
  final Object cause;
}
