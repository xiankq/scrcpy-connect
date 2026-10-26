import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/media/physical_display_recovery.dart';

const _owner = '0123456789abcdef0123456789abcdef';
const _successor = 'fedcba9876543210fedcba9876543210';

void main() {
  test('公开 ADB 流先发现并授权原 owner，DONE 之后才 ACK', () async {
    final f = _Fixture();
    await f.recovery.recover(f.connection);
    expect(f.api.trace.where((v) => !v.startsWith('close:')), [
      'discover:$_owner',
      'recover:$_owner',
      'ack:$_owner',
    ]);
    expect(f.api.operations.length, 2);
    expect(f.api.operations.values.every((o) => o.closed), isTrue);
    await f.recovery.close();
    expect(f.api.operations.length, 2);
  });

  test('发现回执早于脚本写入返回，授权仍遵守真实 SDK 单写者约束', () async {
    final f = _Fixture();
    f.api.uploadGate = Completer<void>();
    final pending = f.recovery.recover(f.connection);
    await f.api.discoverySent.future;
    await Future<void>.delayed(Duration.zero);
    expect(f.api.trace.where((v) => v.startsWith('recover:')), isEmpty);
    f.api.uploadGate!.complete();
    await pending;
    expect(f.api.trace, contains('recover:$_owner'));
    await f.recovery.close();
  });

  test('明确 empty 不发送恢复或 ACK', () async {
    final f = _Fixture();
    f.api.current = null;
    await f.recovery.recover(f.connection);
    expect(f.api.trace.where((v) => !v.startsWith('close:')), [
      'discover:empty',
    ]);
    await f.recovery.close();
  });

  test('发现后结果未知，重试只沿原 owner 而不扫描后继', () async {
    final f = _Fixture();
    f.api.failRestore = true;
    await expectLater(f.recovery.recover(f.connection), throwsA(_unknown));
    f.api.current = _successor;
    f.api.failRestore = false;
    await f.recovery.recover(f.connection);
    expect(f.api.trace.where((v) => v.startsWith('discover:')).length, 1);
    expect(f.api.trace.where((v) => v.startsWith('recover:')), [
      'recover:$_owner',
      'recover:$_owner',
    ]);
    expect(f.api.trace, contains('ack:$_owner'));
    expect(f.api.current, _successor);
    await f.recovery.close();
  });

  test('ACK 回执丢失仅重试同 owner ACK，不重复恢复', () async {
    final f = _Fixture();
    f.api.loseAck = true;
    await expectLater(f.recovery.recover(f.connection), throwsA(_unknown));
    f.api.current = _successor;
    f.api.loseAck = false;
    await f.recovery.recover(f.connection);
    expect(f.api.trace.where((v) => v.startsWith('recover:')).length, 1);
    expect(f.api.trace.where((v) => v.startsWith('ack:')), [
      'ack:$_owner',
      'ack:$_owner',
    ]);
    await f.recovery.close();
  });

  test('本机关闭失败保留原流，下一轮先精确释放再 ACK', () async {
    final f = _Fixture();
    f.api.closeFailures.add('operation-1');
    await expectLater(f.recovery.recover(f.connection), throwsA(_unknown));
    await expectLater(
      f.recovery.stopForConnection(f.connection),
      throwsA(_unknown),
    );
    expect(f.api.operations.length, 1);
    expect(f.api.operations.values.single.closed, isFalse);
    f.api.closeFailures.clear();
    await f.recovery.stopForConnection(f.connection);
    final acknowledged = f.api.trace.indexOf('ack:$_owner');
    expect(
      acknowledged,
      greaterThan(f.api.trace.lastIndexOf('close:operation-1')),
    );
    expect(f.api.operations.values.every((o) => o.closed), isTrue);
    await f.recovery.close();
  });

  test('完整 DONE 也必须等待脚本流结束才 ACK', () async {
    final f = _Fixture();
    f.api.holdTerminal = true;
    var completed = false;
    final recovering = f.recovery
        .recover(f.connection)
        .then((_) => completed = true);
    await f.api.doneSent.future;
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(f.api.trace.where((v) => v.startsWith('ack:')), isEmpty);
    f.api.holdTerminal = false;
    f.api.operations.values.first.end();
    await recovering;
    await f.recovery.close();
  });

  test('冲突发现回执后真实 DONE 不抹掉本次协议错误，停止仍能结清旧 owner', () async {
    final f = _Fixture();
    f.api.conflictingDiscovery = true;
    await expectLater(f.recovery.recover(f.connection), throwsA(_unknown));
    expect(f.api.trace.where((v) => v.startsWith('ack:')), isEmpty);
    f.api.conflictingDiscovery = false;
    await f.recovery.stopForConnection(f.connection);
    expect(f.api.trace, contains('ack:$_owner'));
    expect(f.api.trace.where((v) => v.startsWith('discover:')).length, 1);
    await f.recovery.close();
  });

  test('取消仍等迟到创建，stop 排空原流再恢复且不关闭并行连接', () async {
    final f = _Fixture();
    f.api.creationGate = Completer<void>();
    final cancellation = AdbCancellation();
    final pending = f.recovery.recover(
      f.connection,
      cancellation: cancellation,
    );
    final failure = expectLater(
      pending,
      throwsA(isA<AdbException>().having((e) => e.code, 'code', 'cancelled')),
    );
    await f.api.created.future;
    final foreign = await f.connection.client.services.exec(
      AdbDevice(
        id: 'foreign',
        serial: 'other',
        state: 'device',
        nativeOwner: f.api,
      ),
      'foreign-shell',
    );
    cancellation.cancel();
    var stopped = false;
    final stopping = f.recovery
        .stopForConnection(f.connection)
        .then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    f.api.creationGate!.complete();
    await failure;
    await stopping;
    expect(f.api.operations['operation-1']!.closed, isTrue);
    expect(f.api.operations[foreign.id]!.closed, isFalse);
    expect(f.api.trace, contains('ack:$_owner'));
    await foreign.close();
    await f.recovery.close();
  });

  test('物理断开 detach 等迟到创建并只关原流，失败保留但不新发恢复或 ACK', () async {
    final f = _Fixture();
    f.api.creationGate = Completer<void>();
    f.api.closeFailures.add('operation-1');
    final failure = expectLater(
      f.recovery.recover(f.connection),
      throwsA(_unknown),
    );
    await f.api.created.future;
    var detached = false;
    final detachFailure = expectLater(
      f.recovery
          .detachClosedConnection(f.connection)
          .then((_) => detached = true),
      throwsA(_unknown),
    );
    await Future<void>.delayed(Duration.zero);
    expect(detached, isFalse);
    f.api.creationGate!.complete();
    await failure;
    await detachFailure;
    expect(f.api.operations.values.single.closed, isFalse);
    expect(f.api.trace.where((v) => !v.startsWith('close:')), isEmpty);
    f.api.closeFailures.clear();
    await f.recovery.detachClosedConnection(f.connection);
    await f.recovery.close();
    expect(f.api.operations.length, 1);
    expect(f.api.operations.values.single.closed, isTrue);
    expect(f.api.trace.where((v) => !v.startsWith('close:')), isEmpty);
  });

  test('关闭一条 exact connection 不等待另一条恢复', () async {
    final f = _Fixture();
    final first = f.recovery.recover(f.connection);
    await first;
    final other = DeviceConnection(
      client: f.connection.client,
      device: AdbDevice(
        id: 'second',
        serial: 'serial',
        state: 'device',
        nativeOwner: f.api,
      ),
    );
    f.api.holdRestoration = true;
    final pending = f.recovery.recover(other);
    await f.api.authorization.future;
    await f.recovery.stopForConnection(f.connection);
    expect(f.api.operations.values.last.closed, isFalse);
    f.api.releaseRestoration();
    await pending;
    await f.recovery.close();
  });
}

