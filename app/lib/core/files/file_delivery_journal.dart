import 'system_documents.dart';

import 'package:scrcpy_connect/core/content/cache_status.dart';

import 'file_delivery.dart';

import 'package:scrcpy_connect/core/content/content_cache_gate.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/application/request_failure.dart';

typedef _Json = Map<String, dynamic>;

/// 保存操作的持久准入所有者；原件身份、操作墓碑和未知结果不随页面释放。
final class FileDeliveryJournal implements FileDeliveryRecords {
  FileDeliveryJournal._(
    this._root,
    this._records,
    this._operations,
    this._cacheGate,
    this._validateSource,
  );
  final ContentCacheGate? _cacheGate;
  final Future<void> Function(String)? _validateSource;

  static const _maxRecords = 1024;
  static const _maxOperations = 16384;
  static const _maxBytes = 4 * 1024 * 1024;
  final Directory _root;
  Map<String, _Json> _records;
  Set<String> _operations;
  Future<void> _pending = Future.value();
  File get _file => File(p.join(_root.path, 'deliveries.json'));

  /// 只接受完整的 v1 账本；重开的 pending 先可靠保存为 unknown，绝不重放保存。
  static Future<FileDeliveryJournal> open(
    Directory root, {
    ContentCacheGate? cacheGate,
    Future<void> Function(String)? validateSource,
  }) async {
    final records = <String, _Json>{};
    final operations = <String>{};
    final file = File(p.join(root.path, 'deliveries.json'));
    final bytes = await _read(file);
    if (bytes != null) {
      try {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! _Json ||
            !_fields(value, const {'version', 'records', 'operations'}) ||
            value['version'] is! int ||
            value['version'] != 1 ||
            value['records'] is! _Json ||
            value['operations'] is! List) {
          throw const FormatException();
        }
        for (final operation in value['operations'] as List) {
          if (!_validText(operation, 256)) throw const FormatException();
          operations.add(operation as String);
        }
        final stored = value['records'] as _Json;
        if (stored.length > _maxRecords || operations.length > _maxOperations) {
          throw const FormatException();
        }
        for (final entry in stored.entries) {
          final record = entry.value;
          if (record is! _Json ||
              !_fields(record, const {
                'operationId',
                'sourceId',
                'localPath',
                'kind',
                'name',
                'status',
                'result',
                'updatedAt',
              }) ||
              _key(record) != entry.key ||
              !_validText(record['operationId'], 256) ||
              !_validText(record['name'], 1024) ||
              !operations.contains(record['operationId']) ||
              !_unsigned(record['updatedAt'])) {
            throw const FormatException();
          }
          if (record['status'] == 'pending') {
            if (record['result'] != null) throw const FormatException();
          } else {
            final clean = _cleanResult(record['result']);
            if (record['status'] != clean['status'] ||
                !_same(clean, record['result'])) {
              throw const FormatException();
            }
          }
          records[entry.key] = record;
        }
      } on Object {
        throw const RequestFailure(
          'delivery_storage_invalid',
          '保存记录格式或内容无效，原文件保留。',
        );
      }
    }
    final journal = FileDeliveryJournal._(
      root,
      records,
      operations,
      cacheGate,
      validateSource,
    );
    var changed = false;
    for (final record in records.values) {
      if (record['status'] == 'pending') {
        record['status'] = 'result_unknown';
        record['result'] = {
          'status': 'result_unknown',
          'partialDestinationPossible': true,
          'cacheRetained': true,
        };
        record['updatedAt'] = _now();
        changed = true;
      }
    }
    if (changed) await journal._write(records, operations);
    return journal;
  }

  /// 与保存操作共用提交队列；缓存清理不能越过尚未落盘的准入或完成回执。
  Future<List<String>> get protectedPaths => _serial(
    () async => [
      for (final key in _records.keys.toList()..sort())
        if (_records[key]!['status'] == 'pending' ||
            _records[key]!['status'] == 'result_unknown' ||
            (_records[key]!['result']
                    as _Json?)?['partialDestinationPossible'] ==
                true)
          _records[key]!['localPath'] as String,
    ],
  );

  /// 已有保护记录的只读呈现，不创建新交付或重新获得系统授权。
  Future<List<CacheProtection>> get protectedSources => _serial(
    () async => [
      for (final record in _records.values)
        if (record['status'] == 'pending' ||
            record['status'] == 'result_unknown' ||
            (record['result'] as _Json?)?['partialDestinationPossible'] == true)
          CacheProtection(
            path: record['localPath'] as String,
            name: record['name'] as String?,
            sourceLabel: record['sourceId'] == 'local' ? '本机原件' : '取回的手机原件',
            reason: record['status'] == 'pending'
                ? '系统保存仍在执行'
                : '系统保存结果待核对，原件继续保留',
          ),
    ],
  );

  @override
  Future<FileDeliveryRecord?> read(DocumentSource source) => _commit(() async {
    final record = _records[_sourceKey(source)];
    return record == null ? null : FileDeliveryRecord.fromJson(record);
  });

  @override
  Future<void> begin(FileDeliveryPlan plan) => _commit(() async {
    await _validateSource?.call(
      _checkedText(plan.source.localPath, 'localPath', 4096),
    );
    await _begin(plan);
  });

  @override
  Future<FileDeliveryRecord> finish(
    FileDeliveryPlan plan,
    DocumentOutcome result,
  ) {
    final captured = result.copyWith(errors: List.unmodifiable(result.errors));
    return _commit(() => _finish(plan, captured));
  }

  Future<T> _commit<T>(Future<T> Function() operation) {
    Future<T> commit() => _serial(operation);
    // 先缓存 gate 再日志队列；清理快照与 pending 提交之间没有删除窗口。
    return _cacheGate == null ? commit() : _cacheGate.runExclusive(commit);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // 一次失败不毒化队列；后续只读核验和修复后的显式重试仍可执行。
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<FileDeliveryRecord> _finish(
    FileDeliveryPlan plan,
    DocumentOutcome outcome,
  ) async {
    final key = _sourceKey(plan.source);
    final previous = _records[key];
    final operation = _checkedText(plan.operationId, 'operationId', 256);
    if (previous == null) {
      throw const RequestFailure('delivery_not_found', '找不到本次保存记录。');
    }
    if (previous['operationId'] != operation) {
      throw const RequestFailure('delivery_operation_mismatch', '保存回执不属于当前操作。');
    }
    // v1 持久契约的有界回执适配，保守保留未知结果与原件保护。
    final result = _cleanResult(outcome.toJson());
    if (previous['status'] != 'pending') {
      if (_same(previous['result'], result)) {
        return FileDeliveryRecord.fromJson(previous);
      }
      throw const RequestFailure('delivery_result_conflict', '已有保存终态，请核对目标内容。');
    }
    final record = {
      ...previous,
      'status': result['status'],
      'result': result,
      'updatedAt': _now(),
    };
    final records = {..._records, key: record};
    await _write(records, _operations);
    _records = records;
    return FileDeliveryRecord.fromJson(record);
  }

  Future<void> _begin(FileDeliveryPlan plan) async {
    final key = _sourceKey(plan.source);
    final previous = _records[key];
    final record = <String, dynamic>{
      'operationId': _checkedText(plan.operationId, 'operationId', 256),
      'sourceId': plan.source.sourceId,
      'localPath': plan.source.localPath,
      'kind': plan.source.kind.name,
      'name': _checkedText(plan.name, 'name', 1024),
      'status': 'pending',
      'result': null,
      'updatedAt': _now(),
    };
    if (previous != null) {
      if (previous['status'] == 'pending') {
        throw const RequestFailure('delivery_busy', '此内容正在保存，请等待结果。');
      }
      if (previous['status'] == 'saved' &&
          plan.additionalCopyOfOperationId != previous['operationId']) {
        throw const RequestFailure('delivery_saved', '此内容已经保存。');
      }
      if ((previous['status'] == 'result_unknown' ||
              (previous['result'] as _Json)['partialDestinationPossible'] ==
                  true) &&
          plan.reviewedOperationId != previous['operationId']) {
        throw const RequestFailure(
          'delivery_review_required',
          '请先核对上次目标，再明确重新保存。',
        );
      }
    }
    final operation = record['operationId'] as String;
    if (_operations.contains(operation)) {
      throw const RequestFailure('delivery_operation_reused', '重新保存需要新的操作标识。');
    }
    if (previous == null && _records.length >= _maxRecords ||
        _operations.length >= _maxOperations) {
      throw const RequestFailure('delivery_capacity', '保存记录已满，请保留当前缓存。');
    }
    final records = {..._records, key: record};
    final operations = {..._operations, operation};
    await _write(records, operations);
    _records = records;
    _operations = operations;
  }

  Future<void> _write(
    Map<String, _Json> records,
    Set<String> operations,
  ) async {
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'records': {
          for (final key in records.keys.toList()..sort()) key: records[key],
        },
        'operations': operations.toList()..sort(),
      }),
    );
    // pending 必须为崩溃恢复时增加的保守终态预留空间。
    final reserve =
        records.values.where((record) => record['status'] == 'pending').length *
        256;
    if (bytes.length + reserve > _maxBytes) {
      throw const RequestFailure('delivery_capacity', '保存记录已满，请保留当前缓存。');
    }
    Directory? temporary;
    try {
      await _root.create(recursive: true);
      // 同目录私有临时目录保证同一文件系统；失败只清理本次所有者的临时产物。
      temporary = await _root.createTemp('.delivery-');
      final file = File(p.join(temporary.path, 'ledger'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(_file.path);
    } on FileSystemException catch (error) {
      throw RequestFailure('io_error', error.message);
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete(recursive: true);
        } on FileSystemException {
          /* 清理失败不改写已成功提交的保存回执。 */
        }
      }
    }
  }

  static Future<Uint8List?> _read(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final bytes = BytesBuilder(copy: false);
      while (bytes.length <= _maxBytes) {
        final chunk = await handle.read(_maxBytes + 1 - bytes.length);
        if (chunk.isEmpty) break;
        bytes.add(chunk);
      }
      if (bytes.length > _maxBytes) {
        throw const RequestFailure(
          'delivery_storage_invalid',
          '保存记录超出容量，原文件保留。',
        );
      }
      return bytes.takeBytes();
    } on FileSystemException catch (error) {
      if (handle == null &&
          (error.osError?.errorCode == 2 ||
              Platform.isWindows && error.osError?.errorCode == 3)) {
        return null;
      }
      throw RequestFailure('io_error', error.message);
    } finally {
      await handle?.close();
    }
  }

  static bool _fields(_Json value, Set<String> fields) =>
      value.length == fields.length && value.keys.every(fields.contains);
  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static bool _unsigned(Object? value) => value is int && value >= 0;
  static bool _validText(Object? value, int limit, {bool empty = false}) =>
      value is String &&
      (empty || value.isNotEmpty) &&
      !value.contains('\u0000') &&
      utf8.encode(value).length <= limit &&
      utf8.decode(utf8.encode(value)) == value;
  static String _text(_Json params, String field, int limit) {
    final value = params[field];
    if (!_validText(value, limit)) {
      throw RequestFailure('invalid_argument', '缺少或无效的保存字段：$field');
    }
    return value as String;
  }

  static String _key(_Json params) {
    final source = _text(params, 'sourceId', 256),
        path = _text(params, 'localPath', 4096),
        kind = _text(params, 'kind', 32);
    if (kind != 'file' && kind != 'directory') {
      throw const RequestFailure('invalid_argument', '保存类型无效。');
    }
    return jsonEncode([source, path, kind]);
  }

  static String _sourceKey(DocumentSource source) => jsonEncode([
    _checkedText(source.sourceId, 'sourceId', 256),
    _checkedText(source.localPath, 'localPath', 4096),
    source.kind.name,
  ]);
  static String _checkedText(String value, String field, int limit) {
    if (!_validText(value, limit)) {
      throw RequestFailure('invalid_argument', '缺少或无效的保存字段：$field');
    }
    return value;
  }

  static bool _same(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.entries.every(
            (entry) =>
                right.containsKey(entry.key) &&
                _same(entry.value, right[entry.key]),
          );
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List.generate(
            left.length,
            (index) => _same(left[index], right[index]),
          ).every((same) => same);
    }
    return left == right;
  }

  static _Json _cleanResult(Object? input) {
    if (input is! _Json) {
      throw const RequestFailure('invalid_argument', '保存结果必须是对象。');
    }
    final status = switch (input['status']) {
      'resultUnknown' || 'result_unknown' => 'result_unknown',
      final String status
          when const {
            'saved',
            'partial',
            'failed',
            'cancelled',
          }.contains(status) =>
        status,
      _ => throw const RequestFailure('invalid_argument', '保存结果状态无效。'),
    };
    final result = <String, dynamic>{'status': status};
    if (input.containsKey('name')) {
      if (!_validText(input['name'], 1024, empty: true)) {
        throw const RequestFailure('invalid_argument', '保存结果名称无效。');
      }
      result['name'] = input['name'];
    }
    for (final field in ['files', 'directories', 'bytes', 'skipped']) {
      if (input.containsKey(field)) {
        if (!_unsigned(input[field])) {
          throw const RequestFailure('invalid_argument', '保存结果计数无效。');
        }
        result[field] = input[field];
      }
    }
    for (final field in ['partialDestinationPossible', 'cacheRetained']) {
      if (input.containsKey(field)) {
        if (input[field] is! bool) {
          throw const RequestFailure('invalid_argument', '保存结果标记无效。');
        }
        result[field] = input[field];
      }
    }
    if (status == 'result_unknown' ||
        status != 'saved' &&
            !result.containsKey('partialDestinationPossible')) {
      result['partialDestinationPossible'] = true;
    }
    if (input.containsKey('errors')) {
      final errors = input['errors'];
      if (errors is! List) {
        throw const RequestFailure('invalid_argument', '保存错误明细无效。');
      }
      result['errors'] = [
        for (final error in errors.take(100)) _cleanError(error),
      ];
    }
    return result;
  }

  static _Json _cleanError(Object? error) {
    if (error is! _Json) {
      throw const RequestFailure('invalid_argument', '保存错误明细必须是对象。');
    }
    final result = <String, dynamic>{};
    for (final (field, limit) in [
      ('path', 4096),
      ('code', 256),
      ('message', 4096),
    ]) {
      if (!error.containsKey(field)) continue;
      final value = error[field];
      if (!_validText(value, 0x7fffffffffffffff, empty: true)) {
        throw const RequestFailure('invalid_argument', '保存错误字段无效。');
      }
      final bytes = utf8.encode(value as String);
      var end = bytes.length > limit ? limit : bytes.length;
      while (end < bytes.length && bytes[end] & 0xc0 == 0x80) {
        end--;
      }
      result[field] = utf8.decode(bytes.sublist(0, end));
    }
    return result;
  }
}
