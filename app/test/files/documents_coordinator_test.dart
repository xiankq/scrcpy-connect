import 'dart:async';
import 'dart:convert';

import 'package:adb/adb.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/platform/application_platform.dart';
import 'package:scrcpy_connect/files/documents/documents_coordinator.dart';
import 'package:scrcpy_connect/files/documents/document_scope_recovery.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

class Fixture {
  final calls = <(String, DocumentsJson)>[];
  final nodes = <String, DocumentsJson>{};
  final children = <String, List<String>>{};
  final local = <String, DocumentsJson>{};
  List<String> selected = [];
  String choice = 'keepBoth';
  String ownerLeaseId = 'fixture-owner';
  Future<DocumentsJson> Function(DocumentsJson)? onClaim;
  bool mutateSource = false, loseCreate = false, failClose = false;
  Completer<DocumentsJson>? picker;
  DocumentsJson node(
    String id,
    String name, {
    bool directory = false,
    int size = 3,
  }) {
    return nodes[id] = {
      'handle': id,
      'id': id,
      'authority': 'fixture',
      'uri': 'content://fixture/$id',
      'name': name,
      'directory': directory,
      'virtual': false,
      'canCreate': directory,
      'canWrite': !directory,
      'size': directory ? null : size,
      'modified': 1,
    };
  }

  late final nativeFiles = LocalFixture(this);
  late final localFiles = LocalFiles(nativeFiles);
  Future<LocalFiles> files() async => localFiles;
  late final coordinator = DocumentsCoordinator(
    files: files,
    platform: platform,
  );
  Future<DocumentsJson> platform(String command, DocumentsJson params) async {
    calls.add((command, params));
    if (command != 'documents.platform.environment' &&
        command != 'documents.platform.claim' &&
        params['ownerLeaseId'] != ownerLeaseId) {
      throw const ApplicationCommandException('cancelled', '平台代次已撤销。');
    }
    final id = params['handle'];
    switch (command) {
      case 'documents.platform.environment':
        return {'cacheDirectory': '/cache', 'ownerLeaseId': ownerLeaseId};
      case 'documents.platform.claim':
        if (params['expectedOwnerLeaseId'] != ownerLeaseId &&
            params['ownerLeaseId'] != ownerLeaseId) {
          throw const ApplicationCommandException('cancelled', '旧平台代次。');
        }
        ownerLeaseId = params['ownerLeaseId'] as String;
        if (onClaim case final hook?) return hook(params);
        return {'claimed': true, 'ownerLeaseId': ownerLeaseId};
      case 'documents.platform.release':
        return {'released': true};
      case 'documents.platform.picker':
        return picker?.future ??
            {
              'status': 'selected',
              'documents': [
                for (final id in selected)
                  {'handle': id, 'uri': 'content://fixture/$id'},
              ],
            };
      case 'documents.platform.metadata':
        return {...nodes[id]!};
      case 'documents.platform.children':
        return {
          'documents': [
            for (final child in children[id] ?? <String>[]) {...nodes[child]!},
          ],
          'hasMore': false,
        };
      case 'documents.platform.openFd':
        return {'fd': 44, 'fdLeaseId': 'lease-$id'};
      case 'documents.platform.releaseFd':
        if (failClose) {
          throw const ApplicationCommandException(
            'close_failed',
            'provider refused close',
          );
        }
        return {'released': true};
      case 'documents.platform.cancel':
        picker?.complete({'status': 'cancelled'});
        picker = null;
        return {'cancelled': true};
      case 'documents.platform.conflict':
        return {'choice': choice};
      case 'documents.platform.create':
        if (loseCreate) {
          throw const ApplicationCommandException('binder_lost', 'lost');
        }
        final next = 'created-${nodes.length}';
        final fresh = node(
          next,
          params['name'] as String,
          directory: params['mime'] == 'vnd.android.document/directory',
          size: 0,
        );
        children.putIfAbsent(id as String, () => []).add(next);
        return {...fresh};
      default:
        return {};
    }
  }
}

LocalFileIdentity identity(DocumentsJson value) => LocalFileIdentity(
  device: BigInt.from(value['device'] as int? ?? 1),
  inode: BigInt.from(value['inode'] as int? ?? 1),
  size: BigInt.from(value['size'] as int? ?? 0),
  modifiedSeconds: value['modified'] as int? ?? 1,
  modifiedNanos: value['modifiedNs'] as int? ?? 0,
  kind: switch (value['kind']) {
    'file' => LocalFileKind.file,
    'directory' => LocalFileKind.directory,
    'symlink' => LocalFileKind.symlink,
    _ => LocalFileKind.other,
  },
);

class LocalFixture implements NativeLocalFilesApi {
  LocalFixture(this.fixture);
  final Fixture fixture;
  int nextScope = 0, nextCopy = 0;
  final copies = <String, (String, LocalFileCopyRequest)>{};
  final running = <String, Future<LocalFileCopyResult>>{};
  final committed = <String>{};
  Future<LocalFileStat> Function(Uint8List)? onStat;
  Future<LocalFileList> Function(Uint8List, int)? onList;
  Future<LocalFileCopyResult> Function(LocalFileCopyRequest)? onRunCopy;
  Future<void> Function(String)? onCloseScope;
  Future<void> Function(String)? onCloseCopy;
  Future<String> Function(List<Uint8List>)? onOpenScope;
  Future<String> Function(String, LocalFileCopyRequest)? onCreateCopy;
  String path(List<int> bytes) => utf8.decode(bytes);
  @override
  Future<String> openScope(
    String scopeKey,
    List<Uint8List> allowedRoots,
    int closeTimeoutMs,
  ) async {
    fixture.calls.add((
      'local.scope.open',
      {'key': scopeKey, 'roots': allowedRoots},
    ));
    return onOpenScope?.call(allowedRoots) ?? 'scope-${++nextScope}';
  }

  @override
  Future<void> closeScope(String scopeId, int timeoutMs) async {
    fixture.calls.add(('local.scope.close', {'scope': scopeId}));
    if (onCloseScope case final hook?) await hook(scopeId);
    final owned = copies.entries
        .where((entry) => entry.value.$1 == scopeId)
        .map((entry) => entry.key)
        .toList();
    for (final id in owned) {
      await closeCopy(id, timeoutMs);
    }
  }

  @override
  Future<LocalFileStat> stat(String scopeId, Uint8List bytes) async {
    fixture.calls.add(('local.stat', {'path': path(bytes)}));
    if (onStat case final hook?) return hook(bytes);
    return LocalFileStat(
      identity: identity(fixture.local[path(bytes)] ?? {}),
      freeBytes: BigInt.from(1000000000),
    );
  }

