import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/content/models/cache_status.dart';
import 'package:scrcpy_connect/core/files/file_cache_leases.dart';
import 'package:scrcpy_connect/core/files/models/file_cache_reservation.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/file_transfer_journal.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';
import 'package:uuid/uuid.dart';

/// 持有传输任务、日志、来源租约与精确执行回收；目录快照和文件变更各自独立。
class FileTransferService implements FileTransfers {
  FileTransferService._(
    this.executor,
    this._journal,
    this._tasks,
    this.cache,
    this.publication,
  );
  final FileExecutor executor;
  final FileCacheLeases? cache;
  final FilePublicationLeases? publication;
  final _shareSubmissions = <String, _ShareSubmission>{};
  // 同 isolate 重新附着时旧租约持续保护未知结果；冷启动从持久任务重建保护。
  static final _leaseHandoffs =
      <String, List<({FileCacheLeases owner, Map<String, String> leases})>>{};
  String get _directoryKey => p.normalize(_journal.root.absolute.path);
  void _retainCacheLeases() {
    final leases = <String, String>{
      for (final entry in _batchStates.entries) entry.key: ?entry.value.lease,
    };
    if (cache == null || leases.isEmpty) return;
    final previous = _leaseHandoffs[_directoryKey] ?? const [];
    final same = previous
        .where((owner) => identical(owner.owner, cache))
        .firstOrNull;
    _leaseHandoffs[_directoryKey] = [
      for (final owner in previous)
        if (!identical(owner.owner, cache)) owner,
      (owner: cache!, leases: {...?same?.leases, ...leases}),
    ];
  }

  final FileTransferJournal _journal;
  final Map<String, Map<String, Object?>> _tasks;
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  // worker 结算不等于执行资源退出；精确句柄只在 close 确认后撤销。
  final _transferCleanups = <String, _TransferCleanup>{};
  final _batchStates = <String, _TransferBatch>{};
  final _deviceStops = <String, Future<void>>{};
  bool _closed = false;
  bool _closeConfirmed = false;
  Future<void>? _closing;
  int _activeBatches = 0;
  Future<void> _writes = Future.value();
  Stream<Map<String, Object?>> get events => _events.stream;

  static Future<FileTransferService> open({
    required FileExecutor executor,
    required Directory dataDirectory,
    FileCacheLeases? cache,
    FilePublicationLeases? publication,
  }) async {
    final journal = FileTransferJournal(dataDirectory);
    final tasks = await journal.load();
    final owner = FileTransferService._(
      executor,
      journal,
      tasks,
      cache,
      publication,
    );
    final retained = _leaseHandoffs[owner._directoryKey] ?? const [];
    if (retained.isNotEmpty && cache == null) {
      throw const FileFailure('cache_owner_changed', '尚有未确认缓存租约，不能卸除缓存所有者。');
    }
    for (final previous in retained) {
      if (identical(cache, previous.owner)) {
        for (final entry in previous.leases.entries) {
          owner._batchState(entry.key).lease = entry.value;
        }
      }
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
      if (task['cleanupPending'] == true && executor is ScopedFileExecutor) {
        final scope = executor as ScopedFileExecutor;
        if (scope.fileScopeKey.isNotEmpty &&
            scope.fileScopeId.isNotEmpty &&
            task['cleanupScopeKey'] == scope.fileScopeKey &&
            task['cleanupScopeId'] is String &&
            (task['cleanupScopeId']! as String).isNotEmpty &&
            task['cleanupScopeId'] != scope.fileScopeId) {
          // 同一技术域的新句柄已排空前代；这不证明提交结果，仍保持 result_unknown。
          task['cleanupPending'] = false;
          await owner._save(task);
        }
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
        if (owner._batchStates[batch]?.lease != null) continue;
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
        owner._batchState(batch).lease = await cache.reserve(records);
        owner._retainCacheLeases();
      }
      for (final entry in owner._batchStates.entries.toList()) {
        if (!protectedBatches.contains(entry.key) &&
            entry.value.lease != null) {
          await cache.release(entry.value.lease!);
          entry.value.lease = null;
          owner._forgetIdleBatch(entry.key, entry.value);
        }
      }
    }
    // 新所有者先为全部未确认结果建立保护；任何准入失败都会留下旧租约供重试。
    for (final previous in retained) {
      if (!identical(cache, previous.owner)) {
        for (final entry in previous.leases.entries.toList()) {
          await previous.owner.release(entry.value);
          // 成功回执逐项确认；后续释放失败时不会重放已确认释放的租约。
          previous.leases.remove(entry.key);
        }
      }
    }
    _leaseHandoffs.remove(owner._directoryKey);
    return owner;
  }

  void _check() {
    if (_closed) throw const FileFailure('closed', '文件运行时已关闭。');
  }

  _TransferBatch _batchState(String batch, {String? device}) {
    final state = _batchStates.putIfAbsent(batch, _TransferBatch.new);
    state.device ??=
        device ??
        _tasks.values
            .where((task) => (task['batchId'] ?? task['id']) == batch)
            .map((task) => task['deviceId']! as String)
            .firstOrNull;
    return state;
  }

  Future<void> _save(Map<String, Object?> task) {
    final snapshot = Map<String, Object?>.from(task);
    final result = _writes.then((_) => _journal.upsert(snapshot));
    _writes = result;
    return result.then((_) {
      if (!_events.isClosed) {
        _events.add({'type': 'transfers.changed', 'transferId': task['id']});
      }
    });
  }

  void _checkTransferAdmission(String device) {
    _check();
    if (_deviceStops.containsKey(device) ||
        _batchStates.values
            .map((state) => state.preparation)
            .whereType<_TransferPreparation>()
            .any(
              (preparation) =>
                  preparation.device == device &&
                  preparation.cancellation.isCancelled,
            )) {
      throw const FileFailure('transfer_active', '此设备的旧传输正在停止或等待清理。');
    }
  }

  Future<void> cancelDevice(String device) {
    if (_deviceStops[device] case final pending?) return pending;
    final result = Completer<void>();
    _deviceStops[device] = result.future;
    unawaited(
      _cancelDevice(device).then<void>(
        (_) {
          _deviceStops.remove(device);
          result.complete();
        },
        onError: (Object error, StackTrace stack) {
          _deviceStops.remove(device);
          result.completeError(error, stack);
        },
      ),
    );
    return result.future;
  }

