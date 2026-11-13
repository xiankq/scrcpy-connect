import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_record.dart';
import 'package:uuid/uuid.dart';

/// 分享来源与传输批次的交接：去重、发布回执和持久结果核对。
/// 传输所有者先封住准入，再取消并等待这里已登记的来源交接。
final class FileTransferPublications {
  FileTransferPublications({
    required this._leases,
    required this._publish,
    required this._readRecords,
    required this._readWriteTail,
  });

  final FilePublicationLeases? _leases;
  final Future<FileTransferSubmission> Function(
    FileTransferPlan plan, {
    required String shareId,
    required String batchId,
  })
  _publish;
  final Iterable<FileTransferRecord> Function() _readRecords;
  // 每次任务写入均替换尾部；读取当前尾部不能创建新的 Future。
  final Future<void> Function() _readWriteTail;
  final _shareSubmissions = <String, _ShareSubmission>{};

  /// 同步撤销当前交接；返回值只在迟到租约和发布结果均结算后完成。
  Future<void> cancelPending({String? deviceId}) {
    final pending = _shareSubmissions.values
        .where(
          (submission) => deviceId == null || submission.device == deviceId,
        )
        .toList();
    for (final submission in pending) {
      submission.cancellation.cancel();
    }
    return Future.wait(pending.map((submission) => submission.finished.future));
  }

  /// 同一分享只提交一次；持久指纹从实际执行计划生成。
  Future<FileTransferSubmission> submit(
    FileTransferPlan plan, {
    required String shareId,
  }) {
    if (plan.direction != FileTransferDirection.push) {
      throw const FileFailure('invalid_argument', '分享来源只能发送到设备。');
    }
    final previous = _shareSubmissions[shareId];
    if (previous != null) {
      if (!previous.matches(plan)) {
        throw const FileFailure('share_submission_mismatch', '本次分享已经使用其他传输参数。');
      }
      return previous.result.future;
    }
    final submission = _ShareSubmission(plan);
    // 来源租约尚未返回也属于本设备的准备责任，先登记再调用外部所有者。
    _shareSubmissions[shareId] = submission;
    unawaited(() async {
      try {
        submission.result.complete(
          await _publishShare(
            plan,
            shareId: shareId,
            cancellation: submission.cancellation,
          ),
        );
      } catch (error, stack) {
        submission.result.completeError(error, stack);
      } finally {
        _shareSubmissions.remove(shareId);
        submission.finished.complete();
      }
    }());
    return submission.result.future;
  }

  Future<FileTransferSubmission> _publishShare(
    FileTransferPlan plan, {
    required String shareId,
    required FileCancellation cancellation,
  }) async {
    final leases = _leases;
    if (leases == null) {
      throw const FileFailure('share_not_configured', '分享来源租约执行器尚未配置。');
    }
    final batch = const Uuid().v4();
    final previous = await leases.begin(shareId, plan, transferId: batch);
    if (previous != null) {
      return FileTransferSubmission(
        batchId: previous.batchId,
        transferId: previous.transferId,
        itemCount:
            previous.itemCount ??
            _readRecords()
                .where((record) => record.batchId == previous.batchId)
                .length,
        status: previous.status,
        reusedTransfer: true,
      );
    }
    try {
      // 停止可能发生在来源登记等待期间；迟到租约只能收尾，不能创建新传输。
      cancellation.check();
      final receipt = await _publish(plan, shareId: shareId, batchId: batch);
      try {
        await leases.finish(
          shareId,
          FilePublicationOutcome.published(
            FilePublicationReceipt.fromSubmission(receipt),
          ),
        );
      } catch (_) {
        return receipt.copyWith(sourceLeaseReconciliationPending: true);
      }
      return receipt;
    } catch (error, stack) {
      final unpublished = !_readRecords().any(
        (record) => record.batchId == batch,
      );
      try {
        await leases.finish(
          shareId,
          unpublished
              ? const FilePublicationOutcome.unpublished()
              : const FilePublicationOutcome.unknown(),
        );
      } catch (_) {
        // 回执缺失时保留源租约。
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<FilePublicationReconciliation> reconcile() async {
    final sources = _leases;
    if (sources == null) {
      return const FilePublicationReconciliation(
        reconciled: false,
        snapshotComplete: false,
        reason: FilePublicationReconciliationReason.notConfigured,
      );
    }
    final paths = await sources.sourcePaths;
    // 等待期间追加的提交同样必须落盘；稳定尾部与取快照之间不再异步切换。
    while (true) {
      final pending = _readWriteTail();
      await pending;
      if (identical(pending, _readWriteTail())) break;
    }
    final records = _readRecords().toList();
    Set<String> rootsFor(Object? source) => source is! String
        ? {}
        : {
            for (final root in paths)
              if (p.equals(root, source) || p.isWithin(root, source)) root,
          };
    // Directory owners cover every descendant, including independently selected
    // children. All consumers still contribute their whole batch status.
    // Unrelated history does not spend the source owner's bounded proof budget.
    final batches = records
        .where(
          (task) =>
              task.direction == FileTransferDirection.push &&
              rootsFor(task.source).isNotEmpty,
        )
        .map((task) => task.batchId)
        .toSet();
    final groups = <String, List<FileTransferRecord>>{};
    for (final task in records.where(
      (t) => t.direction == FileTransferDirection.push,
    )) {
      final batch = task.batchId;
      if (!batches.contains(batch)) continue;
      groups.putIfAbsent(batch, () => []).add(task);
    }
    return sources.reconcile(
      DurableFilePublications(
        complete: true,
        coveredSources: paths,
        transfers: [
          for (final group in groups.entries)
            DurableFilePublication(
              batchId: group.key,
              completed: group.value.every(
                (task) => task.status == FileTransferStatus.completed,
              ),
              sources: group.value
                  .expand((task) => rootsFor(task.source))
                  .toSet(),
            ),
        ],
      ),
    );
  }
}

/// 分享来源交接在普通传输准备前开始，停止必须等待其真实结算。
final class _ShareSubmission {
  _ShareSubmission(this.plan);
  final FileTransferPlan plan;
  String get device => plan.deviceId;
  bool matches(FileTransferPlan other) =>
      plan.deviceId == other.deviceId &&
      plan.direction == other.direction &&
      plan.conflict == other.conflict &&
      plan.destination == other.destination &&
      plan.items.length == other.items.length &&
      Iterable<int>.generate(plan.items.length).every(
        (index) =>
            plan.items[index].source == other.items[index].source &&
            plan.items[index].destination == other.items[index].destination,
      );
  final cancellation = FileCancellation();
  final result = Completer<FileTransferSubmission>();
  final finished = Completer<void>();
}
