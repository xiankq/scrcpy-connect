import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_readiness_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_directory_notifier.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_publication_leases.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/files/file_transfer_journal.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_facts.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_event.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';

void main() {
  test('分享提交接入真实传输与日志，重复入口不重复执行且完成证据已落盘', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-share-');
    final executor = _Executor();
    final leases = _PendingPublication();
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
      publication: leases,
    );
    addTearDown(() async {
      if (!leases.begun.isCompleted) leases.begun.complete(null);
      if (!executor.copied.isCompleted) executor.copied.complete(3);
      await transfers.close();
      await directory.delete(recursive: true);
    });
    final first = transfers.startTransfer(_plan(), shareId: 'share');
    final duplicate = transfers.startTransfer(_plan(), shareId: 'share');
    leases.begun.complete(null);
    final receipt = await first;
    expect(await duplicate, receipt);
    expect(
      (leases.outcomes.single as FilePublicationPublished).receipt.batchId,
      receipt.batchId,
    );
    await executor.copyStarted.future;
    executor.copied.complete(3);
    final evidence = await leases.evidence.future;
    expect(evidence.transfers.single.batchId, receipt.batchId);
    expect(evidence.transfers.single.completed, isTrue);
    expect(executor.copyCalls, 1);
    final durable = await FileTransferJournal(directory).load();
    expect(durable.values.single.shareId, 'share');
    expect(durable.values.single.status, FileTransferStatus.completed);
    expect(durable.values.single.transferred, 3);
  });

  for (final close in [false, true]) {
    test('${close ? '关闭所有者' : '停止设备'}等待迟到来源租约，禁止产生后继传输', () async {
      final directory = await Directory.systemTemp.createTemp(
        'transfer-publication-',
      );
      final executor = _Executor();
      final leases = _PendingPublication();
      final transfers = await FileTransferService.open(
        executor: executor,
        dataDirectory: directory,
        publication: leases,
      );
      addTearDown(() async {
        if (!leases.begun.isCompleted) leases.begun.complete(null);
        if (!executor.copied.isCompleted) executor.copied.complete(3);
        await transfers.close();
        await directory.delete(recursive: true);
      });
      final submitted = transfers.startTransfer(_plan(), shareId: 'share');
      final cancelled = expectLater(
        submitted,
        throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
      var stopped = false;
      final stopping =
          (close ? transfers.close() : transfers.cancelDevice('device')).then(
            (_) => stopped = true,
          );
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      await expectLater(
        transfers.startTransfer(_plan(), shareId: 'successor'),
        throwsA(
          isA<FileFailure>().having(
            (e) => e.code,
            'code',
            close ? 'closed' : 'transfer_active',
          ),
        ),
      );
      leases.begun.complete(null);
      await cancelled;
      await stopping;
      expect(leases.outcomes.single, isA<FilePublicationUnpublished>());
      expect(executor.copyCalls, 0);
      expect((await transfers.readTransfers()).transfers, isEmpty);
      expect(await FileTransferJournal(directory).load(), isEmpty);
    });
  }

  test('旧提交中的任务只恢复未知事实，不重放文件操作，来源身份按旧格式归一', () async {
    final directory = await Directory.systemTemp.createTemp(
      'transfer-recover-',
    );
    final executor = _Executor();
    final journal = File('${directory.path}/file_tasks.v2.journal');
    await journal.writeAsString(
      '${jsonEncode({
        'version': 2,
        'sequence': 1,
        'task': {
          'id': 'old',
          'deviceId': 'device',
          'direction': 'push',
          'source': '/tmp/source.bin',
          'destination': '/sdcard/file.bin',
          'status': 'finalizing',
          'generation': 4,
          'sourceStamp': {'mode': 0, 'size': 3, 'modifiedSeconds': 1},
        },
      })}\n',
    );
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    addTearDown(() async {
      await transfers.close();
      await directory.delete(recursive: true);
    });
    final restored = await transfers.readTransfer('old');
    expect(restored.batchId, 'old');
    expect(restored.generation, 4);
    expect(restored.status, FileTransferStatus.interrupted);
    expect(restored.errorCode, 'result_unknown');
    expect(restored.partialDestinationPossible, isTrue);
    expect(restored.canRestart, isFalse);
    await expectLater(
      transfers.restartTransfer('old'),
      throwsA(
        isA<FileFailure>().having((e) => e.code, 'code', 'restart_unavailable'),
      ),
    );
    await transfers.clearTransferHistory([
      const FileTransferTarget.task('old'),
    ]);
    expect((await transfers.readTransfer('old')).historyHidden, isFalse);
    expect(executor.copyCalls, 0);
    final records = await FileTransferJournal(directory).load();
    expect(records['old']!.sourceStamp, _Executor.stamp);
    expect(records['old']!.status, FileTransferStatus.interrupted);
    expect(records['old']!.partialDestinationPossible, isTrue);
  });

  for (final kind in [FileTransferKind.symlink, FileTransferKind.unsupported]) {
    test('跳过的 ${kind.name} 保留真实类型，查询不因枚举转换失败', () async {
      final directory = await Directory.systemTemp.createTemp('transfer-kind-');
      final executor = _Executor(
        sourceStamp: FileStamp(
          mode: kind == .symlink ? 0xa000 : 0,
          size: 0,
          modifiedSeconds: 1,
        ),
      );
      final transfers = await FileTransferService.open(
        executor: executor,
        dataDirectory: directory,
      );
      addTearDown(() async {
        await transfers.close();
        await directory.delete(recursive: true);
      });
      final submitted = await transfers.startTransfer(_plan());
      final skipped = await transfers.readTransfer(submitted.transferId!);
      expect(skipped.kind, kind);
      expect(skipped.status, FileTransferStatus.skipped);
      expect(skipped.items.single.kind, kind);
      expect((await transfers.readTransfers()).transfers.single.kind, kind);
      expect(executor.copyCalls, 0);
    });
  }

  test('取消清理失败保留原执行资源，重试恢复已确认结果且不改写旧快照', () async {
    final directory = await Directory.systemTemp.createTemp(
      'transfer-cleanup-',
    );
    final resource = _Resource();
    final executor = _Executor(cleanup: resource);
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    addTearDown(() async {
      resource.fail = false;
      await transfers.close();
      await directory.delete(recursive: true);
    });
    final submitted = await transfers.startTransfer(_plan());
    await executor.copyStarted.future;
    final running = await transfers.readTransfer(submitted.transferId!);
    final target = FileTransferTarget.task(submitted.transferId!);
    await expectLater(
      transfers.cancelTransfer(target),
      throwsA(
        isA<FileFailure>().having(
          (e) => e.code,
          'code',
          'file_cleanup_unconfirmed',
        ),
      ),
    );
    final unknown = await transfers.readTransfer(submitted.transferId!);
    expect(unknown.status, FileTransferStatus.failed);
    expect(unknown.cleanupPending, isTrue);
    expect(unknown.errorCode, 'result_unknown');
    expect(unknown.canRestart, isFalse);
    expect(resource.closes, 1);
    expect(running.status, FileTransferStatus.running);
    expect(running.cleanupPending, isFalse);
    resource.fail = false;
    await transfers.cancelTransfer(target);
    final cancelled = await transfers.readTransfer(submitted.transferId!);
    expect(cancelled.status, FileTransferStatus.cancelled);
    expect(cancelled.cleanupPending, isFalse);
    expect(cancelled.partialDestinationPossible, isFalse);
    expect(cancelled.errorCode, 'cancelled');
    expect(cancelled.transferred, 1);
    expect(cancelled.generation, 0);
    expect(unknown.cleanupPending, isTrue);
    expect(executor.copyCalls, 1);
    expect(resource.closes, 2);
    await transfers.removeTransfer(target);
    await transfers.close();
    expect(resource.closes, 2);
  });

  test('提交回执未知不能变成完成或重试，持久记录保留实际进度', () async {
    final directory = await Directory.systemTemp.createTemp(
      'transfer-unknown-',
    );
    final executor = _Executor(
      commitFailure: const FileFailure('result_unknown', '提交回执丢失'),
    );
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    addTearDown(() async {
      if (!executor.copied.isCompleted) executor.copied.complete(3);
      await transfers.close();
      await directory.delete(recursive: true);
    });
    final submitted = await transfers.startTransfer(_plan());
    await executor.copyStarted.future;
    final settled = transfers.events
        .asyncMap((_) => transfers.readTransfer(submitted.transferId!))
        .firstWhere((snapshot) => snapshot.errorCode == 'result_unknown');
    final directoryChanged = transfers.events
        .where((event) => event is FileTransferDirectoryChanged)
        .cast<FileTransferDirectoryChanged>()
        .first;
    executor.copied.complete(3);
    final unknown = await settled;
    expect(unknown.status, FileTransferStatus.failed);
    expect(unknown.transferred, 3);
    expect(unknown.partialDestinationPossible, isTrue);
    expect(unknown.canRestart, isFalse);
    expect(unknown.canExport, isFalse);
    expect((await directoryChanged).path, '/sdcard');
    await transfers.close();
    final durable = (await FileTransferJournal(directory)
        .load())[submitted.transferId]!;
    expect(durable.status, FileTransferStatus.failed);
    expect(durable.saveMode, 'committing');
    expect(durable.transferred, 3);
    expect(durable.errorCode, 'result_unknown');
    expect(executor.copyCalls, 1);
  });

  test('同目录并发批次等最后一个执行者退出才通知，取消也结算目录变化', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-list-');
    final executor = _ConcurrentExecutor();
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    final changes = <FileTransferDirectoryChanged>[];
    final subscription = transfers.events.listen((event) {
      if (event is FileTransferDirectoryChanged) changes.add(event);
    });
    addTearDown(() async {
      for (final copy in executor.copies) {
        if (!copy.isCompleted) copy.complete(3);
      }
      await transfers.close();
      await subscription.cancel();
      await directory.delete(recursive: true);
    });
    final first = await transfers.startTransfer(_plan());
    final second = await transfers.startTransfer(_plan());
    await executor.bothStarted.future;
    expect(changes, isEmpty);
    final firstCompleted = transfers.events
        .asyncMap((_) => transfers.readTransfer(first.transferId!))
        .firstWhere((snapshot) => snapshot.status == .completed);
    executor.copies.first.complete(3);
    await firstCompleted;
    // 等待原 worker 的真实收尾，不用延时猜测事件是否已经到达。
    await transfers.cancelTransfer(FileTransferTarget.batch(first.batchId));
    expect(
      (await transfers.readTransfer(first.transferId!)).status,
      FileTransferStatus.completed,
    );
    expect(changes, isEmpty);
    await transfers.cancelTransfer(FileTransferTarget.batch(second.batchId));
    expect(
      (await transfers.readTransfer(second.transferId!)).status,
      FileTransferStatus.cancelled,
    );
    expect(changes, hasLength(1));
    expect(changes.single.deviceId, 'device');
    expect(changes.single.path, '/sdcard');
  });

  test('排队批次可立即取消，停止设备不等待其他批次空出名额', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-queue-');
    final executor = _ConcurrentExecutor();
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    addTearDown(() async {
      for (final copy in executor.copies) {
        if (!copy.isCompleted) copy.complete(3);
      }
      await transfers.close();
      await directory.delete(recursive: true);
    });
    final first = await transfers.startTransfer(_plan());
    final second = await transfers.startTransfer(_plan());
    await executor.bothStarted.future;
    final waiting = await transfers.startTransfer(_plan());
    expect(
      (await transfers.readTransfer(waiting.transferId!)).status,
      FileTransferStatus.queued,
    );
    await transfers
        .cancelTransfer(FileTransferTarget.batch(waiting.batchId))
        .timeout(const Duration(seconds: 2));
    expect(executor.copies, hasLength(2));
    expect(executor.copies.every((copy) => !copy.isCompleted), isTrue);
    expect(
      (await transfers.readTransfer(waiting.transferId!)).status,
      FileTransferStatus.cancelled,
    );
    // 同设备的在途任务仍正常排空；被取消批次没有在名额释放后复活。
    await transfers.cancelDevice('device');
    expect(executor.copies, hasLength(2));
    expect(
      (await transfers.readTransfer(first.transferId!)).status,
      FileTransferStatus.cancelled,
    );
    expect(
      (await transfers.readTransfer(second.transferId!)).status,
      FileTransferStatus.cancelled,
    );
    await transfers.close();
    final durable = await FileTransferJournal(directory).load();
    expect(
      durable.values.every(
        (record) => record.status == FileTransferStatus.cancelled,
      ),
      isTrue,
    );
  });

  test('实际传输所有者的持久变更和进度共用业务水位，并直接驱动文件查询失效', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-events-');
    final executor = _Executor();
    final transfers = await FileTransferService.open(
      executor: executor,
      dataDirectory: directory,
    );
    final events = RuntimeEvents(
      acceptState: ({required sequence, required telemetry}) => true,
      onState: (_) {},
      beforePublish: (_) {},
      afterState: (_) {},
      handlePlatform: (_) async {},
      isDisposed: () => false,
    );
    final directories = _ObservedDirectories();
    final container = ProviderContainer(
      overrides: [
        runtimeEventsProvider.overrideWithValue(events.stream),
        fileDirectoriesProvider.overrideWithValue(directories),
        deviceReadinessProvider('device').overrideWithValue(
          const DeviceReadiness(connectionId: 'connection', status: .connected),
        ),
      ],
    );
    final received = <RuntimeEvent>[];
    final changes = <FileChange>[];
    final subscription = events.stream.listen(received.add);
    final invalidations = container
        .read(fileChangesProvider)
        .listen(changes.add);
    await events.attach(files: [transfers.events]);
    const target = (deviceId: 'device', path: '/sdcard');
    container.listen(fileDirectoryProvider(target), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(directories.reads, 1);
    addTearDown(() async {
      if (!executor.copied.isCompleted) executor.copied.complete(3);
      await transfers.close();
      await events.detach();
      await subscription.cancel();
      await invalidations.cancel();
      container.dispose();
      await events.close();
      await directory.delete(recursive: true);
    });

    final submitted = await transfers.startTransfer(
      FileTransferPlan(
        deviceId: 'device',
        direction: .push,
        items: [
          const FileTransferSelection(
            source: '/tmp/source.bin',
            destination: '/sdcard/file.bin',
          ),
        ],
      ),
    );
    await executor.copyStarted.future;
    await Future<void>.delayed(Duration.zero);
    final progress = received
        .map((event) => event.data)
        .whereType<FileTransferProgress>()
        .single;
    expect(progress.transferId, submitted.transferId);
    expect(progress.transferred, 1);
    expect(changes, isNotEmpty);
    expect(changes.every((change) => change.kind == .transfer), isTrue);
    expect(directories.reads, 1);

    final completed = events.stream.firstWhere(
      (event) => event.data is FileTransferChanged && executor.committed,
    );
    final directoryChanged = container
        .read(fileChangesProvider)
        .firstWhere((change) => change.kind == FileChangeKind.directory);
    executor.copied.complete(3);
    await completed;
    final directoryChange = await directoryChanged.timeout(
      const Duration(seconds: 5),
    );
    expect(directoryChange.deviceId, 'device');
    expect(directoryChange.path, '/sdcard');
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(directories.reads, 2);
    expect(container.read(fileDirectoryProvider(target)).verified, isTrue);
    final task = await transfers.readTransfer(submitted.transferId!);
    expect(task.status, FileTransferStatus.completed);
    expect(task.transferred, 3);
    expect(
      received.map((event) => event.sequence),
      List.generate(received.length, (index) => index + 1),
    );
    expect(events.cursor, (
      sequence: received.length,
      revision: received.length,
    ));
    expect(changes.length, received.length);
    final journal = await File('${directory.path}/file_tasks.v2.journal')
        .readAsString();
    expect(journal, contains('"status":"completed"'));
    expect(journal, contains('"transferred":3'));
  });
}

