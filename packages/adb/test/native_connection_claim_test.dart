import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真实 FRB 认领保留同 Client，旧关闭后新句柄仍能执行服务且不重连', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final incoming = StreamIterator(server);
    final sockets = <Socket>[];
    final commands = <String>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await incoming.cancel();
      await server.close();
    });
    Future<Socket> accept() async {
      if (!await incoming.moveNext()) throw StateError('夹具监听提前关闭。');
      final socket = incoming.current;
      sockets.add(socket);
      return socket;
    }

    Future<String> command(_Reader reader) async {
      final value = await reader.service();
      commands.add(value);
      return value;
    }

    final fixture = () async {
      final transport = await accept();
      final selection = _Reader(transport);
      expect(await command(selection), 'host:tport:serial:fixture');
      final id = ByteData(8)..setUint64(0, 42, Endian.little);
      transport.add([...ascii.encode('OKAY'), ...id.buffer.asUint8List()]);
      await transport.flush();
      await selection.close();

      final features = await accept();
      final query = _Reader(features);
      expect(await command(query), 'host-transport-id:42:features');
      features.add(ascii.encode('OKAY0000'));
      await features.flush();
      await query.close();

      final shell = await accept();
      final execution = _Reader(shell);
      expect(await command(execution), 'host:transport-id:42');
      shell.add(ascii.encode('OKAY'));
      await shell.flush();
      expect(await command(execution), 'shell:fixture-after-claim');
      shell.add([...ascii.encode('OKAY'), 0, 255, 1]);
      await shell.close();
      await execution.close();
    }();
    final observed = expectLater(fixture, completes);
    final api = await createNativeAdbApi();
    final original = await api.connectServer(
      '127.0.0.1:${server.port}',
      'fixture',
      5000,
    );
    addTearDown(() => api.disconnect(original.id));
    final previous = NativeAdbClient(api, '/unused-identity');
    addTearDown(previous.close);
    final successor = NativeAdbClient(api, '/unused-identity');
    addTearDown(successor.close);
    final old = await previous.claimConnection(original);
    final before = await previous.services.connectionFacts(old);
    final claimed = await successor.claimConnection(old);
    final after = await successor.services.connectionFacts(claimed);
    expect(claimed.id, isNot(old.id));
    expect(before.connectionId, isNotEmpty);
    expect(after.connectionId, before.connectionId);
    expect(after.serverAddress, '127.0.0.1:${server.port}');
    expect(after.serverAddress, before.serverAddress);
    expect(after.transportId, before.transportId);
    await previous.close();
    final events = await successor
        .shell(claimed, 'fixture-after-claim')
        .toList();
    final bytes = events
        .where((event) => event.channel == AdbShellChannel.stdout)
        .expand((event) => event.bytes)
        .toList();
    expect(bytes, [0, 255, 1]);
    await observed;
    expect(
      commands.where((value) => value.startsWith('host:tport:')),
      hasLength(1),
    );
    expect((await successor.services.connectionFacts(claimed)).closed, isFalse);
    await successor.close();
  });
}

/// 按 smart socket 长度前缀读取，避免将 TCP 分包误当成命令边界。
final class _Reader {
  _Reader(Socket socket) : _chunks = StreamIterator(socket);
  final StreamIterator<Uint8List> _chunks;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<List<int>> _read(int count) async {
    final output = <int>[];
    while (output.length < count) {
      if (_offset == _buffer.length) {
        if (!await _chunks.moveNext()) throw StateError('夹具命令提前结束。');
        _buffer = _chunks.current;
        _offset = 0;
      }
      final available = _buffer.length - _offset;
      final remaining = count - output.length;
      final length = available < remaining ? available : remaining;
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
