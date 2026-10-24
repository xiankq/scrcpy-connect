import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/companion/companion_client.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';

const _config = CompanionConfig(
  startupTimeout: Duration(seconds: 2),
  requestTimeout: Duration(seconds: 2),
  cleanupTimeout: Duration(seconds: 2),
  sessionTimeout: Duration(minutes: 1),
);

void main() {
  test('上传精确已核验字节，分片 UTF-8 帧和真实远端错误通过同一 RPC', () async {
    final fixture = _Fixture();
    final initial = await fixture.companion.start();
    expect(initial['protocol'], 1);
    expect(fixture.api.uploaded, [1, 2, 3]);
    expect(fixture.api.auth!['token'], matches(r'^[0-9a-f]{64}$'));
    final written = fixture.api.requests.stream.first;
    final result = fixture.companion.request(
      'apps.list',
      const {},
      mutation: false,
    );
    final request = await written;
    fixture.api.message({
      'requestId': request['requestId'],
      'result': {'name': '相机😀'},
    }, split: true);
    expect(await result, {'name': '相机😀'});
    final secondWritten = fixture.api.requests.stream.first;
    final rejected = expectLater(
      fixture.companion.request('apps.icon', const {}, mutation: false),
      throwsA(_code('permission_denied')),
    );
    final second = await secondWritten;
    fixture.api.message({
      'requestId': second['requestId'],
      'error': {'code': 'permission_denied', 'message': '真实权限错误'},
    });
    await rejected;
    await fixture.companion.close();
    expect(fixture.api.disconnected, isEmpty);
    expect(fixture.api.live, isEmpty);
  });

  test('并发请求按 requestId 对应，已发动作取消为未知，迟到回执不污染后继', () async {
    final fixture = _Fixture();
    await fixture.companion.start();
    final seen = <Map<String, Object?>>[];
    final both = Completer<void>();
    final subscription = fixture.api.requests.stream.listen((request) {
      seen.add(request);
      if (seen.length == 2) both.complete();
    });
    final cancellation = AdbCancellation();
    final first = expectLater(
      fixture.companion.request(
        'notifications.open',
        const {},
        mutation: true,
        cancellation: cancellation,
      ),
      throwsA(_code('result_unknown')),
    );
    final second = fixture.companion.request(
      'calls.list',
      const {},
      mutation: false,
    );
    await both.future;
    cancellation.cancel();
    await first;
    fixture.api.message({'requestId': seen[0]['requestId'], 'result': '旧动作迟到'});
    fixture.api.message({'requestId': seen[1]['requestId'], 'result': '当前读取'});
    expect(await second, '当前读取');
    await subscription.cancel();
    await fixture.companion.close();
  });

  test('预取消不上传，排队取消不发出请求，也不伪报副作用未知', () async {
    final cancelled = AdbCancellation()..cancel();
    final unopened = _Fixture();
    expect(
      () => unopened.companion.start(cancellation: cancelled),
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(unopened.api.created, isEmpty);
    await unopened.companion.close();

    final fixture = _Fixture();
    await fixture.companion.start();
    fixture.api.writeGate = Completer<void>();
    final written = fixture.api.requests.stream.first;
    final first = fixture.companion.request(
      'apps.list',
      const {},
      mutation: false,
    );
    final firstMessage = await written;
    final cancellation = AdbCancellation();
    final pending = expectLater(
      fixture.companion.request(
        'notifications.open',
        const {},
        mutation: true,
        cancellation: cancellation,
      ),
      throwsA(_code('cancelled')),
    );
    cancellation.cancel();
    await pending;
    fixture.api.writeGate!.complete();
    fixture.api.message({'requestId': firstMessage['requestId'], 'result': []});
    expect(await first, isEmpty);
    expect(fixture.api.receivedCommands, ['apps.list']);
    await fixture.companion.close();
  });

  test('超出并发容量拒绝新动作，不取消已发读取', () async {
    final fixture = _Fixture(
      config: const CompanionConfig(
        startupTimeout: Duration(seconds: 2),
        requestTimeout: Duration(seconds: 2),
        cleanupTimeout: Duration(seconds: 2),
        sessionTimeout: Duration(minutes: 1),
        maximumPendingRequests: 1,
      ),
    );
    await fixture.companion.start();
    final written = fixture.api.requests.stream.first;
    final read = fixture.companion.request(
      'apps.list',
      const {},
      mutation: false,
    );
    final request = await written;
    expect(
      () => fixture.companion.request(
        'notifications.open',
        const {},
        mutation: true,
      ),
      throwsA(_code('busy')),
    );
    fixture.api.message({'requestId': request['requestId'], 'result': []});
    await read;
    await fixture.companion.close();
  });

  test('暂停事件有界，溢出明确失效，不生成无限缓冲或继续发送动作', () async {
    final fixture = _Fixture(
      config: const CompanionConfig(
        startupTimeout: Duration(seconds: 2),
        requestTimeout: Duration(seconds: 2),
        cleanupTimeout: Duration(seconds: 2),
        sessionTimeout: Duration(minutes: 1),
        maximumQueuedEvents: 2,
      ),
    );
    await fixture.companion.start();
    final events = <Object?>[];
    final done = Completer<void>();
    final stream = fixture.companion.events.listen(
      events.add,
      onError: (Object error) => events.add(error),
      onDone: done.complete,
    );
    stream.pause();
    fixture.api.message({'event': 'notifications.changed', 'revision': 1});
    fixture.api.message({'event': 'notifications.changed', 'revision': 2});
    fixture.api.message({'event': 'notifications.changed', 'revision': 3});
    await fixture.api.rpcCancelled.future;
    expect(
      () => fixture.companion.request('apps.list', const {}, mutation: false),
      throwsA(_code('event_limit')),
    );
    stream.resume();
    await done.future;
    expect(events.whereType<Map<String, Object?>>().length, 2);
    expect(events.last, _code('event_limit'));
    await fixture.companion.close();
  });

  test('协议身份必须是整数且匹配 shell UID，失败仍清理精确原进程', () async {
    final fixture = _Fixture();
    fixture.api.ready['uid'] = 2000.0;
    await expectLater(
      fixture.companion.start(),
      throwsA(_code('protocol_error')),
    );
    expect(fixture.companion.deploymentIdentity?.pid, 77);
    await fixture.companion.close();
    expect(fixture.api.commands.last, contains('rm -f --'));
  });

  test('无换行超长输入终止 RPC，读取失败不会被空列表替代', () async {
    final fixture = _Fixture(
      config: const CompanionConfig(
        startupTimeout: Duration(seconds: 2),
        requestTimeout: Duration(seconds: 2),
        cleanupTimeout: Duration(seconds: 2),
        sessionTimeout: Duration(minutes: 1),
        maximumMessageBytes: 256,
      ),
    );
    await fixture.companion.start();
    final written = fixture.api.requests.stream.first;
    final rejected = expectLater(
      fixture.companion.request('apps.list', const {}, mutation: false),
      throwsA(_code('disconnected')),
    );
    await written;
    fixture.api.raw(Uint8List(257));
    await rejected;
    expect(
      () => fixture.companion.request('apps.list', const {}, mutation: false),
      throwsA(_code('protocol_error')),
    );
    await fixture.companion.close();
  });

  test('关闭等待在途写入实际取消排空，失败保留精确关闭权且不先删除 JAR', () async {
    final fixture = _Fixture();
    await fixture.companion.start();
    fixture.api.writeGate = Completer<void>();
    final written = fixture.api.requests.stream.first;
    final request = expectLater(
      fixture.companion.request('apps.list', const {}, mutation: false),
      throwsA(_code('cancelled')),
    );
    await written;
    final closing = fixture.companion.close();
    await fixture.api.cancelStarted.future;
    expect(fixture.api.commands, isEmpty);
    fixture.api.writeGate!.complete();
    await closing;
    await request;
    expect(fixture.api.commands.last, contains('rm -f --'));
    expect(fixture.api.live, isEmpty);
  });

  test('远端退出核验首败不删部署，重试只清理同 PID/starttime 与唯一名称', () async {
    final fixture = _Fixture();
    await fixture.companion.start();
    final identity = fixture.companion.deploymentIdentity!;
    fixture.api.waitFailures = 1;
    await expectLater(
      fixture.companion.close(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    expect(fixture.companion.deploymentIdentity, same(identity));
    expect(
      fixture.api.commands.any((command) => command.startsWith('rm -f --')),
      isFalse,
    );
    await fixture.companion.close();
    expect(fixture.api.commands.first, contains('expected=9001'));
    expect(fixture.api.commands.first, contains(identity.niceName));
    expect(
      fixture.api.commands.any((command) => command.contains('killall')),
      isFalse,
    );
    expect(fixture.companion.deploymentIdentity, isNull);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('已知部署恢复拒绝同 PID 的错误身份，不删除 JAR 或误停后继进程', () async {
    final fixture = _Fixture();
    final identity = CompanionDeploymentIdentity(
      pid: 77,
      started: 9001,
      jarPath: '/data/local/tmp/interop-companion-${'a' * 32}.jar',
    );
    final restored = CompanionDeploymentIdentity.fromJson(identity.toJson());
    fixture.api.wrongIdentity = true;
    await expectLater(
      cleanupCompanionDeployment(
        fixture.connection,
        restored,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(_code('remote_process_error')),
    );
    expect(fixture.api.commands.length, 1);
    expect(fixture.api.commands.single, contains('expected=9001'));
    expect(fixture.api.commands.single, contains(identity.niceName));
    expect(fixture.api.disconnected, isEmpty);
    await fixture.companion.close();
  });

  test('认证已写出但 ready 未到时关闭，会实际排空并结束启动等待', () async {
    final fixture = _Fixture();
    fixture.api.sendReady = false;
    final starting = expectLater(
      fixture.companion.start(),
      throwsA(_code('closed')),
    );
    await fixture.api.authReceived.future;
    await fixture.companion.close();
    await starting;
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.commands.last, contains('rm -f --'));
  });

  test('exec 创建迟到且身份尚未交付，不把本机关闭当作远端退出证明', () async {
    final fixture = _Fixture();
    fixture.api.execGate = Completer<void>();
    final cancellation = AdbCancellation();
    final starting = expectLater(
      fixture.companion.start(cancellation: cancellation),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    await fixture.api.execCreated.future;
    cancellation.cancel();
    fixture.api.execGate!.complete();
    await starting;
    await expectLater(
      fixture.companion.close(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.commands, isEmpty);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('关闭先取得媒体子进程 reaped 回执，再结束认证 socket 与原进程', () async {
    final fixture = _Fixture();
    await fixture.companion.start();
    final written = fixture.api.requests.stream.first;
    final request = fixture.companion.request('media.stat', const {
      'operationId': '00000000-0000-0000-0000-000000000000',
    }, mutation: false);
    final message = await written;
    fixture.api.message({
      'requestId': message['requestId'],
      'result': {'size': 7},
    });
    await request;
    await fixture.companion.close();
    expect(fixture.api.receivedCommands, ['media.stat', 'media.shutdown']);
    expect(fixture.api.commands.last, contains('rm -f --'));
  });

  for (final firstReply in <Map<String, Object?>>[
    {
      'result': {'reaped': false},
    },
    {
      'error': {'code': 'busy', 'message': '远端仍在清理'},
    },
  ]) {
    test('shutdown有效首败保留同socket，第二次真实reaped成功才释放：$firstReply', () async {
      final fixture = await _mediaFixture();
      final rpc = fixture.api.rpcId;
      fixture.api.shutdownReplies.add(firstReply);
      await expectLater(
        fixture.companion.close(),
        throwsA(_code('cleanup_unconfirmed')),
      );
      expect(fixture.api.live, contains(rpc));
      expect(fixture.api.commands, isEmpty);
      expect(fixture.api.cancelStarted.isCompleted, isFalse);
      expect(
        () => fixture.companion.request('apps.list', const {}, mutation: false),
        throwsA(_code('closed')),
      );
      await fixture.companion.close();
      expect(fixture.api.rpcId, rpc);
      expect(fixture.api.created.where((id) => id.startsWith('rpc')).length, 1);
      expect(fixture.api.receivedCommands, [
        'media.stat',
        'media.shutdown',
        'media.shutdown',
      ]);
      expect(fixture.api.live, isEmpty);
      expect(fixture.api.commands.last, contains('rm -f --'));
    });
  }

  test('shutdown期间通道断开仍核验精确主进程，但不把它当子进程reaped', () async {
    final fixture = await _mediaFixture();
    final identity = fixture.companion.deploymentIdentity!;
    fixture.api.disconnectOnShutdown = true;
    await expectLater(
      fixture.companion.close(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.commands.length, 2);
    expect(fixture.api.commands.first, contains(identity.niceName));
    expect(fixture.api.commands.last, contains('expected=9001'));
    expect(
      fixture.api.commands.any((command) => command.startsWith('rm -f --')),
      isFalse,
    );
    expect(fixture.companion.deploymentIdentity, same(identity));
    await expectLater(
      fixture.companion.close(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    expect(fixture.api.disconnected, isEmpty);
  });

  test('上传关闭首败保留精确session，重试成功且共享shell仍可用', () async {
    final fixture = _Fixture();
    fixture.api.uploadFailure = true;
    await expectLater(
      fixture.companion.start(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    final upload = fixture.api.created.single;
    await expectLater(
      fixture.companion.close(),
      throwsA(_code('cleanup_unconfirmed')),
    );
    expect(fixture.api.live, {upload});
    expect(fixture.api.commands, isEmpty);
    final shell = await fixture.connection.client
        .shell(fixture.connection.device, 'independent')
        .toList();
    expect(shell.expand((event) => event.bytes), isNotEmpty);
    expect(fixture.api.live, {upload});
    fixture.api.uploadFailure = false;
    await fixture.companion.close();
    expect(
      fixture.api.cancelled.where((id) => id.startsWith('push')),
      isNotEmpty,
    );
    expect(fixture.api.cancelled.where((id) => id.startsWith('push')).toSet(), {
      upload,
    });
    expect(fixture.api.created.where((id) => id.startsWith('push')).length, 1);
    expect(fixture.api.commands.last, contains('rm -f --'));
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('上传创建迟到时close不提前完成，等待原session返回并精确排空', () async {
    final fixture = _Fixture();
    fixture.api.uploadGate = Completer<void>();
    final starting = expectLater(
      fixture.companion.start(),
      throwsA(
        isA<AdbException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    await fixture.api.uploadCreated.future;
    var closed = false;
    final closing = fixture.companion.close().then((_) => closed = true);
    expect(closed, isFalse);
    expect(fixture.api.cancelled, isEmpty);
    expect(fixture.api.live.length, 1);
    fixture.api.uploadGate!.complete();
    await starting;
    await closing;
    final upload = fixture.api.created.first;
    expect(fixture.api.cancelled, contains(upload));
    expect(fixture.api.created.any((id) => id.startsWith('exec')), isFalse);
    expect(fixture.api.uploaded, isEmpty);
    expect(fixture.api.live, isEmpty);
    expect(fixture.api.commands.single, contains('rm -f --'));
    expect(fixture.api.disconnected, isEmpty);
  });
}

Future<_Fixture> _mediaFixture() async {
  final fixture = _Fixture();
  await fixture.companion.start();
  final written = fixture.api.requests.stream.first;
  final request = fixture.companion.request('media.stat', const {
    'operationId': '00000000-0000-0000-0000-000000000000',
  }, mutation: false);
  final message = await written;
  fixture.api.message({
    'requestId': message['requestId'],
    'result': {'size': 7},
  });
  await request;
  return fixture;
}

Matcher _code(String code) =>
    isA<CompanionException>().having((error) => error.code, 'code', code);

class _Fixture {
  _Fixture({CompanionConfig config = _config}) {
    final client = NativeAdbClient(api, '/unused/key');
    connection = DeviceConnection(
      client: client,
      device: AdbDevice(
        id: 'exact-connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: api,
      ),
    );
    companion = CompanionClient(
      connection: connection,
      serverBytes: Uint8List.fromList([1, 2, 3]),
      config: config,
    );
  }
  final api = _Api();
  late final DeviceConnection connection;
  late final CompanionClient companion;
}

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

class _Api implements NativeAdbApi {
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

  void raw(Uint8List bytes) => operations[rpcId]!.add(
    NativeAdbEvent(kind: 'data', bytes: bytes, done: false),
  );
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
        NativeAdbEvent(
          kind: 'data',
          done: false,
          bytes: Uint8List.fromList(
            utf8.encode('__INTEROP_PID__77:9001\nINTEROP_COMPANION_READY 77\n'),
          ),
        ),
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
    if (!uploadCreated.isCompleted) uploadCreated.complete();
    await uploadGate?.future;
    return operation;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    if (id.startsWith('push')) {
      if (input.kind == AdbInputKind.bytes) uploaded.addAll(input.bytes);
      if (input.kind == AdbInputKind.finish) {
        operations[id]!.add(
          NativeAdbEvent(
            kind: 'done',
            bytes: Uint8List(0),
            done: true,
            transferred: uploaded.length,
          ),
        );
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
        if (message['command'] == 'media.shutdown') {
          expect(
            message['operationId'],
            matches(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          );
          if (disconnectOnShutdown) {
            operations[rpcId]!.close();
          } else {
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
    operations[operation]!.add(
      NativeAdbEvent(
        kind: 'stdout',
        bytes: Uint8List.fromList(utf8.encode(response)),
        done: false,
      ),
    );
    operations[operation]!.add(
      NativeAdbEvent(
        kind: 'exit',
        bytes: Uint8List(0),
        done: true,
        exitCode: exit,
      ),
    );
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
