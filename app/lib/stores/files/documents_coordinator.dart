import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/models/document_limits.dart';
import 'package:scrcpy_connect/services/files/document_scope_recovery.dart';
import 'package:scrcpy_connect/stores/files/document_sources.dart';

import 'package:scrcpy_connect/services/files/file_executor.dart';

export 'package:scrcpy_connect/models/document_limits.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';

typedef DocumentsJson = Map<String, dynamic>;
typedef DocumentsRequest = Future<DocumentsJson> Function(
  String,
  DocumentsJson,
);

DocumentsJson _map(Object? value) => value is Map<Object?, Object?>
    ? {
        for (final e in value.entries)
          if (e.key case final String key) key: e.value,
      }
    : <String, dynamic>{};
List<DocumentsJson> _maps(Object? value) => value is List<Object?>
    ? value.whereType<Map<Object?, Object?>>().map(_map).toList()
    : <DocumentsJson>[];
String _text(DocumentsJson value, String key, [String fallback = '']) =>
    value[key] is String ? value[key] as String : fallback;
int _number(DocumentsJson value, String key, [int fallback = 0]) =>
    value[key] is num ? (value[key] as num).toInt() : fallback;
String _id() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _name(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.length > 255 ||
      name.contains(RegExp(r'[/\\\x00\r\n]'))) {
    throw const ApplicationCommandException('invalid_path', '文档名称包含不安全的路径字符。');
  }
  return name;
}

/// 应用拥有系统文档计划和预算；平台拥有 URI/PFD，通用文件能力执行有界复制。
class DocumentsCoordinator {
  DocumentsCoordinator({
    required this._files,
    this.limits = const DocumentLimits(),
    required this._platform,
    bool Function()? isDisposed,
    this.onConflictChanged,
    this.sources,
  }) : _isDisposed = isDisposed ?? (() => false);
  final Future<LocalFiles> Function() _files;
  final DocumentLimits limits;
  final DocumentsRequest _platform;
  final bool Function() _isDisposed;
  final void Function(DocumentsJson)? onConflictChanged;
  final DocumentSources? sources;
  final _issued = <String>{};
  _Operation? _active;
  bool _disposed = false;

