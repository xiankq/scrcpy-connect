import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/services/file_publication_leases.dart';
import 'package:scrcpy_connect/services/file_share_owner.dart';
import 'package:scrcpy_connect/models/shared_source_file.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/services/file_share_recovery.dart';
import 'package:scrcpy_connect/services/file_share_ledger.dart';

export 'package:scrcpy_connect/models/share_limits.dart';

/// 分享来源只有这一个持久所有者；平台借出授权，SDK 持有复制件，应用决定发布和回收。
final class FileShareService implements FilePublicationLeases {
  FileShareService._(this._files, this._platform, this.limits, this._emit);
  final Future<LocalFiles> Function() _files;
  final SharePlatformRequest _platform;
  final ShareLimits limits;
  final void Function(Map<String, dynamic>)? _emit;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _jobs = <String, _ImportJob>{};
  final _intents = <String, _ImportIntent>{};
  final _stoppingShares = <String>{};
  Future<void> _tail = Future<void>.value();
  Future<void>? _configuring, _closing;
  FileShareOwner? _owner;
  FileShareLedger? _store;
  bool _closed = false;
  bool _intakeStopped = false;

  static Future<FileShareService> open({
    required Future<LocalFiles> Function() files,
    required SharePlatformRequest platform,
    ShareLimits limits = const ShareLimits(),
    void Function(Map<String, dynamic>)? emit,
  }) async {
    final owner = FileShareService._(files, platform, limits, emit);
    await owner.configure();
    return owner;
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  void _checkOpen() {
    if (_closed) throw const FileFailure('cancelled', '分享来源服务已关闭。');
  }

  void _checkIntake() {
    _checkOpen();
    if (_intakeStopped) throw const FileFailure('cancelled', '分享导入已停止准入。');
  }

  /// 同步撤销新来源准入；发布/核对仍可供正在收尾的传输使用，直到 close。
  void stopIntake() {
    _intakeStopped = true;
    for (final intent in _intents.values) {
      intent.cancellation.cancel();
      if (!intent.started && !intent.result.isCompleted) {
        intent.result.completeError(const FileFailure('cancelled', '分享导入已取消。'));
      }
    }
    for (final id in _jobs.keys.toList()) {
      _jobs[id]!.cancellation.cancel();
      unawaited(_cancelAndDrain(id).catchError((Object _) {}));
    }
  }

  void _changed(Map<String, dynamic> event) {
    if (!_events.isClosed) _events.add(event);
    if (!_closed) _emit?.call(event);
  }

  Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      return await _platform(
        command,
        params,
      ).timeout(const Duration(seconds: 120));
    } on TimeoutException {
      // 平台仍持有未确认资源；超时只结束等待，不撤销精确重试责任。
      throw const FileFailure('share_cleanup_unconfirmed', '分享平台尚未确认本次操作，请重试。');
    }
  }

  Future<void> configure() {
    _checkOpen();
    return _configuring ??= Future<void>.microtask(_prepareConfiguration)
        .whenComplete(() {
          _configuring = null;
        });
  }

  Future<void> _prepareConfiguration() async {
    if (_store != null) {
      final environment = await _request(
        'sharing.platform.environment',
        const {},
      );
      if (_needsRecovery(environment)) {
        // 换 Activity 时先唤醒正在复制的旧任务；不能排在它之后等待一个阻塞来源自行结束。
        for (final id in _jobs.keys.toList()) {
          await _cancelAndDrain(id);
        }
      }
    }
    await _serialize(() async {
      _checkOpen();
      if (_store == null) {
        await _configure();
      } else {
        await _refreshOwner();
      }
    });
  }

  bool _needsRecovery(Map<String, dynamic> environment) =>
      environment['ownerReady'] == false ||
      environment['ownerLeaseId'] != _owner?.leaseId ||
      FileShareRecovery.pending;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _configure() async {
    final owner = await FileShareRecovery.confirm(
      files: _files,
      platform: _platform,
    );
    _owner = owner;
    // 此处之前不打开 .share/.leases，旧 isolate 仍可能持有正在写入的复制件。
    _store = null;
    _store = await FileShareLedger.open(
      cacheDirectory: Directory(owner.cacheDirectory),
      limits: limits,
      onChanged: _changed,
      beforeRemove: _cancelAndDrain,
    );
  }

  Future<void> _refreshOwner() async {
    final environment = await _request(
      'sharing.platform.environment',
      const {},
    );
    if (!_needsRecovery(environment) && _store != null) return;
    // 导入队列串行，此时只有上次清理失败的资源可能仍被保留。
    for (final job in _jobs.values.toList()) {
      await _cancelAndDrain(job.id);
      await _recordResult(job);
    }
    await _configure();
    for (final job in _jobs.values.toList()) {
      await _consumePlatform(job.id, _owner!.leaseId);
      _jobs.remove(job.id);
    }
  }

  Future<void> attach() async {
    _checkIntake();
    await configure();
    _checkIntake();
    final response = await _request('sharing.platform.pending', const {});
    final shares = response['shares'];
    if (shares is! List) throw const FileFailure('invalid_share', '分享队列格式无效。');
    for (final raw in shares) {
      if (raw is Map) await receive(Map<String, dynamic>.from(raw));
    }
  }

  /// 同一分享合并交付；不同分享串行复制，既有限额计算与 SDK 稳定 scope 均只有一位写者。
  Future<Map<String, dynamic>> receive(Map<String, dynamic> share) {
    _checkIntake();
    final id = share['shareId'];
    if (id is! String) throw const FileFailure('invalid_share', '分享标识无效。');
    if (_stoppingShares.contains(id)) {
      throw const FileFailure('cancelled', '此分享正在停止或移除。');
    }
    if (_intents[id] case final running?) return running.result.future;
    if (_intents.length >= limits.pending) {
      throw const FileFailure('share_cache_busy', '分享导入队列已满，请稍后重试。');
    }
    final captured = Map<String, dynamic>.from(share);
    final intent = _ImportIntent();
    _intents[id] = intent;
    void retire() {
      if (identical(_intents[id], intent)) {
        _intents.remove(id);
      }
    }

    unawaited(
      _serialize(() async {
        intent.started = true;
        intent.cancellation.check();
        return _receive(id, captured, intent);
      }).then<void>(
        (value) {
          retire();
          if (!intent.result.isCompleted) intent.result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          retire();
          if (!intent.result.isCompleted) {
            intent.result.completeError(error, stack);
          }
        },
      ),
    );
    return intent.result.future;
  }

  Future<Map<String, dynamic>> _receive(
    String id,
    Map<String, dynamic> share,
    _ImportIntent intent,
  ) async {
    _checkIntake();
    await _refreshOwner();
    _checkIntake();
    intent.cancellation.check();
    if (_jobs[id] case final retained?) {
      await _cleanup(retained);
      return _finalize(retained);
    }
    final store = _store!;
    final existing = await store.existing(id);
    if (existing != null) {
      await _consumePlatform(id, _owner!.leaseId);
      return {...existing, 'reusedImport': true};
    }
    await store.reserve(
      id,
      text: share['text'] as String?,
      mime: share['mime'] as String?,
    );
    final job = _ImportJob(id, _owner!, intent.cancellation);
    _jobs[id] = job;
    try {
      job.cancellation.check();
      final count = share['sourceCount'];
      if (share['status'] == 'error') {
        throw FileFailure(
          'share_open_failed',
          (share['errors'] as List? ?? const []).join('；'),
        );
      }
      if (count is! int || count < 0 || count > limits.sources) {
        throw const FileFailure('share_source_limit', '一次最多分享32个来源。');
      }
      job.openingScope = job.owner.openScope(await _files()).catchError((
        Object error,
        StackTrace stack,
      ) {
        job.openingScope = null;
        // 新 scope 未返回时仍可能有旧 scope 排空失败；保留同 key 的接管重试责任。
        job.scopeAttachFailed = true;
        Error.throwWithStackTrace(error, stack);
      });
      job.scope = await job.openingScope;
      job.scopeAttachFailed = false;
      job.cancellation.check();
      var copied = 0;
      final deadline = DateTime.now().add(limits.timeout);
      for (var index = 0; index < count; index++) {
        job.cancellation.check();
        final openId = '${job.id}:${const Uuid().v4()}';
        job.openIds.add(openId);
        final descriptor = await _request('sharing.platform.open', {
          'shareId': id,
          'index': index,
          'openId': openId,
          'ownerLeaseId': job.owner.leaseId,
        }).timeout(limits.timeout);
        // 迟到回执必须先登记，取消检查不能跳过原始 PFD 的关闭责任。
        job.descriptors.add(Map<String, dynamic>.from(descriptor));
        job.cancellation.check();
        final fd = descriptor['fd'];
        final fdLease = descriptor['fdLeaseId'];
        final offset = descriptor['offset'] ?? 0;
        final length = descriptor['declaredLength'];
        if (fd is! int ||
            fd < 0 ||
            fdLease is! String ||
            fdLease.isEmpty ||
            offset is! int ||
            offset < 0 ||
            (length != null && (length is! int || length < 0))) {
          throw const FileFailure('invalid_share', '系统来源描述符无效。');
        }
        final directory = p.join(store.root.path, id);
        final free = (await job.scope!.stat(_path(directory))).freeBytes;
        if (free == null || free < BigInt.from(limits.minimumFreeBytes)) {
          throw const FileFailure('share_cache_full', '无法确认暂存目录剩余空间，或剩余空间不足。');
        }
        final freeBudget = free - BigInt.from(limits.minimumFreeBytes);
        final budget = min(
          min(limits.fileBytes, await store.availableBytes(id) - copied),
          freeBudget > BigInt.from(limits.fileBytes)
              ? limits.fileBytes
              : freeBudget.toInt(),
        );
        if (budget < 0 || (length is int && length > budget)) {
          throw const FileFailure('share_byte_limit', '分享内容超过暂存容量。');
        }
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw const FileFailure('timeout', '分享导入超时。');
        }
        final diskName = const Uuid().v4();
        final copy = await job.scope!.copy(
          source: LocalFileEndpoint.fd(fd),
          target: LocalFileEndpoint.part(
            _path(p.join(directory, '.$diskName.part')),
          ),
          sourceOffset: offset,
          length: length as int?,
          maxBytes: budget,
          timeout: remaining,
          cancellation: job.cancellation,
        );
        job.cancellation.check();
        await job.scope!.commit(
          copy,
          _path(p.join(directory, diskName)),
          expectedIdentity: copy.identity,
        );
        job.cancellation.check();
        job.files.add(
          SharedSourceFile(
            diskName: diskName,
            name: _displayName(descriptor['name']),
            size: copy.bytes,
          ),
        );
        copied += copy.bytes;
        await copy.close();
      }
      job.succeeded = true;
    } catch (error) {
      job.failure = error;
    } finally {
      job.executionFinished.complete();
    }
    await _cleanup(job);
    return _finalize(job);
  }

  /// 先确认原生复制件排空，再关闭平台原始 FD 与迟到打开；失败资源留在 job 中重试。
  Future<void> _cleanup(_ImportJob job) {
    return job.cleaning ??= _cleanupJob(job).whenComplete(() {
      job.cleaning = null;
    });
  }

  Future<void> _cleanupJob(_ImportJob job) async {
    if (job.scopeAttachFailed) {
      job.scope = await job.owner.openScope(await _files());
      job.scopeAttachFailed = false;
    }
    if (job.openingScope case final opening?) {
      job.scope ??= await opening;
    }
    await job.scope?.close();
    job.scope = null;
    job.openingScope = null;
    Object? failure;
    StackTrace? failureStack;
    for (final id in job.openIds.toList()) {
      try {
        final receipt = await _request('sharing.platform.cancel', {
          'openId': id,
          'ownerLeaseId': job.owner.leaseId,
        });
        if (receipt['cancelled'] != true) {
          throw const FileFailure('share_cleanup_unconfirmed', '分享打开尚未确认取消。');
        }
        job.openIds.remove(id);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    for (final descriptor in job.descriptors.toList()) {
      try {
        final receipt = await _request('sharing.platform.release', {
          'fdLeaseId': descriptor['fdLeaseId'],
          'ownerLeaseId': job.owner.leaseId,
        });
        if (receipt['released'] != true) {
          throw const FileFailure(
            'share_cleanup_unconfirmed',
            '分享原始描述符尚未确认释放。',
          );
        }
        job.descriptors.remove(descriptor);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _recordResult(_ImportJob job) async {
    if (job.receipt != null) return;
    if (job.succeeded && !job.cancellation.isCancelled) {
      await _store!.complete(job.id, job.files);
    } else {
      await _store!.fail(job.id, '${job.failure ?? '分享导入已取消。'}');
    }
    job.receipt = (await _store!.existing(job.id))!;
  }

  Future<Map<String, dynamic>> _finalize(_ImportJob job) async {
    await _recordResult(job);
    await _consumePlatform(job.id, job.owner.leaseId);
    _jobs.remove(job.id);
    return job.receipt!;
  }

  Future<void> _consumePlatform(String id, String lease) async {
    final receipt = await _request('sharing.platform.consume', {
      'shareId': id,
      'ownerLeaseId': lease,
    });
    if (receipt['consumed'] != true) {
      throw const FileFailure('share_cleanup_unconfirmed', '分享交接回执尚未确认。');
    }
  }

  Future<void> _cancelAndDrain(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    job.cancellation.cancel();
    await _cleanup(job);
    await job.executionFinished.future;
    await _cleanup(job);
  }

  Future<Map<String, dynamic>> command(
    String command,
    Map<String, dynamic> params,
  ) async {
    _checkOpen();
    if (command == 'sharing.configure') {
      await configure();
      return {'configured': true, 'absoluteRoot': _store!.root.path};
    }
    if (_store == null) await configure();
    if (command == 'sharing.import') {
      throw const FileFailure('unsupported', '分享来源只能从系统授权入口导入。');
    }
    if (command == 'sharing.consume' || command == 'sharing.cancel') {
      final id = params['shareId'];
      if (id is! String) throw const FileFailure('invalid_share', '分享标识无效。');
      if (!_stoppingShares.add(id)) {
        throw const FileFailure('share_busy', '此分享正在停止。');
      }
      try {
        final intent = _intents[id];
        intent?.cancellation.cancel();
        final queued = intent != null && !intent.started;
        if (queued && !intent.result.isCompleted) {
          intent.result.completeError(
            const FileFailure('cancelled', '排队分享已取消。'),
          );
        }
        await _cancelAndDrain(id);
        final pending = _intents[id]?.result.future;
        if (pending != null) {
          try {
            await pending;
          } catch (error) {
            if (!_cancelled(error)) rethrow;
          }
        }
        if (queued) {
          await _store!.command('sharing.reject', {
            'shareId': id,
            'reason': '排队分享已取消。',
          });
          await _consumePlatform(id, _owner!.leaseId);
        }
        return await _store!.command(command, params);
      } finally {
        _stoppingShares.remove(id);
      }
    }
    return _store!.command(command, params);
  }

  @override
  Future<Map<String, Object?>?> begin(
    String share,
    Map<String, Object?> request, {
    String? transferId,
  }) async {
    _checkOpen();
    if (_store == null) await configure();
    return _store!.begin(share, request, transferId: transferId);
  }

  @override
  Future<void> finish(
    String share,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) async {
    _checkOpen();
    if (_store == null) await configure();
    await _store!.finish(
      share,
      receipt,
      definitelyUnpublished: definitelyUnpublished,
    );
  }

  @override
  Future<Set<String>> get sourcePaths async {
    _checkOpen();
    if (_store == null) await configure();
    return _store!.sourcePaths;
  }

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  }) async {
    _checkOpen();
    if (_store == null) await configure();
    return _store!.reconcile(durableReferences, coveredSources: coveredSources);
  }

  Future<void> close() {
    stopIntake();
    _closed = true;
    for (final job in _jobs.values) {
      job.cancellation.cancel();
    }
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    Object? failure;
    StackTrace? failureStack;
    for (final id in _jobs.keys.toList()) {
      try {
        await _cancelAndDrain(id);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    // 未确认 SDK 排空时不无界等待仍被 native 持有的 run；原始 PFD 和重试权都保留。
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    await _configuring;
    await _tail;
    for (final job in _jobs.values.toList()) {
      try {
        await _cleanup(job);
        await _finalize(job);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    await _events.close();
  }
}

final class _ImportJob {
  _ImportJob(this.id, this.owner, this.cancellation);
  final String id;
  final FileShareOwner owner;
  final AdbCancellation cancellation;
  final executionFinished = Completer<void>();
  final openIds = <String>{};
  final descriptors = <Map<String, dynamic>>[];
  final files = <SharedSourceFile>[];
  Future<LocalFileScope>? openingScope;
  LocalFileScope? scope;
  Future<void>? cleaning;
  Object? failure;
  Map<String, dynamic>? receipt;
  bool succeeded = false;
  bool scopeAttachFailed = false;
}

final class _ImportIntent {
  final cancellation = AdbCancellation();
  final result = Completer<Map<String, dynamic>>();
  bool started = false;
}

bool _cancelled(Object error) => switch (error) {
  FileFailure(:final code) => code == 'cancelled',
  AdbException(:final code) => code == 'cancelled',
  LocalFileException(:final code) =>
    code == LocalFileErrorCode.cancelled ||
        code == LocalFileErrorCode.scopeClosed,
  _ => false,
};

Uint8List _path(String value) => Uint8List.fromList(utf8.encode(value));

String _displayName(Object? value) {
  if (value is! String) return '共享文件';
  final basename = value.split(RegExp(r'[/\\]')).last.replaceAll('\u0000', '_');
  final name = String.fromCharCodes(basename.runes.take(180));
  return name.isEmpty || name == '.' || name == '..' ? '共享文件' : name;
}
