import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'file_executor.dart';
import 'file_type.dart';

part 'task_journal.dart';

typedef FileSnapshot = Map<String, Object?>;

/// Owns remote browsing, fixed search/gallery snapshots and durable transfers.
/// The executor supplies facts and byte I/O; all decisions are made here.
class RemoteFiles {
  RemoteFiles._(
    this.executor,
    this._journal,
    this._tasks,
    this.cache,
    this.publication,
  );
  final RemoteFileExecutor executor;
  final RemoteFileCache? cache;
  final FilePublicationLeases? publication;
  final _shareSubmissions = <String, Future<FileSnapshot>>{};
  final _batchLeases = <String, String>{};
  // The native cache outlives a Dart UI attachment. Keep uncertain destinations
  // protected continuously while ownership passes to the next attachment.
  static final _leaseHandoffs =
      <String, (RemoteFileCache, Map<String, String>)>{};
  String get _directoryKey => p.normalize(_journal.root.absolute.path);
  void _retainCacheLeases() {
    if (cache == null || _batchLeases.isEmpty) return;
    final previous = _leaseHandoffs[_directoryKey];
    _leaseHandoffs[_directoryKey] = (
      cache!,
      {...?previous?.$2, ..._batchLeases},
    );
  }

  final _TaskJournal _journal;
  final Map<String, FileSnapshot> _tasks;
  final _events = StreamController<FileSnapshot>.broadcast(sync: true);
  final Map<String, _Scan> _scans = {};
  final Map<String, FileCancellation> _running = {};
  final Map<String, Future<void>> _workers = {};
  final _preparing = <String, (String, FileCancellation, Completer<void>)>{};
  bool _closed = false;
  int _activeBatches = 0;
  Future<void> _writes = Future.value();
  Stream<FileSnapshot> get events => _events.stream;

  static Future<RemoteFiles> open({
    required RemoteFileExecutor executor,
    required Directory dataDirectory,
    RemoteFileCache? cache,
    FilePublicationLeases? publication,
  }) async {
    final journal = _TaskJournal(dataDirectory);
    final tasks = await journal.load();
    final owner = RemoteFiles._(executor, journal, tasks, cache, publication);
    final retained = _leaseHandoffs[owner._directoryKey];
    if (retained != null) {
      if (!identical(cache, retained.$1)) {
        throw const FileFailure(
          'cache_owner_changed',
          '此目录仍有原缓存执行器保护的文件，不能切换后端。',
        );
      }
      owner._batchLeases.addAll(retained.$2);
    }
    for (final task in tasks.values) {
      if (task['batchId'] == null || task['batchId'] == '') {
        task['batchId'] = task['id'];
      }
      task['generation'] ??= 0;
      task['kind'] ??= 'file';
      task['destinationScope'] ??= 'localPath';
      task['itemIndex'] ??= 0;
      task['itemCount'] ??= 1;
      if (task['direction'] == 'push' && task['sourceStamp'] is Map) {
        final stamp = Map<String, Object?>.from(task['sourceStamp']! as Map);
        if (stamp['mode'] == 0) {
          stamp['mode'] = task['kind'] == 'directory' ? 0x4000 : 0x8000;
        }
        task['sourceStamp'] = stamp;
      }
      final status = task['status'];
      if (const [
            'queued',
            'running',
            'finalizing',
            'cancelling',
            'conflict',
          ].contains(status) ||
          task['kind'] == 'directory' &&
              status == 'completed' &&
              task['treeVerified'] != true) {
        task['status'] = 'interrupted';
        if (status == 'finalizing' || status == 'cancelling') {
          task['errorCode'] = 'result_unknown';
          task['partialDestinationPossible'] = true;
          task['error'] = '上次提交或取消未取得回执，请核对目标；不会自动重试。';
        }
        await owner._save(task);
      }
    }
    if (cache != null) {
      final protectedBatches = tasks.values
          .where(
            (t) =>
                t['direction'] == 'pull' &&
                t['destinationScope'] == 'privateCache' &&
                (t['partialDestinationPossible'] == true ||
                    t['errorCode'] == 'result_unknown' ||
                    t['kind'] == 'directory' && t['treeVerified'] != true),
          )
          .map((t) => t['batchId'] as String? ?? t['id']! as String)
          .toSet();
      for (final batch in protectedBatches) {
        if (owner._batchLeases.containsKey(batch)) continue;
        final records = tasks.values
            .where(
              (t) =>
                  (t['batchId'] ?? t['id']) == batch &&
                  (t['parentId'] == null || !tasks.containsKey(t['parentId'])),
            )
            .expand(
              (t) => [
                FileCacheReservation(t['destination']! as String, 0),
                if (t['temporaryPath'] is String)
                  FileCacheReservation(t['temporaryPath']! as String, 0),
              ],
            )
            .toList();
        owner._batchLeases[batch] = await cache.reserve(records);
        owner._retainCacheLeases();
      }
      for (final batch in owner._batchLeases.keys.toList()) {
        if (!protectedBatches.contains(batch)) {
          await cache.release(owner._batchLeases[batch]!);
          owner._batchLeases.remove(batch);
        }
      }
    }
    _leaseHandoffs.remove(owner._directoryKey);
    return owner;
  }

