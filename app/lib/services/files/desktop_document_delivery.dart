import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/models/document_limits.dart';

typedef DesktopSavePicker = Future<String?> Function(String name, String kind);

/// 桌面位置选择后的写入端；持久准入及未知结果仍由 SystemDeliveryCoordinator 统一拥有。
final class DesktopDocumentDelivery {
  static const scopeKey = 'scrcpy-connect-desktop-documents';
  static LocalFiles? _recoveringFiles;
  static Future<LocalFileScope>? _recoveringScope;
  static Future<void>? _recovery;

  /// 同 owner 重开先让原生排空旧 isolate 的复制；仅在关闭确认后移交新操作。
  static Future<void> recover(
    Future<LocalFiles> Function() files,
    String recoveryRoot,
  ) => _recovery ??= Future<void>.microtask(() async {
    _recoveringFiles ??= await files();
    _recoveringScope ??= _recoveringFiles!
        .openScope(scopeKey: scopeKey, allowedRoots: [_bytes(recoveryRoot)])
        .catchError((Object error, StackTrace stack) {
          _recoveringScope = null;
          Error.throwWithStackTrace(error, stack);
        });
    final scope = await _recoveringScope!;
    await scope.close();
    _recoveringScope = null;
    await _recoveringFiles!.close();
    _recoveringFiles = null;
  }).whenComplete(() => _recovery = null);

  DesktopDocumentDelivery({
    required this.files,
    required this.emit,
    DesktopSavePicker? pick,
    this.limits = const DocumentLimits(),
  }) : pick = pick ?? _pick;
  final Future<LocalFiles> Function() files;
  final void Function(Json) emit;
  final DesktopSavePicker pick;
  final DocumentLimits limits;
  _DesktopSave? _active;
  bool _closed = false;

  static Future<String?> _pick(String name, String kind) async {
    // saveFile 的宿主实现会先写 bytes；这里只选择位置，目标发布必须等持久准入并由 LocalFiles 独占完成。
    final parent = await FilePicker.getDirectoryPath(
      dialogTitle: '选择保存 $name 的位置',
    );
    return parent == null ? null : p.join(parent, name);
  }

  Future<Json> request(String command, Json params) async {
    final active = _active;
    final matches = active?.id == params['operationId'];
    if (command == 'documents.conflict.get') {
      return {'pending': matches ? active?.pending : null};
    }
    if (command == 'documents.conflict.resolve') {
      final choice = params['choice'];
      if (!matches ||
          active?.pending?['conflictId'] != params['conflictId'] ||
          active?.reply == null) {
        return {'resolved': false};
      }
      if (!['keepBoth', 'skip', 'cancel'].contains(choice)) {
        throw const ApplicationCommandException(
          'invalid_decision',
          '请选择保留两份、跳过或取消。',
        );
      }
      if (params['applyToRemaining'] == true && choice != 'cancel') {
        active!.policy = choice as String;
      }
      active!.reply!.complete(choice as String);
      active.reply = null;
      return {'resolved': true};
    }
    if (command == 'documents.cancel') {
      if (matches) active!.cancel();
      return {'cancelled': matches};
    }
    throw const ApplicationCommandException(
      'platform_unavailable',
      '此桌面入口仅支持保存本机原件。',
    );
  }

