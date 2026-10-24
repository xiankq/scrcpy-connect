import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实 FRB 取消官方选择握手，等待实际 socket 关闭且不登记迟到连接', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>(), eof = Completer<void>();
    final sockets = <Socket>[];
    final observers = <StreamSubscription<List<int>>>[];
    final accepting = server.listen((socket) {
      sockets.add(socket);
      final bytes = <int>[];
      observers.add(
        socket.listen(
          (chunk) {
            bytes.addAll(chunk);
            if (bytes.length < 4) return;
            final length = int.parse(
              ascii.decode(bytes.take(4).toList()),
              radix: 16,
            );
            if (bytes.length < 4 + length || received.isCompleted) return;
            expect(
              ascii.decode(bytes.sublist(4)),
              'host:tport:serial:blocked-fixture',
            );
            received.complete();
            // 保留真实 smart socket 等待；取消必须关闭它，不能靠夹具主动退出。
          },
          onDone: () {
            if (!eof.isCompleted) eof.complete();
          },
        ),
      );
    });
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      for (final observer in observers) {
        await observer.cancel();
      }
      await accepting.cancel();
      await server.close();
    });
    final api = await createNativeAdbApi();
    final handshakes = api as NativeAdbHandshakeApi;
    final id = await handshakes.createHandshake();
    addTearDown(() => handshakes.closeHandshake(id));
    final opening = api.connectServer(
      '127.0.0.1:${server.port}',
      'blocked-fixture',
      30000,
      handshakeId: id,
    );
    final rejected = expectLater(opening, throwsA(isA<AdbException>()));
    await received.future.timeout(const Duration(seconds: 3));
    await handshakes.cancelHandshake(id);
    await handshakes.closeHandshake(id);
    await rejected;
    await eof.future.timeout(const Duration(seconds: 3));
    expect(
      (await api.devices()).where(
        (device) => device.serial == 'blocked-fixture',
      ),
      isEmpty,
    );
  });

  test('真实 FRB 撤销未开始的握手后，迟到启动不接触官方端点', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final accepting = server.listen(sockets.add);
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await accepting.cancel();
      await server.close();
    });
    final api = await createNativeAdbApi();
    final handshakes = api as NativeAdbHandshakeApi;
    final id = await handshakes.createHandshake();
    await handshakes.closeHandshake(id);
    await expectLater(
      api.connectServer(
        '127.0.0.1:${server.port}',
        'revoked-fixture',
        30000,
        handshakeId: id,
      ),
      throwsA(isA<AdbException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sockets, isEmpty);
    await handshakes.closeHandshake(id);
  });
}
