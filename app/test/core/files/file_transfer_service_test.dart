import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_changes_provider.dart';
import 'package:scrcpy_connect/core/files/file_executor.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/files/models/file_directory_facts.dart';
import 'package:scrcpy_connect/core/files/models/file_stamp.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_event.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_plan.dart';
import 'package:scrcpy_connect/core/files/models/file_transfer_snapshot.dart';

void main() {
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
    final container = ProviderContainer(
      overrides: [runtimeEventsProvider.overrideWithValue(events.stream)],
    );
    final received = <RuntimeEvent>[];
    final changes = <FileChange>[];
    final subscription = events.stream.listen(received.add);
    final invalidations = container
        .read(fileChangesProvider)
        .listen(changes.add);
    await events.attach(files: [transfers.events]);
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

    final completed = events.stream.firstWhere(
      (event) => event.data is FileTransferChanged && executor.committed,
    );
    executor.copied.complete(3);
    await completed;
    await Future<void>.delayed(Duration.zero);
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
      return stamp;
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
    expect(expected, stamp);
    cancellation.check();
    _part = temporary;
    onProgress(1);
    copyStarted.complete();
    return copied.future;
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
