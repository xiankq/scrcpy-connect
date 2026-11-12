import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_delivery.dart';
import 'package:scrcpy_connect/core/files/file_export_service.dart';
import 'package:scrcpy_connect/core/files/file_selection_requests.dart';
import 'package:scrcpy_connect/core/files/system_document_backend.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 系统文档的准入、持久交付与执行资源所有者。
/// 查询和取消借用已有执行端；首次实际导入、导出或释放来源才创建它。
final class SystemDocumentService implements SystemDocuments {
  SystemDocumentService({
    required this._deliveries,
    required this._createBackend,
    required this.allowImport,
    required this.isDisposed,
    required this.emit,
  });

  final FileDeliveryRecords _deliveries;
  final SystemDocumentBackend Function(FileSelectionRequests)? _createBackend;
  final bool allowImport;
  final bool Function() isDisposed;
  final void Function(Map<String, dynamic>) emit;
  bool _closed = false;
  SystemDocumentBackend? _backend;
  FileExportService? _delivery;
  FileSelectionRequests? _selections;

  void _requireOpen() {
    if (_closed || isDisposed()) {
      throw const RequestFailure('cancelled', '文档服务正在关闭。');
    }
  }

  void _requireAvailable({bool importing = false}) {
    _requireOpen();
    if (_createBackend == null || importing && !allowImport) {
      throw const RequestFailure(
        'platform_unavailable',
        '此平台尚不支持此系统文档操作，请使用系统文件分享并在接收应用核对。',
      );
    }
  }

  SystemDocumentBackend get _executor {
    _requireAvailable();
    return _backend ??= _createBackend!(
      _selections ??= FileSelectionRequests((selection) {
        if (!_closed && !isDisposed()) {
          emit({'type': 'documents.selection.requested', 'data': selection});
        }
      }),
    );
  }

  FileExportService get _exports => _delivery ??= FileExportService(
    deliveries: _deliveries,
    write: (plan) => _executor.exportDocument(plan),
    cancelWrite: (id) async => await _backend?.cancel(id),
    onChanged: (source) {
      if (!_closed && !isDisposed()) {
        emit({'type': 'delivery.changed', 'data': source.toJson()});
      }
    },
  );

  bool completeSelection(String id, Map<String, dynamic> result) =>
      _selections?.complete(id, result) ?? false;

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) {
    _requireAvailable(importing: true);
    return _executor.importDocuments(operationId, kind);
  }

  @override
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan) {
    _requireAvailable();
    return _exports.save(plan);
  }

  @override
  Future<void> cancelDocument(String operationId) async {
    _requireAvailable();
    if (await _delivery?.cancel(operationId) == true) return;
    await _backend?.cancel(operationId);
  }

  @override
  Future<void> releaseDocumentSource(String managedSourceId) async {
    _requireAvailable(importing: true);
    await _executor.releaseSource(managedSourceId);
  }

  @override
  Future<DocumentConflict?> readDocumentConflict(String operationId) async {
    _requireAvailable();
    return await _backend?.readConflict(operationId);
  }

  @override
  Future<bool> resolveDocumentConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  }) async {
    _requireAvailable();
    return await _backend?.resolveConflict(
          operationId,
          conflictId,
          decision,
          applyToRemaining: applyToRemaining,
        ) ??
        false;
  }

  @override
  Future<FileDeliveryRecord?> readDelivery(DocumentSource source) {
    _requireOpen();
    return _deliveries.read(source);
  }

  OrderedDisposal? _disposal;
  void stopAdmission() {
    _closed = true;
    _delivery?.stopAdmission();
  }

  Future<void> close() {
    stopAdmission();
    _disposal ??= OrderedDisposal([
      () async {
        await _backend?.dispose();
        await _delivery?.close();
      },
    ]);
    return _disposal!.run();
  }
}