  Future<DocumentsJson> request(
    String command, [
    DocumentsJson params = const {},
  ]) async {
    if (command == 'documents.conflict.get') {
      final op = _active;
      final pending = op?.pendingConflict;
      return {
        'pending':
            op != null &&
                !op.cancelled &&
                op.id == params['operationId'] &&
                (params['conflictId'] == null ||
                    pending?['conflictId'] == params['conflictId'])
            ? pending
            : null,
      };
    }
    if (command == 'documents.conflict.resolve') {
      final op = _active;
      final pending = op?.pendingConflict;
      if (op == null ||
          op.cancelled ||
          pending == null ||
          op.id != params['operationId'] ||
          pending['conflictId'] != params['conflictId']) {
        return {'resolved': false};
      }
      final choice = _text(params, 'choice');
      if (!['keepBoth', 'skip', 'cancel'].contains(choice) ||
          (params['applyToRemaining'] != null &&
              params['applyToRemaining'] is! bool)) {
        throw const ApplicationCommandException(
          'invalid_decision',
          '请选择保留两份、跳过或取消。',
        );
      }
      if (params['applyToRemaining'] == true && choice != 'cancel') {
        op.conflict = choice;
      }
      _clearConflict(op);
      op.conflictReply!.complete(choice);
      op.conflictReply = null;
      return {'resolved': true};
    }
    if (command == 'documents.cancel') {
      final op = _active;
      final matches = op != null && op.id == params['operationId'];
      if (matches) {
        await _cancel(op);
        if (op.finished.isCompleted) await _finish(op);
      }
      final source = params['managedSourceId'];
      if (source is String && sources != null) await sources!.release(source);
      return {'cancelled': matches, 'operationId': params['operationId']};
    }
    if (![
      'documents.importDirectory',
      'documents.importFiles',
      'documents.export',
    ].contains(command)) {
      throw const ApplicationCommandException('unknown_command', '未知的系统文档操作。');
    }
    if (_disposed || _isDisposed()) {
      throw const ApplicationCommandException('cancelled', '页面已关闭。');
    }
    final previous = _active;
    if (previous != null && previous.finished.isCompleted) {
      await _finish(previous);
      if (_disposed || _isDisposed()) {
        throw const ApplicationCommandException('cancelled', '页面已关闭。');
      }
    }
    if (_active != null) {
      throw const ApplicationCommandException(
        'documents_busy',
        '已有文件选择或复制正在进行，请先完成或取消。',
      );
    }
    final id = _text(params, 'operationId', _id());
    if (id.isEmpty ||
        id.length > 128 ||
        _issued.length >= 10000 ||
        !_issued.add(id)) {
      throw const ApplicationCommandException(
        'operation_id_reused',
        '请使用新的文件操作标识。',
      );
    }
    final conflict = _text(params, 'conflict', 'ask');
    if (!['ask', 'skip', 'keepBoth'].contains(conflict)) {
      throw const ApplicationCommandException(
        'invalid_argument',
        '系统目录仅支持询问、跳过或保留两者。',
      );
    }
    final op = _Operation(id, command, conflict, limits);
    _active = op;
    try {
      final environment = await _platformCall(
        'documents.platform.environment',
        const {},
      );
      final boundary = await DocumentScopeConfiguration.fromEnvironment(
        environment,
      );
      op.boundary = boundary;
      op.cache = boundary.cacheDirectory;
      final ownerLease = environment['ownerLeaseId'];
      if (ownerLease is! String || ownerLease.isEmpty) {
        throw const ApplicationCommandException(
          'document_cleanup_unconfirmed',
          '文档平台尚未接管。',
        );
      }
      op.ownerLeaseId = ownerLease;
      op.check(_disposed || _isDisposed());
      // 在等待前登记创建 Future；取消也必须回收迟到的 scope。
      op.openingScope = Future<LocalFiles>.sync(_files).then((files) {
        op.check(_disposed || _isDisposed());
        return boundary.open(files);
      });
      await _native(() => op.openingScope!);
      op.check(_disposed || _isDisposed());
      String mode = command == 'documents.importDirectory'
          ? 'importDirectory'
          : 'importFiles';
      String? source;
      if (command == 'documents.export') {
        source = _text(params, 'localPath');
        final stat = await _stat(op, source);
        final kind = stat.identity.kind;
        if (![LocalFileKind.file, LocalFileKind.directory].contains(kind) ||
            (params['kind'] != null && params['kind'] != kind.name)) {
          throw const ApplicationCommandException(
            'source_changed',
            '源类型与所选保存方式不一致。',
          );
        }
        op.localPath = source;
        op.name = _name(_text(params, 'name', p.basename(source)));
        mode = kind == LocalFileKind.directory
            ? 'exportDirectory'
            : 'exportFile';
      }
      op.check(_disposed || _isDisposed());
      final selection = await op.wait(
        _platform('documents.platform.picker', {
          'ownerLeaseId': op.ownerLeaseId,
          'operationId': id,
          'mode': mode,
          'name': op.name,
          'mime': _text(
            params,
            'mime',
            mode == 'exportFile' ? 'application/octet-stream' : '*/*',
          ),
        }),
      );
      if (selection['status'] == 'cancelled') return op.response('cancelled');
      op.started = true;
      op.timer = Timer(op.limits.timeout, () {
        op.timedOut = true;
        unawaited(_cancel(op).catchError((Object _) {}));
      });
      op.check(_disposed || _isDisposed());
      final selections = _maps(selection['documents']);
      if (selections.isEmpty) {
        throw const ApplicationCommandException('invalid_uri', '系统没有返回可读取的文档。');
      }
      if (selections.length > op.limits.maxSelected) {
        throw const ApplicationCommandException(
          'selection_limit',
          '最多选择 1000 个文件，请分批导入。',
        );
      }
      op.uri = _text(selections.first, 'uri');
      if (mode == 'importDirectory') {
        final root = await _metadata(op, selections.first);
        if (root['directory'] != true || root['virtual'] == true) {
          throw const ApplicationCommandException(
            'not_a_directory',
            '请选择可读取的普通文档目录。',
          );
        }
        op.name = _name(_text(root, 'name'));
        final owner = await _owner(op);
        op.localPath = '$owner/${op.name}';
        await _importNode(op, root, op.localPath!, 0, op.name);
      } else if (mode == 'importFiles') {
        final owner = await _owner(op);
        op.localPath = owner;
        op.name = '所选文件';
        for (var index = 0; index < selections.length; index++) {
          op.examine();
          try {
            final source = await _metadata(op, selections[index]);
            if (source['directory'] == true) {
              throw const ApplicationCommandException(
                'not_a_file',
                '文件选择器返回了目录，请使用发送本机文件夹。',
              );
            }
            final name = _name(_text(source, 'name'));
            final parent = '$owner/$index';
            await _mkdir(op, parent);
            final path = '$parent/$name';
            final copied = await _importNode(op, source, path, 0, name);
            if (copied) op.items.add({'localPath': path, 'name': name});
          } catch (error) {
            op.record('所选文件 ${index + 1}', error);
          }
        }
      } else if (mode == 'exportDirectory') {
        final parent = await _metadata(op, selections.first);
        if (parent['directory'] != true || parent['canCreate'] != true) {
          throw const ApplicationCommandException(
            'create_unavailable',
            '所选提供方目录没有新建能力；本机暂存已保留。',
          );
        }
        final root = await _create(op, parent, op.name, true);
        if (root != null) {
          op.uri = _text(root, 'uri');
          op.name = _text(root, 'name');
          await _exportNode(op, source!, root, 0, op.name);
        }
      } else {
        final target = await _metadata(op, selections.first);
        op.name = _text(target, 'name');
        await _writeFile(op, source!, target, p.basename(source));
      }
      op.check(_disposed || _isDisposed());
      return op.response(
        op.errorsCount > 0 || op.skipped > 0
            ? 'partial'
            : command.startsWith('documents.import')
            ? 'imported'
            : 'saved',
      );
    } catch (error) {
      final code = op.timedOut
          ? 'timeout'
          : error is ApplicationCommandException
          ? error.code
          : 'documents_error';
      op.error(op.name, code, '$error');
      return op.response(
        code == 'result_unknown'
            ? 'resultUnknown'
            : code == 'cancelled'
            ? 'cancelled'
            : !op.started
            ? 'failed'
            : 'partial',
      );
    } finally {
      op.timer?.cancel();
      try {
        await _finish(op);
      } finally {
        // dispose 等待真实请求退出；清理失败仍保留 op，后续关闭可以重试。
        op.finished.complete();
      }
    }
  }

