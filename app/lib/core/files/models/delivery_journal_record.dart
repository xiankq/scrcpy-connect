import 'package:scrcpy_connect/core/files/models/document_outcome.dart';

/// 保存准入与原件保护的持久快照；不携带系统授权。
final class DeliveryJournalRecord {
  const DeliveryJournalRecord({
    required this.operationId,
    required this.source,
    required this.name,
    required this.status,
    required this.updatedAt,
    this.result,
  });

  factory DeliveryJournalRecord.fromJson(Map<String, dynamic> value) =>
      DeliveryJournalRecord(
        operationId: value['operationId'] as String,
        source: DocumentSource.fromJson(value),
        name: value['name'] as String,
        status: DocumentOutcomeStatus.values.firstWhere(
          (status) =>
              (status == DocumentOutcomeStatus.resultUnknown
                  ? 'result_unknown'
                  : status.name) ==
              value['status'],
        ),
        updatedAt: value['updatedAt'] as int,
        result: value['result'] == null
            ? null
            : DocumentOutcome.fromJson(
                Map<String, Object?>.from(value['result'] as Map),
              ),
      );

  final String operationId, name;
  final DocumentSource source;
  final DocumentOutcomeStatus status;
  final DocumentOutcome? result;
  final int updatedAt;

  bool get protectsSource =>
      status == DocumentOutcomeStatus.pending ||
      status == DocumentOutcomeStatus.resultUnknown ||
      result?.partialDestinationPossible == true;

  DeliveryJournalRecord complete(DocumentOutcome outcome, int time) =>
      DeliveryJournalRecord(
        operationId: operationId,
        source: source,
        name: name,
        status: outcome.status,
        result: outcome,
        updatedAt: time,
      );

  FileDeliveryRecord get view => FileDeliveryRecord(
    operationId: operationId,
    name: name,
    status: status,
    result: result,
  );

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    ...source.toJson(),
    'name': name,
    'status': status == DocumentOutcomeStatus.resultUnknown
        ? 'result_unknown'
        : status.name,
    'result': result?.toJson(),
    'updatedAt': updatedAt,
  };
}
