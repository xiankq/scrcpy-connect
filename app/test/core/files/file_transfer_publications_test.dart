import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/file_transfer_publications.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_record.dart';

void main() {
  test('同一来源的并发提交共用结果，参数变化拒绝，后续提交复用持久回执', () async {
    final leases = _Leases();
    final published = Completer<FileTransferSubmission>();
    var calls = 0;
    final publications = FileTransferPublications(
      leases: leases,
      publish: (plan, {required shareId, required batchId}) {
        calls++;
        return published.future;
      },
      readRecords: () => [],
      readWriteTail: () => _written,
    );
    final first = publications.submit(_plan(), shareId: 'share');
    final duplicate = publications.submit(_plan(), shareId: 'share');
    expect(
      () => publications.submit(_plan(device: 'other'), shareId: 'share'),
      throwsA(_failure('share_submission_mismatch')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(leases.begins, 1);
    const receipt = FileTransferSubmission(
      batchId: 'batch',
      transferId: 'task',
      itemCount: 1,
      status: .queued,
    );
    published.complete(receipt);
    expect(await first, receipt);
    expect(await duplicate, receipt);
    final reused = await publications.submit(_plan(), shareId: 'share');
    expect(reused.batchId, 'batch');
    expect(reused.transferId, 'task');
    expect(reused.reusedTransfer, isTrue);
    expect(calls, 1);
  });

  for (final registered in [false, true]) {
    test('发布失败且${registered ? '已有任务登记时保留未知' : '没有任务登记时确认未发布'}', () async {
      final leases = _Leases();
      final records = <FileTransferRecord>[];
      final publications = FileTransferPublications(
        leases: leases,
        publish: (plan, {required shareId, required batchId}) async {
          if (registered) records.add(_record('task', batch: batchId));
          throw const FileFailure('storage_failed', '任务未取得发布回执');
        },
        readRecords: () => records,
        readWriteTail: () => _written,
      );
      await expectLater(
        publications.submit(_plan(), shareId: 'share'),
        throwsA(_failure('storage_failed')),
      );
      expect(
        leases.outcomes.single,
        registered
            ? isA<FilePublicationUnknown>()
            : isA<FilePublicationUnpublished>(),
      );
    });
  }

  test('发布成功但来源回执写入失败只标待核对，不重发已登记任务', () async {
    final leases = _Leases()..failFinish = true;
    var calls = 0;
    final publications = FileTransferPublications(
      leases: leases,
      publish: (plan, {required shareId, required batchId}) async {
        calls++;
        return FileTransferSubmission(
          batchId: batchId,
          transferId: 'task',
          itemCount: 1,
          status: .queued,
        );
      },
      readRecords: () => [],
      readWriteTail: () => _written,
    );
    final receipt = await publications.submit(_plan(), shareId: 'share');
    expect(receipt.transferId, 'task');
    expect(receipt.sourceLeaseReconciliationPending, isTrue);
    expect(leases.outcomes.single, isA<FilePublicationPublished>());
    expect(calls, 1);
  });

  test('核对等待持久快照，以整个消费批次判断完成并覆盖目录后代', () async {
    final leases = _Leases()..paths = {'/tmp/shared'};
    final firstWrite = Completer<void>();
    final nextWrite = Completer<void>();
    var tail = firstWrite.future;
    var reads = 0;
    final records = <FileTransferRecord>[];
    final publications = FileTransferPublications(
      leases: leases,
      publish: (plan, {required shareId, required batchId}) =>
          throw StateError('只读核对不能提交任务'),
      readRecords: () {
        reads++;
        return records;
      },
      readWriteTail: () => tail,
    );
    final pending = publications.reconcile();
    await Future<void>.delayed(Duration.zero);
    expect(leases.evidence, isNull);
    expect(reads, 0);
    tail = nextWrite.future;
    firstWrite.complete();
    await Future<void>.delayed(Duration.zero);
    expect(leases.evidence, isNull);
    expect(reads, 0);
    records.addAll([
      _record('child', batch: 'mixed', source: '/tmp/shared/child'),
      _record('other', batch: 'mixed', source: '/tmp/other', status: .failed),
      _record('nested', batch: 'done', source: '/tmp/shared/nested/file'),
      _record('unrelated', batch: 'unrelated', source: '/tmp/unrelated'),
      _record('pull', batch: 'pull', source: '/tmp/shared', direction: .pull),
    ]);
    nextWrite.complete();
    await pending;
    expect(reads, 1);
    final evidence = leases.evidence!;
    expect(evidence.complete, isTrue);
    expect(evidence.coveredSources, {'/tmp/shared'});
    expect(evidence.transfers.map((batch) => batch.batchId), ['mixed', 'done']);
    expect(evidence.transfers.first.completed, isFalse);
    expect(evidence.transfers.last.completed, isTrue);
    expect(
      evidence.transfers.every(
        (batch) => batch.sources.single == '/tmp/shared',
      ),
      isTrue,
    );
  });
}

final _written = Future<void>.value();

Matcher _failure(String code) =>
    isA<FileFailure>().having((error) => error.code, 'code', code);

FileTransferPlan _plan({String device = 'device'}) => FileTransferPlan(
  deviceId: device,
  direction: .push,
  items: [
    const FileTransferSelection(
      source: '/tmp/source',
      destination: '/sdcard/file',
    ),
  ],
);

FileTransferRecord _record(
  String id, {
  required String batch,
  String source = '/tmp/source',
  FileTransferStatus status = .completed,
  FileTransferDirection direction = .push,
}) => FileTransferRecord(
  id: id,
  deviceId: 'device',
  batchId: batch,
  direction: direction,
  source: source,
  destination: '/sdcard/file',
  status: status,
);

final class _Leases implements FilePublicationLeases {
  var begins = 0;
  var failFinish = false;
  var paths = <String>{};
  FilePublicationReceipt? _receipt;
  final outcomes = <FilePublicationOutcome>[];
  DurableFilePublications? evidence;

  @override
  Future<FilePublicationReceipt?> begin(
    String share,
    FileTransferPlan plan, {
    required String transferId,
  }) async {
    begins++;
    return _receipt;
  }

  @override
  Future<void> finish(String share, FilePublicationOutcome outcome) async {
    outcomes.add(outcome);
    if (failFinish) throw StateError('来源回执写入失败');
    if (outcome case FilePublicationPublished(:final receipt)) {
      _receipt = receipt;
    }
  }

  @override
  Future<Set<String>> get sourcePaths async => Set.of(paths);

  @override
  Future<FilePublicationReconciliation> reconcile(
    DurableFilePublications evidence,
  ) async {
    this.evidence = evidence;
    return const FilePublicationReconciliation(
      reconciled: true,
      snapshotComplete: true,
    );
  }
}
