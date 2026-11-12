import 'package:scrcpy_connect/core/files/system_documents.dart';

/// 系统位置的执行端；持久交付记录由 SystemDocumentService 统一管理。
abstract interface class SystemDocumentBackend {
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  );
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan);
  Future<void> cancel(String operationId);
  Future<void> releaseSource(String managedSourceId);
  Future<DocumentConflict?> readConflict(String operationId);
  Future<bool> resolveConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  });
  Future<void> dispose();
}
