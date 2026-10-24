import 'dart:async';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/owned_server_fake.dart';

const _first = AdbAdmissionScopeInfo(
  scopeKey: 'controlled-host',
  scopeId: 'first',
  accepting: true,
);
const _next = AdbAdmissionScopeInfo(
  scopeKey: 'controlled-host',
  scopeId: 'next',
  accepting: true,
);

class _ScopedServers extends OwnedServerFake
    implements NativeAdbScopedServerApi {
  String authority = _first.scopeId;
  final scopedCreates = <String>[], scopedClaims = <String>[];
  final deliveries = <String>{};
  final createEntered = Completer<void>(), confirmEntered = Completer<void>();
  Future<void>? createGate, confirmGate;
  int legacyCreates = 0, legacyClaims = 0;

  void _admit(String scope) {
    if (authority != scope) {
      throw const AdbException('adb_admission_scope_stale');
    }
  }

  @override
  Future<AdbServerInfo> createServer(AdbServerLaunchSpec launch) {
    legacyCreates++;
    return super.createServer(launch);
  }

  @override
  Future<AdbServerInfo> claimServer(String leaseId) {
    legacyClaims++;
    return super.claimServer(leaseId);
  }

  @override
  Future<AdbServerInfo> createScopedServer(
    AdbServerLaunchSpec launch,
    String scopeId,
  ) async {
    scopedCreates.add(scopeId);
    if (!createEntered.isCompleted) createEntered.complete();
    await createGate;
    // 模拟原生登记锁内核验；调用尚未受理时没有服务器可被后继漏掉。
    _admit(scopeId);
    return super.createServer(launch);
  }

  @override
  Future<AdbServerInfo> claimScopedServer(
    String leaseId,
    String scopeId,
  ) async {
    _admit(scopeId);
    scopedClaims.add(scopeId);
    final claimed = await super.claimServer(leaseId);
    _admit(scopeId);
    deliveries.remove(leaseId);
    return claimed;
  }

  @override
  Future<void> confirmScopedServer(String leaseId, String scopeId) async {
    if (!confirmEntered.isCompleted) confirmEntered.complete();
    await confirmGate;
    _admit(scopeId);
    if (!entries.values.any((entry) => entry.leaseId == leaseId)) {
      throw const AdbException('stale_server_lease');
    }
    deliveries.add(leaseId);
  }

  Future<void> takeOver() async {
    authority = _next.scopeId;
    for (final entry in entries.values.toList()) {
      if (!deliveries.contains(entry.leaseId)) {
        await closeServer(entry.leaseId);
      }
    }
  }
}

void main() {
  late Directory directory, binary;
  late _ScopedServers api;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scoped-adb-');
    binary = await Directory(p.join(directory.path, 'bin')).create();
    await File(p.join(binary.path, Platform.isWindows ? 'adb.exe' : 'adb'))
        .writeAsString('fixture');
    api = _ScopedServers();
  });
  tearDown(() async {
    await api.dispose();
    await directory.delete(recursive: true);
  });
  Future<AdbHost> prepare() => AdbHost.prepare(
    dataDirectory: directory,
    binaryDirectory: binary,
    bindings: api,
    admissionScope: _first,
  );

  test('scoped prepare 协议探测后确认交付，不走无scope登记', () async {
    var probed = false;
    api.onProbe = () async {
      probed = true;
      expect(api.deliveries, isEmpty);
    };
    final host = await prepare();
    expect(probed, isTrue);
    expect(api.scopedCreates, [_first.scopeId]);
    expect(api.legacyCreates, 0);
    expect(api.deliveries, [host.nativeConfiguration!['leaseId']]);
    await host.close();
  });

  test('旧prepare尚未登记就接管，迟到创建拒绝且不留下keyhome', () async {
    final gate = Completer<void>();
    api.createGate = gate.future;
    final preparing = prepare();
    final rejected = expectLater(
      preparing,
      throwsA(
        isA<AdbException>().having(
          (error) => error.code,
          'code',
          'adb_admission_scope_stale',
        ),
      ),
    );
    await api.createEntered.future;
    await api.takeOver();
    gate.complete();
    await rejected;
    expect(api.entries, isEmpty);
    expect(api.listeners, isEmpty);
    expect(
      await Directory(p.join(directory.path, 'official_adb')).list().toList(),
      isEmpty,
    );
  });

  test('原生已ready但交付未确认时接管，旧prepare不能返回可用宿主', () async {
    final gate = Completer<void>();
    api.confirmGate = gate.future;
    final preparing = prepare();
    final rejected = expectLater(preparing, throwsA(isA<AdbException>()));
    await api.confirmEntered.future;
    expect(api.entries.values.single.phase, AdbServerPhase.ready);
    await api.takeOver();
    gate.complete();
    await rejected;
    expect(api.entries, isEmpty);
    expect(api.listeners, isEmpty);
    expect(api.deliveries, isEmpty);
  });

  test('已确认server接管后精确scoped restore，旧close不撤销新lease', () async {
    final original = await prepare();
    final before = original.nativeConfiguration!;
    await api.takeOver();
    expect(api.entries, hasLength(1));
    final restored = await AdbHost.restore(
      dataDirectory: directory,
      binaryDirectory: binary,
      bindings: api,
      admissionScope: _next,
      leaseId: before['leaseId'] as String,
    );
    final after = restored.nativeConfiguration!;
    expect(api.scopedClaims, [_next.scopeId]);
    expect(api.legacyClaims, 0);
    expect(after['serverId'], before['serverId']);
    expect(after['leaseId'], isNot(before['leaseId']));
    expect(api.deliveries, [after['leaseId']]);
    await original.close();
    expect(api.entries.values.single.leaseId, after['leaseId']);
    expect(await Directory(after['keyDirectory'] as String).exists(), isTrue);
    await restored.close();
    expect(api.entries, isEmpty);
  });
}
