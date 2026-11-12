import 'package:scrcpy_connect/core/files/models/file_publication_receipt.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';

export 'package:scrcpy_connect/core/files/models/file_publication_receipt.dart';

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
