import 'file_transfers.dart';

/// 可恢复的发布回执；恢复核对可能只知道批次，尚不知道首项及数量。
final class FilePublicationReceipt {
  const FilePublicationReceipt({
    required this.batchId,
    required this.status,
    this.transferId,
    this.itemCount,
  });
  factory FilePublicationReceipt.fromJson(Map<String, Object?> value) =>
      FilePublicationReceipt(
        batchId: (value['batchId'] ?? value['transferId']) as String,
        status: FileTransferAdmission.values.byName(value['status'] as String),
        transferId: value['transferId'] as String?,
        itemCount: value['itemCount'] as int?,
      );
  factory FilePublicationReceipt.fromSubmission(FileTransferSubmission value) =>
      FilePublicationReceipt(
        batchId: value.batchId,
        transferId: value.transferId,
        itemCount: value.itemCount,
        status: value.status,
      );
  final String batchId;
  final String? transferId;
  final int? itemCount;
  final FileTransferAdmission status;
  Map<String, Object?> toJson() => {
    'batchId': batchId,
    'status': status.name,
    if (transferId != null) 'transferId': transferId,
    if (itemCount != null) 'itemCount': itemCount,
  };
}

sealed class FilePublicationOutcome {
  const FilePublicationOutcome();
  const factory FilePublicationOutcome.published(
    FilePublicationReceipt receipt,
  ) = FilePublicationPublished;
  const factory FilePublicationOutcome.unpublished() =
      FilePublicationUnpublished;
  const factory FilePublicationOutcome.unknown() = FilePublicationUnknown;
}

final class FilePublicationPublished extends FilePublicationOutcome {
  const FilePublicationPublished(this.receipt);
  final FilePublicationReceipt receipt;
}

final class FilePublicationUnpublished extends FilePublicationOutcome {
  const FilePublicationUnpublished();
}

final class FilePublicationUnknown extends FilePublicationOutcome {
  const FilePublicationUnknown();
}

/// 任务所有者在日志提交尾部退出后提供的整批证据；单项完成不等于整批完成。
final class DurableFilePublication {
  DurableFilePublication({
    required this.batchId,
    required this.completed,
    required Set<String> sources,
  }) : sources = Set.unmodifiable(sources);
  final String batchId;
  final bool completed;
  final Set<String> sources;
}

/// 覆盖范围属于取得证据时的来源快照；后来出现的来源不能据此释放。
final class DurableFilePublications {
  DurableFilePublications({
    required this.complete,
    required List<DurableFilePublication> transfers,
    Set<String>? coveredSources,
  }) : transfers = List.unmodifiable(transfers),
       coveredSources = coveredSources == null
           ? null
           : Set.unmodifiable(coveredSources);
  final bool complete;
  final List<DurableFilePublication> transfers;
  final Set<String>? coveredSources;
}

enum FilePublicationReconciliationReason {
  invalidSnapshot,
  referenceLimit,
  incompleteSnapshot,
  sourceCoverageChanged,
  notConfigured,
}

final class FilePublicationReconciliation {
  const FilePublicationReconciliation({
    required this.reconciled,
    required this.snapshotComplete,
    this.reason,
  });
  final bool reconciled, snapshotComplete;
  final FilePublicationReconciliationReason? reason;
}

/// 保护仍被任务引用的导入缓存，不持有导入描述符或传输执行资源。
abstract interface class FilePublicationLeases {
  Future<Set<String>> get sourcePaths;

  /// 发布前绑定唯一批次；旧未知记录不能按路径认领。
  Future<FilePublicationReceipt?> begin(
    String share,
    FileTransferPlan plan, {
    required String transferId,
  });
  Future<void> finish(String share, FilePublicationOutcome outcome);
  Future<FilePublicationReconciliation> reconcile(
    DurableFilePublications evidence,
  );
}

/// 识别受管来源，禁止调用方绕过持久租约。
abstract interface class ManagedFilePublicationLeases
    implements FilePublicationLeases {
  Future<String?> ownerForSources(List<String> sources);
}
