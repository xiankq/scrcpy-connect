import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/models/file_directory_facts.dart';
import 'package:scrcpy_connect/services/file_executor.dart';
import 'package:scrcpy_connect/models/file_cache_reservation.dart';
import 'package:scrcpy_connect/services/file_cache_leases.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';
import 'package:scrcpy_connect/stores/file_transfer_store.dart';

void main() {
  test('取消失败保留精确执行与缓存，所有取消入口和关闭沿原句柄重试', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.resource.failures = 100;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      final batch = receipt['batchId']! as String;
      await fixture.executor.copyStarted.future;

      await expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      final task = fixture.owner.transfer(id);
      expect(task['cleanupPending'], isTrue);
      expect(task['errorCode'], 'result_unknown');
      expect(task['canRestart'], isFalse);
      expect(task['canCancel'], isTrue);
      expect(fixture.cache.leases, hasLength(1));
      final saved = (await FileTransferStore(fixture.root).load())[id]!;
      expect(saved['cleanupPending'], isTrue);
      expect(saved['errorCode'], 'result_unknown');
      await expectLater(
        fixture.owner.resolveTransfer(id, 'ask', restart: true),
        _throwsCode('restart_unavailable'),
      );
      await expectLater(
        fixture.owner.removeTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await expectLater(
        fixture.owner.cancelBatch(batch),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await expectLater(
        fixture.owner.cancelDevice('device'),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await expectLater(
        fixture.owner.close(),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      expect(fixture.executor.releaseCalls, 0);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.executor.commitCalls, 0);

      fixture.executor.resource.failures = 0;
      final gate = fixture.executor.resource.gate = Completer<void>();
      final entered = fixture.executor.resource.entered = Completer<void>();
      var closed = false;
      final closing = fixture.owner.close().then((_) => closed = true);
      await entered.future;
      expect(closed, isFalse);
      expect(fixture.cache.leases, hasLength(1));
      expect(fixture.executor.releaseCalls, 0);
      gate.complete();
      await closing;
      expect(fixture.executor.resource.closed, isTrue);
      expect(fixture.owner.transfer(id)['cleanupPending'], isFalse);
      expect(fixture.owner.transfer(id)['status'], 'cancelled');
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.executor.releaseCalls, 1);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.executor.commitCalls, 0);
    } finally {
      await fixture.dispose();
    }
  });

  test('releasePart失败保留原执行错误，成功清理不重放复制且批回执如实返回失败', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.copyFailure = const FileFailure(
        'source_changed',
        '原执行失败',
      );
      fixture.executor.releaseFailures = 100;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      final batch = receipt['batchId']! as String;
      await _until(() => fixture.owner.transfer(id)['cleanupPending'] == true);
      await expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      final task = fixture.owner.transfer(id);
      expect(task['error'], contains('原执行失败'));
      expect(task['error'], contains('片段释放失败'));
      expect(fixture.cache.leases, hasLength(1));
      await expectLater(
        fixture.owner.removeTransfer(id, batch: false),
        _throwsCode('file_cleanup_unconfirmed'),
      );

      fixture.executor.releaseFailures = 0;
      final result = await fixture.owner.cancelBatch(batch);
      expect(result['status'], 'partialFailure');
      expect(fixture.owner.transfer(id)['cleanupPending'], isFalse);
      expect(fixture.owner.transfer(id)['errorCode'], 'source_changed');
      expect(fixture.owner.transfer(id)['canRestart'], isFalse);
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.executor.commitCalls, 0);
    } finally {
      await fixture.dispose();
    }
  });

  test('提交回执未知即使精确资源已关闭也不变成取消成功或释放保护', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.commitUnknown = true;
      fixture.executor.resource.failures = 100;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      final batch = receipt['batchId']! as String;
      await _until(() => fixture.owner.transfer(id)['cleanupPending'] == true);
      await expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await expectLater(
        fixture.owner.removeTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      fixture.executor.resource.failures = 0;
      final result = await fixture.owner.cancelBatch(batch);
      expect(result['status'], 'partialFailure');
      final task = fixture.owner.transfer(id);
      expect(task['cleanupPending'], isFalse);
      expect(task['status'], 'failed');
      expect(task['errorCode'], 'result_unknown');
      expect(task['canRestart'], isFalse);
      expect(fixture.cache.leases, hasLength(1));
      expect(fixture.executor.commitCalls, 1);
      expect(fixture.executor.copyCalls, 1);
      await fixture.owner.close();
      expect(fixture.cache.leases, hasLength(1));
    } finally {
      await fixture.dispose();
    }
  });

  test('已确认提交只在片段清理确认后发布完成，清理重试不重放commit', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.releaseFailures = 100;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      await _until(() => fixture.owner.transfer(id)['cleanupPending'] == true);
      await expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      expect(fixture.owner.transfer(id)['canExport'], isFalse);
      expect(fixture.cache.leases, hasLength(1));
      fixture.executor.releaseFailures = 0;
      final result = await fixture.owner.cancelTransfer(id);
      expect(result['status'], 'completed');
      expect(result['cleanupPending'], isFalse);
      expect(result['errorCode'], isNull);
      expect(result['temporaryPath'], isNull);
      expect(fixture.executor.commitCalls, 1);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.cache.leases, isEmpty);
    } finally {
      await fixture.dispose();
    }
  });

  test('releasePart已确认但原worker关闭失败，只重试精确worker而不重复释放part', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.releaseCleanupFailure = true;
      fixture.executor.resource.failures = 100;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      await _until(() => fixture.owner.transfer(id)['cleanupPending'] == true);
      await expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      expect(fixture.executor.releaseDispatches, 1);
      expect(fixture.cache.leases, hasLength(1));
      fixture.executor.resource.failures = 0;
      final result = await fixture.owner.cancelTransfer(id);
      expect(result['status'], 'completed');
      expect(result['temporaryPath'], isNull);
      expect(fixture.executor.resource.closed, isTrue);
      expect(fixture.executor.releaseDispatches, 1);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.executor.commitCalls, 1);
      expect(fixture.cache.leases, isEmpty);
    } finally {
      await fixture.dispose();
    }
  });

  test('重启等待预算时同批删除与重复重启均拒绝，完成后仅启动一次', () async {
    final fixture = await _Fixture.open();
    try {
      final id = await fixture.restartable();
      fixture.executor.copyFailure = null;
      fixture.executor.waitForCancellation = true;
      fixture.cache.reserveEntered = Completer<void>();
      fixture.cache.reserveGate = Completer<void>();
      final restart = fixture.owner.resolveTransfer(id, 'ask', restart: true);
      await fixture.cache.reserveEntered!.future;
      await expectLater(
        fixture.owner.removeTransfer(id),
        _throwsCode('transfer_active'),
      );
      await expectLater(
        fixture.owner.resolveTransfer(id, 'ask', restart: true),
        _throwsCode('restart_unavailable'),
      );
      expect(fixture.cache.sequence, 1);
      fixture.cache.reserveGate!.complete();
      await restart;
      await _until(() => fixture.executor.copyCalls == 2);
      await fixture.owner.cancelTransfer(id);
      expect(fixture.owner.transfer(id)['generation'], 1);
      expect(fixture.executor.copyCalls, 2);
      expect(fixture.cache.leases, isEmpty);
      expect(
        (await FileTransferStore(fixture.root).load())[id]!['generation'],
        1,
      );
    } finally {
      await fixture.dispose();
    }
  });

  test('旧worker正在释放预算时重启和移除均拒绝，确认后新预算不受旧回执影响', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.copyFailure = const FileFailure('io_error', '本次复制失败');
      fixture.cache.releaseEntered = Completer<void>();
      fixture.cache.releaseGate = Completer<void>();
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      await fixture.cache.releaseEntered!.future;
      expect(fixture.owner.transfer(id)['canRestart'], isFalse);
      await expectLater(
        fixture.owner.resolveTransfer(id, 'ask', restart: true),
        _throwsCode('restart_unavailable'),
      );
      await expectLater(
        fixture.owner.removeTransfer(id),
        _throwsCode('transfer_active'),
      );
      expect(fixture.cache.leases, {'lease-1'});
      fixture.cache.releaseGate!.complete();
      await _until(() => fixture.owner.transfer(id)['canRestart'] == true);
      fixture.executor.copyFailure = null;
      fixture.executor.waitForCancellation = true;
      await fixture.owner.resolveTransfer(id, 'ask', restart: true);
      await _until(() => fixture.executor.copyCalls == 2);
      expect(fixture.cache.leases, {'lease-2'});
      await fixture.owner.cancelTransfer(id);
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.cache.successfulReleases, ['lease-1', 'lease-2']);
    } finally {
      await fixture.dispose();
    }
  });

  test('删除先取得批次准入，在日志提交前的重启不能持旧Map复活任务', () async {
    final fixture = await _Fixture.open();
    try {
      final id = await fixture.restartable();
      // remove 在首次 await 日志前同步取得准入；同一 turn 的 restart 必须拒绝。
      final removing = fixture.owner.removeTransfer(id);
      final rejected = expectLater(
        fixture.owner.resolveTransfer(id, 'ask', restart: true),
        _throwsCode('restart_unavailable'),
      );
      await removing;
      await rejected;
      expect((fixture.owner.transfers()['transfers']! as List), isEmpty);
      expect(await FileTransferStore(fixture.root).load(), isEmpty);
      expect(fixture.cache.sequence, 1);
      expect(fixture.cache.leases, isEmpty);
    } finally {
      await fixture.dispose();
    }
  });

  test('迟到预算释放首败保留同编辑责任，cancel与close共同等待且重试不重复释放', () async {
    final fixture = await _Fixture.open();
    try {
      final id = await fixture.restartable();
      fixture.cache.reserveEntered = Completer<void>();
      fixture.cache.reserveGate = Completer<void>();
      fixture.cache.releaseFailures = 100;
      final rejected = expectLater(
        fixture.owner.resolveTransfer(id, 'ask', restart: true),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await fixture.cache.reserveEntered!.future;
      final cancelled = expectLater(
        fixture.owner.cancelTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      final closed = expectLater(
        fixture.owner.close(),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      fixture.cache.reserveGate!.complete();
      await Future.wait([rejected, cancelled, closed]);
      expect(fixture.cache.leases, hasLength(1));
      fixture.cache.releaseFailures = 0;
      await fixture.owner.close();
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.cache.successfulReleases.toSet(), {'lease-1', 'lease-2'});
      expect(fixture.cache.successfulReleases, hasLength(2));
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.owner.transfer(id)['generation'], 0);
    } finally {
      await fixture.dispose();
    }
  });

  for (final closing in [false, true]) {
    test('首次创建${closing ? '关闭' : '设备取消'}等待迟到预算归还，不发布任务', () async {
      final fixture = await _Fixture.open();
      try {
        fixture.cache.reserveEntered = Completer<void>();
        fixture.cache.reserveGate = Completer<void>();
        final rejected = expectLater(fixture.start(), _throwsCode('cancelled'));
        await fixture.cache.reserveEntered!.future;
        var stopped = false;
        final stopping =
            (closing
                    ? fixture.owner.close()
                    : fixture.owner.cancelDevice('device'))
                .then((_) => stopped = true);
        expect(stopped, isFalse);
        fixture.cache.reserveGate!.complete();
        await Future.wait([rejected, stopping]);
        expect(fixture.cache.leases, isEmpty);
        expect(fixture.executor.copyCalls, 0);
        expect(fixture.owner.transfers()['transfers'], isEmpty);
        expect(await FileTransferStore(fixture.root).load(), isEmpty);
        expect(fixture.cache.successfulReleases, ['lease-1']);
      } finally {
        await fixture.dispose();
      }
    });
  }

  for (final closing in [false, true]) {
    test('首条日志回执期间${closing ? '关闭' : '设备取消'}也收束后续登记任务', () async {
      final fixture = await _Fixture.open();
      StreamSubscription<Map<String, Object?>>? subscription;
      try {
        final stopping = Completer<void>();
        var issued = false;
        subscription = fixture.owner.events.listen((event) {
          if (issued || event['type'] != 'transfers.changed') return;
          issued = true;
          final stopped = closing
              ? fixture.owner.close()
              : fixture.owner.cancelDevice('device');
          stopping.complete(stopped);
        });
        await expectLater(
          fixture.owner.startTransfer('device', false, [
            {
              'source': '/sdcard/source',
              'destination': '${fixture.root.path}/first',
            },
            {
              'source': '/sdcard/source',
              'destination': '${fixture.root.path}/second',
            },
          ], destinationScope: 'privateCache'),
          _throwsCode('cancelled'),
        );
        await stopping.future;
        final records = await FileTransferStore(fixture.root).load();
        expect(records, hasLength(2));
        expect(
          records.values.map((task) => task['status']),
          everyElement('cancelled'),
        );
        expect(fixture.cache.leases, isEmpty);
        expect(fixture.executor.copyCalls, 0);
      } finally {
        await subscription?.cancel();
        await fixture.dispose();
      }
    });
  }

  test('首次创建的迟到预算释放失败保留精确责任，关闭重试不重新reserve', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.cache.reserveEntered = Completer<void>();
      fixture.cache.reserveGate = Completer<void>();
      fixture.cache.releaseFailures = 100;
      final rejected = expectLater(
        fixture.start(),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      await fixture.cache.reserveEntered!.future;
      final closed = expectLater(
        fixture.owner.close(),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      fixture.cache.reserveGate!.complete();
      await Future.wait([rejected, closed]);
      expect(fixture.cache.leases, {'lease-1'});
      expect(fixture.executor.copyCalls, 0);
      expect(fixture.owner.transfers()['transfers'], isEmpty);
      fixture.cache.releaseFailures = 0;
      await fixture.owner.close();
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.cache.sequence, 1);
      expect(fixture.cache.successfulReleases, ['lease-1']);
    } finally {
      await fixture.dispose();
    }
  });

  test('移除已落盘后预算释放失败，关闭仍沿原批次责任重试', () async {
    final fixture = await _Fixture.open();
    try {
      fixture.executor.waitForCancellation = false;
      fixture.executor.commitUnknown = true;
      final receipt = await fixture.start();
      final id = receipt['transferId']! as String;
      await _until(
        () => fixture.owner.transfer(id)['errorCode'] == 'result_unknown',
      );
      await fixture.owner.cancelTransfer(id);
      fixture.cache.releaseFailures = 100;
      await expectLater(
        fixture.owner.removeTransfer(id),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      expect(fixture.owner.transfers()['transfers'], isEmpty);
      expect(await FileTransferStore(fixture.root).load(), isEmpty);
      expect(fixture.cache.leases, {'lease-1'});
      await expectLater(
        fixture.owner.close(),
        _throwsCode('file_cleanup_unconfirmed'),
      );
      fixture.cache.releaseFailures = 0;
      await fixture.owner.close();
      expect(fixture.cache.leases, isEmpty);
      expect(fixture.executor.copyCalls, 1);
      expect(fixture.executor.commitCalls, 1);
      expect(fixture.cache.successfulReleases, ['lease-1']);
    } finally {
      await fixture.dispose();
    }
  });

  for (final variant in ['same', 'different-key', 'missing', 'successor']) {
    test('冷重开清理保护仅接受同技术域已排空换代事实：$variant', () async {
      final fixture = await _Fixture.open();
      final coldRoot = await Directory.systemTemp.createTemp('transfer-cold-');
      FileTransferService? reopened;
      try {
        fixture.executor.resource.failures = 100;
        final receipt = await fixture.start();
        final id = receipt['transferId']! as String;
        await fixture.executor.copyStarted.future;
        await expectLater(
          fixture.owner.cancelTransfer(id),
          _throwsCode('file_cleanup_unconfirmed'),
        );
        // 复制实际落盘日志到另一目录，避免借用旧 isolate 的缓存交接登记。
        await File('${fixture.root.path}/file_tasks.v2.journal')
            .copy('${coldRoot.path}/file_tasks.v2.journal');
        final executor = _Executor()
          ..fileScopeKey = variant == 'different-key'
              ? 'foreign'
              : variant == 'missing'
              ? ''
              : 'transfer-files'
          ..fileScopeId = variant == 'same' ? 'scope-old' : 'scope-new';
        final cache = _Cache();
        reopened = await FileTransferService.open(
          executor: executor,
          dataDirectory: coldRoot,
          cache: cache,
        );
        final result = reopened.transfer(id);
        expect(result['errorCode'], 'result_unknown');
        expect(result['canRestart'], isFalse);
        expect(cache.leases, hasLength(1));
        if (variant == 'successor') {
          expect(result['cleanupPending'], isFalse);
          final cancelled = await reopened.cancelTransfer(id);
          expect(cancelled['status'], 'failed');
          expect(cancelled['errorCode'], 'result_unknown');
        } else {
          expect(result['cleanupPending'], isTrue);
          await expectLater(
            reopened.cancelTransfer(id),
            _throwsCode('result_unknown'),
          );
          await expectLater(
            reopened.removeTransfer(id),
            _throwsCode('file_cleanup_unconfirmed'),
          );
        }
        expect(executor.resource.calls, 0);
        expect(executor.releaseCalls, 0);
        expect(executor.copyCalls, 0);
        await reopened.close();
        expect(cache.leases, hasLength(1));
      } finally {
        await reopened?.close();
        await coldRoot.delete(recursive: true);
        await fixture.dispose();
      }
    });
  }
}