  @override
  Future<LocalFileList> list(
    String scopeId,
    Uint8List bytes,
    int maxEntries,
  ) async {
    fixture.calls.add((
      'local.list',
      {'path': path(bytes), 'maxEntries': maxEntries},
    ));
    if (onList case final hook?) return hook(bytes, maxEntries);
    return LocalFileList(
      identity: identity(fixture.local[path(bytes)] ?? {}),
      entries: const [],
    );
  }

  @override
  Future<void> mkdir(String scopeId, Uint8List bytes, bool exclusive) async {
    fixture.calls.add((
      'local.mkdir',
      {'path': path(bytes), 'exclusive': exclusive},
    ));
    fixture.local[path(bytes)] = {'kind': 'directory'};
  }

  @override
  Future<void> remove(
    String scopeId,
    Uint8List bytes,
    LocalFileIdentity expectedIdentity,
  ) async {
    fixture.calls.add(('local.remove', {'path': path(bytes)}));
    fixture.local.remove(path(bytes));
  }

  @override
  Future<String> createCopy(
    String scopeId,
    LocalFileCopyRequest request,
  ) async {
    final id = onCreateCopy == null
        ? 'copy-${++nextCopy}'
        : await onCreateCopy!(scopeId, request);
    copies[id] = (scopeId, request);
    fixture.calls.add(('local.copy', {'request': request}));
    return id;
  }

  @override
  Future<LocalFileCopyResult> runCopy(String copyId) =>
      running.putIfAbsent(copyId, () async {
        final request = copies[copyId]!.$2;
        if (onRunCopy case final hook?) return hook(request);
        if (request.maxBytes < 3) {
          throw const LocalFileException(
            LocalFileErrorCode.byteLimit,
            '复制超过调用方预算。',
          );
        }
        if (fixture.mutateSource) {
          fixture.nodes[fixture.selected.single]!['modified'] = 2;
        }
        if (request.target.kind == LocalFileEndpointKind.descriptor) {
          final handle = fixture.calls
              .lastWhere((call) => call.$1 == 'documents.platform.openFd')
              .$2['handle'];
          fixture.nodes[handle]!['size'] = 3;
        } else {
          fixture.local[path(request.target.pathBytes!)] = {
            'kind': 'file',
            'size': 3,
          };
        }
        return LocalFileCopyResult(
          bytes: 3,
          identity: identity({'kind': 'file', 'size': 3}),
          sourceIdentity: identity({'kind': 'file', 'size': 3}),
        );
      });
  @override
  Future<void> cancelCopy(String copyId) async {}
  @override
  Future<void> closeCopy(String copyId, int timeoutMs) async {
    if (onCloseCopy case final hook?) await hook(copyId);
    if (running[copyId] case final work?) {
      try {
        await work;
      } catch (_) {
        /* 等待复制真实退出，原错误由调用者读取。 */
      }
    }
    final request = copies.remove(copyId)?.$2;
    fixture.calls.add(('local.copy.close', {'copy': copyId}));
    if (request?.target.kind == LocalFileEndpointKind.part &&
        !committed.contains(copyId)) {
      final target = path(request!.target.pathBytes!);
      fixture.calls.add(('local.part.remove', {'path': target}));
      fixture.local.remove(target);
    }
  }

