import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/services/files/file_executor.dart';

import 'package:scrcpy_connect/models/share_limits.dart';
import 'package:scrcpy_connect/services/files/share_store_format.dart';
import 'package:scrcpy_connect/services/files/share_store_storage.dart';
import 'package:scrcpy_connect/services/files/source_tree.dart';
export 'package:scrcpy_connect/services/files/share_store_storage.dart'
    show ShareStoreCommit;
export 'package:scrcpy_connect/models/share_limits.dart';

final class SharedSourceFile {
  const SharedSourceFile({
    required this.diskName,
    required this.name,
    required this.size,
    this.directory = false,
  });
  final String diskName, name;
  final int size;
  final bool directory;
  Map<String, dynamic> toJson() => {
    'diskName': diskName,
    'name': name,
    'size': size,
    if (directory) 'directory': true,
  };
}

/// 分享来源及发布关系的唯一持久所有者；不读取平台 FD，也不拥有传输任务。
/// 再次打开前必须先排空旧复制 scope。未知存储结果封存旧实例，不能自行解除。
final class ShareStore implements FilePublicationLeases {
  ShareStore._(
    this.root,
    this.limits,
    this._onChanged,
    this._beforeRemove,
    this._storage,
    this._now,
    this._directories,
  );
  final Directory root;
  final ShareLimits limits;
  final void Function(Map<String, dynamic>)? _onChanged;
  final Future<void> Function(String)? _beforeRemove;
  final ShareStoreStorage _storage;
  final DateTime Function() _now;
  final bool _directories;
  final _batches = <String, Map<String, dynamic>>{};
  final _leases = <String, Map<String, dynamic>>{};
  bool _uncertain = false;
  int _unknownBatches = 0;
  static final _queues = <String, Future<void>>{};
  static final _owners = <String, WeakReference<ShareStore>>{};
  static final _random = Random.secure();

