import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'support/media_file_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/media/cache/app_media_cache.dart';
import 'package:scrcpy_connect/media/cache/media_artifact_coordinator.dart';

void main() {
  late Directory root;
  late AppMediaCache cache;
  late MediaFileFixture executor;
  late _Companion companion;
  late MediaArtifactCoordinator owner;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('media-artifact-owner-');
    cache = await AppMediaCache.open(root: root);
    executor = MediaFileFixture();
    companion = _Companion();
    owner = MediaArtifactCoordinator(
      cache: cache,
      executor: executor,
      request: companion.request,
    );
  });
  tearDown(() async {
    await owner.close();
    await root.delete(recursive: true);
  });

  test('预览真实落盘、同源命中、租约保护及释放后清理共用应用预算', () async {
    final first = await owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    final target = File(first['localPath'] as String);
    expect(await target.readAsBytes(), executor.bytes);
    expect(first['cacheHit'], false);
    expect((await cache.clear())['deletedBytes'], 0);
    final second = await owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    expect(second['cacheHit'], true);
    expect(second['localPath'], first['localPath']);
    expect(executor.copies, 1);
    await cache.release(first['cacheLeaseId'] as String);
    expect((await cache.clear())['deletedBytes'], 0);
    await cache.release(second['cacheLeaseId'] as String);
    expect((await cache.clear())['deletedBytes'], greaterThan(0));
    expect(await target.exists(), false);
  });

  test('正在接收的预览以写入预算保护，不通过保留整个媒体根目录绕过清理', () async {
    final entered = Completer<void>(), finish = Completer<void>();
    executor.duringCopy = () async {
      entered.complete();
      await finish.future;
    };
    final pending = owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    await entered.future;
    final status = await cache.status();
    expect(status['reservedBytes'], greaterThan(0));
    expect((await cache.clear())['deletedBytes'], 0);
    finish.complete();
    final result = await pending;
    expect(await File(result['localPath'] as String).exists(), true);
    await cache.release(result['cacheLeaseId'] as String);
  });

  test('预算拒绝预览发生在复制之前，源变化不发布产物且释放暂存与预算', () async {
    await cache.configure(budgetBytes: 16);
    await expectLater(
      owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/raw.png',
      }),
      throwsA(
        isA<MediaCacheFailure>().having(
          (e) => e.code,
          'code',
          'cache_budget_exceeded',
        ),
      ),
    );
    expect(executor.copies, 0);
    await cache.configure(budgetBytes: 8192);
    executor.duringCopy = () async {
      executor.changed = true;
    };
    await expectLater(
      owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/raw.png',
      }),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'source_changed',
        ),
      ),
    );
    expect((await cache.status())['reservedBytes'], 0);
    expect(
      await root
          .list(recursive: true)
          .where((e) => e.path.endsWith('.part'))
          .isEmpty,
      true,
    );
  });

  test('缩略图只传有界 JPEG，经三次源核验后发布并命中，原件不经 RPC 或文件执行器下载', () async {
    final first = await owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/image.png',
    });
    expect(companion.phases, ['stat', 'thumbnail', 'stat']);
    expect(executor.copies, 0);
    expect(first['originalBytesTransferred'], 0);
    expect(first['jpegBytesTransferred'], companion.jpeg.length);
    expect(
      await File(first['localPath'] as String).readAsBytes(),
      companion.jpeg,
    );
    final second = await owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/image.png',
    });
    expect(second['cacheHit'], true);
    expect(companion.phases, ['stat', 'thumbnail', 'stat', 'stat']);
    expect(second['jpegBytesTransferred'], 0);
    expect((await cache.clear())['deletedBytes'], 0);
    await cache.release(first['cacheLeaseId'] as String);
    await cache.release(second['cacheLeaseId'] as String);
    expect((await cache.clear())['deletedBytes'], greaterThan(0));
  });

  test('缩略图摘要错误和生成后的源变化均不留下已发布 JPEG 或租约', () async {
    companion.wrongDigest = true;
    await expectLater(
      owner.invoke('media.thumbnail', {
        'deviceId': 'device',
        'path': '/sdcard/image.png',
      }),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'invalid_thumbnail',
        ),
      ),
    );
    companion.wrongDigest = false;
    companion.changeAfterDecode = true;
    companion.decoded = false;
    await expectLater(
      owner.invoke('media.thumbnail', {
        'deviceId': 'device',
        'path': '/sdcard/image.png',
      }),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'source_changed',
        ),
      ),
    );
    expect((await cache.status())['reservedBytes'], 0);
    expect(
      await root
          .list(recursive: true)
          .where((e) => e.path.endsWith('.jpg'))
          .isEmpty,
      true,
    );
  });

  test('所有可用内容已被消费者持有时拒绝新预览，保留原件及无益可回收内容', () async {
    final first = await owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    final status = await cache.status();
    await cache.configure(
      budgetBytes: (status['usedBytes'] as int) + executor.bytes.length + 4095,
    );
    final loose = File(p.join(root.path, 'media', 'loose'));
    await loose.writeAsBytes([9]);
    await expectLater(
      owner.invoke('media.preview', {
        'deviceId': 'device',
        'path': '/sdcard/other.png',
      }),
      throwsA(
        isA<MediaCacheFailure>().having(
          (e) => e.code,
          'code',
          'cache_budget_exceeded',
        ),
      ),
    );
    expect(executor.copies, 1);
    expect(
      await File(first['localPath'] as String).readAsBytes(),
      executor.bytes,
    );
    expect(await loose.exists(), true);
    await cache.release(first['cacheLeaseId'] as String);
  });

  test('源版本变化发布新文件，旧播放器持有的文件身份与字节不被覆盖', () async {
    final first = await owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    final original = List<int>.of(executor.bytes);
    executor.changed = true;
    executor.bytes[0] = 99;
    final second = await owner.invoke('media.preview', {
      'deviceId': 'device',
      'path': '/sdcard/raw.png',
    });
    expect(second['localPath'], isNot(first['localPath']));
    expect(await File(first['localPath'] as String).readAsBytes(), original);
    expect(
      await File(second['localPath'] as String).readAsBytes(),
      executor.bytes,
    );
    expect((await cache.clear())['deletedBytes'], 0);
    await cache.release(first['cacheLeaseId'] as String);
    expect((await cache.clear())['deletedBytes'], greaterThan(0));
    expect(await File(second['localPath'] as String).exists(), true);
    await cache.release(second['cacheLeaseId'] as String);
  });

  test('真实私有 pull 的租约贯穿复制发布，acquire 仅信任任务路径且驱逐撤销导出能力', () async {
    final files = await TransferCoordinator.open(
      executor: executor,
      dataDirectory: root,
      cache: cache,
    );
    final copied = Completer<void>(),
        publish = Completer<void>(),
        committed = Completer<void>(),
        finish = Completer<void>();
    executor.duringCopy = () async {
      copied.complete();
      await publish.future;
    };
    executor.duringCommit = () async {
      committed.complete();
      await finish.future;
    };
    final destination = p.join(root.path, 'media', 'pull', 'original');
    await Directory(p.dirname(destination)).create(recursive: true);
    try {
      final receipt = await files.startTransfer('device', false, [
        {'source': '/sdcard/raw.png', 'destination': destination},
      ], destinationScope: 'privateCache');
      final id = receipt['transferId'] as String;
      await copied.future;
      expect((await cache.clear())['deletedBytes'], 0);
      publish.complete();
      await committed.future;
      expect(await File(destination).readAsBytes(), executor.bytes);
      expect((await cache.clear())['deletedBytes'], 0);
      finish.complete();
      for (
        var attempt = 0;
        files.transfer(id)['status'] != 'completed' && attempt < 1000;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(files.transfer(id)['canExport'], true);
      final held = await files.acquireCacheLease(id);
      expect((await cache.clear())['deletedBytes'], 0);
      await expectLater(
        files.acquireCacheLease('not-a-transfer'),
        throwsA(
          isA<FileFailure>().having((e) => e.code, 'code', 'invalid_argument'),
        ),
      );
      // completed 先于日志持久化及批次写租约释放；关闭等待真实 worker 排空。
      await files.close();
      await cache.release(held);
      expect((await cache.clear())['deletedBytes'], executor.bytes.length);
      expect(files.transfer(id)['canExport'], false);
      expect(files.transfer(id)['cacheEvicted'], true);
    } finally {
      if (!publish.isCompleted) publish.complete();
      if (!finish.isCompleted) finish.complete();
      await files.close();
    }
  });

  test('缓存 JPEG 损坏重新生成，不能永久卡在旧缓存错误', () async {
    final first = await owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/image.png',
    });
    await File(first['localPath'] as String).writeAsString('broken');
    await cache.release(first['cacheLeaseId'] as String);
    final second = await owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/image.png',
    });
    expect(second['cacheHit'], false);
    expect(companion.phases.where((p) => p == 'thumbnail').length, 2);
    await cache.release(second['cacheLeaseId'] as String);
  });

  test('启动前取消持久到本次附着的操作墓碑，不向伴生发出请求', () async {
    const operation = '4081c402-3418-4b3e-a719-be1323533468';
    await owner.invoke('media.thumbnail.cancel', {
      'deviceId': 'device',
      'operationId': operation,
    });
    await expectLater(
      owner.invoke('media.thumbnail', {
        'deviceId': 'device',
        'path': '/sdcard/image.png',
        'operationId': operation,
      }),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(companion.phases, isEmpty);
  });

  test('取消正在运行的缩略图等待原生阶段清理，排队者不会越过尚未结束的解码', () async {
    const firstId = '4081c402-3418-4b3e-a719-be1323533468';
    final entered = Completer<void>(), finish = Completer<void>();
    companion.duringDecode = () async {
      entered.complete();
      await finish.future;
    };
    final first = owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/image.png',
      'operationId': firstId,
    });
    final rejected = expectLater(
      first,
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await entered.future;
    final second = owner.invoke('media.thumbnail', {
      'deviceId': 'device',
      'path': '/sdcard/another.png',
    });
    await owner.invoke('media.thumbnail.cancel', {
      'deviceId': 'device',
      'operationId': firstId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(companion.cancelled, hasLength(1));
    expect(companion.phases, ['stat', 'thumbnail']);
    expect((await cache.status())['reservedBytes'], greaterThan(0));
    companion.duringDecode = null;
    finish.complete();
    await rejected;
    final result = await second;
    expect(companion.phases, [
      'stat',
      'thumbnail',
      'stat',
      'thumbnail',
      'stat',
    ]);
    await cache.release(result['cacheLeaseId'] as String);
    expect((await cache.status())['reservedBytes'], 0);
  });
}

final class _Companion {
  final jpeg = <int>[255, 216, 255, 192, 0, 8, 8, 0, 32, 0, 48, 1, 255, 217];
  final phases = <String>[], cancelled = <String>[];
  bool wrongDigest = false, changeAfterDecode = false, decoded = false;
  Future<void> Function()? duringDecode;
  Map<String, dynamic> get source => {
    'device': '1',
    'inode': '2',
    'mode': 0x8000,
    'size': 50000,
    'modifiedSeconds': 1,
    'changedSeconds': changeAfterDecode && decoded ? 2 : 1,
    'modifiedNanos': null,
    'changedNanos': null,
  };
  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async {
    if (command == 'media.thumbnail.cancel') {
      cancelled.add(params['operationId'] as String);
      return {'cancelRequested': true};
    }
    final phase = params['execution'] as String;
    phases.add(phase);
    if (phase == 'stat') {
      return {'sourceStamp': source, 'rpcBytesReceived': 100};
    }
    final stamp = source;
    await duringDecode?.call();
    decoded = true;
    return {
      'sourceStamp': stamp,
      'rpcBytesReceived': 200,
      'thumbnail': true,
      'mime': 'image/jpeg',
      'data': base64Encode(jpeg),
      'jpegBytes': jpeg.length,
      'sha256': wrongDigest ? 'bad' : sha256.convert(jpeg).toString(),
      'width': 48,
      'height': 32,
    };
  }
}
