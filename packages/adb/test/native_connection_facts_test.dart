import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实 FRB 保留官方代理的握手未知性，不伪造配置身份', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final connections = StreamIterator(server);
    final sockets = <Socket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await connections.cancel();
      await server.close();
    });

    final fixture = () async {
      expect(await connections.moveNext(), isTrue);
      final transport = connections.current;
      sockets.add(transport);
      final selection = _Reader(transport);
      expect(await selection.service(), 'host:tport:serial:fixture');
      final id = ByteData(8)..setUint64(0, 42, Endian.little);
      transport.add([...ascii.encode('OKAY'), ...id.buffer.asUint8List()]);
      await transport.flush();
      await selection.close();

      expect(await connections.moveNext(), isTrue);
      final features = connections.current;
      sockets.add(features);
      final query = _Reader(features);
      expect(await query.service(), 'host-transport-id:42:features');
      features.add(ascii.encode('OKAY0008shell_v2'));
      await features.flush();
      await query.close();
    }();
    // 立即观察夹具错误，避免网络失败导致未处理的异步异常。
    final observed = expectLater(fixture, completes);
    final api = await createNativeAdbApi();
    final device = await api.connectServer(
      '127.0.0.1:${server.port}',
      'fixture',
      5000,
    );
    addTearDown(() => api.disconnect(device.id));
    await observed;

    final facts = await api.connectionFacts(device.id);
    expect(facts.officialServer, isTrue);
    expect(facts.transportId, 42);
    expect(facts.features, contains('shell_v2'));
    expect(facts.handshake, AdbHandshakeKind.delegatedServer);
    expect(facts.configuredIdentity, isNull);
    expect(facts.closed, isFalse);
  });
}

/// smart socket 的长度和命令可能跨 TCP 包到达，夹具按协议长度读取。
final class _Reader {
  _Reader(Socket socket) : _chunks = StreamIterator(socket);
  final StreamIterator<Uint8List> _chunks;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<List<int>> _read(int count) async {
    final output = <int>[];
    while (output.length < count) {
      if (_offset == _buffer.length) {
        if (!await _chunks.moveNext()) throw StateError('夹具收到提前结束的命令。');
        _buffer = _chunks.current;
        _offset = 0;
      }
      final remaining = count - output.length;
      final available = _buffer.length - _offset;
      final length = remaining < available ? remaining : available;
      output.addAll(_buffer.sublist(_offset, _offset + length));
      _offset += length;
    }
    return output;
  }

  Future<String> service() async {
    final length = int.parse(ascii.decode(await _read(4)), radix: 16);
    return ascii.decode(await _read(length));
  }

  Future<void> close() => _chunks.cancel();
}
