import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/files/sharing/share_store.dart';
import 'package:scrcpy_connect/files/sharing/source_tree.dart';

/// 文档复制结果的页面持有权；持久发布关系复用来源账本。
/// 打开前，调用方必须先排空旧文档 scope 和平台 worker。
final class DocumentSources {
  DocumentSources._(this.store, this._legacyRoot, this.totalBytes);
  final ShareStore store;
  final Directory _legacyRoot;
  final int totalBytes;
  static const prefix = 'document:';

  static Future<DocumentSources> open({
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
    final store = await ShareStore.open(
      cacheDirectory: root,
      directoryName: 'managed',
      directorySources: true,
      limits: ShareLimits(
        fileBytes: totalBytes,
        batchBytes: totalBytes,
        totalBytes: totalBytes,
      ),
    );
    final owner = DocumentSources._(store, root, totalBytes);
    // 页面不会跨进程存活。没有发布租约的页面持有权在恢复栅栏后可以归还；
    // publishing/unknown/bound 租约由同一账本保护，consume 不解除这些租约。
    final pending = await store.pending();
    for (final batch
        in (pending['shares'] as List).cast<Map<String, dynamic>>()) {
      await store.command('sharing.consume', {'shareId': batch['shareId']});
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
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await store.reserve(id);
    final available = max(0, await store.availableBytes(id) - legacy);
    if (available == 0) {
      await store.fail(id, '文档暂存已满。');
      await store.command('sharing.consume', {'shareId': id});
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

  Future<void> release(String id) =>
      store.command('sharing.consume', {'shareId': _id(id)}).then((_) {});

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

  Future<Map<String, Object?>?> begin(
    String id,
    Map<String, Object?> request, {
    String? transferId,
  }) => store.begin(_id(id), request, transferId: transferId);
  Future<void> finish(
    String id,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) => store.finish(
    _id(id),
    receipt,
    definitelyUnpublished: definitelyUnpublished,
  );
}
