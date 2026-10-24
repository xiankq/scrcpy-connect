import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/owned_server_fake.dart';

Matcher _code(String code) =>
    throwsA(isA<AdbException>().having((e) => e.code, 'code', code));

void main() {
  late Directory directory, binary;
  late OwnedServerFake api;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('owned-adb-');
    binary = await Directory(p.join(directory.path, 'bin')).create();
    await File(p.join(binary.path, Platform.isWindows ? 'adb.exe' : 'adb'))
        .writeAsString('fixture');
    api = OwnedServerFake();
  });
  tearDown(() async {
    await api.dispose();
    await directory.delete(recursive: true);
  });
  Future<AdbHost> prepare({String? identityPath}) => AdbHost.prepare(
    dataDirectory: directory,
    binaryDirectory: binary,
    bindings: api,
    identityPath: identityPath,
  );
  Future<AdbHost> restore(AdbHost host) => AdbHost.restore(
    dataDirectory: directory,
    binaryDirectory: binary,
    bindings: api,
    nativeConfiguration: host.nativeConfiguration!,
  );

  test('prepare先登记原生server，再监督明确绝对chmod，独立keyhome不共写', () async {
    final first = await prepare(), second = await prepare();
    final a = first.nativeConfiguration!, b = second.nativeConfiguration!;
    expect(a['serverId'], isNot(b['serverId']));
    expect(a['keyDirectory'], isNot(b['keyDirectory']));
    expect(a['identityPath'], b['identityPath']);
    for (final spec in api.specs.values) {
      expect(spec.preparation, isTrue);
      expect(spec.mayCreateTransport, isFalse);
      expect(p.isAbsolute(spec.executable), isTrue);
      expect(spec.arguments, ['600', isA<String>()]);
      expect(spec.arguments, isNot(contains(a['identityPath'])));
    }
    await first.close();
    await second.close();
  });
  test('恢复仅认领native lease，保留server身份和密钥，不信任地图端点', () async {
    final original = await prepare();
    final configuration = original.nativeConfiguration!;
    final identity = File(configuration['identityPath'] as String);
    final bytes = await identity.readAsBytes(),
        modified = await identity.lastModified();
    final restored = await AdbHost.restore(
      dataDirectory: directory,
      binaryDirectory: binary,
      bindings: api,
      nativeConfiguration: {
        ...configuration,
        'host': 'foreign',
        'port': 5037,
        'executablePath': '/untrusted',
      },
    );
    expect(
      restored.nativeConfiguration!['serverId'],
      configuration['serverId'],
    );
    expect(restored.nativeConfiguration!['port'], configuration['port']);
    expect(
      restored.nativeConfiguration!['leaseId'],
      isNot(configuration['leaseId']),
    );
    expect(await identity.readAsBytes(), bytes);
    expect(await identity.lastModified(), modified);
    await original.close();
    expect(
      await Directory(configuration['keyDirectory'] as String).exists(),
      isTrue,
    );
    expect(api.entries.values.single.phase, AdbServerPhase.ready);
    await restored.close();
    expect(
      await Directory(configuration['keyDirectory'] as String).exists(),
      isFalse,
    );
  });
  test('启动探测期间被认领后失败，旧prepare不能删除新owner的keyhome', () async {
    AdbHost? restored;
    AdbServerInfo? started;
    api.readinessReply = 'FAIL00040000';
    api.onProbe = () async {
      started = api.entries.values.single;
      restored = await AdbHost.restore(
        dataDirectory: directory,
        binaryDirectory: binary,
        bindings: api,
        leaseId: started!.leaseId,
      );
      // 即便 Child 已退出，登记仍由新 owner 负责；不能把 exited 当成已排空。
      final current = api.entries.values.single;
      api.entries[current.serverId] = AdbServerInfo(
        serverId: current.serverId,
        leaseId: current.leaseId,
        launch: current.launch,
        phase: AdbServerPhase.exited,
        transportStateUnknown: false,
        pid: current.pid,
        exitCode: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    };
    await expectLater(
      AdbHost.prepare(
        dataDirectory: directory,
        binaryDirectory: binary,
        bindings: api,
        startupTimeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<SocketException>()),
    );
    final owner = restored!;
    final home = Directory(
      owner.nativeConfiguration!['keyDirectory'] as String,
    );
    expect(api.closedLeases, [started!.leaseId]);
    expect(
      api.entries.values.single.leaseId,
      owner.nativeConfiguration!['leaseId'],
    );
    expect(await home.exists(), isTrue);
    expect(await File(p.join(home.path, 'global', 'adbkey')).exists(), isTrue);
    await owner.close();
    expect(api.entries, isEmpty);
    expect(await home.exists(), isFalse);
  });
  test('无lease或过期lease拒绝恢复，不探测并关闭地图端口', () async {
    await expectLater(
      AdbHost.restore(
        dataDirectory: directory,
        bindings: api,
        nativeConfiguration: const {'host': '127.0.0.1', 'port': 5037},
      ),
      _code('invalid_host_configuration'),
    );
    await expectLater(
      AdbHost.restore(
        dataDirectory: directory,
        bindings: api,
        leaseId: 'absent',
      ),
      _code('host_unavailable'),
    );
    expect(api.closedLeases, isEmpty);
  });
  test('同旧lease的重复恢复不能撤销已发出的新lease', () async {
    final original = await prepare();
    final restored = await restore(original);
    await expectLater(restore(original), _code('host_unavailable'));
    expect(
      api.entries.values.single.leaseId,
      restored.nativeConfiguration!['leaseId'],
    );
    await original.close();
    await restored.close();
  });
  test('fake同server串行CAS：排队旧claim和旧close不能夺取或关闭新lease', () async {
    final original = await prepare();
    final oldLease = original.nativeConfiguration!['leaseId'] as String;
    final command = await api.createServerCommand(
      oldLease,
      AdbServerCommandSpec(
        executable: '/controlled/adb',
        arguments: const ['echo'],
        input: Uint8List(0),
        timeoutMs: 1000,
      ),
    );
    final release = Completer<void>();
    api.commandCloseGate = release.future;
    final first = api.claimServer(oldLease);
    while (!api.commandCloses.contains(command)) {
      await Future<void>.delayed(Duration.zero);
    }
    final competing = expectLater(
      api.claimServer(oldLease),
      _code('stale_server_lease'),
    );
    final lateClose = api.closeServer(oldLease);
    release.complete();
    final claimed = await first;
    await competing;
    await lateClose;
    expect(api.entries.values.single.leaseId, claimed.leaseId);
    expect(api.entries.values.single.phase, AdbServerPhase.ready);
    await original.close();
    expect(api.entries.values.single.leaseId, claimed.leaseId);
    await api.closeServer(claimed.leaseId);
    expect(api.entries, isEmpty);
  });
  test('close-only unknown跨认领保留，直到原server真实关闭', () async {
    final original = await prepare();
    final old = api.entries.values.single;
    api.entries[old.serverId] = AdbServerInfo(
      serverId: old.serverId,
      leaseId: old.leaseId,
      launch: old.launch,
      phase: old.phase,
      transportStateUnknown: true,
      pid: old.pid,
    );
    final restored = await restore(original);
    await expectLater(
      restored.client.connect('different'),
      _code('official_connect_result_unknown'),
    );
    await expectLater(
      restored.client.devices(),
      _code('official_connect_result_unknown'),
    );
    await restored.close();
    await original.close();
    expect(api.entries, isEmpty);
  });
  test('已退出但仍登记的server可恢复关闭清理，退出本身不删除keyhome', () async {
    final original = await prepare();
    final old = api.entries.values.single;
    api.entries[old.serverId] = AdbServerInfo(
      serverId: old.serverId,
      leaseId: old.leaseId,
      launch: old.launch,
      phase: AdbServerPhase.exited,
      transportStateUnknown: false,
      pid: old.pid,
      exitCode: 0,
    );
    final restored = await restore(original);
    final home = Directory(
      original.nativeConfiguration!['keyDirectory'] as String,
    );
    await original.close();
    expect(await home.exists(), isTrue);
    await restored.close();
    expect(await home.exists(), isFalse);
  });
  test('客户端scope排空前不停止server，失败保留原server供重试', () async {
    final host = await prepare();
    await host.client.services.attachFileScope('owner');
    api.scopeCloseFailures = 1;
    await expectLater(host.close(), _code('file_cleanup_unconfirmed'));
    expect(api.closedLeases, isEmpty);
    expect(api.entries.values.single.phase, AdbServerPhase.ready);
    await host.close();
    expect(api.closedScopes, ['scope-owner', 'scope-owner']);
    expect(api.entries, isEmpty);
  });
  test('close等待实际scope回收，不用外层超时伪造完成', () async {
    final host = await prepare();
    await host.client.services.attachFileScope('owner');
    final release = Completer<void>();
    api.scopeCloseGate = release.future;
    var closed = false;
    final closing = host.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(api.closedLeases, isEmpty);
    release.complete();
    await closing;
    expect(api.entries, isEmpty);
  });
  test('原生server关闭失败保留同租约和keyhome重试且客户端准入保持关闭', () async {
    final host = await prepare();
    final home = Directory(host.nativeConfiguration!['keyDirectory'] as String);
    api.serverCloseFailures = 1;
    await expectLater(host.close(), _code('adb_server_cleanup_unconfirmed'));
    expect(await home.exists(), isTrue);
    await expectLater(host.client.connect('target'), _code('server_closed'));
    await host.close();
    expect(api.closedLeases, [
      host.nativeConfiguration!['leaseId'],
      host.nativeConfiguration!['leaseId'],
    ]);
    expect(await home.exists(), isFalse);
  });
  test('显式缺失identity不创建server或替代私钥', () async {
    await expectLater(
      prepare(identityPath: p.join(directory.path, 'missing.pem')),
      throwsA(isA<FileSystemException>()),
    );
    expect(api.entries, isEmpty);
  });
}
