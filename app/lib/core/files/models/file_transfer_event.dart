import 'package:scrcpy_connect/core/events/models/app_event.dart';

sealed class FileTransferEvent extends AppEvent {
  const FileTransferEvent();
}

final class FileTransferChanged extends FileTransferEvent {
  const FileTransferChanged(this.transferId);
  final String transferId;

  @override
  String get type => 'transfers.changed';
}

final class FileTransferProgress extends FileTransferEvent {
  const FileTransferProgress(this.transferId, this.transferred);
  final String transferId;
  final int transferred;

  @override
  String get type => 'transfers.progress';
}

final class FileTransferFailed extends FileTransferEvent {
  const FileTransferFailed(this.batchId, this.cause);
  final String batchId;
  final Object cause;

  @override
  String get type => 'transfers.failed';
}
