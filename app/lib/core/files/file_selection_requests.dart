import 'dart:async';

import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 文档任务等待用户输入的数据通道；选择器由持有该任务的视图打开。
final class FileSelectionRequests {
  FileSelectionRequests(this.onRequested);
  final void Function(Json) onRequested;
  final _pending = <String, Completer<Json>>{};

  Future<Json> request(Json selection) async {
    final id = selection['operationId'] as String;
    if (_pending.containsKey(id)) {
      throw const RequestFailure('documents_busy', '此任务仍在等待位置选择。');
    }
    final reply = Completer<Json>();
    _pending[id] = reply;
    try {
      onRequested(Map.unmodifiable(selection));
      final result = await reply.future;
      if (result['status'] == 'failed') {
        throw RequestFailure(
          result['code'] as String? ?? 'selection_failed',
          result['message'] as String? ?? '无法读取所选位置。',
        );
      }
      return result;
    } finally {
      if (identical(_pending[id], reply)) _pending.remove(id);
    }
  }

  bool complete(String id, Json result) {
    final reply = _pending[id];
    if (reply == null || reply.isCompleted) return false;
    reply.complete(Map.unmodifiable(result));
    return true;
  }

  void cancel(String id) => complete(id, {'status': 'cancelled'});
}