  static Future<ShareStore> open({
    required Directory cacheDirectory,
    ShareLimits limits = const ShareLimits(),
    void Function(Map<String, dynamic>)? onChanged,
    Future<void> Function(String)? beforeRemove,
    ShareStoreCommit? commitFile,
    DateTime Function()? now,
    String directoryName = 'incoming',
    bool directorySources = false,
  }) async {
    _validateLimits(limits);
    final cache = Directory(await cacheDirectory.resolveSymbolicLinks());
    if (!_safeDisk(directoryName)) _bad('暂存根名称无效。');
    final root = Directory(p.join(cache.path, directoryName));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      _bad('分享目录不能是链接或文件。');
    }
    await root.create();
    if (await root.resolveSymbolicLinks() != root.path) _bad('分享目录跳转到了其他位置。');
    final store = ShareStore._(
      root,
      limits,
      onChanged,
      beforeRemove,
      ShareStoreStorage(root, commitFile),
      now ?? DateTime.now,
      directorySources,
    );
    await store._exclusive(() async {
      // 同 isolate 后继在旧队列退出后接管；旧对象的迟到写入会被精确拒绝。
      _owners[root.path] = WeakReference(store);
      await store._load();
    }, opening: true);
    return store;
  }

  Future<T> _exclusive<T>(Future<T> Function() action, {bool opening = false}) {
    final previous = _queues[root.path] ?? Future<void>.value();
    final result = previous.then((_) async {
      if (!opening && !identical(_owners[root.path]?.target, this)) {
        throw const FileFailure('share_owner_replaced', '分享所有者已被后继接管。');
      }
      return action();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[root.path] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_queues[root.path], tail)) _queues.remove(root.path);
      }),
    );
    return result;
  }

  int get _retainedBytes => _batches.values.fold(
    0,
    (total, batch) => total + (batch['bytes'] as int),
  );
  File _batchFile(String id) => File(p.join(root.path, id, '.share'));
  File _leaseFile(String id) => File(p.join(root.path, '.leases', id));
  List<String> _paths(Map<String, dynamic> batch) => [
    for (final file in (batch['files'] as List).cast<Map<String, dynamic>>())
      p.join(root.path, batch['id'] as String, file['diskName'] as String),
  ];
  Map<String, dynamic> _view(Map<String, dynamic> batch) => {
    'shareId': batch['id'],
    'status': batch['status'],
    'text': batch['text'],
    'mime': batch['mime'],
    'files': [
      for (final file in (batch['files'] as List).cast<Map<String, dynamic>>())
        {
          'name': file['name'],
          'size': file['size'],
          'localPath': p.join(
            root.path,
            batch['id'] as String,
            file['diskName'] as String,
          ),
        },
    ],
    'errors': List<String>.from(batch['errors'] as List),
  };
  Map<String, dynamic> _leaseView(Map<String, dynamic> lease) => {
    'leaseId': lease['id'],
    'shareId': lease['shareId'],
    'transferId': lease['transferId'],
    'status': lease['transferId'] == null ? 'unknown' : 'bound',
    'files': _batches[lease['shareId']] == null
        ? null
        : _view(_batches[lease['shareId']]!)['files'],
    'publication': lease['publication'],
  };
  Map<String, dynamic> _pending() => {
    'shares': [
      for (final id in (_batches.keys.toList()..sort()))
        if (_batches[id]!['visible'] == true) _view(_batches[id]!),
    ],
  };
  Future<Map<String, dynamic>> pending() => _exclusive(() async => _pending());
  Future<Map<String, dynamic>> sources() => _exclusive(() async => _sources());
  @override
  Future<Set<String>> get sourcePaths => _exclusive(
    () async => Set<String>.unmodifiable([
      for (final batch in _batches.values) ..._paths(batch),
    ]),
  );
  Map<String, dynamic> _sources() => {
    'sourcePaths': [for (final batch in _batches.values) ..._paths(batch)],
    'leases': _leases.values.map(_leaseView).toList(),
    'limits': {
      'references': limits.references,
      'sourcesPerReference': limits.pathsPerReference,
      'totalSourceEntries': limits.totalPaths,
      'sourcePathChars': 4096,
    },
  };
  Future<Map<String, dynamic>?> existing(String id) => _exclusive(() async {
    final batch = _batches[id];
    if (batch == null) return null;
    return {
      ..._view(batch),
      'status': batch['status'] == 'importing' ? 'starting' : batch['status'],
      'reusedImport': true,
    };
  });
  void _changed(String id) {
    final batch = _batches[id];
    final event = batch != null && batch['visible'] == true
        ? {'type': 'share.received', 'data': _view(batch)}
        : <String, dynamic>{
            'type': 'share.consumed',
            'data': {'shareId': id},
          };
    // 监听器只得到不可与账本共享的投影，不参与磁盘提交结果。
    try {
      _onChanged?.call(event);
    } catch (_) {
      /* 呈现失败不撤销已经完成的提交。 */
    }
  }

  Future<void> reserve(String id, {String? text, String? mime}) =>
      _exclusive(() => _reserve(id, text, mime));
  Future<void> _reserve(String id, String? text, String? mime) async {
    _storage.writable();
    if (!_validId(id) || _batches.containsKey(id)) _bad('分享标识无效或已存在。');
    if (_uncertain ||
        _batches.values.where((b) => b['visible'] == true).length >=
            limits.pending ||
        _batches.length + _unknownBatches >= limits.batches ||
        _retainedBytes >= limits.totalBytes) {
      throw const FileFailure('share_cache_busy', '分享暂存已满或有待核对来源；已有任务不会被删除。');
    }
    if (text != null && text.runes.length > 1048576 ||
        mime != null && utf8.encode(mime).length > 256) {
      _bad('分享文字或类型过长。');
    }
    final batch = <String, dynamic>{
      'version': 2,
      'id': id,
      'created': _now().millisecondsSinceEpoch,
      'visible': true,
      'status': 'importing',
      'bytes': 0,
      'text': text,
      'mime': mime,
      'files': <Map<String, dynamic>>[],
      'errors': <String>[],
    };
    final directory = Directory(p.join(root.path, id));
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      _bad('分享标识的目录已被其他内容占用。');
    }
    await _storage.persist(() async {
      await _storage.assertRoot();
      await directory.create();
      await _storage.write(_batchFile(id), batch);
    });
    _batches[id] = batch;
  }

  /// 返回批次/全局剩余容量；调用方串行复制并扣除本批尚未 complete 的字节。
  Future<int> availableBytes(String id) => _exclusive(() async {
    _storage.writable();
    final batch = _requireBatch(id);
    if (batch['status'] != 'importing' || batch['visible'] != true) {
      throw const FileFailure('cancelled', '分享导入已结束。');
    }
    return max(
      0,
      min(
        limits.batchBytes - (batch['bytes'] as int),
        limits.totalBytes - _retainedBytes,
      ),
    );
  });
  Future<void> complete(String id, List<SharedSourceFile> files) {
    final captured = List<SharedSourceFile>.unmodifiable(files);
    return _exclusive(() async {
      _storage.writable();
      final old = _requireBatch(id);
      if (old['status'] != 'importing' || old['visible'] != true) return;
      if (captured.length > limits.sources) _bad('分享文件数超限。');
      final unique = <String>{};
      var bytes = 0;
      for (final file in captured) {
        if (!_safeDisk(file.diskName) ||
            !unique.add(file.diskName) ||
            file.size < 0 ||
            file.size > limits.fileBytes) {
          _bad('分享文件记录无效。');
        }
        final path = p.join(root.path, id, file.diskName);
        await _storage.directory(id);
        final type = await FileSystemEntity.type(path, followLinks: false);
        final size = file.directory && _directories
            ? await sourceTreeBytes(path, maxBytes: limits.batchBytes)
            : (await FileStat.stat(path)).size;
        if (type !=
                (file.directory && _directories
                    ? FileSystemEntityType.directory
                    : FileSystemEntityType.file) ||
            file.directory && !_directories ||
            size != file.size) {
          _bad('分享文件已被替换或大小不符。');
        }
        bytes += file.size;
      }
      if (bytes > limits.batchBytes ||
          _retainedBytes - (old['bytes'] as int) + bytes > limits.totalBytes) {
        throw const FileFailure('share_byte_limit', '分享内容超过暂存容量。');
      }
      final batch = {
        ...old,
        'status': 'ready',
        'bytes': bytes,
        'files': captured.map((file) => file.toJson()).toList(),
      };
      await _storage.persist(() => _storage.write(_batchFile(id), batch));
      _batches[id] = batch;
      _changed(id);
    });
  }

  /// 调用方必须先等待复制 scope 真正排空；此方法会删除未完成片段。
  Future<void> fail(String id, String reason) =>
      _exclusive(() => _fail(id, reason));
  Future<void> _fail(String id, String reason) async {
    _storage.writable();
    final old = _batches[id];
    if (old == null || old['status'] != 'importing') return;
    final batch = {
      ...old,
      'status': 'error',
      'bytes': 0,
      'files': <Map<String, dynamic>>[],
      'errors': [String.fromCharCodes(reason.runes.take(4096))],
    };
    await _storage.persist(() async {
      await _storage.removeChildren(id, keepJournal: true);
      await _storage.write(_batchFile(id), batch);
    });
    _batches[id] = batch;
    _changed(id);
  }

  Future<void> _drainBeforeRemove(String id) async {
    final active = await _exclusive(
      () async => _batches[id]?['status'] == 'importing',
    );
    if (!active) return;
    if (_beforeRemove == null) {
      throw const FileFailure(
        'share_import_active',
        '分享仍在复制；必须先等待原生 scope 排空。',
      );
    }
    // 不持有账本队列：复制的 finally 可能需要回写 fail。
    await _beforeRemove(id);
  }

  Future<Map<String, dynamic>> command(
    String command,
    Map<String, dynamic> params,
  ) async {
    final captured = _jsonCopy(params);
    final id = captured['shareId'];
    if (command == 'sharing.consume' || command == 'sharing.cancel') {
      if (id is! String) _bad('缺少分享标识。');
      await _drainBeforeRemove(id);
    }
    return _exclusive(() async {
      switch (command) {
        case 'sharing.pending':
          return _pending();
        case 'sharing.sources':
          return _sources();
        case 'sharing.reconcile':
          return _reconcile(captured);
        case 'sharing.retain':
          return _retain(_string(captured, 'shareId'));
        case 'sharing.bind':
          return _bind(
            _string(captured, 'leaseId'),
            _string(captured, 'transferId'),
          );
        case 'sharing.release':
          final lease = _leases[_string(captured, 'leaseId')];
          if (lease != null &&
              (lease['transferId'] != null || lease['publication'] != null)) {
            throw const FileFailure(
              'share_lease_in_use',
              '仍属任务或未知提交的来源只能按完整持久任务快照回收。',
            );
          }
          await _release(_string(captured, 'leaseId'));
          return {'released': true};
        case 'sharing.reject':
          final share = _string(captured, 'shareId');
          if (!_batches.containsKey(share)) {
            await _reserve(share, null, null);
            await _fail(share, captured['reason'] as String? ?? '系统未能打开分享来源。');
          }
          return _pending();
        case 'sharing.cancel':
          await _fail(id as String, '分享导入已取消。');
          return {'cancelled': true, 'shareId': id};
        case 'sharing.consume':
          await _consume(id as String);
          return {'consumed': true};
        default:
          throw const FileFailure('unknown_command', '分享来源操作无效。');
      }
    });
  }

  Future<void> _consume(String id) async {
    _storage.writable();
    final old = _batches[id];
    if (old == null) {
      _changed(id);
      return;
    }
    final batch = {...old, 'visible': false};
    await _storage.persist(() => _storage.write(_batchFile(id), batch));
    _batches[id] = batch;
    await _reclaim(id);
    _changed(id);
  }

  Future<void> _reclaim(String id) async {
    if (_uncertain ||
        _batches[id]?['visible'] != false ||
        _leases.values.any((l) => l['shareId'] == id)) {
      return;
    }
    await _storage.persist(() async {
      await _storage.directory(id);
      await Directory(p.join(root.path, id)).delete(recursive: true);
    });
    _batches.remove(id);
  }

  Future<Map<String, dynamic>> _retain(String id) async {
    _storage.writable();
    final existing = _leases.values
        .where((l) => l['shareId'] == id)
        .firstOrNull;
    if (existing != null) return _leaseView(existing);
    final batch = _requireBatch(id);
    if (batch['status'] != 'ready' || (batch['files'] as List).isEmpty) {
      _bad('分享文件尚未完成导入。');
    }
    if (_leases.length >= limits.leases) {
      throw const FileFailure('share_cache_busy', '分享租约已满。');
    }
    final lease = <String, dynamic>{
      'version': 2,
      'id': _newId(),
      'shareId': id,
      'transferId': null,
      'request': null,
      'publication': null,
      'receipt': null,
    };
    await _saveLease(lease);
    return _leaseView(lease);
  }

  Future<Map<String, dynamic>> _bind(String id, String transfer) async {
    _storage.writable();
    if (!_validId(transfer)) _bad('传输标识无效。');
    final old =
        _leases[id] ??
        (throw const FileFailure('share_source_invalid', '分享租约不存在。'));
    if (old['transferId'] != null && old['transferId'] != transfer) {
      throw const FileFailure('share_submission_mismatch', '分享已属于另一批任务。');
    }
    final lease = {...old, 'transferId': transfer};
    await _saveLease(lease);
    return _leaseView(lease);
  }

  Future<void> _saveLease(Map<String, dynamic> lease) async {
    await _storage.persist(
      () => _storage.write(_leaseFile(lease['id'] as String), lease),
    );
    _leases[lease['id'] as String] = lease;
  }

  Future<void> _release(String id) async {
    _storage.writable();
    final lease = _leases[id];
    if (lease == null) return;
    await _storage.persist(() async {
      await _storage.checkLeaseDirectory();
      final file = _leaseFile(id);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await file.delete();
      }
    });
    _leases.remove(id);
    await _reclaim(lease['shareId'] as String);
  }

  @override
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request, {
    String? transferId,
  }) {
    final captured = _jsonCopy(request);
    return _exclusive(() async {
      _storage.writable();
      if (transferId != null && !_validId(transferId)) {
        _bad('发布批次标识无效。');
      }
      final allowed = _paths(_requireBatch(share)).toSet();
      final items = captured['items'];
      if (items is! List ||
          (!_directories && items.length != allowed.length) ||
          items.isEmpty ||
          items.length > 1000 ||
          allowed.isEmpty ||
          items.any((item) => item is! Map || item['source'] is! String) ||
          (_directories
              ? items.any(
                  (item) => !allowed.any(
                    (root) =>
                        root == item['source'] ||
                        p.isWithin(root, item['source'] as String),
                  ),
                )
              : !(items
                    .map((item) => (item as Map)['source'])
                    .toSet()
                    .containsAll(allowed)))) {
        _bad('请完整提交本次分享文件。');
      }
      await _retain(share);
      final old = _leases.values.firstWhere((l) => l['shareId'] == share);
      final fingerprint = shareRequestFingerprint(captured);
      if (old['request'] != null && old['request'] != fingerprint) {
        throw const FileFailure('share_submission_mismatch', '本次分享已经使用其他传输参数。');
      }
      if (old['receipt'] != null) {
        return _jsonCopy(Map<String, Object?>.from(old['receipt'] as Map));
      }
      if (old['transferId'] != null || old['publication'] != null) {
        throw const FileFailure(
          'share_submission_unknown',
          '分享已有任务或提交结果待核对，不会重复发布。',
        );
      }
      await _saveLease({
        ...old,
        'transferId': transferId,
        'request': fingerprint,
        'publication': 'publishing',
      });
      return null;
    });
  }

  @override
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) {
    final captured = receipt == null ? null : _jsonCopy(receipt);
    return _exclusive(() async {
      _storage.writable();
      if (definitelyUnpublished) {
        final lease = _leases.values
            .where((l) => l['shareId'] == share)
            .firstOrNull;
        if (lease == null) return;
        if (lease['receipt'] != null || lease['publication'] != 'publishing') {
          throw const FileFailure('share_submission_unknown', '已有提交仍待核对，不能重置。');
        }
        await _saveLease({
          ...lease,
          'transferId': null,
          'request': null,
          'publication': null,
        });
        if (_directories) await _release(lease['id'] as String);
      } else {
        await _finished(share, captured);
      }
    });
  }

  Future<void> _finished(String share, Map<String, dynamic>? receipt) async {
    final lease =
        _leases.values.where((l) => l['shareId'] == share).firstOrNull ??
        (throw const FileFailure('share_source_invalid', '分享租约不存在。'));
    final next = {...lease};
    if (receipt == null) {
      next['publication'] = 'unknown';
    } else {
      final id = receipt['batchId'] ?? receipt['transferId'];
      if (id is! String ||
          !_validId(id) ||
          lease['transferId'] != null && lease['transferId'] != id) {
        _bad('分享任务回执与绑定不一致。');
      }
      next.addAll({
        'transferId': id,
        'receipt': _receipt(receipt),
        'publication': 'published',
      });
    }
    await _saveLease(next);
  }

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  }) {
    final captured = _jsonCopy(durableReferences);
    final coverage = coveredSources == null
        ? null
        : Set<String>.of(coveredSources);
    return _exclusive(() => _reconcile(captured, coveredSources: coverage));
  }

  Map<String, dynamic> _snapshot(
    bool reconciled,
    bool complete,
    String? reason,
  ) => {
    'reconciled': reconciled,
    'snapshotComplete': complete,
    'reason': reason,
    'leases': _leases.values.map(_leaseView).toList(),
    'retainedBytes': _retainedBytes,
    'unknownBytes': 0,
    'unknownBatches': _unknownBatches,
    'needsReview': _uncertain,
  };
  Future<Map<String, dynamic>> _reconcile(
    Map<String, dynamic> input, {
    Set<String>? coveredSources,
  }) async {
    _storage.writable();
    if (coveredSources != null &&
        (coveredSources.length > limits.totalPaths ||
            coveredSources.any(
              (path) =>
                  utf8.encode(path).length > 16384 || path.runes.length > 4096,
            ))) {
      return _snapshot(false, false, 'invalid_snapshot');
    }
    final rows = input['transfers'];
    if (rows is! List) return _snapshot(false, false, 'invalid_snapshot');
    if (rows.length > limits.references) {
      return _snapshot(false, false, 'reference_limit');
    }
    var verified = input['complete'] == true, count = 0;
    final valid = <(String, String, Set<String>)>[];
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          row['status'] is! String ||
          row['sources'] is! List) {
        return _snapshot(false, false, 'invalid_snapshot');
      }
      final paths = row['sources'] as List;
      if (paths.length > limits.pathsPerReference ||
          paths.length > limits.totalPaths - count) {
        return _snapshot(false, false, 'reference_limit');
      }
      if (utf8.encode(row['id'] as String).length > 128 ||
          utf8.encode(row['status'] as String).length > 64 ||
          paths.any(
            (path) =>
                path is! String ||
                utf8.encode(path).length > 16384 ||
                path.runes.length > 4096,
          )) {
        return _snapshot(false, false, 'invalid_snapshot');
      }
      count += paths.length;
      if (coveredSources != null && !coveredSources.containsAll(paths)) {
        return _snapshot(false, false, 'invalid_snapshot');
      }
      verified &= paths.isNotEmpty;
      valid.add((
        row['id'] as String,
        row['status'] as String,
        paths.cast<String>().toSet(),
      ));
    }
    for (final id in _leases.keys.toList()) {
      final lease = _leases[id]!;
      final batch = _batches[lease['shareId']];
      if (batch == null) continue;
      final paths = _paths(batch).toSet();
      if (coveredSources != null && !coveredSources.containsAll(paths)) {
        continue;
      }
      final matches = valid
          .where((row) => row.$3.intersection(paths).isNotEmpty)
          .toList();
      // 路径只能证明消费者覆盖，不能证明这是哪一次发布。旧的无批次未知
      // 记录继续保留；新发布在任务落盘前已绑定其唯一批次。
      final transfer = lease['transferId'] as String?;
      if (matches.length == 1 &&
          matches.single.$1 == transfer &&
          lease['request'] != null &&
          lease['receipt'] == null &&
          matches.single.$3.containsAll(paths) &&
          _validId(matches.single.$1)) {
        await _finished(lease['shareId'] as String, {
          'batchId': matches.single.$1,
          'status': 'submitted',
          'reusedTransfer': true,
        });
      }
      if (verified &&
          transfer != null &&
          valid.any(
            (row) =>
                row.$1 == transfer &&
                row.$2 == 'completed' &&
                row.$3.containsAll(paths),
          ) &&
          matches.every((row) => row.$2 == 'completed')) {
        await _release(id);
      }
    }
    if (verified) {
      final expired = _batches.values
          .where(
            (batch) =>
                _now().millisecondsSinceEpoch - (batch['created'] as int) >
                    limits.pendingExpiry.inMilliseconds &&
                batch['status'] != 'importing' &&
                (coveredSources == null ||
                    coveredSources.containsAll(_paths(batch))) &&
                !_leases.values.any(
                  (lease) => lease['shareId'] == batch['id'],
                ) &&
                !_paths(batch)
                    .any((path) => valid.any((row) => row.$3.contains(path))),
          )
          .map((batch) => batch['id'] as String)
          .toList();
      for (final id in expired) {
        await _consume(id);
      }
    }
    final coverageComplete =
        coveredSources == null ||
        _batches.values.every(
          (batch) => coveredSources.containsAll(_paths(batch)),
        );
    return _snapshot(
      true,
      verified && coverageComplete,
      !verified
          ? 'incomplete_snapshot'
          : !coverageComplete
          ? 'source_coverage_changed'
          : null,
    );
  }

  Future<void> _load() async {
    var scanned = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (p.basename(entry.path) == '.leases') continue;
      if (++scanned > 4096) {
        _uncertain = true;
        break;
      }
      final id = p.basename(entry.path);
      if (entry is! Directory || !_validId(id)) {
        _uncertain = true;
        _unknownBatches++;
        continue;
      }
      try {
        if (_batches.length >= limits.batches) {
          throw const FormatException('分享批次数超限。');
        }
        final batch = await _loadBatch(id);
        _batches[id] = batch;
      } on FileFailure {
        rethrow;
      } on Object {
        _uncertain = true;
        _unknownBatches++;
      }
    }
    final leases = Directory(p.join(root.path, '.leases'));
    if (await FileSystemEntity.type(leases.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await leases.create();
    }
    await _storage.checkLeaseDirectory();
    var count = 0;
    await for (final entry in leases.list(followLinks: false)) {
      if (++count > limits.leases) {
        _uncertain = true;
        break;
      }
      final id = p.basename(entry.path);
      try {
        if (entry is! File || !_validId(id)) {
          throw const FormatException('分享租约路径无效。');
        }
        final bytes = await _storage.read(entry, 16 * 1024);
        final Map<String, dynamic> lease;
        if (bytes.isNotEmpty && bytes.first == 123) {
          lease = _object(jsonDecode(utf8.decode(bytes)));
        } else {
          final properties = readShareProperties(bytes);
          lease = {
            'version': 2,
            'id': id,
            'shareId': properties['share'],
            'transferId': properties['transfer'],
            'request': null,
            'publication': null,
            'receipt': null,
          };
        }
        if (lease['version'] != 2 ||
            lease['id'] != id ||
            !_batches.containsKey(lease['shareId']) ||
            lease['transferId'] != null &&
                (lease['transferId'] is! String ||
                    !_validId(lease['transferId'] as String))) {
          throw const FormatException('分享租约格式无效。');
        }
        if (lease['publication'] != null &&
            !const [
              'publishing',
              'published',
              'unknown',
            ].contains(lease['publication'])) {
          throw const FormatException('分享发布状态无效。');
        }
        if (lease['publication'] == 'publishing') {
          lease['publication'] = 'unknown';
        }
        final request = lease['request'];
        if (request != null &&
            !(request is String &&
                RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(request))) {
          lease['request'] = shareRequestFingerprint(request);
        }
        if (lease['receipt'] != null) {
          lease['receipt'] = _receipt(_object(lease['receipt']));
        }
        await _saveLease(lease);
      } on FileFailure {
        rethrow;
      } on Object {
        _uncertain = true;
      }
    }
    for (final batch in _batches.values.toList()) {
      if (batch['status'] != 'importing') continue;
      if (_leases.values.any((lease) => lease['shareId'] == batch['id'])) {
        _uncertain = true;
        continue;
      }
      // open 的调用方已先排空旧 scope；这里只收尾已中断的业务日志。
      await _fail(batch['id'] as String, '上次分享导入已中断，请重新分享。');
    }
  }

  Future<Map<String, dynamic>> _loadBatch(String id) async {
    final bytes = await _storage.read(_batchFile(id), 8 * 1024 * 1024);
    final Map<String, dynamic> batch;
    if (bytes.isNotEmpty && bytes.first == 123) {
      batch = _object(jsonDecode(utf8.decode(bytes)));
    } else {
      final legacy = readShareProperties(bytes);
      final count = int.parse(legacy['count'] ?? '');
      if (count < 0 || count > limits.sources) {
        throw const FormatException('旧分享文件数无效。');
      }
      batch = {
        'version': 2,
        'id': id,
        'created': int.parse(legacy['created'] ?? ''),
        'visible': legacy['visible'] == 'true',
        'status': legacy['status'],
        'bytes': 0,
        'text': legacy['text'],
        'mime': legacy['mime'],
        'files': [
          for (var i = 0; i < count; i++)
            {
              'diskName': legacy['file.$i.disk'],
              'name': legacy['file.$i.name'],
              'size': 0,
            },
        ],
        'errors': [if (legacy['error'] != null) legacy['error']],
      };
    }
    if (batch['version'] != 2 ||
        batch['id'] != id ||
        batch['created'] is! int ||
        (batch['created'] as int) < 0 ||
        batch['visible'] is! bool ||
        !const ['importing', 'ready', 'error'].contains(batch['status']) ||
        batch['files'] is! List ||
        (batch['files'] as List).length > limits.sources ||
        batch['errors'] is! List ||
        (batch['errors'] as List).any((error) => error is! String) ||
        batch['text'] != null && batch['text'] is! String ||
        batch['mime'] != null && batch['mime'] is! String) {
      throw const FormatException('分享记录格式或版本无效。');
    }
    var total = 0;
    final unique = <String>{};
    for (final raw in batch['files'] as List) {
      final file = _object(raw);
      final disk = file['diskName'];
      if (disk is! String ||
          !_safeDisk(disk) ||
          !unique.add(disk) ||
          file['name'] is! String) {
        throw const FormatException('分享来源路径无效。');
      }
      final path = p.join(root.path, id, disk);
      final directory = file['directory'] == true;
      if (directory && !_directories ||
          file['directory'] != null && file['directory'] is! bool ||
          await FileSystemEntity.type(path, followLinks: false) !=
              (directory
                  ? FileSystemEntityType.directory
                  : FileSystemEntityType.file)) {
        throw const FormatException('分享来源不再是普通文件。');
      }
      file['size'] = directory
          ? await sourceTreeBytes(path, maxBytes: limits.batchBytes)
          : (await FileStat.stat(path)).size;
      total += file['size'] as int;
      raw['size'] = file['size'];
    }
    batch['bytes'] = total;
    await _storage.persist(() => _storage.write(_batchFile(id), batch));
    return batch;
  }

  Map<String, dynamic> _requireBatch(String id) =>
      _batches[id] ??
      (throw const FileFailure('share_source_invalid', '分享来源已不存在。'));
}

