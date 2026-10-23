import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An accepted listener is not yet a ready adb-server during cold startup.
Future<void> waitForOfficialAdbServer(
  int port, {
  required bool Function() hasExited,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (hasExited()) {
      throw StateError('Official ADB server exited during startup');
    }
    try {
      await _probe(port);
      if (hasExited()) {
        throw StateError('Official ADB server exited during startup');
      }
      return;
    } on SocketException {
      if (DateTime.now().isAfter(deadline)) rethrow;
    } on TimeoutException {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Official ADB server did not become ready',
          timeout,
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _probe(int port) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: const Duration(milliseconds: 300),
  );
  StreamIterator<List<int>>? input;
  try {
    input = StreamIterator<List<int>>(socket);
    socket.add(ascii.encode('000chost:version'));
    await socket.flush();
    final bytes = <int>[];
    while (bytes.length < 12) {
      if (!await input.moveNext().timeout(const Duration(milliseconds: 500))) {
        throw const SocketException('ADB readiness response ended');
      }
      bytes.addAll(input.current);
      if (bytes.length > 64) {
        throw const SocketException('ADB readiness response exceeded bound');
      }
    }
    final reply = ascii.decode(bytes);
    if (!reply.startsWith('OKAY0004') ||
        !RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(reply.substring(8, 12))) {
      throw const SocketException('ADB readiness response rejected');
    }
  } finally {
    socket.destroy();
    await input?.cancel();
  }
}