  @override
  Future<LocalFileIdentity> commit(
    String scopeId,
    String copyId,
    Uint8List destination,
    LocalFileIdentity expectedIdentity,
  ) async {
    fixture.calls.add(('local.commit', {'path': path(destination)}));
    final source = path(copies[copyId]!.$2.target.pathBytes!);
    fixture.local[path(destination)] = fixture.local.remove(source)!;
    committed.add(copyId);
    return expectedIdentity;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同 Dart 会话换 Activity 后精确收尾旧操作，再排空接管后启动新选择器', () async {
    final f = Fixture()..picker = Completer<DocumentsJson>();
    var ready = true;
    final oldPicker = Completer<void>();
    const channel = MethodChannel('dev.scrcpyconnect/platform');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final params = Map<String, dynamic>.from(call.arguments as Map);
      final response = await f.platform(call.method, params);
      if (call.method == 'documents.platform.claim') ready = true;
      return {
        ...response,
        if (call.method == 'documents.platform.environment')
          'ownerReady': ready,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final platform = ApplicationPlatform(
      applicationRequest: (_, _) async => {},
      localFiles: f.files,
      emit: (_) {},
      isDisposed: () => false,
    );
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: (command, params) {
        if (command == 'documents.platform.picker' &&
            params['operationId'] == 'old-activity') {
          oldPicker.complete();
        }
        return platform.request(command, params);
      },
    );
    final old = coordinator.request('documents.importFiles', {
      'operationId': 'old-activity',
    });
    await oldPicker.future;
    ready = false;
    await coordinator.request('documents.cancel', {
      'operationId': 'old-activity',
    });
    await old;
    final oldCleanup = f.calls.where(
      (call) =>
          call.$2['operationId'] == 'old-activity' &&
          [
            'documents.platform.cancel',
            'documents.platform.release',
          ].contains(call.$1),
    );
    expect(oldCleanup, hasLength(2));
    expect(
      oldCleanup.map((call) => call.$2['ownerLeaseId']),
      everyElement('fixture-owner'),
    );
    f.selected = ['root'];
    f.node('root', 'Empty', directory: true);
    final result = await coordinator.request('documents.importDirectory', {
      'operationId': 'new-activity',
    });
    expect(result['status'], 'imported');
    final claimIndex = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.claim',
    );
    final newPickerIndex = f.calls.indexWhere(
      (call) =>
          call.$1 == 'documents.platform.picker' &&
          call.$2['operationId'] == 'new-activity',
    );
    expect(claimIndex, greaterThan(0));
    expect(f.calls[claimIndex - 1].$1, 'local.scope.close');
    expect(claimIndex, lessThan(newPickerIndex));
    expect(f.calls[newPickerIndex].$2['ownerLeaseId'], f.ownerLeaseId);
    expect(f.ownerLeaseId, isNot('fixture-owner'));
    final keys = f.calls
        .where((call) => call.$1 == 'local.scope.open')
        .map((call) => call.$2['key']);
    expect(keys, everyElement('/cache/documents'));
    expect(keys, hasLength(3));
    await coordinator.dispose();
    await platform.dispose();
  });

  test('claim 已提交但回执丢失时先确认同候选，再次换代仍重新排空 scope', () async {
    final f = Fixture()..selected = ['root'];
    f.node('root', 'Empty', directory: true);
    var ready = false;
    var attempts = 0;
    final confirming = Completer<void>();
    final confirm = Completer<void>();
    const channel = MethodChannel('dev.scrcpyconnect/platform');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    f.onClaim = (_) async {
      ready = true;
      attempts++;
      if (attempts == 1) {
        throw PlatformException(code: 'reply_lost', message: '接管已完成但回执丢失。');
      }
      if (attempts == 2) {
        confirming.complete();
        await confirm.future;
      }
      return {'claimed': true, 'ownerLeaseId': f.ownerLeaseId};
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      final response = await f.platform(
        call.method,
        Map<String, dynamic>.from(call.arguments as Map),
      );
      return {
        ...response,
        if (call.method == 'documents.platform.environment')
          'ownerReady': ready,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final platform = ApplicationPlatform(
      applicationRequest: (_, _) async => {},
      localFiles: f.files,
      emit: (_) {},
      isDisposed: () => false,
    );
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: platform.request,
    );
    final first = await coordinator.request('documents.importDirectory', {
      'operationId': 'lost-reply',
    });
    expect(first['status'], 'failed');
    expect(ready, isTrue);
    // 新实例也必须遵守共享 pending，不能仅查看自己的恢复标记。
    final nextPlatform = ApplicationPlatform(
      applicationRequest: (_, _) async => {},
      localFiles: f.files,
      emit: (_) {},
      isDisposed: () => false,
    );
    final nextCoordinator = DocumentsCoordinator(
      files: f.files,
      platform: nextPlatform.request,
    );
    final second = nextCoordinator.request('documents.importDirectory', {
      'operationId': 'confirmed',
    });
    await confirming.future;
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.picker'),
      isEmpty,
    );
    final firstClaims = f.calls
        .where((call) => call.$1 == 'documents.platform.claim')
        .toList();
    expect(firstClaims, hasLength(2));
    expect(firstClaims[0].$2, firstClaims[1].$2);
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.open'),
      hasLength(1),
    );
    confirm.complete();
    expect((await second)['status'], 'imported');
    final previousEnd = f.calls.length;
    ready = false;
    expect(
      (await nextCoordinator.request('documents.importDirectory', {
        'operationId': 'next-activity',
      }))['status'],
      'imported',
    );
    final next = f.calls.skip(previousEnd).toList();
    final reopened = next.indexWhere((call) => call.$1 == 'local.scope.open');
    final drained = next.indexWhere((call) => call.$1 == 'local.scope.close');
    final claim = next.indexWhere(
      (call) => call.$1 == 'documents.platform.claim',
    );
    final picker = next.indexWhere(
      (call) => call.$1 == 'documents.platform.picker',
    );
    expect(reopened, greaterThanOrEqualTo(0));
    expect(reopened, lessThan(drained));
    expect(drained, lessThan(claim));
    expect(claim, lessThan(picker));
    expect(
      next[claim].$2['ownerLeaseId'],
      isNot(firstClaims.first.$2['ownerLeaseId']),
    );
    await nextCoordinator.dispose();
    await nextPlatform.dispose();
    await coordinator.dispose();
    await platform.dispose();
  });

  LocalFileCopyResult copied(int bytes) => LocalFileCopyResult(
    bytes: bytes,
    identity: identity({'kind': 'file', 'size': bytes}),
    sourceIdentity: identity({'kind': 'file', 'size': bytes}),
  );

  test('恢复先排空 SDK scope，再等待平台 claim 关闭旧原始 PFD 后读取缓存', () async {
    final f = Fixture();
    final claiming = Completer<void>();
    final claimed = Completer<DocumentsJson>();
    f.onClaim = (_) {
      claiming.complete();
      return claimed.future;
    };
    final recovery = DocumentScopeRecovery(
      files: f.files,
      platform: f.platform,
    );
    var cacheReads = 0;
    final restoring = () async {
      await recovery.recover();
      cacheReads++;
    }();
    await claiming.future;
    expect(cacheReads, 0);
    final closed = f.calls.indexWhere((call) => call.$1 == 'local.scope.close');
    final claim = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.claim',
    );
    expect(closed, lessThan(claim));
    claimed.complete({'claimed': true, 'ownerLeaseId': f.ownerLeaseId});
    await restoring;
    expect(cacheReads, 1);
  });

  test('平台 claim 失败后重试同一候选代次，不再次打开已排空的 scope', () async {
    final f = Fixture();
    var fails = true;
    f.onClaim = (_) async {
      if (fails) {
        throw const ApplicationCommandException(
          'document_cleanup_unconfirmed',
          '原始 PFD 尚未关闭。',
        );
      }
      return {'claimed': true, 'ownerLeaseId': f.ownerLeaseId};
    };
    final recovery = DocumentScopeRecovery(
      files: f.files,
      platform: f.platform,
    );
    await expectLater(
      recovery.recover(),
      throwsA(isA<ApplicationCommandException>()),
    );
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.open'),
      hasLength(1),
    );
    fails = false;
    await recovery.recover();
    final claims = f.calls
        .where((call) => call.$1 == 'documents.platform.claim')
        .toList();
    expect(claims, hasLength(2));
    expect(claims[0].$2, claims[1].$2);
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.open'),
      hasLength(1),
    );
  });

  test('平台 release 未确认不能清除操作，重试关闭成功后才放行', () async {
    final f = Fixture()..selected = ['root'];
    f.node('root', 'Empty', directory: true);
    var released = false;
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: (command, params) async {
        if (command == 'documents.platform.release' && !released) {
          return {'released': false};
        }
        return f.platform(command, params);
      },
    );
    await expectLater(
      coordinator.request('documents.importDirectory'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'document_cleanup_unconfirmed',
        ),
      ),
    );
    await expectLater(
      coordinator.request('documents.importFiles'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'documents_busy',
        ),
      ),
    );
    released = true;
    await coordinator.dispose();
    expect(f.calls.last.$1, 'documents.platform.release');
    expect(
      f.calls
          .where(
            (call) =>
                call.$1.startsWith('documents.platform.') &&
                call.$1 != 'documents.platform.environment' &&
                call.$1 != 'documents.platform.claim',
          )
          .map((call) => call.$2['ownerLeaseId']),
      everyElement('fixture-owner'),
    );
  });

  test('恢复栅栏确认 scope 排空前不读取缓存，并与文档操作共用 key', () async {
    final f = Fixture()..selected = ['root'];
    f.node('root', 'Empty', directory: true);
    final closing = Completer<void>();
    final entered = Completer<void>();
    f.nativeFiles.onCloseScope = (_) {
      entered.complete();
      return closing.future;
    };
    final recovery = DocumentScopeRecovery(
      files: f.files,
      platform: f.platform,
    );
    var cacheReads = 0;
    final restoring = () async {
      await recovery.recover();
      cacheReads++;
    }();
    await entered.future;
    await Future<void>.delayed(Duration.zero);
    expect(cacheReads, 0);
    closing.complete();
    await restoring;
    expect(cacheReads, 1);
    f.nativeFiles.onCloseScope = null;
    await f.coordinator.request('documents.importDirectory');
    final openings = f.calls
        .where((call) => call.$1 == 'local.scope.open')
        .toList();
    expect(openings, hasLength(2));
    expect(openings[0].$2['key'], openings[1].$2['key']);
    expect(openings[0].$2['key'], '/cache/documents');
    final recoveryClosed = f.calls.indexWhere(
      (call) => call.$1 == 'local.scope.close',
    );
    final picker = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.picker',
    );
    expect(recoveryClosed, lessThan(picker));
    await f.coordinator.dispose();
  });

  test('恢复关闭失败阻止读取，重试保留原 scope 而不是遗弃它', () async {
    final f = Fixture();
    var fails = true;
    f.nativeFiles.onCloseScope = (_) async {
      if (fails) {
        throw const LocalFileException(
          LocalFileErrorCode.cleanupUnconfirmed,
          '仍有旧 worker。',
        );
      }
    };
    final recovery = DocumentScopeRecovery(
      files: f.files,
      platform: f.platform,
    );
    var cacheReads = 0;
    Future<void> restore() async {
      await recovery.recover();
      cacheReads++;
    }

    await expectLater(restore(), throwsA(isA<LocalFileException>()));
    expect(cacheReads, 0);
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.open'),
      hasLength(1),
    );
    fails = false;
    await restore();
    expect(cacheReads, 1);
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.open'),
      hasLength(1),
    );
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.close'),
      hasLength(2),
    );
    final closes = f.calls
        .where((call) => call.$1 == 'local.scope.close')
        .toList();
    expect(closes[0].$2['scope'], closes[1].$2['scope']);
  });

  test('同一目录的后续文档操作使用稳定 scope key 回收旧代次', () async {
    final f = Fixture()..selected = ['root'];
    f.node('root', 'Empty', directory: true);
    await f.coordinator.request('documents.importDirectory');
    await f.coordinator.request('documents.importDirectory');
    final openings = f.calls.where((call) => call.$1 == 'local.scope.open');
    expect(openings, hasLength(2));
    expect(
      openings.map((call) => call.$2['key']),
      everyElement('/cache/documents'),
    );
    await f.coordinator.dispose();
  });

  test('复制与 scope 都未确认清理时保留原始 PFD，关闭可重试', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'data.txt');
    var fails = true;
    f.nativeFiles.onRunCopy = (_) async =>
        throw const LocalFileException(LocalFileErrorCode.io, '复制失败。');
    Future<void> unconfirmed(String _) async {
      if (fails) {
        throw const LocalFileException(
          LocalFileErrorCode.cleanupUnconfirmed,
          '复制仍可能在运行。',
        );
      }
    }

    f.nativeFiles.onCloseCopy = unconfirmed;
    f.nativeFiles.onCloseScope = unconfirmed;
    await expectLater(
      f.coordinator.request('documents.importFiles'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'document_cleanup_unconfirmed',
        ),
      ),
    );
    expect(f.nativeFiles.copies, hasLength(1));
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.releaseFd'),
      isEmpty,
    );
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.release'),
      isEmpty,
    );
    fails = false;
    await f.coordinator.dispose();
    expect(f.nativeFiles.copies, isEmpty);
    final closed = f.calls.indexWhere((call) => call.$1 == 'local.copy.close');
    final cancelled = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.cancel',
    );
    expect(closed, lessThan(cancelled));
    expect(f.calls.last.$1, 'documents.platform.release');
  });

  test('取消先于 typed 工厂返回时不创建 scope、不启动选择器', () async {
    final f = Fixture();
    final factory = Completer<LocalFiles>();
    final entered = Completer<void>();
    final coordinator = DocumentsCoordinator(
      files: () {
        entered.complete();
        return factory.future;
      },
      platform: f.platform,
    );
    final job = coordinator.request('documents.importFiles', {
      'operationId': 'early',
    });
    await entered.future;
    var cancelled = false;
    final cancelling = coordinator
        .request('documents.cancel', {'operationId': 'early'})
        .then((_) => cancelled = true);
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isFalse);
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.release'),
      isEmpty,
    );
    factory.complete(f.localFiles);
    await cancelling;
    expect((await job)['status'], 'cancelled');
    expect(f.calls.where((call) => call.$1 == 'local.scope.open'), isEmpty);
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.picker'),
      isEmpty,
    );
    await coordinator.dispose();
  });

  test('scope 登记迟到时先关闭真实 scope 再释放平台 owner', () async {
    final f = Fixture();
    final opening = Completer<String>();
    final entered = Completer<void>();
    f.nativeFiles.onOpenScope = (_) {
      entered.complete();
      return opening.future;
    };
    final job = f.coordinator.request('documents.importFiles', {
      'operationId': 'late-scope',
    });
    await entered.future;
    final cancelling = f.coordinator.request('documents.cancel', {
      'operationId': 'late-scope',
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.cancel'),
      isEmpty,
    );
    opening.complete('late-scope');
    await cancelling;
    expect((await job)['status'], 'cancelled');
    final close = f.calls.indexWhere((call) => call.$1 == 'local.scope.close');
    final cancel = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.cancel',
    );
    final release = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.release',
    );
    expect(close, lessThan(cancel));
    expect(cancel, lessThan(release));
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.picker'),
      isEmpty,
    );
    await f.coordinator.dispose();
  });

  test('复制登记迟到也须回收后才释放 PFD，不能开始已取消复制', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'data.txt');
    final creating = Completer<String>();
    final entered = Completer<void>();
    f.nativeFiles.onCreateCopy = (_, request) {
      entered.complete();
      return creating.future;
    };
    var ran = false;
    f.nativeFiles.onRunCopy = (_) async {
      ran = true;
      return copied(3);
    };
    final job = f.coordinator.request('documents.importFiles', {
      'operationId': 'late-copy',
    });
    await entered.future;
    final cancelling = f.coordinator.request('documents.cancel', {
      'operationId': 'late-copy',
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.releaseFd'),
      isEmpty,
    );
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.cancel'),
      isEmpty,
    );
    creating.complete('late-copy');
    await cancelling;
    expect((await job)['status'], 'cancelled');
    expect(ran, isFalse);
    expect(f.nativeFiles.copies, isEmpty);
    final closed = f.calls.indexWhere((call) => call.$1 == 'local.copy.close');
    final released = f.calls.indexWhere(
      (call) => call.$1 == 'documents.platform.releaseFd',
    );
    expect(closed, lessThan(released));
    await f.coordinator.dispose();
  });

  test('dispose 等待在途复制和平台最终释放，不能提前复用协调器', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'data.txt');
    final work = Completer<LocalFileCopyResult>();
    final entered = Completer<void>();
    f.nativeFiles.onRunCopy = (_) {
      entered.complete();
      return work.future;
    };
    final job = f.coordinator.request('documents.importFiles', {
      'operationId': 'disposing',
    });
    await entered.future;
    var disposed = false;
    final disposing = f.coordinator.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.releaseFd'),
      isEmpty,
    );
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.cancel'),
      isEmpty,
    );
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.release'),
      isEmpty,
    );
    work.complete(copied(3));
    await disposing;
    expect((await job)['status'], 'cancelled');
    expect(f.nativeFiles.copies, isEmpty);
    expect(f.calls.last.$1, 'documents.platform.release');
    await expectLater(
      f.coordinator.request('documents.importFiles'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
  });

  test('scope 关闭失败保留 owner，显式重试前不释放平台或接受新请求', () async {
    final f = Fixture()..selected = ['root'];
    f.node('root', 'Empty', directory: true);
    var fails = true;
    f.nativeFiles.onCloseScope = (_) async {
      if (fails) {
        throw const LocalFileException(
          LocalFileErrorCode.cleanupUnconfirmed,
          '尚未排空。',
        );
      }
    };
    await expectLater(
      f.coordinator.request('documents.importDirectory', {
        'operationId': 'cleanup',
      }),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'document_cleanup_unconfirmed',
        ),
      ),
    );
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.release'),
      isEmpty,
    );
    await expectLater(
      f.coordinator.request('documents.importFiles'),
      throwsA(
        isA<ApplicationCommandException>().having(
          (e) => e.code,
          'code',
          'documents_busy',
        ),
      ),
    );
    fails = false;
    await f.coordinator.dispose();
    expect(
      f.calls.where((call) => call.$1 == 'local.scope.close'),
      hasLength(2),
    );
    expect(f.calls.last.$1, 'documents.platform.release');
  });

  test('应用字节和选择预算通过 typed 限额生效，不查询核心限额', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'data.txt');
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: f.platform,
      limits: const DocumentLimits(maxBytes: 2),
    );
    final response = await coordinator.request('documents.importFiles');
    expect(response['status'], 'partial');
    expect(
      (response['errors'] as List).single,
      containsPair('code', 'byte_limit'),
    );
    expect(f.calls.where((call) => call.$1 == 'local.commit'), isEmpty);
    await coordinator.dispose();
    final selection = Fixture()..selected = ['one', 'two'];
    final limited = DocumentsCoordinator(
      files: selection.files,
      platform: selection.platform,
      limits: const DocumentLimits(maxSelected: 1),
    );
    final rejected = await limited.request('documents.importFiles');
    expect(
      (rejected['errors'] as List).single,
      containsPair('code', 'selection_limit'),
    );
    expect(selection.calls.where((call) => call.$1 == 'local.copy'), isEmpty);
    await limited.dispose();
  });
  for (final applyToRemaining in [false, true]) {
    testWidgets(
      'skip applies ${applyToRemaining ? 'through this save only' : 'to one conflict only'}',
      (tester) async {
        final f = Fixture()..selected = ['parent'];
        f.node('parent', 'Target', directory: true);
        f.local['/cache/source'] = {'kind': 'directory'};
        final events = <DocumentsJson>[];
        final coordinator = DocumentsCoordinator(
          files: () async {
            f.nativeFiles.onList = (path, maxEntries) async => LocalFileList(
              identity: identity({'kind': 'directory'}),
              entries: [
                for (final name in ['one', 'two'])
                  LocalFileEntry(
                    name: utf8.encode(name),
                    identity: identity({'kind': 'directory'}),
                  ),
              ],
            );
            return f.localFiles;
          },
          platform: (command, params) async {
            final result = await f.platform(command, params);
            if (command == 'documents.platform.create' &&
                params['name'] == 'Tree') {
              // 新根目录出现后，提供方写入者创建同名子项；两者均属于外部文件系统冲突。
              for (final name in ['one', 'two']) {
                f.node(name, name, directory: true);
              }
              f.children[result['handle'] as String] = ['one', 'two'];
            }
            return result;
          },
          onConflictChanged: events.add,
        );
        f.local['/cache/source/one'] = {'kind': 'directory'};
        f.local['/cache/source/two'] = {'kind': 'directory'};
        final job = coordinator.request('documents.export', {
          'operationId': 'batch',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        });
        await tester.pump();
        final first = events.last['pending'] as DocumentsJson;
        expect(first['name'], 'one');
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'batch',
          'conflictId': first['conflictId'],
          'choice': 'skip',
          'applyToRemaining': applyToRemaining,
        });
        await tester.pump();
        if (!applyToRemaining) {
          final second = events.last['pending'] as DocumentsJson;
          expect(second['name'], 'two');
          expect(
            await coordinator.request('documents.conflict.resolve', {
              'operationId': 'batch',
              'conflictId': first['conflictId'],
              'choice': 'cancel',
            }),
            {'resolved': false},
          );
          await coordinator.request('documents.conflict.resolve', {
            'operationId': 'batch',
            'conflictId': second['conflictId'],
            'choice': 'skip',
          });
        }
        final result = await job;
        expect(result['status'], 'partial');
        expect(result['skipped'], 2);
        expect(
          events.where((event) => event['pending'] != null),
          hasLength(applyToRemaining ? 1 : 2),
        );
        final next = coordinator.request('documents.export', {
          'operationId': 'next-batch',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        });
        await tester.pump();
        expect(
          (events.last['pending'] as DocumentsJson)['operationId'],
          'next-batch',
        );
        await coordinator.request('documents.cancel', {
          'operationId': 'next-batch',
        });
        expect((await next)['status'], 'cancelled');
        await coordinator.dispose();
      },
    );
  }

  testWidgets(
    'an unanswered shared conflict expires and cannot hold the next save',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final coordinator = DocumentsCoordinator(
        files: f.files,
        limits: const DocumentLimits(timeout: Duration(milliseconds: 20)),
        platform: f.platform,
      );
      final job = coordinator.request('documents.export', {
        'operationId': 'timeout-conflict',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await tester.pump();
      final pending =
          (await coordinator.request('documents.conflict.get', {
                'operationId': 'timeout-conflict',
              }))['pending']
              as DocumentsJson;
      await expectLater(
        coordinator.request('documents.conflict.resolve', {
          ...pending,
          'choice': 'replace',
        }),
        throwsA(isA<ApplicationCommandException>()),
      );
      await tester.pump(const Duration(milliseconds: 21));
      final result = await job;
      expect(result['status'], 'partial');
      expect(
        (result['errors'] as List).single,
        containsPair('code', 'timeout'),
      );
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'timeout-conflict',
        }))['pending'],
        isNull,
      );
      expect(
        await coordinator.request('documents.conflict.resolve', {
          ...pending,
          'choice': 'keepBoth',
        }),
        {'resolved': false},
      );
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.create'),
        isEmpty,
      );
      f.children['parent'] = [];
      expect(
        (await coordinator.request('documents.export', {
          'operationId': 'healthy-next',
          'localPath': '/cache/source',
          'kind': 'directory',
          'name': 'Tree',
        }))['status'],
        'saved',
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'conflict cancellation clears its event and stale decisions cannot resolve another operation',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final events = <DocumentsJson>[];
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: f.platform,
        onConflictChanged: events.add,
      );
      Future<DocumentsJson> start(String id) =>
          coordinator.request('documents.export', {
            'operationId': id,
            'localPath': '/cache/source',
            'kind': 'directory',
            'name': 'Tree',
          });
      final oldJob = start('old-operation');
      await tester.pump();
      final oldPending = events.single['pending'] as DocumentsJson;
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'other-device-operation',
        }))['pending'],
        isNull,
      );
      await coordinator.request('documents.cancel', {
        'operationId': 'old-operation',
      });
      expect((await oldJob)['status'], 'cancelled');
      expect(events.last, {'operationId': 'old-operation', 'pending': null});
      final newJob = start('new-operation');
      await tester.pump();
      final current = events.last['pending'] as DocumentsJson;
      expect(
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'old-operation',
          'conflictId': oldPending['conflictId'],
          'choice': 'keepBoth',
        }),
        {'resolved': false},
      );
      expect(
        await coordinator.request('documents.conflict.resolve', {
          'operationId': 'new-operation',
          'conflictId': oldPending['conflictId'],
          'choice': 'cancel',
        }),
        {'resolved': false},
      );
      expect(
        (await coordinator.request('documents.conflict.get', {
          'operationId': 'new-operation',
          'conflictId': current['conflictId'],
        }))['pending'],
        current,
      );
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        isEmpty,
      );
      await coordinator.request('documents.conflict.resolve', {
        'operationId': 'new-operation',
        'conflictId': current['conflictId'],
        'choice': 'cancel',
      });
      expect((await newJob)['status'], 'cancelled');
      await coordinator.dispose();
    },
  );
  test(
    'a rejected source before the picker is failed without a partial save',
    () async {
      final f = Fixture();
      final coordinator = DocumentsCoordinator(
        platform: f.platform,
        files: () async {
          f.nativeFiles.onStat = (path) async => throw const LocalFileException(
            LocalFileErrorCode.sourceChanged,
            '原文件已变化',
          );
          return f.localFiles;
        },
      );
      final result = await coordinator.request('documents.export', {
        'operationId': 'preflight-rejected',
        'localPath': '/cache/outgoing/original',
        'name': 'original',
        'kind': 'file',
      });
      expect(result['status'], 'failed');
      expect(result['files'], 0);
      expect(result['bytes'], 0);
      expect(result['partialDestinationPossible'], false);
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.picker'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );
  testWidgets(
    'a never responding metadata query times out and releases the operation',
    (tester) async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      final pending = Completer<DocumentsJson>();
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) {
          if (command == 'documents.platform.metadata') return pending.future;
          return f.platform(command, params);
        },
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importDirectory', {
            'operationId': 'metadata-timeout',
          })
          .then((value) {
            result = value;
          });
      await tester.pump();
      await tester.pump(const Duration(seconds: 121));
      await tester.pump();
      expect(
        result,
        isNotNull,
        reason: 'Metadata must use the bounded platform wait.',
      );
      expect(result!['status'], 'partial');
      expect(
        (result!['errors'] as List<Object?>).single,
        containsPair('code', 'timeout'),
      );
      await job;
      f.selected = [];
      final next = await coordinator.request('documents.importFiles', {
        'operationId': 'after-timeout',
      });
      expect(next['status'], 'partial');
      expect(
        (next['errors'] as List<Object?>).single,
        containsPair('code', 'invalid_uri'),
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'shared cancellation releases a picker without waiting for its native reply',
    (tester) async {
      final f = Fixture();
      f.node('late', 'late.txt');
      final first = Completer<DocumentsJson>();
      final second = Completer<DocumentsJson>();
      var picks = 0;
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) {
          if (command == 'documents.platform.picker') {
            return ++picks == 1 ? first.future : second.future;
          }
          return f.platform(command, params);
        },
      );
      DocumentsJson? firstResult, secondResult;
      final oldJob = coordinator
          .request('documents.importFiles', {'operationId': 'old'})
          .then((value) {
            firstResult = value;
          });
      await tester.pump();
      await coordinator.request('documents.cancel', {'operationId': 'old'});
      await tester.pump();
      expect(firstResult?['status'], 'cancelled');
      await oldJob;
      final newJob = coordinator
          .request('documents.importFiles', {'operationId': 'new'})
          .then((value) {
            secondResult = value;
          });
      await tester.pump();
      first.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'late'},
        ],
      });
      await tester.pump(const Duration(seconds: 121));
      expect(secondResult, isNull);
      expect(f.calls.where((call) => call.$1 == 'local.copy'), isEmpty);
      expect(
        f.calls
            .where((call) => call.$1 == 'documents.platform.cancel')
            .map((call) => call.$2['operationId']),
        ['old'],
      );
      await coordinator.request('documents.cancel', {'operationId': 'new'});
      await tester.pump();
      await newJob;
      expect(secondResult?['status'], 'cancelled');
      second.completeError(
        const ApplicationCommandException(
          'late_provider',
          'late provider failure',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await coordinator.dispose();
    },
  );

  testWidgets(
    'metadata cancellation ignores its late provider error and cannot affect the next selection',
    (tester) async {
      final f = Fixture()..selected = ['file'];
      f.node('file', 'data.txt');
      final pending = Completer<DocumentsJson>();
      var blocked = true;
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) {
          if (blocked && command == 'documents.platform.metadata') {
            return pending.future;
          }
          return f.platform(command, params);
        },
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importFiles', {'operationId': 'cancel-meta'})
          .then((value) {
            result = value;
          });
      await tester.pump();
      await coordinator.request('documents.cancel', {
        'operationId': 'cancel-meta',
      });
      await tester.pump();
      expect(result?['status'], 'cancelled');
      await job;
      blocked = false;
      final next = await coordinator.request('documents.importFiles', {
        'operationId': 'healthy',
      });
      expect(next['status'], 'imported');
      pending.completeError(
        const ApplicationCommandException('late_metadata', 'late response'),
      );
      await tester.pump(const Duration(seconds: 121));
      expect(tester.takeException(), isNull);
      expect(
        f.calls
            .where((call) => call.$1 == 'documents.platform.cancel')
            .map((call) => call.$2['operationId']),
        ['cancel-meta'],
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'disposal releases a picker that never acknowledges cancellation',
    (tester) async {
      final f = Fixture();
      final pending = Completer<DocumentsJson>();
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) => command == 'documents.platform.picker'
            ? pending.future
            : f.platform(command, params),
      );
      DocumentsJson? result;
      final job = coordinator
          .request('documents.importFiles', {'operationId': 'disposed'})
          .then((value) {
            result = value;
          });
      await tester.pump();
      await coordinator.dispose();
      await tester.pump();
      expect(result?['status'], 'cancelled');
      await job;
      pending.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'late'},
        ],
      });
      await tester.pump();
      expect(f.calls.where((call) => call.$1 == 'local.copy'), isEmpty);
    },
  );

  test(
    'a completed save confirms provider success before reporting saved',
    () async {
      final f = Fixture()..selected = ['file'];
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) {
          if (command == 'documents.platform.releaseFd' &&
              params['outcome'] != 'success') {
            throw const ApplicationCommandException(
              'provider_incomplete',
              'provider did not receive successful completion',
            );
          }
          return f.platform(command, params);
        },
      );
      final result = await coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'saved');
      expect(result['files'], 1);
      expect(result['uri'], 'content://fixture/file');
      expect(result['bytes'], 3);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.releaseFd'),
        hasLength(1),
      );
      expect(
        f.calls.singleWhere((c) => c.$1 == 'local.copy').$2['request']
            as LocalFileCopyRequest,
        isA<LocalFileCopyRequest>().having(
          (request) => request.expectedSource?.size,
          'source size',
          BigInt.from(3),
        ),
      );
      await coordinator.dispose();
    },
  );

  test(
    'a failed write aborts its provider lease and preserves the write error',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final coordinator = DocumentsCoordinator(
        files: () async {
          f.nativeFiles.onRunCopy = (request) async {
            f.nodes['file']!['size'] = 1;
            throw const LocalFileException(
              LocalFileErrorCode.io,
              'provider stopped',
              bytesCopied: 1,
              partialDestinationPossible: true,
            );
          };
          return f.localFiles;
        },
        platform: f.platform,
      );
      final result = await coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'partial');
      expect(result['files'], 0);
      expect(result['bytes'], 1);
      expect(result['partialDestinationPossible'], isTrue);
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'document_io'),
      );
      expect(
        f.calls
            .singleWhere((call) => call.$1 == 'documents.platform.releaseFd')
            .$2['outcome'],
        'abort',
      );
      expect(f.calls.where((call) => call.$1 == 'local.copy'), hasLength(1));
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.delete'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );

  test(
    'cancelling a write retains possible output without reporting it saved',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final copying = Completer<void>();
      final copied = Completer<LocalFileCopyResult>();
      final coordinator = DocumentsCoordinator(
        files: () async {
          f.nativeFiles.onRunCopy = (request) {
            copying.complete();
            return copied.future;
          };
          return f.localFiles;
        },
        platform: f.platform,
      );
      final job = coordinator.request('documents.export', {
        'operationId': 'cancel-write',
        'localPath': '/cache/source',
        'kind': 'file',
      });
      await copying.future;
      final cancelling = coordinator.request('documents.cancel', {
        'operationId': 'cancel-write',
      });
      // 取消先于复制回执到达时，字节可能已发送至提供方，但保存尚未确认。
      f.nodes['file']!['size'] = 3;
      copied.complete(
        LocalFileCopyResult(
          bytes: 3,
          identity: identity({'kind': 'file', 'size': 3}),
          sourceIdentity: identity({'kind': 'file', 'size': 3}),
        ),
      );
      await cancelling;
      final result = await job;
      expect(result['status'], 'cancelled');
      expect(result['files'], 0);
      expect(result['bytes'], 3);
      expect(result['partialDestinationPossible'], isTrue);
      expect(result['cacheRetained'], isTrue);
      expect(result['uri'], 'content://fixture/file');
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'cancelled'),
      );
      expect(
        f.calls
            .singleWhere((call) => call.$1 == 'documents.platform.releaseFd')
            .$2['outcome'],
        'abort',
      );
      expect(f.calls.where((call) => call.$1 == 'local.copy'), hasLength(1));
      expect(
        f.calls.where((call) => call.$1 == 'documents.platform.delete'),
        isEmpty,
      );
      await coordinator.dispose();
    },
  );

  test('a missing provider lease leaves the save result unknown', () async {
    final f = Fixture()..selected = ['file'];
    f.node('file', 'saved.txt', size: 0);
    f.local['/cache/source'] = {'kind': 'file', 'size': 3};
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: (command, params) async {
        if (command == 'documents.platform.releaseFd') {
          return {'released': false};
        }
        return f.platform(command, params);
      },
    );
    final result = await coordinator.request('documents.export', {
      'localPath': '/cache/source',
      'kind': 'file',
    });
    expect(result['status'], 'resultUnknown');
    expect(result['files'], 0);
    expect(result['partialDestinationPossible'], isTrue);
    expect(result['cacheRetained'], isTrue);
    expect(result['uri'], 'content://fixture/file');
    expect(f.calls.where((call) => call.$1 == 'local.copy'), hasLength(1));
    expect(
      f.calls.where((call) => call.$1 == 'documents.platform.delete'),
      isEmpty,
    );
    await coordinator.dispose();
  });

  test(
    'provider close failure leaves write receipt unknown and never retries',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'saved.txt', size: 0);
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['files'], 0);
      expect(f.calls.where((c) => c.$1 == 'local.copy'), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );
  test(
    'read descriptor close failure removes only its unpublished cache part',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..failClose = true;
      f.node('file', 'data.txt');
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['items'], isEmpty);
      expect(f.calls.where((c) => c.$1 == 'local.commit'), isEmpty);
      expect(f.calls.where((c) => c.$1 == 'local.part.remove'), hasLength(1));
    },
  );

  test(
    'exporting an empty source tree creates its real empty destination',
    () async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.local['/cache/source'] = {'kind': 'directory'};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Empty',
      });
      expect(result['status'], 'saved');
      expect(result['directories'], 1);
      expect(result['files'], 0);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'existing provider names wait for a shared decision and keep both preserves originals',
    (tester) async {
      final f = Fixture()..selected = ['parent'];
      f.node('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final job = f.coordinator.request('documents.export', {
        'operationId': 'conflicting-tree',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await tester.pump();
      final pending =
          (await f.coordinator.request('documents.conflict.get', {
                'operationId': 'conflicting-tree',
              }))['pending']
              as DocumentsJson;
      expect(pending['name'], 'Tree');
      expect(pending['choices'], ['keepBoth', 'skip', 'cancel']);
      expect(pending['replacementSupported'], false);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        isEmpty,
      );
      expect(
        await f.coordinator.request('documents.conflict.resolve', {
          'operationId': 'conflicting-tree',
          'conflictId': pending['conflictId'],
          'choice': 'keepBoth',
        }),
        containsPair('resolved', true),
      );
      final result = await job;
      expect(result['status'], 'saved');
      expect(f.nodes['old']!['name'], 'Tree');
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.conflict'),
        isEmpty,
      );
      expect((result['renamed'] as List<Object?>), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );

  test(
    'shared document names preserve Unicode and reject path escapes',
    () async {
      for (final name in [
        '',
        '.',
        '..',
        '../outside',
        'nested/file',
        r'nested\file',
        'nul\u0000name',
        'line\nname',
        'a' * 256,
      ]) {
        final f = Fixture()..selected = ['bad'];
        f.node('bad', name);
        final response = await f.coordinator.request('documents.importFiles');
        expect(response['status'], 'partial', reason: name);
        expect(
          f.calls.where((c) => c.$1 == 'local.copy'),
          isEmpty,
          reason: name,
        );
      }
      for (final name in [
        '中文 empty',
        'file.bin',
        '.hidden',
        'name with spaces',
      ]) {
        final f = Fixture()..selected = ['good'];
        f.node('good', name);
        expect(
          (await f.coordinator.request('documents.importFiles'))['status'],
          'imported',
        );
      }
    },
  );

  test(
    'shared import plans files and empty directories; all owned FDs release',
    () async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      f.node('empty', 'Empty', directory: true);
      f.node('file', 'data.txt');
      f.children['root'] = ['empty', 'file'];
      final result = await f.coordinator.request('documents.importDirectory', {
        'operationId': 'tree',
      });
      expect(result['status'], 'imported');
      expect(result['directories'], 2);
      expect(result['files'], 1);
      expect(result['bytes'], 3);
      expect(f.local.keys.any((path) => path.endsWith('/Tree/Empty')), isTrue);
      expect(
        f.calls
            .where((c) => c.$1 == 'documents.platform.releaseFd')
            .single
            .$2['fdLeaseId'],
        'lease-file',
      );
      expect(f.calls.last.$1, 'documents.platform.release');
    },
  );
  test(
    'provider source changes never publish an unverified cache file',
    () async {
      final f = Fixture()
        ..selected = ['file']
        ..mutateSource = true;
      f.node('file', 'data.txt');
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['files'], 0);
      expect(result['items'], isEmpty);
      expect(f.calls.where((c) => c.$1 == 'local.commit'), isEmpty);
      expect(f.calls.where((c) => c.$1 == 'local.part.remove'), hasLength(1));
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.releaseFd'),
        hasLength(1),
      );
    },
  );
  test(
    'duplicate provider names remain partial and are never silently merged',
    () async {
      final f = Fixture()..selected = ['root'];
      f.node('root', 'Tree', directory: true);
      f.node('a', 'same');
      f.node('b', 'same');
      f.children['root'] = ['a', 'b'];
      final result = await f.coordinator.request('documents.importDirectory');
      expect(result['status'], 'partial');
      expect(result['files'], 1);
      expect(
        (result['errors'] as List<Object?>).single,
        containsPair('code', 'duplicate_name'),
      );
    },
  );
  test(
    'each selected same-name file keeps its independent cache root',
    () async {
      final f = Fixture()..selected = ['a', 'b'];
      f.node('a', 'same');
      f.node('b', 'same');
      final result = await f.coordinator.request('documents.importFiles');
      final items = result['items'] as List<DocumentsJson>;
      expect(result['status'], 'imported');
      expect(items, hasLength(2));
      expect(items[0]['localPath'], isNot(items[1]['localPath']));
    },
  );
  test(
    'cancellation is matched to its owner and late picker receipts cannot copy',
    () async {
      final f = Fixture()..picker = Completer<DocumentsJson>();
      final job = f.coordinator.request('documents.importFiles', {
        'operationId': 'owned',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        (await f.coordinator.request('documents.cancel', {
          'operationId': 'other',
        }))['cancelled'],
        isFalse,
      );
      expect(
        (await f.coordinator.request('documents.cancel', {
          'operationId': 'owned',
        }))['cancelled'],
        isTrue,
      );
      expect((await job)['status'], 'cancelled');
      expect(f.calls.where((c) => c.$1 == 'local.copy'), isEmpty);
      expect(
        f.calls
            .where((c) => c.$1 == 'documents.platform.cancel')
            .single
            .$2['operationId'],
        'owned',
      );
      await expectLater(
        f.coordinator.request('documents.importFiles', {
          'operationId': 'owned',
        }),
        throwsA(isA<ApplicationCommandException>()),
      );
    },
  );
  test(
    'uncertain provider create never retries or deletes an existing document',
    () async {
      final f = Fixture()
        ..selected = ['parent']
        ..loseCreate = true;
      f.node('parent', 'Destination', directory: true);
      f.local['/cache/source'] = {'kind': 'directory'};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'name': 'Tree',
        'kind': 'directory',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['partialDestinationPossible'], isTrue);
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.create'),
        hasLength(1),
      );
      expect(
        f.calls.where((c) => c.$1 == 'documents.platform.delete'),
        isEmpty,
      );
    },
  );
}