final class _Executor implements FileExecutor {
  _Executor({this.sourceStamp = stamp, this.cleanup, this.commitFailure});
  final FileStamp sourceStamp;
  final FileExecutionResource? cleanup;
  final FileFailure? commitFailure;
  var copyCalls = 0;
  final copyStarted = Completer<void>();
  final copied = Completer<int>();
  bool committed = false;
  String? _part;
  static const stamp = FileStamp(mode: 0x8000, size: 3, modifiedSeconds: 1);

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    expect(device, 'device');
    cancellation.check();
    if (path == '/tmp/source.bin') {
      expect(local, isTrue);
      return sourceStamp;
    }
    expect(path, '/sdcard/file.bin');
    expect(local, isFalse);
    throw const FileFailure('not_found', '目标不存在');
  }

  @override
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  }) {
    expect(device, 'device');
    expect(source, '/tmp/source.bin');
    expect(push, isTrue);
    expect(expected, sourceStamp);
    copyCalls++;
    cancellation.check();
    _part = temporary;
    onProgress(1);
    copyStarted.complete();
    final remove = cancellation.onCancel(() {
      if (cleanup case final resource? when !copied.isCompleted) {
        copied.completeError(
          FileExecutionCleanupFailure(
            resource,
            const FileFailure('cancelled', '已取消'),
          ),
        );
      }
    });
    return copied.future.whenComplete(remove);
  }

  @override
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  }) async {
    expect(device, 'device');
    expect(action, 'commit');
    expect(path, _part);
    expect(destination, '/sdcard/file.bin');
    expect(local, isFalse);
    cancellation.check();
    if (commitFailure case final failure?) throw failure;
    committed = true;
    return 'atomicRename';
  }

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) => throw StateError('单文件传输不得枚举目录');
}

