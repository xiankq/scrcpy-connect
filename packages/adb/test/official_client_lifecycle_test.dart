import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:adb/src/official_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/owned_server_fake.dart';

Matcher _error(String code) =>
    throwsA(isA<AdbException>().having((e) => e.code, 'code', code));

Future<OfficialAdbClient> clientFor(
  OwnedServerFake api, {
  AdbServerInfo? server,
}) async {
  final client = OfficialAdbClient(api, server ?? await api.readyServer());
  addTearDown(() async {
    api.commandCloseGate = null;
    api.scopeCloseGate = null;
    await client.close();
    await api.dispose();
  });
  return client;
}

void main() {
  test('官方 push 与显式服务共用关闭责任', () async {
    final api = _ServiceOwnerFake();
    final root = await Directory.systemTemp.createTemp('official-service-');
    addTearDown(() async {
      await root.delete(recursive: true);
    });
    final client = await clientFor(api);
    addTearDown(() {
      if (!api.release.isCompleted) api.release.complete();
    });
    final device = await client.connect('target');
    final file = await File(p.join(root.path, 'file')).writeAsString('input');
    final running = client.push(device, file, '/file');
    final failed = expectLater(running, _error('cancelled'));
    await api.reading.future;
    var closed = false;
    final closing = client.services.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(api.cancelled, ['operation']);
    expect(closed, isFalse, reason: '取消通知不能代替原生操作释放确认');
    api.release.complete();
    await closing;
    await failed;
    expect(closed, isTrue);
    expect(api.connections, contains(device.id));
    await client.disconnect(device);
  });
  test('预取消不登记命令或启动原生握手', () async {
    final api = OwnedServerFake();
    final client = await clientFor(api);
    final stop = AdbCancellation()..cancel();
    await expectLater(
      client.connect('target', cancellation: stop),
      _error('cancelled'),
    );
    await expectLater(
      client.pair('target', 'code', cancellation: stop),
      _error('cancelled'),
    );
    expect(api.specs, isEmpty);
    expect(api.handshakes, isEmpty);
  });
  test('非法选项及期限不触及命令准入', () async {
    final api = OwnedServerFake();
    final client = await clientFor(api);
    await expectLater(
      client.connect('target', directOptions: const AdbConnectOptions()),
      _error('official_adb_controls_connection_options'),
    );
    await expectLater(
      client.connect('target', timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(api.specs, isEmpty);
  });
  test('确认真实 connected 回执后才释放命令，所有普通命令固定数字-H', () async {
    final api = OwnedServerFake();
    final client = await clientFor(api);
    final device = await client.connect('target');
    final connect = api.specs.keys.single;
    expect(api.confirmed, {connect});
    expect(api.commandCloses, [connect]);
    expect(api.arguments(connect), ['connect', 'target']);
    expect(api.specs[connect]!.arguments.take(3), ['-H', '127.0.0.1', '-P']);
    expect(device.id, isNot(device.serial));
    expect(identical(device.nativeOwner, api), isTrue);
  });
  test('原生明确启动失败不制造永久未知，后续连接仍可准入', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => AdbServerCommandResult(
        status: AdbServerCommandStatus.startFailed,
        exitCode: null,
        stdout: Uint8List(0),
        stderr: Uint8List(0),
        errorMessage: 'spawn rejected',
      );
    final client = await clientFor(api);
    await expectLater(client.connect('target'), _error('command_start_failed'));
    expect(api.specs, hasLength(1));
    expect(api.arguments(api.specs.keys.single), ['connect', 'target']);
    expect(api.entries.values.single.transportStateUnknown, isFalse);
    api.running = null;
    expect((await client.connect('other')).serial, 'other');
  });
  test('already connected 只有 get-state 为device才能确认active', () async {
    final api = OwnedServerFake()..connectPrefix = 'already connected to';
    final client = await clientFor(api);
    await client.connect('target');
    final commands = api.specs.keys.toList();
    expect(api.arguments(commands[1]), ['-s', 'target', 'get-state']);
    expect(api.confirmed, {commands.first});
    expect(api.commandCloses, [commands[1], commands[0]]);
  });
  for (final probe in [
    (state: '', exit: 1),
    (state: 'unauthorized', exit: 0),
    (state: 'device', exit: 1),
  ]) {
    test(
      'already connected 的${probe.state}/${probe.exit}不能确认，unknown跨client保留',
      () async {
        final api = OwnedServerFake()
          ..connectPrefix = 'already connected to'
          ..probeState = probe.state
          ..probeExit = probe.exit;
        final server = await api.readyServer();
        final first = await clientFor(api, server: server);
        await expectLater(
          first.connect('target'),
          _error('official_connect_result_unknown'),
        );
        expect(api.confirmed, isEmpty);
        final second = await clientFor(api, server: server);
        await expectLater(
          second.connect('other-target'),
          _error('official_connect_result_unknown'),
        );
        await expectLater(
          second.devices(),
          _error('official_connect_result_unknown'),
        );
        expect(api.opened, isEmpty);
      },
    );
  }
  test('关闭等待迟到命令准入，登记后只回收不运行', () async {
    final api = OwnedServerFake();
    final gate = Completer<void>();
    api.createCommandGate = gate.future;
    final client = await clientFor(api);
    final opening = expectLater(
      client.connect('target'),
      _error('server_closed'),
    );
    while (api.specs.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    var closed = false;
    final closing = client.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await opening;
    await closing;
    expect(api.issued, isEmpty);
    expect(api.commandCloses, hasLength(1));
  });
  test('取消通知原生命令且等待实际收尾，未知状态拒绝其它目标', () async {
    final api = OwnedServerFake();
    final running = Completer<void>(),
        cancelled = Completer<void>(),
        done = Completer<void>();
    api.running = (id, spec) async {
      running.complete();
      await done.future;
      return AdbServerCommandResult(
        status: AdbServerCommandStatus.cancelled,
        exitCode: null,
        stdout: Uint8List(0),
        stderr: Uint8List(0),
      );
    };
    api.cancelling = (_) {
      if (!cancelled.isCompleted) cancelled.complete();
    };
    final client = await clientFor(api);
    final stop = AdbCancellation();
    var finished = false;
    final result = expectLater(
      client.connect('target', cancellation: stop).whenComplete(() {
        finished = true;
      }),
      _error('official_connect_result_unknown'),
    );
    await running.future;
    stop.cancel();
    await cancelled.future;
    expect(finished, isFalse);
    done.complete();
    await result;
    await expectLater(
      client.connect('different'),
      _error('official_connect_result_unknown'),
    );
  });
  test('命令清理失败保留同ID，关闭确认前不返回且失败后可重试', () async {
    final api = OwnedServerFake()..commandCloseFailures = 1;
    final client = await clientFor(api);
    await expectLater(client.connect('target'), throwsStateError);
    final id = api.specs.keys.first;
    api.commandCloseFailures = 1;
    await expectLater(client.close(), throwsStateError);
    expect(api.commandLeases, contains(id));
    await expectLater(client.connect('other'), _error('server_closed'));
    await client.close();
    expect(api.commandLeases, isNot(contains(id)));
    expect(api.commandCloses.where((value) => value == id), hasLength(3));
  });
  test('配对确认成功不被命令close失败覆盖，close保留精确重试', () async {
    final api = OwnedServerFake()..commandCloseFailures = 1;
    final client = await clientFor(api);
    expect(await client.pair('target', 'secret'), 'actual-guid');
    final id = api.specs.keys.single;
    expect(api.commandLeases, contains(id));
    expect(String.fromCharCodes(api.specs[id]!.input), 'secret\n');
    await client.close();
    expect(api.commandCloses, [id, id]);
  });
  test('配对失败明确可能已建立对端信任', () async {
    final api = OwnedServerFake()
      ..running = (_, _) async => commandResult('failed', exit: 1);
    final client = await clientFor(api);
    await expectLater(
      client.pair('target', 'secret'),
      throwsA(
        isA<AdbException>().having(
          (e) => e.message,
          'message',
          contains('可能已建立信任'),
        ),
      ),
    );
  });
  test('成功后的命令收尾仍属于connect准入，期间关闭不交付连接', () async {
    final api = OwnedServerFake();
    final gate = Completer<void>();
    api.commandCloseGate = gate.future;
    final client = await clientFor(api);
    final result = expectLater(
      client.connect('target'),
      throwsA(isA<AdbException>()),
    );
    while (api.commandCloses.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    var closed = false;
    final closing = client.close().then((_) {
      closed = true;
    });
    expect(closed, isFalse);
    gate.complete();
    await result;
    await closing;
    expect(api.opened, isEmpty);
  });
  test('迟到smart socket握手登记绑定原server lease并被精确回收', () async {
    final api = OwnedServerFake();
    final gate = Completer<String>();
    final creating = Completer<void>();
    api.handshakeCreating = () {
      creating.complete();
      return gate.future;
    };
    final client = await clientFor(api);
    final result = expectLater(
      client.connect('target'),
      throwsA(isA<AdbException>()),
    );
    await creating.future;
    var closed = false;
    final closing = client.close().then((_) {
      closed = true;
    });
    gate.complete('late-handshake');
    await result;
    await closing;
    expect(closed, isTrue);
    expect(api.handshakeCloses, ['late-handshake']);
    expect(api.opened, isEmpty);
  });
  test('smart socket迟到连接释放失败仍保留原ID重试', () async {
    final api = OwnedServerFake();
    final gate = Completer<AdbDevice>();
    api.connecting = (_) => gate.future;
    final client = await clientFor(api);
    final opening = expectLater(client.connect('target'), throwsStateError);
    while (api.opened.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    api.disconnectFailures = 2;
    final closing = expectLater(client.close(), throwsStateError);
    gate.complete(
      const AdbDevice(id: 'late-exact', serial: 'target', state: 'device'),
    );
    await opening;
    await closing;
    await client.close();
    expect(api.disconnected, everyElement('late-exact'));
    expect(api.disconnected, hasLength(3));
  });
  test('原生握手结束等待期间取消不交付已分配连接', () async {
    final api = OwnedServerFake();
    final closing = Completer<void>(), release = Completer<void>();
    api.handshakeClosing = (_) async {
      if (!closing.isCompleted) closing.complete();
      await release.future;
    };
    final client = await clientFor(api);
    final stop = AdbCancellation();
    final result = expectLater(
      client.connect('target', cancellation: stop),
      _error('cancelled'),
    );
    await closing.future;
    stop.cancel();
    release.complete();
    await result;
    expect(api.disconnected, hasLength(1));
  });
  test('重连后的旧句柄和离线占位不能关闭后继连接', () async {
    final api = OwnedServerFake();
    final client = await clientFor(api);
    final first = await client.connect('target');
    final next = await client.connect('target');
    expect(api.disconnected, [first.id]);
    await expectLater(client.disconnect(first), _error('unknown_connection'));
    await expectLater(
      client.disconnect(
        const AdbDevice(id: 'target', serial: 'target', state: 'offline'),
      ),
      _error('unknown_connection'),
    );
    expect(api.connections, contains(next.id));
    await client.disconnect(next);
  });
  test('不同客户端精确句柄互不拥有，跨宿主句柄在派发前拒绝', () async {
    final api = OwnedServerFake();
    final server = await api.readyServer();
    final first = await clientFor(api, server: server),
        second = await clientFor(api, server: server);
    final a = await first.connect('target'), b = await second.connect('target');
    await expectLater(first.disconnect(b), _error('unknown_connection'));
    await expectLater(
      first.disconnect(
        AdbDevice(
          id: a.id,
          serial: a.serial,
          state: a.state,
          nativeOwner: Object(),
        ),
      ),
      _error('foreign_native_host'),
    );
    await first.close();
    expect(api.connections, contains(b.id));
    expect(api.disconnected, [a.id]);
  });
}

/// 将普通服务固定在原生读取阶段，核验实际关闭登记而不依赖私有集合。
class _ServiceOwnerFake extends OwnedServerFake {
  final reading = Completer<void>();
  final release = Completer<void>();
  final result = Completer<NativeAdbEvent?>();
  final cancelled = <String>[];

  @override
  Future<String> shell(String id, String command, int timeoutMs) async =>
      'operation';

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async =>
      'operation';

  @override
  Future<NativeAdbEvent?> next(String id) {
    reading.complete();
    return result.future;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    await release.future;
    result.complete(null);
  }
}
