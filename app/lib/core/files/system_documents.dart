import 'package:scrcpy_connect/core/files/models/document_outcome.dart';

export 'package:scrcpy_connect/core/files/models/document_outcome.dart';

abstract interface class SystemDocuments {
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  );
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan);
  Future<void> cancelDocument(String operationId);
  Future<void> releaseDocumentSource(String managedSourceId);
  Future<DocumentConflict?> readDocumentConflict(String operationId);
  Future<bool> resolveDocumentConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  });
  Future<FileDeliveryRecord?> readDelivery(DocumentSource source);
}
