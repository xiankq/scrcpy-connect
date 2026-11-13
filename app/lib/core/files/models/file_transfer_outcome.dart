import 'package:scrcpy_connect/core/files/models/file_transfer_record.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';

/// 执行已有回执；资源排空后恢复这些结果，不覆盖迟到的实际字节进度。
final class FileTransferOutcome {
  const FileTransferOutcome({
    required this.status,
    required this.errorCode,
    required this.error,
    required this.partialDestinationPossible,
    this.clearTemporaryPath = false,
  });

  factory FileTransferOutcome.fromRecord(FileTransferRecord record) =>
      FileTransferOutcome(
        status: record.status,
        errorCode: record.errorCode,
        error: record.error,
        partialDestinationPossible: record.partialDestinationPossible,
      );

  final FileTransferStatus status;
  final String? errorCode;
  final String? error;
  final bool partialDestinationPossible;
  final bool clearTemporaryPath;
}
