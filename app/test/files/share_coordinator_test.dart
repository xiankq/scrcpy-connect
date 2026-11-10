import 'package:scrcpy_connect/models/file_failure.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/file_share_service.dart';

const shareId = '00000000-0000-4000-8000-000000000001';
const nextShareId = '00000000-0000-4000-8000-000000000002';
typedef Json = Map<String, dynamic>;

class Fixture {
  Fixture(this.directory);
  final Directory directory;
  final calls = <String>[];
  late final api = LocalFixture(this);
  late final localFiles = LocalFiles(api);
  FileShareService? coordinator;
  String? lease;
  bool ready = false, failRelease = false, missingReceipt = false;
  int opens = 0, consumed = 0;
  int sourceLength = 3;
  final opened = Completer<void>();
  Completer<Json>? holdOpen;
  final descriptors = <String, Json>{};

  Future<FileShareService> open({
    ShareLimits limits = const ShareLimits(),
  }) async {
    return coordinator = await FileShareService.open(
      files: () async => localFiles,
      platform: platform,
      limits: limits,
    );
  }

  Json descriptor(int index) => {
    'fdLeaseId': 'lease-$index',
    'fd': index + 100,
    'offset': 2,
    'declaredLength': sourceLength,
    'name': '来源$index.txt',
  };

  Future<Json> platform(String command, Json params) async {
    calls.add(command);
    switch (command) {
      case 'sharing.platform.environment':
        return {
          'cacheDirectory': directory.path,
          'ownerLeaseId': lease,
          'ownerReady': ready,
        };
      case 'sharing.platform.claim':
        if (params['expectedOwnerLeaseId'] != lease &&
            params['ownerLeaseId'] != lease) {
          throw StateError('错误代次');
        }
        lease = params['ownerLeaseId'] as String;
        ready = true;
        return {'claimed': true, 'ownerLeaseId': lease};
      case 'sharing.platform.pending':
        return {'shares': <Json>[]};
      case 'sharing.platform.open':
        expect(params['ownerLeaseId'], lease);
        expect(ready, isTrue);
        opens++;
        final value = descriptor(params['index'] as int);
        descriptors[params['openId'] as String] = value;
        if (!opened.isCompleted) opened.complete();
        return holdOpen?.future ?? value;
      case 'sharing.platform.cancel':
        final waiting = holdOpen;
        if (waiting != null && !waiting.isCompleted) {
          waiting.complete(descriptors[params['openId']]!);
        }
        return {'cancelled': true};
      case 'sharing.platform.release':
        if (failRelease && params['fdLeaseId'] == 'lease-0') {
          throw StateError('原始 FD 未关闭');
        }
        return missingReceipt ? {} : {'released': true};
      case 'sharing.platform.consume':
        if (!ready || params['ownerLeaseId'] != lease) {
          throw StateError('当前代次尚未准入');
        }
        consumed++;
        return {'consumed': true};
    }
    throw StateError('未知平台命令 $command');
  }

  Future<void> dispose() async {
    api.failScopeClose = false;
    failRelease = false;
    missingReceipt = false;
    await coordinator?.close();
    await directory.delete(recursive: true);
  }
}

class LocalFixture implements NativeLocalFilesApi {
  LocalFixture(this.fixture);
  final Fixture fixture;
  final copies = <String, (String, LocalFileCopyRequest)>{};
  final committed = <String>{};
  final requests = <LocalFileCopyRequest>[];
  final started = Completer<void>();
  Completer<void>? holdCopy;
  bool failScopeClose = false;
  int nextScope = 0, nextCopy = 0;
  int freeBytes = 40 * 1024 * 1024;

  @override
  Future<String> openScope(
    String key,
    List<Uint8List> roots,
    int timeout,
  ) async {
    fixture.calls.add('scope.open');
    expect(key, '${fixture.directory.path}/incoming');
    return 'scope-${++nextScope}';
  }

  @override
  Future<void> closeScope(String scope, int timeout) async {
    fixture.calls.add('scope.close');
    if (failScopeClose) {
      throw const LocalFileException(
        LocalFileErrorCode.cleanupUnconfirmed,
        '仍在复制',
      );
    }
    final held = holdCopy;
    if (held != null && !held.isCompleted) {
      held.completeError(
        const LocalFileException(LocalFileErrorCode.cancelled, '已撤销'),
      );
    }
    for (final id in copies.keys.toList()) {
      if (copies[id]!.$1 == scope) await closeCopy(id, timeout);
    }
  }

  @override
  Future<LocalFileStat> stat(String scope, Uint8List path) async {
    final target = utf8.decode(path);
    expect(target, startsWith('${fixture.directory.path}/incoming/'));
    expect(await Directory(target).exists(), isTrue);
    return LocalFileStat(
      identity: identity(utf8.decode(path), directory: true),
      freeBytes: BigInt.from(freeBytes),
    );
  }

