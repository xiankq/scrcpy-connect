import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';

typedef TransferHistoryEntry = ({
  String id,
  FileTransferSnapshot task,
  List<FileTransferSnapshot> members,
  String? batchId,
});
