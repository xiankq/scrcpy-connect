import 'package:scrcpy_connect/core/files/system_documents.dart';

import 'models/file_delivery_plan.dart';

export 'models/file_delivery_plan.dart';

/// 先可靠记录准入，再保存终态；失败重试只提交回执，不重放系统写入。
abstract interface class FileDeliveryRecords {
  Future<FileDeliveryRecord?> read(DocumentSource source);
  Future<void> begin(FileDeliveryPlan plan);
  Future<FileDeliveryRecord> finish(
    FileDeliveryPlan plan,
    DocumentOutcome result,
  );
}
