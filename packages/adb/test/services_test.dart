import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

const device = AdbDevice(id: 'fixed', serial: 'serial', state: 'device');
NativeAdbEvent event(
  String kind, {
  bool done = false,
  List<int> bytes = const [],
  AdbServiceFacts? facts,
  int transferred = 0,
}) => NativeAdbEvent(
  kind: kind,
  bytes: Uint8List.fromList(bytes),
  done: done,
  facts: facts,
  transferred: transferred,
);

void main() {
  test('路径和 SYNC 请求在解析连接前固定字节，外部视图不能修改目标', () async {
    final source = Uint8List.fromList([47, 255, 97]);
    final path = AdbPath.bytes(source);
    final request = AdbSyncRequest(AdbSyncKind.stat, source);
    final resolved = Completer<AdbDevice>();
    final resolving = Completer<void>();
    final api = FakeServiceApi();
    final services = AdbServices(() => api, (_) {
      resolving.complete();
      return resolved.future;
    }, () {});
    api.emit(
      event(
        'stat',
        facts: const AdbServiceFacts(metadata: AdbFileMetadata(0x8000, 1, 0)),
      ),
    );
    api.emit(event('sync', done: true));
    final stat = services.sync(device).stat(path);
    await resolving.future;
    source[2] = 98;
    expect(() => path.bytes[2] = 99, throwsUnsupportedError);
    expect(() => request.path[2] = 99, throwsUnsupportedError);
    expect(request.path, [47, 255, 97]);
    resolved.complete(device);
    expect((await stat).size, 1);
    expect(api.syncRequest!.path, [47, 255, 97]);
    await services.close();
  });

  for (final completed in [true, false]) {
    test(
      'multi-chunk response ${completed ? 'waits for done' : 'rejects truncated EOF'}',
      () async {
        final api = FakeServiceApi();
        api.emit(event('data', bytes: [1, 2]));
        api.emit(event('data', bytes: [3, 4]));
        final response = NativeAdbClient(
          api,
          '',
        ).services.serviceResponse(device, 'host:test');
        final result = completed
            ? expectLater(response, completion([1, 2, 3, 4]))
            : expectLater(
                response,
                throwsA(
                  isA<AdbException>().having(
                    (e) => e.code,
                    'code',
                    'result_unknown',
                  ),
                ),
              );
        await api.waiting.future;
        if (completed) {
          api.emit(event('done', done: true));
        } else {
          api.pending!.complete(null);
          api.pending = null;
        }
        await result;
        expect(api.reads, 3);
        expect(api.cancelled, ['operation']);
      },
    );
  }

  for (final kind in ['data', 'exit']) {
    test(
      'cancelled service reader rejects an already returned $kind receipt',
      () async {
        final api = FakeServiceApi();
        final token = AdbCancellation();
        final session = await NativeAdbClient(
          api,
          '',
        ).services.exec(device, 'true', cancellation: token);
        final received = <NativeAdbEvent>[];
        final failed = expectLater(
          session.events.forEach(received.add),
          throwsA(
            isA<AdbException>().having((e) => e.code, 'code', 'cancelled'),
          ),
        );
        await api.waiting.future;
        // 原生读取已经返回，但 await 续体尚未处理；撤销后不能再发布旧事件。
        api.emit(event(kind, done: kind == 'exit', bytes: [1]));
        token.cancel();
        await failed;
        expect(received, isEmpty);
        expect(api.cancelled, ['operation']);
      },
    );
  }

  test('sync stat waits for the terminal receipt after metadata', () async {
    final api = FakeServiceApi();
    api.emit(
      event(
        'stat',
        facts: const AdbServiceFacts(metadata: AdbFileMetadata(0x8000, 7, 1)),
      ),
    );
    var completed = false;
    final stat = NativeAdbClient(api, '').services
        .sync(device)
        .stat(AdbPath('/file'))
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse, reason: '元数据本身不是执行完成回执');
    api.emit(event('sync', done: true));
    expect((await stat).size, 7);
    expect(api.cancelled, ['operation']);
  });

  for (final kind in ['stat', 'list']) {
    test('sync $kind rejects EOF without a terminal receipt', () async {
      final api = FakeServiceApi();
      final sync = NativeAdbClient(api, '').services.sync(device);
      final reading = kind == 'stat'
          ? sync.stat(AdbPath('/file'))
          : sync.list(AdbPath('/')).toList();
      final failed = expectLater(
        reading,
        throwsA(
          isA<AdbException>().having((e) => e.code, 'code', 'result_unknown'),
        ),
      );
      await api.waiting.future;
      api.pending!.complete(null);
      api.pending = null;
      await failed;
      expect(api.cancelled, ['operation']);
    });
  }

  test('duplex input progresses while output is blocked and write ownership is bounded', () async {
    final api = FakeServiceApi();
    final service = await NativeAdbClient(
      api,
      '',
    ).services.open(device, 'exec:cat');
    final events = StreamIterator(service.events);
    final read = events.moveNext();
    final gate = Completer<void>();
    api.writeGate = gate.future;
    final write = service.write(Uint8List.fromList([0, 255]));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      service.write(Uint8List(1)),
      throwsA(isA<AdbException>()),
    );
    api.emit(event('data', bytes: [0, 255]));
    expect(await read, isTrue);
    expect(events.current.bytes, [0, 255]);
    expect(api.reads, 1);
    gate.complete();
    await write;
    expect(api.inputs.single.bytes, [0, 255]);
    await events.cancel();
    expect(api.cancelled, ['operation']);
    await expectLater(
      service.write(Uint8List(1)),
      throwsA(isA<AdbException>()),
    );
  });

  test(
    'client close releases service handles without closing another connection',
    () async {
      final api = FakeServiceApi();
      final client = NativeAdbClient(api, '');
      final session = await client.services.open(device, 'exec:cat');
      final pending = session.events.toList();
      final cancelled = expectLater(pending, throwsA(isA<AdbException>()));
      await api.waiting.future;
      await client.close();
      await cancelled;
      expect(api.cancelled, ['operation']);
    },
  );
  test(
    'PTY control and raw byte paths retain typed protocol semantics',
    () async {
      final api = FakeServiceApi();
      final services = NativeAdbClient(api, '').services;
      final shell = await services.shell(device, 'cat', pty: true);
      expect(api.request!.kind, AdbServiceKind.shellPty);
      await shell.resize(24, 80);
      await shell.closeStdin();
      expect(api.inputs.map((i) => i.kind), [
        AdbInputKind.resize,
        AdbInputKind.closeStdin,
      ]);
      await shell.close();
      api.events.clear();
      api.emit(
        event(
          'sync',
          done: true,
          facts: const AdbServiceFacts(
            metadata: AdbFileMetadata(0xa1ff, 0x100000001, -10),
          ),
        ),
      );
      final stat = await services.sync(device).lstat(AdbPath.bytes([47, 255]));
      expect(stat.size, 0x100000001);
      expect(stat.modifiedSeconds, -10);
      expect(stat.isSymlink, isTrue);
      expect(api.syncRequest!.path, [47, 255]);
      expect(api.syncRequest!.kind, AdbSyncKind.lstat);
    },
  );

  test(
    'directory pages preserve non UTF8 names and only pull on demand',
    () async {
      final api = FakeServiceApi();
      api.emit(
        event(
          'entries',
          facts: AdbServiceFacts(
            entries: [
              AdbDirectoryEntry(
                Uint8List.fromList([255]),
                const AdbFileMetadata(0x8000, 1, 2),
              ),
            ],
          ),
        ),
      );
      api.emit(event('sync', done: true));
      final entries = StreamIterator(
        NativeAdbClient(api, '').services.sync(device).list(AdbPath('/')),
      );
      expect(await entries.moveNext(), isTrue);
      expect(entries.current.name, [255]);
      expect(api.reads, 1);
      await entries.cancel();
      expect(api.cancelled, ['operation']);
    },
  );

  test(
    'streaming push splits input at 64KiB and returns acknowledged count',
    () async {
      final api = FakeServiceApi();
      api.onWrite = (input) {
        if (input.kind == AdbInputKind.finish) {
          api.emit(event('sync', done: true, transferred: 140000));
        }
      };
      final count = await NativeAdbClient(api, '').services
          .sync(device)
          .push(
            AdbPath('/file'),
            Stream.value(List.filled(140000, 255)),
            compression: AdbCompression.zstd,
          );
      expect(count, 140000);
      expect(
        api.inputs
            .where((i) => i.kind == AdbInputKind.bytes)
            .map((i) => i.bytes.length),
        [65536, 65536, 8928],
      );
      expect(api.syncRequest!.compression, AdbCompression.zstd);
    },
  );

  test('owned push retains a late session for exact close retry without closing a parallel shell', () async {
    final api = FakeServiceApi();
    final services = NativeAdbClient(api, '').services;
    final shell = await services.exec(device, 'cat');
    api.serviceGate = Completer<String>();
    final sourcePath = Uint8List.fromList([47, 255]);
    final path = AdbPath.bytes(sourcePath);
    final opening = services
        .sync(device)
        .openPush(
          path,
          maxBytes: 3,
          permissions: 384,
          modifiedSeconds: 0xffffffff,
          compression: AdbCompression.zstd,
        );
    sourcePath[1] = 65;
    expect(() => path.bytes[1] = 65, throwsUnsupportedError);
    await api.syncStarted.future;
    // 模拟创建尚未返回时取消；仍需取得并保存迟到的精确会话。
    final cancellation = AdbCancellation()..cancel();
    api.serviceGate!.complete('late-upload');
    final upload = await opening;
    expect(api.syncRequest!.path, [47, 255]);
    expect(api.syncRequest!.maxBytes, 3);
    expect(api.syncRequest!.permissions, 384);
    expect(api.syncRequest!.modifiedSeconds, 0xffffffff);
    expect(api.syncRequest!.compression, AdbCompression.zstd);
    api.cancelFailures = 1;
    late Future<void> firstClose;
    final unwatch = cancellation.onCancel(() {
      firstClose = upload.close();
    });
    await expectLater(firstClose, throwsStateError);
    expect(api.cancelled, ['late-upload']);
    await shell.write(Uint8List.fromList([1]));
    await upload.close();
    await shell.write(Uint8List.fromList([2]));
    expect(api.cancelled, ['late-upload', 'late-upload']);
    expect(api.inputs.map((input) => input.bytes.single), [1, 2]);
    unwatch();
    await shell.close();
    await services.close();
    expect(api.cancelled, ['late-upload', 'late-upload', 'operation']);
  });

  for (final remoteFailure in [false, true]) {
    test(
      'owned push ${remoteFailure ? 'error' : 'done'} retains failed cleanup for exact retry',
      () async {
        final api = FakeServiceApi();
        final services = NativeAdbClient(api, '').services;
        final upload = await services.sync(device).openPush(AdbPath('/file'));
        api.cancelFailures = 1;
        if (remoteFailure) {
          api.fail(const AdbException('permission_denied'));
        } else {
          api.emit(event('sync', done: true, transferred: 3));
        }
        final received = <NativeAdbEvent>[];
        // done 只是远端结果；事件流 finally 的关闭首败仍须报告。
        await expectLater(
          upload.events.forEach(received.add),
          throwsStateError,
        );
        expect(
          received.map((value) => value.transferred),
          remoteFailure ? isEmpty : [3],
        );
        expect(api.cancelled, ['operation']);
        await upload.close();
        await services.close();
        expect(api.cancelled, ['operation', 'operation']);
      },
    );
  }

  for (final request in <String, Future<AdbServiceSession> Function(AdbSync)>{
    'negative budget': (sync) => sync.openPush(AdbPath('/file'), maxBytes: -1),
    'negative permissions': (sync) =>
        sync.openPush(AdbPath('/file'), permissions: -1),
    'wide permissions': (sync) =>
        sync.openPush(AdbPath('/file'), permissions: 512),
    'negative timestamp': (sync) =>
        sync.openPush(AdbPath('/file'), modifiedSeconds: -1),
    'wide timestamp': (sync) =>
        sync.openPush(AdbPath('/file'), modifiedSeconds: 0x100000000),
    'zero timeout': (sync) =>
        sync.openPush(AdbPath('/file'), timeout: Duration.zero),
  }.entries) {
    test('owned push rejects ${request.key} before native creation', () async {
      final api = FakeServiceApi();
      final sync = NativeAdbClient(api, '').services.sync(device);
      await expectLater(
        Future<AdbServiceSession>.sync(() => request.value(sync)),
        throwsArgumentError,
      );
      expect(api.syncRequest, isNull);
      expect(api.cancelled, isEmpty);
    });
  }

  test(
    'remote push failure cancels a stalled producer and propagates its failure',
    () async {
      final api = FakeServiceApi();
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      final pushing = NativeAdbClient(
        api,
        '',
      ).services.sync(device).push(AdbPath('/file'), source.stream);
      final assertion = expectLater(
        pushing,
        throwsA(
          predicate<Object>((e) => e.toString().contains('permission_denied')),
        ),
      );
      await api.waiting.future;
      api.fail(const AdbException('permission_denied'));
      await assertion.timeout(const Duration(seconds: 2));
      await cancelled.future;
      await source.close();
    },
  );

  test(
    'streaming producer failures retain identity and stop the native worker',
    () async {
      final api = FakeServiceApi();
      final failure = StateError('source_read_failed');
      final push = NativeAdbClient(api, '').services
          .sync(device)
          .push(AdbPath('/file'), Stream<List<int>>.error(failure));
      await expectLater(push, throwsA(same(failure)));
      expect(api.cancelled, ['operation']);
    },
  );

  test(
    'reverse is owned and cancellation interrupts a blocked acknowledgement',
    () async {
      final api = FakeServiceApi();
      final token = AdbCancellation();
      final reversing = NativeAdbClient(api, '').services.reverse(
        device,
        AdbReverseSocket.tcp(0),
        InternetAddress.loopbackIPv4,
        12345,
        cancellation: token,
      );
      final assertion = expectLater(reversing, throwsA(isA<AdbException>()));
      await api.waiting.future;
      token.cancel();
      await assertion;
      expect(api.reverseRequest!.hostAddress, '127.0.0.1:12345');
      expect(api.cancelled, ['operation']);
    },
  );
  test('close waits for late service registration and retains failed cancellation for retry', () async {
    final api = FakeServiceApi()
      ..serviceGate = Completer<String>()
      ..cancelFailures = 2;
    final client = NativeAdbClient(api, '');
    final opening = client.services.exec(device, 'true');
    final rejected = expectLater(opening, throwsStateError);
    await api.serviceStarted.future;
    var closed = false;
    final closing = client.close();
    final failedClose = expectLater(
      closing,
      throwsStateError,
    ).then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    api.serviceGate!.complete('late-service');
    await rejected;
    await failedClose;
    expect(api.cancelled, ['late-service', 'late-service']);
    await client.close();
    expect(api.cancelled, ['late-service', 'late-service', 'late-service']);
    await expectLater(
      client.services.exec(device, 'new'),
      throwsA(isA<AdbException>()),
    );
  });

  test(
    'close during device resolution prevents a later remote service start',
    () async {
      final api = FakeServiceApi();
      final client = NativeAdbClient(api, '');
      final opening = client.services.exec(device, 'must not run');
      final rejected = expectLater(opening, throwsA(isA<AdbException>()));
      await client.close();
      await rejected;
      expect(api.request, isNull);
    },
  );

  test('cancellation cleanup failure is observed by explicit retry without an unhandled future', () async {
    final api = FakeServiceApi()..cancelFailures = 1;
    final client = NativeAdbClient(api, '');
    final token = AdbCancellation();
    await client.services.exec(device, 'true', cancellation: token);
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    await client.close();
    expect(api.cancelled, ['operation', 'operation']);
  });
  for (final entry in <String, Future<Object?> Function(AdbServices)>{
    'sync': (services) => services.sync(device).stat(AdbPath('/file')),
    'owned push': (services) =>
        services.sync(device).openPush(AdbPath('/file')),
    'reverse': (services) => services.reverseList(device),
  }.entries) {
    test(
      'close tracks late ${entry.key} registration before returning',
      () async {
        final api = FakeServiceApi()..serviceGate = Completer<String>();
        final services = NativeAdbClient(api, '').services;
        final opening = entry.value(services);
        final failed = expectLater(opening, throwsA(isA<AdbException>()));
        await api.serviceStarted.future;
        var closed = false;
        final closing = services.close().then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        api.serviceGate!.complete('late-${entry.key}');
        await failed;
        await closing;
        expect(api.cancelled, ['late-${entry.key}']);
      },
    );
  }
}

