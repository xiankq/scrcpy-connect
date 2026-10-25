import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';
import 'package:scrcpy_connect/stores/files/transfer_journal.dart';
import 'package:scrcpy_connect/stores/media/app_media_cache.dart';

void main() {
  test('新缓存 reserve 失败时保留旧所有者；重试先覆盖全部未知任务再释放各代旧租约', () async {
    final root = await Directory.systemTemp.createTemp('cache-owner-handoff-');
    final journal = TransferJournal(root);
    for (final id in ['first', 'second']) {
      final file = File(p.join(root.path, 'media', id, 'original'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      await journal.upsert({
        'id': id,
        'deviceId': 'd',
        'batchId': id,
        'direction': 'pull',
        'source': '/sdcard/$id',
        'destination': file.path,
        'destinationScope': 'privateCache',
        'name': id,
        'kind': 'file',
        'status': 'finalizing',
        'generation': 0,
        'transferred': 3,
        'total': 3,
        'policy': 'ask',
      });
    }
    final old = _Cache(await AppMediaCache.open(root: root));
    final failing = _Cache(await AppMediaCache.open(root: root))..failOn = 2;
    final fresh = _Cache(await AppMediaCache.open(root: root));
    TransferCoordinator? owner;
    try {
      owner = await TransferCoordinator.open(
        executor: _NoExecution(),
        dataDirectory: root,
        cache: old,
      );
      await owner.close();
      expect((await old.owner.clear())['deletedBytes'], 0);
      await expectLater(
        TransferCoordinator.open(
          executor: _NoExecution(),
          dataDirectory: root,
          cache: failing,
        ),
        throwsA(
          isA<FileFailure>().having((e) => e.code, 'code', 'reserve_failed'),
        ),
      );
      expect(old.releases, 0);
      expect((await old.owner.clear())['deletedBytes'], 0);
      expect(failing.active, hasLength(1));
      fresh.beforeRelease = () {
        expect(fresh.active, hasLength(2));
      };
      old.beforeRelease = () {
        expect(fresh.active, hasLength(2));
      };
      failing.beforeRelease = () {
        expect(fresh.active, hasLength(2));
      };
      owner = await TransferCoordinator.open(
        executor: _NoExecution(),
        dataDirectory: root,
        cache: fresh,
      );
      expect(old.active, isEmpty);
      expect(failing.active, isEmpty);
      expect((await fresh.owner.clear())['deletedBytes'], 0);
      await owner.removeTransfer('first');
      fresh.beforeRelease = null;
      await owner.removeTransfer('second');
      expect(fresh.active, isEmpty);
      expect((await fresh.owner.clear())['deletedBytes'], 6);
    } finally {
      await owner?.close();
      await root.delete(recursive: true);
    }
  });
}

final class _Cache implements FileCacheLeases {
  _Cache(this.owner);
  final AppMediaCache owner;
  int calls = 0, releases = 0;
  int? failOn;
  final active = <String>{};
  void Function()? beforeRelease;
  @override
  Future<String> reserve(List<FileCacheReservation> items) async {
    if (++calls == failOn) throw const FileFailure('reserve_failed', '测试准入失败');
    final lease = await owner.reserve(items);
    active.add(lease);
    return lease;
  }

  @override
  Future<void> release(String lease) async {
    beforeRelease?.call();
    await owner.release(lease);
    active.remove(lease);
    releases++;
  }
}

final class _NoExecution implements FileExecutor {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('重建租约不能重放传输');
}