  Future<Json> write(Json params) async {
    if (_closed || _active != null) {
      throw const ApplicationCommandException(
        'documents_busy',
        '上次桌面保存尚未结束或未确认清理。',
      );
    }
    final op = _DesktopSave(params['operationId'] as String);
    _active = op;
    String status = 'failed';
    try {
      final source = _absolute(params['localPath']);
      final name = params['name'] as String;
      final kind = params['kind'] as String;
      if (!['file', 'directory'].contains(kind) || !_safeName(name)) {
        throw const ApplicationCommandException(
          'invalid_argument',
          '原件类型或名称无效。',
        );
      }
      final chosen = await Future.any([
        pick(name, kind),
        op.cancelled.future.then<String?>((_) => null),
      ]);
      op.check();
      if (chosen == null) return op.result('cancelled');
      var destination = _absolute(chosen);
      if (destination == source || p.isWithin(source, destination)) {
        throw const ApplicationCommandException(
          'invalid_argument',
          '保存位置不能位于本机原件内部。',
        );
      }
      op.destination = destination;
      op.scope = await (await files()).openScope(
        scopeKey: scopeKey,
        allowedRoots: [
          _bytes(p.dirname(source)),
          _bytes(p.dirname(destination)),
        ],
      );
      op.timer = Timer(limits.timeout, op.cancel);
      op.check();
      final stat = await op.scope!.stat(_bytes(source));
      if (stat.identity.kind.name != kind) {
        throw const ApplicationCommandException(
          'source_changed',
          '原件类型已变化，未写入目标。',
        );
      }
      destination = await _copyNode(op, source, destination, 0) ?? destination;
      op.destination = destination;
      op.check();
      status = op.skipped > 0 ? 'partial' : 'saved';
    } catch (error) {
      final uncertain =
          op.publishing ||
          error is LocalFileException &&
              [
                LocalFileErrorCode.resultUnknown,
                LocalFileErrorCode.cleanupUnconfirmed,
              ].contains(error.code);
      final cancelled =
          op.cancelled.isCompleted ||
          error is ApplicationCommandException && error.code == 'cancelled';
      status = uncertain
          ? 'result_unknown'
          : cancelled
          ? 'cancelled'
          : op.written
          ? 'partial'
          : 'failed';
      op.errors.add({'message': '$error'});
    } finally {
      op.timer?.cancel();
      op.reply?.complete('cancel');
      op.reply = null;
      op.pending = null;
      emit({'operationId': op.id, 'pending': null});
      try {
        await op.scope?.close();
        _active = null;
      } catch (error) {
        status = 'result_unknown';
        op.errors.add({'message': '桌面复制资源尚未确认关闭：$error'});
      }
      op.finished.complete();
    }
    return op.result(status);
  }

