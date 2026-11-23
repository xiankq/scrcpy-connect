import 'dart:async';
import 'dart:math';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/core/files/models/document_operation_state.dart';
import 'package:scrcpy_connect/core/files/models/document_selection.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';

part 'document_operation_notifier.g.dart';

/// 导入与系统保存共用的提交、取消和记录回读；视图负责打开选择器。
@riverpod
class DocumentOperationNotifier extends _$DocumentOperationNotifier {
  late _DocumentOperationOwner _owner;

  @override
  DocumentOperationState build({
    required Object scope,
    DocumentSource? exportSource,
  }) {
    final owner = _owner = _DocumentOperationOwner(
      documents: ref.watch(systemDocumentsProvider),
      completeSelection: ref.watch(documentSelectionResponderProvider),
      events: ref.watch(runtimeEventsProvider),
      exportSource: exportSource,
    );
    owner.subscription = owner.events.listen((event) {
      if (!_current(owner)) return;
      if (event.data case DocumentDeliveryChanged(:final source)
          when owner.exportSource == source && !state.busy) {
        unawaited(refresh());
      }
    });
    ref.onDispose(owner.dispose);
    if (exportSource != null) {
      scheduleMicrotask(() {
        if (_current(owner)) unawaited(refresh());
      });
    }
    return DocumentOperationState(loaded: exportSource == null);
  }

  bool _current(_DocumentOperationOwner owner) =>
      !owner.disposed &&
      ref.mounted &&
      identical(_owner, owner) &&
      identical(ref.read(systemDocumentsProvider), owner.documents) &&
      identical(
        ref.read(documentSelectionResponderProvider),
        owner.completeSelection,
      ) &&
      identical(ref.read(runtimeEventsProvider), owner.events);

  /// 确认框等视图等待只对发起时的能力和表单有效。
  bool Function() captureScope() {
    final owner = _owner;
    return () => _current(owner);
  }

  /// 只允许发起视图认领一次；返回的交付函数固定原操作及原能力所有者。
  void Function(DocumentSelectionResult)? claimSelection(
    DocumentSelectionRequest request,
  ) {
    final owner = _owner;
    final id = request.operationId;
    if (!_current(owner) ||
        owner.operationId != id ||
        owner.selectionClaimed ||
        owner.selectionCancelled) {
      return null;
    }
    owner.selectionClaimed = true;
    return (result) {
      owner.completeSelection?.call(
        id,
        _current(owner) && owner.operationId == id && !owner.selectionCancelled
            ? result
            : const DocumentSelectionCancelled(),
      );
    };
  }

  Future<void> refresh() async {
    final owner = _owner;
    final source = owner.exportSource;
    if (!_current(owner) || source == null || state.busy) return;
    final generation = ++owner.readGeneration;
    state = state.copyWith(refreshing: true);
    try {
      final record = await owner.documents.readDelivery(source);
      if (!_current(owner) || generation != owner.readGeneration) return;
      final result = record == null
          ? null
          : record.result ??
                DocumentOutcome(status: record.status, name: record.name);
      owner.pendingOperationId = result?.status == .pending
          ? record?.operationId
          : null;
      state = state.copyWith(
        recordOperationId: record?.operationId,
        result: result,
        error: null,
        loaded: true,
        cancelling: result?.status == .pending && state.cancelling,
      );
    } catch (failure) {
      if (_current(owner) && generation == owner.readGeneration) {
        state = state.copyWith(
          loaded: false,
          error: failureMessage(failure, fallback: '无法读取上次保存结果。请先查看保存位置。'),
        );
      }
    } finally {
      if (_current(owner) && generation == owner.readGeneration) {
        state = state.copyWith(refreshing: false);
      }
    }
  }

  Future<void> importDirectory() =>
      _run((owner, id, _) => owner.documents.importDocuments(id, .directory));

