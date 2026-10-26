import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../fixtures/usb_fixture/usbip_server.dart';

Uint8List word(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

Uint8List adb(String command, int arg0, int arg1, List<int> payload) {
  final bytes = Uint8List(24 + payload.length);
  bytes.setRange(0, 4, ascii.encode(command));
  final view = ByteData.sublistView(bytes);
  view.setUint32(4, arg0, Endian.little);
  view.setUint32(8, arg1, Endian.little);
  view.setUint32(12, payload.length, Endian.little);
  view.setUint32(16, payload.fold<int>(0, (a, b) => a + b), Endian.little);
  view.setUint32(
    20,
    view.getUint32(0, Endian.little) ^ 0xffffffff,
    Endian.little,
  );
  bytes.setRange(24, bytes.length, payload);
  return bytes;
}

Uint8List submit(
  int sequence,
  int direction,
  int length, {
  int endpoint = 1,
  List<int> setup = const [],
  List<int> payload = const [],
}) {
  final bytes = Uint8List(48 + payload.length);
  final view = ByteData.sublistView(bytes);
  for (final (offset, value) in [
    (0, 1),
    (4, sequence),
    (8, 0x10001),
    (12, direction),
    (16, endpoint),
    (24, length),
  ]) {
    view.setUint32(offset, value);
  }
  if (setup.isNotEmpty) bytes.setRange(40, 48, setup);
  bytes.setRange(48, bytes.length, payload);
  return bytes;
}

class Peer {
  Peer(this.socket) : iterator = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> iterator;
  List<int> pending = [];

  Future<Uint8List> read(int count) async {
    while (pending.length < count) {
      if (!await iterator.moveNext().timeout(const Duration(seconds: 3))) {
        throw StateError('USB/IP peer closed before reply');
      }
      pending.addAll(iterator.current);
    }
    final result = Uint8List.fromList(pending.sublist(0, count));
    pending = pending.sublist(count);
    return result;
  }

  Future<void> attach({bool fragmented = false}) async {
    final request = Uint8List(40);
    final view = ByteData.sublistView(request);
    view.setUint16(0, 0x111);
    view.setUint16(2, 0x8003);
    request.setRange(8, 11, ascii.encode('1-1'));
    if (fragmented) {
      for (final byte in request) {
        socket.add([byte]);
        await socket.flush();
      }
    } else {
      socket.add(request);
    }
    final reply = await read(8);
    expect(ByteData.sublistView(reply).getUint16(2), 3);
    expect(ByteData.sublistView(reply).getUint32(4), 0);
    final device = await read(312);
    final fields = ByteData.sublistView(device);
    expect(fields.getUint32(296), 3);
    expect(fields.getUint16(300), 0x18d1);
    expect(fields.getUint16(302), 0x4ee7);
  }

  Future<(int, int, Uint8List)> response({bool input = true}) async {
    final header = ByteData.sublistView(await read(48));
    final bytes = input && header.getUint32(0) == 3
        ? await read(header.getUint32(24))
        : Uint8List(0);
    return (header.getUint32(4), header.getInt32(20), bytes);
  }

  Future<void> close() async {
    socket.destroy();
    await iterator.cancel();
  }
}

void main() {
  Future<(UsbIpAdbServer, Peer)> setup({
    String? targetHost,
    int? targetPort,
  }) async {
    final server = await UsbIpAdbServer.start(
      targetHost: targetHost,
      targetPort: targetPort,
    );
    addTearDown(server.close);
    final peer = Peer(await Socket.connect(server.address, server.port));
    addTearDown(peer.close);
    return (server, peer);
  }

  test(
    'enumerates high-speed ADB interface and standard control requests',
    () async {
      final (_, peer) = await setup();
      await peer.attach(fragmented: true);
      peer.socket.add(
        submit(1, 1, 255, endpoint: 0, setup: [0x80, 6, 0, 2, 0, 0, 255, 0]),
      );
      final (seq, status, config) = await peer.response();
      expect((seq, status), (1, 0));
      expect(config.length, 32);
      expect(config.sublist(14, 17), [0xff, 0x42, 1]);
      expect(config.sublist(20, 25), [0x81, 2, 0, 2, 0]);
      peer.socket.add(
        submit(2, 0, 0, endpoint: 0, setup: [0, 9, 1, 0, 0, 0, 0, 0]),
      );
      expect((await peer.response(input: false)).$2, 0);
      peer.socket.add(
        submit(3, 1, 1, endpoint: 0, setup: [0x80, 8, 0, 0, 0, 0, 1, 0]),
      );
      expect((await peer.response()).$3, [1]);
      peer.socket.add(
        submit(4, 1, 10, endpoint: 0, setup: [0x80, 6, 0, 6, 0, 0, 10, 0]),
      );
      expect((await peer.response()).$2, -32);
    },
  );

  test(
    'fragmented USB OUT establishes ADB and shell v2 through real sockets',
    () async {
      final (_, peer) = await setup();
      await peer.attach();
      final connect = adb(
        'CNXN',
        0x1000001,
        1048576,
        utf8.encode('host::features=shell_v2;\x00'),
      );
      final request = submit(1, 0, connect.length, payload: connect);
      for (var start = 0; start < request.length; start += 7) {
        peer.socket.add(
          request.sublist(
            start,
            start + 7 > request.length ? request.length : start + 7,
          ),
        );
      }
      expect((await peer.response(input: false)).$1, 1);
      peer.socket.add(submit(2, 1, 65536));
      peer.socket.add(submit(3, 1, 65536));
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'CNXN');
      expect(
        utf8.decode((await peer.response()).$3),
        contains('VirtualAndroid'),
      );
      final open = adb(
        'OPEN',
        7,
        0,
        utf8.encode('shell,v2,raw:getprop ro.build.version.sdk\x00'),
      );
      peer.socket.add(submit(4, 0, open.length, payload: open));
      expect((await peer.response(input: false)).$1, 4);
      for (var seq = 5; seq <= 7; seq++) {
        peer.socket.add(submit(seq, 1, 65536));
      }
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'OKAY');
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'WRTE');
      final output = (await peer.response()).$3;
      expect(output, [1, 3, 0, 0, 0, 51, 54, 10, 3, 1, 0, 0, 0, 0]);
      final okay = adb('OKAY', 7, 1, []);
      peer.socket.add(submit(8, 0, okay.length, payload: okay));
      expect((await peer.response(input: false)).$1, 8);
      peer.socket.add(submit(9, 1, 65536));
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'CLSE');
    },
  );

  test(
    'adbd forwarding preserves header, payload, exact packet ZLP and unlink',
    () async {
      final targetListener = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(targetListener.close);
      final accepted = targetListener.first;
      final (_, peer) = await setup(
        targetHost: '127.0.0.1',
        targetPort: targetListener.port,
      );
      await peer.attach();
      final target = Peer(await accepted);
      addTearDown(target.close);
      final outgoing = adb(
        'CNXN',
        0x1000001,
        1048576,
        utf8.encode('host::\x00'),
      );
      // 头与载荷通过独立的 USB OUT 传输到达。
      peer.socket.add(submit(1, 0, 24, payload: outgoing.sublist(0, 24)));
      peer.socket.add(
        submit(2, 0, outgoing.length - 24, payload: outgoing.sublist(24)),
      );
      expect((await peer.response(input: false)).$1, 1);
      expect((await peer.response(input: false)).$1, 2);
      expect(await target.read(outgoing.length), outgoing);

      peer.socket.add(submit(3, 1, 65536));
      final unlink = Uint8List(48);
      final unlinkView = ByteData.sublistView(unlink);
      unlinkView.setUint32(0, 2);
      unlinkView.setUint32(4, 4);
      unlinkView.setUint32(20, 3);
      peer.socket.add(unlink);
      final canceled = await peer.response();
      expect((canceled.$1, canceled.$2), (4, -104));
      expect(canceled.$3, isEmpty);

      final payload = List<int>.generate(512, (i) => i & 255);
      final incoming = adb('WRTE', 1, 7, payload);
      // USB 输出前须重组分段到达的 TCP 头与载荷。
      target.socket.add(incoming.sublist(0, 11));
      await target.socket.flush();
      target.socket.add(incoming.sublist(11));
      for (final (seq, length) in [(5, 65536), (6, 512), (7, 65536)]) {
        peer.socket.add(submit(seq, 1, length));
      }
      final header = await peer.response();
      expect(header.$1, 5); // 已取消的序号 3 不会完成。
      expect(header.$3, incoming.sublist(0, 24));
      expect((await peer.response()).$3, payload);
      final zlp = await peer.response();
      expect(zlp.$1, 7);
      expect(zlp.$3, isEmpty);
      target.socket.add(adb('OKAY', 1, 7, []));
      peer.socket.add(submit(8, 1, 65536));
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'OKAY');
    },
  );

  test(
    'full packet plus ZLP completes a larger read without an extra empty read',
    () async {
      final targetListener = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(targetListener.close);
      final accepted = targetListener.first;
      final (_, peer) = await setup(
        targetHost: '127.0.0.1',
        targetPort: targetListener.port,
      );
      await peer.attach();
      final target = await accepted;
      addTearDown(target.destroy);
      target.add(adb('WRTE', 1, 7, List.filled(512, 33)));
      target.add(adb('OKAY', 1, 7, []));
      for (var seq = 1; seq <= 3; seq++) {
        peer.socket.add(submit(seq, 1, 65536));
      }
      expect((await peer.response()).$3.length, 24);
      expect((await peer.response()).$3.length, 512);
      expect(ascii.decode((await peer.response()).$3.sublist(0, 4)), 'OKAY');
    },
  );

  test(
    'disconnect clears pending reads and releases the import lease',
    () async {
      final (server, peer) = await setup();
      await peer.attach();
      peer.socket.add(submit(1, 1, 65536));
      await peer.close();
      // EOF 异步到达，等待确定的断开事件。
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final replacement = Peer(
        await Socket.connect(server.address, server.port),
      );
      addTearDown(replacement.close);
      await replacement.attach();
      replacement.socket.add(
        submit(2, 1, 18, endpoint: 0, setup: [0x80, 6, 0, 1, 0, 0, 18, 0]),
      );
      expect((await replacement.response()).$1, 2);
    },
  );

  test(
    'application metadata command retains property order over USB shell',
    () async {
      final (_, peer) = await setup();
      await peer.attach();
      final command = adb(
        'OPEN',
        7,
        0,
        utf8.encode(
          'shell:getprop ro.product.model; getprop ro.build.version.release; '
          'getprop ro.build.version.sdk; getprop ro.serialno\x00',
        ),
      );
      peer.socket.add(submit(1, 0, command.length, payload: command));
      await peer.response(input: false);
      for (var seq = 2; seq <= 4; seq++) {
        peer.socket.add(submit(seq, 1, 65536));
      }
      await peer.response(); // OKAY 响应头。
      await peer.response(); // WRTE 响应头。
      expect(
        utf8.decode((await peer.response()).$3),
        'VirtualAndroid\n16\n36\nconnect-usb-fixture\n',
      );
    },
  );
}
