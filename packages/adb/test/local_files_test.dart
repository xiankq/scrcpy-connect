import 'dart:async';
import 'dart:typed_data';

import 'package:adb/src/api.dart' show AdbCancellation;
import 'package:adb/src/local_files.dart';
import 'package:flutter_test/flutter_test.dart';

final _path = Uint8List.fromList('/safe/file'.codeUnits);
final _identity = LocalFileIdentity(
  device: BigInt.one,
  inode: BigInt.two,
  size: BigInt.from(3),
  modifiedSeconds: -1,
  modifiedNanos: 999,
  kind: LocalFileKind.file,
);

void main() {
  Future<LocalFileScope> open(_FilesApi api) =>
      LocalFiles(api)
          .openScope(scopeKey: 'test-local-files', allowedRoots: [_path]);
  Future<LocalFileCopy> copy(
    LocalFileScope scope, {
    AdbCancellation? cancellation,
  }) => scope.copy(
    source: const LocalFileEndpoint.fd(12),
    target: const LocalFileEndpoint.fd(13),
    maxBytes: 10,
    timeout: const Duration(seconds: 1),
    cancellation: cancellation,
  );

  test('预取消不会登记复制或复制描述符', () async {
    final api = _FilesApi();
    final scope = await open(api);
    final stop = AdbCancellation()..cancel();
    expect(
      () => copy(scope, cancellation: stop),
      throwsA(_code(LocalFileErrorCode.cancelled)),
    );
    expect(api.created, 0);
    await scope.close();
  });

  test('create 迟到后取消须等精确 close，不启动 run', () async {
    final api = _FilesApi()
      ..creating = Completer<String>()
      ..copyClosing = Completer<void>();
    final scope = await open(api);
    final stop = AdbCancellation();
    final operation = copy(scope, cancellation: stop);
    final checked = expectLater(
      operation,
      throwsA(_code(LocalFileErrorCode.cancelled)),
    );
    stop.cancel();
    api.creating!.complete('late-copy');
    await api.closeEntered.future;
    expect(api.ran, 0);
    var settled = false;
    operation.then<void>(
      (_) {
        settled = true;
      },
      onError: (Object _) {
        settled = true;
      },
    );
    await Future<void>.value();
    expect(settled, isFalse);
    expect(api.closedIds, ['late-copy']);
    api.copyClosing!.complete();
    await checked;
    await scope.close();
  });

  test('run 成功与取消交错保留外部目标部分写入事实', () async {
    final api = _FilesApi()..running = Completer<LocalFileCopyResult>();
    final scope = await open(api);
    final stop = AdbCancellation();
    final operation = copy(scope, cancellation: stop);
    final checked = expectLater(
      operation,
      throwsA(
        isA<LocalFileException>()
            .having((e) => e.code, 'code', LocalFileErrorCode.cancelled)
            .having((e) => e.bytesCopied, 'bytesCopied', 3)
            .having(
              (e) => e.partialDestinationPossible,
              'partialDestinationPossible',
              isTrue,
            ),
      ),
    );
    await api.runEntered.future;
    stop.cancel();
    api.running!.complete(
      LocalFileCopyResult(
        bytes: 3,
        identity: _identity,
        sourceIdentity: _identity,
      ),
    );
    await checked;
    expect(api.closedIds, ['copy']);
    await scope.close();
  });

  test('scope close 立即撤销 native 并等待迟到 run 交付被拒绝', () async {
    final api = _FilesApi()..running = Completer<LocalFileCopyResult>();
    final scope = await open(api);
    final operation = copy(scope);
    final checked = expectLater(
      operation,
      throwsA(_code(LocalFileErrorCode.scopeClosed)),
    );
    await api.runEntered.future;
    var closed = false;
    final closing = scope.close().then((_) {
      closed = true;
    });
    await api.scopeCloseEntered.future;
    expect(closed, isFalse);
    api.running!.complete(
      LocalFileCopyResult(
        bytes: 3,
        identity: _identity,
        sourceIdentity: _identity,
      ),
    );
    await checked;
    await closing;
    expect(
      () => scope.stat(_path),
      throwsA(_code(LocalFileErrorCode.scopeClosed)),
    );
  });

  test('scope 确认关闭后的 copy close 幂等，不再调用已释放 native id', () async {
    final api = _FilesApi();
    final scope = await open(api);
    final value = await copy(scope);
    await scope.close();
    await value.close();
    expect(api.closedIds, isEmpty);
  });

  test('关闭失败保持禁止准入，下一次 close 重试同 scope', () async {
    final api = _FilesApi()..scopeCloseFailures = 1;
    final files = LocalFiles(api);
    await files.openScope(scopeKey: 'test-local-files', allowedRoots: [_path]);
    await expectLater(
      files.close(),
      throwsA(_code(LocalFileErrorCode.cleanupUnconfirmed)),
    );
    expect(
      () =>
          files.openScope(scopeKey: 'test-local-files', allowedRoots: [_path]),
      throwsA(_code(LocalFileErrorCode.scopeClosed)),
    );
    await files.close();
    expect(api.scopeClosedIds, ['scope', 'scope']);
  });

  test('另一个 open 失败不会跳过已经登记的 scope 清理', () async {
    final api = _FilesApi();
    final files = LocalFiles(api);
    await files.openScope(scopeKey: 'test-local-files', allowedRoots: [_path]);
    api.opening = Completer<String>();
    final failed = files.openScope(
      scopeKey: 'test-local-files',
      allowedRoots: [_path],
    );
    final checked = expectLater(failed, throwsStateError);
    final closing = files.close();
    api.opening!.completeError(StateError('登记前失败'));
    await checked;
    await closing;
    expect(api.scopeClosedIds, ['scope']);
  });

  test('native scope close 超时失败不等待仍阻塞 run，保留可重试所有者', () async {
    final api = _FilesApi()
      ..scopeCloseFailures = 1
      ..running = Completer<LocalFileCopyResult>();
    final scope = await open(api);
    final copying = copy(scope);
    final checked = expectLater(
      copying,
      throwsA(_code(LocalFileErrorCode.scopeClosed)),
    );
    await api.runEntered.future;
    await expectLater(
      scope.close(),
      throwsA(_code(LocalFileErrorCode.cleanupUnconfirmed)),
    );
    api.running!.complete(
      LocalFileCopyResult(
        bytes: 3,
        identity: _identity,
        sourceIdentity: _identity,
      ),
    );
    await checked;
    await scope.close();
    expect(api.scopeClosedIds, ['scope', 'scope']);
  });

  test('LocalFiles close 等待迟到 scope 并将其关闭', () async {
    final api = _FilesApi()..opening = Completer<String>();
    final files = LocalFiles(api);
    final opening = files.openScope(
      scopeKey: 'test-local-files',
      allowedRoots: [_path],
    );
    final checked = expectLater(
      opening,
      throwsA(_code(LocalFileErrorCode.scopeClosed)),
    );
    var closed = false;
    final closing = files.close().then((_) {
      closed = true;
    });
    expect(closed, isFalse);
    api.opening!.complete('late-scope');
    await checked;
    await closing;
    expect(api.scopeClosedIds, ['late-scope']);
  });

  test('复制失败后回收再失败仍保留已写字节与未知目标事实', () async {
    final api = _FilesApi()
      ..copyCloseFailures = 1
      ..copyCloseCode = LocalFileErrorCode.io
      ..runFailure = const LocalFileException(
        LocalFileErrorCode.cancelled,
        '外部流已写入',
        bytesCopied: 3,
        partialDestinationPossible: true,
      );
    final scope = await open(api);
    await expectLater(
      copy(scope),
      throwsA(
        isA<LocalFileException>()
            .having(
              (e) => e.code,
              'code',
              LocalFileErrorCode.cleanupUnconfirmed,
            )
            .having((e) => e.bytesCopied, 'bytesCopied', 3)
            .having(
              (e) => e.partialDestinationPossible,
              'partialDestinationPossible',
              isTrue,
            ),
      ),
    );
    await scope.close();
    expect(api.scopeClosedIds, ['scope']);
  });

  test('copy close 首次失败保留租约供精确重试', () async {
    final api = _FilesApi()..copyCloseFailures = 1;
    final scope = await open(api);
    final value = await copy(scope);
    await expectLater(
      value.close(),
      throwsA(_code(LocalFileErrorCode.cleanupUnconfirmed)),
    );
    await value.close();
    expect(api.closedIds, ['copy', 'copy']);
    await scope.close();
  });
}

