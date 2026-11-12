import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
export 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';

part 'file_transfer_submission.freezed.dart';

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