class FakeServiceApi implements NativeAdbApi {
  final events = <Object>[];
  final inputs = <AdbServiceInput>[];
  final cancelled = <String>[];
  final waiting = Completer<void>();
  Completer<NativeAdbEvent?>? pending;
  AdbServiceRequest? request;
  AdbSyncRequest? syncRequest;
  final syncStarted = Completer<void>();
  AdbReverseRequest? reverseRequest;
  Future<void>? writeGate;
  void Function(AdbServiceInput)? onWrite;
  int reads = 0;
  int cancelFailures = 0;
  Completer<String>? serviceGate;
  final serviceStarted = Completer<void>();
  void emit(NativeAdbEvent value) {
    if (pending case final p?) {
      pending = null;
      p.complete(value);
    } else {
      events.add(value);
    }
  }

  void fail(Object error) {
    if (pending case final p?) {
      pending = null;
      p.completeError(error);
    } else {
      events.add(error);
    }
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    reads++;
    if (events.isNotEmpty) {
      final value = events.removeAt(0);
      if (value is NativeAdbEvent) return value;
      throw value;
    }
    pending = Completer<NativeAdbEvent?>();
    if (!waiting.isCompleted) waiting.complete();
    return pending!.future;
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest value,
    int timeoutMs,
  ) async {
    request = value;
    if (!serviceStarted.isCompleted) serviceStarted.complete();
    return serviceGate?.future ?? 'operation';
  }

  @override
  Future<String> sync(String id, AdbSyncRequest value, int timeoutMs) async {
    syncRequest = value;
    if (!syncStarted.isCompleted) syncStarted.complete();
    if (!serviceStarted.isCompleted) serviceStarted.complete();
    return serviceGate?.future ?? 'operation';
  }

  @override
  Future<String> reverse(
    String id,
    AdbReverseRequest value,
    int timeoutMs,
  ) async {
    reverseRequest = value;
    if (!serviceStarted.isCompleted) serviceStarted.complete();
    return serviceGate?.future ?? 'operation';
  }

  @override
  Future<void> write(String id, AdbServiceInput value) async {
    inputs.add(value);
    await writeGate;
    onWrite?.call(value);
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    if (cancelFailures > 0) {
      cancelFailures--;
      throw StateError('cancel unconfirmed');
    }
    if (pending != null) fail(const AdbException('cancelled'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
