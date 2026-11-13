import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';

part 'file_transfer_snapshot.freezed.dart';
part 'file_transfer_snapshot.g.dart';

enum FileTransferStatus {
  unknown,
  queued,
  running,
  finalizing,
  cancelling,
  conflict,
  completed,
  skipped,
  failed,
  cancelled,
  interrupted,
  paused,
  partial,
  partialFailure,
  completedWithSkips;

  bool get isActive => switch (this) {
    .queued || .running || .finalizing || .cancelling || .conflict => true,
    .unknown ||
    .completed ||
    .skipped ||
    .failed ||
    .cancelled ||
    .interrupted ||
    .paused ||
    .partial ||
    .partialFailure ||
    .completedWithSkips => false,
  };
}

enum FileTransferKind { file, directory, symlink, unsupported }

/// 查询只交付不可变快照；任务执行及资源回收仍由传输所有者管理。
@freezed
abstract class FileTransferSnapshot with _$FileTransferSnapshot {
  const FileTransferSnapshot._();
  // Freezed 通过工厂注解配置生成实现。
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory FileTransferSnapshot({
    required String id,
    @Default('') String deviceId,
    String? batchId,
    String? parentId,
    @Default('文件传输') String name,
    @Default('') String source,
    @Default('') String destination,
    @Default(FileTransferDirection.pull) FileTransferDirection direction,
    @Default(FileTransferDestination.localPath)
    FileTransferDestination destinationScope,
    @Default(FileTransferKind.file) FileTransferKind kind,
    @Default(FileTransferStatus.unknown) FileTransferStatus status,
    @Default(FileTransferConflict.ask) FileTransferConflict policy,
    @Default(0) int generation,
    @Default(0) int itemIndex,
    @Default(1) int itemCount,
    @Default(0) int transferred,
    int? total,
    int? completedBytes,
    int? totalBytes,
    String? deviceName,
    String? sourceLabel,
    String? destinationLabel,
    String? localPath,
    String? partialLocalPath,
    String? error,
    String? errorCode,
    String? exportReason,
    String? saveMode,
    @Default(false) bool cleanupPending,
    @Default(false) bool partialDestinationPossible,
    @Default(false) bool treeVerified,
    @Default(false) bool treeComplete,
    @Default(false) bool cacheEvicted,
    @Default(false) bool canResume,
    @Default(false) bool canRestart,
    @Default(false) bool canCancel,
    @Default(false) bool canExport,
    @Default(false) bool canExportPartial,
    @Default(true) bool restartFromBeginning,
    @Default(true) bool restartRequiresSourceCheck,
    @Default([]) List<FileTransferSnapshot> items,
    FileTransferBatch? batch,
  }) = _FileTransferSnapshot;

  factory FileTransferSnapshot.fromJson(Map<String, Object?> json) =>
      _$FileTransferSnapshotFromJson(json);
}

@freezed
abstract class FileTransferBatch with _$FileTransferBatch {
  const factory FileTransferBatch({
    required String batchId,
    @Default('') String deviceId,
    @Default(FileTransferDirection.pull) FileTransferDirection direction,
    @Default(FileTransferDestination.localPath)
    FileTransferDestination destinationScope,
    @Default(FileTransferStatus.unknown) FileTransferStatus status,
    @Default(0) int itemCount,
    @Default(0) int fileCount,
    @Default(0) int directoryCount,
    @Default(0) int completed,
    @Default(0) int failed,
    @Default(0) int cancelled,
    @Default(0) int skipped,
    @Default(0) int interrupted,
    @Default(0) int transferred,
    @Default(0) int total,
    @Default(false) bool canCancel,
    @Default(0) int selectedRootCount,
    @Default(false) bool canResume,
    @Default(false) bool canRestart,
    @Default(true) bool selectionSnapshot,
  }) = _FileTransferBatch;

  factory FileTransferBatch.fromJson(Map<String, Object?> json) =>
      _$FileTransferBatchFromJson(json);
}

@freezed
abstract class FileTransferCollection with _$FileTransferCollection {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory FileTransferCollection({
    @Default([]) List<FileTransferSnapshot> transfers,
    @Default([]) List<FileTransferBatch> batches,
  }) = _FileTransferCollection;

  factory FileTransferCollection.fromJson(Map<String, Object?> json) =>
      _$FileTransferCollectionFromJson(json);
}
