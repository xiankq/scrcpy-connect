import 'dart:io';

import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  test(
    'closing an owned server closes its port and preserves another listener',
    () async {
      final root = await Directory.systemTemp.createTemp('flutter-adb-close-');
      final unrelated = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final accepted = <Socket>[];
      final listener = unrelated.listen(accepted.add);
      final host = await FlutterAdb.prepare(
        dataDirectory: root,
        binaryDirectory: File(binary!).parent,
      );
      addTearDown(() async {
        await host.close();
        for (final socket in accepted) {
          socket.destroy();
        }
        await listener.cancel();
        await unrelated.close();
        await root.delete(recursive: true);
      });
      final port = host.nativeConfiguration!['port'] as int;
      final first = host.close();
      expect(identical(first, host.close()), isTrue);
      await first;
      await host.close();
      await expectLater(
        Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()),
      );
      final socket = await Socket.connect('127.0.0.1', unrelated.port);
      socket.destroy();
    },
    skip: binary == null ? 'Set explicit controlled ADB binary' : false,
  );
}