  Future<void> _cancelDevice(String device) async {
    // 首次等待前封住新传输，并撤销本设备所有已受理准备。
    // 终态任务可能已从历史移除，worker 的设备归属仍由批次保留到真实收尾。
    final workers = _batchStates.values
        .where((state) => state.device == device)
        .map((state) => state.worker)
        .whereType<Future<void>>()
        .toList();
    final submissions = _shareSubmissions.values
        .where((submission) => submission.device == device)
        .toList();
    for (final submission in submissions) {
      submission.cancellation.cancel();
    }
    final preparing = _batchStates.values
        .map((state) => state.preparation)
        .whereType<_TransferPreparation>()
        .where((p) => p.device == device)
        .toList();
    for (final preparation in preparing) {
      preparation.cancellation.cancel();
    }
    final transfers = _cancelTasks(
      _tasks.values.where((t) => t['deviceId'] == device).toList(),
    );
    final prepared = (() async {
      await Future.wait(preparing.map(_closePreparation));
      await _cancelTasks(
        _tasks.values.where((t) => t['deviceId'] == device).toList(),
      );
    })();
    await Future.wait([
      prepared,
      transfers,
      ...workers,
      ...submissions.map((submission) => submission.finished.future),
    ]);
  }

  Future<void> close() {
    if (_closeConfirmed) return Future.value();
    _closed = true;
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    final submissions = _shareSubmissions.values.toList();
    for (final submission in submissions) {
      submission.cancellation.cancel();
    }
    final preparing = _batchStates.values
        .map((state) => state.preparation)
        .whereType<_TransferPreparation>()
        .toList();
    for (final preparation in preparing) {
      preparation.cancellation.cancel();
    }
    await _stopBatchEdits(
      _tasks.values.toList(),
      (_) async {},
      additionalBatches: _batchStates.keys.toList(),
    );
    await Future.wait(preparing.map(_closePreparation));
    // 准备阶段可能已提交首条日志；排空后再收束迟到登记的未启动任务。
    for (final task in _tasks.values.where((t) => t['status'] == 'queued')) {
      task['status'] = 'cancelled';
      await _save(task);
    }
    for (final state in _batchStates.values) {
      state.activeTask?.cancellation.cancel();
    }
    try {
      await Future.wait([
        ..._batchStates.values
            .map((state) => state.worker)
            .whereType<Future<void>>(),
        ...submissions.map((submission) => submission.finished.future),
      ]);
      await _retryTransferCleanups(_tasks.values, requireRecoverable: false);
      await _writes;
      await _events.close();
      _closeConfirmed = true;
    } finally {
      _retainCacheLeases();
    }
  }

