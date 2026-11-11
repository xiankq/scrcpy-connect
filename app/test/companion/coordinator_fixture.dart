import '../support/adb_event_fixture.dart';

import 'package:scrcpy_connect/models/companion_exception.dart';

import 'package:scrcpy_connect/models/companion_config.dart';
import 'package:scrcpy_connect/models/device_connection.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/companion_service.dart';
import 'package:scrcpy_connect/services/companion_recovery.dart';

const coordinatorConfig = CompanionConfig(
  startupTimeout: Duration(seconds: 2),
  requestTimeout: Duration(seconds: 2),
  cleanupTimeout: Duration(seconds: 2),
  sessionTimeout: Duration(minutes: 1),
);

class CoordinatorFixture {
  CoordinatorFixture({CompanionRecovery? recovery}) {
    client = NativeAdbClient(api, '/unused/key');
    replaceConnection();
    companion = CompanionService(
      requireConnection: (_) =>
          current ?? (throw const CompanionException('disconnected', '离线')),
      serverBytes: Uint8List.fromList([1, 2, 3]),
      config: coordinatorConfig,
      emit: emit,
      recovery: recovery,
      deviceSerial: (_) => 'serial',
    );
  }
  final api = CoordinatorApi();
  late final NativeAdbClient client;
  DeviceConnection? current;
  late final CompanionService companion;
  bool rejectStartingEvent = false;
  final emitted =
      <({String type, String? device, Map<String, Object?> data})>[];
  void emit(String type, String? device, Map<String, Object?> data) {
    if (type == 'companion.starting' && rejectStartingEvent) {
      rejectStartingEvent = false;
      throw StateError('启动事件消费者首败');
    }
    emitted.add((type: type, device: device, data: data));
  }

  DeviceConnection replaceConnection() => current = DeviceConnection(
    client: client,
    device: AdbDevice(
      id: 'exact-connection',
      serial: 'serial',
      state: 'device',
      nativeOwner: api,
    ),
  );
  void reply(Map<String, Object?> request, Map<String, Object?> result) =>
      api.message({'requestId': request['requestId'], 'result': result});
}

Matcher companionCode(String code) =>
    isA<CompanionException>().having((error) => error.code, 'code', code);

class _Operation {
  final queue = Queue<NativeAdbEvent>();
  Completer<NativeAdbEvent?>? waiting;
  bool closed = false;
  void add(NativeAdbEvent event) {
    if (closed) return;
    final pending = waiting;
    if (pending == null) {
      queue.add(event);
    } else {
      waiting = null;
      pending.complete(event);
    }
  }

  Future<NativeAdbEvent?> next() {
    if (queue.isNotEmpty) return Future.value(queue.removeFirst());
    if (closed) return Future.value(null);
    return (waiting = Completer<NativeAdbEvent?>()).future;
  }

  void close() {
    closed = true;
    queue.clear();
    waiting?.complete(null);
    waiting = null;
  }
}

class CoordinatorApi implements NativeAdbApi {
  bool transportClosed = false;
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      AdbConnectionFacts(
        officialServer: false,
        closed: transportClosed,
        features: const [],
      );
  void Function(Map<String, Object?>)? onRequest;
  final pushBytes = <String, int>{};
  final operations = <String, _Operation>{};
  final created = <String>[],
      commands = <String>[],
      receivedCommands = <String>[];
  final disconnected = <String>[], cancelled = <String>[];
  final uploaded = <int>[];
  final requests = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final ready = <String, Object?>{
    'event': 'ready',
    'protocol': 1,
    'uid': 2000,
    'apiLevel': 35,
  };
  final rpcCancelled = Completer<void>(), cancelStarted = Completer<void>();
  final authReceived = Completer<void>(), execCreated = Completer<void>();
  final uploadCreated = Completer<void>();
  final _rpcBytes = <int>[];
  final shutdownReplies = Queue<Map<String, Object?>>();
  Map<String, Object?>? auth;
  Completer<void>? writeGate;
  Completer<void>? execGate;
  Completer<void>? uploadGate;
  int generation = 0, waitFailures = 0;
  bool wrongIdentity = false;
  bool sendReady = true;
  bool uploadFailure = false;
  bool disconnectOnShutdown = false;
  bool replyToShutdown = true;
  String? rpcId;
  Set<String> get live => operations.entries
      .where((entry) => !entry.value.closed)
      .map((entry) => entry.key)
      .toSet();
  String _open(String kind) {
    final id = '$kind-${++generation}';
    created.add(id);
    operations[id] = _Operation();
    return id;
  }