  Future<DocumentsJson> _platformCall(
    String command,
    DocumentsJson params, {
    bool cancellable = true,
    _Operation? operation,
  }) async {
    // 等待前捕获所有者；迟到超时或回复不能取消替换操作。
    final op = operation ?? _active;
    try {
      final response = _platform(command, {
        ...params,
        if (command != 'documents.platform.environment' &&
            op?.ownerLeaseId != null)
          'ownerLeaseId': op!.ownerLeaseId,
      }).timeout(const Duration(seconds: 120));
      return await (cancellable && op != null ? op.wait(response) : response);
    } on TimeoutException {
      if (cancellable && op != null) {
        op.timedOut = true;
        unawaited(_cancel(op).catchError((Object _) {}));
      }
      throw const ApplicationCommandException(
        'timeout',
        '系统文档提供方未及时响应；请核对已完成内容。',
      );
    }
  }

  Future<void> _closeScope(_Operation op) {
    if (op.scopeClosed) return Future<void>.value();
    return op.closingScope ??= Future<void>.sync(() async {
      final opening = op.openingScope;
      if (opening == null) {
        op.scopeClosed = true;
        return;
      }
      final LocalFileScope scope;
      try {
        scope = await opening;
      } catch (_) {
        // 创建失败没有交出 scope；通用能力负责其未交出的资源。
        op.scopeClosed = true;
        return;
      }
      await scope.close();
      op.scopeClosed = true;
    }).whenComplete(() => op.closingScope = null);
  }

  Future<void> _finish(_Operation op) =>
      op.finishing ??= _finishOperation(op)
          .catchError((Object error, StackTrace stack) {
            op.finishing = null;
            Error.throwWithStackTrace(error, stack);
          });

  Future<void> _finishOperation(_Operation op) async {
    try {
      await _closeScope(op);
      await op.cancellationRequest;
      if (op.ownerLeaseId != null) {
        final released = await _platformCall(
          'documents.platform.release',
          {'operationId': op.id},
          cancellable: false,
          operation: op,
        );
        if (released['released'] != true) {
          throw const ApplicationCommandException(
            'document_cleanup_unconfirmed',
            '平台文档资源未确认释放。',
          );
        }
      }
      if (!op.sourceCompleted && op.managedSourceId != null) {
        await sources!.complete(op.managedSourceId!, op.name);
        op.sourceCompleted = true;
      }
      if (identical(_active, op)) _active = null;
    } catch (error) {
      throw ApplicationCommandException(
        'document_cleanup_unconfirmed',
        '文档操作尚未确认释放，请重试关闭；不会重新复制。',
        {'operationId': op.id},
      );
    }
  }

