import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';

/// 只组合来源所有者；任务日志与来源账本仍各自负责持久状态。
final class FilePublicationLeasePool implements ManagedFilePublicationLeases {
  FilePublicationLeasePool({this.sharing, required this.documents});
  final FilePublicationLeases? sharing;
  final FileDocumentCache documents;

  @override
  Future<Set<String>> get sourcePaths async => {
    ...?await sharing?.sourcePaths,
    ...await documents.store.sourcePaths,
  };

  @override
  Future<String?> ownerForSources(List<String> sources) =>
      documents.ownerForSources(sources);

  @override
  Future<FilePublicationReceipt?> begin(
    String id,
    FileTransferPlan plan, {
    required String transferId,
  }) {
    if (id.startsWith(FileDocumentCache.prefix)) {
      return documents.begin(id, plan, transferId: transferId);
    }
    if (sharing case final owner?) {
      return owner.begin(id, plan, transferId: transferId);
    }
    throw const FileFailure('share_not_configured', '来源所有者尚未配置。');
  }

  @override
  Future<void> finish(String id, FilePublicationOutcome outcome) {
    if (id.startsWith(FileDocumentCache.prefix)) {
      return documents.finish(id, outcome);
    }
    if (sharing case final owner?) {
      return owner.finish(id, outcome);
    }
    throw const FileFailure('share_not_configured', '来源所有者尚未配置。');
  }

  @override
  Future<FilePublicationReconciliation> reconcile(
    DurableFilePublications evidence,
  ) async {
    final owners = [?sharing, documents.store];
    var complete = true;
    for (final owner in owners) {
      final paths = await owner.sourcePaths;
      final result = await owner.reconcile(
        DurableFilePublications(
          complete: evidence.complete,
          coveredSources: evidence.coveredSources?.intersection(paths),
          transfers: [
            for (final row in evidence.transfers)
              if (row.sources.intersection(paths).isNotEmpty)
                DurableFilePublication(
                  batchId: row.batchId,
                  completed: row.completed,
                  sources: row.sources.intersection(paths),
                ),
          ],
        ),
      );
      complete &= result.snapshotComplete;
    }
    return FilePublicationReconciliation(
      reconciled: true,
      snapshotComplete: complete,
    );
  }
}
