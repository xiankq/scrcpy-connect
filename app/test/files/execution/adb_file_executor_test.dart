import 'package:scrcpy_connect/models/device_connection.dart';
import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/models/file_cancellation.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';
import 'package:scrcpy_connect/services/file_executor.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart' as adb;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/adb_file_executor.dart';

const first = adb.AdbDevice(id: 'original', serial: 'serial', state: 'device');
const second = adb.AdbDevice(
  id: 'replacement',
  serial: 'serial',
  state: 'device',
);
const remoteStamp = adb.AdbFileExecutionStamp(
  mode: 0x81a4,
  size: 7,
  modifiedSeconds: 12,
  modifiedNanos: 0,
  nanosecondPrecision: false,
);
const preciseStamp = adb.AdbFileExecutionStamp(
  mode: 0x81a4,
  size: 7,
  modifiedSeconds: 12,
  modifiedNanos: 123456789,
  nanosecondPrecision: true,
);

final class Api
    implements
        adb.NativeAdbApi,
        adb.NativeAdbFileApi,
        adb.NativeAdbLocalFileApi {
  final calls = <(String, adb.AdbFileExecutionRequest)>[];
  final closed = <String>[];
  final queues = <String, List<adb.AdbFileExecutionEvent>>{};
  final localPaths = <Uint8List>[];
  final admission = Completer<void>();
  Completer<String>? delayed;
  Completer<adb.AdbFileExecutionEvent?>? blockedNext;
  final reading = Completer<void>();
  bool unknownMutation = false, rejectClose = false, rejectPartClose = false;
  bool blockCopyOnly = false;
  bool _blocks(String operationId) =>
      !blockCopyOnly ||
      calls[int.parse(operationId.substring('worker-'.length)) - 1].$2.kind ==
          adb.AdbFileExecutionKind.copy;
  adb.AdbFileExecutionStamp localStamp = preciseStamp;
  @override
  Future<String> fileExecute(
    String connectionId,
    adb.AdbFileExecutionRequest request,
    int timeoutMs,
  ) async {
    calls.add((connectionId, request));
    final id = 'worker-${calls.length}';
    queues[id] = switch (request.kind) {
      adb.AdbFileExecutionKind.stat => [
        adb.AdbFileExecutionEvent(kind: 'stat', stamp: remoteStamp),
        adb.AdbFileExecutionEvent(kind: 'done'),
      ],
      adb.AdbFileExecutionKind.copy => [
        adb.AdbFileExecutionEvent(kind: 'progress', transferred: 2),
        adb.AdbFileExecutionEvent(
          kind: 'done',
          transferred: 7,
          partId: request.push ? null : 'exact-part',
        ),
      ],
      _ =>
        unknownMutation
            ? []
            : [
                adb.AdbFileExecutionEvent(
                  kind: 'done',
                  saveMode: request.kind == adb.AdbFileExecutionKind.releasePart
                      ? 'released'
                      : 'atomicNoReplace',
                ),
              ],
    };
    if (!admission.isCompleted) admission.complete();
    if (delayed case final gate?) return gate.future;
    return id;
  }

  @override
  Future<adb.AdbFileExecutionEvent?> fileNext(String operationId) async {
    final pending = blockedNext;
    if (pending != null && _blocks(operationId)) {
      if (!reading.isCompleted) reading.complete();
      return pending.future;
    }
    final queue = queues[operationId]!;
    return queue.isEmpty ? null : queue.removeAt(0);
  }

  @override
  Future<void> fileCancel(String operationId) async {
    closed.add(operationId);
    if (rejectClose && _blocks(operationId) ||
        rejectPartClose &&
            calls[int.parse(operationId.substring('worker-'.length)) - 1]
                    .$2
                    .kind ==
                adb.AdbFileExecutionKind.releasePart) {
      throw const adb.AdbException('adb_cleanup_unconfirmed', '原worker仍未退出');
    }
    final pending = blockedNext;
    if (pending != null && _blocks(operationId)) {
      if (!pending.isCompleted) pending.complete(null);
    }
  }

  @override
  Future<adb.AdbFileExecutionStamp> localFileStat(Uint8List path) async {
    localPaths.add(path);
    return localStamp;
  }

  @override
  Future<adb.AdbLocalFileFacts> localFileList(
    Uint8List path,
    int limit,
  ) async => adb.AdbLocalFileFacts([
    adb.AdbFileExecutionEntry(
      name: [255, 10],
      stamp: const adb.AdbFileExecutionStamp(
        mode: 0xa1ff,
        size: 4,
        modifiedSeconds: -1,
        modifiedNanos: 999999999,
        nanosecondPrecision: true,
      ),
    ),
    adb.AdbFileExecutionEntry(
      name: [97],
      errorCode: 'permission_denied',
      errorMessage: 'denied',
      errno: 13,
    ),
  ], truncated: true);
  @override
  Future<void> initializeFileHelpers(List<adb.AdbFileHelper> helpers) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileStamp expected({int nanos = 0, int resolution = 1000000000}) => FileStamp(
  mode: 0x81a4,
  size: 7,
  modifiedSeconds: 12,
  modifiedNanos: nanos,
  modifiedResolutionNanos: resolution,
);

void main() {
  test('便捷读取关闭反复失败返回精确执行所有者，重试不重放读取或关闭共享services', () async {
    final api = Api()..rejectClose = true;
    final client = adb.NativeAdbClient(api, '');
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async =>
          DeviceConnection(client: client, device: first),
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    FileExecutionCleanupFailure? failure;
    try {
      await executor.stat(
        'device',
        '/remote',
        local: false,
        cancellation: FileCancellation(),
      );
      fail('原worker关闭未确认，不能交付读取成功。');
    } on FileExecutionCleanupFailure catch (error) {
      failure = error;
    }
    await expectLater(failure.execution.close(), throwsA(isA<FileFailure>()));
    expect(api.calls, hasLength(1));
    api.rejectClose = false;
    await failure.execution.close();
    await failure.execution.close();
    expect(api.calls, hasLength(1));
    expect(api.closed.toSet(), {'worker-1'});
    expect(
      await executor.stat(
        'device',
        '/other',
        local: false,
        cancellation: FileCancellation(),
      ),
      expected(),
    );
    expect(api.calls, hasLength(2));
  });

  test('精确连接停止首败保留原worker，后继连接仍能读取，原连接拒绝新准入', () async {
    final api = Api()
      ..rejectClose = true
      ..blockedNext = Completer<adb.AdbFileExecutionEvent?>();
    final otherApi = Api();
    final client = adb.NativeAdbClient(api, '');
    final otherClient = adb.NativeAdbClient(otherApi, '');
    final original = DeviceConnection(client: client, device: first);
    final replacement = DeviceConnection(client: otherClient, device: second);
    var current = original;
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async => current,
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    final read = executor.stat(
      'device',
      '/remote',
      local: false,
      cancellation: FileCancellation(),
    );
    final failedRead = expectLater(read, throwsA(isA<FileFailure>()));
    await api.reading.future;
    await expectLater(
      executor.stopForConnection(original),
      throwsA(isA<FileFailure>()),
    );
    await expectLater(
      executor.stat(
        'device',
        '/late',
        local: false,
        cancellation: FileCancellation(),
      ),
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(api.calls, hasLength(1));
    current = replacement;
    expect(
      await executor.stat(
        'device',
        '/new',
        local: false,
        cancellation: FileCancellation(),
      ),
      expected(),
    );
    api.rejectClose = false;
    await executor.stopForConnection(original);
    await failedRead;
    await executor.stopForConnection(original);
    expect(api.closed.toSet(), {'worker-1'});
    expect(api.calls, hasLength(1));
    expect(otherApi.calls, hasLength(1));
    await executor.stopForConnection(replacement);
  });

  test('连接停止等待尚未交付的精确创建，再取消原worker而不重新执行', () async {
    final api = Api()..delayed = Completer<String>();
    final client = adb.NativeAdbClient(api, '');
    final original = DeviceConnection(client: client, device: first);
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async => original,
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    final read = executor.stat(
      'device',
      '/remote',
      local: false,
      cancellation: FileCancellation(),
    );
    final failedRead = expectLater(
      read,
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await api.admission.future;
    var stopped = false;
    final stopping = executor.stopForConnection(original).then((_) {
      stopped = true;
    });
    // 后续调用必须在实际创建仍被门闩阻塞时立即拒绝。
    await expectLater(
      executor.stat(
        'device',
        '/late',
        local: false,
        cancellation: FileCancellation(),
      ),
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(stopped, isFalse);
    expect(api.closed, isEmpty);
    api.delayed!.complete('late-worker');
    await stopping;
    await failedRead;
    expect(api.closed, ['late-worker']);
    expect(api.calls, hasLength(1));
  });

  test('停止连接精确回收未发布part，释放已确认而worker首败只重试原worker', () async {
    final api = Api();
    final client = adb.NativeAdbClient(api, '');
    final original = DeviceConnection(client: client, device: first);
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async => original,
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    await executor.copy(
      'device',
      '/remote',
      '/part',
      push: false,
      expected: expected(),
      cancellation: FileCancellation(),
      onProgress: (_) {},
    );
    api.rejectPartClose = true;
    await expectLater(
      executor.stopForConnection(original),
      throwsA(isA<FileExecutionCleanupFailure>()),
    );
    expect(api.calls.last.$2.kind, adb.AdbFileExecutionKind.releasePart);
    expect(api.calls.last.$2.partId, 'exact-part');
    final callsBeforeRetry = api.calls.length;
    api.rejectPartClose = false;
    await executor.stopForConnection(original);
    expect(api.calls, hasLength(callsBeforeRetry));
    expect(api.closed.last, 'worker-3');
  });

  test('全局关闭先撤准入并尝试全部精确连接，阻塞读取首败后可重试且不重放', () async {
    final firstApi = Api()
      ..rejectClose = true
      ..blockedNext = Completer<adb.AdbFileExecutionEvent?>();
    final secondApi = Api()
      ..rejectClose = true
      ..blockedNext = Completer<adb.AdbFileExecutionEvent?>();
    final firstClient = adb.NativeAdbClient(firstApi, '');
    final secondClient = adb.NativeAdbClient(secondApi, '');
    final original = DeviceConnection(client: firstClient, device: first);
    final replacement = DeviceConnection(client: secondClient, device: second);
    final executor = AdbFileExecutor(
      localFiles: firstClient.services,
      resolveConnection: (id) async => id == 'first' ? original : replacement,
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    final firstRead = expectLater(
      executor.stat(
        'first',
        '/first',
        local: false,
        cancellation: FileCancellation(),
      ),
      throwsA(isA<FileFailure>()),
    );
    final secondRead = expectLater(
      executor.stat(
        'second',
        '/second',
        local: false,
        cancellation: FileCancellation(),
      ),
      throwsA(isA<FileFailure>()),
    );
    await Future.wait([firstApi.reading.future, secondApi.reading.future]);
    await expectLater(executor.close(), throwsA(isA<FileFailure>()));
    expect(firstApi.closed, isNotEmpty);
    expect(secondApi.closed, isNotEmpty);
    await expectLater(
      executor.beginRead('first', cancellation: FileCancellation()),
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await expectLater(
      executor.beginMutation('second', cancellation: FileCancellation()),
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await expectLater(
      executor.stat(
        'first',
        '/late',
        local: false,
        cancellation: FileCancellation(),
      ),
      throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    firstApi.rejectClose = false;
    secondApi.rejectClose = false;
    await executor.close();
    await Future.wait([firstRead, secondRead]);
    await executor.close();
    expect(firstApi.calls, hasLength(1));
    expect(secondApi.calls, hasLength(1));
    expect(firstApi.closed.toSet(), {'worker-1'});
    expect(secondApi.closed.toSet(), {'worker-1'});
  });

  for (final copying in [false, true]) {
    test(
      '普通${copying ? '复制' : '读取'}取消遇阻塞next与关闭失败及时报错，原读取由同owner重试排空',
      () async {
        final api = Api()
          ..rejectClose = true
          ..blockCopyOnly = copying
          ..blockedNext = Completer<adb.AdbFileExecutionEvent?>();
        final client = adb.NativeAdbClient(api, '');
        final original = DeviceConnection(client: client, device: first);
        final executor = AdbFileExecutor(
          localFiles: client.services,
          resolveConnection: (_) async => original,
          fileScopeId: 'scope',
          fileScopeKey: 'file-execution-fixture',
        );
        final cancellation = FileCancellation();
        final result = copying
            ? executor.copy(
                'device',
                '/remote',
                '/part',
                push: false,
                expected: expected(),
                cancellation: cancellation,
                onProgress: (_) {},
              )
            : executor.stat(
                'device',
                '/remote',
                local: false,
                cancellation: cancellation,
              );
        final failed = expectLater(
          result,
          throwsA(isA<FileExecutionCleanupFailure>()),
        );
        await api.reading.future;
        cancellation.cancel();
        await failed;
        // 公开调用已经失败，但原 next 仍未返回，不能据此丢弃原资源。
        expect(api.blockedNext!.isCompleted, isFalse);
        expect(api.calls, hasLength(copying ? 2 : 1));
        await expectLater(
          executor.stopForConnection(original),
          throwsA(isA<FileFailure>()),
        );
        api.rejectClose = false;
        await executor.stopForConnection(original);
        expect(api.blockedNext!.isCompleted, isTrue);
        expect(api.calls, hasLength(copying ? 2 : 1));
        expect(
          api.closed.toSet(),
          copying ? {'worker-1', 'worker-2'} : {'worker-1'},
        );
      },
    );
  }

  test('预览批次一次固定连接，后继stat复制提交不重新选择同名设备', () async {
    final api = Api();
    final client = adb.NativeAdbClient(api, '');
    var current = first;
    var resolutions = 0;
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async {
        resolutions++;
        return DeviceConnection(client: client, device: current);
      },
      fileScopeId: 'scope',
      fileScopeKey: 'file-execution-fixture',
    );
    final batch = await executor.beginRead(
      'device',
      cancellation: FileCancellation(),
    );
    final stamp = await batch.stat('/remote');
    current = second;
    expect(
      await batch.copy('/remote', '/part', expected: stamp, onProgress: (_) {}),
      7,
    );
    await batch.commit('/part', '/target');
    await batch.close();
    expect(resolutions, 1);
    expect(api.calls.every((call) => call.$1 == first.id), isTrue);
    expect(api.calls.last.$2.kind, adb.AdbFileExecutionKind.commit);
    expect(api.calls.last.$2.partId, 'exact-part');
    expect(
      api.calls.where(
        (call) => call.$2.kind == adb.AdbFileExecutionKind.releasePart,
      ),
      isEmpty,
    );
    expect(() => batch.stat('/late'), throwsA(isA<FileFailure>()));
  });

  test('pull uses final count and commits the exact part on its original connection', () async {
    final api = Api();
    final client = adb.NativeAdbClient(api, '');
    var current = first;
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async =>
          DeviceConnection(client: client, device: current),
      fileScopeId: 'file-scope',
      fileScopeKey: 'file-execution-fixture',
    );
    final progress = <int>[];
    expect(
      await executor.copy(
        'business',
        '/remote',
        '/part',
        push: false,
        expected: expected(),
        cancellation: FileCancellation(),
        onProgress: progress.add,
      ),
      7,
    );
    expect(progress, [2]);
    current = second;
    expect(
      await executor.mutate(
        'business',
        'commit',
        '/part',
        destination: '/saved',
        local: true,
        cancellation: FileCancellation(),
      ),
      'atomicNoReplace',
    );
    expect(api.calls.map((call) => call.$2.kind), [
      adb.AdbFileExecutionKind.stat,
      adb.AdbFileExecutionKind.copy,
      adb.AdbFileExecutionKind.commit,
    ]);
    expect(api.calls.last.$1, 'original');
    expect(api.calls.last.$2.partId, 'exact-part');
    expect(api.calls.every((call) => call.$2.scopeId == 'file-scope'), isTrue);
    await expectLater(
      executor.mutate(
        'business',
        'commit',
        '/part',
        destination: '/saved',
        local: true,
        cancellation: FileCancellation(),
      ),
      throwsA(
        isA<FileFailure>().having((e) => e.code, 'code', 'source_changed'),
      ),
    );
    expect(
      await executor.mutate(
        'business',
        'releasePart',
        '/part',
        local: true,
        cancellation: FileCancellation(),
      ),
      'released',
    );
    expect(api.closed.length, 3);
  });

  test('microsecond snapshot is checked before upgrading to native nanosecond transfer checks', () async {
    final api = Api();
    final client = adb.NativeAdbClient(api, '');
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async =>
          DeviceConnection(client: client, device: first),
      fileScopeId: 'scope-test',
      fileScopeKey: 'file-execution-fixture',
    );
    expect(
      await executor.copy(
        'business',
        '/source',
        '/remote-part',
        push: true,
        expected: expected(nanos: 123456000, resolution: 1000),
        cancellation: FileCancellation(),
        onProgress: (_) {},
      ),
      7,
    );
    final copy = api.calls.single.$2;
    expect(copy.expected!.modifiedNanos, 123456789);
    expect(copy.expected!.nanosecondPrecision, isTrue);
    await expectLater(
      executor.copy(
        'business',
        '/source',
        '/remote-part2',
        push: true,
        expected: expected(nanos: 123455000, resolution: 1000),
        cancellation: FileCancellation(),
        onProgress: (_) {},
      ),
      throwsA(
        isA<FileFailure>().having((e) => e.code, 'code', 'source_changed'),
      ),
    );
    expect(api.calls.length, 1);
  });

  test('legacy exact snapshot cannot silently downgrade to seconds', () async {
    final api = Api();
    final client = adb.NativeAdbClient(api, '');
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async =>
          DeviceConnection(client: client, device: first),
      fileScopeId: 'scope-test',
      fileScopeKey: 'file-execution-fixture',
    );
    await expectLater(
      executor.copy(
        'business',
        '/remote',
        '/part',
        push: false,
        expected: expected(resolution: 1),
        cancellation: FileCancellation(),
        onProgress: (_) {},
      ),
      throwsA(
        isA<FileFailure>().having((e) => e.code, 'code', 'source_changed'),
      ),
    );
    expect(api.calls.single.$2.kind, adb.AdbFileExecutionKind.stat);
  });

  test(
    'late admitted cancellation drains the worker before returning failure',
    () async {
      final api = Api()..delayed = Completer<String>();
      final client = adb.NativeAdbClient(api, '');
      final executor = AdbFileExecutor(
        localFiles: client.services,
        resolveConnection: (_) async =>
            DeviceConnection(client: client, device: first),
        fileScopeId: 'scope-test',
        fileScopeKey: 'file-execution-fixture',
      );
      final cancellation = FileCancellation();
      final mutation = executor.mutate(
        'business',
        'mkdir',
        '/remote',
        cancellation: cancellation,
      );
      final failed = expectLater(
        mutation,
        throwsA(isA<FileFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
      await api.admission.future;
      cancellation.cancel();
      api.delayed!.complete('late-worker');
      await failed;
      expect(api.closed, ['late-worker']);
    },
  );

  test('不同身份客户端的文件操作与暂存提交都使用原连接，不能落到本机客户端或后继', () async {
    final localApi = Api(), originalApi = Api(), replacementApi = Api();
    final local = adb.NativeAdbClient(localApi, '/local-key');
    final original = adb.NativeAdbClient(originalApi, '/original-key');
    final replacement = adb.NativeAdbClient(replacementApi, '/replacement-key');
    var connection = DeviceConnection(client: original, device: first);
    final executor = AdbFileExecutor(
      localFiles: local.services,
      resolveConnection: (_) async => connection,
      fileScopeId: 'scope-test',
      fileScopeKey: 'file-execution-fixture',
    );
    await executor.copy(
      'device',
      '/remote',
      '/part',
      push: false,
      expected: expected(),
      cancellation: FileCancellation(),
      onProgress: (_) {},
    );
    connection = DeviceConnection(client: replacement, device: second);
    await executor.mutate(
      'device',
      'commit',
      '/part',
      destination: '/destination',
      local: true,
      cancellation: FileCancellation(),
    );
    expect(localApi.calls, isEmpty);
    expect(replacementApi.calls, isEmpty);
    expect(originalApi.calls.map((call) => call.$1), [
      'original',
      'original',
      'original',
    ]);
    expect(originalApi.calls.last.$2.partId, 'exact-part');
  });

  test('missing mutation terminal stays unknown', () async {
    final api = Api()..unknownMutation = true;
    final client = adb.NativeAdbClient(api, '');
    final executor = AdbFileExecutor(
      localFiles: client.services,
      resolveConnection: (_) async =>
          DeviceConnection(client: client, device: first),
      fileScopeId: 'scope-test',
      fileScopeKey: 'file-execution-fixture',
    );
    await expectLater(
      executor.mutate(
        'business',
        'rename',
        '/source',
        destination: '/target',
        cancellation: FileCancellation(),
      ),
      throwsA(
        isA<FileFailure>().having((e) => e.code, 'code', 'result_unknown'),
      ),
    );
    expect(api.closed, ['worker-1']);
  });

  test(
    'timestamp precision survives journals and legacy data remains exact',
    () {
      final stamp = expected(nanos: 123000, resolution: 1000);
      expect(
        FileStamp.fromJson(
          jsonDecode(jsonEncode(stamp.toJson())) as Map<String, dynamic>,
        ),
        stamp,
      );
      final legacy = Map<String, Object?>.from(stamp.toJson())
        ..remove('modifiedResolutionNanos');
      expect(FileStamp.fromJson(legacy).modifiedResolutionNanos, 1);
      expect(FileStamp.fromJson(legacy), isNot(stamp));
      expect(
        () => FileStamp.fromJson({...legacy, 'modifiedResolutionNanos': 0}),
        throwsFormatException,
      );
    },
  );
}