  Future<void> _cancel(_Operation op) {
    op.cancelled = true;
    _clearConflict(op);
    if (!op.interrupted.isCompleted) op.interrupted.complete();
    return op.cancellationRequest ??= Future<void>.sync(() async {
      // 平台 cancel 也会关闭 PFD，必须先排空复制，不能与 worker 并行关闭原始 FD。
      await _closeScope(op);
      if (op.ownerLeaseId != null) {
        final cancelled = await _platformCall(
          'documents.platform.cancel',
          {'operationId': op.id},
          cancellable: false,
          operation: op,
        );
        if (cancelled['cancelled'] != true) {
          throw const ApplicationCommandException(
            'document_cleanup_unconfirmed',
            '平台文档取消未确认。',
          );
        }
      }
    }).whenComplete(() => op.cancellationRequest = null);
  }

  Future<void> dispose() async {
    _disposed = true;
    final op = _active;
    if (op == null) return;
    await _cancel(op);
    await op.finished.future;
    if (identical(_active, op)) await _finish(op);
  }

  Future<LocalFileScope> _scope(_Operation op) async {
    op.check(_disposed || _isDisposed());
    final scope = await op.openingScope!;
    op.check(_disposed || _isDisposed());
    return scope;
  }

  Uint8List _path(_Operation op, String value) =>
      Uint8List.fromList(utf8.encode(op.boundary!.pathForScope(value)));

  Future<DocumentsJson> _metadata(_Operation op, DocumentsJson document) async {
    op.check(_disposed || _isDisposed());
    return _platformCall('documents.platform.metadata', {
      'operationId': op.id,
      'handle': document['handle'],
    });
  }

  Future<List<DocumentsJson>> _children(
    _Operation op,
    DocumentsJson parent,
  ) async {
    final children = <DocumentsJson>[];
    var offset = 0;
    while (true) {
      op.check(_disposed || _isDisposed());
      final page = await _platformCall('documents.platform.children', {
        'operationId': op.id,
        'handle': parent['handle'],
        'offset': offset,
        'limit': 256,
      });
      final entries = _maps(page['documents']);
      children.addAll(entries);
      if (children.length > op.limits.maxEntries) {
        throw const ApplicationCommandException(
          'tree_limit',
          '提供方目录超过项目上限，请分批处理。',
        );
      }
      if (page['loading'] == true) {
        throw const ApplicationCommandException(
          'provider_loading',
          '文档提供方尚未完成目录加载，请稍后重新选择。',
        );
      }
      if (page['hasMore'] != true) return children;
      if (entries.isEmpty) {
        throw const ApplicationCommandException(
          'provider_loading',
          '提供方没有完成目录分页。',
        );
      }
      offset += entries.length;
    }
  }

  Future<String> _owner(_Operation op) async {
    if (sources case final owner?) {
      try {
        final source = await owner.reserve();
        op.managedSourceId = source.id;
        op.importBytes = source.availableBytes;
        await _mkdir(op, source.path);
        return source.path;
      } on FileFailure catch (error) {
        throw ApplicationCommandException(error.code, error.message);
      }
    }
    final base = p.join(op.cache, 'documents');
    await _mkdir(op, base, exclusive: false);
    final path = p.join(base, _id());
    await _mkdir(op, path);
    return path;
  }

  ApplicationCommandException _fileFailure(LocalFileException error) =>
      ApplicationCommandException(
        switch (error.code) {
          LocalFileErrorCode.invalidArgument => 'invalid_path',
          LocalFileErrorCode.scopeClosed ||
          LocalFileErrorCode.cancelled => 'cancelled',
          LocalFileErrorCode.notFound => 'not_found',
          LocalFileErrorCode.busy => 'documents_busy',
          LocalFileErrorCode.timedOut => 'timeout',
          LocalFileErrorCode.byteLimit => 'byte_limit',
          LocalFileErrorCode.entryLimit => 'tree_limit',
          LocalFileErrorCode.sourceChanged => 'source_changed',
          LocalFileErrorCode.targetChanged => 'target_changed',
          LocalFileErrorCode.conflict => 'conflict',
          LocalFileErrorCode.resultUnknown => 'result_unknown',
          LocalFileErrorCode.cleanupUnconfirmed =>
            'document_cleanup_unconfirmed',
          LocalFileErrorCode.unsupported => 'implementation_pending',
          LocalFileErrorCode.io => 'document_io',
        },
        error.message,
        {
          'bytesCopied': error.bytesCopied,
          'partialDestinationPossible': error.partialDestinationPossible,
        },
      );