Matcher _throwsCode(String code) =>
    throwsA(isA<FileFailure>().having((error) => error.code, 'code', code));

Future<void> _until(bool Function() condition) async {
  await (() async {
    while (!condition()) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  })().timeout(const Duration(seconds: 5));
}

final class _Fixture {
  _Fixture(this.root, this.executor, this.cache, this.owner);
  final Directory root;
  final _Executor executor;
  final _Cache cache;
  final FileTransferService owner;

  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('transfer-cleanup-');
    final executor = _Executor();
    final cache = _Cache();
    final owner = await FileTransferService.open(
      executor: executor,
      dataDirectory: root,
      cache: cache,
    );
    return _Fixture(root, executor, cache, owner);
  }

  Future<Map<String, Object?>> start() => owner.startTransfer('device', false, [
    {'source': '/sdcard/source', 'destination': '${root.path}/saved'},
  ], destinationScope: 'privateCache');

  Future<String> restartable() async {
    executor.waitForCancellation = false;
    executor.copyFailure = const FileFailure('io_error', '复制失败且没有未知提交');
    final receipt = await start();
    final id = receipt['transferId']! as String;
    await _until(
      () => owner.transfer(id)['status'] == 'failed' && cache.leases.isEmpty,
    );
    return id;
  }

  Future<void> dispose() async {
    cache.releaseFailures = 0;
    final reservation = cache.reserveGate;
    if (reservation != null && !reservation.isCompleted) reservation.complete();
    final releasing = cache.releaseGate;
    if (releasing != null && !releasing.isCompleted) releasing.complete();
    executor.resource.failures = 0;
    executor.releaseFailures = 0;
    final gate = executor.resource.gate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await owner.close();
    await root.delete(recursive: true);
  }
}