  @override
  Future<String> createCopy(String scope, LocalFileCopyRequest request) async {
    fixture.calls.add('copy.create');
    final id = 'copy-${++nextCopy}';
    copies[id] = (scope, request);
    requests.add(request);
    return id;
  }

  @override
  Future<LocalFileCopyResult> runCopy(String id) async {
    fixture.calls.add('copy.run');
    if (!started.isCompleted) started.complete();
    await holdCopy?.future;
    final request = copies[id]!.$2;
    final bytes = utf8
        .encode('xxabc')
        .skip(request.sourceOffset)
        .take(request.length ?? 5)
        .toList();
    if (bytes.length > request.maxBytes) {
      throw const LocalFileException(LocalFileErrorCode.byteLimit, '超出字节上限');
    }
    final file = File(utf8.decode(request.target.pathBytes!));
    await file.writeAsBytes(bytes, flush: true);
    return LocalFileCopyResult(
      bytes: bytes.length,
      identity: identity(file.path, size: bytes.length),
      sourceIdentity: identity('fd', size: 5),
    );
  }

  @override
  Future<LocalFileIdentity> commit(
    String scope,
    String id,
    Uint8List destination,
    LocalFileIdentity expected,
  ) async {
    fixture.calls.add('copy.commit');
    final source = File(utf8.decode(copies[id]!.$2.target.pathBytes!));
    final result = await source.rename(utf8.decode(destination));
    committed.add(id);
    return identity(result.path, size: await result.length());
  }

  @override
  Future<void> cancelCopy(String id) async {
    fixture.calls.add('copy.cancel');
    final held = holdCopy;
    if (held != null && !held.isCompleted && !failScopeClose) {
      held.completeError(
        const LocalFileException(LocalFileErrorCode.cancelled, '已撤销'),
      );
    }
  }

  @override
  Future<void> closeCopy(String id, int timeout) async {
    fixture.calls.add('copy.close');
    if (failScopeClose) {
      throw const LocalFileException(
        LocalFileErrorCode.cleanupUnconfirmed,
        '尚未排空',
      );
    }
    final value = copies.remove(id);
    if (value != null && !committed.contains(id)) {
      final part = File(utf8.decode(value.$2.target.pathBytes!));
      if (await part.exists()) await part.delete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalFileIdentity identity(
  String path, {
  int size = 0,
  bool directory = false,
}) => LocalFileIdentity(
  device: BigInt.one,
  inode: BigInt.from(path.hashCode.abs()),
  size: BigInt.from(size),
  modifiedSeconds: 1,
  modifiedNanos: 0,
  kind: directory ? LocalFileKind.directory : LocalFileKind.file,
);

void main() {
  Future<Fixture> fixture() async {
    final value = Fixture(
      await Directory.systemTemp.createTemp('share-import-'),
    );
    addTearDown(value.dispose);
    return value;
  }

  test('关闭期间迟到的 provider 回执仍登记并精确释放，不启动复制', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.holdOpen = Completer<Json>();
    final operation = coordinator.receive({
      'shareId': shareId,
      'sourceCount': 1,
    });
    await f.opened.future;
    await coordinator.close();
    expect((await operation)['status'], 'error');
    expect(f.api.requests, isEmpty);
    expect(f.calls, contains('sharing.platform.release'));
    expect(
      f.calls.lastIndexOf('scope.close'),
      lessThan(f.calls.indexOf('sharing.platform.cancel')),
    );
  });

  test('SDK 排空失败不释放平台 PFD；保留同 scope 供第二次 close 重试', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.api.holdCopy = Completer<void>();
    final operation = coordinator.receive({
      'shareId': shareId,
      'sourceCount': 1,
    });
    await f.api.started.future;
    f.api.failScopeClose = true;
    await expectLater(coordinator.close(), throwsA(isA<LocalFileException>()));
    expect(f.calls, isNot(contains('sharing.platform.release')));
    f.api.failScopeClose = false;
    await coordinator.close();
    await operation;
    expect(f.calls, contains('sharing.platform.release'));
  });

  test('一个平台 FD 关闭失败仍关闭其他 FD；重新交付仅重试清理，不重复复制', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.failRelease = true;
    await expectLater(
      coordinator.receive({'shareId': shareId, 'sourceCount': 2}),
      throwsStateError,
    );
    expect(f.calls.where((c) => c == 'sharing.platform.release'), hasLength(2));
    expect(f.consumed, 0);
    f.failRelease = false;
    expect(
      (await coordinator.receive({
        'shareId': shareId,
        'sourceCount': 2,
      }))['status'],
      'ready',
    );
    expect(f.opens, 2);
    expect(f.api.requests, hasLength(2));
    expect(f.consumed, 1);
  });