  Future<T> _native<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on LocalFileException catch (error) {
      throw _fileFailure(error);
    }
  }

  Future<LocalFileStat> _stat(_Operation op, String path) =>
      _native(() async => (await _scope(op)).stat(_path(op, path)));

  Future<void> _mkdir(_Operation op, String path, {bool exclusive = true}) =>
      _native(
        () async =>
            (await _scope(op)).mkdir(_path(op, path), exclusive: exclusive),
      );

  Future<LocalFileCopy> _copy(
    _Operation op,
    DocumentsJson provider,
    String mode, {
    String? source,
    String? target,
    LocalFileIdentity? expectedSource,
  }) async {
    op.check(_disposed || _isDisposed());
    final opened = await _platformCall('documents.platform.openFd', {
      'operationId': op.id,
      'handle': provider['handle'],
      'mode': mode,
    });
    LocalFileCopy? copy;
    var completed = false;
    var cleanupUnconfirmed = false;
    try {
      op.check(_disposed || _isDisposed());
      final scope = await _scope(op);
      final completedCopy = await _native<LocalFileCopy>(
        () => scope.copy(
          source: mode == 'r'
              ? LocalFileEndpoint.fd(opened['fd'] as int)
              : LocalFileEndpoint.path(_path(op, source!)),
          target: mode == 'r'
              ? LocalFileEndpoint.part(_path(op, target!))
              : LocalFileEndpoint.fd(opened['fd'] as int),
          expectedSource: expectedSource,
          maxBytes:
              min(op.limits.maxBytes, op.importBytes ?? op.limits.maxBytes) -
              op.bytes,
          timeout: op.limits.timeout,
        ),
      );
      copy = completedCopy;
      op.bytes += completedCopy.bytes;
      op.check(_disposed || _isDisposed());
      completed = true;
      return completedCopy;
    } on ApplicationCommandException catch (error) {
      op.bytes += _number(_map(error.details), 'bytesCopied');
      cleanupUnconfirmed = error.code == 'document_cleanup_unconfirmed';
      rethrow;
    } finally {
      // 复制没有确认排空时，原始 PFD 也不能提前释放；失败由当前 op 保留重试权。
      if (cleanupUnconfirmed) await _closeScope(op);
      Object? releaseFailure;
      try {
        final released = await _platformCall('documents.platform.releaseFd', {
          'operationId': op.id,
          'fdLeaseId': opened['fdLeaseId'],
          'outcome': completed && !op.cancelled ? 'success' : 'abort',
        }, cancellable: false);
        if (released['released'] != true) {
          throw const ApplicationCommandException(
            'close_failed',
            '系统文档流已释放，无法确认本次完成。',
          );
        }
      } catch (error) {
        releaseFailure = error;
      }
      if ((!completed || releaseFailure != null) && copy != null) {
        await _native(copy.close);
      }
      // 写入已完成但提供方关闭未确认时，不重写、不删除该 URI。
      if (completed && releaseFailure != null) {
        op.check(_disposed || _isDisposed());
        throw ApplicationCommandException(
          mode == 'rw' ? 'result_unknown' : 'read_failed',
          '系统文档流关闭未确认，请核对已完成内容；不会自动重试。',
        );
      }
    }
  }

  Future<bool> _importNode(
    _Operation op,
    DocumentsJson source,
    String target,
    int depth,
    String relative,
  ) async {
    op.entry(depth, relative);
    final providerIdentity = '${source['authority']}:${source['id']}';
    if (!op.visited.add(providerIdentity)) {
      op.skip(relative, 'document_cycle', '提供方重复返回同一文档，未继续递归。');
      return false;
    }
    if (source['virtual'] == true) {
      op.skip(relative, 'virtual_document', '虚拟文档未自动转换或下载。');
      return false;
    }
    if (source['directory'] == true) {
      await _mkdir(op, target);
      op.writing = true;
      op.directories++;
      final names = <String>{};
      for (final child in await _children(op, source)) {
        op.examine();
        try {
          final name = _name(_text(child, 'name'));
          if (!names.add(name)) {
            throw const ApplicationCommandException(
              'duplicate_name',
              '提供方返回同名项目，未合并或覆盖。',
            );
          }
          await _importNode(
            op,
            child,
            '$target/$name',
            depth + 1,
            '$relative/$name',
          );
        } catch (error) {
          op.record('$relative/${child['name']}', error);
        }
      }
      final after = await _metadata(op, source);
      if (!_sameProvider(source, after, directory: true)) {
        op.error(relative, 'source_changed', '目录在复制期间发生变化；快照未完整确认。');
      }
      return true;
    }
    final parent = p.dirname(target);
    final space = await _stat(op, parent);
    if (source['size'] is num &&
        BigInt.from(_number(source, 'size')) >
            (space.freeBytes ?? BigInt.zero) -
                BigInt.from(op.limits.reserveBytes)) {
      throw const ApplicationCommandException('cache_full', '本机暂存空间不足，未下载此文件。');
    }
    final part = p.join(parent, '.interop-${_id()}.part');
    LocalFileCopy? copy;
    try {
      copy = await _copy(op, source, 'r', target: part);
      final after = await _metadata(op, source);
      if (!_sameProvider(source, after, directory: false) ||
          (source['size'] is num && copy.bytes != _number(source, 'size'))) {
        throw const ApplicationCommandException(
          'source_changed',
          '源文件在复制期间发生变化；未提交暂存文件。',
        );
      }
      final identity = copy.identity;
      final scope = await _scope(op);
      await _native(
        () =>
            scope.commit(copy!, _path(op, target), expectedIdentity: identity),
      );
      op.check(_disposed || _isDisposed());
      op.files++;
      return true;
    } finally {
      // SDK 按持有的片段身份回收未发布对象，不能按路径猜测删除替换文件。
      if (copy != null) await _native(copy.close);
    }
  }

  bool _sameProvider(
    DocumentsJson before,
    DocumentsJson after, {
    required bool directory,
  }) =>
      before['id'] == after['id'] &&
      after['directory'] == directory &&
      (before['modified'] == null || before['modified'] == after['modified']) &&
      (directory || before['size'] == null || before['size'] == after['size']);

  Future<DocumentsJson?> _create(
    _Operation op,
    DocumentsJson parent,
    String requested,
    bool directory,
  ) async {
    final existing = await _children(op, parent);
    var name = _name(requested);
    if (existing.any((child) => child['name'] == name)) {
      final decision = op.conflict == 'ask'
          ? await _conflict(op, name)
          : op.conflict;
      if (decision == 'cancel') {
        throw const ApplicationCommandException('cancelled', '已取消保存；已完成内容保留。');
      }
      if (decision == 'skip') {
        op.skipped++;
        return null;
      }
      if (decision != 'keepBoth') {
        throw const ApplicationCommandException(
          'invalid_decision',
          '未确认同名项目处理方式。',
        );
      }
      name = '$name (${_id()})';
    }
    final fresh = await _metadata(op, parent);
    if (fresh['directory'] != true || fresh['canCreate'] != true) {
      throw const ApplicationCommandException(
        'target_changed',
        '目标目录的新建能力已变化。',
      );
    }
    op.check(_disposed || _isDisposed());
    op.writing = true;
    DocumentsJson created;
    try {
      created = await _platformCall('documents.platform.create', {
        'operationId': op.id,
        'handle': parent['handle'],
        'name': name,
        'mime': directory
            ? 'vnd.android.document/directory'
            : 'application/octet-stream',
      });
    } catch (_) {
      throw const ApplicationCommandException(
        'result_unknown',
        '文档创建结果尚不确定，请核对目标目录；不会自动重试。',
      );
    }
    op.createdCount++;
    if (op.created.length < op.limits.maxErrors) {
      op.created.add({'uri': created['uri'], 'name': created['name']});
    }
    if (op.createdCount == 1) {
      op.uri = _text(created, 'uri');
      op.name = _text(created, 'name');
    }
    if (existing.any((child) => child['id'] == created['id']) ||
        created['name'] != name ||
        created['directory'] != directory) {
      throw const ApplicationCommandException(
        'target_changed',
        '提供方返回已有文档、不同类型或修改了名称；未写入内容，请核对空项目。',
      );
    }
    if ((await _children(
          op,
          parent,
        )).where((child) => child['name'] == name).length !=
        1) {
      throw const ApplicationCommandException(
        'target_changed',
        '创建期间出现同名竞争；未写入内容，请核对空项目。',
      );
    }
    if (name != requested && op.renamed.length < op.limits.maxErrors) {
      op.renamed.add({
        'requested': requested,
        'name': name,
        'uri': created['uri'],
      });
    }
    return created;
  }

  Future<String> _conflict(_Operation op, String name) async {
    op.check(_disposed || _isDisposed());
    final reply = Completer<String>();
    op.conflictReply = reply;
    op.pendingConflict = Map<String, dynamic>.unmodifiable({
      'operationId': op.id,
      'conflictId': _id(),
      'name': name,
      'choices': const ['keepBoth', 'skip', 'cancel'],
      'replacementSupported': false,
      'replacementUnavailableReason': '系统文档提供方不能保证原子替换；已有内容不会被覆盖。',
    });
    onConflictChanged?.call({
      'operationId': op.id,
      'pending': op.pendingConflict,
    });
    try {
      return await op.wait(reply.future);
    } finally {
      _clearConflict(op);
      op.conflictReply = null;
    }
  }

  void _clearConflict(_Operation op) {
    if (op.pendingConflict == null) return;
    op.pendingConflict = null;
    onConflictChanged?.call({'operationId': op.id, 'pending': null});
  }

  Future<void> _exportNode(
    _Operation op,
    String source,
    DocumentsJson target,
    int depth,
    String relative, {
    LocalFileIdentity? expected,
  }) async {
    op.entry(depth, relative);
    final before = (await _stat(op, source)).identity;
    if (expected != null && !_sameLocal(expected, before)) {
      throw const ApplicationCommandException(
        'source_changed',
        '源项目在遍历后被替换，未读取替换内容。',
      );
    }
    if (before.kind == LocalFileKind.directory) {
      op.directories++;
      final scope = await _scope(op);
      final listing = await _native(
        () => scope.list(_path(op, source), maxEntries: op.limits.maxEntries),
      );
      op.check(_disposed || _isDisposed());
      if (!_sameLocal(before, listing.identity)) {
        throw const ApplicationCommandException(
          'source_changed',
          '源目录在遍历前发生变化。',
        );
      }
      for (final child in listing.entries) {
        op.examine();
        var name = '未知名称';
        try {
          name = _name(utf8.decode(child.name));
          final path = p.join(source, name);
          final stat = (await _stat(op, path)).identity;
          if (!_sameLocal(child.identity, stat)) {
            throw const ApplicationCommandException(
              'source_changed',
              '源项目在目录快照后发生变化。',
            );
          }
          if (![
            LocalFileKind.file,
            LocalFileKind.directory,
          ].contains(stat.kind)) {
            op.skip('$relative/$name', 'not_followed', '符号链接和特殊文件不会自动跟随。');
            continue;
          }
          final created = await _create(
            op,
            target,
            name,
            stat.kind == LocalFileKind.directory,
          );
          if (created != null) {
            await _exportNode(
              op,
              path,
              created,
              depth + 1,
              '$relative/$name',
              expected: stat,
            );
          }
        } catch (error) {
          op.record('$relative/$name', error);
        }
      }
      final after = (await _stat(op, source)).identity;
      if (!_sameLocal(before, after)) {
        op.error(relative, 'source_changed', '源目录在保存期间发生变化，已保存项目保留。');
      }
    } else {
      await _writeFile(op, source, target, relative);
    }
  }

  bool _sameLocal(LocalFileIdentity before, LocalFileIdentity after) =>
      before.device == after.device &&
      before.inode == after.inode &&
      before.size == after.size &&
      before.modifiedSeconds == after.modifiedSeconds &&
      before.modifiedNanos == after.modifiedNanos &&
      before.kind == after.kind;

  Future<void> _writeFile(
    _Operation op,
    String source,
    DocumentsJson target,
    String relative,
  ) async {
    op.examine();
    final before = (await _stat(op, source)).identity;
    if (before.kind != LocalFileKind.file) {
      throw const ApplicationCommandException(
        'source_changed',
        '源文件类型已变化，未跟随符号链接。',
      );
    }
    final fresh = await _metadata(op, target);
    if (fresh['id'] != target['id'] ||
        fresh['directory'] == true ||
        fresh['virtual'] == true ||
        (fresh['size'] != null && fresh['size'] != 0)) {
      throw const ApplicationCommandException(
        'target_changed',
        '目标不是刚创建的空文档，未覆盖已有内容。',
      );
    }
    if (fresh['canWrite'] != true) {
      throw const ApplicationCommandException(
        'write_unavailable',
        '提供方没有声明写入能力；本机暂存已保留。',
      );
    }
    op.writing = true;
    final copy = await _copy(
      op,
      fresh,
      'rw',
      source: source,
      expectedSource: before,
    );
    try {
      final after = (await _stat(op, source)).identity;
      if (!_sameLocal(before, after)) {
        throw const ApplicationCommandException(
          'source_changed',
          '源文件在保存期间变化，目标可能包含部分内容。',
        );
      }
    } finally {
      await _native(copy.close);
    }
    final saved = await _metadata(op, target);
    if (saved['size'] != null &&
        BigInt.from(_number(saved, 'size')) != before.size) {
      throw const ApplicationCommandException(
        'result_unknown',
        '提供方返回保存长度不一致，请核对目标；本机暂存已保留。',
      );
    }
    op.files++;
  }
}

