import 'dart:math';

import 'package:scrcpy_connect/models/application_request.dart';

import 'package:scrcpy_connect/services/file_document_service.dart';

/// provider 可见写入前，先通过持久日志准入；请求保存的页面退出后仍记录完成结果。
class FileExportService {
  FileExportService({
    required this._applicationRequest,
    required this._write,
    this._cancelWrite,
    this._onChanged,
  });

  final DocumentsRequest _applicationRequest;
  final Future<DocumentsJson> Function(DocumentsJson) _write;
  final Future<DocumentsJson> Function(String)? _cancelWrite;
  final void Function(DocumentsJson)? _onChanged;
  final _pending = <String, _PendingSave>{};
  bool _closed = false;

  Future<DocumentsJson?> cancel(String operationId) async {
    final pending = _pending[operationId];
    if (pending == null) return null;
    pending.cancelled = true;
    if (pending.started) await _cancelWrite?.call(operationId);
    return {'cancelled': true, 'operationId': operationId};
  }

  void close() {
    _closed = true;
    for (final pending in _pending.values) {
      pending.cancelled = true;
    }
  }

  Future<DocumentsJson> save(DocumentsJson params) async {
    if (_closed) {
      throw const RequestFailure('cancelled', '系统保存已停止。');
    }
    final path = params['localPath'];
    if (path is! String || path.isEmpty) {
      throw const RequestFailure('invalid_path', '缺少本机原件位置。');
    }
    final random = Random.secure();
    final operationId =
        params['operationId'] ??
        'documents-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    if (operationId is! String ||
        operationId.isEmpty ||
        _pending.containsKey(operationId)) {
      throw const RequestFailure('delivery_operation_reused', '请使用新的系统保存操作标识。');
    }
    final source = <String, dynamic>{
      'sourceId': params['sourceId'] ?? 'local',
      'localPath': path,
      'kind': params['kind'] ?? 'file',
    };
    final pending = _PendingSave();
    _pending[operationId] = pending;
    try {
      await _applicationRequest('delivery.begin', {
        ...source,
        'operationId': operationId,
        'name': params['name'] ?? path.split('/').last,
        if (params['reviewedOperationId'] != null)
          'reviewedOperationId': params['reviewedOperationId'],
        if (params['additionalCopyOfOperationId'] != null)
          'additionalCopyOfOperationId': params['additionalCopyOfOperationId'],
      });
      _onChanged?.call(source);
      DocumentsJson result;
      if (pending.cancelled || _closed) {
        result = {
          'status': 'cancelled',
          'cacheRetained': true,
          'partialDestinationPossible': false,
        };
      } else {
        pending.started = true;
        try {
          result = await _write({
            ...params,
            ...source,
            'operationId': operationId,
          });
        } catch (error) {
          // 这些协调器拒绝发生在选择器创建和复制之前。
          final rejectedBeforeWrite =
              error is RequestFailure &&
              [
                'documents_busy',
                'operation_id_reused',
                'invalid_argument',
              ].contains(error.code);
          result = {
            'status': rejectedBeforeWrite ? 'failed' : 'result_unknown',
            'cacheRetained': true,
            'partialDestinationPossible': !rejectedBeforeWrite,
            'errors': [
              {'message': '$error'},
            ],
          };
        }
      }
      DocumentsJson receipt;
      final identity = {...source, 'operationId': operationId};
      try {
        receipt = await _applicationRequest('delivery.finish', {
          ...identity,
          'result': result,
        });
      } catch (error, stack) {
        // 有界日志可能拒绝较大 provider 回执；保存最小不确定标记，只重试元数据，不重复写入。
        try {
          receipt = await _applicationRequest('delivery.finish', {
            ...identity,
            'result': {
              'status': 'result_unknown',
              'cacheRetained': true,
              'partialDestinationPossible': true,
            },
          });
        } catch (_) {
          Error.throwWithStackTrace(error, stack);
        }
      }
      final record = receipt['record'];
      if (record is! Map<Object?, Object?> ||
          record['result'] is! Map<Object?, Object?>) {
        throw const RequestFailure(
          'delivery_receipt_missing',
          '系统保存结果尚未可靠记录，请重新核验。',
        );
      }
      _onChanged?.call(source);
      return Map<String, dynamic>.from(
        record['result'] as Map<Object?, Object?>,
      );
    } finally {
      _pending.remove(operationId);
    }
  }
}

class _PendingSave {
  bool cancelled = false;
  bool started = false;
}