  Future<String?> _target(_DesktopSave op, String destination) async {
    op.check();
    try {
      await op.scope!.stat(_bytes(destination));
    } on LocalFileException catch (error) {
      if (error.code == LocalFileErrorCode.notFound) return destination;
      rethrow;
    }
    var decision = op.policy;
    if (decision == 'ask') {
      final reply = Completer<String>();
      op.reply = reply;
      op.pending = {
        'operationId': op.id,
        'conflictId': _nonce(),
        'name': p.basename(destination),
        'choices': ['keepBoth', 'skip', 'cancel'],
        'replacementSupported': false,
        'replacementUnavailableReason': '已有文件不会覆盖；可保留两份、跳过或取消。',
      };
      emit({'operationId': op.id, 'pending': op.pending});
      try {
        decision = await Future.any([
          reply.future,
          op.cancelled.future.then((_) => 'cancel'),
        ]);
      } finally {
        op.pending = null;
        op.reply = null;
        emit({'operationId': op.id, 'pending': null});
      }
    }
    op.check();
    if (decision == 'cancel') {
      throw const ApplicationCommandException('cancelled', '已取消保存，已有内容保留。');
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
    final extension = p.extension(destination);
    return p.join(
      p.dirname(destination),
      '${p.basenameWithoutExtension(destination)} (${_nonce()})$extension',
    );
  }

  Future<String?> _copyNode(
    _DesktopSave op,
    String source,
    String requested,
    int depth,
  ) async {
    op.check();
    op.entries++;
    op.pathBytes += utf8.encode(source).length + utf8.encode(requested).length;
    if (depth > limits.maxDepth ||
        op.entries > limits.maxEntries ||
        op.pathBytes > limits.maxPathBytes) {
      throw const ApplicationCommandException(
        'tree_limit',
        '原件超过目录、深度或路径上限，请分批处理。',
      );
    }
    final scope = op.scope!;
    final before = (await scope.stat(_bytes(source))).identity;
    var destination = await _target(op, requested);
    if (destination == null) return null;
    if (before.kind == LocalFileKind.directory) {
      op.check();
      op.publishing = true;
      await scope.mkdir(_bytes(destination), exclusive: true);
      op.publishing = false;
      op.directories++;
      op.written = true;
      final children = await scope.list(
        _bytes(source),
        maxEntries: limits.maxEntries - op.entries + 1,
      );
      for (final child in children.entries) {
        final name = utf8.decode(child.name);
        if (!_safeName(name)) {
          throw const ApplicationCommandException(
            'invalid_path',
            '目录包含无法安全交付的名称。',
          );
        }
        await _copyNode(
          op,
          p.join(source, name),
          p.join(destination, name),
          depth + 1,
        );
      }
    } else if (before.kind == LocalFileKind.file) {
      if (before.size > BigInt.from(limits.maxBytes - op.bytes)) {
        throw const ApplicationCommandException(
          'byte_limit',
          '原件超过本次系统保存上限，请分批处理。',
        );
      }
      final free = (await scope.stat(_bytes(p.dirname(destination)))).freeBytes;
      if (free == null ||
          free < before.size + BigInt.from(limits.reserveBytes)) {
        throw const ApplicationCommandException(
          'storage_full',
          '所选位置可用空间不足或无法核验，未写入文件。',
        );
      }
      op.check();
      final copy = await scope.copy(
        source: LocalFileEndpoint.path(_bytes(source)),
        target: LocalFileEndpoint.part(
          _bytes(p.join(p.dirname(destination), '.interop-${_nonce()}.part')),
        ),
        maxBytes: limits.maxBytes - op.bytes,
        timeout: limits.timeout,
        expectedSource: before,
        cancellation: op.cancellation,
      );
      try {
        op.check();
        for (var attempt = 0; ; attempt++) {
          op.publishing = true;
          try {
            await scope.commit(
              copy,
              _bytes(destination!),
              expectedIdentity: copy.identity,
            );
            op.publishing = false;
            break;
          } on LocalFileException catch (error) {
            if (error.code != LocalFileErrorCode.conflict) rethrow;
            op.publishing = false;
            if (attempt >= 15) rethrow;
            destination = await _target(op, destination!);
            if (destination == null) return null;
          }
        }
        op.files++;
        op.bytes += copy.bytes;
        op.written = true;
      } finally {
        await copy.close();
      }
    } else {
      throw const ApplicationCommandException(
        'unsupported_source',
        '符号链接及特殊文件不会保存。',
      );
    }
    final after = (await scope.stat(_bytes(source))).identity;
    if (before.device != after.device ||
        before.inode != after.inode ||
        before.size != after.size ||
        before.modifiedSeconds != after.modifiedSeconds ||
        before.modifiedNanos != after.modifiedNanos ||
        before.kind != after.kind) {
      throw const ApplicationCommandException(
        'source_changed',
        '复制期间原件发生变化，请核对已保存内容。',
      );
    }
    return destination;
  }

  Future<void> dispose() async {
    _closed = true;
    final op = _active;
    if (op == null) return;
    op.cancel();
    await op.finished.future;
    await op.scope?.close();
    _active = null;
  }
}

String _nonce() => List.generate(
  12,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
Uint8List _bytes(String path) => Uint8List.fromList(utf8.encode(path));
String _absolute(Object? path) {
  if (path is! String ||
      !p.isAbsolute(path) ||
      path.contains('\u0000') ||
      p.split(path).any((part) => part == '.' || part == '..')) {
    throw const ApplicationCommandException(
      'invalid_argument',
      '请选择有效的绝对文件位置。',
    );
  }
  return p.normalize(path);
}

bool _safeName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains(RegExp(r'[/\\\x00\r\n]'));

final class _DesktopSave {
  _DesktopSave(this.id);
  final String id;
  final cancelled = Completer<void>(), finished = Completer<void>();
  final cancellation = AdbCancellation();
  LocalFileScope? scope;
  Timer? timer;
  Json? pending;
  Completer<String>? reply;
  String policy = 'ask';
  String? destination;
  bool publishing = false, written = false;
  int bytes = 0,
      files = 0,
      directories = 0,
      skipped = 0,
      entries = 0,
      pathBytes = 0;
  final errors = <Json>[];
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    cancellation.cancel();
  }

  void check() {
    if (cancelled.isCompleted) {
      throw const ApplicationCommandException('cancelled', '已取消本次桌面保存。');
    }
  }

  Json result(String status) => {
    'status': status,
    'operationId': id,
    if (destination != null) 'name': p.basename(destination!),
    'localPath': destination,
    'bytes': bytes,
    'files': files,
    'directories': directories,
    'skipped': skipped,
    'errors': errors,
    'partialDestinationPossible':
        status == 'result_unknown' || written && status != 'saved',
    'cacheRetained': true,
  };
}