Never _bad(String message) =>
    throw FileFailure('share_source_invalid', message);
bool _validId(String id) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(id);
bool _safeDisk(String disk) =>
    disk.isNotEmpty &&
    disk != '.' &&
    disk != '..' &&
    disk != '.share' &&
    utf8.encode(disk).length <= 255 &&
    !disk.contains(RegExp(r'[/\\\x00]'));
Map<String, dynamic> _object(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : (throw const FormatException('分享记录必须为对象。'));
Map<String, dynamic> _jsonCopy(Map<String, Object?> value) =>
    _object(jsonDecode(jsonEncode(value)));
Map<String, dynamic> _receipt(Map<String, dynamic> value) => {
  for (final key in ['batchId', 'transferId', 'transferIds', 'status'])
    if (value.containsKey(key)) key: value[key],
};
String _string(Map<String, dynamic> value, String key) =>
    value[key] is String ? value[key] as String : _bad('缺少参数 $key。');
String _newId() {
  final bytes = List.generate(16, (_) => ShareStore._random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

void _validateLimits(ShareLimits limits) {
  if (limits.pending <= 0 ||
      limits.sources <= 0 ||
      limits.pending > 8 ||
      limits.sources > 32 ||
      limits.batches <= 0 ||
      limits.batches > 64 ||
      limits.leases <= 0 ||
      limits.leases > 128 ||
      limits.fileBytes <= 0 ||
      limits.batchBytes <= 0 ||
      limits.totalBytes <= 0 ||
      limits.timeout <= Duration.zero ||
      limits.pendingExpiry < Duration.zero ||
      limits.references <= 0 ||
      limits.pathsPerReference <= 0 ||
      limits.totalPaths <= 0 ||
      limits.minimumFreeBytes < 0) {
    throw const FileFailure('invalid_share_limits', '分享容量配置无效。');
  }
}
