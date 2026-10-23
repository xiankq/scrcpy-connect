import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

const device = AdbDevice(id: 'connection', serial: 'target', state: 'device');

void main() {
  test(
    'typed shell retains binary channels and pulls one event at a time',
    () async {
      final api = _Api();
      final client = NativeAdbClient(api, '/owned/key');
      final iterator = StreamIterator(client.shell(device, 'command'));
      expect(api.reads, 0);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.bytes, [0, 255]);
      expect(api.reads, 1);
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, 1, reason: 'paused Dart consumption must not prefetch');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.channel, AdbShellChannel.stderr);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.exitCode, 7);
      expect(await iterator.moveNext(), isFalse);
      expect(api.cancelled, ['operation']);
    },
  );
  test(
    'explicit cancellation wakes a blocked native read and disposes handle',
    () async {
      final api = _Api()..blocked = Completer<NativeAdbEvent?>();
      final token = AdbCancellation();
      final iterator = StreamIterator(
        NativeAdbClient(
          api,
          '/owned/key',
        ).shell(device, 'sleep', cancellation: token),
      );
      final pending = iterator.moveNext();
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(pending, throwsA(isA<AdbException>()));
      expect(api.cancelled, isNotEmpty);
    },
  );
  test(
    'closing native client is idempotent and forbids future operations',
    () async {
      final api = _Api();
      final client = NativeAdbClient(api, '/owned/key');
      await client.close();
      await client.close();
      expect(
        api.closes,
        0,
        reason: 'Closing one client must not call a global registry close',
      );
      expect(() => client.devices(), throwsA(isA<AdbException>()));
    },
  );
  test('closing a client disconnects only its own connections', () async {
    final api = _Api();
    final first = NativeAdbClient(api, '/first');
    final second = NativeAdbClient(api, '/second');
    final a = await first.connect('first');
    final b = await second.connect('second');
    await first.close();
    expect(api.disconnected, [a.id]);
    expect(api.disconnected, isNot(contains(b.id)));
    await second.close();
    expect(api.disconnected, [a.id, b.id]);
    expect(api.closes, 0);
  });
  test('close waits for a late connect to release its handle', () async {
    final api = _Api()..opening = Completer<AdbDevice>();
    final client = NativeAdbClient(api, '/owned');
    final opening = client.connect('late');
    final rejected = expectLater(opening, throwsA(isA<AdbException>()));
    final closing = client.close();
    api.opening!.complete(
      const AdbDevice(id: 'late', serial: 'late', state: 'device'),
    );
    await closing;
    await rejected;
    expect(api.disconnected, ['late']);
  });
  test(
    'missing bundled desktop binary fails without a PATH fallback',
    () async {
      if (Platform.isAndroid || Platform.isIOS) return;
      final root = await Directory.systemTemp.createTemp(
        'flutter-adb-missing-',
      );
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        FlutterAdb.prepare(dataDirectory: root, binaryDirectory: root),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

class _Api implements NativeAdbApi {
  int reads = 0, closes = 0;
  final disconnected = <String>[];
  Completer<AdbDevice>? opening;
  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs,
  ) async => opening == null
      ? AdbDevice(id: address, serial: address, state: 'device')
      : opening!.future;
  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
  }

  final cancelled = <String>[];
  Completer<NativeAdbEvent?>? blocked;
  @override
  Future<String> shell(String id, String command, int timeoutMs) async =>
      'operation';
  @override
  Future<NativeAdbEvent?> next(String id) async {
    reads++;
    if (blocked case final pending?) return pending.future;
    return switch (reads) {
      1 => NativeAdbEvent(
        kind: 'stdout',
        bytes: Uint8List.fromList([0, 255]),
        done: false,
      ),
      2 => NativeAdbEvent(
        kind: 'stderr',
        bytes: Uint8List.fromList([101]),
        done: false,
      ),
      3 => NativeAdbEvent(
        kind: 'exit',
        bytes: Uint8List(0),
        done: true,
        exitCode: 7,
      ),
      _ => null,
    };
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    if (blocked case final pending? when !pending.isCompleted) {
      pending.completeError(const AdbException('cancelled'));
    }
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
