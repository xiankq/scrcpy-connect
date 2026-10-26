import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/platform/application_platform.dart';
import 'package:scrcpy_connect/stores/files/documents_coordinator.dart';
import 'package:scrcpy_connect/stores/files/document_sources.dart';
import 'package:scrcpy_connect/services/files/document_scope_recovery.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';

// 虚拟时钟不会推进可信根解析的真实文件系统回执。等待实际阶段，同时
// 继续由 pump 驱动协调器，避免把准入耗时误算成 provider/conflict 超时。
Future<void> documentStage(WidgetTester tester, bool Function() entered) async {
  final elapsed = Stopwatch()..start();
  await tester.runAsync(() async {
    while (!entered()) {
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw StateError('文档操作未进入预期阶段。');
      }
      await Future<void>(() {});
      await tester.pump();
    }
  });
}

Future<DocumentsJson> documentResult(
  WidgetTester tester,
  Future<DocumentsJson> request,
) async {
  var complete = false;
  final result = request.whenComplete(() => complete = true);
  await documentStage(tester, () => complete);
  return result;
}

Matcher documentFailure(String code) => throwsA(
  isA<ApplicationCommandException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

class Fixture {
  Fixture({this.cacheDirectory = '/cache', this.sources});
  final String cacheDirectory;
  final DocumentSources? sources;
  bool ownerReady = true;

  void mockPlatformChannel() {
    const channel = MethodChannel('dev.scrcpyconnect/platform');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final response = await platform(
        call.method,
        Map<String, dynamic>.from(call.arguments as Map),
      );
      return {
        ...response,
        if (call.method == 'documents.platform.environment')
          'ownerReady': ownerReady,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  ApplicationPlatform applicationPlatform() => ApplicationPlatform(
    applicationRequest: (_, _) async => {},
    localFiles: files,
    emit: (_) {},
    isDisposed: () => false,
  );

  final calls = <(String, DocumentsJson)>[];
  Iterable<(String, DocumentsJson)> callsFor(String command) =>
      calls.where((call) => call.$1 == command);

  final nodes = <String, DocumentsJson>{};
  final children = <String, List<String>>{};
  final local = <String, DocumentsJson>{};
  final conflicts = <DocumentsJson>[];
  final pickerEntered = Completer<void>();
  List<String> selected = [];
  String choice = 'keepBoth';
  String ownerLeaseId = 'fixture-owner';
  Future<DocumentsJson> Function(DocumentsJson)? onClaim;
  bool mutateSource = false, loseCreate = false, failClose = false;
  Completer<DocumentsJson>? picker;
  void select(String id, String name, {bool directory = false, int size = 3}) {
    selected = [id];
    node(id, name, directory: directory, size: size);
  }

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
    sources: sources,
    onConflictChanged: conflicts.add,
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
        return {'cacheDirectory': cacheDirectory, 'ownerLeaseId': ownerLeaseId};
      case 'documents.platform.claim':
        if (params['expectedOwnerLeaseId'] != ownerLeaseId &&
            params['ownerLeaseId'] != ownerLeaseId) {
          throw const ApplicationCommandException('cancelled', '旧平台代次。');
        }
        ownerLeaseId = params['ownerLeaseId'] as String;
        ownerReady = true;
        if (onClaim case final hook?) return hook(params);
        return {'claimed': true, 'ownerLeaseId': ownerLeaseId};
      case 'documents.platform.release':
        return {'released': true};
      case 'documents.platform.picker':
        if (!pickerEntered.isCompleted) pickerEntered.complete();
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
  Future<void> Function(String)? onMkdir;
  Future<void> Function(String)? onCommit;
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
    await onMkdir?.call(path(bytes));
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
    await onCommit?.call(path(destination));
    committed.add(copyId);
    return expectedIdentity;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('managed imports drain before publication and each copy receives the shared remaining budget', () async {
    final cache = await Directory.systemTemp.createTemp('documents-managed-');
    addTearDown(() => cache.delete(recursive: true));
    final sources = await DocumentSources.open(
      cacheDirectory: cache,
      totalBytes: 5,
    );
    final f = Fixture(cacheDirectory: cache.path, sources: sources);
    f.node('root', 'Docs', directory: true);
    f.node('a', 'a.txt');
    f.selected = ['root'];
    f.children['root'] = ['a'];
    f.nativeFiles.onMkdir = (path) async {
      await Directory(path).create();
    };
    f.nativeFiles.onCommit = (path) async {
      await File(path).writeAsBytes([1, 2, 3]);
    };
    f.nativeFiles.onCloseScope = (_) async {
      expect((await sources.store.sourcePaths).length, lessThanOrEqualTo(1));
    };
    final first = await f.coordinator.request('documents.importDirectory');
    expect(first['status'], 'imported');
    expect(first['managedSourceId'], startsWith(DocumentSources.prefix));
    expect(await sources.store.sourcePaths, hasLength(1));
    final second = await f.coordinator.request('documents.importDirectory');
    expect(second['status'], 'partial');
    expect((second['errors'] as List).single['code'], 'byte_limit');
    expect(
      f
          .callsFor('local.copy')
          .map((call) => (call.$2['request'] as LocalFileCopyRequest).maxBytes),
      [5, 2],
    );
    expect(await Directory(first['localPath'] as String).exists(), isTrue);
    await f.coordinator.request('documents.cancel', {
      'managedSourceId': first['managedSourceId'],
    });
    await f.coordinator.request('documents.cancel', {
      'managedSourceId': second['managedSourceId'],
    });
    expect(await sources.store.sourcePaths, isEmpty);
    await f.coordinator.dispose();
  });

  test('同 Dart 会话换 Activity 后精确收尾旧操作，再排空接管后启动新选择器', () async {
    final f = Fixture()..picker = Completer<DocumentsJson>();
    final oldPicker = Completer<void>();
    f.mockPlatformChannel();
    final platform = f.applicationPlatform();
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
    f.ownerReady = false;
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
    final keys = f.callsFor('local.scope.open').map((call) => call.$2['key']);
    expect(keys, everyElement('/cache/documents'));
    expect(keys, hasLength(3));
    await coordinator.dispose();
    await platform.dispose();
  });

  test('claim 已提交但回执丢失时先确认同候选，再次换代仍重新排空 scope', () async {
    final f = Fixture()..select('root', 'Empty', directory: true);
    f.ownerReady = false;
    var attempts = 0;
    final confirming = Completer<void>();
    final confirm = Completer<void>();
    f.onClaim = (_) async {
      f.ownerReady = true;
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
    f.mockPlatformChannel();
    final platform = f.applicationPlatform();
    final coordinator = DocumentsCoordinator(
      files: f.files,
      platform: platform.request,
    );
    final first = await coordinator.request('documents.importDirectory', {
      'operationId': 'lost-reply',
    });
    expect(first['status'], 'failed');
    expect(f.ownerReady, isTrue);
    // 新实例也必须遵守共享 pending，不能仅查看自己的恢复标记。
    final nextPlatform = f.applicationPlatform();
    final nextCoordinator = DocumentsCoordinator(
      files: f.files,
      platform: nextPlatform.request,
    );
    final second = nextCoordinator.request('documents.importDirectory', {
      'operationId': 'confirmed',
    });
    await confirming.future;
    expect(f.callsFor('documents.platform.picker'), isEmpty);
    final firstClaims = f.callsFor('documents.platform.claim').toList();
    expect(firstClaims, hasLength(2));
    expect(firstClaims[0].$2, firstClaims[1].$2);
    expect(f.callsFor('local.scope.open'), hasLength(1));
    confirm.complete();
    expect((await second)['status'], 'imported');
    final previousEnd = f.calls.length;
    f.ownerReady = false;
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

  LocalFileCopyResult copiedResult(int bytes) => LocalFileCopyResult(
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
    expect(f.callsFor('local.scope.open'), hasLength(1));
    fails = false;
    await recovery.recover();
    final claims = f.callsFor('documents.platform.claim').toList();
    expect(claims, hasLength(2));
    expect(claims[0].$2, claims[1].$2);
    expect(f.callsFor('local.scope.open'), hasLength(1));
  });

  for (final cancelFirst in [false, true]) {
    test('平台 release 未确认后${cancelFirst ? '取消' : '再次操作'}重试清理并恢复准入', () async {
      final f = Fixture()..select('root', 'Empty', directory: true);
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
        coordinator.request('documents.importDirectory', {
          'operationId': 'old',
        }),
        documentFailure('document_cleanup_unconfirmed'),
      );
      await expectLater(
        coordinator.request('documents.importFiles'),
        documentFailure('document_cleanup_unconfirmed'),
      );
      released = true;
      if (cancelFirst) {
        expect(
          await coordinator.request('documents.cancel', {'operationId': 'old'}),
          containsPair('cancelled', true),
        );
      }
      expect(
        (await coordinator.request('documents.importDirectory'))['status'],
        'imported',
      );
      await coordinator.dispose();
    });
  }

  test('恢复栅栏确认 scope 排空前不读取缓存，并与文档操作共用 key', () async {
    final f = Fixture()..select('root', 'Empty', directory: true);
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
    final openings = f.callsFor('local.scope.open').toList();
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
    expect(f.callsFor('local.scope.open'), hasLength(1));
    fails = false;
    await restore();
    expect(cacheReads, 1);
    expect(f.callsFor('local.scope.open'), hasLength(1));
    expect(f.callsFor('local.scope.close'), hasLength(2));
    final closes = f.callsFor('local.scope.close').toList();
    expect(closes[0].$2['scope'], closes[1].$2['scope']);
  });

  test('复制与 scope 都未确认清理时保留原始 PFD，关闭可重试', () async {
    final f = Fixture()..select('file', 'data.txt');
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
      documentFailure('document_cleanup_unconfirmed'),
    );
    expect(f.nativeFiles.copies, hasLength(1));
    expect(f.callsFor('documents.platform.releaseFd'), isEmpty);
    expect(f.callsFor('documents.platform.release'), isEmpty);
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

  test('复制登记迟到也须回收后才释放 PFD，不能开始已取消复制', () async {
    final f = Fixture()..select('file', 'data.txt');
    final creating = Completer<String>();
    final entered = Completer<void>();
    f.nativeFiles.onCreateCopy = (_, request) {
      entered.complete();
      return creating.future;
    };
    var ran = false;
    f.nativeFiles.onRunCopy = (_) async {
      ran = true;
      return copiedResult(3);
    };
    final job = f.coordinator.request('documents.importFiles', {
      'operationId': 'late-copy',
    });
    await entered.future;
    final cancelling = f.coordinator.request('documents.cancel', {
      'operationId': 'late-copy',
    });
    await Future<void>.delayed(Duration.zero);
    expect(f.callsFor('documents.platform.releaseFd'), isEmpty);
    expect(f.callsFor('documents.platform.cancel'), isEmpty);
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

  for (final applyToRemaining in [false, true]) {
    testWidgets(
      'skip applies ${applyToRemaining ? 'through this save only' : 'to one conflict only'}',
      (tester) async {
        final f = Fixture()..select('parent', 'Target', directory: true);
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
        await documentStage(tester, () => events.isNotEmpty);
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
        await documentStage(
          tester,
          () => events.last['pending']?['operationId'] == 'next-batch',
        );
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
      final f = Fixture()..select('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      var conflictEntered = false;
      final coordinator = DocumentsCoordinator(
        files: f.files,
        limits: const DocumentLimits(timeout: Duration(milliseconds: 20)),
        platform: f.platform,
        onConflictChanged: (event) {
          if (event['pending'] != null) conflictEntered = true;
        },
      );
      final job = coordinator.request('documents.export', {
        'operationId': 'timeout-conflict',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await documentStage(tester, () => conflictEntered);
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
      expect(f.callsFor('documents.platform.create'), isEmpty);
      f.children['parent'] = [];
      expect(
        (await documentResult(
          tester,
          coordinator.request('documents.export', {
            'operationId': 'healthy-next',
            'localPath': '/cache/source',
            'kind': 'directory',
            'name': 'Tree',
          }),
        ))['status'],
        'saved',
      );
      await coordinator.dispose();
    },
  );

  testWidgets(
    'conflict cancellation clears its event and stale decisions cannot resolve another operation',
    (tester) async {
      final f = Fixture()..select('parent', 'Target', directory: true);
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
      await documentStage(tester, () => events.isNotEmpty);
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
      await documentStage(
        tester,
        () => events.last['pending']?['operationId'] == 'new-operation',
      );
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
      expect(f.callsFor('documents.platform.create'), isEmpty);
      await coordinator.request('documents.conflict.resolve', {
        'operationId': 'new-operation',
        'conflictId': current['conflictId'],
        'choice': 'cancel',
      });
      expect((await newJob)['status'], 'cancelled');
      await coordinator.dispose();
    },
  );
  testWidgets(
    'a never responding metadata query times out and releases the operation',
    (tester) async {
      final f = Fixture()..select('root', 'Tree', directory: true);
      final pending = Completer<DocumentsJson>();
      var metadataEntered = false;
      final coordinator = DocumentsCoordinator(
        files: f.files,
        platform: (command, params) {
          if (command == 'documents.platform.metadata') {
            metadataEntered = true;
            return pending.future;
          }
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
      await documentStage(tester, () => metadataEntered);
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
      final next = await documentResult(
        tester,
        coordinator.request('documents.importFiles', {
          'operationId': 'after-timeout',
        }),
      );
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
      await documentStage(tester, () => picks == 1);
      await coordinator.request('documents.cancel', {'operationId': 'old'});
      await tester.pump();
      expect(firstResult?['status'], 'cancelled');
      await oldJob;
      final newJob = coordinator
          .request('documents.importFiles', {'operationId': 'new'})
          .then((value) {
            secondResult = value;
          });
      await documentStage(tester, () => picks == 2);
      first.complete({
        'status': 'selected',
        'documents': [
          {'handle': 'late'},
        ],
      });
      await tester.pump(const Duration(seconds: 121));
      expect(secondResult, isNull);
      expect(f.callsFor('local.copy'), isEmpty);
      expect(
        f
            .callsFor('documents.platform.cancel')
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

  test(
    'a completed save confirms provider success before reporting saved',
    () async {
      final f = Fixture()..select('file', 'saved.txt', size: 0);
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
      expect(f.callsFor('documents.platform.releaseFd'), hasLength(1));
      expect(
        f.callsFor('local.copy').single.$2['request'] as LocalFileCopyRequest,
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
        ..select('file', 'saved.txt', size: 0)
        ..failClose = true;
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      f.nativeFiles.onRunCopy = (request) async {
        f.nodes['file']!['size'] = 1;
        throw const LocalFileException(
          LocalFileErrorCode.io,
          'provider stopped',
          bytesCopied: 1,
          partialDestinationPossible: true,
        );
      };
      final coordinator = f.coordinator;
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
        f.callsFor('documents.platform.releaseFd').single.$2['outcome'],
        'abort',
      );
      expect(f.callsFor('local.copy'), hasLength(1));
      expect(f.callsFor('documents.platform.delete'), isEmpty);
      await coordinator.dispose();
    },
  );

  test(
    'cancelling a write retains possible output without reporting it saved',
    () async {
      final f = Fixture()
        ..select('file', 'saved.txt', size: 0)
        ..failClose = true;
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final copying = Completer<void>();
      final copied = Completer<LocalFileCopyResult>();
      f.nativeFiles.onRunCopy = (request) {
        copying.complete();
        return copied.future;
      };
      final coordinator = f.coordinator;
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
      copied.complete(copiedResult(3));
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
        f.callsFor('documents.platform.releaseFd').single.$2['outcome'],
        'abort',
      );
      expect(f.callsFor('local.copy'), hasLength(1));
      expect(f.callsFor('documents.platform.delete'), isEmpty);
      await coordinator.dispose();
    },
  );

  test('a missing provider lease leaves the save result unknown', () async {
    final f = Fixture()..select('file', 'saved.txt', size: 0);
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
    expect(f.callsFor('local.copy'), hasLength(1));
    expect(f.callsFor('documents.platform.delete'), isEmpty);
    await coordinator.dispose();
  });

  test(
    'provider close failure leaves write receipt unknown and never retries',
    () async {
      final f = Fixture()
        ..select('file', 'saved.txt', size: 0)
        ..failClose = true;
      f.local['/cache/source'] = {'kind': 'file', 'size': 3};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'kind': 'file',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['files'], 0);
      expect(f.callsFor('local.copy'), hasLength(1));
      expect(f.callsFor('documents.platform.delete'), isEmpty);
    },
  );
  test(
    'read descriptor close failure removes only its unpublished cache part',
    () async {
      final f = Fixture()
        ..select('file', 'data.txt')
        ..failClose = true;
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['items'], isEmpty);
      expect(f.callsFor('local.commit'), isEmpty);
      expect(f.callsFor('local.part.remove'), hasLength(1));
    },
  );

  testWidgets(
    'existing provider names wait for a shared decision and keep both preserves originals',
    (tester) async {
      final f = Fixture()..select('parent', 'Target', directory: true);
      f.node('old', 'Tree', directory: true);
      f.children['parent'] = ['old'];
      f.local['/cache/source'] = {'kind': 'directory'};
      final job = f.coordinator.request('documents.export', {
        'operationId': 'conflicting-tree',
        'localPath': '/cache/source',
        'kind': 'directory',
        'name': 'Tree',
      });
      await documentStage(tester, () => f.conflicts.isNotEmpty);
      final pending =
          (await f.coordinator.request('documents.conflict.get', {
                'operationId': 'conflicting-tree',
              }))['pending']
              as DocumentsJson;
      expect(pending['name'], 'Tree');
      expect(pending['choices'], ['keepBoth', 'skip', 'cancel']);
      expect(pending['replacementSupported'], false);
      expect(f.callsFor('documents.platform.create'), isEmpty);
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
      expect(f.callsFor('documents.platform.conflict'), isEmpty);
      expect((result['renamed'] as List<Object?>), hasLength(1));
      expect(f.callsFor('documents.platform.delete'), isEmpty);
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
        final f = Fixture()..select('bad', name);
        final response = await f.coordinator.request('documents.importFiles');
        expect(response['status'], 'partial', reason: name);
        expect(f.callsFor('local.copy'), isEmpty, reason: name);
      }
      for (final name in [
        '中文 empty',
        'file.bin',
        '.hidden',
        'name with spaces',
      ]) {
        final f = Fixture()..select('good', name);
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
      final f = Fixture()..select('root', 'Tree', directory: true);
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
        f.callsFor('documents.platform.releaseFd').single.$2['fdLeaseId'],
        'lease-file',
      );
      expect(f.calls.last.$1, 'documents.platform.release');
    },
  );
  test(
    'provider source changes never publish an unverified cache file',
    () async {
      final f = Fixture()
        ..select('file', 'data.txt')
        ..mutateSource = true;
      final result = await f.coordinator.request('documents.importFiles');
      expect(result['status'], 'partial');
      expect(result['files'], 0);
      expect(result['items'], isEmpty);
      expect(f.callsFor('local.commit'), isEmpty);
      expect(f.callsFor('local.part.remove'), hasLength(1));
      expect(f.callsFor('documents.platform.releaseFd'), hasLength(1));
    },
  );
  test(
    'duplicate provider names remain partial and are never silently merged',
    () async {
      final f = Fixture()..select('root', 'Tree', directory: true);
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
    'uncertain provider create never retries or deletes an existing document',
    () async {
      final f = Fixture()
        ..select('parent', 'Destination', directory: true)
        ..loseCreate = true;
      f.local['/cache/source'] = {'kind': 'directory'};
      final result = await f.coordinator.request('documents.export', {
        'localPath': '/cache/source',
        'name': 'Tree',
        'kind': 'directory',
      });
      expect(result['status'], 'resultUnknown');
      expect(result['partialDestinationPossible'], isTrue);
      expect(f.callsFor('documents.platform.create'), hasLength(1));
      expect(f.callsFor('documents.platform.delete'), isEmpty);
    },
  );
}
