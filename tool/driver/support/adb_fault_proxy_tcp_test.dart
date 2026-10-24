// 独立的真实 TCP 回归，不依赖 Flutter runner 或原生构建。
// 可从任意目录运行：dart /absolute/path/to/adb_fault_proxy_tcp_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'adb_fault_proxy.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Peer {
  Peer(this.socket) {
    subscription = socket.listen(
      received.addAll,
      onDone: () => ended = true,
      onError: (Object error) => errors.add(error),
    );
  }

  final Socket socket;
  final received = <int>[];
  final errors = <Object>[];
  late final StreamSubscription<List<int>> subscription;
  bool ended = false;

  Future<void> send(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  void destroy() => socket.destroy();
}

Future<void> until(bool Function() predicate, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(message);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class Network {
  final targets = <Peer>[];
  final controllers = <Peer>[];
  late final ServerSocket upstream;
  late final StreamSubscription<Socket> subscription;
  late final AdbFaultProxy proxy;

  Future<void> start() async {
    upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    subscription = upstream.listen((socket) => targets.add(Peer(socket)));
    proxy = AdbFaultProxy(upstream.port, listenPort: 0);
    await proxy.start();
  }

  Future<(Peer, Peer)> connect() async {
    final count = targets.length + 1;
    final controller = Peer(
      await Socket.connect(InternetAddress.loopbackIPv4, proxy.port),
    );
    controllers.add(controller);
    await until(
      () =>
          targets.length == count &&
          proxy.events.where((e) => e['kind'] == 'upstream-connected').length ==
              count,
      'New upstream was not connected.',
    );
    return (controller, targets.last);
  }

  Future<void> close() async {
    for (final controller in controllers) {
      controller.destroy();
    }
    for (final target in targets) {
      target.destroy();
    }
    await proxy.close().timeout(const Duration(seconds: 3));
    await upstream.close();
    await subscription.cancel();
  }
}

Future<void> roundTrip(Peer controller, Peer target) async {
  final previousTarget = target.received.length;
  final previousController = controller.received.length;
  await controller.send([11, 12]);
  await target.send([21, 22]);
  await until(
    () =>
        target.received.length == previousTarget + 2 &&
        controller.received.length == previousController + 2,
    'Normal connection did not carry bytes in both directions.',
  );
  check(
    target.received.skip(previousTarget).join(',') == '11,12',
    'Upstream bytes changed.',
  );
  check(
    controller.received.skip(previousController).join(',') == '21,22',
    'Controller bytes changed.',
  );
}

Future<void> blackholeDropsAndKeepsNewConnectionsWorking() async {
  final network = Network();
  await network.start();
  final proxy = network.proxy;
  try {
    final (controller, target) = await network.connect();
    await roundTrip(controller, target);
    proxy.injectFault(AdbRecoveryFault.blackhole);
    // 使用足以跨多个 socket 块的真实数据，不记录载荷。
    await controller.send(List<int>.filled(256 * 1024, 31));
    await target.send(List<int>.filled(128 * 1024, 41));
    await until(() {
      final drops = proxy.faultEvidence['droppedBytes'] as Map<String, int>;
      return drops['controller-to-upstream'] == 256 * 1024 &&
          drops['upstream-to-controller'] == 128 * 1024;
    }, 'Blackhole did not continue reading and counting both byte streams.');
    check(target.received.length == 2, 'Blackhole leaked controller bytes.');
    check(controller.received.length == 2, 'Blackhole leaked upstream bytes.');
    check(!controller.ended && !target.ended, 'Injection closed a TCP socket.');
    check(
      controller.errors.isEmpty && target.errors.isEmpty,
      'TCP peer error.',
    );
    final (newController, newTarget) = await network.connect();
    await roundTrip(newController, newTarget);
    check(
      !controller.ended && !target.ended,
      'New connection closed old sockets.',
    );
    controller.destroy();
    await until(
      () => proxy.faultEvidence['firstDirectionEnd'] != null,
      'Controller close produced no EOF receipt.',
    );
    final end =
        proxy.faultEvidence['firstDirectionEnd'] as Map<String, Object?>;
    check(
      end['direction'] == 'controller-to-upstream',
      'Wrong first direction.',
    );
    check(end['end'] == 'eof', 'Controller close was not observed as EOF.');
    check(
      proxy.recoveryEvidenceErrors().any((e) => e.contains('before any new')),
      'Acceptance allowed a replacement connection before the original EOF.',
    );
    stdout.writeln(
      'PASS: discard/isolation ${jsonEncode(proxy.faultEvidence)}',
    );
  } finally {
    await network.close();
  }
}

Future<void> controllerEofBeforeReplacementPasses() async {
  final network = Network();
  await network.start();
  final proxy = network.proxy;
  try {
    final (controller, target) = await network.connect();
    proxy.injectFault(AdbRecoveryFault.blackhole);
    await controller.send([61, 62]);
    await target.send([51, 52, 53]);
    await until(() {
      final drops = proxy.faultEvidence['droppedBytes'] as Map<String, int>;
      return drops['upstream-to-controller'] == 3 &&
          drops['controller-to-upstream'] == 2;
    }, 'No discarded bytes were observed.');
    check(
      proxy.recoveryEvidenceErrors().isNotEmpty,
      'An open original connection was accepted as recovered.',
    );
    controller.destroy();
    await until(
      () => proxy.faultEvidence['closeReason'] == 'controller-to-upstream-eof',
      'The controller did not close its original TCP connection first.',
    );
    final (newController, newTarget) = await network.connect();
    await roundTrip(newController, newTarget);
    check(
      proxy.recoveryEvidenceErrors().isEmpty,
      'Valid recovery rejected: ${proxy.recoveryEvidenceErrors()}',
    );
    stdout.writeln('PASS: controller EOF ${jsonEncode(proxy.faultEvidence)}');
  } finally {
    await network.close();
  }
}

Future<void> eofModePreservesTransportCut() async {
  final network = Network();
  await network.start();
  final proxy = network.proxy;
  try {
    final (controller, target) = await network.connect();
    await roundTrip(controller, target);
    proxy.injectFault(AdbRecoveryFault.eof);
    await until(
      () => controller.ended && target.ended,
      'EOF injection did not close both TCP peers.',
    );
    final (newController, newTarget) = await network.connect();
    await roundTrip(newController, newTarget);
    check(
      proxy.recoveryEvidenceErrors().isEmpty,
      'Original EOF recovery mode was rejected.',
    );
    stdout.writeln('PASS: default EOF closes the old pair; new pair forwards.');
  } finally {
    await network.close();
  }
}

Future<void> shutdownClosesBlackholeWithinQuota() async {
  final network = Network();
  await network.start();
  final proxy = network.proxy;
  try {
    final (controller, target) = await network.connect();
    proxy.injectFault(AdbRecoveryFault.blackhole);
    await controller.send([71]);
    await target.send([81]);
    await until(
      () => (proxy.faultEvidence['droppedBytes'] as Map<String, int>).values
          .every((count) => count > 0),
      'Shutdown test did not enter a real discarding state.',
    );
    final beforeShutdown = proxy.faultEvidence;
    final errorsBeforeShutdown = proxy.recoveryEvidenceErrors();
    check(
      errorsBeforeShutdown.isNotEmpty,
      'Unrecovered blackhole was accepted.',
    );
    final port = proxy.port;
    await proxy.close().timeout(const Duration(seconds: 2));
    await until(
      () => controller.ended && target.ended,
      'Shutdown left a blackholed TCP socket open.',
    );
    check(
      proxy.recoveryEvidenceErrors().any((e) => e.contains('controller must')),
      'Cleanup manufactured acceptable controller EOF evidence.',
    );
    check(
      beforeShutdown['firstDirectionEnd'] == null &&
          beforeShutdown['closeReason'] == null,
      'Pre-cleanup evidence was altered by shutdown.',
    );
    final replacement = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    await replacement.close();
    stdout.writeln(
      'PASS: shutdown closes sockets/releases port within 2 seconds.',
    );
  } finally {
    await network.close();
  }
}

Future<void> main() async {
  await blackholeDropsAndKeepsNewConnectionsWorking();
  await controllerEofBeforeReplacementPasses();
  await eofModePreservesTransportCut();
  await shutdownClosesBlackholeWithinQuota();
}
