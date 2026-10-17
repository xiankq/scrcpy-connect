import 'dart:math';

import '../interop_exception.dart';
import 'documents_coordinator.dart';

/// The durable journal admits a system write before a provider can see it.
/// It records completion even after the page that requested the save is gone.
class SystemDelivery {
  SystemDelivery({
    required this._core,
    required this._write,
    this._cancelWrite,
    this._onChanged,
  });

  final DocumentsRequest _core;
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
    if (_closed) throw const InteropException('cancelled', '系统保存已停止。');
    final path = params['localPath'];
    if (path is! String || path.isEmpty) {
      throw const InteropException('invalid_path', '缺少本机原件位置。');
    }
    final random = Random.secure();
    final operationId =
        params['operationId'] ??
        'documents-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    if (operationId is! String ||
        operationId.isEmpty ||
        _pending.containsKey(operationId)) {
      throw const InteropException(
        'delivery_operation_reused',
        '请使用新的系统保存操作标识。',
      );
    }
    final source = <String, dynamic>{
      'sourceId': params['sourceId'] ?? 'local',
      'localPath': path,
      'kind': params['kind'] ?? 'file',
    };
    final pending = _PendingSave();
    _pending[operationId] = pending;
    try {
      await _core('delivery.begin', {
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
          // These coordinator rejections precede picker creation and copying.
          final rejectedBeforeWrite =
              error is InteropException &&
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
        receipt = await _core('delivery.finish', {
          ...identity,
          'result': result,
        });
      } catch (error, stack) {
        // A bounded journal may reject a large provider receipt. Persist a
        // minimal uncertainty marker; retry only metadata, never the write.
        try {
          receipt = await _core('delivery.finish', {
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
        throw const InteropException(
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
