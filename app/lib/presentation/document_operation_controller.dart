import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';
import 'dart:math';

import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 持有文档操作表单的提交、取消与交付记录回读状态。
/// 实际系统文档操作及资源回收由应用文档所有者执行。
class DocumentOperationController extends ChangeNotifier {
  DocumentOperationController(this.controller, {this.exportSource})
    : loaded = exportSource == null {
    if (exportSource != null) {
      _events = controller
          .eventStream()
          .where((event) {
            final data = jsonObject(event['data']);
            return event['type'] == 'delivery.changed' &&
                [
                  'sourceId',
                  'localPath',
                  'kind',
                ].every((field) => data[field] == exportSource![field]);
          })
          .listen((_) {
            if (!busy) unawaited(refresh());
          });
    }
  }
  final AppController controller;
  final Json? exportSource;
  StreamSubscription<Json>? _events;
  int _readGeneration = 0;
  String? recordOperationId;
  bool loaded;
  bool refreshing = false;
  String? operationId;
  Json? result;
  String? error;
  bool busy = false;
  bool cancelling = false;
  bool disposed = false;

  Future<void> refresh() async {
    if (exportSource == null || disposed || busy) return;
    final generation = ++_readGeneration;
    refreshing = true;
    notifyListeners();
    try {
      final response = await controller.execute(
        ApplicationCommand.deliveryGet,
        exportSource!,
      );
      if (disposed || generation != _readGeneration) return;
      final record = response['record'];
      if (record is Map<Object?, Object?>) {
        final current = jsonObject(record);
        recordOperationId = value(current, 'operationId');
        result = current['result'] is Map<Object?, Object?>
            ? jsonObject(current['result'])
            : {'status': current['status'], 'name': current['name']};
      } else {
        recordOperationId = null;
        result = null;
      }
      error = null;
      loaded = true;
      if (result?['status'] != 'pending') cancelling = false;
    } catch (failure) {
      if (!disposed && generation == _readGeneration) {
        loaded = false;
        error = '尚未核验上次系统保存结果：$failure';
      }
    } finally {
      if (!disposed && generation == _readGeneration) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> run(
    String command,
    Json params, {
    bool reviewed = false,
    bool additionalCopy = false,
  }) async {
    if (busy || refreshing || !loaded || result?['status'] == 'pending') return;
    final previousOperation = recordOperationId;
    final random = Random.secure();
    final id =
        'documents-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    operationId = id;
    recordOperationId = id;
    _readGeneration++;
    result = null;
    error = null;
    busy = true;
    var reread = false;
    notifyListeners();
    try {
      final data = await controller.request(command, {
        ...params,
        ...?exportSource,
        if (reviewed && previousOperation != null)
          'reviewedOperationId': previousOperation,
        if (additionalCopy && previousOperation != null)
          'additionalCopyOfOperationId': previousOperation,
        'operationId': id,
      });
      if (!disposed && operationId == id) result = data;
    } catch (failure) {
      if (!disposed && operationId == id) {
        reread = exportSource != null;
        error = '$failure';
        // 没有回执不能证明系统未写入，再次导出前必须核对。
        if (command == 'documents.export') {
          result = {
            'status': 'result_unknown',
            'name': params['name'],
            'cacheRetained': true,
            'partialDestinationPossible': true,
          };
        }
      }
    } finally {
      if (!disposed && operationId == id) {
        operationId = null;
        busy = false;
        cancelling = false;
        notifyListeners();
      }
    }
    if (reread && !disposed) await refresh();
  }

  Future<void> cancel() async {
    final id =
        operationId ??
        (result?['status'] == 'pending' ? recordOperationId : null);
    if (id == null || cancelling) return;
    cancelling = true;
    notifyListeners();
    try {
      await controller.execute(ApplicationCommand.documentsCancel, {
        'operationId': id,
      });
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
    unawaited(_events?.cancel());
    final id = operationId;
    operationId = null;
    if (id != null) {
      controller.execute(ApplicationCommand.documentsCancel, {
        'operationId': id,
      }).ignore();
    }
    super.dispose();
  }
}

DocumentOperationController useDocumentOperationController(
  AppController controller, {
  Json? exportSource,
}) {
  final operation = useMemoized(
    () => DocumentOperationController(controller, exportSource: exportSource),
    [
      controller,
      exportSource?['sourceId'],
      exportSource?['localPath'],
      exportSource?['kind'],
    ],
  );
  useListenable(operation);
  useEffect(() {
    if (exportSource != null) Future.microtask(operation.refresh);
    return operation.dispose;
  }, [operation]);
  return operation;
}