Matcher _code(LocalFileErrorCode code) =>
    isA<LocalFileException>().having((e) => e.code, 'code', code);

final class _FilesApi implements NativeLocalFilesApi {
  Completer<String>? opening, creating;
  Completer<LocalFileCopyResult>? running;
  Completer<void>? copyClosing;
  LocalFileException? runFailure;
  LocalFileErrorCode copyCloseCode = LocalFileErrorCode.cleanupUnconfirmed;
  final closeEntered = Completer<void>();
  final runEntered = Completer<void>();
  final scopeCloseEntered = Completer<void>();
  final closedIds = <String>[], scopeClosedIds = <String>[];
  int created = 0, ran = 0, copyCloseFailures = 0, scopeCloseFailures = 0;
  @override
  Future<String> openScope(
    String scopeKey,
    List<Uint8List> allowedRoots,
    int closeTimeoutMs,
  ) async => opening == null ? 'scope' : opening!.future;
  @override
  Future<void> closeScope(String scopeId, int timeoutMs) async {
    scopeClosedIds.add(scopeId);
    if (!scopeCloseEntered.isCompleted) scopeCloseEntered.complete();
    if (scopeCloseFailures > 0) {
      scopeCloseFailures--;
      throw const LocalFileException(
        LocalFileErrorCode.cleanupUnconfirmed,
        '保留原 scope',
      );
    }
  }