  void raw(Uint8List bytes) => operations[rpcId]!.add(adbData(bytes));
  void disconnectRpc() => operations[rpcId]!.close();
  void message(Map<String, Object?> message, {bool split = false}) {
    final bytes = Uint8List.fromList(utf8.encode('${jsonEncode(message)}\n'));
    if (split) {
      for (final value in bytes) {
        raw(Uint8List.fromList([value]));
      }
    } else {
      raw(bytes);
    }
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(id, 'exact-connection');
    if (request.kind == AdbServiceKind.exec) {
      final operation = _open('exec');
      expect(request.service, contains('watch_input'));
      operations[operation]!.add(
        adbText('__INTEROP_PID__77:9001\nINTEROP_COMPANION_READY 77\n'),
      );
      if (!execCreated.isCompleted) execCreated.complete();
      await execGate?.future;
      return operation;
    }
    expect(request.kind, AdbServiceKind.raw);
    expect(
      request.service,
      matches(r'^localabstract:interop-companion-[0-9a-f]{32}$'),
    );
    return rpcId = _open('rpc');
  }

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async {
    expect(id, 'exact-connection');
    expect(request.kind, AdbSyncKind.push);
    expect(request.maxBytes, 3);
    final operation = _open('push');
    pushBytes[operation] = 0;
    if (!uploadCreated.isCompleted) uploadCreated.complete();
    await uploadGate?.future;
    return operation;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    if (id.startsWith('push')) {
      if (input.kind == AdbInputKind.bytes) {
        uploaded.addAll(input.bytes);
        pushBytes[id] = pushBytes[id]! + input.bytes.length;
      }
      if (input.kind == AdbInputKind.finish) {
        operations[id]!.add(adbDone(transferred: pushBytes[id]!));
      }
      return;
    }
    _rpcBytes.addAll(input.bytes);
    while (_rpcBytes.contains(10)) {
      final end = _rpcBytes.indexOf(10);
      final message = Map<String, Object?>.from(
        jsonDecode(utf8.decode(_rpcBytes.sublist(0, end)))
            as Map<String, dynamic>,
      );
      _rpcBytes.removeRange(0, end + 1);
      if (message.containsKey('token')) {
        auth = message;
        if (!authReceived.isCompleted) authReceived.complete();
        if (sendReady) this.message(ready, split: true);
      } else {
        receivedCommands.add(message['command']! as String);
        requests.add(message);
        onRequest?.call(message);
        if (message['command'] == 'media.shutdown') {
          expect(
            message['operationId'],
            matches(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          );
          if (disconnectOnShutdown) {
            operations[rpcId]!.close();
          } else if (replyToShutdown) {
            this.message({
              'requestId': message['requestId'],
              ...shutdownReplies.isEmpty
                  ? {
                      'result': {'reaped': true},
                    }
                  : shutdownReplies.removeFirst(),
            });
          }
        }
        await writeGate?.future;
      }
    }
  }

  @override
  Future<String> shell(String id, String command, int timeoutMs) async {
    expect(id, 'exact-connection');
    commands.add(command);
    final operation = _open('shell');
    var response = 'removed\n', exit = 0;
    if (command.startsWith('while :')) {
      response = waitFailures-- > 0 ? 'unknown\n' : 'released:absent\n';
    } else if (command.contains('cmdline')) {
      response = wrongIdentity ? 'identity-mismatch\n' : 'signalled\n';
      if (wrongIdentity) exit = 41;
    }
    operations[operation]!.add(adbText(response, kind: 'stdout'));
    operations[operation]!.add(adbDone(kind: 'exit', exitCode: exit));
    return operation;
  }

  @override
  Future<NativeAdbEvent?> next(String id) {
    return operations[id]!.next();
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    if (id.startsWith('push') && uploadFailure) {
      throw const AdbException('native_adb', '真实上传结束尚未确认');
    }
    if (id == rpcId) {
      if (!cancelStarted.isCompleted) cancelStarted.complete();
      await writeGate?.future;
      if (!rpcCancelled.isCompleted) rpcCancelled.complete();
    }
    operations[id]!.close();
  }

  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