  test('同分享并发交付仅复制一次；超过批次预算时不交付已导入的部分文件', () async {
    final f = await fixture();
    final coordinator = await f.open(
      limits: const ShareLimits(fileBytes: 4, batchBytes: 5, totalBytes: 8),
    );
    f.api.holdCopy = Completer<void>();
    final first = coordinator.receive({'shareId': shareId, 'sourceCount': 2});
    await f.api.started.future;
    final same = coordinator.receive({'shareId': shareId, 'sourceCount': 2});
    f.api.holdCopy!.complete();
    expect((await first)['status'], 'error');
    expect((await same)['status'], 'error');
    expect(f.opens, 2);
    expect((await coordinator.command('sharing.pending', const {}))['shares'], [
      containsPair('files', isEmpty),
    ]);
    f.api.holdCopy = null;
    expect(
      (await coordinator.receive({
        'shareId': nextShareId,
        'sourceCount': 1,
      }))['status'],
      'ready',
    );
  });

  test('同 engine 换 Activity 先排空旧导入和日志写入，再认领并重开日志', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.api.holdCopy = Completer<void>();
    final operation = coordinator.receive({
      'shareId': shareId,
      'sourceCount': 1,
    });
    final observed = operation.then<Object?>(
      (value) => value,
      onError: (Object e) => e,
    );
    await f.api.started.future;
    final oldLease = f.lease;
    f.ready = false;
    await coordinator.configure();
    await observed;
    expect(f.lease, isNot(oldLease));
    expect(
      f.calls.lastIndexOf('scope.close'),
      lessThan(f.calls.lastIndexOf('sharing.platform.claim')),
    );
    final pending = await coordinator.command('sharing.pending', const {});
    expect((pending['shares'] as List).single['status'], 'error');
    f.api.holdCopy = null;
    expect(
      (await coordinator.receive({
        'shareId': nextShareId,
        'sourceCount': 1,
      }))['status'],
      'ready',
    );
  });

  test('原始 FD 缺少释放确认时保留责任，后继 receive 不重放导入', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.missingReceipt = true;
    await expectLater(
      coordinator.receive({'shareId': shareId, 'sourceCount': 1}),
      throwsA(isA<Exception>()),
    );
    expect(f.consumed, 0);
    f.missingReceipt = false;
    expect(
      (await coordinator.receive({
        'shareId': shareId,
        'sourceCount': 1,
      }))['status'],
      'ready',
    );
    expect(f.opens, 1);
  });

  test('consume 等当前导入完整收尾后移除批次，不与最后回执读取竞争', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.api.holdCopy = Completer<void>();
    final operation = coordinator.receive({
      'shareId': shareId,
      'sourceCount': 1,
    });
    await f.api.started.future;
    expect(await coordinator.command('sharing.consume', {'shareId': shareId}), {
      'consumed': true,
    });
    expect((await operation)['status'], 'error');
    expect(
      (await coordinator.command('sharing.pending', const {}))['shares'],
      isEmpty,
    );
    expect(f.calls, contains('sharing.platform.release'));
    expect(f.api.copies, isEmpty);
  });

  test('取消排队的第二个分享立即生效，不停止第一个分享或随后重新导入第二个', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.api.holdCopy = Completer<void>();
    final first = coordinator.receive({'shareId': shareId, 'sourceCount': 1});
    await f.api.started.future;
    final second = coordinator.receive({
      'shareId': nextShareId,
      'sourceCount': 1,
    });
    final cancelled = expectLater(
      second,
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(
      await coordinator.command('sharing.cancel', {'shareId': nextShareId}),
      {'cancelled': true, 'shareId': nextShareId},
    );
    await cancelled;
    expect(f.api.holdCopy!.isCompleted, isFalse);
    expect(f.opens, 1);
    f.api.holdCopy!.complete();
    expect((await first)['status'], 'ready');
    await coordinator.configure();
    expect(f.opens, 1);
    expect(
      (await coordinator.command('sharing.pending', const {}))['shares'],
      hasLength(2),
    );
  });

  test('空文件能在零复制预算中导入，错误批次不会借出任何 FD', () async {
    final f = await fixture();
    final coordinator = await f.open();
    f.sourceLength = 0;
    f.api.freeBytes = const ShareLimits().minimumFreeBytes;
    final empty = await coordinator.receive({
      'shareId': shareId,
      'sourceCount': 1,
    });
    expect(empty['files'], [containsPair('size', 0)]);
    expect(f.api.requests.single.maxBytes, 0);
    expect(
      (await coordinator.receive({
        'shareId': nextShareId,
        'sourceCount': 33,
      }))['status'],
      'error',
    );
    expect(f.opens, 1);
  });
}
