import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';

DocumentOperationController useDocumentOperationController(
  AppController controller, {
  Json? exportSource,
}) {
  final operation = useMemoized(
    () => DocumentOperationController(
      request: controller.request,
      execute: controller.execute,
      events: controller.eventStream(),
      exportSource: exportSource,
    ),
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

/// 持有文档操作表单的提交、取消与交付记录回读状态。
/// 实际系统文档操作及资源回收由应用文档所有者执行。
class DocumentOperationController extends ChangeNotifier {
  DocumentOperationController({
    required this.request,
    required this.execute,
    required Stream<Json> events,
    this.exportSource,
  }) : loaded = exportSource == null {
    if (exportSource != null) {
      _events = events
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
  final ApplicationRequest request;
  final ApplicationCommandExecutor execute;
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

  Future<void> _release(Json? data) async {
    final source = data?['managedSourceId'];
    if (source is! String) return;
    try {
      await execute(ApplicationCommand.documentsCancel, {
        'managedSourceId': source,
      });
    } catch (failure) {
      // 退出不代表归还成功。来源账本继续保护未确认内容，保留错误供核对。
      error = '$failure';
      rethrow;
    }
  }

  Future<void> refresh() async {
    if (exportSource == null || disposed || busy) return;
    final generation = ++_readGeneration;
    refreshing = true;
    notifyListeners();
    try {
      final response = await execute(
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
    final previousResult = result;
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
    var previousReleased = false;
    notifyListeners();
    try {
      await _release(previousResult);
      previousReleased = true;
      if (disposed || operationId != id) return;
      final data = await request(command, {
        ...params,
        ...?exportSource,
        if (reviewed && previousOperation != null)
          'reviewedOperationId': previousOperation,
        if (additionalCopy && previousOperation != null)
          'additionalCopyOfOperationId': previousOperation,
        'operationId': id,
      });
      if (!disposed && operationId == id) {
        result = data;
      } else {
        result = data;
        await _release(data);
        result = null;
      }
    } catch (failure) {
      if (!previousReleased) result = previousResult;
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
      await execute(ApplicationCommand.documentsCancel, {'operationId': id});
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
    _release(result).ignore();
    final id = operationId;
    operationId = null;
    if (id != null) {
      execute(ApplicationCommand.documentsCancel, {'operationId': id}).ignore();
    }
    super.dispose();
  }
}