  @override
  Future<String> createCopy(
    String scopeId,
    LocalFileCopyRequest request,
  ) async {
    created++;
    return creating == null ? 'copy' : creating!.future;
  }

  @override
  Future<LocalFileCopyResult> runCopy(String copyId) async {
    ran++;
    if (runFailure case final failure?) throw failure;
    if (!runEntered.isCompleted) runEntered.complete();
    return running == null
        ? LocalFileCopyResult(
            bytes: 3,
            identity: _identity,
            sourceIdentity: _identity,
          )
        : running!.future;
  }

  @override
  Future<void> cancelCopy(String copyId) async {}
  @override
  Future<void> closeCopy(String copyId, int timeoutMs) async {
    closedIds.add(copyId);
    if (!closeEntered.isCompleted) closeEntered.complete();
    if (copyCloseFailures > 0) {
      copyCloseFailures--;
      throw LocalFileException(copyCloseCode, '保留原 copy');
    }
    await copyClosing?.future;
  }

  @override
  Future<LocalFileStat> stat(String scopeId, Uint8List path) async =>
      LocalFileStat(identity: _identity);
  @override
  Future<LocalFileList> list(
    String scopeId,
    Uint8List path,
    int maxEntries,
  ) async => LocalFileList(identity: _identity, entries: []);
  @override
  Future<void> mkdir(String scopeId, Uint8List path, bool exclusive) async {}
  @override
  Future<void> remove(
    String scopeId,
    Uint8List path,
    LocalFileIdentity expectedIdentity,
  ) async {}
  @override
  Future<LocalFileIdentity> commit(
    String scopeId,
    String copyId,
    Uint8List destination,
    LocalFileIdentity expectedIdentity,
  ) async => _identity;
}