class _Operation {
  _Operation(this.id, this.command, this.conflict, this.limits);
  final String id, command;
  String conflict;
  DocumentsJson? pendingConflict;
  Completer<String>? conflictReply;
  final DocumentLimits limits;
  DocumentScopeConfiguration? boundary;
  Future<LocalFileScope>? openingScope;
  Future<void>? closingScope;
  bool scopeClosed = false;
  final finished = Completer<void>();
  String cache = '', name = '';
  String? localPath, uri, ownerLeaseId;
  String? managedSourceId;
  int? importBytes;
  bool sourceCompleted = false;
  bool cancelled = false, timedOut = false, writing = false, started = false;
  Timer? timer;
  final interrupted = Completer<void>();
  Future<void>? cancellationRequest;
  Future<void>? finishing;
  Future<T> wait<T>(Future<T> response) => Future.any<T>([
    response,
    interrupted.future.then<T>((_) {
      check(false);
      throw const ApplicationCommandException('cancelled', '操作已取消。');
    }),
  ]);
  int entries = 0,
      examined = 0,
      pathBytes = 0,
      bytes = 0,
      files = 0,
      directories = 0,
      skipped = 0,
      errorsCount = 0,
      createdCount = 0;
  final visited = <String>{};
  final errors = <DocumentsJson>[],
      renamed = <DocumentsJson>[],
      created = <DocumentsJson>[],
      items = <DocumentsJson>[];
  void check(bool disposed) {
    if (timedOut) {
      throw const ApplicationCommandException(
        'timeout',
        '系统文档复制超过十分钟；已完成内容保留，请分批处理。',
      );
    }
    if (cancelled || disposed) {
      throw const ApplicationCommandException('cancelled', '操作已取消。');
    }
  }

