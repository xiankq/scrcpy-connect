import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/flutter_adb.dart';
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
}

class FakeServiceApi implements NativeAdbApi {
  final events = <Object>[];
  final inputs = <AdbServiceInput>[];
  final cancelled = <String>[];
  final waiting = Completer<void>();
  Completer<NativeAdbEvent?>? pending;
  AdbServiceRequest? request;
  AdbSyncRequest? syncRequest;
  AdbReverseRequest? reverseRequest;
  Future<void>? writeGate;
  void Function(AdbServiceInput)? onWrite;
  int reads = 0;
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
    return 'operation';
  }

  @override
  Future<String> sync(String id, AdbSyncRequest value, int timeoutMs) async {
    syncRequest = value;
    return 'operation';
  }

  @override
  Future<String> reverse(
    String id,
    AdbReverseRequest value,
    int timeoutMs,
  ) async {
    reverseRequest = value;
    return 'operation';
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
    if (pending != null) fail(const AdbException('cancelled'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
