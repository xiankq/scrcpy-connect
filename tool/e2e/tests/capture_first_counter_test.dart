import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../video_fixture/capture_first_counter.dart';

void main() {
  test('exact reader retains fragmented and buffered scrcpy bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final client = await Socket.connect(server.address, server.port);
    final peer = await accepted;
    addTearDown(() async {
      client.destroy();
      peer.destroy();
      await server.close();
    });
    final reader = ExactReader(client);
    peer.add([1, 2]);
    await peer.flush();
    final three = reader.exact(3);
    peer.add([3, 4, 5]);
    await peer.flush();
    expect(await three, [1, 2, 3]);
    expect(await reader.exact(2), [4, 5]);
    peer.add([6]);
    await peer.flush();
    await peer.close();
    await expectLater(reader.exact(2), throwsStateError);
  });
}
