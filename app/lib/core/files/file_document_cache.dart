import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/file_share_ledger.dart';
import 'package:scrcpy_connect/core/files/file_source_tree.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
import 'package:scrcpy_connect/core/files/models/shared_source_file.dart';
import 'package:uuid/uuid.dart';

/// 文档复制结果的页面持有权；持久发布关系复用来源账本。
/// 打开前，调用方必须先排空旧文档 scope 和平台 worker。
final class FileDocumentCache {
  FileDocumentCache._(this.store, this._legacyRoot, this.totalBytes);
  final FileShareLedger store;
  final Directory _legacyRoot;
  final int totalBytes;
  static const prefix = 'document:';

  static Future<FileDocumentCache> open({
    required Directory cacheDirectory,
    int totalBytes = 8 * 1024 * 1024 * 1024,
  }) async {
    var root = Directory(p.join(cacheDirectory.path, 'documents'));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const FileFailure('source_changed', '文档暂存根不是普通目录。');
    }
    await root.create();
    root = Directory(await root.resolveSymbolicLinks());
    final store = await FileShareLedger.open(
      cacheDirectory: root,
      directoryName: 'managed',
      directorySources: true,
      limits: ShareLimits(
        fileBytes: totalBytes,
        batchBytes: totalBytes,
        totalBytes: totalBytes,
      ),
    );
    final owner = FileDocumentCache._(store, root, totalBytes);
    // 页面不会跨进程存活。没有发布租约的页面持有权在恢复栅栏后可以归还；
    // publishing/unknown/bound 租约由同一账本保护，consume 不解除这些租约。
    final pending = await store.pending();
    for (final batch in pending) {
      await store.consume(batch.shareId);
    }
    return owner;
  }

  Future<int> _legacyBytes() async {
    var total = 0, roots = 0;
    await for (final entry in _legacyRoot.list(followLinks: false)) {
      if (p.equals(entry.path, store.root.path)) continue;
      if (++roots > 64) {
        throw const FileFailure('source_tree_limit', '旧文档暂存超过核验预算。');
      }
      total += await sourceTreeBytes(entry.path, maxBytes: totalBytes - total);
      if (total >= totalBytes) return total;
    }
    return total;
  }

  Future<({String id, String path, int availableBytes})> reserve() async {
    final legacy = await _legacyBytes();
    if (legacy >= totalBytes) {
      throw const FileFailure('document_cache_full', '文档暂存已满，已有来源保留。');
    }
    final id = const Uuid().v4();
    await store.reserve(id);
    final available = max(0, await store.availableBytes(id) - legacy);
    if (available == 0) {
      await store.fail(id, '文档暂存已满。');
      await store.consume(id);
      throw const FileFailure('document_cache_full', '文档暂存已满，已有来源保留。');
    }
    return (
      id: '$prefix$id',
      path: p.join(store.root.path, id, 'content'),
      availableBytes: available,
    );
  }

  String _id(String id) {
    if (!id.startsWith(prefix)) {
      throw const FileFailure('invalid_argument', '文档来源标识无效。');
    }
    return id.substring(prefix.length);
  }

  Future<void> complete(String id, String name) async {
    final key = _id(id), path = p.join(store.root.path, _id(id), 'content');
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await store.fail(key, '未产生文档暂存内容。');
      await release(id);
      return;
    }
    final bytes = await sourceTreeBytes(path, maxBytes: totalBytes);
    if (bytes > await store.availableBytes(key) - await _legacyBytes()) {
      throw const FileFailure('document_cache_full', '文档暂存超过总容量，未发布来源保留待收尾。');
    }
    await store.complete(key, [
      SharedSourceFile(
        diskName: 'content',
        name: name,
        size: bytes,
        directory: true,
      ),
    ]);
  }

  Future<void> release(String id) => store.consume(_id(id));

  Future<String?> ownerForSources(List<String> sources) async {
    final matches = <String>{};
    final paths = await store.sourcePaths;
    for (final source in sources) {
      for (final root in paths) {
        if (p.equals(root, source) || p.isWithin(root, source)) {
          matches.add('$prefix${p.basename(p.dirname(root))}');
        }
      }
    }
    if (matches.isEmpty) {
      // 已释放/正在复制的路径也不能被当成无主文件发布。
      if (sources.any((path) => p.isWithin(store.root.path, path))) {
        throw const FileFailure('source_changed', '文档来源尚未完成或已归还。');
      }
      return null;
    }
    if (matches.length != 1 ||
        sources.any(
          (source) => !paths.any(
            (root) =>
                (p.equals(root, source) || p.isWithin(root, source)) &&
                matches.contains('$prefix${p.basename(p.dirname(root))}'),
          ),
        )) {
      throw const FileFailure('invalid_argument', '请分别提交不同归属的暂存来源。');
    }
    return matches.single;
  }

  Future<FilePublicationReceipt?> begin(
    String id,
    FileTransferPlan plan, {
    required String transferId,
  }) => store.begin(
    _id(id),
    plan,
    transferId: transferId,
    // 持久来源键与公开文档来源标识不同，摘要继续使用公开身份。
    publicationId: id,
  );
  Future<void> finish(String id, FilePublicationOutcome outcome) =>
      store.finish(_id(id), outcome);
}