final class _Resource implements FileExecutionResource {
  int failures = 0, calls = 0;
  bool closed = false;
  Completer<void>? gate, entered;
  @override
  Future<void> close() async {
    calls++;
    final started = entered;
    if (started != null && !started.isCompleted) started.complete();
    if (failures > 0) {
      failures--;
      throw const FileFailure('close_failed', '原reader仍未退出');
    }
    await gate?.future;
    closed = true;
  }
}

final class _Cache implements FileCacheLeases {
  final leases = <String>{};
  int sequence = 0, releaseFailures = 0;
  Completer<void>? reserveEntered, reserveGate, releaseEntered, releaseGate;
  final successfulReleases = <String>[];
  @override
  Future<String> reserve(List<FileCacheReservation> reservations) async {
    final entered = reserveEntered;
    if (entered != null && !entered.isCompleted) entered.complete();
    await reserveGate?.future;
    final lease = 'lease-${++sequence}';
    leases.add(lease);
    return lease;
  }

  @override
  Future<void> release(String lease) async {
    final entered = releaseEntered;
    if (entered != null && !entered.isCompleted) entered.complete();
    await releaseGate?.future;
    if (releaseFailures > 0) {
      releaseFailures--;
      throw const FileFailure('release_failed', '缓存租约释放未确认');
    }
    if (!leases.remove(lease)) throw StateError('重复释放缓存租约');
    successfulReleases.add(lease);
  }
}