  void examine() {
    check(false);
    if (++examined > limits.maxEntries) {
      throw const ApplicationCommandException('tree_limit', '目录超过项目上限，请分批处理。');
    }
  }

  void entry(int depth, String path) {
    check(false);
    entries++;
    pathBytes += utf8.encode(path).length;
    if (entries > limits.maxEntries ||
        depth > limits.maxDepth ||
        pathBytes > limits.maxPathBytes) {
      throw const ApplicationCommandException(
        'tree_limit',
        '目录超过项目、深度或路径上限，请分批处理。',
      );
    }
  }

  void error(String path, String code, String message) {
    errorsCount++;
    if (errors.length < limits.maxErrors) {
      errors.add({'path': path, 'code': code, 'message': message});
    }
  }

  void skip(String path, String code, String message) {
    skipped++;
    error(path, code, message);
  }

  void record(String path, Object failure) {
    if (cancelled ||
        failure is ApplicationCommandException &&
            [
              'cancelled',
              'tree_limit',
              'byte_limit',
              'timeout',
              'result_unknown',
              'document_cleanup_unconfirmed',
            ].contains(failure.code)) {
      throw failure;
    }
    skip(
      path,
      failure is ApplicationCommandException ? failure.code : 'documents_error',
      '$failure',
    );
  }

  DocumentsJson response(String status) => {
    'operationId': id,
    if (managedSourceId != null) 'managedSourceId': managedSourceId,
    'status': status,
    'localPath': localPath,
    'uri': uri,
    'name': name,
    'bytes': bytes,
    'files': files,
    'directories': directories,
    'skipped': skipped,
    'errors': errors,
    'errorCount': errorsCount,
    'errorsTruncated': errorsCount > errors.length,
    'renamed': renamed,
    'created': created,
    'createdCount': createdCount,
    'items': items,
    'atomic': false,
    'saveMode': command.startsWith('documents.import')
        ? 'cacheSnapshot'
        : 'providerStream',
    'partialDestinationPossible':
        writing && !['saved', 'imported'].contains(status),
    'sourceValidation': 'sizeAndMtimeWhenAvailable',
    'cacheRetained': localPath != null,
  };
}
