import 'file_transfer_record.dart';
import 'file_transfer_snapshot.dart';

/// 只聚合持久任务事实，不读取或持有 worker、租约及执行资源。
List<FileTransferBatch> summarizeTransferBatches(
  Iterable<FileTransferRecord> records,
) {
  final groups = <String, List<FileTransferRecord>>{};
  for (final task in records) {
    groups.putIfAbsent(task.batchId, () => []).add(task);
  }
  return groups.entries.map((g) {
    final tasks = g.value;
    int count(FileTransferStatus status) =>
        tasks.where((t) => t.status == status).length;
    final active = tasks.any(
      (t) =>
          !_terminal(t.status) ||
          t.kind == FileTransferKind.directory &&
              t.status == FileTransferStatus.completed &&
              t.treeVerified != true,
    );
    final status = count(FileTransferStatus.conflict) > 0
        ? FileTransferStatus.conflict
        : active
        ? FileTransferStatus.running
        : count(FileTransferStatus.failed) > 0
        ? FileTransferStatus.partialFailure
        : count(FileTransferStatus.interrupted) > 0
        ? FileTransferStatus.interrupted
        : count(FileTransferStatus.cancelled) > 0
        ? FileTransferStatus.cancelled
        : count(FileTransferStatus.skipped) > 0
        ? FileTransferStatus.completedWithSkips
        : FileTransferStatus.completed;
    return FileTransferBatch(
      batchId: g.key,
      deviceId: tasks.first.deviceId,
      direction: tasks.first.direction,
      destinationScope: tasks.first.destinationScope,
      status: status,
      itemCount: tasks.length,
      fileCount: tasks.where((t) => t.kind == FileTransferKind.file).length,
      directoryCount: tasks
          .where((t) => t.kind == FileTransferKind.directory)
          .length,
      completed: count(FileTransferStatus.completed),
      failed: count(FileTransferStatus.failed),
      cancelled: count(FileTransferStatus.cancelled),
      skipped: count(FileTransferStatus.skipped),
      interrupted: count(FileTransferStatus.interrupted),
      transferred: tasks.fold<int>(0, (n, t) => n + (t.transferred)),
      total: tasks.fold<int>(0, (n, t) => n + (t.total ?? 0)),
      canCancel: active || tasks.any((t) => t.cleanupPending == true),
      selectedRootCount: tasks.where((t) => t.parentId == null).length,
    );
  }).toList();
}

bool _terminal(FileTransferStatus status) => switch (status) {
  .completed || .skipped || .failed || .cancelled || .interrupted => true,
  _ => false,
};
