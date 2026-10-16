import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../interop_exception.dart';

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
    throw const InteropException('invalid_path', '文档名称包含不安全的路径字符。');
  }
  return name;
}

/// Shared SAF planning. Android only supplies operation-owned URI capabilities
/// and descriptor leases; bounded byte copying belongs to the shared core.
class DocumentsCoordinator {
  DocumentsCoordinator({
    required this._core,
    required this._platform,
    bool Function()? isDisposed,
  }) : _isDisposed = isDisposed ?? (() => false);
  final DocumentsRequest _core;
  final DocumentsRequest _platform;
  final bool Function() _isDisposed;
  final _issued = <String>{};
  _Operation? _active;
  bool _disposed = false;

  Future<DocumentsJson> request(
    String command, [
    DocumentsJson params = const {},
  ]) async {
    if (command == 'documents.cancel') {
      final op = _active;
      final matches = op != null && op.id == params['operationId'];
      if (matches) await _cancel(op);
      return {'cancelled': matches, 'operationId': params['operationId']};
    }
    if (![
      'documents.importDirectory',
      'documents.importFiles',
      'documents.export',
    ].contains(command)) {
      throw const InteropException('unknown_command', '未知的系统文档操作。');
    }
    if (_disposed || _isDisposed()) {
      throw const InteropException('cancelled', '页面已关闭。');
    }
    if (_active != null) {
      throw const InteropException('documents_busy', '已有文件选择或复制正在进行，请先完成或取消。');
    }
    final id = _text(params, 'operationId', _id());
    if (id.isEmpty ||
        id.length > 128 ||
        _issued.length >= 10000 ||
        !_issued.add(id)) {
      throw const InteropException('operation_id_reused', '请使用新的文件操作标识。');
    }
    final conflict = _text(params, 'conflict', 'ask');
    if (!['ask', 'skip', 'keepBoth'].contains(conflict)) {
      throw const InteropException('invalid_argument', '系统目录仅支持询问、跳过或保留两者。');
    }
    final op = _Operation(id, command, conflict);
    _active = op;
    try {
      op.limits = await _core('document.limits', const {});
      final environment = await _platformCall(
        'documents.platform.environment',
        const {},
      );
      op.cache = _text(environment, 'cacheDirectory');
      op.roots = [
        op.cache,
        _text(environment, 'screenshotsDirectory'),
      ].where((p) => p.isNotEmpty).toList();
      if (!op.cache.startsWith('/')) {
        throw const InteropException('cache_unavailable', '系统没有提供本机暂存位置。');
      }
      String mode = command == 'documents.importDirectory'
          ? 'importDirectory'
          : 'importFiles';
      String? source;
      if (command == 'documents.export') {
        source = _text(params, 'localPath');
        final stat = await _local(op, 'localStat', {'path': source});
        final kind = _text(stat, 'kind');
        if (!['file', 'directory'].contains(kind) ||
            (params['kind'] != null && params['kind'] != kind)) {
          throw const InteropException('source_changed', '源类型与所选保存方式不一致。');
        }
        op.localPath = source;
        op.name = _name(_text(params, 'name', source.split('/').last));
        mode = kind == 'directory' ? 'exportDirectory' : 'exportFile';
      }
      op.check(_disposed || _isDisposed());
      final selection = await op.wait(
        _platform('documents.platform.picker', {
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
      op.timer = Timer(
        Duration(milliseconds: _number(op.limits, 'timeoutMillis')),
        () {
          op.timedOut = true;
          unawaited(_cancel(op));
        },
      );
      op.check(_disposed || _isDisposed());
      final selections = _maps(selection['documents']);
      if (selections.isEmpty) {
        throw const InteropException('invalid_uri', '系统没有返回可读取的文档。');
      }
      if (selections.length > _number(op.limits, 'maxSelected')) {
        throw const InteropException('selection_limit', '最多选择 1000 个文件，请分批导入。');
      }
      op.uri = _text(selections.first, 'uri');
      if (mode == 'importDirectory') {
        final root = await _metadata(op, selections.first);
        if (root['directory'] != true || root['virtual'] == true) {
          throw const InteropException('not_a_directory', '请选择可读取的普通文档目录。');
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
              throw const InteropException(
                'not_a_file',
                '文件选择器返回了目录，请使用发送本机文件夹。',
              );
            }
            final name = _name(_text(source, 'name'));
            final parent = '$owner/$index';
            await _local(op, 'mkdir', {'path': parent});
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
          throw const InteropException(
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
        await _writeFile(op, source!, target, source.split('/').last);
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
          : error is InteropException
          ? error.code
          : 'documents_error';
      op.error(op.name, code, '$error');
      return op.response(
        code == 'result_unknown'
            ? 'resultUnknown'
            : op.writing
            ? 'partial'
            : code == 'cancelled'
            ? 'cancelled'
            : 'partial',
      );
    } finally {
      op.timer?.cancel();
      try {
        await _platformCall('documents.platform.release', {
          'operationId': id,
        }, cancellable: false);
      } catch (_) {
        /* Native onDestroy also closes owned leases. */
      }
      if (identical(_active, op)) _active = null;
    }
  }

  Future<DocumentsJson> _platformCall(
    String command,
    DocumentsJson params, {
    bool cancellable = true,
  }) async {
    // Capture the owner before awaiting. A late timeout or reply from this
    // request must never cancel a replacement operation.
    final op = _active;
    try {
      final response = _platform(
        command,
        params,
      ).timeout(const Duration(seconds: 120));
      return await (cancellable && op != null ? op.wait(response) : response);
    } on TimeoutException {
      if (cancellable && op != null) {
        op.timedOut = true;
        unawaited(_cancel(op));
      }
      throw const InteropException('timeout', '系统文档提供方未及时响应；请核对已完成内容。');
    }
  }

  Future<void> _cancel(_Operation op) async {
    op.cancelled = true;
    if (!op.interrupted.isCompleted) op.interrupted.complete();
    await (op.cancellationRequest ??= Future.wait([
      _platformCall('documents.platform.cancel', {
        'operationId': op.id,
      }, cancellable: false).catchError((Object _) => <String, dynamic>{}),
      _core('document.cancel', {
        'operationId': op.id,
      }).catchError((Object _) => <String, dynamic>{}),
    ]).then<void>((_) {}));
  }

  Future<void> dispose() async {
    _disposed = true;
    final op = _active;
    if (op != null) await _cancel(op);
  }

  Future<DocumentsJson> _local(
    _Operation op,
    String command,
    DocumentsJson params,
  ) async {
    op.check(_disposed || _isDisposed());
    return _core('document.$command', {...params, 'allowedRoots': op.roots});
  }

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
      if (children.length > _number(op.limits, 'maxEntries')) {
        throw const InteropException('tree_limit', '提供方目录超过项目上限，请分批处理。');
      }
      if (page['loading'] == true) {
        throw const InteropException(
          'provider_loading',
          '文档提供方尚未完成目录加载，请稍后重新选择。',
        );
      }
      if (page['hasMore'] != true) return children;
      if (entries.isEmpty) {
        throw const InteropException('provider_loading', '提供方没有完成目录分页。');
      }
      offset += entries.length;
    }
  }

  Future<String> _owner(_Operation op) async {
    final base = '${op.cache}/documents';
    await _local(op, 'mkdir', {'path': base, 'exclusive': false});
    final path = '$base/${_id()}';
    await _local(op, 'mkdir', {'path': path});
    return path;
  }

  Future<DocumentsJson> _copy(
    _Operation op,
    DocumentsJson params,
    DocumentsJson provider,
    String mode,
  ) async {
    op.check(_disposed || _isDisposed());
    final opened = await _platformCall('documents.platform.openFd', {
      'operationId': op.id,
      'handle': provider['handle'],
      'mode': mode,
    });
    DocumentsJson? copiedReceipt;
    try {
      op.check(_disposed || _isDisposed());
      final result = await _core('document.copy', {
        ...params,
        'operationId': op.id,
        'allowedRoots': op.roots,
        (mode == 'r' ? 'sourceFd' : 'targetFd'): opened['fd'],
        'maxBytes': _number(op.limits, 'maxBytes') - op.bytes,
      });
      op.bytes += _number(result, 'bytes');
      copiedReceipt = result;
      return result;
    } on InteropException catch (error) {
      op.bytes += _number(_map(error.details), 'bytesCopied');
      rethrow;
    } finally {
      try {
        await _platformCall('documents.platform.releaseFd', {
          'operationId': op.id,
          'fdLeaseId': opened['fdLeaseId'],
        }, cancellable: false);
      } catch (_) {
        // Preserve a prior copy failure. A successful write whose provider
        // close failed is not a confirmed save; never retry or delete its URI.
        if (copiedReceipt != null) {
          if (mode == 'r' && params['targetPath'] is String) {
            try {
              await _core('document.remove', {
                'path': params['targetPath'],
                'identity': copiedReceipt['identity'],
                'allowedRoots': op.roots,
              });
            } catch (_) {
              /* Leave a replacement untouched. */
            }
          }
          throw InteropException(
            mode == 'rw' ? 'result_unknown' : 'read_failed',
            '系统文档流关闭未确认，请核对已完成内容；不会自动重试。',
          );
        }
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
      await _local(op, 'mkdir', {'path': target});
      op.writing = true;
      op.directories++;
      final names = <String>{};
      for (final child in await _children(op, source)) {
        op.examine();
        try {
          final name = _name(_text(child, 'name'));
          if (!names.add(name)) {
            throw const InteropException('duplicate_name', '提供方返回同名项目，未合并或覆盖。');
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
    final parent = target.substring(0, target.lastIndexOf('/'));
    final space = await _local(op, 'localStat', {'path': parent});
    if (source['size'] is num &&
        _number(source, 'size') >
            _number(space, 'freeBytes') - _number(op.limits, 'reserveBytes')) {
      throw const InteropException('cache_full', '本机暂存空间不足，未下载此文件。');
    }
    final part = '$parent/.interop-${_id()}.part';
    DocumentsJson? identity;
    var committed = false;
    try {
      final result = await _copy(op, {'targetPath': part}, source, 'r');
      identity = _map(result['identity']);
      final after = await _metadata(op, source);
      if (!_sameProvider(source, after, directory: false) ||
          (source['size'] is num &&
              _number(result, 'bytes') != _number(source, 'size'))) {
        throw const InteropException('source_changed', '源文件在复制期间发生变化；未提交暂存文件。');
      }
      await _local(op, 'commit', {
        'partPath': part,
        'path': target,
        'identity': identity,
      });
      committed = true;
      op.files++;
      return true;
    } finally {
      if (!committed && identity != null) {
        try {
          await _core('document.remove', {
            'path': part,
            'identity': identity,
            'allowedRoots': op.roots,
          });
        } catch (_) {
          /* Never delete a replacement or unknown destination. */
        }
      }
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
          ? _text(
              await _platformCall('documents.platform.conflict', {
                'operationId': op.id,
                'name': name,
              }),
              'choice',
              'cancel',
            )
          : op.conflict;
      if (decision == 'cancel') {
        throw const InteropException('cancelled', '已取消保存；已完成内容保留。');
      }
      if (decision == 'skip') {
        op.skipped++;
        return null;
      }
      if (decision != 'keepBoth') {
        throw const InteropException('invalid_decision', '未确认同名项目处理方式。');
      }
      name = '$name (${_id()})';
    }
    final fresh = await _metadata(op, parent);
    if (fresh['directory'] != true || fresh['canCreate'] != true) {
      throw const InteropException('target_changed', '目标目录的新建能力已变化。');
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
      throw const InteropException(
        'result_unknown',
        '文档创建结果尚不确定，请核对目标目录；不会自动重试。',
      );
    }
    op.createdCount++;
    if (op.created.length < _number(op.limits, 'maxErrors')) {
      op.created.add({'uri': created['uri'], 'name': created['name']});
    }
    if (op.createdCount == 1) {
      op.uri = _text(created, 'uri');
      op.name = _text(created, 'name');
    }
    if (existing.any((child) => child['id'] == created['id']) ||
        created['name'] != name ||
        created['directory'] != directory) {
      throw const InteropException(
        'target_changed',
        '提供方返回已有文档、不同类型或修改了名称；未写入内容，请核对空项目。',
      );
    }
    if ((await _children(
          op,
          parent,
        )).where((child) => child['name'] == name).length !=
        1) {
      throw const InteropException(
        'target_changed',
        '创建期间出现同名竞争；未写入内容，请核对空项目。',
      );
    }
    if (name != requested &&
        op.renamed.length < _number(op.limits, 'maxErrors')) {
      op.renamed.add({
        'requested': requested,
        'name': name,
        'uri': created['uri'],
      });
    }
    return created;
  }

  Future<void> _exportNode(
    _Operation op,
    String source,
    DocumentsJson target,
    int depth,
    String relative, {
    DocumentsJson? expected,
  }) async {
    op.entry(depth, relative);
    final before = await _local(op, 'localStat', {'path': source});
    if (expected != null && !_sameLocal(expected, before)) {
      throw const InteropException('source_changed', '源项目在遍历后被替换，未读取替换内容。');
    }
    if (before['kind'] == 'directory') {
      op.directories++;
      final listing = await _local(op, 'localChildren', {'path': source});
      if (!_sameLocal(before, _map(listing['identity']))) {
        throw const InteropException('source_changed', '源目录在遍历前发生变化。');
      }
      for (final child in _maps(listing['entries'])) {
        op.examine();
        try {
          final name = _name(_text(child, 'name'));
          final path = _text(child, 'path');
          final stat = await _local(op, 'localStat', {'path': path});
          if (!_sameLocal(_map(child['identity']), stat)) {
            throw const InteropException('source_changed', '源项目在目录快照后发生变化。');
          }
          if (!['file', 'directory'].contains(stat['kind'])) {
            op.skip('$relative/$name', 'not_followed', '符号链接和特殊文件不会自动跟随。');
            continue;
          }
          final created = await _create(
            op,
            target,
            name,
            stat['kind'] == 'directory',
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
          op.record('$relative/${child['name']}', error);
        }
      }
      final after = await _local(op, 'localStat', {'path': source});
      if (!_sameLocal(before, after)) {
        op.error(relative, 'source_changed', '源目录在保存期间发生变化，已保存项目保留。');
      }
    } else {
      await _writeFile(op, source, target, relative);
    }
  }

  bool _sameLocal(DocumentsJson before, DocumentsJson after) => [
    'inode',
    'device',
    'modified',
    'modifiedNs',
    'size',
    'kind',
  ].every((key) => before[key] == after[key]);
  Future<void> _writeFile(
    _Operation op,
    String source,
    DocumentsJson target,
    String relative,
  ) async {
    op.examine();
    final before = await _local(op, 'localStat', {'path': source});
    if (before['kind'] != 'file') {
      throw const InteropException('source_changed', '源文件类型已变化，未跟随符号链接。');
    }
    final fresh = await _metadata(op, target);
    if (fresh['id'] != target['id'] ||
        fresh['directory'] == true ||
        fresh['virtual'] == true ||
        (fresh['size'] != null && fresh['size'] != 0)) {
      throw const InteropException('target_changed', '目标不是刚创建的空文档，未覆盖已有内容。');
    }
    if (fresh['canWrite'] != true) {
      throw const InteropException('write_unavailable', '提供方没有声明写入能力；本机暂存已保留。');
    }
    op.writing = true;
    await _copy(
      op,
      {'sourcePath': source, 'sourceIdentity': before},
      fresh,
      'rw',
    );
    final after = await _local(op, 'localStat', {'path': source});
    if (!_sameLocal(before, after)) {
      throw const InteropException('source_changed', '源文件在保存期间变化，目标可能包含部分内容。');
    }
    final saved = await _metadata(op, target);
    if (saved['size'] != null && saved['size'] != before['size']) {
      throw const InteropException(
        'result_unknown',
        '提供方返回保存长度不一致，请核对目标；本机暂存已保留。',
      );
    }
    op.files++;
  }
}

class _Operation {
  _Operation(this.id, this.command, this.conflict);
  final String id, command, conflict;
  DocumentsJson limits = {};
  List<String> roots = [];
  String cache = '', name = '';
  String? localPath, uri;
  bool cancelled = false, timedOut = false, writing = false, started = false;
  Timer? timer;
  final interrupted = Completer<void>();
  Future<void>? cancellationRequest;
  Future<T> wait<T>(Future<T> response) => Future.any<T>([
    response,
    interrupted.future.then<T>((_) {
      check(false);
      throw const InteropException('cancelled', '操作已取消。');
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
      throw const InteropException('timeout', '系统文档复制超过十分钟；已完成内容保留，请分批处理。');
    }
    if (cancelled || disposed) {
      throw const InteropException('cancelled', '操作已取消。');
    }
  }

  void examine() {
    check(false);
    if (++examined > _number(limits, 'maxEntries')) {
      throw const InteropException('tree_limit', '目录超过项目上限，请分批处理。');
    }
  }

  void entry(int depth, String path) {
    check(false);
    entries++;
    pathBytes += utf8.encode(path).length;
    if (entries > _number(limits, 'maxEntries') ||
        depth > _number(limits, 'maxDepth') ||
        pathBytes > _number(limits, 'maxPathBytes')) {
      throw const InteropException('tree_limit', '目录超过项目、深度或路径上限，请分批处理。');
    }
  }

  void error(String path, String code, String message) {
    errorsCount++;
    if (errors.length < _number(limits, 'maxErrors', 1000)) {
      errors.add({'path': path, 'code': code, 'message': message});
    }
  }

  void skip(String path, String code, String message) {
    skipped++;
    error(path, code, message);
  }

  void record(String path, Object failure) {
    if (cancelled ||
        failure is InteropException &&
            [
              'cancelled',
              'tree_limit',
              'byte_limit',
              'timeout',
              'result_unknown',
            ].contains(failure.code)) {
      throw failure;
    }
    skip(
      path,
      failure is InteropException ? failure.code : 'documents_error',
      '$failure',
    );
  }

  DocumentsJson response(String status) => {
    'operationId': id,
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
