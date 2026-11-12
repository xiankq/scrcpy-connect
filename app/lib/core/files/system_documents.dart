import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_documents.freezed.dart';
part 'system_documents.g.dart';

enum DocumentKind { file, directory }

enum DocumentImportKind { directory, files }

enum DocumentConflictPolicy { ask, skip, keepBoth }

enum DocumentConflictDecision { keepBoth, skip, cancel }

enum DocumentOutcomeStatus {
  pending,
  imported,
  saved,
  partial,
  failed,
  cancelled,
  @JsonValue('result_unknown')
  resultUnknown,
}

@freezed
abstract class DocumentSource with _$DocumentSource {
  const factory DocumentSource({
    required String sourceId,
    required String localPath,
    required DocumentKind kind,
  }) = _DocumentSource;
  factory DocumentSource.fromJson(Map<String, Object?> json) =>
      _$DocumentSourceFromJson(json);
}

final class DocumentExportPlan {
  const DocumentExportPlan({
    required this.operationId,
    required this.source,
    required this.name,
    this.mime,
    this.conflict = .ask,
    this.reviewedOperationId,
    this.additionalCopyOfOperationId,
  });
  final String operationId, name;
  final DocumentSource source;
  final String? mime, reviewedOperationId, additionalCopyOfOperationId;
  final DocumentConflictPolicy conflict;
}

@freezed
abstract class DocumentIssue with _$DocumentIssue {
  const factory DocumentIssue({
    @Default('') String path,
    @Default('') String code,
    @Default('') String message,
  }) = _DocumentIssue;
  factory DocumentIssue.fromJson(Map<String, Object?> json) =>
      _$DocumentIssueFromJson(json);
}

@freezed
abstract class DocumentOutcome with _$DocumentOutcome {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true, includeIfNull: false)
  const factory DocumentOutcome({
    required DocumentOutcomeStatus status,
    String? operationId,
    String? managedSourceId,
    String? localPath,
    String? uri,
    String? name,
    int? bytes,
    int? files,
    int? directories,
    int? skipped,
    int? errorCount,
    bool? errorsTruncated,
    bool? partialDestinationPossible,
    bool? cacheRetained,
    @Default([]) List<DocumentIssue> errors,
  }) = _DocumentOutcome;
  factory DocumentOutcome.fromJson(Map<String, Object?> json) =>
      _$DocumentOutcomeFromJson(json);
}

@freezed
abstract class DocumentConflict with _$DocumentConflict {
  const factory DocumentConflict({
    required String operationId,
    required String conflictId,
    required String name,
  }) = _DocumentConflict;
  factory DocumentConflict.fromJson(Map<String, Object?> json) =>
      _$DocumentConflictFromJson(json);
}

final class FileDeliveryRecord {
  const FileDeliveryRecord({
    required this.operationId,
    required this.name,
    required this.status,
    this.result,
  });
  factory FileDeliveryRecord.fromJson(Map<String, Object?> json) =>
      FileDeliveryRecord(
        operationId: json['operationId'] as String,
        name: json['name'] as String,
        status: $enumDecode(_$DocumentOutcomeStatusEnumMap, json['status']),
        result: json['result'] == null
            ? null
            : DocumentOutcome.fromJson(
                Map<String, Object?>.from(json['result'] as Map),
              ),
      );
  final String operationId, name;
  final DocumentOutcomeStatus status;
  final DocumentOutcome? result;
}

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
