import 'dart:async';
import 'dart:math';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/widgets/documents/document_picker.dart';

DocumentOperationController useDocumentOperationController(
  WidgetRef ref, {
  DocumentSource? exportSource,
}) {
  final documents = ref.watch(systemDocumentsProvider);
  final completeSelection = ref.watch(documentSelectionResponderProvider);
  final events = ref.watch(runtimeEventsProvider);
  final operation = useMemoized(
    () => DocumentOperationController(
      documents: documents,
      completeSelection: completeSelection,
      events: events,
      exportSource: exportSource,
    ),
    [
      documents,
      completeSelection,
      events,
      exportSource?.sourceId,
      exportSource?.localPath,
      exportSource?.kind,
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
    required this.documents,
    this.completeSelection,
    required Stream<RuntimeEvent> events,
    this.exportSource,
  }) : loaded = exportSource == null {
    _events = events.listen((event) {
      if (event.data case DocumentSelectionRequested(:final request)
          when request.operationId == operationId && !disposed) {
        unawaited(_choose(request));
      }
      if (event.data case DocumentDeliveryChanged(:final source)
          when exportSource == source && !busy && !disposed) {
        unawaited(refresh());
      }
    });
  }

  Future<void> _choose(DocumentSelectionRequest selection) async {
    final id = selection.operationId;
    DocumentSelectionResult receipt;
    try {
      receipt = await DocumentPicker.choose(selection);
    } catch (failure) {
      receipt = DocumentSelectionFailed(
        failure is RequestFailure ? failure.code : 'selection_failed',
        '$failure',
      );
    }
    // 退出或取消后拒绝迟到的选择；原任务仍负责回收原生资源。
    completeSelection?.call(
      id,
      disposed || operationId != id
          ? const DocumentSelectionCancelled()
          : receipt,
    );
  }

  final bool Function(String, DocumentSelectionResult)? completeSelection;
  final SystemDocuments documents;
  final DocumentSource? exportSource;
  StreamSubscription<RuntimeEvent>? _events;
  int _readGeneration = 0;
  String? recordOperationId;
  bool loaded;
  bool refreshing = false;
  String? operationId;
  DocumentOutcome? result;
  String? error;
  bool busy = false;
  bool cancelling = false;
  bool disposed = false;

  Future<void> _release(DocumentOutcome? data) async {
    final source = data?.managedSourceId;
    if (source is! String) return;
    try {
      await documents.releaseDocumentSource(source);
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
      final record = await documents.readDelivery(exportSource!);
      if (disposed || generation != _readGeneration) return;
      recordOperationId = record?.operationId;
      result = record == null
          ? null
          : record.result ??
                DocumentOutcome(status: record.status, name: record.name);
      error = null;
      loaded = true;
      if (result?.status != DocumentOutcomeStatus.pending) cancelling = false;
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

  Future<void> importDirectory() =>
      _run((id, _) => documents.importDocuments(id, .directory));

  Future<void> export(
    String name, {
    bool reviewed = false,
    bool additionalCopy = false,
  }) async {
    final source = exportSource;
    if (source == null) return;
    await _run(
      (id, previousOperation) => documents.exportDocument(
        DocumentExportPlan(
          operationId: id,
          source: source,
          name: name,
          reviewedOperationId: reviewed ? previousOperation : null,
          additionalCopyOfOperationId: additionalCopy
              ? previousOperation
              : null,
        ),
      ),
      exporting: true,
      name: name,
    );
  }

  Future<void> _run(
    Future<DocumentOutcome> Function(String, String?) action, {
    bool exporting = false,
    String? name,
  }) async {
    if (busy ||
        refreshing ||
        !loaded ||
        result?.status == DocumentOutcomeStatus.pending) {
      return;
    }
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
      final data = await action(id, previousOperation);
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
        if (exporting) {
          result = DocumentOutcome(
            status: .resultUnknown,
            name: name,
            cacheRetained: true,
            partialDestinationPossible: true,
          );
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
        (result?.status == DocumentOutcomeStatus.pending
            ? recordOperationId
            : null);
    if (id == null || cancelling) return;
    cancelling = true;
    notifyListeners();
    try {
      await documents.cancelDocument(id);
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
      documents.cancelDocument(id).ignore();
    }
    super.dispose();
  }
}