  Future<void> export(
    String name, {
    bool reviewed = false,
    bool additionalCopy = false,
  }) async {
    if (!_current(_owner) || _owner.exportSource == null) return;
    await _run(
      (owner, id, previousOperation) => owner.documents.exportDocument(
        DocumentExportPlan(
          operationId: id,
          source: owner.exportSource!,
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
    Future<DocumentOutcome> Function(_DocumentOperationOwner, String, String?)
    action, {
    bool exporting = false,
    String? name,
  }) async {
    final owner = _owner;
    if (!_current(owner) ||
        state.busy ||
        state.refreshing ||
        !state.loaded ||
        state.result?.status == .pending) {
      return;
    }
    final previousOperation = state.recordOperationId;
    final previousResult = state.result;
    final random = Random.secure();
    final id =
        'documents-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    owner.operationId = id;
    owner.selectionClaimed = owner.selectionCancelled = false;
    owner.readGeneration++;
    state = state.copyWith(
      operationId: id,
      recordOperationId: id,
      result: null,
      error: null,
      busy: true,
    );
    var reread = false;
    var previousReleased = false;
    try {
      await owner.release(previousResult?.managedSourceId);
      previousReleased = true;
      if (!_current(owner) || owner.operationId != id) return;
      final data = await action(owner, id, previousOperation);
      if (_current(owner) && owner.operationId == id) {
        owner.managedSourceId = data.managedSourceId;
        owner.pendingOperationId = data.status == .pending ? id : null;
        state = state.copyWith(result: data);
      } else {
        // 迟到来源交回原能力，不能发布给新表单，也不能解除传输自己的租约。
        await owner.release(data.managedSourceId);
      }
    } catch (failure) {
      if (_current(owner) && owner.operationId == id) {
        reread = owner.exportSource != null;
        state = state.copyWith(
          error: failureMessage(
            failure,
            fallback: exporting
                ? '暂时无法确认文件是否已保存。请先查看保存位置。'
                : !previousReleased
                ? '上次选择的文件仍在使用。请稍后再试。'
                : '无法导入所选内容。请重新选择文件。',
          ),
          result: exporting
              ? DocumentOutcome(
                  status: .resultUnknown,
                  name: name,
                  cacheRetained: true,
                  partialDestinationPossible: true,
                )
              : previousReleased
              ? null
              : previousResult,
        );
      }
    } finally {
      if (owner.operationId == id) owner.operationId = null;
      if (_current(owner)) {
        state = state.copyWith(
          operationId: null,
          busy: false,
          cancelling: false,
        );
      }
    }
    if (reread && _current(owner)) await refresh();
  }

  Future<void> cancel() async {
    final owner = _owner;
    if (!_current(owner) || state.cancelling) return;
    final id = owner.operationId ?? owner.pendingOperationId;
    if (id == null) return;
    owner.selectionCancelled = true;
    state = state.copyWith(cancelling: true);
    try {
      await owner.documents.cancelDocument(id);
    } catch (failure) {
      if (_current(owner)) {
        state = state.copyWith(
          error: failureMessage(failure, fallback: '暂时无法确认是否已取消。请先检查操作结果。'),
          cancelling: false,
        );
      }
    }
  }
}

/// 存活操作与来源归还权固定到原能力；provider 换源后仍负责迟到回执。
final class _DocumentOperationOwner {
  _DocumentOperationOwner({
    required this.documents,
    required this.completeSelection,
    required this.events,
    required this.exportSource,
  });
  final SystemDocuments documents;
  final bool Function(String, DocumentSelectionResult)? completeSelection;
  final Stream<RuntimeEvent> events;
  final DocumentSource? exportSource;
  StreamSubscription<RuntimeEvent>? subscription;
  String? operationId, pendingOperationId, managedSourceId;
  bool disposed = false, selectionClaimed = false, selectionCancelled = false;
  int readGeneration = 0;
  final releases = <String, Future<void>>{};

  Future<void> release(String? source) {
    if (source == null) return Future.value();
    return releases.putIfAbsent(source, () async {
      try {
        await documents.releaseDocumentSource(source);
        if (managedSourceId == source) managedSourceId = null;
      } finally {
        releases.remove(source);
      }
    });
  }

  void dispose() {
    disposed = true;
    selectionCancelled = true;
    unawaited(subscription?.cancel());
    // 未确认归还仍由来源账本保护；离页不能把它当作已释放。
    release(managedSourceId).ignore();
    final id = operationId ?? pendingOperationId;
    operationId = null;
    if (id != null) documents.cancelDocument(id).ignore();
  }
}
