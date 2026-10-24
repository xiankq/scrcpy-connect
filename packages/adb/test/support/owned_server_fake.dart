import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';

AdbServerCommandResult commandResult(String output, {int exit = 0}) =>
    AdbServerCommandResult(
      status: AdbServerCommandStatus.exited,
      exitCode: exit,
      stdout: Uint8List.fromList(utf8.encode(output)),
      stderr: Uint8List(0),
    );

/// 仅模拟公开能力的回执和资源责任；真实 Child/ACK/管道回收由原生夹具验证。
class OwnedServerFake
    implements
        NativeAdbApi,
        NativeAdbServerApi,
        NativeAdbHandshakeApi,
        NativeAdbFileScopeApi,
        AdbIdentities {
  int _sequence = 0;
  final entries = <String, AdbServerInfo>{};
  final specs = <String, AdbServerCommandSpec>{};
  final commandLeases = <String, String>{};
  final commandDone = <String, Completer<void>>{};
  final issued = <String>{}, confirmed = <String>{};
  final commandCloses = <String>[], commandCancels = <String>[];
  final closedLeases = <String>[];
  final opened = <String>[], disconnected = <String>[];
  final handshakes = <String>[],
      handshakeCloses = <String>[],
      handshakeCancels = <String>[];
  final handshakeLeases = <String, String>{};
  final connections = <String, String>{};
  final closedScopes = <String>[];
  final listeners = <String, ServerSocket>{};
  final sockets = <Socket>[];
  final _serverTails = <String, Future<void>>{};

  Future<T> _serialServer<T>(String serverId, Future<T> Function() action) {
    final result = (_serverTails[serverId] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _serverTails[serverId] = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_serverTails[serverId], settled)) {
          _serverTails.remove(serverId);
        }
      }),
    );
    return result;
  }

  int commandCloseFailures = 0,
      serverCloseFailures = 0,
      disconnectFailures = 0,
      scopeCloseFailures = 0;
  String connectPrefix = 'connected to', probeState = 'device';
  String readinessReply = 'OKAY00040029';
  Future<void> Function()? onProbe;
  int probeExit = 0;
  Future<void>? createCommandGate, commandCloseGate, scopeCloseGate;
  Future<String> Function()? handshakeCreating;
  Future<void> Function(String)? handshakeClosing;
  Future<AdbDevice> Function(String)? connecting;
  Future<AdbServerCommandResult> Function(String, AdbServerCommandSpec)?
  running;
  void Function(String)? cancelling;

  AdbServerInfo _copy(
    AdbServerInfo old, {
    String? lease,
    AdbServerPhase? phase,
    bool? unknown,
  }) => AdbServerInfo(
    serverId: old.serverId,
    leaseId: lease ?? old.leaseId,
    launch: old.launch,
    phase: phase ?? old.phase,
    transportStateUnknown: unknown ?? old.transportStateUnknown,
    pid: old.pid,
    exitCode: old.exitCode,
  );

  AdbServerInfo _lease(String lease, {bool admit = true}) {
    final matching = entries.values.where((entry) => entry.leaseId == lease);
    if (matching.isEmpty) throw const AdbException('stale_server_lease');
    final entry = matching.single;
    if (admit && entry.transportStateUnknown) {
      throw const AdbException('official_connect_result_unknown');
    }
    return entry;
  }

  @override
  Future<AdbServerInfo> createServer(AdbServerLaunchSpec launch) async {
    final id = 'server-${_sequence++}';
    final info = AdbServerInfo(
      serverId: id,
      leaseId: 'lease-${_sequence++}',
      launch: launch,
      phase: AdbServerPhase.reserved,
      transportStateUnknown: false,
      pid: 1000 + _sequence,
    );
    entries[id] = info;
    return info;
  }

  Future<AdbServerInfo> readyServer() async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final entry = await createServer(
      AdbServerLaunchSpec(
        executable: '/controlled/adb',
        arguments: ['server', 'nodaemon'],
        environment: const {},
        endpoint: '127.0.0.1:$port',
      ),
    );
    return startServer(entry.leaseId, 1000);
  }

  @override
  Future<AdbServerInfo> startServer(String leaseId, int timeoutMs) async {
    final old = _lease(leaseId);
    final endpoint = Uri.parse('tcp://${old.launch.endpoint}');
    final server = await ServerSocket.bind(endpoint.host, endpoint.port);
    listeners[old.serverId] = server;
    server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) async {
        await onProbe?.call();
        socket.add(ascii.encode(readinessReply));
      });
    });
    final ready = _copy(old, phase: AdbServerPhase.ready);
    entries[old.serverId] = ready;
    return ready;
  }

  @override
  Future<List<AdbServerInfo>> listServers() async => entries.values.toList();

  @override
  Future<AdbServerInfo> claimServer(String leaseId) async {
    final server = _lease(leaseId, admit: false);
    return _serialServer(server.serverId, () async {
      _lease(leaseId, admit: false);
      for (final id
          in commandLeases.keys
              .where((id) => commandLeases[id] == leaseId)
              .toList()) {
        await closeServerCommand(id);
      }
      // drain 会让出执行权；提交前仍须核验同一旧租约。
      final current = _lease(leaseId, admit: false);
      final claimed = _copy(current, lease: 'lease-${_sequence++}');
      entries[current.serverId] = claimed;
      return claimed;
    });
  }

  @override
  Future<void> closeServer(String leaseId) async {
    closedLeases.add(leaseId);
    final matching = entries.values.where((entry) => entry.leaseId == leaseId);
    if (matching.isEmpty) return;
    final serverId = matching.single.serverId;
    return _serialServer(serverId, () async {
      final current = entries[serverId];
      if (current == null || current.leaseId != leaseId) return;
      if (serverCloseFailures > 0) {
        serverCloseFailures--;
        throw const AdbException('adb_server_cleanup_unconfirmed');
      }
      for (final id
          in commandLeases.keys
              .where((id) => commandLeases[id] == leaseId)
              .toList()) {
        await closeServerCommand(id);
      }
      if (entries[serverId]?.leaseId != leaseId) return;
      await listeners.remove(serverId)?.close();
      if (entries[serverId]?.leaseId == leaseId) entries.remove(serverId);
    });
  }

  @override
  Future<String> createServerCommand(
    String leaseId,
    AdbServerCommandSpec spec,
  ) async {
    final entry = _lease(leaseId);
    if (spec.preparation
        ? entry.phase != AdbServerPhase.reserved
        : entry.phase != AdbServerPhase.ready) {
      throw const AdbException('server_closed');
    }
    final id = 'command-${_sequence++}';
    specs[id] = spec;
    commandLeases[id] = leaseId;
    commandDone[id] = Completer<void>();
    await createCommandGate;
    return id;
  }

  List<String> arguments(String id) {
    final args = specs[id]!.arguments;
    return args.isNotEmpty && args.first == '-H' ? args.sublist(4) : args;
  }

  @override
  Future<AdbServerCommandResult> runServerCommand(String id) async {
    _lease(commandLeases[id]!);
    issued.add(id);
    try {
      if (running case final run?) {
        final result = await run(id, specs[id]!);
        if (result.status == AdbServerCommandStatus.startFailed) {
          issued.remove(id);
        }
        return result;
      }
      final args = arguments(id);
      return switch (args.first) {
        'keygen' => await _keygen(args[1]),
        'connect' => commandResult('$connectPrefix ${args[1]}\n'),
        '-s' => commandResult('$probeState\n', exit: probeExit),
        'devices' => commandResult('List of devices attached\ntarget device\n'),
        'pair' => commandResult('Successfully paired [guid=actual-guid]\n'),
        _ => commandResult(''),
      };
    } finally {
      commandDone[id]!.complete();
    }
  }

  Future<AdbServerCommandResult> _keygen(String path) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('fixture-private-key');
    return commandResult('');
  }

  @override
  Future<void> confirmServerCommand(String id) async {
    confirmed.add(id);
  }

  @override
  Future<void> cancelServerCommand(String id) async {
    commandCancels.add(id);
    cancelling?.call(id);
  }

  @override
  Future<void> closeServerCommand(String id) async {
    commandCloses.add(id);
    if (issued.contains(id)) {
      if (!commandDone[id]!.isCompleted) await cancelServerCommand(id);
      await commandDone[id]!.future;
    }
    await commandCloseGate;
    if (commandCloseFailures > 0) {
      commandCloseFailures--;
      throw StateError('command cleanup unconfirmed');
    }
    final spec = specs[id];
    if (spec != null &&
        spec.mayCreateTransport &&
        issued.contains(id) &&
        !confirmed.contains(id)) {
      final entry = _lease(commandLeases[id]!, admit: false);
      entries[entry.serverId] = _copy(entry, unknown: true);
    }
    commandLeases.remove(id);
  }

  @override
  Future<String> createServerHandshake(String leaseId) async {
    _lease(leaseId);
    final id =
        await (handshakeCreating?.call() ??
            Future.value('handshake-${_sequence++}'));
    handshakes.add(id);
    handshakeLeases[id] = leaseId;
    return id;
  }

  @override
  Future<String> createHandshake() => throw UnsupportedError('必须绑定服务器租约');
  @override
  Future<void> cancelHandshake(String id) async {
    handshakeCancels.add(id);
  }

  @override
  Future<void> closeHandshake(String id) async {
    handshakeCloses.add(id);
    await handshakeClosing?.call(id);
  }

  @override
  Future<AdbDevice> connectServer(
    String address,
    String serial,
    int timeoutMs, {
    String? handshakeId,
  }) async {
    _lease(handshakeLeases[handshakeId]!);
    opened.add(serial);
    final result =
        await (connecting?.call(serial) ??
            Future.value(
              AdbDevice(
                id: 'connection-${_sequence++}',
                serial: serial,
                state: 'device',
              ),
            ));
    connections[result.id] = serial;
    return result;
  }

  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
    if (disconnectFailures > 0) {
      disconnectFailures--;
      throw StateError('connection cleanup unconfirmed');
    }
    connections.remove(id);
  }

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    if (!connections.containsKey(id)) {
      throw const AdbException('unknown_connection');
    }
    return const AdbConnectionFacts(
      officialServer: true,
      closed: false,
      features: [],
    );
  }

  @override
  Future<String> fileScopeAttach(String ownerKey) async => 'scope-$ownerKey';
  @override
  Future<void> fileScopeClose(String scopeId) async {
    closedScopes.add(scopeId);
    await scopeCloseGate;
    if (scopeCloseFailures > 0) {
      scopeCloseFailures--;
      throw const AdbException('file_cleanup_unconfirmed');
    }
  }

  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async =>
      await File(path).exists()
      ? const AdbIdentityInfo(
          fingerprint: 'fixture',
          fingerprintAlgorithm: 'sha256',
          fingerprintInput: 'fixture',
          bits: 2048,
          exponent: 65537,
        )
      : null;
  @override
  Future<void> prepareIdentity(String path) async {
    if (!await File(path).exists()) await _keygen(path);
  }

  Future<void> dispose() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    for (final server in listeners.values) {
      await server.close();
    }
    listeners.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