final _unknown = isA<ApplicationCommandException>().having(
  (e) => e.code,
  'code',
  'display_recovery_unconfirmed',
);

final class _Fixture {
  _Fixture() {
    connection = DeviceConnection(
      client: NativeAdbClient(api, '/unused/key'),
      device: AdbDevice(
        id: 'connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: api,
      ),
    );
  }
  final api = _Api();
  final recovery = PhysicalDisplayRecovery(timeout: const Duration(seconds: 2));
  late final DeviceConnection connection;
}

// 夹具只模拟公开 ADB 流和远端协议回执，不实现恢复所有者的阶段状态机。
final class _Api implements NativeAdbApi {
  final operations = <String, _Operation>{};
  final trace = <String>[];
  final closeFailures = <String>{};
  final created = Completer<void>();
  Completer<void> authorization = Completer<void>();
  Completer<void>? creationGate, uploadGate;
  final discoverySent = Completer<void>();
  String? current = _owner;
  bool failRestore = false, loseAck = false, holdRestoration = false;
  bool holdTerminal = false, conflictingDiscovery = false;
  final doneSent = Completer<void>();
  final held = <(_Operation, String)>[];

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    final key = 'operation-${operations.length + 1}';
    operations[key] = _Operation();
    if (!created.isCompleted) created.complete();
    if (key == 'operation-1') await creationGate?.future;
    return key;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    final operation = operations[id]!;
    operation.input.write(utf8.decode(input.bytes));
    final data = operation.input.toString();
    if (!operation.injected &&
        data.contains('__INTEROP_DISPLAY_PROGRAM_END__\n')) {
      operation.injected = true;
      final token = RegExp("expected_owner='([0-9a-f]{32})'")
          .firstMatch(data)![1]!;
      if (data.contains('__DISPLAY_CURRENT__')) {
        trace.add('discover:${current ?? 'empty'}');
        operation.line('__DISPLAY_CURRENT__$token:${current ?? 'empty'}');
        if (!discoverySent.isCompleted) discoverySent.complete();
        if (conflictingDiscovery) {
          operation.line('__DISPLAY_CURRENT__$token:$_successor');
        }
        if (current == null) operation.end();
        await uploadGate?.future;
      } else if (data.contains('__DISPLAY_ACK__')) {
        trace.add('ack:$token');
        if (!loseAck) operation.line('__DISPLAY_ACK__$token');
        operation.end();
      } else {
        _restore(operation, token);
      }
    }
    final grant = RegExp(r'RECOVER:[0-9a-f]{32}:([0-9a-f]{32})\n')
        .firstMatch(data);
    if (grant != null && !operation.authorized) {
      operation.authorized = true;
      _restore(operation, grant[1]!);
    }
  }

  void _restore(_Operation operation, String owner) {
    trace.add('recover:$owner');
    if (holdRestoration) {
      held.add((operation, owner));
      if (!authorization.isCompleted) authorization.complete();
      return;
    }
    if (!failRestore) operation.line('__DISPLAY_DONE__$owner:restored');
    if (!doneSent.isCompleted) doneSent.complete();
    if (!holdTerminal) operation.end();
  }

  void releaseRestoration() {
    holdRestoration = false;
    for (final (operation, owner) in held) {
      operation.line('__DISPLAY_DONE__$owner:restored');
      operation.end();
    }
    held.clear();
  }

  @override
  Future<NativeAdbEvent?> next(String id) => operations[id]!.next();

  @override
  Future<void> cancel(String id) async {
    trace.add('close:$id');
    if (closeFailures.contains(id)) {
      throw const AdbException('cleanup_unconfirmed');
    }
    operations[id]!.closed = true;
    operations[id]!.end();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Operation {
  final input = StringBuffer();
  final queue = Queue<NativeAdbEvent>();
  Completer<void>? changed;
  bool injected = false, authorized = false, closed = false;
  void add(NativeAdbEvent event) {
    queue.add(event);
    changed?.complete();
    changed = null;
  }

  void line(String line) => add(
    NativeAdbEvent(
      kind: 'stdout',
      bytes: Uint8List.fromList(utf8.encode('$line\n')),
      done: false,
    ),
  );
  void end() => add(
    NativeAdbEvent(kind: 'exit', bytes: Uint8List(0), done: true, exitCode: 0),
  );
  Future<NativeAdbEvent?> next() async {
    while (queue.isEmpty) {
      changed = Completer<void>();
      await changed!.future;
    }
    return queue.removeFirst();
  }
}
