import 'system_documents.dart';

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

/// 先可靠记录准入，再保存终态；失败重试只提交回执，不重放系统写入。
abstract interface class FileDeliveryRecords {
  Future<FileDeliveryRecord?> read(DocumentSource source);
  Future<void> begin(FileDeliveryPlan plan);
  Future<FileDeliveryRecord> finish(
    FileDeliveryPlan plan,
    DocumentOutcome result,
  );
}