  static String _id() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = bytes[6] & 15 | 64;
    bytes[8] = bytes[8] & 63 | 128;
    final text = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }

  static String _validName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\u0000')) {
      throw const FileFailure('invalid_name', '名称无效。');
    }
    return name;
  }

  static String _remote(String path) {
    if (!path.startsWith('/') ||
        path.contains('\u0000') ||
        utf8.encode(path).length > 4096 ||
        path.split('/').contains('..')) {
      throw const FileFailure('invalid_path', '设备路径无效。');
    }
    return p.posix.normalize(path);
  }

  void _check() {
    if (_closed) throw const FileFailure('closed', '文件运行时已关闭。');
  }

  Future<void> _save(FileSnapshot task) {
    final snapshot = Map<String, Object?>.from(task);
    final result = _writes.then((_) => _journal.upsert(snapshot));
    _writes = result;
    return result.then((_) {
      if (!_events.isClosed) {
        _events.add({'type': 'transfers.changed', 'transferId': task['id']});
      }
    });
  }

  static String mime(String path) => FileTypePolicy.mime(path);

  static bool _matches(FileSnapshot entry, String filter) => switch (filter) {
    'all' => true,
    'folders' => entry['kind'] == 'directory',
    'images' || 'videos' || 'audio' || 'documents' || 'archives' =>
      FileTypePolicy.kind(
            name: entry['name'] as String? ?? '',
            mime: entry['mime'] as String?,
          ).name ==
          filter,
    _ => throw const FileFailure('invalid_argument', '文件类型无效。'),
  };

  static FileSnapshot _entry(String root, FileEntryFact fact) {
    final name = fact.pathName;
    return {
      'name': fact.displayName,
      'path': name == null ? null : p.posix.join(root, name),
      'kind': fact.stamp?.kind ?? 'failed',
      'isDirectory': fact.stamp?.isDirectory ?? false,
      'isSymlink': fact.stamp?.isLink ?? false,
      'nameIsUtf8': name != null,
      'canOpen': name != null && fact.error == null,
      'canManage': name != null && fact.error == null,
      'size': fact.stamp?.size ?? 0,
      'modified': fact.stamp?.modifiedSeconds ?? 0,
      'modifiedSeconds': fact.stamp?.modifiedSeconds ?? 0,
      'mime': mime(fact.displayName),
      'mode': fact.stamp?.mode ?? 0,
      'selectable':
          name != null &&
          fact.error == null &&
          (fact.stamp?.isFile == true || fact.stamp?.isDirectory == true),
      if (name == null) 'errorCode': 'invalid_filename',
      if (fact.error != null) 'errorCode': fact.error!.code,
    };
  }

  Future<FileSnapshot> browse(
    String device,
    String path, {
    String filter = 'all',
    String sort = 'name',
    bool descending = false,
    int offset = 0,
    int limit = 200,
    FileCancellation? cancellation,
  }) async {
    _check();
    path = _remote(path);
    if (offset < 0 ||
        limit < 1 ||
        limit > 10000 ||
        !const ['name', 'size', 'modified', 'type'].contains(sort)) {
      throw const FileFailure('invalid_argument', '分页或排序参数无效。');
    }
    final token = cancellation ?? FileCancellation();
    final facts = await executor.list(
      device,
      path,
      local: false,
      limit: 10000,
      cancellation: token,
    );
    token.check();
    final entries = facts.entries
        .map((e) => _entry(path, e))
        .where((e) => _matches(e, filter))
        .toList();
    entries.sort((a, b) {
      final directory = (a['kind'] == 'directory' ? 0 : 1).compareTo(
        b['kind'] == 'directory' ? 0 : 1,
      );
      if (directory != 0) return directory;
      final int result = switch (sort) {
        'size' => (a['size']! as int).compareTo(b['size']! as int),
        'modified' => (a['modified']! as int).compareTo(b['modified']! as int),
        'type' => (a['mime']! as String).compareTo(b['mime']! as String),
        _ => (a['name']! as String).toLowerCase().compareTo(
          (b['name']! as String).toLowerCase(),
        ),
      };
      return (descending ? -result : result) != 0
          ? (descending ? -result : result)
          : (a['name']! as String).compareTo(b['name']! as String);
    });
    return {
      'path': path,
      'entries': entries.skip(offset).take(limit).toList(),
      'total': entries.length,
      'offset': offset,
      'hasMore': offset + limit < entries.length,
      'truncated': facts.truncated,
    };
  }

  FileSnapshot startSearch(
    String device,
    String root, {
    required String query,
    String filter = 'all',
    bool gallery = false,
  }) {
    _check();
    root = _remote(root);
    if (utf8.encode(query).length > 256 ||
        query.contains('\u0000') ||
        (!gallery && query.trim().isEmpty && filter == 'all')) {
      throw const FileFailure('invalid_argument', '请输入最多256字节的文件名或选择文件类型。');
    }
    _matches({'mime': '', 'kind': ''}, filter);
    if (_scans.values.where((s) => s.status == 'running').length >= 4) {
      throw const FileFailure('busy', '搜索或扫描数量已达到上限。');
    }
    while (_scans.length >= 16) {
      final old = _scans.entries
          .where((e) => e.value.status != 'running')
          .firstOrNull;
      if (old == null) break;
      _scans.remove(old.key);
    }
    final scan = _Scan(
      _id(),
      device,
      root,
      query.toLowerCase(),
      filter,
      gallery,
    );
    _scans[scan.id] = scan;
    scan.worker = _walk(scan);
    return scan.snapshot();
  }

  Future<void> _walk(_Scan scan) async {
    final timer = Timer(const Duration(seconds: 30), () {
      scan.timedOut = true;
      scan.cancellation.cancel();
    });
    final queue = Queue<(String, int)>()..add((scan.root, 0));
    var directories = 0, bytes = 0;
    try {
      final root = await executor.stat(
        scan.device,
        scan.root,
        local: false,
        followStorageAlias: true,
        cancellation: scan.cancellation,
      );
      if (!root.isDirectory) {
        throw const FileFailure('not_directory', '搜索根路径不是目录。');
      }
      while (queue.isNotEmpty) {
        scan.cancellation.check();
        final (path, depth) = queue.removeFirst();
        scan.currentDirectory = path;
        scan.visitedDirectories = directories + 1;
        if (++directories > (scan.gallery ? 4096 : 2048)) {
          scan.limited = true;
          break;
        }
        DirectoryFacts facts;
        try {
          facts = await executor.list(
            scan.device,
            path,
            local: false,
            limit: 4096,
            cancellation: scan.cancellation,
          );
        } on FileFailure catch (e) {
          if (e.code == 'cancelled') rethrow;
          scan.issue(path, e.code, e.message);
          continue;
        }
        if (facts.truncated) {
          scan.issue(path, 'directory_limit', '目录超过4096项。');
          scan.limited = true;
        }
        for (final fact in facts.entries) {
          scan.cancellation.check();
          if (++scan.visited > 50000) {
            scan.limited = true;
            break;
          }
          final entry = _entry(path, fact);
          final child = entry['path'] as String?;
          if (child == null || fact.error != null) {
            scan.issue(
              path,
              fact.error?.code ?? 'invalid_filename',
              fact.error?.message ?? '文件名不能表示为有效文字。',
            );
            continue;
          }
          if (scan.gallery &&
              (child == '/sdcard/Android/data' ||
                  child == '/sdcard/Android/obb')) {
            continue;
          }
          if (fact.stamp?.isDirectory == true) {
            if (depth < 32) {
              queue.add((child, depth + 1));
            } else {
              scan.limited = true;
              scan.issue(child, 'depth_limit', '已达到32层目录深度。');
            }
          }
          if (scan.gallery
              ? fact.stamp?.isFile == true &&
                    ((entry['mime']! as String).startsWith('image/') ||
                        (entry['mime']! as String).startsWith('video/'))
              : (entry['name']! as String).toLowerCase().contains(scan.query) &&
                    _matches(entry, scan.filter)) {
            bytes += utf8.encode(child).length + 256;
            if (scan.entries.length >= (scan.gallery ? 25000 : 500) ||
                bytes > 8 * 1024 * 1024) {
              scan.limited = true;
              break;
            }
            scan.entries.add(entry);
          }
        }
        if (scan.visited > 50000 ||
            scan.entries.length >= (scan.gallery ? 25000 : 500) ||
            bytes > 8 * 1024 * 1024) {
          break;
        }
      }
      scan.status = scan.limited || scan.issues.isNotEmpty
          ? 'partial'
          : 'completed';
    } on FileFailure catch (e) {
      if (e.code == 'cancelled') {
        scan.status = scan.timedOut ? 'partial' : 'cancelled';
      } else {
        scan.issue(scan.root, e.code, e.message);
        scan.status = 'failed';
      }
    } catch (e) {
      scan.issue(scan.root, 'scan_failed', '$e');
      scan.status = 'failed';
    } finally {
      timer.cancel();
      if (scan.gallery) {
        scan.entries.sort((a, b) {
          final modified = (b['modified']! as int).compareTo(
            a['modified']! as int,
          );
          return modified != 0
              ? modified
              : (a['path']! as String).compareTo(b['path']! as String);
        });
      }
      if (!_events.isClosed) {
        _events.add({
          'type': scan.gallery ? 'media.scan.changed' : 'files.search.changed',
          'deviceId': scan.device,
          'scanId': scan.id,
          'searchId': scan.id,
        });
      }
    }
  }

  FileSnapshot scan(
    String device,
    String id, {
    int offset = 0,
    int limit = 100,
  }) {
    final scan = _scans[id];
    if (scan == null) throw const FileFailure('search_not_found', '搜索记录已过期。');
    if (scan.device != device) {
      throw const FileFailure('search_device_mismatch', '搜索属于另一台设备。');
    }
    if (offset < 0 || limit < 1 || limit > 500) {
      throw const FileFailure('invalid_argument', '分页参数无效。');
    }
    return scan.snapshot(offset: offset, limit: limit);
  }

  Future<FileSnapshot> cancelScan(String device, String id) async {
    final scan = _scans[id];
    if (scan == null || scan.device != device) {
      throw const FileFailure('search_not_found', '搜索不存在。');
    }
    scan.cancellation.cancel();
    await scan.worker;
    return scan.snapshot();
  }

  Future<void> cancelDevice(String device) async {
    final preparing = _preparing.values.where((p) => p.$1 == device).toList();
    for (final preparation in preparing) {
      preparation.$2.cancel();
    }
    await Future.wait(preparing.map((p) => p.$3.future));
    for (final scan in _scans.values.where((s) => s.device == device)) {
      scan.cancellation.cancel();
    }
    await _cancelTasks(
      _tasks.values.where((t) => t['deviceId'] == device).toList(),
    );
    await Future.wait(
      _scans.values.where((s) => s.device == device).map((s) => s.worker),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final preparing = _preparing.values.toList();
    for (final preparation in preparing) {
      preparation.$2.cancel();
    }
    await Future.wait(preparing.map((p) => p.$3.future));
    for (final s in _scans.values) {
      s.cancellation.cancel();
    }
    for (final t in _running.values) {
      t.cancel();
    }
    try {
      await Future.wait([
        ..._scans.values.map((s) => s.worker),
        ..._workers.values,
      ]);
      await _writes;
    } finally {
      _retainCacheLeases();
      await _events.close();
    }
  }

  static bool _terminal(Object? status) => const [
    'completed',
    'skipped',
    'failed',
    'cancelled',
    'interrupted',
  ].contains(status);
  FileSnapshot transfers() => {
    'transfers': _tasks.values.map(_project).toList(),
    'batches': _batches(),
  };
  FileSnapshot _project(FileSnapshot task) {
    final result = Map<String, Object?>.from(task);
    final uncertain =
        task['errorCode'] == 'result_unknown' ||
        task['errorCode'] == 'source_changed';
    result.addAll({
      'canResume': false,
      'canRestart':
          const [
            'failed',
            'cancelled',
            'interrupted',
          ].contains(task['status']) &&
          !uncertain,
      'restartFromBeginning': true,
      'restartRequiresSourceCheck': true,
      'canCancel': !_terminal(task['status']),
      'canExport':
          task['direction'] == 'pull' &&
          task['status'] == 'completed' &&
          (task['kind'] == 'file' ||
              task['treeVerified'] == true && task['treeComplete'] == true),
      'canExportPartial':
          task['direction'] == 'pull' &&
          task['kind'] == 'directory' &&
          task['treeVerified'] == true &&
          task['treeComplete'] != true &&
          task['saveMode'] == 'directoryMerge',
    });
    final evicted =
        task['direction'] == 'pull' &&
        task['destinationScope'] == 'privateCache' &&
        _terminal(task['status']) &&
        FileSystemEntity.typeSync(
              task['destination']! as String,
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound;
    result['cacheEvicted'] = evicted;
    if (evicted) {
      result['canExport'] = false;
      result['canExportPartial'] = false;
    }
    if (result['canExport'] == true) result['localPath'] = task['destination'];
    if (result['canExportPartial'] == true) {
      result['partialLocalPath'] = task['destination'];
    }
    return result;
  }

  List<FileSnapshot> _batches() {
    final groups = <String, List<FileSnapshot>>{};
    for (final task in _tasks.values) {
      groups
          .putIfAbsent(
            task['batchId'] as String? ?? task['id']! as String,
            () => [],
          )
          .add(task);
    }
    return groups.entries.map((g) {
      final tasks = g.value;
      int count(String status) =>
          tasks.where((t) => t['status'] == status).length;
      final active = tasks.any(
        (t) =>
            !_terminal(t['status']) ||
            t['kind'] == 'directory' &&
                t['status'] == 'completed' &&
                t['treeVerified'] != true,
      );
      final status = count('conflict') > 0
          ? 'conflict'
          : active
          ? 'running'
          : count('failed') > 0
          ? 'partialFailure'
          : count('interrupted') > 0
          ? 'interrupted'
          : count('cancelled') > 0
          ? 'cancelled'
          : count('skipped') > 0
          ? 'completedWithSkips'
          : 'completed';
      return <String, Object?>{
        'batchId': g.key,
        'deviceId': tasks.first['deviceId'],
        'direction': tasks.first['direction'],
        'destinationScope': tasks.first['destinationScope'],
        'status': status,
        'itemCount': tasks.length,
        'fileCount': tasks.where((t) => t['kind'] == 'file').length,
        'directoryCount': tasks.where((t) => t['kind'] == 'directory').length,
        'completed': count('completed'),
        'failed': count('failed'),
        'cancelled': count('cancelled'),
        'skipped': count('skipped'),
        'interrupted': count('interrupted'),
        'transferred': tasks.fold<int>(
          0,
          (n, t) => n + (t['transferred'] as int? ?? 0),
        ),
        'total': tasks.fold<int>(0, (n, t) => n + (t['total'] as int? ?? 0)),
        'canResume': false,
        'canRestart': false,
        'canCancel': active,
        'selectionSnapshot': true,
        'selectedRootCount': tasks.where((t) => t['parentId'] == null).length,
      };
    }).toList();
  }

  FileSnapshot transfer(String id) {
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    return {
      ..._project(task),
      'items':
          _tasks.values
              .where((t) => t['batchId'] == task['batchId'])
              .map(_project)
              .toList()
            ..sort(
              (a, b) => (a['itemIndex'] as int? ?? 0).compareTo(
                b['itemIndex'] as int? ?? 0,
              ),
            ),
      'batch': _batches()
          .where((b) => b['batchId'] == task['batchId'])
          .firstOrNull,
    };
  }

  List<FileSnapshot> activities({Map<String, String> deviceNames = const {}}) =>
      _tasks.values
          .where((t) => !_terminal(t['status']))
          .map(
            (t) => {
              'id': 'transfer:${t['id']}',
              'deviceId': t['deviceId'],
              'deviceName': deviceNames[t['deviceId']] ?? 'Android 设备',
              'name': t['name'],
              'status': t['status'],
              'canStop': true,
              'stopImpact': '仅取消这一项传输；已完成的文件不回滚。',
            },
          )
          .toList();
  Future<void> _cancelTasks(List<FileSnapshot> tasks) async {
    final active = tasks.where((t) => !_terminal(t['status'])).toList();
    for (final task in active) {
      final token = _running[task['id']];
      task['status'] = token == null ? 'cancelled' : 'cancelling';
      token?.cancel();
    }
    for (final task in active) {
      await _save(task);
    }
    final batches = active.map((t) => t['batchId']).toSet();
    await Future.wait(
      batches.map((b) => _workers[b]).whereType<Future<void>>(),
    );
    for (final task in active.where((t) => t['status'] == 'cancelling')) {
      task['status'] = 'cancelled';
      if (task['saveMode'] == 'committing') {
        task['errorCode'] = 'result_unknown';
        task['partialDestinationPossible'] = true;
      }
      await _save(task);
    }
  }

  Future<FileSnapshot> cancelBatch(String batch) async {
    final tasks = _tasks.values.where((t) => t['batchId'] == batch).toList();
    if (tasks.isEmpty) throw const FileFailure('not_found', '批任务不存在。');
    await _cancelTasks(tasks);
    return {'batchId': batch, 'status': 'cancelled'};
  }

  Future<FileSnapshot> startTransfer(
    String device,
    bool push,
    List<FileSnapshot> selections, {
    String policy = 'ask',
    String destinationScope = 'localPath',
    String? shareId,
  }) async {
    _check();
    if (selections.isEmpty ||
        selections.length > 1000 ||
        !const ['ask', 'keepBoth', 'replace', 'skip'].contains(policy)) {
      throw const FileFailure('invalid_argument', '传输选择或冲突策略无效。');
    }
    if (!const ['localPath', 'privateCache'].contains(destinationScope) ||
        destinationScope == 'privateCache' && cache == null) {
      throw const FileFailure('cache_unavailable', '私有缓存执行器尚未配置。');
    }
    final batch = _id(), token = FileCancellation();
    final pending = Queue<(String, String, String?, int)>();
    final selected = <FileSnapshot>[];
    final destinations = <String>{};
    var pathBytes = 0;
    for (final item in selections) {
      final source = item['source']! as String,
          destination = item['destination']! as String;
      if (push) {
        if (!p.isAbsolute(source)) {
          throw const FileFailure('invalid_path', '源必须为本机绝对路径。');
        }
        _remote(destination);
      } else {
        _remote(source);
        if (!p.isAbsolute(destination)) {
          throw const FileFailure('invalid_path', '目标必须为本机绝对路径。');
        }
      }
      pending.add((source, destination, null, 0));
    }
    final timer = Timer(const Duration(seconds: 120), token.cancel);
    final prepared = Completer<void>();
    _preparing[batch] = (device, token, prepared);
    try {
      while (pending.isNotEmpty) {
        token.check();
        final (source, destination, parent, depth) = pending.removeFirst();
        pathBytes +=
            utf8.encode(source).length + utf8.encode(destination).length;
        if (selected.length >= 10000 ||
            depth > 64 ||
            pathBytes > 16 * 1024 * 1024) {
          throw const FileFailure('tree_limit', '选择超过10000项、64层或16MiB路径上限。');
        }
        if (!destinations.add(destination)) {
          throw const FileFailure('duplicate_destination', '任务不能重复写入同一目标。');
        }
        final stamp = await executor.stat(
          device,
          source,
          local: push,
          followStorageAlias: !push && parent == null,
          cancellation: token,
        );
        final id = _id();
        final task = <String, Object?>{
          'id': id,
          'shareId': ?shareId,
          'deviceId': device,
          'direction': push ? 'push' : 'pull',
          'source': source,
          'destination': destination,
          'name': push ? p.basename(source) : p.posix.basename(source),
          'status': stamp.isFile || stamp.isDirectory ? 'queued' : 'skipped',
          'transferred': 0,
          'total': stamp.isFile ? stamp.size : 0,
          'policy': policy,
          'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'batchId': batch,
          'itemIndex': selected.length,
          'generation': 0,
          'sourceStamp': stamp.toJson(),
          'kind': stamp.kind,
          'parentId': parent,
          'treeVerified': false,
          'treeComplete': false,
          'destinationScope': destinationScope,
          'partialDestinationPossible': false,
        };
        selected.add(task);
        if (stamp.isDirectory) {
          final children = await executor.list(
            device,
            source,
            local: push,
            limit: 10000 - selected.length,
            cancellation: token,
          );
          if (children.truncated) {
            throw const FileFailure('tree_limit', '选中目录超过条目上限。');
          }
          for (final child in children.entries) {
            final name = child.pathName;
            if (name == null || child.error != null) {
              throw child.error ??
                  const FileFailure('invalid_filename', '目录包含无法安全表示的文件名。');
            }
            pending.add((
              push ? p.join(source, name) : p.posix.join(source, name),
              push
                  ? p.posix.join(destination, name)
                  : p.join(destination, name),
              id,
              depth + 1,
            ));
          }
        }
      }
      if (!push && destinationScope == 'privateCache') {
        final reservations = <FileCacheReservation>[];
        final totals = <String, int>{};
        for (final task in selected.reversed) {
          final id = task['id']! as String;
          final size = (totals[id] ?? 0) + (task['total'] as int? ?? 0);
          totals[id] = size;
          final parent = task['parentId'];
          if (parent is String) totals[parent] = (totals[parent] ?? 0) + size;
        }
        for (final root in selected.where((t) => t['parentId'] == null)) {
          final size = totals[root['id']]!;
          reservations.add(
            FileCacheReservation(
              root['destination']! as String,
              root['kind'] == 'file' ? 0 : size,
            ),
          );
          if (root['kind'] == 'file') {
            reservations.add(
              FileCacheReservation(
                p.join(
                  p.dirname(root['destination']! as String),
                  '.interop-${root['id']}-${root['generation']}.part',
                ),
                size,
              ),
            );
          }
        }
        _batchLeases[batch] = await cache!.reserve(reservations);
      }
      for (final task in selected) {
        task['itemCount'] = selected.length;
        _tasks[task['id']! as String] = task;
        await _save(task);
      }
    } finally {
      timer.cancel();
      _preparing.remove(batch);
      prepared.complete();
    }
    _schedule(batch);
    return {
      'batchId': batch,
      'transferId': selected.first['id'],
      'status': 'queued',
      'itemCount': selected.length,
    };
  }

  void _schedule(String batch) {
    if (_closed || _workers.containsKey(batch)) return;
    final job = Future<void>(() => _runBatch(batch));
    _workers[batch] = job;
    unawaited(
      job.then<void>(
        (_) {
          _workers.remove(batch);
          if (!_closed &&
              _tasks.values.any(
                (t) => t['batchId'] == batch && t['status'] == 'queued',
              ) &&
              !_tasks.values.any(
                (t) => t['batchId'] == batch && t['status'] == 'conflict',
              )) {
            _schedule(batch);
          }
        },
        onError: (Object error, StackTrace stack) {
          _workers.remove(batch);
          if (!_events.isClosed) {
            _events.add({
              'type': 'transfers.failed',
              'batchId': batch,
              'error': '$error',
            });
          }
        },
      ),
    );
  }

  Future<void> _runBatch(String batch) async {
    // One device batch is sequential; at most two concurrent batches globally.
    while (!_closed && _activeBatches >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_closed) return;
    _activeBatches++;
    try {
      final tasks = _tasks.values.where((t) => t['batchId'] == batch).toList()
        ..sort(
          (a, b) => (a['itemIndex']! as int).compareTo(b['itemIndex']! as int),
        );
      for (final task in tasks) {
        if (_closed || task['status'] == 'conflict') break;
        if (task['status'] != 'queued') continue;
        final token = FileCancellation();
        _running[task['id']! as String] = token;
        try {
          await _runTask(task, token);
        } on FileFailure catch (e) {
          task['status'] = e.code == 'conflict'
              ? 'conflict'
              : e.code == 'cancelled'
              ? 'cancelled'
              : 'failed';
          task['errorCode'] =
              task['status'] == 'failed' && task['saveMode'] == 'committing' ||
                  task['status'] == 'cancelled' &&
                      task['saveMode'] == 'committing'
              ? 'result_unknown'
              : e.code;
          task['partialDestinationPossible'] =
              task['errorCode'] == 'result_unknown';
          task['error'] = e.message;
          await _save(task);
        } catch (e) {
          task['status'] = 'failed';
          task['errorCode'] = task['saveMode'] == 'committing'
              ? 'result_unknown'
              : 'transfer_failed';
          task['partialDestinationPossible'] =
              task['errorCode'] == 'result_unknown';
          task['error'] = '$e';
          await _save(task);
        } finally {
          _running.remove(task['id']);
        }
        if (task['status'] == 'conflict') break;
      }
      final children = _children(tasks);
      for (final task in tasks.reversed.where(
        (t) => t['kind'] == 'directory' && t['status'] == 'completed',
      )) {
        task['treeVerified'] = true;
        task['treeComplete'] = (children[task['id']] ?? const []).every(
          (child) =>
              child['status'] == 'completed' &&
              (child['kind'] != 'directory' ||
                  child['treeVerified'] == true &&
                      child['treeComplete'] == true),
        );
        await _save(task);
      }
    } finally {
      _activeBatches--;
      final tasks = _tasks.values.where((t) => t['batchId'] == batch);
      if (tasks.every(
        (t) =>
            _terminal(t['status']) &&
            t['partialDestinationPossible'] != true &&
            t['errorCode'] != 'result_unknown',
      )) {
        final lease = _batchLeases.remove(batch);
        if (lease != null) await cache?.release(lease);
      }
      try {
        await reconcileShares();
      } catch (_) {
        /* Sources remain retained if a durable proof is unavailable. */
      }
    }
  }

  Future<FileStamp?> _destination(
    FileSnapshot task,
    FileCancellation token,
  ) async {
    try {
      return await executor.stat(
        task['deviceId']! as String,
        task['destination']! as String,
        local: task['direction'] == 'pull',
        cancellation: token,
      );
    } on FileFailure catch (e) {
      if (e.code == 'not_found') return null;
      rethrow;
    }
  }

  Future<void> _runTask(FileSnapshot task, FileCancellation token) async {
    final device = task['deviceId']! as String,
        source = task['source']! as String;
    final push = task['direction'] == 'push';
    final parent = _tasks[task['parentId']];
    if (parent != null && parent['status'] != 'completed') {
      task['status'] = 'skipped';
      task['errorCode'] = 'parent_incomplete';
      await _save(task);
      return;
    }
    final expected = FileStamp.fromJson(
      Map<String, Object?>.from(task['sourceStamp']! as Map),
    );
    if (await executor.stat(
          device,
          source,
          local: push,
          followStorageAlias: !push && parent == null,
          cancellation: token,
        ) !=
        expected) {
      throw const FileFailure('source_changed', '源文件与选择时不同，需重新选择。');
    }
    var ancestor = parent;
    for (var depth = 0; ancestor != null && depth < 64; depth++) {
      final state = await executor.stat(
        device,
        ancestor['destination']! as String,
        local: !push,
        cancellation: token,
      );
      if (!state.isDirectory) {
        throw const FileFailure('source_changed', '目标父目录已变化，不能沿链接或特殊文件写入。');
      }
      ancestor = _tasks[ancestor['parentId']];
    }
    var existing = await _destination(task, token);
    if (existing != null && !(expected.isDirectory && existing.isDirectory)) {
      switch (task['policy']) {
        case 'skip':
          task['status'] = 'skipped';
          await _save(task);
          return;
        case 'ask':
          throw const FileFailure('conflict', '目标存在，请选择冲突处理方式。');
        case 'replace':
          if (expected.isDirectory || !existing.isFile) {
            throw const FileFailure('conflict', '不能替换目录、链接或特殊文件。');
          }
        case 'keepBoth':
          final original = task['destination']! as String;
          var found = false;
          for (var i = 1; i <= 10000; i++) {
            final context = push ? p.posix : p.context;
            task['destination'] = context.join(
              context.dirname(original),
              '${context.basenameWithoutExtension(original)} ($i)${context.extension(original)}',
            );
            if (await _destination(task, token) == null) {
              found = true;
              existing = null;
              break;
            }
          }
          if (!found) throw const FileFailure('conflict', '无法找到空闲目标名称。');
          if (expected.isDirectory) {
            final replacement = task['destination']! as String;
            final context = push ? p.posix : p.context;
            for (final child in _subtree([task]).skip(1)) {
              child['destination'] = context.join(
                replacement,
                context.relative(
                  child['destination']! as String,
                  from: original,
                ),
              );
              await _save(child);
            }
          }
      }
    }
    token.check();
    final destination = task['destination']! as String;
    if (expected.isDirectory) {
      task['status'] = 'finalizing';
      task['saveMode'] = 'committing';
      await _save(task);
      if (existing == null) {
        await executor.mutate(
          device,
          'mkdir',
          destination,
          local: !push,
          cancellation: token,
        );
      }
      task['saveMode'] = 'directoryMerge';
      task['status'] = 'completed';
      await _save(task);
      return;
    }
    final temporary = push
        ? '$destination.interop-${task['id']}-${task['generation']}.part'
        : p.join(
            p.dirname(destination),
            '.interop-${task['id']}-${task['generation']}.part',
          );
    task['temporaryPath'] = temporary;
    task['status'] = 'running';
    await _save(task);
    try {
      final count = await executor.copy(
        device,
        source,
        temporary,
        push: push,
        expected: expected,
        cancellation: token,
        onProgress: (bytes) {
          task['transferred'] = bytes;
          if (!_events.isClosed) {
            _events.add({
              'type': 'transfers.progress',
              'transferId': task['id'],
              'transferred': bytes,
            });
          }
        },
      );
      task['transferred'] = count;
      task['status'] = 'finalizing';
      task['saveMode'] = 'committing';
      await _save(task);
      token.check();
      task['saveMode'] = await executor.mutate(
        device,
        'commit',
        temporary,
        destination: destination,
        local: !push,
        replace: task['policy'] == 'replace',
        cancellation: token,
      );
      task['status'] = 'completed';
      task['temporaryPath'] = null;
      await _save(task);
    } finally {
      if (!push) {
        try {
          await executor.mutate(
            device,
            'releasePart',
            temporary,
            local: true,
            cancellation: FileCancellation(),
          );
        } catch (_) {
          /* The native registry is bounded and closes on runtime shutdown. */
        }
      }
    }
  }

  static Map<String, List<FileSnapshot>> _children(
    Iterable<FileSnapshot> tasks,
  ) {
    final children = <String, List<FileSnapshot>>{};
    for (final task in tasks) {
      final parent = task['parentId'];
      if (parent is String) children.putIfAbsent(parent, () => []).add(task);
    }
    return children;
  }

  List<FileSnapshot> _subtree(Iterable<FileSnapshot> roots) {
    final children = _children(_tasks.values);
    final pending = Queue<FileSnapshot>()..addAll(roots);
    final selected = <FileSnapshot>[];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final task = pending.removeFirst();
      if (!seen.add(task['id']! as String)) continue;
      selected.add(task);
      pending.addAll(children[task['id']] ?? const []);
    }
    return selected;
  }

  Future<FileSnapshot> cancelTransfer(String id) async {
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    await _cancelTasks(_subtree([task]));
    return _project(task);
  }

  Future<FileSnapshot> resolveTransfer(
    String id,
    String policy, {
    bool restart = false,
    bool applyToAll = false,
  }) async {
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    if (!const ['ask', 'keepBoth', 'replace', 'skip'].contains(policy)) {
      throw const FileFailure('invalid_argument', '冲突策略无效。');
    }
    if (task['status'] != 'conflict' &&
        (!restart || _project(task)['canRestart'] != true)) {
      throw const FileFailure('restart_unavailable', '此任务不能安全重试，请核对结果或重新选择。');
    }
    final batch = task['batchId']! as String;
    if (task['direction'] == 'pull' &&
        task['destinationScope'] == 'privateCache' &&
        !_batchLeases.containsKey(batch)) {
      final next = (task['generation'] as int? ?? 0) + 1;
      _batchLeases[batch] = await cache!.reserve([
        FileCacheReservation(
          task['destination']! as String,
          task['kind'] == 'directory' ? task['total'] as int? ?? 0 : 0,
        ),
        if (task['kind'] == 'file')
          FileCacheReservation(
            p.join(
              p.dirname(task['destination']! as String),
              '.interop-${task['id']}-$next.part',
            ),
            task['total'] as int? ?? 0,
          ),
      ]);
    }
    task['policy'] = policy;
    task['generation'] = (task['generation'] as int? ?? 0) + 1;
    task['status'] = 'queued';
    task['error'] = null;
    task['errorCode'] = null;
    task['transferred'] = 0;
    await _save(task);
    if (applyToAll) {
      for (final candidate in _tasks.values.where(
        (t) => t['batchId'] == task['batchId'] && t['status'] == 'queued',
      )) {
        candidate['policy'] = policy;
        await _save(candidate);
      }
    }
    _schedule(task['batchId']! as String);
    return _project(task);
  }

  Future<FileSnapshot> removeTransfer(String id, {bool batch = false}) async {
    _check();
    final root = _tasks[id];
    final selected = _subtree(
      batch
          ? _tasks.values.where((t) => t['batchId'] == id)
          : root == null
          ? const <FileSnapshot>[]
          : [root],
    );
    final ids = selected.map((t) => t['id']! as String).toSet();
    final batches = selected.map((t) => t['batchId']).toSet();
    if (_tasks.values.any(
      (t) => batches.contains(t['batchId']) && !_terminal(t['status']),
    )) {
      throw const FileFailure('transfer_active', '请先停止整批任务。');
    }
    await _writes;
    await _journal.removeMany(ids.toList());
    for (final taskId in ids) {
      _tasks.remove(taskId);
    }
    for (final batchId in batches) {
      if (!_tasks.values.any((t) => t['batchId'] == batchId)) {
        final lease = _batchLeases[batchId];
        if (lease != null) {
          await cache?.release(lease);
          _batchLeases.remove(batchId);
        }
      }
    }
    return {'removed': true, 'filesRemoved': false, 'removedIds': ids.toList()};
  }

  Future<FileSnapshot> _startFromParams(String command, FileSnapshot params) =>
      startTransfer(
        params['deviceId']! as String,
        command == 'files.push',
        (params['items'] as List? ?? [params]).map((i) {
          final item = Map<String, Object?>.from(i as Map);
          item['source'] ??= item['path'];
          return item;
        }).toList(),
        policy:
            params['conflict'] as String? ??
            params['policy'] as String? ??
            'ask',
        destinationScope: params['destinationScope'] as String? ?? 'localPath',
        shareId: params['shareId'] as String?,
      );
  Future<FileSnapshot> _submitShare(FileSnapshot params, String share) async {
    final leases = publication;
    if (leases == null) {
      throw const FileFailure('share_not_configured', '分享来源租约执行器尚未配置。');
    }
    final previous = await leases.begin(share, params);
    if (previous != null) return {...previous, 'reusedTransfer': true};
    try {
      final receipt = await _startFromParams('files.push', params);
      try {
        await leases.finish(share, receipt);
      } catch (_) {
        receipt['sourceLeaseReconciliationPending'] = true;
      }
      return receipt;
    } catch (error, stack) {
      final unpublished = !_tasks.values.any(
        (task) => task['shareId'] == share,
      );
      try {
        await leases.finish(share, null, definitelyUnpublished: unpublished);
      } catch (_) {
        /* A missing receipt retains the source lease. */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<FileSnapshot> reconcileShares() async {
    await _writes;
    if (publication == null) {
      return {'reconciled': false, 'sourcesRetained': true};
    }
    final groups = <String, List<FileSnapshot>>{};
    for (final task in _tasks.values.where((t) => t['direction'] == 'push')) {
      groups
          .putIfAbsent(
            task['batchId'] as String? ?? task['id']! as String,
            () => [],
          )
          .add(task);
    }
    return publication!.reconcile({
      'complete': true,
      'transfers': groups.entries
          .map(
            (g) => {
              'id': g.key,
              'status': g.value.every((t) => t['status'] == 'completed')
                  ? 'completed'
                  : 'retained',
              'sources': g.value.map((t) => t['source']).toSet().toList(),
            },
          )
          .toList(),
    });
  }

  /// Compatibility at the control boundary only; directory facts and file bytes
  /// arrive from the typed executor, never a JSON file-list or data payload.
  Future<FileSnapshot?> invoke(String command, FileSnapshot params) async {
    final device = params['deviceId'] as String? ?? '';
    switch (command) {
      case 'media.cache.acquire':
        final task = _tasks[params['transferId']];
        if (task == null ||
            task['direction'] != 'pull' ||
            task['destinationScope'] != 'privateCache' ||
            cache == null) {
          throw const FileFailure('invalid_argument', '仅可持有取回到私有缓存的传输。');
        }
        if (_project(task)['cacheEvicted'] == true) {
          throw const FileFailure('cache_evicted', '缓存已清理。');
        }
        return {
          'leaseId': await cache!.reserve([
            FileCacheReservation(task['destination']! as String, 0),
            if (task['temporaryPath'] is String)
              FileCacheReservation(task['temporaryPath']! as String, 0),
          ]),
        };
      case 'files.list':
        return browse(
          device,
          params['path'] as String? ?? '/sdcard',
          filter: params['filter'] as String? ?? 'all',
          sort: params['sort'] as String? ?? 'name',
          descending: params['descending'] == true,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 10000,
        );
      case 'files.search.start':
        return startSearch(
          device,
          params['path']! as String,
          query: params['query']! as String,
          filter: params['filter'] as String? ?? 'all',
        );
      case 'files.search.get':
        return scan(
          device,
          params['searchId']! as String,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 500,
        );
      case 'files.search.cancel':
        return cancelScan(device, params['searchId']! as String);
      case 'media.list':
        final id = params['scanId'] as String?;
        if (id == null || params['refresh'] == true) {
          return startSearch(device, '/sdcard', query: '', gallery: true);
        }
        return scan(
          device,
          id,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 100,
        );
      case 'media.scan.cancel':
        return cancelScan(device, params['scanId']! as String);
      case 'files.push':
      case 'files.pull':
        final share = params['shareId'] as String?;
        if (command == 'files.push' && share != null) {
          return _shareSubmissions.putIfAbsent(
            share,
            () => _submitShare(
              params,
              share,
            ).whenComplete(() => _shareSubmissions.remove(share)),
          );
        }
        return _startFromParams(command, params);
      case 'sharing.reconcile':
        if (publication != null && params['transfers'] == null) {
          return reconcileShares();
        }
        return null;
      case 'transfers.list':
        return transfers();
      case 'transfers.get':
        final task = _tasks[params['transferId']];
        if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
        return transfer(task['id']! as String);
      case 'transfers.cancel':
        if (params['batchId'] is String) {
          return cancelBatch(params['batchId']! as String);
        }
        return cancelTransfer(params['transferId']! as String);
      case 'transfers.resolve':
      case 'transfers.resume':
        return resolveTransfer(
          params['transferId']! as String,
          params['policy'] as String? ??
              params['conflict'] as String? ??
              (_tasks[params['transferId']]?['policy'] as String? ?? 'ask'),
          restart: params['restart'] == true,
          applyToAll: params['applyToAll'] == true,
        );
      case 'transfers.remove':
        return removeTransfer(
          (params['batchId'] ?? params['transferId'])! as String,
          batch: params['batchId'] is String,
        );
      case 'files.mkdir':
      case 'files.rename':
      case 'files.delete':
        final token = FileCancellation();
        final paths = command == 'files.delete'
            ? (params['paths']! as List).cast<String>()
            : [params['path']! as String];
        if (paths.isEmpty || paths.length > 1000) {
          throw const FileFailure('invalid_argument', '文件选择必须为1至1000项。');
        }
        for (final path in paths) {
          await executor.mutate(
            device,
            command.substring(6),
            _remote(path),
            destination:
                params['destination'] as String? ??
                params['newPath'] as String? ??
                (params['name'] is String
                    ? p.posix.join(
                        p.posix.dirname(path),
                        _validName(params['name']! as String),
                      )
                    : ''),
            cancellation: token,
          );
        }
        return {'ok': true};
      default:
        return null;
    }
  }
}

class _Scan {
  _Scan(this.id, this.device, this.root, this.query, this.filter, this.gallery);
  final String id, device, root, query, filter;
  final bool gallery;
  final cancellation = FileCancellation();
  final entries = <FileSnapshot>[], issues = <FileSnapshot>[];
  String status = 'running';
  int visited = 0, visitedDirectories = 0;
  String currentDirectory = '';
  bool limited = false, timedOut = false;
  Future<void> worker = Future.value();
  void issue(String path, String code, String reason) {
    if (issues.length < 128) {
      issues.add({'path': path, 'code': code, 'reason': reason});
    }
  }

  FileSnapshot snapshot({int offset = 0, int limit = 500}) {
    final ready = !gallery || status != 'running';
    final page = ready
        ? entries.skip(offset).take(limit).toList()
        : <FileSnapshot>[];
    final total = ready ? entries.length : 0;
    return {
      'deviceId': device,
      'searchId': id,
      'scanId': id,
      'path': root,
      'query': query,
      'filter': filter,
      'status': gallery && status == 'running'
          ? 'scanning'
          : gallery && status == 'failed'
          ? 'partial'
          : status,
      'complete': status == 'completed',
      'canCancel': status == 'running',
      'visitedEntries': visited,
      'visitedDirectories': visitedDirectories,
      'currentDirectory': currentDirectory,
      'issues': List<FileSnapshot>.of(issues),
      'issueCount': issues.length,
      'results': page,
      'items': page,
      'entries': page,
      'total': total,
      'hasMore': ready && offset + page.length < total,
      'nextOffset': ready && offset + page.length < total
          ? offset + page.length
          : null,
      'offset': offset,
      'limited': limited || timedOut,
      'truncated': limited || timedOut,
      'snapshot': ready,
      'scope': {
        'roots': [root],
        'recognition': 'fileExtension',
        'modifiedSource': 'mtimeUnixSeconds',
        'followsChildSymlinks': false,
        'consistency': 'bestEffortDirectoryMetadata',
        'refresh': 'newIndependentSnapshot',
      },
      'limitation':
          '按名称或扩展名检查；最多30秒、50000项、32层，每目录4096项，不跟随子符号链接；目录变化可能使结果不完整。',
    };
  }
}
