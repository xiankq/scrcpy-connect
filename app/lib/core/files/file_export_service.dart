import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_delivery.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';

/// provider 可见写入前，先通过持久日志准入；请求保存的页面退出后仍记录完成结果。
class FileExportService {
  FileExportService({
    required this._deliveries,
    required this._write,
    this._cancelWrite,
    this._onChanged,
  });

  final FileDeliveryRecords _deliveries;
  final Future<DocumentOutcome> Function(DocumentExportPlan) _write;
  final Future<void> Function(String)? _cancelWrite;
  final void Function(DocumentSource)? _onChanged;
  final _pending = <String, _PendingSave>{};
  bool _closed = false;

  Future<bool> cancel(String operationId) async {
    final pending = _pending[operationId];
    if (pending == null) return false;
    pending.cancelled = true;
    if (pending.started) await _cancelWrite?.call(operationId);
    return true;
  }

  void close() {
    _closed = true;
    for (final pending in _pending.values) {
      pending.cancelled = true;
    }
  }

  Future<DocumentOutcome> save(DocumentExportPlan request) async {
    if (_closed) throw const RequestFailure('cancelled', '系统保存已停止。');
    final operationId = request.operationId;
    if (operationId.isEmpty || _pending.containsKey(operationId)) {
      throw const RequestFailure('delivery_operation_reused', '请使用新的系统保存操作标识。');
    }
    final plan = FileDeliveryPlan(
      operationId: operationId,
      source: request.source,
      name: request.name,
      reviewedOperationId: request.reviewedOperationId,
      additionalCopyOfOperationId: request.additionalCopyOfOperationId,
    );
    final source = plan.source;
    final pending = _PendingSave();
    _pending[operationId] = pending;
    try {
      await _deliveries.begin(plan);
      _onChanged?.call(source);
      DocumentOutcome result;
      if (pending.cancelled || _closed) {
        result = const DocumentOutcome(
          status: .cancelled,
          cacheRetained: true,
          partialDestinationPossible: false,
        );
      } else {
        pending.started = true;
        try {
          result = await _write(request);
        } catch (error) {
          // 这些协调器拒绝发生在选择器创建和复制之前。
          final rejectedBeforeWrite =
              error is RequestFailure &&
              [
                'documents_busy',
                'operation_id_reused',
                'invalid_argument',
              ].contains(error.code);
          result = DocumentOutcome(
            status: rejectedBeforeWrite ? .failed : .resultUnknown,
            cacheRetained: true,
            partialDestinationPossible: !rejectedBeforeWrite,
            errors: [DocumentIssue(message: '$error')],
          );
        }
      }
      FileDeliveryRecord receipt;
      try {
        receipt = await _deliveries.finish(plan, result);
      } catch (error, stack) {
        // 有界日志可能拒绝较大 provider 回执；保存最小不确定标记，只重试元数据，不重复写入。
        try {
          receipt = await _deliveries.finish(
            plan,
            const DocumentOutcome(
              status: .resultUnknown,
              cacheRetained: true,
              partialDestinationPossible: true,
            ),
          );
        } catch (_) {
          Error.throwWithStackTrace(error, stack);
        }
      }
      final resultReceipt = receipt.result;
      if (resultReceipt == null) {
        throw const RequestFailure(
          'delivery_receipt_missing',
          '系统保存结果尚未可靠记录，请重新核验。',
        );
      }
      _onChanged?.call(source);
      return resultReceipt;
    } finally {
      _pending.remove(operationId);
    }
  }
}

class _PendingSave {
  bool cancelled = false;
  bool started = false;
}
