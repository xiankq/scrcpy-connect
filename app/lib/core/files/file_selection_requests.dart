import 'dart:async';

import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';

/// 文档任务等待用户输入的数据通道；选择器由持有该任务的视图打开。
final class FileSelectionRequests {
  FileSelectionRequests(this.onRequested);
  final void Function(DocumentSelectionRequest) onRequested;
  final _pending = <String, Completer<DocumentSelectionResult>>{};

  Future<DocumentSelectionResult> request(
    DocumentSelectionRequest selection,
  ) async {
    final id = selection.operationId;
    if (_pending.containsKey(id)) {
      throw const RequestFailure('documents_busy', '此任务仍在等待位置选择。');
    }
    final reply = Completer<DocumentSelectionResult>();
    _pending[id] = reply;
    try {
      onRequested(selection);
      final result = await reply.future;
      if (result case DocumentSelectionFailed(:final code, :final message)) {
        throw RequestFailure(code, message);
      }
      return result;
    } finally {
      if (identical(_pending[id], reply)) _pending.remove(id);
    }
  }

  bool complete(String id, DocumentSelectionResult result) {
    final reply = _pending[id];
    if (reply == null || reply.isCompleted) return false;
    reply.complete(result);
    return true;
  }

  void cancel(String id) => complete(id, const DocumentSelectionCancelled());
}