final class _Executor implements FileExecutor, ScopedFileExecutor {
  @override
  String fileScopeKey = 'transfer-files';
  @override
  String fileScopeId = 'scope-old';
  final resource = _Resource();
  final copyStarted = Completer<void>();
  int copyCalls = 0, commitCalls = 0, releaseCalls = 0, releaseFailures = 0;
  bool waitForCancellation = true, commitUnknown = false;
  bool releaseCleanupFailure = false, _partReleased = false;
  int releaseDispatches = 0;
  FileFailure? copyFailure;
  static const stamp = FileStamp(mode: 0x8000, size: 4, modifiedSeconds: 1);

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    cancellation.check();
    if (path == '/sdcard/source') return stamp;
    throw const FileFailure('not_found', '目标不存在');
  }

  @override
  Future<FileDirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) => throw StateError('本夹具只传输单个文件');

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
    copyCalls++;
    if (!copyStarted.isCompleted) copyStarted.complete();
    if (waitForCancellation) {
      await cancellation.whenCancelled;
      throw FileExecutionCleanupFailure(
        resource,
        const FileFailure('cancelled', '原执行已取消但reader仍存活'),
      );
    }
    if (copyFailure case final error?) throw error;
    return 4;
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
    if (action == 'commit') {
      commitCalls++;
      if (commitUnknown) {
        throw FileExecutionCleanupFailure(
          resource,
          const FileFailure('disconnected', '提交回执丢失'),
        );
      }
      return 'atomicNoReplace';
    }
    if (action == 'releasePart') {
      releaseCalls++;
      if (_partReleased) return 'released';
      releaseDispatches++;
      if (releaseCleanupFailure) {
        _partReleased = true;
        throw FileExecutionCleanupFailure(
          resource,
          const FileFailure('close_failed', '片段释放已有回执但worker尚未退出'),
        );
      }
      if (releaseFailures > 0) {
        releaseFailures--;
        throw const FileFailure('release_failed', '片段释放失败');
      }
      _partReleased = true;
      return 'released';
    }
    throw StateError('未知操作 $action');
  }
}
