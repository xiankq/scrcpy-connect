import 'package:freezed_annotation/freezed_annotation.dart';

import 'file_transfer_plan.dart';
import 'file_transfer_snapshot.dart';

export 'file_transfer_plan.dart';
export 'file_transfer_snapshot.dart';

part 'file_transfers.freezed.dart';

@freezed
sealed class FileTransferTarget with _$FileTransferTarget {
  const factory FileTransferTarget.task(String id) = FileTransferTaskTarget;
  const factory FileTransferTarget.batch(String id) = FileTransferBatchTarget;
}

enum FileTransferAdmission { queued, submitted }

/// 已可靠登记的批次；恢复后的回执可能仅确认批次，返回不代表文件已经送达。
@freezed
sealed class FileTransferSubmission with _$FileTransferSubmission {
  const factory FileTransferSubmission({
    required String batchId,
    required String? transferId,
    required int itemCount,
    required FileTransferAdmission status,
    @Default(false) bool reusedTransfer,
    @Default(false) bool sourceLeaseReconciliationPending,
  }) = _FileTransferSubmission;
}

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
