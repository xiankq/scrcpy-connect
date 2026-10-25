import 'package:scrcpy_connect/files/documents/document_sources.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';

/// 只组合来源所有者；任务日志与来源账本仍各自负责持久状态。
final class CompositePublicationLeases implements ManagedFilePublicationLeases {
  CompositePublicationLeases({this.sharing, required this.documents});
  final FilePublicationLeases? sharing;
  final DocumentSources documents;

  @override
  Future<Set<String>> get sourcePaths async => {
    ...?await sharing?.sourcePaths,
    ...await documents.store.sourcePaths,
  };

  @override
  Future<String?> ownerForSources(List<String> sources) =>
      documents.ownerForSources(sources);

  @override
  Future<Map<String, Object?>?> begin(
    String id,
    Map<String, Object?> request, {
    String? transferId,
  }) {
    if (id.startsWith(DocumentSources.prefix)) {
      return documents.begin(id, request, transferId: transferId);
    }
    if (sharing case final owner?) {
      return owner.begin(id, request, transferId: transferId);
    }
    throw const FileFailure('share_not_configured', '来源所有者尚未配置。');
  }

  @override
  Future<void> finish(
    String id,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) {
    if (id.startsWith(DocumentSources.prefix)) {
      return documents.finish(
        id,
        receipt,
        definitelyUnpublished: definitelyUnpublished,
      );
    }
    if (sharing case final owner?) {
      return owner.finish(
        id,
        receipt,
        definitelyUnpublished: definitelyUnpublished,
      );
    }
    throw const FileFailure('share_not_configured', '来源所有者尚未配置。');
  }

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  }) async {
    final rows = durableReferences['transfers'];
    if (rows is! List ||
        rows.any(
          (row) =>
              row is! Map<Object?, Object?> ||
              row['id'] is! String ||
              row['status'] is! String ||
              row['sources'] is! List ||
              (row['sources'] as List).any((path) => path is! String),
        )) {
      return {
        'reconciled': false,
        'snapshotComplete': false,
        'reason': 'invalid_snapshot',
      };
    }
    final owners = [?sharing, documents.store];
    var complete = true;
    for (final owner in owners) {
      final paths = await owner.sourcePaths;
      final covered = coveredSources?.intersection(paths);
      final result = await owner.reconcile({
        ...durableReferences,
        'transfers': [
          for (final row in rows)
            if ((row as Map<Object?, Object?>)['sources'] is List)
              if (((row['sources'] as List).where(paths.contains)).isNotEmpty)
                {
                  ...row,
                  'sources': (row['sources'] as List)
                      .where(paths.contains)
                      .toList(),
                },
        ],
      }, coveredSources: covered);
      complete &= result['snapshotComplete'] == true;
    }
    return {'reconciled': true, 'snapshotComplete': complete};
  }
}
