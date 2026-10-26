import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../driver/support/weak_network_proxy.dart';

void main() {
  late ServerSocket server;
  late WeakNetworkProxy proxy;
  Socket? client, upstream;
  late StreamSubscription<Socket> accepts;
  late Completer<Socket> connected;

  Future<void> start({
    int uploadRate = 0,
    Duration delay = Duration.zero,
  }) async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    connected = Completer<Socket>();
    accepts = server.listen((socket) => connected.complete(socket));
    proxy = await WeakNetworkProxy.start(
      upstreamHost: '127.0.0.1',
      upstreamPort: server.port,
      uploadBytesPerSecond: uploadRate,
      uploadDelay: delay,
    );
    client = await Socket.connect(InternetAddress.loopbackIPv4, proxy.port);
    upstream = await connected.future;
  }

  tearDown(() async {
    client?.destroy();
    upstream?.destroy();
    await proxy.close().timeout(const Duration(seconds: 3));
    await server.close();
    await accepts.cancel();
    client = upstream = null;
  });

  test(
    'a stalled receiver backpressures the sender while reverse bytes progress',
    () async {
      await start();
      final reverse = Completer<void>();
      final clientReads = client!.listen((bytes) {
        expect(bytes, everyElement(23));
        if (!reverse.isCompleted) reverse.complete();
      });
      addTearDown(clientReads.cancel);

      // 目标暂不订阅读取；载荷大于本机 socket 缓冲，因此接收恢复前，有界代理不能接受整个传输。
      //
      //
      final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 17);
      const total = 32 * 1024 * 1024;
      for (var sent = 0; sent < total; sent += chunk.length) {
        client!.add(chunk);
      }
      var senderFinished = false;
      final sent = client!.flush().then((_) => senderFinished = true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        senderFinished,
        isFalse,
        reason: 'Output buffering must not hide a stalled receiver',
      );
      upstream!.add([23]);
      await upstream!.flush();
      await reverse.future.timeout(const Duration(seconds: 3));

      var received = 0;
      final complete = Completer<void>();
      final targetReads = upstream!.listen((bytes) {
        expect(bytes, everyElement(17));
        received += bytes.length;
        if (received == total) complete.complete();
      });
      addTearDown(targetReads.cancel);
      await sent.timeout(const Duration(seconds: 10));
      await complete.future.timeout(const Duration(seconds: 10));
      expect(received, total);
    },
  );

  test(
    'request half-close preserves the later response in the other direction',
    () async {
      await start();
      final response = client!.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );
      final request = upstream!.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );
      client!.add([1, 2, 3]);
      await client!.close();
      expect(await request.timeout(const Duration(seconds: 3)), [1, 2, 3]);
      // 服务端可能等请求 EOF 后才生成响应。
      upstream!.add([4, 5, 6]);
      await upstream!.close();
      expect(await response.timeout(const Duration(seconds: 3)), [4, 5, 6]);
    },
  );

  test('source EOF flushes the accepted tail before the pair closes', () async {
    await start();
    final received = <int>[];
    final ended = Completer<void>();
    final subscription = upstream!.listen(
      received.addAll,
      onDone: ended.complete,
    );
    addTearDown(subscription.cancel);
    final payload = List<int>.generate(256 * 1024, (i) => i % 251);
    client!.add(payload);
    await client!.close();
    await ended.future.timeout(const Duration(seconds: 5));
    expect(received, payload);
  });

  for (final delay in [Duration.zero, const Duration(minutes: 1)]) {
    test(
      'close interrupts ${delay == Duration.zero ? 'bandwidth' : 'delay'} waits and releases the listener',
      () async {
        await start(uploadRate: 1, delay: delay);
        client!.add(Uint8List(64 * 1024));
        await client!.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final port = proxy.port;
        await proxy.close().timeout(const Duration(seconds: 2));
        await proxy.close();
        // TCP TIME_WAIT may prevent rebinding even after the listener is closed.
        await expectLater(
          Socket.connect(InternetAddress.loopbackIPv4, port),
          throwsA(isA<SocketException>()),
        );
      },
    );
  }

  test('close interrupts a blocked socket flush in both directions', () async {
    await start();
    final chunk = Uint8List(64 * 1024);
    for (var i = 0; i < 512; i++) {
      client!.add(chunk);
      upstream!.add(chunk);
    }
    final writes = [
      client!.flush().then((_) {}, onError: (Object _) {}),
      upstream!.flush().then((_) {}, onError: (Object _) {}),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await proxy.close().timeout(const Duration(seconds: 2));
    await Future.wait(writes).timeout(const Duration(seconds: 2));
  });
}
