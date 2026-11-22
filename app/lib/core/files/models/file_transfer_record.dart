import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';

part 'file_transfer_record.freezed.dart';
part 'file_transfer_record.g.dart';

/// 可持久化的任务事实；执行对象及其清理责任留在传输所有者中。
@freezed
abstract class FileTransferRecord with _$FileTransferRecord {
  const FileTransferRecord._();
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true, includeIfNull: false)
  const factory FileTransferRecord({
    required String id,
    required String deviceId,
    required String batchId,
    required FileTransferDirection direction,
    required String source,
    required String destination,
    @Default('文件传输') String name,
    String? shareId,
    String? parentId,
    FileStamp? sourceStamp,
    @JsonKey(unknownEnumValue: FileTransferKind.unsupported)
    @Default(FileTransferKind.file)
    FileTransferKind kind,
    @JsonKey(unknownEnumValue: FileTransferStatus.unknown)
    @Default(FileTransferStatus.unknown)
    FileTransferStatus status,
    @Default(FileTransferConflict.ask) FileTransferConflict policy,
    @Default(FileTransferDestination.localPath)
    FileTransferDestination destinationScope,
    @Default(0) int createdAt,
    int? endedAt,
    @Default(0) int generation,
    @Default(0) int itemIndex,
    @Default(1) int itemCount,
    @Default(0) int transferred,
    int? total,
    String? temporaryPath,
    String? saveMode,
    String? errorCode,
    String? error,
    @Default(false) bool treeVerified,
    @Default(false) bool treeComplete,
    @Default(false) bool partialDestinationPossible,
    @Default(false) bool cleanupPending,
    @Default(false) bool historyHidden,
    String? cleanupScopeId,
    String? cleanupScopeKey,
  }) = _FileTransferRecord;

  factory FileTransferRecord.fromJson(Map<String, dynamic> json) =>
      _$FileTransferRecordFromJson(json);
}
