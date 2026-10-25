import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  test('真实官方服务器的 already connected 回执不能把未完成握手当作设备连接', () async {
    final root = await Directory.systemTemp.createTemp('adb-inflight-');
    addTearDown(() => root.delete(recursive: true));
    final endpoint = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    final handshakeStarted = Completer<void>();
    final listener = endpoint.listen((peer) {
      peers.add(peer);
      peer.listen((bytes) {
        if (bytes.isNotEmpty && !handshakeStarted.isCompleted) {
          handshakeStarted.complete();
        }
        // 保持真实 adbd 握手阻塞，不发送 CNXN 或认证回执。
      });
    });
    Future<void> closePeers() async {
      for (final peer in peers) {
        peer.destroy();
      }
      await listener.cancel();
      await endpoint.close();
    }

    AdbHost? owned;
    addTearDown(() async {
      // 显式关闭仍在下方保持远端阻塞；失败收尾先释放夹具端点，再重试原生所有者。
      await closePeers();
      await owned?.close();
    });
    final host = await AdbHost.prepare(
      bindings: await createNativeAdbApi(),
      dataDirectory: root,
      binaryDirectory: File(binary!).parent,
    );
    owned = host;
    final target = '127.0.0.1:${endpoint.port}';
    final original = await Process.start(binary, [
      '-H',
      '127.0.0.1',
      '-P',
      '${host.nativeConfiguration!['port']}',
      'connect',
      target,
    ]);
    final outputDrained = Future.wait([
      original.stdout.drain<void>(),
      original.stderr.drain<void>(),
    ]);
    addTearDown(() async {
      original.kill();
      await original.exitCode.timeout(const Duration(seconds: 5));
      await outputDrained;
    });
    await handshakeStarted.future.timeout(const Duration(seconds: 5));
    await expectLater(
      host.client.connect(target),
      throwsA(
        isA<AdbException>().having(
          (error) => error.code,
          'code',
          'official_connect_result_unknown',
        ),
      ),
    );
    await expectLater(
      host.client.connect('127.0.0.1:1'),
      throwsA(
        isA<AdbException>().having(
          (error) => error.code,
          'code',
          'official_connect_result_unknown',
        ),
      ),
    );
    await host.close();
    await expectLater(
      Socket.connect('127.0.0.1', host.nativeConfiguration!['port'] as int),
      throwsA(isA<SocketException>()),
    );
  }, skip: binary == null ? '需要显式受控 ADB 二进制' : false);
}