  static bool _terminal(Object? status) => const [
    'completed',
    'skipped',
    'failed',
    'cancelled',
    'interrupted',
  ].contains(status);
  Map<String, Object?> transfers() => {
    'transfers': _tasks.values.map(_project).toList(),
    'batches': _batches().map((batch) => batch.toJson()).toList(),
  };
  ({
    bool canRestart,
    bool canCancel,
    bool canExport,
    bool canExportPartial,
    bool cacheEvicted,
    String? localPath,
    String? partialLocalPath,
  })
  _projection(Map<String, Object?> task) {
    final uncertain =
        task['errorCode'] == 'result_unknown' ||
        task['errorCode'] == 'source_changed' ||
        task['cleanupPending'] == true;
    final lifecycle = _batchStates[task['batchId']];
    final changing =
        lifecycle != null &&
        (lifecycle.edit != null ||
            lifecycle.releasing != null ||
            lifecycle.stopping > 0);
    final canRestart =
        const ['failed', 'cancelled', 'interrupted'].contains(task['status']) &&
        !uncertain &&
        !changing;
    final canCancel =
        !_terminal(task['status']) || task['cleanupPending'] == true;
    final canExport =
        task['direction'] == 'pull' &&
        task['status'] == 'completed' &&
        !uncertain &&
        (task['kind'] == 'file' ||
            task['treeVerified'] == true && task['treeComplete'] == true);
    final canExportPartial =
        task['direction'] == 'pull' &&
        !uncertain &&
        task['kind'] == 'directory' &&
        task['treeVerified'] == true &&
        task['treeComplete'] != true &&
        task['saveMode'] == 'directoryMerge';
    final evicted =
        task['direction'] == 'pull' &&
        task['destinationScope'] == 'privateCache' &&
        _terminal(task['status']) &&
        FileSystemEntity.typeSync(
              task['destination']! as String,
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound;
    return (
      canRestart: canRestart,
      canCancel: canCancel,
      canExport: canExport && !evicted,
      canExportPartial: canExportPartial && !evicted,
      cacheEvicted: evicted,
      localPath: canExport && !evicted ? task['destination'] as String? : null,
      partialLocalPath: canExportPartial && !evicted
          ? task['destination'] as String?
          : null,
    );
  }

  Map<String, Object?> _project(Map<String, Object?> task) {
    final projection = _projection(task);
    return {
      ...task,
      'canResume': false,
      'canRestart': projection.canRestart,
      'restartFromBeginning': true,
      'restartRequiresSourceCheck': true,
      'canCancel': projection.canCancel,
      'canExport': projection.canExport,
      'canExportPartial': projection.canExportPartial,
      'cacheEvicted': projection.cacheEvicted,
      'localPath': ?projection.localPath,
      'partialLocalPath': ?projection.partialLocalPath,
    };
  }

  FileTransferSnapshot _snapshot(Map<String, Object?> task) {
    final projection = _projection(task);
    return FileTransferSnapshot(
      id: task['id']! as String,
      deviceId: task['deviceId'] as String? ?? '',
      batchId: task['batchId'] as String?,
      parentId: task['parentId'] as String?,
      name: task['name'] as String? ?? '文件传输',
      source: task['source'] as String? ?? '',
      destination: task['destination'] as String? ?? '',
      direction: FileTransferDirection.values.byName(
        task['direction']! as String,
      ),
      destinationScope: FileTransferDestination.values.byName(
        task['destinationScope'] as String? ?? 'localPath',
      ),
      kind: FileTransferKind.values.byName(task['kind'] as String? ?? 'file'),
      status: _status(task['status']),
      policy: FileTransferConflict.parse(task['policy'] as String? ?? 'ask'),
      generation: task['generation'] as int? ?? 0,
      itemIndex: task['itemIndex'] as int? ?? 0,
      itemCount: task['itemCount'] as int? ?? 1,
      transferred: task['transferred'] as int? ?? 0,
      total: task['total'] as int?,
      error: task['error'] as String?,
      errorCode: task['errorCode'] as String?,
      saveMode: task['saveMode'] as String?,
      cleanupPending: task['cleanupPending'] == true,
      partialDestinationPossible: task['partialDestinationPossible'] == true,
      treeVerified: task['treeVerified'] == true,
      treeComplete: task['treeComplete'] == true,
      canRestart: projection.canRestart,
      canCancel: projection.canCancel,
      canExport: projection.canExport,
      canExportPartial: projection.canExportPartial,
      cacheEvicted: projection.cacheEvicted,
      localPath: projection.localPath,
      partialLocalPath: projection.partialLocalPath,
    );
  }

  FileTransferStatus _status(Object? value) =>
      FileTransferStatus.values
          .where((status) => status.name == value)
          .firstOrNull ??
      .unknown;

  @override
  Future<FileTransferCollection> readTransfers() async =>
      FileTransferCollection(
        transfers: _tasks.values.map(_snapshot).toList(),
        batches: _batches(),
      );

  @override
  Future<FileTransferSnapshot> readTransfer(String id) async {
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    return _snapshot(task).copyWith(
      items:
          _tasks.values
              .where((item) => item['batchId'] == task['batchId'])
              .map(_snapshot)
              .toList()
            ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex)),
      batch: _batches()
          .where((batch) => batch.batchId == task['batchId'])
          .firstOrNull,
    );
  }

  List<FileTransferBatch> _batches() {
    final groups = <String, List<Map<String, Object?>>>{};
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
      return FileTransferBatch(
        batchId: g.key,
        deviceId: tasks.first['deviceId'] as String? ?? '',
        direction: FileTransferDirection.values.byName(
          tasks.first['direction']! as String,
        ),
        destinationScope: FileTransferDestination.values.byName(
          tasks.first['destinationScope'] as String? ?? 'localPath',
        ),
        status: _status(status),
        itemCount: tasks.length,
        fileCount: tasks.where((t) => t['kind'] == 'file').length,
        directoryCount: tasks.where((t) => t['kind'] == 'directory').length,
        completed: count('completed'),
        failed: count('failed'),
        cancelled: count('cancelled'),
        skipped: count('skipped'),
        interrupted: count('interrupted'),
        transferred: tasks.fold<int>(
          0,
          (n, t) => n + (t['transferred'] as int? ?? 0),
        ),
        total: tasks.fold<int>(0, (n, t) => n + (t['total'] as int? ?? 0)),
        canCancel: active || tasks.any((t) => t['cleanupPending'] == true),
        selectedRootCount: tasks.where((t) => t['parentId'] == null).length,
      );
    }).toList();
  }

  Map<String, Object?> transfer(String id) {
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
          .where((b) => b.batchId == task['batchId'])
          .firstOrNull
          ?.toJson(),
    };
  }

  void _retainExecution(Map<String, Object?> task, Object error) {
    if (error is FileExecutionCleanupFailure) {
      final cleanup = _transferCleanups.putIfAbsent(
        task['id']! as String,
        _TransferCleanup.new,
      );
      cleanup.resources.add(error.execution);
    }
  }

  void _markCleanupPending(Map<String, Object?> task, Object error) {
    task['cleanupPending'] = true;
    task['status'] = 'failed';
    task['errorCode'] = 'result_unknown';
    task['partialDestinationPossible'] = true;
    task['error'] = '$error';
    if (executor case final ScopedFileExecutor scope) {
      task['cleanupScopeKey'] = scope.fileScopeKey;
      task['cleanupScopeId'] = scope.fileScopeId;
    }
  }

  Future<void> _retryTransferCleanups(
    Iterable<Map<String, Object?>> tasks, {
    bool requireRecoverable = true,
  }) async {
    Object? failure;
    StackTrace? failureStack;
    final selected = tasks.toList();
    for (final task in selected) {
      final cleanup = _transferCleanups[task['id']];
      if (cleanup == null) {
        if (requireRecoverable && task['cleanupPending'] == true) {
          failure ??= const FileFailure(
            'result_unknown',
            '上次执行的清理回执未知；当前所有者没有原句柄，不能确认取消成功。',
          );
          failureStack ??= StackTrace.current;
        }
        continue;
      }
      try {
        await (cleanup.closing ??= _retryTransferCleanup(
          task,
          cleanup,
        ).whenComplete(() => cleanup.closing = null));
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    for (final batch in selected.map((t) => t['batchId']! as String).toSet()) {
      await _releaseBatchLeaseIfSafe(batch);
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _retryTransferCleanup(
    Map<String, Object?> task,
    _TransferCleanup cleanup,
  ) async {
    Object? failure;
    for (final resource in cleanup.resources.toList()) {
      try {
        await resource.close();
        cleanup.resources.remove(resource);
      } catch (error) {
        failure ??= error;
      }
    }
    // 原 reader 可能仍写入片段，不能抢先释放 part 或按路径删除。
    if ((failure, cleanup.partPath) case (null, final String path)) {
      try {
        await executor.mutate(
          task['deviceId']! as String,
          'releasePart',
          path,
          local: true,
          cancellation: FileCancellation(),
        );
        cleanup.partPath = null;
      } catch (error) {
        _retainExecution(task, error);
        failure = error;
      }
    }
    if (failure != null) {
      _markCleanupPending(
        task,
        cleanup.executionFailure == null
            ? failure
            : (execution: cleanup.executionFailure, cleanup: failure),
      );
      await _save(task);
      throw FileFailure('file_cleanup_unconfirmed', '原传输资源尚未确认释放：$failure');
    }
    // 只恢复当时已经明确的结果；提交回执未知不会因 close 成功变为取消成功。
    task.addAll(cleanup.outcome!);
    task['cleanupPending'] = false;
    await _save(task);
    _transferCleanups.remove(task['id']);
  }

  Future<void> _releaseBatchLeaseIfSafe(String batch) async {
    final previous = _batchStates[batch];
    if (previous?.edit != null) return;
    if (previous?.releasing case final pending?) {
      await pending;
      return;
    }
    final tasks = _tasks.values.where((t) => t['batchId'] == batch);
    if (tasks.every(
      (t) =>
          _terminal(t['status']) &&
          t['cleanupPending'] != true &&
          !_transferCleanups.containsKey(t['id']) &&
          t['partialDestinationPossible'] != true &&
          t['errorCode'] != 'result_unknown',
    )) {
      final lease = previous?.lease;
      if (lease != null) {
        final lifecycle = _batchState(batch);
        // 释放旧预算同样占用准入，不能在 await 期间被重启复用。
        final result = (() async {
          await cache!.release(lease);
          if (lifecycle.lease == lease) lifecycle.lease = null;
        })();
        final releasing = result.whenComplete(() {
          lifecycle.releasing = null;
          _forgetIdleBatch(batch, lifecycle);
        });
        lifecycle.releasing = releasing;
        await releasing;
      }
    }
  }

  Future<void> _releasePreparationLease(_TransferPreparation preparation) {
    return preparation.releasing ??=
        (() async {
          final lease = preparation.lease;
          if (lease == null) return;
          try {
            await cache!.release(lease);
          } catch (error) {
            throw FileFailure(
              'file_cleanup_unconfirmed',
              '首次批次预算尚未确认释放：$error',
            );
          }
          preparation.lease = null;
        })().whenComplete(() {
          preparation.releasing = null;
        });
  }

  Future<void> _closePreparation(_TransferPreparation preparation) async {
    preparation.cancellation.cancel();
    await preparation.finished.future;
    await _releasePreparationLease(preparation);
    final state = _batchStates[preparation.batch];
    if (identical(state?.preparation, preparation)) {
      state!.preparation = null;
      _forgetIdleBatch(preparation.batch, state);
    }
  }

  _BatchEdit _beginBatchEdit(String batch, _BatchEditKind kind) {
    _check();
    final lifecycle = _batchState(batch);
    if (lifecycle.stopping > 0 ||
        lifecycle.edit != null ||
        lifecycle.releasing != null) {
      throw const FileFailure('transfer_active', '此批次正在变更或清理，请等待其完成。');
    }
    final edit = _BatchEdit(kind);
    lifecycle.edit = edit;
    return edit;
  }

  Map<String, _BatchEdit> _beginBatchEdits(
    Set<String> batches,
    _BatchEditKind kind,
  ) {
    _check();
    // 先检查全部受影响批次，再同步取得准入，不能留下部分已占用的子树。
    for (final batch in batches) {
      final lifecycle = _batchStates[batch];
      if (lifecycle != null &&
          (lifecycle.stopping > 0 ||
              lifecycle.edit != null ||
              lifecycle.releasing != null)) {
        throw const FileFailure('transfer_active', '此批次正在变更或清理，请等待其完成。');
      }
    }
    return {for (final batch in batches) batch: _beginBatchEdit(batch, kind)};
  }

  Future<void> _releaseEditLease(String batch, _BatchEdit edit) {
    return edit.releasing ??=
        (() async {
          if (edit.lease case final lease?) {
            try {
              await cache!.release(lease);
            } catch (error) {
              throw FileFailure(
                'file_cleanup_unconfirmed',
                '批次准入预算尚未确认释放：$error',
              );
            }
            final state = _batchStates[batch];
            if (state?.lease == lease) state!.lease = null;
            edit.lease = null;
          }
        })().whenComplete(() {
          edit.releasing = null;
        });
  }

  void _forgetBatchEdit(String batch, _BatchEdit edit) {
    final lifecycle = _batchStates[batch];
    if (identical(lifecycle?.edit, edit)) lifecycle!.edit = null;
    if (lifecycle != null) _forgetIdleBatch(batch, lifecycle);
  }

  void _forgetIdleBatch(String batch, _TransferBatch state) {
    if (state.isIdle && identical(_batchStates[batch], state)) {
      _batchStates.remove(batch);
    }
  }

  Future<void> _endBatchEdit(String batch, _BatchEdit edit) async {
    try {
      await _releaseEditLease(batch, edit);
      _forgetBatchEdit(batch, edit);
    } finally {
      // 完成只表示原异步操作已交接；清理失败时 edit 及精确 lease 仍登记着。
      edit.finished.complete();
    }
  }

  Future<void> _stopBatchEdits(
    List<Map<String, Object?>> tasks,
    Future<void> Function(List<Map<String, Object?>>) action, {
    Iterable<String> additionalBatches = const [],
  }) async {
    final batches = tasks.map((task) => task['batchId']! as String).toSet()
      ..addAll(additionalBatches);
    final held = <String, _TransferBatch>{};
    for (final batch in batches) {
      final lifecycle = _batchState(batch);
      lifecycle.stopping++;
      held[batch] = lifecycle;
      if (lifecycle.edit?.kind == _BatchEditKind.restart) {
        lifecycle.edit!.cancellation.cancel();
      }
    }
    try {
      Object? failure;
      StackTrace? failureStack;
      for (final entry in held.entries) {
        final edit = entry.value.edit;
        final releasing = entry.value.releasing;
        try {
          if (edit != null) {
            await edit.finished.future;
            await _releaseEditLease(entry.key, edit);
            _forgetBatchEdit(entry.key, edit);
          }
          await releasing;
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      // 删除可能已在原编辑中确认，不能拿脱离任务表的旧 Map 再追加日志。
      await action(
        tasks.where((task) => identical(_tasks[task['id']], task)).toList(),
      );
    } finally {
      for (final entry in held.entries) {
        entry.value.stopping--;
        _forgetIdleBatch(entry.key, entry.value);
      }
    }
  }

  Future<void> _cancelTasks(List<Map<String, Object?>> tasks) =>
      _stopBatchEdits(tasks, _cancelSettledTasks);

  Future<void> _cancelSettledTasks(List<Map<String, Object?>> tasks) async {
    final active = tasks.where((t) => !_terminal(t['status'])).toList();
    for (final task in active) {
      final running = _batchStates[task['batchId']]?.activeTask;
      final token = running?.taskId == task['id']
          ? running?.cancellation
          : null;
      task['status'] = token == null ? 'cancelled' : 'cancelling';
      token?.cancel();
    }
    for (final task in active) {
      await _save(task);
    }
    // 任务终态不代表 worker 的来源核验收尾完成，停止仍须等待原批次。
    final batches = tasks.map((t) => t['batchId']).toSet();
    await Future.wait(
      batches.map((b) => _batchStates[b]?.worker).whereType<Future<void>>(),
    );
    await _retryTransferCleanups(tasks);
    for (final task in active.where((t) => t['status'] == 'cancelling')) {
      task['status'] = 'cancelled';
      if (task['saveMode'] == 'committing') {
        task['errorCode'] = 'result_unknown';
        task['partialDestinationPossible'] = true;
      }
      await _save(task);
    }
  }

  Future<void> _cancelBatch(String batch) async {
    final tasks = _tasks.values.where((t) => t['batchId'] == batch).toList();
    if (tasks.isEmpty) throw const FileFailure('not_found', '批任务不存在。');
    await _cancelTasks(tasks);
  }

  /// 暂存呈现只读取现有任务，不改变其进度、授权或保护寿命。
  List<CacheProtection> get cacheSources => [
    for (final task in _tasks.values)
      if (task['direction'] == 'pull' &&
          task['destinationScope'] == 'privateCache')
        CacheProtection(
          path: task['destination'] as String,
          name: task['name'] as String?,
          sourceLabel: task['deviceId'] as String?,
          sourcePath: task['source'] as String?,
          transferId: task['id'] as String?,
          canExport: _project(task)['canExport'] == true,
          reason:
              task['errorCode'] == 'result_unknown' ||
                  task['partialDestinationPossible'] == true
              ? '原件取回结果待核对'
              : '预览、传输或准备仍在使用',
        ),
  ];

  @override
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  }) async {
    return shareId != null && plan.direction == FileTransferDirection.push
        ? _submitSharePlan(plan, shareId: shareId)
        : _startTransfer(plan, shareId: shareId);
  }

  Future<FileTransferSubmission> _startTransfer(
    FileTransferPlan plan, {
    String? shareId,
    String? publicationBatchId,
  }) async {
    final device = plan.deviceId;
    final push = plan.direction == FileTransferDirection.push;
    final selections = plan.items.map((item) => item.toJson()).toList();
    final policy = plan.conflict.name;
    final destinationScope = plan.destination.name;
    _checkTransferAdmission(device);
    if (selections.isEmpty || selections.length > 1000) {
      throw const FileFailure('invalid_argument', '传输选择或冲突策略无效。');
    }
    if (plan.destination == FileTransferDestination.privateCache &&
        cache == null) {
      throw const FileFailure('cache_unavailable', '私有缓存执行器尚未配置。');
    }
    if (publicationBatchId != null &&
        (shareId == null ||
            _batchStates.containsKey(publicationBatchId) ||
            _tasks.values.any(
              (task) => task['batchId'] == publicationBatchId,
            ))) {
      throw const FileFailure('invalid_argument', '发布必须使用尚未创建的独立批次。');
    }
    final batch = publicationBatchId ?? const Uuid().v4(),
        token = FileCancellation();
    final pending =
        Queue<
          ({String source, String destination, String? parent, int depth})
        >();
    final selected = <Map<String, Object?>>[];
    final destinations = <String>{};
    var pathBytes = 0;
    void enqueue(String source, String destination, String? parent, int depth) {
      final bytes =
          utf8.encode(source).length + utf8.encode(destination).length;
      if (selected.length + pending.length >= 10000 ||
          depth > 64 ||
          bytes > 16 * 1024 * 1024 - pathBytes) {
        throw const FileFailure('tree_limit', '选择超过10000项、64层或16MiB路径上限。');
      }
      if (!destinations.add(destination)) {
        throw const FileFailure('duplicate_destination', '任务不能重复写入同一目标。');
      }
      pathBytes += bytes;
      pending.add((
        source: source,
        destination: destination,
        parent: parent,
        depth: depth,
      ));
    }

    for (final item in selections) {
      final source = item['source']! as String,
          destination = item['destination']! as String;
      if (push) {
        if (!p.isAbsolute(source)) {
          throw const FileFailure('invalid_path', '源必须为本机绝对路径。');
        }
        FilePaths.remote(destination);
      } else {
        FilePaths.remote(source);
        if (!p.isAbsolute(destination)) {
          throw const FileFailure('invalid_path', '目标必须为本机绝对路径。');
        }
      }
      enqueue(source, destination, null, 0);
    }
    final timer = Timer(const Duration(seconds: 120), token.cancel);
    final preparation = _TransferPreparation(batch, device, token);
    final state = _batchState(batch, device: device);
    state.preparation = preparation;
    try {
      // Source lookup is admitted preparation too: stop/close must cancel it
      // and await its actual exit before allowing a successor connection.
      if (push &&
          shareId == null &&
          publication is ManagedFilePublicationLeases) {
        final owner = await (publication! as ManagedFilePublicationLeases)
            .ownerForSources(
              selections.map((item) => item['source']! as String).toList(),
            );
        token.check();
        _check();
        if (owner != null) {
          timer.cancel();
          return await _submitSharePlan(plan, shareId: owner);
        }
      }
      while (pending.isNotEmpty) {
        token.check();
        final (:source, :destination, :parent, :depth) = pending.removeFirst();
        final stamp = await executor.stat(
          device,
          source,
          local: push,
          followStorageAlias: !push && parent == null,
          cancellation: token,
        );
        final id = const Uuid().v4();
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
          final remaining = 10000 - selected.length - pending.length;
          final children = await executor.list(
            device,
            source,
            local: push,
            // At capacity one entry distinguishes an empty directory from an
            // overflowing tree without an unbounded enumeration.
            limit: max(1, remaining),
            cancellation: token,
          );
          if (children.truncated || children.entries.length > remaining) {
            throw const FileFailure('tree_limit', '选中目录超过条目上限。');
          }
          for (final child in children.entries) {
            final name = child.pathName;
            if (name == null || child.error != null) {
              throw child.error ??
                  const FileFailure('invalid_filename', '目录包含无法安全表示的文件名。');
            }
            enqueue(
              push ? p.join(source, name) : p.posix.join(source, name),
              push
                  ? p.posix.join(destination, name)
                  : p.join(destination, name),
              id,
              depth + 1,
            );
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
        token.check();
        _check();
        final lease = await cache!.reserve(reservations);
        preparation.lease = lease;
        token.check();
        _check();
        state.lease = lease;
      }
      token.check();
      _check();
      // 首个日志提交后可能结果未知，预算转交批次，不能再按未发布释放。
      preparation.lease = null;
      for (final task in selected) {
        task['itemCount'] = selected.length;
        _tasks[task['id']! as String] = task;
        await _save(task);
      }
    } finally {
      timer.cancel();
      try {
        await _releasePreparationLease(preparation);
        state.preparation = null;
        _forgetIdleBatch(batch, state);
      } finally {
        preparation.finished.complete();
      }
    }
    token.check();
    _check();
    _schedule(batch);
    return FileTransferSubmission(
      batchId: batch,
      transferId: selected.first['id'] as String,
      status: FileTransferAdmission.queued,
      itemCount: selected.length,
    );
  }

  void _schedule(String batch) {
    if (_closed) return;
    final state = _batchState(batch);
    if (state.worker != null) return;
    final job = Future<void>(() => _runBatch(batch, state));
    state.worker = job;
    unawaited(
      job.then<void>(
        (_) {
          state.worker = null;
          if (!_closed &&
              _tasks.values.any(
                (t) => t['batchId'] == batch && t['status'] == 'queued',
              ) &&
              !_tasks.values.any(
                (t) => t['batchId'] == batch && t['status'] == 'conflict',
              )) {
            _schedule(batch);
          }
          _forgetIdleBatch(batch, state);
        },
        onError: (Object error, StackTrace stack) {
          state.worker = null;
          _forgetIdleBatch(batch, state);
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

  Future<void> _runBatch(String batch, _TransferBatch state) async {
    // 每个批次内顺序执行，全局最多并发两个批次。
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
        state.activeTask = (taskId: task['id']! as String, cancellation: token);
        try {
          await _runTask(task, token);
        } on FileFailure catch (e) {
          _retainExecution(task, e);
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
          _retainFailedTaskOutcome(task, token);
          await _save(task);
        } catch (e) {
          task['status'] = 'failed';
          task['errorCode'] = task['saveMode'] == 'committing'
              ? 'result_unknown'
              : 'transfer_failed';
          task['partialDestinationPossible'] =
              task['errorCode'] == 'result_unknown';
          task['error'] = '$e';
          _retainFailedTaskOutcome(task, token);
          await _save(task);
        } finally {
          state.activeTask = null;
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
      await _releaseBatchLeaseIfSafe(batch);
      try {
        await reconcileShares();
      } catch (_) {
        /* 无法取得持久证明时继续保留源。 */
      }
    }
  }

  Map<String, Object?> _taskOutcome(Map<String, Object?> task) => {
    'status': task['status'],
    'errorCode': task['errorCode'],
    'error': task['error'],
    'partialDestinationPossible': task['partialDestinationPossible'],
  };

  void _retainFailedTaskOutcome(
    Map<String, Object?> task,
    FileCancellation cancellation,
  ) {
    final cleanup = _transferCleanups[task['id']];
    if (cleanup == null) return;
    if (cleanup.outcome == null) {
      // 提交前取消且原资源真正排空后，可以确认取消；提交阶段继续保留未知结果。
      if (cancellation.isCancelled && task['saveMode'] != 'committing') {
        cleanup.outcome = {
          'status': 'cancelled',
          'errorCode': 'cancelled',
          'error': '文件任务已取消。',
          'partialDestinationPossible': false,
        };
      } else {
        cleanup.outcome = _taskOutcome(task);
        if (cleanup.executionFailure case final FileFailure original) {
          final unknown =
              task['saveMode'] == 'committing' ||
              original.code == 'result_unknown';
          cleanup.outcome!.addAll({
            'status': original.code == 'cancelled' ? 'cancelled' : 'failed',
            'errorCode': unknown ? 'result_unknown' : original.code,
            'error': original.message,
            'partialDestinationPossible': unknown,
          });
        }
      }
    }
    _markCleanupPending(task, task['error'] ?? '文件执行资源尚未确认释放。');
  }

  Future<FileStamp?> _destination(
    Map<String, Object?> task,
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

  Future<void> _runTask(
    Map<String, Object?> task,
    FileCancellation token,
  ) async {
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
    Object? executionFailure;
    var committed = false;
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
      committed = true;
    } catch (error) {
      executionFailure = error;
      _retainExecution(task, error);
      _transferCleanups[task['id']]?.executionFailure = error;
      rethrow;
    } finally {
      if (!push) {
        final retained = _transferCleanups[task['id']];
        if (retained != null) {
          retained.partPath = temporary;
        } else {
          try {
            await executor.mutate(
              device,
              'releasePart',
              temporary,
              local: true,
              cancellation: FileCancellation(),
            );
          } catch (error) {
            _retainExecution(task, error);
            final cleanup = _transferCleanups.putIfAbsent(
              task['id']! as String,
              _TransferCleanup.new,
            );
            cleanup.partPath = temporary;
            cleanup.executionFailure = executionFailure;
            if (committed) {
              cleanup.outcome = {
                'status': 'completed',
                'temporaryPath': null,
                'errorCode': null,
                'error': null,
                'partialDestinationPossible': false,
              };
            }
            throw FileFailure(
              'file_cleanup_unconfirmed',
              '${executionFailure == null ? '' : '执行失败：$executionFailure；'}清理失败：$error',
            );
          }
        }
      }
    }
    task['status'] = 'completed';
    task['temporaryPath'] = null;
    await _save(task);
  }

  static Map<String, List<Map<String, Object?>>> _children(
    Iterable<Map<String, Object?>> tasks,
  ) {
    final children = <String, List<Map<String, Object?>>>{};
    for (final task in tasks) {
      final parent = task['parentId'];
      if (parent is String) children.putIfAbsent(parent, () => []).add(task);
    }
    return children;
  }

  List<Map<String, Object?>> _subtree(Iterable<Map<String, Object?>> roots) {
    final children = _children(_tasks.values);
    final pending = Queue<Map<String, Object?>>()..addAll(roots);
    final selected = <Map<String, Object?>>[];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final task = pending.removeFirst();
      if (!seen.add(task['id']! as String)) continue;
      selected.add(task);
      pending.addAll(children[task['id']] ?? const []);
    }
    return selected;
  }

  @override
  Future<void> cancelTransfer(FileTransferTarget target) => switch (target) {
    FileTransferTaskTarget(:final id) => _cancelTask(id),
    FileTransferBatchTarget(:final id) => _cancelBatch(id),
  };

  Future<void> _cancelTask(String id) async {
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    await _cancelTasks(_subtree([task]));
  }

  @override
  Future<FileTransferSnapshot> resolveConflict(
    String id,
    FileTransferConflict policy, {
    bool applyToAll = false,
  }) => _resolveTransfer(id, policy: policy, applyToAll: applyToAll);

  @override
  Future<FileTransferSnapshot> restartTransfer(
    String id, {
    FileTransferConflict? policy,
    bool applyToAll = false,
  }) => _resolveTransfer(
    id,
    policy: policy,
    restart: true,
    applyToAll: applyToAll,
  );

  Future<FileTransferSnapshot> _resolveTransfer(
    String id, {
    FileTransferConflict? policy,
    bool restart = false,
    bool applyToAll = false,
  }) async {
    _check();
    final task = _tasks[id];
    if (task == null) throw const FileFailure('not_found', '传输任务不存在。');
    _checkTransferAdmission(task['deviceId']! as String);
    if (task['cleanupPending'] == true) {
      throw const FileFailure('restart_unavailable', '原传输资源尚未确认释放，不能重放任务。');
    }
    if (task['status'] != 'conflict' &&
        (!restart || !_projection(task).canRestart)) {
      throw const FileFailure('restart_unavailable', '此任务不能安全重试，请核对结果或重新选择。');
    }
    final selectedPolicy =
        policy ??
        FileTransferConflict.parse(task['policy'] as String? ?? 'ask');
    final batch = task['batchId']! as String;
    final edit = _beginBatchEdit(batch, _BatchEditKind.restart);
    try {
      if (task['direction'] == 'pull' &&
          task['destinationScope'] == 'privateCache' &&
          _batchStates[batch]?.lease == null) {
        final next = (task['generation'] as int? ?? 0) + 1;
        final lease = await cache!.reserve([
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
        edit.lease = lease;
        _batchStates[batch]!.lease = lease;
      }
      edit.cancellation.check();
      _check();
      task['policy'] = selectedPolicy.name;
      task['generation'] = (task['generation'] as int? ?? 0) + 1;
      task['status'] = 'queued';
      task['error'] = null;
      task['errorCode'] = null;
      task['transferred'] = 0;
      // 排队状态开始提交后，预算归持久批次保护，不再属于可撤回的准备阶段。
      edit.lease = null;
      await _save(task);
      edit.cancellation.check();
      _check();
      if (applyToAll) {
        for (final candidate in _tasks.values.where(
          (t) => t['batchId'] == task['batchId'] && t['status'] == 'queued',
        )) {
          candidate['policy'] = selectedPolicy.name;
          await _save(candidate);
        }
      }
      edit.cancellation.check();
      _check();
      _schedule(task['batchId']! as String);
      return _snapshot(task);
    } finally {
      await _endBatchEdit(batch, edit);
    }
  }

  @override
  Future<List<String>> removeTransfer(FileTransferTarget target) async {
    _check();
    final (id: id, :batch) = switch (target) {
      FileTransferTaskTarget(:final id) => (id: id, batch: false),
      FileTransferBatchTarget(:final id) => (id: id, batch: true),
    };
    final root = _tasks[id];
    final selected = _subtree(
      batch
          ? _tasks.values.where((t) => t['batchId'] == id)
          : root == null
          ? const <Map<String, Object?>>[]
          : [root],
    );
    final ids = selected.map((t) => t['id']! as String).toSet();
    final batches = selected.map((t) => t['batchId']! as String).toSet();
    final edits = _beginBatchEdits(batches, _BatchEditKind.remove);
    try {
      if (_tasks.values.any(
        (t) =>
            batches.contains(t['batchId']) &&
            (t['cleanupPending'] == true ||
                _transferCleanups.containsKey(t['id'])),
      )) {
        throw const FileFailure(
          'file_cleanup_unconfirmed',
          '原传输资源尚未确认释放，不能移除任务。',
        );
      }
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
          final lease = _batchStates[batchId]?.lease;
          if (lease != null) {
            final edit = edits[batchId]!;
            edit.lease = lease;
            await _releaseEditLease(batchId, edit);
          }
        }
      }
      return List.unmodifiable(ids);
    } finally {
      Object? failure;
      StackTrace? failureStack;
      for (final entry in edits.entries) {
        try {
          await _endBatchEdit(entry.key, entry.value);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  /// 同一分享只提交一次；持久指纹从实际执行计划生成。
  Future<FileTransferSubmission> _submitSharePlan(
    FileTransferPlan plan, {
    required String shareId,
  }) {
    final device = plan.deviceId;
    _checkTransferAdmission(device);
    if (plan.direction != FileTransferDirection.push) {
      throw const FileFailure('invalid_argument', '分享来源只能发送到设备。');
    }
    final previous = _shareSubmissions[shareId];
    if (previous != null) {
      if (!previous.matches(plan)) {
        throw const FileFailure('share_submission_mismatch', '本次分享已经使用其他传输参数。');
      }
      return previous.result.future;
    }
    final submission = _ShareSubmission(plan);
    // 来源租约尚未返回也属于本设备的准备责任，先登记再调用外部所有者。
    _shareSubmissions[shareId] = submission;
    unawaited(() async {
      try {
        submission.result.complete(
          await _publishShare(
            plan,
            shareId: shareId,
            cancellation: submission.cancellation,
          ),
        );
      } catch (error, stack) {
        submission.result.completeError(error, stack);
      } finally {
        _shareSubmissions.remove(shareId);
        submission.finished.complete();
      }
    }());
    return submission.result.future;
  }

  Future<FileTransferSubmission> _publishShare(
    FileTransferPlan plan, {
    required String shareId,
    required FileCancellation cancellation,
  }) async {
    final leases = publication;
    if (leases == null) {
      throw const FileFailure('share_not_configured', '分享来源租约执行器尚未配置。');
    }
    final batch = const Uuid().v4();
    final previous = await leases.begin(shareId, plan, transferId: batch);
    if (previous != null) {
      return FileTransferSubmission(
        batchId: previous.batchId,
        transferId: previous.transferId,
        itemCount:
            previous.itemCount ??
            _tasks.values
                .where((task) => task['batchId'] == previous.batchId)
                .length,
        status: previous.status,
        reusedTransfer: true,
      );
    }
    try {
      // 停止可能发生在来源登记等待期间；迟到租约只能收尾，不能创建新传输。
      cancellation.check();
      final receipt = await _startTransfer(
        plan,
        shareId: shareId,
        publicationBatchId: batch,
      );
      try {
        await leases.finish(
          shareId,
          FilePublicationOutcome.published(
            FilePublicationReceipt.fromSubmission(receipt),
          ),
        );
      } catch (_) {
        return receipt.copyWith(sourceLeaseReconciliationPending: true);
      }
      return receipt;
    } catch (error, stack) {
      final unpublished = !_tasks.values.any(
        (task) => task['batchId'] == batch,
      );
      try {
        await leases.finish(
          shareId,
          unpublished
              ? const FilePublicationOutcome.unpublished()
              : const FilePublicationOutcome.unknown(),
        );
      } catch (_) {
        // 回执缺失时保留源租约。
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// 保护受管取回内容及未发布片段；租约由实际消费者显式释放。
  Future<String> acquireCacheLease(String transferId) async {
    _check();
    final task = _tasks[transferId];
    if (task == null ||
        task['direction'] != 'pull' ||
        task['destinationScope'] != 'privateCache' ||
        cache == null) {
      throw const FileFailure('invalid_argument', '仅可持有取回到私有缓存的传输。');
    }
    if (_project(task)['cacheEvicted'] == true) {
      throw const FileFailure('cache_evicted', '缓存已清理。');
    }
    return cache!.reserve([
      FileCacheReservation(task['destination']! as String, 0),
      if (task['temporaryPath'] is String)
        FileCacheReservation(task['temporaryPath']! as String, 0),
    ]);
  }

  Future<FilePublicationReconciliation> reconcileShares() async {
    final sources = publication;
    if (sources == null) {
      return const FilePublicationReconciliation(
        reconciled: false,
        snapshotComplete: false,
        reason: FilePublicationReconciliationReason.notConfigured,
      );
    }
    final paths = await sources.sourcePaths;
    // Await the current tail again if another task queued a commit while the
    // previous tail was flushing. Runtime completion alone is not durable proof.
    while (true) {
      final pending = _writes;
      await pending;
      if (identical(pending, _writes)) break;
    }
    Set<String> rootsFor(Object? source) => source is! String
        ? {}
        : {
            for (final root in paths)
              if (p.equals(root, source) || p.isWithin(root, source)) root,
          };
    // Directory owners cover every descendant, including independently selected
    // children. All consumers still contribute their whole batch status.
    // Unrelated history does not spend the source owner's bounded proof budget.
    final batches = _tasks.values
        .where(
          (task) =>
              task['direction'] == 'push' &&
              rootsFor(task['source']).isNotEmpty,
        )
        .map((task) => task['batchId'] as String? ?? task['id']! as String)
        .toSet();
    final groups = <String, List<Map<String, Object?>>>{};
    for (final task in _tasks.values.where((t) => t['direction'] == 'push')) {
      final batch = task['batchId'] as String? ?? task['id']! as String;
      if (!batches.contains(batch)) continue;
      groups.putIfAbsent(batch, () => []).add(task);
    }
    return sources.reconcile(
      DurableFilePublications(
        complete: true,
        coveredSources: paths,
        transfers: [
          for (final group in groups.entries)
            DurableFilePublication(
              batchId: group.key,
              completed: group.value.every(
                (task) => task['status'] == 'completed',
              ),
              sources: group.value
                  .expand((task) => rootsFor(task['source']))
                  .toSet(),
            ),
        ],
      ),
    );
  }
}

/// 仅当前 isolate 的精确清理权；持久日志只保存未知事实，不序列化资源句柄。
final class _TransferCleanup {
  final resources = Set<FileExecutionResource>.identity();
  String? partPath;
  Map<String, Object?>? outcome;
  Object? executionFailure;
  Future<void>? closing;
}

/// 同一批次的准备、worker、当前执行、缓存租约与变更准入共用唯一登记。
final class _TransferBatch {
  String? device;
  _TransferPreparation? preparation;
  Future<void>? worker;
  ({String taskId, FileCancellation cancellation})? activeTask;
  String? lease;
  _BatchEdit? edit;
  Future<void>? releasing;
  int stopping = 0;

  bool get isIdle =>
      preparation == null &&
      worker == null &&
      activeTask == null &&
      lease == null &&
      edit == null &&
      releasing == null &&
      stopping == 0;
}

enum _BatchEditKind { restart, remove }

/// reserve 的迟到租约在交给批次前由本对象持有，清理失败后不能撤销登记。
final class _BatchEdit {
  _BatchEdit(this.kind);
  final _BatchEditKind kind;
  final cancellation = FileCancellation();
  final finished = Completer<void>();
  String? lease;
  Future<void>? releasing;
}

/// 首次批次规划在日志接管前持有迟到预算，失败时保留同一精确租约。
final class _TransferPreparation {
  _TransferPreparation(this.batch, this.device, this.cancellation);
  final String batch;
  final String device;
  final FileCancellation cancellation;
  final finished = Completer<void>();
  String? lease;
  Future<void>? releasing;
}

/// 分享来源交接在普通传输准备前开始，停止必须等待其真实结算。
final class _ShareSubmission {
  _ShareSubmission(this.plan);
  final FileTransferPlan plan;
  String get device => plan.deviceId;
  bool matches(FileTransferPlan other) =>
      plan.deviceId == other.deviceId &&
      plan.direction == other.direction &&
      plan.conflict == other.conflict &&
      plan.destination == other.destination &&
      plan.items.length == other.items.length &&
      Iterable<int>.generate(plan.items.length).every(
        (index) =>
            plan.items[index].source == other.items[index].source &&
            plan.items[index].destination == other.items[index].destination,
      );
  final cancellation = FileCancellation();
  final result = Completer<FileTransferSubmission>();
  final finished = Completer<void>();
}
