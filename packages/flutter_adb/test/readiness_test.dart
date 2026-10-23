import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_adb/src/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cold accepted listener with a timed-out probe retries actual host service',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      var requests = 0;
      final subscription = server.listen((socket) {
        sockets.add(socket);
        final bytes = <int>[];
        var replied = false;
        socket.listen((request) {
          bytes.addAll(request);
          if (bytes.length < 16 || replied) return;
          replied = true;
          expect(ascii.decode(bytes), '000chost:version');
          if (++requests > 1) {
            socket.add(ascii.encode('OK'));
            scheduleMicrotask(() => socket.add(ascii.encode('AY00040029')));
          }
        });
      });
      try {
        await waitForOfficialAdbServer(
          server.port,
          hasExited: () => false,
          timeout: const Duration(seconds: 2),
        );
        expect(requests, 2);
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      }
    },
  );
  test('unresponsive accepted server fails within bounded startup and closes probes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {});
    });
    final watch = Stopwatch()..start();
    try {
      await expectLater(
        waitForOfficialAdbServer(
          server.port,
          hasExited: () => false,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'startup cannot wait indefinitely',
      );
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    }
  });
}
