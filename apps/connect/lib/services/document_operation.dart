import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class DocumentOperation extends ChangeNotifier {
  DocumentOperation(this.controller);
  final AppController controller;
  String? operationId;
  Json? result;
  String? error;
  bool busy = false;
  bool cancelling = false;
  bool disposed = false;

  Future<void> run(String command, Json params) async {
    if (busy) return;
    final id =
        'documents-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    operationId = id;
    result = null;
    error = null;
    busy = true;
    notifyListeners();
    try {
      final data = await controller.request(command, {
        ...params,
        'operationId': id,
      });
      if (!disposed && operationId == id) result = data;
    } catch (failure) {
      if (!disposed && operationId == id) error = '$failure';
    } finally {
      if (!disposed && operationId == id) {
        operationId = null;
        busy = false;
        cancelling = false;
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    final id = operationId;
    if (id == null || cancelling) return;
    cancelling = true;
    notifyListeners();
    try {
      await controller.request('documents.cancel', {'operationId': id});
    } catch (failure) {
      if (!disposed) {
        error = '$failure';
        cancelling = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    final id = operationId;
    operationId = null;
    if (id != null) {
      controller.request('documents.cancel', {'operationId': id}).ignore();
    }
    super.dispose();
  }
}

DocumentOperation useDocumentOperation(AppController controller) {
  final operation = useMemoized(() => DocumentOperation(controller), [
    controller,
  ]);
  useListenable(operation);
  useEffect(() => operation.dispose, [operation]);
  return operation;
}
