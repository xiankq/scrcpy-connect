import 'document_outcome.dart';

/// 一次系统交付的持久身份；不携带选择器、页面或原生文件句柄。
final class FileDeliveryPlan {
  const FileDeliveryPlan({
    required this.operationId,
    required this.source,
    required this.name,
    this.reviewedOperationId,
    this.additionalCopyOfOperationId,
  });
  final String operationId, name;
  final DocumentSource source;
  final String? reviewedOperationId, additionalCopyOfOperationId;
}
