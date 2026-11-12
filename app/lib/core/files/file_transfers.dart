import 'package:scrcpy_connect/core/files/models/file_transfer_submission.dart';

export 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
export 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';
export 'package:scrcpy_connect/core/files/models/file_transfer_submission.dart';

abstract interface class FileTransfers {
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  });
  Future<FileTransferCollection> readTransfers();
  Future<FileTransferSnapshot> readTransfer(String id);

  /// 停止精确任务或批次，等待原执行资源确认退出，不重放文件操作。
  Future<void> cancelTransfer(FileTransferTarget target);

  Future<FileTransferSnapshot> resolveConflict(
    String id,
    FileTransferConflict policy, {
    bool applyToAll = false,
  });

  /// 逐项从头重试；不具备可靠结果或来源身份时由所有者拒绝。
  Future<FileTransferSnapshot> restartTransfer(
    String id, {
    FileTransferConflict? policy,
    bool applyToAll = false,
  });

  /// 仅移除记录，返回实际移除的任务标识；不删除保存的文件。
  Future<List<String>> removeTransfer(FileTransferTarget target);
}
