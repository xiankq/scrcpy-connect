import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/stores/media/app_media_cache.dart';

Matcher failure(String code) =>
    isA<MediaCacheFailure>().having((error) => error.code, 'code', code);

void main() {
  late Directory sandbox, root;
  late String media;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('app-media-cache-test-');
    root = await Directory(p.join(sandbox.path, 'application')).create();
    media = p.join(root.path, 'media');
    await Directory(media).create();
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });
  Future<File> file(String path, int bytes, {DateTime? modified}) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(List.filled(bytes, 1), flush: true);
    if (modified != null) await target.setLastModified(modified);
    return target;
  }

  test('旧配置形状与自定义预算兼容，未知分享保留跨重开继续保护', () async {
    final kept = await file(p.join(media, 'shared'), 8);
    final configuration = File(p.join(root.path, 'media-cache.json'));
    await configuration.writeAsString(
      jsonEncode({
        'budgetBytes': 12,
        'outgoingDirectory': null,
        'retainedShares': [kept.path],
      }),
      flush: true,
    );
    final cache = await AppMediaCache.open(root: root);
    expect((await cache.status())['budgetBytes'], 12);
    expect((await cache.clear())['deletedBytes'], 0);
    expect(await kept.exists(), isTrue);
    final status = await cache.status();
    expect(status['retainedShareCount'], 1);
    expect(status['retentionReason'], isNotNull);
    expect(status['protectedBytes'], 8);
  });

  test('写入按实际增长扣除预算，既有基线不能冒充本次完成量', () async {
    final target = await file(p.join(media, 'receive', 'original'), 4);
    final cache = await AppMediaCache.open(root: root);
    await cache.configure(budgetBytes: 20);
    final lease = await cache.reserve([FileCacheReservation(target.path, 6)]);
    expect((await cache.status())['reservedBytes'], 6);
    await target.writeAsBytes(List.filled(7, 1), flush: true);
    expect((await cache.status())['reservedBytes'], 3);
    expect((await cache.clear())['deletedBytes'], 0);
    await cache.release(lease);
    expect((await cache.status())['reservedBytes'], 0);
    expect((await cache.clear())['deletedBytes'], 7);
  });

  test('同一预留内部重叠写入预算被拒绝，父子保护不误伤兄弟前缀', () async {
    final first = await file(p.join(media, 'a', 'one'), 2);
    final sibling = await file(p.join(media, 'a-copy', 'one'), 3);
    final cache = await AppMediaCache.open(root: root);
    final lease = await cache.reserve([
      FileCacheReservation(p.dirname(first.path), 0),
    ]);
    await expectLater(
      cache.reserve([FileCacheReservation(first.path, 2)]),
      throwsA(failure('cache_in_use')),
    );
    await expectLater(
      cache.reserve([FileCacheReservation(media, 2)]),
      throwsA(failure('cache_in_use')),
    );
    final writer = await cache.writer(sibling.path, 4);
    await writer.close();
    await writer.close();
    await cache.release(lease);
    await expectLater(
      cache.reserve([
        FileCacheReservation(p.dirname(first.path), 1),
        FileCacheReservation(first.path, 1),
      ]),
      throwsA(failure('invalid_argument')),
    );
  });

  test('只读租约可以重叠且超预算时不因读取启动驱逐', () async {
    final target = await file(p.join(media, 'large'), 8);
    final other = await file(p.join(media, 'other'), 5);
    final cache = await AppMediaCache.open(root: root);
    await cache.configure(budgetBytes: 4);
    final first = await cache.reserve([FileCacheReservation(target.path, 0)]);
    final second = await cache.reserve([FileCacheReservation(target.path, 0)]);
    expect(await other.exists(), isTrue);
    expect((await cache.clear())['deletedBytes'], 5);
    await cache.release(first);
    expect((await cache.clear())['deletedBytes'], 0);
    await cache.release(second);
    expect((await cache.clear())['deletedBytes'], 8);
  });

  test('准入按修改时间再路径稳定驱逐，保留最新与本次选中目标', () async {
    final old = DateTime.utc(2020), newer = DateTime.utc(2021);
    final first = await file(p.join(media, 'a'), 4, modified: old);
    final second = await file(p.join(media, 'b'), 4, modified: old);
    final latest = await file(p.join(media, 'latest'), 4, modified: newer);
    final cache = await AppMediaCache.open(root: root);
    await cache.configure(budgetBytes: 14);
    final lease = await cache.reserve([
      FileCacheReservation(p.join(media, 'new'), 6),
    ]);
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
    expect(await latest.exists(), isTrue);
    await cache.release(lease);
    // 选择旧目标写入时，它必须在准入驱逐前就受到保护。
    final replacement = await cache.reserve([
      FileCacheReservation(second.path, 7),
    ]);
    expect(await second.exists(), isTrue);
    expect(await latest.exists(), isFalse);
    await cache.release(replacement);
  });

  test('无法容纳受保护内容和新预算时拒绝，不先删除无益的可回收文件', () async {
    final kept = await file(p.join(media, 'protected'), 8);
    final free = await file(p.join(media, 'free'), 4);
    final cache = await AppMediaCache.open(root: root);
    await cache.configure(budgetBytes: 12);
    final lease = await cache.reserve([FileCacheReservation(kept.path, 0)]);
    await expectLater(
      cache.reserve([FileCacheReservation(p.join(media, 'new'), 5)]),
      throwsA(failure('cache_budget_exceeded')),
    );
    expect(await kept.exists(), isTrue);
    expect(await free.exists(), isTrue);
    expect((await cache.status())['reservedBytes'], 0);
    await cache.release(lease);
  });

  test('reserve 与 clear 共用准入顺序，清理不能越过正在登记的路径保护', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var block = true;
    final target = await file(p.join(media, 'pending'), 4);
    final cache = await AppMediaCache.open(
      root: root,
      protectedPaths: () async {
        if (block) {
          entered.complete();
          await release.future;
          block = false;
        }
        return <String>[];
      },
    );
    final reserving = cache.reserve([FileCacheReservation(target.path, 3)]);
    await entered.future;
    var cleared = false;
    final clearing = cache.clear().then((result) {
      cleared = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    expect(await target.exists(), isTrue);
    release.complete();
    final lease = await reserving;
    expect((await clearing)['deletedBytes'], 0);
    expect(await target.exists(), isTrue);
    await cache.release(lease);
    expect((await cache.clear())['deletedBytes'], 4);
  });

  test('共享 gate 将 delivery 核验和持久 pending 发布排在清理前，结束后可回收', () async {
    final gate = MediaCacheGate();
    final protected = <String>{};
    final entered = Completer<void>(), committed = Completer<void>();
    final source = await file(p.join(media, 'original'), 5);
    final cache = await AppMediaCache.open(
      root: root,
      gate: gate,
      protectedPaths: () => protected,
    );
    final begin = gate.runExclusive(() async {
      await cache.validateDeliveryLocked(source.path);
      entered.complete();
      await committed.future;
      protected.add(source.path);
    });
    await entered.future;
    final clearing = cache.clear();
    expect(await source.exists(), isTrue);
    committed.complete();
    await begin;
    expect((await clearing)['deletedBytes'], 0);
    expect(await source.exists(), isTrue);
    await gate.runExclusive(() {
      protected.clear();
    });
    expect((await cache.clear())['deletedBytes'], 5);
    await expectLater(
      gate.runExclusive(() => cache.validateDeliveryLocked(source.path)),
      throwsA(failure('cache_evicted')),
    );
  });

  test('配置提交真实文件系统失败保留旧预算和文件，随后准入与提交可继续', () async {
    var fail = false;
    final cache = await AppMediaCache.open(
      root: root,
      commitConfiguration: (temporary, destination) async {
        if (fail) {
          await File('${temporary.path}.missing').rename(destination.path);
        }
        await temporary.rename(destination.path);
      },
    );
    await cache.configure(budgetBytes: 20);
    final configuration = File(p.join(root.path, 'media-cache.json'));
    final bytes = await configuration.readAsBytes();
    final shared = await file(p.join(media, 'shared'), 4);
    fail = true;
    await expectLater(
      cache.configure(budgetBytes: 10),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      cache.retain(shared.path),
      throwsA(isA<FileSystemException>()),
    );
    expect((await cache.status())['budgetBytes'], 20);
    expect((await cache.status())['retainedShareCount'], 0);
    expect(await configuration.readAsBytes(), bytes);
    expect(
      await root
          .list()
          .where((entity) => entity.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
    fail = false;
    await cache.retain(shared.path);
    expect((await cache.status())['retainedShareCount'], 1);
    final reopened = await AppMediaCache.open(root: root);
    expect((await reopened.clear())['deletedBytes'], 0);
  });

  test('配置替换已完成但回执失败时核对已提交字节，不保留旧内存预算', () async {
    final cache = await AppMediaCache.open(
      root: root,
      commitConfiguration: (temporary, destination) async {
        await temporary.rename(destination.path);
        throw const FileSystemException('替换后的回执丢失');
      },
    );
    await cache.configure(budgetBytes: 9);
    expect((await cache.status())['budgetBytes'], 9);
    final reopened = await AppMediaCache.open(root: root);
    expect((await reopened.status())['budgetBytes'], 9);
  });

  test('替换回执丢失且配置无法回读时封锁旧所有者，重开恢复真实已提交记录', () async {
    var obstruct = false, commits = 0;
    final configuration = File(p.join(root.path, 'media-cache.json'));
    final committed = File(p.join(root.path, 'committed-config'));
    final original = await file(p.join(media, 'original'), 4);
    final cache = await AppMediaCache.open(
      root: root,
      commitConfiguration: (temporary, destination) async {
        commits++;
        await temporary.rename(destination.path);
        if (obstruct) {
          // 已提交的真实字节仍在同一文件系统；目录使配置路径持续发生实际读取错误。
          await destination.rename(committed.path);
          await Directory(destination.path).create();
          throw const FileSystemException('替换回执丢失，配置路径暂不可读取');
        }
      },
    );
    await cache.configure(budgetBytes: 20);
    final lease = await cache.reserve([FileCacheReservation(original.path, 0)]);
    obstruct = true;
    await expectLater(
      cache.retain(original.path),
      throwsA(failure('cache_storage_unknown')),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        configuration.readAsBytes(),
        throwsA(isA<FileSystemException>()),
      );
    }
    expect(
      (jsonDecode(await committed.readAsString()) as Map)['retainedShares'],
      [original.path],
    );
    await cache.release(lease);
    for (final operation in <Future<Object?> Function()>[
      cache.status,
      cache.clear,
      () => cache.configure(budgetBytes: 1),
      () => cache.retain(original.path),
      () => cache.reserve([FileCacheReservation(original.path, 1)]),
      () => cache.writer(original.path, 1),
      () => cache.gate.runExclusive(
        () => cache.validateDeliveryLocked(original.path),
      ),
    ]) {
      await expectLater(operation(), throwsA(failure('cache_storage_unknown')));
    }
    expect(commits, 2);
    expect(await original.exists(), isTrue);
    await Directory(configuration.path).delete();
    await committed.rename(configuration.path);
    // 修复文件系统后仍需明确重开，旧实例不能猜测或覆盖提交结果。
    await expectLater(
      cache.configure(budgetBytes: 1),
      throwsA(failure('cache_storage_unknown')),
    );
    final reopened = await AppMediaCache.open(root: root);
    expect((await reopened.status())['budgetBytes'], 20);
    expect((await reopened.status())['retainedShareCount'], 1);
    expect((await reopened.clear())['deletedBytes'], 0);
    await reopened.configure(budgetBytes: 19);
    expect((await reopened.status())['retainedShareCount'], 1);
    expect(await original.exists(), isTrue);
  });

  test('配置 commit 屏障期间后续清理排队，不发布未落盘预算', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final cache = await AppMediaCache.open(
      root: root,
      commitConfiguration: (temporary, destination) async {
        entered.complete();
        await release.future;
        await temporary.rename(destination.path);
      },
    );
    final configure = cache.configure(budgetBytes: 13);
    await entered.future;
    var completed = false;
    final status = cache.status().then((value) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    release.complete();
    await configure;
    expect((await status)['budgetBytes'], 13);
  });

  test('损坏配置拒绝且原字节不变，不能静默重置保留所有权', () async {
    final configuration = File(p.join(root.path, 'media-cache.json'));
    for (final data in <String>[
      '{broken',
      jsonEncode({'version': 2}),
      jsonEncode({
        'budgetBytes': 8,
        'outgoingDirectory': null,
        'retainedShares': [3],
      }),
    ]) {
      await configuration.writeAsString(data, flush: true);
      await expectLater(
        AppMediaCache.open(root: root),
        throwsA(failure('cache_storage_invalid')),
      );
      expect(await configuration.readAsString(), data);
    }
  });

  test('路径、链接和 outgoing 归属严格核验，不跟随链接统计或删除外部文件', () async {
    final external = await file(p.join(sandbox.path, 'outside'), 6);
    final linked = Link(p.join(media, 'linked'));
    await linked.create(external.path);
    final cache = await AppMediaCache.open(root: root);
    expect((await cache.status())['usedBytes'], 0);
    expect((await cache.clear())['deletedBytes'], 0);
    expect(await external.exists(), isTrue);
    for (final path in [
      linked.path,
      p.join(media, '..', 'outside'),
      p.join(root.path, 'media-other', 'file'),
      'relative',
    ]) {
      await expectLater(
        cache.reserve([FileCacheReservation(path, 1)]),
        throwsA(failure('invalid_argument')),
      );
    }
    await expectLater(
      cache.configure(outgoingDirectory: p.join(media, 'outgoing')),
      throwsA(failure('invalid_argument')),
    );
    final rootLink = Link(p.join(sandbox.path, 'alias'));
    await rootLink.create(root.path);
    await expectLater(
      AppMediaCache.open(root: Directory(rootLink.path)),
      throwsA(failure('invalid_argument')),
    );
    final parentLink = Link(p.join(sandbox.path, 'parent-link'));
    await parentLink.create(sandbox.path);
    await expectLater(
      cache.configure(outgoingDirectory: p.join(parentLink.path, 'outgoing')),
      throwsA(failure('invalid_argument')),
    );
  }, skip: Platform.isWindows ? '宿主权限不保证允许创建符号链接' : false);

  test('配置文件链接在读取前拒绝，外部目标不被覆盖', () async {
    final external = await file(p.join(sandbox.path, 'outside-config'), 5);
    await Link(p.join(root.path, 'media-cache.json')).create(external.path);
    await expectLater(
      AppMediaCache.open(root: root),
      throwsA(failure('invalid_argument')),
    );
    expect(await external.length(), 5);
  }, skip: Platform.isWindows ? '宿主权限不保证允许创建符号链接' : false);

  test('命令参数、容量溢出和未受管分享按真实结果处理', () async {
    final cache = await AppMediaCache.open(root: root);
    expect(
      await cache.command('media.cache.retain', {
        'localPath': p.join(sandbox.path, 'external'),
        'ifManaged': true,
      }),
      {'managed': false, 'retained': false},
    );
    await expectLater(
      cache.command('media.cache.configure', {'budgetBytes': 0}),
      throwsA(failure('invalid_argument')),
    );
    await expectLater(
      cache.command('media.cache.configure', {'budgetBytes': '5'}),
      throwsA(failure('invalid_argument')),
    );
    await expectLater(
      cache.reserve([
        FileCacheReservation(p.join(media, 'a'), 0x7fffffffffffffff),
        FileCacheReservation(p.join(media, 'b'), 1),
      ]),
      throwsA(failure('invalid_argument')),
    );
    expect((await cache.status())['reservedBytes'], 0);
    final lease = await cache.reserve([
      FileCacheReservation(p.join(media, 'a'), 0),
    ]);
    expect(
      (await cache.command('media.cache.release', {
        'leaseId': lease,
      }))['released'],
      isTrue,
    );
    expect(
      (await cache.command('media.cache.release', {
        'leaseId': lease,
      }))['released'],
      isFalse,
    );
  });
  test('真实空间不足和无法核验均在准入前拒绝并报告所需可用量', () async {
    var free = 3;
    var unavailable = false;
    final cache = await AppMediaCache.open(
      root: root,
      freeBytes: (_) async {
        if (unavailable) throw const FileSystemException('space query failed');
        return free;
      },
    );
    await cache.configure(budgetBytes: 20);
    await expectLater(
      cache.reserve([FileCacheReservation(p.join(media, 'incoming'), 4)]),
      throwsA(
        isA<MediaCacheFailure>().having(
          (error) => error.message,
          'message',
          contains('需要 4 B，当前可用 3 B'),
        ),
      ),
    );
    expect((await cache.status())['reservedBytes'], 0);
    free = 10;
    final lease = await cache.reserve([
      FileCacheReservation(p.join(media, 'incoming'), 4),
    ]);
    expect((await cache.status())['availableBytes'], 6);
    unavailable = true;
    await expectLater(
      cache.reserve([FileCacheReservation(p.join(media, 'another'), 1)]),
      throwsA(failure('cache_space_unknown')),
    );
    expect((await cache.status())['spaceVerified'], isFalse);
    await cache.release(lease);
  });

  test('保护项目按实际占用去重并呈现真实来源与未知分享原因', () async {
    final original = await file(p.join(media, 'receive', 'original.jpg'), 8);
    final cache = await AppMediaCache.open(
      root: root,
      protectionDetails: () => [
        {
          'path': original.path,
          'name': '原照片.jpg',
          'sourceLabel': '来源手机',
          'sourcePath': '/sdcard/DCIM/原照片.jpg',
          'transferId': 'receive-task',
          'canExport': true,
        },
      ],
    );
    final lease = await cache.reserve([
      FileCacheReservation(original.parent.path, 0),
    ]);
    await cache.retain(original.path);
    final status = await cache.status();
    final items = status['protectedItems']! as List;
    expect(items, hasLength(1));
    expect((items.single as Map)['bytes'], 8);
    expect((items.single as Map)['name'], '原照片.jpg');
    expect((items.single as Map)['sourceLabel'], '来源手机');
    expect((items.single as Map)['externalLifetimeUnknown'], isTrue);
    expect((items.single as Map)['reason'], contains('读取寿命未知'));
    await cache.release(lease);
    expect((await cache.clear())['deletedBytes'], 0);
    expect(await original.exists(), isTrue);
  });
}
