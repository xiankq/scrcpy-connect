import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';

import 'support/file_executor_fixture.dart'
    show FixtureExecutor, regular, until;

void main() {
  late Directory root;
  late _Executor executor;
  late _Publication publication;
  late TransferCoordinator owner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transfer-batch-');
    executor = _Executor()
      ..stamps['/first'] = regular
      ..stamps['/second'] = regular;
    publication = _Publication();
    owner = await TransferCoordinator.open(
      executor: executor,
      publication: publication,
      dataDirectory: root,
    );
  });

  tearDown(() async {
    executor.release();
    publication.release();
    await owner.close();
    await root.delete(recursive: true);
  });

  test('取消排队兄弟任务不取消同批正在执行的任务', () async {
    executor.block = true;
    final receipt = await owner.startTransfer('device', true, const [
      {'source': '/first', 'destination': '/sdcard/first'},
      {'source': '/second', 'destination': '/sdcard/second'},
    ]);
    await executor.entered.future;
    final tasks = (owner.transfers()['transfers']! as List)
        .cast<Map<String, Object?>>();
    final second = tasks.singleWhere((task) => task['itemIndex'] == 1);
    final secondId = second['id']! as String;
    final cancelling = owner.cancelTransfer(secondId);
    await until(() => owner.transfer(secondId)['status'] == 'cancelled');
    expect(executor.cancellation!.isCancelled, isFalse);
    executor.release();
    await cancelling;
    expect(
      owner.transfer(receipt['transferId']! as String)['status'],
      'completed',
    );
    expect(owner.transfer(secondId)['status'], 'cancelled');
    expect(executor.contents['/sdcard/first'], [1, 2, 3, 4]);
    expect(executor.contents.containsKey('/sdcard/second'), isFalse);
    expect(
      executor.calls.where((call) => call.startsWith('copy:')),
      hasLength(1),
    );
  });

  for (final (closing, remove) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    test(
      '${remove ? '删除终态记录后' : ''}${closing ? '关闭' : '设备停止'}仍等待批次来源核验收尾',
      () async {
        publication.block = true;
        final receipt = await owner.startTransfer('device', true, const [
          {'source': '/first', 'destination': '/sdcard/first'},
        ]);
        await publication.entered.future;
        final id = receipt['transferId']! as String;
        expect(owner.transfer(id)['status'], 'completed');
        if (remove) {
          await owner.removeTransfer(id);
          expect(owner.transfers()['transfers'], isEmpty);
        }
        var stopped = false;
        final stopping =
            (closing ? owner.close() : owner.cancelDevice('device')).then(
              (_) => stopped = true,
            );
        await Future<void>.delayed(Duration.zero);
        expect(stopped, isFalse);
        publication.release();
        await stopping;
        expect(stopped, isTrue);
      },
    );
  }
}

final class _Executor extends FixtureExecutor {
  bool block = false;
  final entered = Completer<void>();
  final _released = Completer<void>();
  FileCancellation? cancellation;

  void release() {
    if (!_released.isCompleted) _released.complete();
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
  }) async {
    this.cancellation = cancellation;
    if (!entered.isCompleted) entered.complete();
    if (block) await _released.future;
    cancellation.check();
    return super.copy(
      device,
      source,
      temporary,
      push: push,
      expected: expected,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }
}

final class _Publication implements FilePublicationLeases {
  @override
  Future<Set<String>> get sourcePaths async => {};

  bool block = false;
  final entered = Completer<void>();
  final _released = Completer<void>();

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<Map<String, Object?>?> begin(
    String shareId,
    Map<String, Object?> request, {
    String? transferId,
  }) async => null;

  @override
  Future<void> finish(
    String shareId,
    Map<String, Object?>? receipt, {
    bool definitelyUnpublished = false,
  }) async {}

  @override
  Future<Map<String, Object?>> reconcile(
    Map<String, Object?> durableReferences, {
    Set<String>? coveredSources,
  }) async {
    if (!entered.isCompleted) entered.complete();
    if (block) await _released.future;
    return {'reconciled': true};
  }
}
