import 'dart:async';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

const device = AdbDevice(id: 'connection', serial: 'serial', state: 'device');

final class FileApi implements NativeAdbApi, NativeAdbFileApi {
  final executeGate = Completer<String>();
  final waiting = Completer<void>();
  final queued = <AdbFileExecutionEvent>[];
  final cancelled = <String>[];
  final cancelledServices = <String>[];
  AdbFileExecutionRequest? request;
  Completer<AdbFileExecutionEvent?>? pending;
  bool delayAdmission = false, failCancel = false;
  bool failServiceCancel = false;
  int reads = 0;
  @override
  Future<String> fileExecute(
    String connectionId,
    AdbFileExecutionRequest request,
    int timeoutMs,
  ) async {
    expect(connectionId, 'connection');
    this.request = request;
    return delayAdmission ? executeGate.future : 'worker';
  }

  @override
  Future<AdbFileExecutionEvent?> fileNext(String operationId) {
    reads++;
    if (queued.isNotEmpty) return Future.value(queued.removeAt(0));
    if (!waiting.isCompleted) waiting.complete();
    pending = Completer<AdbFileExecutionEvent?>();
    return pending!.future;
  }

  @override
  Future<void> fileCancel(String operationId) async {
    cancelled.add(operationId);
    if (failCancel) throw const AdbException('file_cleanup_unconfirmed');
    final read = pending;
    if (read != null && !read.isCompleted) {
      read.completeError(const AdbException('cancelled'));
    }
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async => 'service-worker';
  @override
  Future<void> cancel(String id) async {
    cancelledServices.add(id);
    if (failServiceCancel) throw const AdbException('cleanup_unconfirmed');
  }

  @override
  Future<void> initializeFileHelpers(List<AdbFileHelper> helpers) async {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class ScopeFileApi extends FileApi implements NativeAdbFileScopeApi {
  final attached = <String>[];
  final closedScopes = <String>[];
  bool failScopeClose = false;
  Completer<String>? scopeAdmission;

  @override
  Future<String> fileScopeAttach(String ownerKey) async {
    attached.add(ownerKey);
    return scopeAdmission?.future ?? 'scope-${attached.length}';
  }

  @override
  Future<void> fileScopeClose(String scopeId) async {
    closedScopes.add(scopeId);
    if (failScopeClose) throw const AdbException('file_cleanup_unconfirmed');
  }
}

const _admission = AdbAdmissionScopeInfo(
  scopeKey: 'file-owner',
  scopeId: 'admission-first',
  accepting: true,
);

final class ScopedFileApi extends ScopeFileApi
    implements NativeAdbScopedFileScopeApi, NativeAdbAdmissionApi {
  AdbAdmissionScopeInfo? currentAdmission = _admission;
  final admissionRequests = <String>[];

  @override
  Future<String> fileScopeAttachScoped(
    String ownerKey,
    String admissionScopeId,
  ) {
    admissionRequests.add(admissionScopeId);
    return super.fileScopeAttach(ownerKey);
  }

  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String scopeKey) async {
    expect(scopeKey, _admission.scopeKey);
    return currentAdmission;
  }
}

final class PartFileApi extends ScopeFileApi {
  final releases = <AdbFileExecutionRequest>[];
  final retainedParts = <String>{'exact-part'};
  bool failReleaseCancel = false;
  Completer<void>? scopeCloseGate;
  int releaseReads = 0, releaseReadFailures = 0;

  @override
  Future<String> fileExecute(
    String connectionId,
    AdbFileExecutionRequest request,
    int timeoutMs,
  ) async {
    if (request.kind == AdbFileExecutionKind.releasePart) {
      expect(connectionId, 'connection');
      releases.add(request);
      return 'release-worker';
    }
    return super.fileExecute(connectionId, request, timeoutMs);
  }

  @override
  Future<AdbFileExecutionEvent?> fileNext(String operationId) async {
    if (operationId == 'release-worker') {
      releaseReads++;
      if (releaseReadFailures > 0) {
        releaseReadFailures--;
        throw const AdbException('release_read_failed');
      }
      retainedParts.remove(releases.last.partId);
      return AdbFileExecutionEvent(kind: 'done');
    }
    return super.fileNext(operationId);
  }

  @override
  Future<void> fileScopeClose(String scopeId) async {
    await super.fileScopeClose(scopeId);
    await scopeCloseGate?.future;
    retainedParts.clear();
  }

  @override
  Future<void> fileCancel(String operationId) async {
    if (operationId == 'release-worker' && failReleaseCancel) {
      cancelled.add(operationId);
      throw const AdbException('file_cleanup_unconfirmed');
    }
    await super.fileCancel(operationId);
  }
}

void main() {
  for (final tokenCancellation in [true, false]) {
    test(
      'late part handoff is reclaimed after ${tokenCancellation ? 'token cancellation' : 'external close'}',
      () async {
        final api = PartFileApi();
        final services = NativeAdbClient(api, '').services;
        final scope = await services.attachFileScope('owner');
        final token = AdbCancellation();
        final operation = await scope
            .files(device)
            .execute(
              AdbFileExecutionRequest(
                kind: AdbFileExecutionKind.copy,
                path: [47, 115],
                destination: [47, 255],
              ),
              cancellation: token,
            );
        final received = <AdbFileExecutionEvent>[];
        final failed = expectLater(
          operation.events.forEach(received.add),
          throwsA(isA<AdbException>()),
        );
        await api.waiting.future;
        // 原生已将精确 part 交给 next；随后取消不能只丢弃 done。
        api.pending!.complete(
          AdbFileExecutionEvent(kind: 'done', partId: 'exact-part'),
        );
        if (tokenCancellation) token.cancel();
        await operation.close();
        await failed;
        expect(received, isEmpty);
        expect(api.retainedParts, isEmpty);
        expect(api.releases.single.partId, 'exact-part');
        expect(api.releases.single.path, [47, 255]);
        expect(api.releases.single.scopeId, scope.id);
        expect(api.cancelled, ['worker', 'release-worker']);
        await services.close();
      },
    );
  }

  for (final rawRequest in [false, true]) {
    test(
      'facade close confirms scope drain for ${rawRequest ? 'raw request scopeId' : 'scoped files'} before discarding a late part',
      () async {
        final api = PartFileApi()..scopeCloseGate = Completer<void>();
        final services = NativeAdbClient(api, '').services;
        final scope = await services.attachFileScope('owner');
        final files = rawRequest ? services.files(device) : scope.files(device);
        final operation = await files.execute(
          AdbFileExecutionRequest(
            kind: AdbFileExecutionKind.copy,
            path: [47],
            destination: [47, 112],
            scopeId: rawRequest ? scope.id : '',
          ),
        );
        final failed = expectLater(
          operation.events.drain<void>(),
          throwsA(isA<AdbException>()),
        );
        await api.waiting.future;
        api.pending!.complete(
          AdbFileExecutionEvent(kind: 'done', partId: 'exact-part'),
        );
        var closed = false;
        final closing = services.close().then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse, reason: '不能在 scope 原生排空尚未确认时丢弃 part');
        api.scopeCloseGate!.complete();
        await closing;
        await failed;
        expect(api.retainedParts, isEmpty);
        expect(api.closedScopes, [scope.id]);
        expect(
          api.releases,
          isEmpty,
          reason: '已确认原生 scope drain，不重新向旧代准入 release',
        );
      },
    );
  }

  test(
    'failed late part release cleanup retains the exact owner for retry',
    () async {
      final api = PartFileApi()..failReleaseCancel = true;
      final services = NativeAdbClient(api, '').services;
      final operation = await services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.copy,
              path: [47],
              destination: [47, 112],
            ),
          );
      final failed = expectLater(
        operation.events.drain<void>(),
        throwsA(isA<AdbException>()),
      );
      await api.waiting.future;
      api.pending!.complete(
        AdbFileExecutionEvent(kind: 'done', partId: 'exact-part'),
      );
      await expectLater(operation.close(), throwsA(isA<AdbException>()));
      await failed;
      api.failReleaseCancel = false;
      await services.close();
      expect(api.retainedParts, isEmpty);
      expect(api.releases, hasLength(1), reason: '已确认释放，重试只回收同一清理 worker');
      expect(api.releaseReads, 1);
      expect(api.cancelled.where((id) => id == 'release-worker'), hasLength(2));
    },
  );

  test('late part release read failure keeps part and drains old worker before retry', () async {
    final api = PartFileApi()..releaseReadFailures = 1;
    final services = NativeAdbClient(api, '').services;
    final operation = await services
        .files(device)
        .execute(
          AdbFileExecutionRequest(
            kind: AdbFileExecutionKind.copy,
            path: [47],
            destination: [47, 112],
          ),
        );
    final failed = expectLater(
      operation.events.drain<void>(),
      throwsA(isA<AdbException>()),
    );
    await api.waiting.future;
    api.pending!.complete(
      AdbFileExecutionEvent(kind: 'done', partId: 'exact-part'),
    );
    await expectLater(operation.close(), throwsA(isA<AdbException>()));
    await failed;
    expect(api.retainedParts, {'exact-part'});
    await services.close();
    expect(api.retainedParts, isEmpty);
    expect(api.releases.map((request) => request.partId), [
      'exact-part',
      'exact-part',
    ]);
    expect(api.cancelled.where((id) => id == 'release-worker'), hasLength(2));
  });

  test(
    'normally delivered part remains owned by the caller after session close',
    () async {
      final api = PartFileApi()
        ..queued.add(AdbFileExecutionEvent(kind: 'done', partId: 'exact-part'));
      final operation = await NativeAdbClient(api, '').services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.copy,
              path: [47],
              destination: [47, 112],
            ),
          );
      expect((await operation.events.single).partId, 'exact-part');
      expect(api.retainedParts, {'exact-part'});
      expect(api.releases, isEmpty);
    },
  );

  for (final kind in ['stat', 'done']) {
    test(
      'cancelled file reader rejects an already returned $kind receipt',
      () async {
        const stamp = AdbFileExecutionStamp(
          mode: 0x81a4,
          size: 1,
          modifiedSeconds: 1,
          modifiedNanos: 0,
          nanosecondPrecision: false,
        );
        final api = FileApi();
        final token = AdbCancellation();
        final operation = await NativeAdbClient(api, '').services
            .files(device)
            .execute(
              AdbFileExecutionRequest(
                kind: AdbFileExecutionKind.stat,
                path: [47],
              ),
              cancellation: token,
            );
        final received = <AdbFileExecutionEvent>[];
        final failed = expectLater(
          operation.events.forEach(received.add),
          throwsA(
            isA<AdbException>().having((e) => e.code, 'code', 'cancelled'),
          ),
        );
        await api.waiting.future;
        // 读取 Future 已交回，Dart 的 await 续体尚未运行；取消必须先撤销准入。
        api.pending!.complete(AdbFileExecutionEvent(kind: kind, stamp: stamp));
        token.cancel();
        await failed;
        expect(received, isEmpty);
        expect(api.cancelled, ['worker']);
      },
    );
  }

  test('external close cannot turn a partial stat into success', () async {
    const stamp = AdbFileExecutionStamp(
      mode: 0x81a4,
      size: 1,
      modifiedSeconds: 1,
      modifiedNanos: 0,
      nanosecondPrecision: false,
    );
    final api = FileApi()
      ..queued.add(AdbFileExecutionEvent(kind: 'stat', stamp: stamp));
    final client = NativeAdbClient(api, '');
    final failed = expectLater(
      client.services.files(device).stat([47]),
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    );
    await api.waiting.future;
    api.pending!.complete(AdbFileExecutionEvent(kind: 'done'));
    await client.services.close();
    await failed;
  });

  test('service close waits for input release and preserves failed native cleanup for retry', () async {
    final api = FileApi()..failServiceCancel = true;
    final client = NativeAdbClient(api, '');
    final session = await client.services.exec(device, 'cat');
    final cancellingInput = Completer<void>();
    final releaseInput = Completer<void>();
    final input = StreamController<List<int>>(
      onCancel: () async {
        cancellingInput.complete();
        await releaseInput.future;
      },
    );
    final inputFailed = expectLater(
      session.addStream(input.stream),
      throwsA(
        isA<AdbException>().having((e) => e.code, 'code', 'service_closed'),
      ),
    );
    var finished = false;
    final closing = expectLater(
      session.close(),
      throwsA(isA<AdbException>()),
    ).then((_) => finished = true);
    await cancellingInput.future;
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse, reason: '原生取消失败也必须等待本机输入迭代器释放');
    releaseInput.complete();
    await closing;
    await inputFailed;
    api.failServiceCancel = false;
    await client.services.close();
    expect(api.cancelledServices, ['service-worker', 'service-worker']);
  });

  test('same-owner attachments cannot retire a newer scope through reordered receipts', () async {
    final gate = Completer<String>();
    final api = ScopeFileApi()..scopeAdmission = gate;
    final client = NativeAdbClient(api, '');
    final first = client.services.attachFileScope('owner');
    final second = client.services.attachFileScope('owner');
    await Future<void>.delayed(Duration.zero);
    expect(api.attached, ['owner']);
    api.scopeAdmission = null;
    gate.complete('first-scope');
    final old = await first;
    final current = await second;
    expect(api.attached, ['owner', 'owner']);
    expect(() => old.files(device), throwsA(isA<AdbException>()));
    final operation = await current
        .files(device)
        .execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
        );
    expect(api.request!.scopeId, current.id);
    await operation.close();
    await client.services.close();
    expect(api.closedScopes, [current.id]);
  });

  test(
    'services close retries every failed owner while admission stays closed',
    () async {
      final api = ScopeFileApi()
        ..failCancel = true
        ..failServiceCancel = true
        ..failScopeClose = true;
      final client = NativeAdbClient(api, '');
      final service = await client.services.exec(device, 'true');
      await client.services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.stat,
              path: [47],
            ),
          );
      final scope = await client.services.attachFileScope('stable-owner');
      await expectLater(client.services.close(), throwsA(isA<AdbException>()));
      expect(api.cancelledServices, ['service-worker']);
      expect(api.cancelled, ['worker']);
      expect(api.closedScopes, [scope.id]);
      await expectLater(
        client.services.exec(device, 'true'),
        throwsA(isA<AdbException>().having((e) => e.code, 'code', 'closed')),
      );
      await expectLater(
        service.write(Uint8List(1)),
        throwsA(
          isA<AdbException>().having((e) => e.code, 'code', 'service_closed'),
        ),
      );
      api.failCancel = false;
      api.failServiceCancel = false;
      api.failScopeClose = false;
      await client.services.close();
      expect(api.cancelledServices, ['service-worker', 'service-worker']);
      expect(api.cancelled, ['worker', 'worker']);
      expect(api.closedScopes, [scope.id, scope.id]);
      await expectLater(
        client.services.attachFileScope('another-owner'),
        throwsA(isA<AdbException>().having((e) => e.code, 'code', 'closed')),
      );
    },
  );

  test(
    'reattach retires the old local scope and drains late operation admission',
    () async {
      final api = ScopeFileApi()..delayAdmission = true;
      final client = NativeAdbClient(api, '');
      final old = await client.services.attachFileScope('stable-owner');
      final oldFiles = old.files(device);
      final opening = oldFiles.execute(
        AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
      );
      final failed = expectLater(opening, throwsA(isA<AdbException>()));
      await Future<void>.delayed(Duration.zero);
      final current = await client.services.attachFileScope('stable-owner');
      api.executeGate.complete('late-old-worker');
      await failed;
      expect(api.cancelled, ['late-old-worker']);
      await expectLater(
        oldFiles.execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
        ),
        throwsA(
          isA<AdbException>().having(
            (e) => e.code,
            'code',
            'file_scope_closed',
          ),
        ),
      );
      await client.services.close();
      expect(api.closedScopes, [current.id], reason: '旧代已由原生交接排空，不累计历史 owner');
    },
  );

  test(
    'scope binding captures its opaque id without mutating caller requests',
    () async {
      final api = ScopeFileApi();
      final client = NativeAdbClient(api, '');
      final scope = await client.services.attachFileScope('stable-owner');
      final request = AdbFileExecutionRequest(
        kind: AdbFileExecutionKind.stat,
        path: [47],
      );
      final operation = await scope.files(device).execute(request);
      expect(api.request!.scopeId, scope.id);
      expect(request.scopeId, isEmpty);
      expect(api.attached, ['stable-owner']);
      await operation.close();
      await scope.close();
      expect(api.closedScopes, [scope.id]);
      expect(() => scope.files(device), throwsA(isA<AdbException>()));
    },
  );

  test('scoped file admission passes exact authority and retains its closing handle', () async {
    final api = ScopedFileApi();
    final services = NativeAdbClient(api, '').services;
    final scope = await services.attachFileScope(
      'stable-owner',
      admissionScope: _admission,
    );
    expect(api.admissionRequests, [_admission.scopeId]);
    expect(api.attached, ['stable-owner']);
    await scope.close();
    expect(api.closedScopes, [scope.id]);
  });

  test('late scoped file receipt cannot cross a parent handover', () async {
    final api = ScopedFileApi()..scopeAdmission = Completer<String>();
    final services = NativeAdbClient(api, '').services;
    final attaching = services.attachFileScope(
      'stable-owner',
      admissionScope: _admission,
    );
    final rejected = expectLater(
      attaching,
      throwsA(
        isA<AdbException>().having(
          (error) => error.code,
          'code',
          'adb_admission_scope_stale',
        ),
      ),
    );
    api.currentAdmission = const AdbAdmissionScopeInfo(
      scopeKey: 'file-owner',
      scopeId: 'admission-next',
      accepting: true,
    );
    api.scopeAdmission!.complete('old-file-scope');
    await rejected;
    expect(api.closedScopes, ['old-file-scope']);
    expect(api.admissionRequests, [_admission.scopeId]);
  });

  test(
    'failed cleanup of a rejected scoped receipt remains owned for retry',
    () async {
      final api = ScopedFileApi()
        ..currentAdmission = null
        ..failScopeClose = true;
      final services = NativeAdbClient(api, '').services;
      await expectLater(
        services.attachFileScope('stable-owner', admissionScope: _admission),
        throwsA(
          isA<AdbException>().having(
            (error) => error.code,
            'code',
            'file_cleanup_unconfirmed',
          ),
        ),
      );
      api.failScopeClose = false;
      await services.close();
      expect(api.closedScopes, ['scope-1', 'scope-1']);
    },
  );

  test(
    'scoped file admission never falls back to an unscoped adapter',
    () async {
      final api = ScopeFileApi();
      await expectLater(
        NativeAdbClient(
          api,
          '',
        ).services.attachFileScope('stable-owner', admissionScope: _admission),
        throwsA(
          isA<AdbException>().having(
            (error) => error.code,
            'code',
            'scoped_file_capability_unavailable',
          ),
        ),
      );
      expect(api.attached, isEmpty);
    },
  );

  test('scope close failure retains retry and never falls back to unscoped execution', () async {
    final api = ScopeFileApi()..failScopeClose = true;
    final client = NativeAdbClient(api, '');
    final scope = await client.services.attachFileScope('stable-owner');
    final files = scope.files(device);
    await expectLater(scope.close(), throwsA(isA<AdbException>()));
    await expectLater(
      files.execute(
        AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
      ),
      throwsA(
        isA<AdbException>().having((e) => e.code, 'code', 'file_scope_closed'),
      ),
    );
    expect(api.request, isNull);
    api.failScopeClose = false;
    await scope.close();
    expect(api.closedScopes, [scope.id, scope.id]);
  });

  test(
    'late scope admission after services close drains the exact new scope',
    () async {
      final api = ScopeFileApi()..scopeAdmission = Completer<String>();
      final client = NativeAdbClient(api, '');
      final attaching = client.services.attachFileScope('stable-owner');
      final failed = expectLater(attaching, throwsA(isA<AdbException>()));
      var closed = false;
      final closing = client.services.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      api.scopeAdmission!.complete('late-scope');
      await failed;
      await closing;
      expect(api.closedScopes, ['late-scope']);
    },
  );

  test('scope binding refuses another scope and leaves legacy file adapters usable', () async {
    final api = ScopeFileApi();
    final scope = await NativeAdbClient(
      api,
      '',
    ).services.attachFileScope('owner');
    await expectLater(
      scope
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.commit,
              path: [47],
              scopeId: 'another-scope',
              partId: 'part',
            ),
          ),
      throwsA(
        isA<AdbException>().having(
          (e) => e.code,
          'code',
          'file_scope_mismatch',
        ),
      ),
    );
    expect(api.request, isNull);
    final legacy = FileApi();
    await expectLater(
      NativeAdbClient(legacy, '').services.attachFileScope('owner'),
      throwsA(
        isA<AdbException>().having(
          (e) => e.code,
          'code',
          'file_scope_capability_unavailable',
        ),
      ),
    );
    final operation = await NativeAdbClient(legacy, '').services
        .files(device)
        .execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
        );
    expect(legacy.request!.scopeId, isEmpty);
    await operation.close();
    await scope.close();
  });

  test(
    'raw paths and helper bytes are captured before asynchronous admission',
    () async {
      final api = FileApi()..delayAdmission = true;
      final path = Uint8List.fromList([47, 255, 10]);
      final helperBytes = [1, 2, 3];
      final helper = AdbFileHelper('x86_64', helperBytes);
      final request = AdbFileExecutionRequest(
        kind: AdbFileExecutionKind.list,
        path: path,
      );
      final opening = NativeAdbClient(
        api,
        '',
      ).services.files(device).execute(request);
      path[1] = 65;
      helperBytes[0] = 99;
      api.executeGate.complete('worker');
      final operation = await opening;
      expect(api.request!.path, [47, 255, 10]);
      expect(helper.bytes, [1, 2, 3]);
      expect(() => request.path[0] = 1, throwsUnsupportedError);
      await operation.close();
    },
  );

  test(
    'late operation admission after cancellation is drained by exact handle',
    () async {
      final api = FileApi()..delayAdmission = true;
      final cancellation = AdbCancellation();
      final opening = NativeAdbClient(api, '').services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.stat,
              path: [47],
            ),
            cancellation: cancellation,
          );
      final failed = expectLater(
        opening,
        throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
      );
      // execute 已进入原生登记，取消发生在句柄尚未返回时。
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      api.executeGate.complete('late-worker');
      await failed;
      expect(api.cancelled, ['late-worker']);
    },
  );

  test('client close drains a pending file reader and keeps cleanup retry observable', () async {
    final api = FileApi();
    final client = NativeAdbClient(api, '');
    final operation = await client.services
        .files(device)
        .execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.copy, path: [47]),
        );
    final reading = operation.events.toList();
    final cancelled = expectLater(reading, throwsA(isA<AdbException>()));
    await api.waiting.future;
    await client.close();
    await cancelled;
    expect(api.cancelled, ['worker']);
  });

  test('failed cleanup preserves exact handle for explicit retry', () async {
    final api = FileApi()..failCancel = true;
    final operation = await NativeAdbClient(api, '').services
        .files(device)
        .execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.stat, path: [47]),
        );
    await expectLater(operation.close(), throwsA(isA<AdbException>()));
    api.failCancel = false;
    await operation.close();
    expect(api.cancelled, ['worker', 'worker']);
  });

  test('event consumption retains per-entry errno, precise part id and backpressure', () async {
    const stamp = AdbFileExecutionStamp(
      mode: 0x81a4,
      size: 7,
      modifiedSeconds: -1,
      modifiedNanos: 123,
      nanosecondPrecision: true,
    );
    final api = FileApi()
      ..queued.addAll([
        AdbFileExecutionEvent(
          kind: 'entries',
          entries: [
            AdbFileExecutionEntry(
              name: [255],
              errorCode: 'permission_denied',
              errno: 13,
            ),
          ],
        ),
        AdbFileExecutionEvent(
          kind: 'done',
          stamp: stamp,
          partId: 'exact-part',
          transferred: 7,
        ),
      ]);
    final operation = await NativeAdbClient(api, '').services
        .files(device)
        .execute(
          AdbFileExecutionRequest(kind: AdbFileExecutionKind.copy, path: [47]),
        );
    final events = StreamIterator(operation.events);
    expect(await events.moveNext(), isTrue);
    expect(events.current.entries.single.name, [255]);
    expect(events.current.entries.single.errno, 13);
    await Future<void>.delayed(Duration.zero);
    expect(api.reads, 1, reason: '暂停消费者不能预取下一个事件');
    expect(await events.moveNext(), isTrue);
    expect(events.current.partId, 'exact-part');
    expect(events.current.stamp!.modifiedNanos, 123);
    expect(await events.moveNext(), isFalse);
    expect(api.cancelled, ['worker']);
  });

  test('foreign native owner is rejected before file admission', () async {
    final api = FileApi();
    await expectLater(
      NativeAdbClient(api, '').services
          .files(
            AdbDevice(
              id: 'connection',
              serial: 'serial',
              state: 'device',
              nativeOwner: Object(),
            ),
          )
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.stat,
              path: [47],
            ),
          ),
      throwsA(isA<AdbException>()),
    );
    expect(api.request, isNull);
  });
  test(
    'a stat packet without done cannot become a successful snapshot',
    () async {
      const stamp = AdbFileExecutionStamp(
        mode: 0x81a4,
        size: 1,
        modifiedSeconds: 1,
        modifiedNanos: 0,
        nanosecondPrecision: false,
      );
      final api = FileApi()
        ..queued.add(AdbFileExecutionEvent(kind: 'stat', stamp: stamp));
      final stat = NativeAdbClient(api, '').services.files(device).stat([47]);
      final failed = expectLater(
        stat,
        throwsA(
          isA<AdbException>().having((e) => e.code, 'code', 'result_unknown'),
        ),
      );
      await api.waiting.future;
      api.pending!.complete(null);
      await failed;
      expect(api.cancelled, ['worker']);
    },
  );
  test(
    'completed file session removes cancellation listener before token reuse',
    () async {
      final api = FileApi()..queued.add(AdbFileExecutionEvent(kind: 'done'));
      final token = AdbCancellation();
      final operation = await NativeAdbClient(api, '').services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.mkdir,
              path: [47],
            ),
            cancellation: token,
          );
      await operation.events.drain<void>();
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(api.cancelled, ['worker']);
    },
  );
  test(
    'late file admission retains failed cleanup until client close retries it',
    () async {
      final api = FileApi()
        ..delayAdmission = true
        ..failCancel = true;
      final client = NativeAdbClient(api, '');
      final opening = client.services
          .files(device)
          .execute(
            AdbFileExecutionRequest(
              kind: AdbFileExecutionKind.stat,
              path: [47],
            ),
          );
      final failed = expectLater(opening, throwsA(isA<AdbException>()));
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = client.close();
      final failedClose = expectLater(
        closing,
        throwsA(isA<AdbException>()),
      ).then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      api.executeGate.complete('late-worker');
      await failed;
      await failedClose;
      expect(api.cancelled, ['late-worker', 'late-worker']);
      api.failCancel = false;
      await client.close();
      expect(api.cancelled, ['late-worker', 'late-worker', 'late-worker']);
    },
  );

  test('late scope admission retains failed cleanup and same-owner queued requests cannot start after close', () async {
    final api = ScopeFileApi()
      ..scopeAdmission = Completer<String>()
      ..failScopeClose = true;
    final client = NativeAdbClient(api, '');
    final first = client.services.attachFileScope('owner');
    final firstFailed = expectLater(first, throwsA(isA<AdbException>()));
    final queued = client.services.attachFileScope('owner');
    final queuedFailed = expectLater(queued, throwsA(isA<AdbException>()));
    var closed = false;
    final closing = client.services.close();
    final failedClose = expectLater(
      closing,
      throwsA(isA<AdbException>()),
    ).then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    api.scopeAdmission!.complete('late-scope');
    await firstFailed;
    await queuedFailed;
    await failedClose;
    expect(api.attached, ['owner']);
    expect(api.closedScopes, ['late-scope', 'late-scope']);
    api.failScopeClose = false;
    await client.services.close();
    expect(api.closedScopes, ['late-scope', 'late-scope', 'late-scope']);
  });
}
