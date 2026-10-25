import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NativeAdbApi api;

  setUpAll(() async {
    api = await createNativeAdbApi();
  });

  test('真实 FRB 把本机已关闭端口映射为 connection_refused', () async {
    final endpoint = await _closedEndpoint();
    await expectLater(
      _connectServer(api, endpoint),
      throwsA(_code('connection_refused')),
    );
  });

  test('真实 FRB 在途握手取消返回 cancelled，并排空实际 socket', () async {
    final server = await _SilentServer.open();
    addTearDown(server.close);
    final handshakes = api as NativeAdbHandshakeApi;
    final id = await handshakes.createHandshake();
    addTearDown(() => handshakes.closeHandshake(id));
    final result = expectLater(
      _connectServer(api, server.endpoint, handshakeId: id),
      throwsA(_code('cancelled')),
    );
    await server.requestReceived.future.timeout(const Duration(seconds: 5));
    await handshakes.cancelHandshake(id);
    await result;
    await handshakes.closeHandshake(id);
    await server.peerClosed.future.timeout(const Duration(seconds: 5));
  });
}

Matcher _code(String code) =>
    isA<AdbException>().having((error) => error.code, 'code', code);

/// 短暂预留独立环回端口后关闭，不依赖公网路由或用户的 ADB 服务。
Future<String> _closedEndpoint() async {
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final endpoint = '127.0.0.1:${reservation.port}';
  await reservation.close();
  return endpoint;
}

/// 若测试意外收到成功，也必须精确回收该连接，不能让失败断言遗留资源。
Future<void> _connectServer(
  NativeAdbApi api,
  String endpoint, {
  int timeoutMs = 5000,
  String? handshakeId,
}) async {
  final device = await api.connectServer(
    endpoint,
    'connection-error-fixture',
    timeoutMs,
    handshakeId: handshakeId,
  );
  await api.disconnect(device.id);
}

/// 接收并读取真实请求但不应答，分别暴露请求到达与对端实际关闭边界。
final class _SilentServer {
  _SilentServer._(this._server) {
    _accepting = _server.listen((socket) {
      _sockets.add(socket);
      _readers.add(
        socket.listen(
          (_) {
            if (!requestReceived.isCompleted) requestReceived.complete();
          },
          onDone: () {
            if (!peerClosed.isCompleted) peerClosed.complete();
          },
          onError: (Object error) {
            if (!requestReceived.isCompleted) {
              requestReceived.completeError(error);
            }
            if (!peerClosed.isCompleted) peerClosed.complete();
          },
        ),
      );
    });
  }

  static Future<_SilentServer> open() async =>
      _SilentServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  late final StreamSubscription<Socket> _accepting;
  final _sockets = <Socket>[];
  final _readers = <StreamSubscription<List<int>>>[];
  final requestReceived = Completer<void>();
  final peerClosed = Completer<void>();
  String get endpoint => '127.0.0.1:${_server.port}';

  Future<void> close() async {
    await _accepting.cancel();
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
    for (final reader in _readers) {
      await reader.cancel();
    }
  }
}