FileTransferPlan _plan() => FileTransferPlan(
  deviceId: 'device',
  direction: .push,
  items: [
    const FileTransferSelection(
      source: '/tmp/source.bin',
      destination: '/sdcard/file.bin',
    ),
  ],
);

final class _Resource implements FileExecutionResource {
  var fail = true;
  var closes = 0;
  @override
  Future<void> close() async {
    closes++;
    if (fail) throw StateError('原 worker 尚未退出');
  }
}

final class _ConcurrentExecutor extends _Executor {
  final copies = <Completer<int>>[];
  final bothStarted = Completer<void>();

  @override
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  }) {
    final copied = Completer<int>();
    copies.add(copied);
    if (copies.length == 2) bothStarted.complete();
    final remove = cancellation.onCancel(() {
      if (!copied.isCompleted) {
        copied.completeError(const FileFailure('cancelled', '已取消'));
      }
    });
    return copied.future.whenComplete(remove);
  }

  @override
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    return 'atomicRename';
  }
}

final class _ObservedDirectories implements FileDirectories {
  int reads = 0;

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) async {
    reads++;
    return FileDirectorySnapshot(deviceId: target.deviceId, path: target.path);
  }
}

final class _PendingPublication implements FilePublicationLeases {
  final begun = Completer<FilePublicationReceipt?>();
  final outcomes = <FilePublicationOutcome>[];
  final evidence = Completer<DurableFilePublications>();

  @override
  Future<FilePublicationReceipt?> begin(
    String share,
    FileTransferPlan plan, {
    required String transferId,
  }) => begun.future;

  @override
  Future<void> finish(String share, FilePublicationOutcome outcome) async {
    outcomes.add(outcome);
  }

  @override
  Future<Set<String>> get sourcePaths async => {'/tmp/source.bin'};

  @override
  Future<FilePublicationReconciliation> reconcile(
    DurableFilePublications evidence,
  ) async {
    if (!this.evidence.isCompleted) this.evidence.complete(evidence);
    return const FilePublicationReconciliation(
      reconciled: true,
      snapshotComplete: true,
    );
  }
}
